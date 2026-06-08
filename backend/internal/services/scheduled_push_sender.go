package services

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/repositories"
)

// ScheduledPushSender fires admin "countdown" push notifications when their
// send_at passes (mig 0048). Mirrors ScheduledPublisher's loop. Lives
// server-side so a scheduled push survives the dashboard being closed.
//
// Cadence: 15s — tight enough that a "5 second" countdown feels accurate
// without hammering the DB. The ClaimDue query only scans pending+due rows
// (partial-ish index) and atomically flips them to 'sending' so two
// instances never double-send.
type ScheduledPushSender struct {
	repo   *repositories.ScheduledPushRepository
	tokens *repositories.PushTokenRepository
	fcm    *FCMSender // nullable — sender stays idle when FCM isn't configured
}

func NewScheduledPushSender(
	repo *repositories.ScheduledPushRepository,
	tokens *repositories.PushTokenRepository,
	fcm *FCMSender,
) *ScheduledPushSender {
	return &ScheduledPushSender{repo: repo, tokens: tokens, fcm: fcm}
}

func (s *ScheduledPushSender) Start(ctx context.Context) {
	if s.fcm == nil || s.repo == nil {
		log.Printf("[scheduled_push] sender disabled (fcm=%v repo=%v)",
			s.fcm != nil, s.repo != nil)
		return
	}
	// Re-queue anything a previous run left mid-flight in 'sending'.
	if err := s.repo.RequeueStuck(); err != nil {
		log.Printf("[scheduled_push] requeue stuck: %v", err)
	}
	log.Printf("[scheduled_push] sender started")
	go s.run(ctx)
}

func (s *ScheduledPushSender) run(ctx context.Context) {
	tick := time.NewTicker(15 * time.Second)
	defer tick.Stop()
	s.tick(ctx)
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			s.tick(ctx)
		}
	}
}

func (s *ScheduledPushSender) tick(ctx context.Context) {
	due, err := s.repo.ClaimDue()
	if err != nil {
		log.Printf("[scheduled_push] claim: %v", err)
		return
	}
	for _, p := range due {
		s.send(ctx, p)
	}
}

func (s *ScheduledPushSender) send(ctx context.Context, p repositories.ScheduledPush) {
	var userID int64
	if p.UserID != nil {
		userID = *p.UserID
	}
	var role, cid string
	if p.Role != nil {
		role = *p.Role
	}
	if p.CommunityID != nil {
		cid = *p.CommunityID
	}
	recipients, err := s.tokens.ResolveTokensWithLocale(p.Target, userID, role, cid)
	if err != nil {
		s.finishFailed(p, err.Error())
		return
	}
	if len(recipients) == 0 {
		s.finishSent(p, 0, 0, 0) // nothing to send, but it "ran"
		return
	}
	sctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	// Each recipient gets the copy in their own language (Arabic users the
	// Arabic copy, everyone else English; Arabic falls back to English when
	// the scheduled row has no Arabic text).
	res, sendErr := s.fcm.SendLocalized(
		sctx, recipients, p.Title, p.Body, p.TitleAr, p.BodyAr, p.Data,
	)
	for _, t := range res.InvalidTokens {
		_ = s.tokens.DeleteToken(t)
	}
	if sendErr != nil {
		s.finishFailed(p, sendErr.Error())
		return
	}
	s.finishSent(p, res.SuccessCount, res.FailureCount, len(recipients))
	log.Printf("[scheduled_push] fired #%d → %d ok / %d fail",
		p.ID, res.SuccessCount, res.FailureCount)
}

func isRecurring(p repositories.ScheduledPush) bool {
	return p.RepeatKind != "" && p.RepeatKind != "none"
}

// finishSent closes out a successful fire: one-shot rows become 'sent';
// recurring rows record the result and re-arm to the next occurrence.
func (s *ScheduledPushSender) finishSent(p repositories.ScheduledPush, success, failure, recipients int) {
	if isRecurring(p) {
		next := nextRun(p.RepeatKind, p.RepeatDays, p.SendAt, time.Now())
		_ = s.repo.RearmRecurring(p.ID, success, failure, recipients, next)
		log.Printf("[scheduled_push] recurring #%d fired → next at %s", p.ID, next.Format(time.RFC3339))
		return
	}
	_ = s.repo.MarkSent(p.ID, success, failure, recipients)
}

// finishFailed: a one-shot failure marks 'failed'; a recurring failure keeps
// the schedule alive and just retries on the next occurrence.
func (s *ScheduledPushSender) finishFailed(p repositories.ScheduledPush, msg string) {
	if isRecurring(p) {
		next := nextRun(p.RepeatKind, p.RepeatDays, p.SendAt, time.Now())
		_ = s.repo.RearmRecurring(p.ID, 0, 0, 0, next)
		log.Printf("[scheduled_push] recurring #%d error (will retry %s): %s",
			p.ID, next.Format(time.RFC3339), msg)
		return
	}
	_ = s.repo.MarkFailed(p.ID, msg)
}

// nextRun advances a recurrence one step past `base`, then skips any
// occurrences already in the past (e.g. the server was asleep) so a recurring
// push never fires a burst to catch up. Clock time-of-day is preserved because
// AddDate keeps the hour/minute/second.
func nextRun(kind string, days []int64, base, now time.Time) time.Time {
	advance := func(t time.Time) time.Time {
		switch kind {
		case "minutely":
			return t.Add(time.Minute)
		case "hourly":
			return t.Add(time.Hour)
		case "daily":
			return t.AddDate(0, 0, 1)
		case "weekly":
			if len(days) == 0 {
				return t.AddDate(0, 0, 7)
			}
			for i := 1; i <= 7; i++ {
				cand := t.AddDate(0, 0, i)
				for _, d := range days {
					if int(cand.Weekday()) == int(d) {
						return cand
					}
				}
			}
			return t.AddDate(0, 0, 7)
		case "monthly":
			return t.AddDate(0, 1, 0)
		default:
			return t.AddDate(0, 0, 1)
		}
	}
	next := advance(base)
	for guard := 0; !next.After(now) && guard < 100000; guard++ {
		next = advance(next)
	}
	return next
}

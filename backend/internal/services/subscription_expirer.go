package services

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// SubscriptionExpirer is a tiny background loop that periodically
// flips active expert subscriptions whose `expires_at` has passed
// over to status='expired'. For each row it transitions, a
// `subscription_expired` realtime event is fanned out to the
// affected user's WS channel so the mobile app can drop subscriber-
// only content gating immediately and surface a "your subscription
// has expired" snackbar.
//
// Cadence: 60 seconds. The loop is cheap — a single UPDATE …
// RETURNING on a tiny indexed slice of rows where status='active'
// AND expires_at < NOW(). No schema changes needed; this just
// turns the existing `expires_at` column into a real lifecycle
// signal instead of a passive timestamp.
//
// Robustness:
//   - The SQL flips status atomically with the read of the
//     summary tuples (RETURNING), so we can't double-broadcast a
//     row even if two expirer instances ran at once.
//   - A nil hub is tolerated — the DB transitions still happen,
//     just no realtime events.
//   - Errors are logged at WARN, never panic'd. A bad query (e.g.
//     transient DB connectivity drop) gets retried on the next
//     tick.
type SubscriptionExpirer struct {
	subs       *repositories.ExpertSubscriptionRepository
	experts    *repositories.SocialRepository
	hub        *realtime.Hub
	userNotifs *repositories.UserNotificationsRepository
	notifier   *Notifier // optional, set via SetNotifier
}

// SetNotifier wires the localized push sender. Best-effort: when nil the
// expiry still writes the inbox row, it just doesn't push a device alert.
func (e *SubscriptionExpirer) SetNotifier(n *Notifier) {
	e.notifier = n
}

// NewSubscriptionExpirer constructs an idle expirer. Call Start to
// kick off the background loop. [userNotifs] is optional — when
// supplied, every flipped row also lays down a `subscription_expired`
// row in the unified inbox so the user finds it in history later.
func NewSubscriptionExpirer(
	subs *repositories.ExpertSubscriptionRepository,
	experts *repositories.SocialRepository,
	hub *realtime.Hub,
	userNotifs *repositories.UserNotificationsRepository,
) *SubscriptionExpirer {
	return &SubscriptionExpirer{
		subs:       subs,
		experts:    experts,
		hub:        hub,
		userNotifs: userNotifs,
	}
}

// Start spins up a goroutine that ticks every minute. Cancel the
// passed context to stop the loop on shutdown.
func (e *SubscriptionExpirer) Start(ctx context.Context) {
	go e.run(ctx)
}

func (e *SubscriptionExpirer) run(ctx context.Context) {
	// Fire once immediately so a freshly-restarted server doesn't
	// wait a full minute to clear out anything that expired while
	// it was down.
	e.tick()
	ticker := time.NewTicker(60 * time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			e.tick()
		}
	}
}

func (e *SubscriptionExpirer) tick() {
	if e.subs == nil {
		return
	}
	expired, err := e.subs.ExpireDue()
	if err != nil {
		log.Printf("subscription expirer: ExpireDue failed: %v", err)
		return
	}
	if len(expired) == 0 {
		return
	}
	if e.hub == nil {
		// DB transitioned but no realtime fanout possible — that's
		// still a correct state, the user just won't see the
		// snackbar until next refresh.
		return
	}
	// Look up expert names in a small per-row hop. The expirer
	// doesn't run hot, so per-call lookups are fine — typical tick
	// flips 0–few rows, not hundreds.
	for _, s := range expired {
		var expertName string
		if e.experts != nil {
			if exp, lookupErr := e.experts.GetExpert(s.ExpertID); lookupErr == nil &&
				exp != nil {
				expertName = exp.Name
			}
		}
		e.hub.PublishJSON(
			realtime.ChannelUser(s.UserID),
			"subscription_expired",
			gin.H{
				"subscriptionId": s.ID,
				"expertId":       s.ExpertID,
				"expertName":     expertName,
			},
		)
		// Persistent inbox row — the realtime snackbar disappears
		// after a few seconds, but the user can scroll back through
		// inbox history to find this anytime.
		if e.userNotifs != nil {
			_ = e.userNotifs.Insert(
				s.UserID,
				"subscription_expired",
				nil,
				expertName,
				"", // body localized on-device by kind
				nil,
			)
		}
		if e.notifier != nil {
			e.notifier.PushToUser(
				context.Background(),
				s.UserID,
				"subscription_expired",
				nil,
			)
		}
	}
}

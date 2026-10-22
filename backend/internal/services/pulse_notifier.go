package services

import (
	"context"
	"log"
	"strconv"
	"sync"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

// =============================================================================
// pulse_notifier.go — push notifications for UNMU Pulse (spec §17).
//
//	new item goes live      -> everyone who wants "new Pulse"      (pulse_new)
//	several go live at once -> one combined push, not four        (pulse_new_many)
//	live item updated       -> only people who SAVED it            (pulse_updated)
//	live item corrected     -> only people who SAVED it            (pulse_corrected)
//
// Each user gets the text in their own language (Notifier renders by
// users.locale) and the exact per-event switch is checked by the Notifier
// (categoryEnabled), so a user who turned a switch off never receives it.
//
// Sending is best-effort and runs in the background: publishing has already
// been committed, so a push problem can never undo or block it.
// =============================================================================

const (
	pulsePushWorkers = 8                // concurrent sends per fan-out
	pulsePushTimeout = 10 * time.Minute // upper bound for one fan-out
)

// pulsePusher is the part of Notifier this service needs (so tests can fake it).
type pulsePusher interface {
	PushToUser(ctx context.Context, userID int64, notifType string, params map[string]string)
}

// pulseRecipientSource finds who should be notified.
type pulseRecipientSource interface {
	NewItemRecipients(ctx context.Context) ([]int64, error)
	SaverRecipients(ctx context.Context, itemID int64) ([]int64, error)
}

// PulseNotifier turns Pulse publish / change events into push notifications.
type PulseNotifier struct {
	push       pulsePusher
	recipients pulseRecipientSource
}

// NewPulseNotifier wires the notifier. A nil Notifier (push not configured,
// e.g. local dev without Firebase) makes every send a harmless no-op, because
// Notifier.PushToUser returns immediately on a nil receiver.
func NewPulseNotifier(push *Notifier, recipients *repositories.PulseAdminRepository) *PulseNotifier {
	return &PulseNotifier{push: push, recipients: recipients}
}

// OnPublished is the scheduler's callback: items that just went live.
func (p *PulseNotifier) OnPublished(_ context.Context, items []models.PulseAdminItem) {
	p.background(func(ctx context.Context) { p.sendPublished(ctx, items) })
}

// OnChange is the CMS handler's hook. event is "published", "updated" or
// "corrected".
func (p *PulseNotifier) OnChange(_ context.Context, event string, it models.PulseAdminItem) {
	switch event {
	case "published":
		p.background(func(ctx context.Context) { p.sendPublished(ctx, []models.PulseAdminItem{it}) })
	case models.PulseChangeUpdated, models.PulseChangeCorrected:
		p.background(func(ctx context.Context) { p.sendChanged(ctx, event, it) })
	}
}

// background runs fn detached from the request (its context ends when the
// response is sent) with its own timeout. Panics are contained so a bug here
// can never take the server down.
func (p *PulseNotifier) background(fn func(ctx context.Context)) {
	if p == nil {
		return
	}
	go func() {
		defer func() {
			if r := recover(); r != nil {
				log.Printf("[pulse_notifier] recovered: %v", r)
			}
		}()
		ctx, cancel := context.WithTimeout(context.Background(), pulsePushTimeout)
		defer cancel()
		fn(ctx)
	}()
}

// pulseItemParams are the template values and the deep-link payload.
func pulseItemParams(it models.PulseAdminItem) map[string]string {
	return map[string]string{
		"itemId":  strconv.FormatInt(it.ID, 10),
		"date":    it.PulseDate,
		"slot":    it.Slot,
		"titleEn": it.TitleEn,
		"titleAr": it.TitleAr,
	}
}

func (p *PulseNotifier) sendPublished(ctx context.Context, items []models.PulseAdminItem) {
	if len(items) == 0 {
		return
	}
	ids, err := p.recipients.NewItemRecipients(ctx)
	if err != nil {
		log.Printf("[pulse_notifier] recipients for new items: %v", err)
		return
	}
	if len(items) == 1 {
		p.fanOut(ctx, ids, "pulse_new", pulseItemParams(items[0]))
		return
	}
	// Several items at the same moment: one push that opens today's Pulse.
	p.fanOut(ctx, ids, "pulse_new_many", map[string]string{
		"count": strconv.Itoa(len(items)),
		"date":  items[0].PulseDate,
	})
}

func (p *PulseNotifier) sendChanged(ctx context.Context, event string, it models.PulseAdminItem) {
	notifType := "pulse_updated"
	if event == models.PulseChangeCorrected {
		notifType = "pulse_corrected"
	}
	ids, err := p.recipients.SaverRecipients(ctx, it.ID)
	if err != nil {
		log.Printf("[pulse_notifier] recipients for %s item %d: %v", event, it.ID, err)
		return
	}
	p.fanOut(ctx, ids, notifType, pulseItemParams(it))
}

// fanOut sends the same notification to many users with bounded concurrency.
func (p *PulseNotifier) fanOut(ctx context.Context, userIDs []int64, notifType string, params map[string]string) {
	if len(userIDs) == 0 {
		return
	}
	work := make(chan int64)
	var wg sync.WaitGroup
	for i := 0; i < pulsePushWorkers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for uid := range work {
				p.push.PushToUser(ctx, uid, notifType, params)
			}
		}()
	}
	for _, uid := range userIDs {
		select {
		case work <- uid:
		case <-ctx.Done():
			close(work)
			wg.Wait()
			return
		}
	}
	close(work)
	wg.Wait()
	log.Printf("[pulse_notifier] sent %s to %d user(s)", notifType, len(userIDs))
}

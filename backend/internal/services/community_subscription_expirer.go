package services

import (
	"context"
	"log"
	"time"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// CommunitySubscriptionExpirer flips paid-community subscriptions
// past their expires_at to status=expired AND removes the matching
// community_members row so the user loses access immediately.
//
// Mig 0022 / step-23. Mirrors SubscriptionExpirer (expert subs) and
// PollCloser (chat polls) so the platform's background tick story
// stays consistent.
//
// Cadence: 60 seconds. Cheap query thanks to the
// `idx_comm_subs_expiring` partial index (only scans active rows
// with a non-null expires_at).
type CommunitySubscriptionExpirer struct {
	subs       *repositories.CommunitySubscriptionsRepository
	hub        *realtime.Hub
	userNotifs *repositories.UserNotificationsRepository // optional
	notifier   *Notifier                                 // optional, set via SetNotifier
}

// SetNotifier wires the localized push sender. Best-effort: when nil the
// expiry still writes the inbox row, it just doesn't push a device alert.
func (e *CommunitySubscriptionExpirer) SetNotifier(n *Notifier) {
	e.notifier = n
}

func NewCommunitySubscriptionExpirer(
	subs *repositories.CommunitySubscriptionsRepository,
	hub *realtime.Hub,
	userNotifs *repositories.UserNotificationsRepository,
) *CommunitySubscriptionExpirer {
	return &CommunitySubscriptionExpirer{
		subs: subs, hub: hub, userNotifs: userNotifs,
	}
}

// Start launches the background goroutine. Cancelling [ctx] stops it.
func (e *CommunitySubscriptionExpirer) Start(ctx context.Context) {
	go e.run(ctx)
}

func (e *CommunitySubscriptionExpirer) run(ctx context.Context) {
	tick := time.NewTicker(60 * time.Second)
	defer tick.Stop()
	// Run once on startup so any subs expired during downtime get
	// promoted immediately rather than waiting a full minute.
	e.tick()
	for {
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
			e.tick()
		}
	}
}

func (e *CommunitySubscriptionExpirer) tick() {
	expired, err := e.subs.PromoteExpired()
	if err != nil {
		log.Printf("[community_sub_expirer] promote failed: %v", err)
		return
	}
	if len(expired) == 0 {
		return
	}
	log.Printf("[community_sub_expirer] expired %d subscription(s)", len(expired))
	for _, x := range expired {
		payload := gin.H{
			"id":          x.SubscriptionID,
			"userId":      x.UserID,
			"communityId": x.CommunityID,
		}
		if e.hub != nil {
			// User channel so the mobile drops gating immediately.
			e.hub.PublishJSON(
				realtime.ChannelUser(x.UserID),
				"community_subscription_expired",
				payload,
			)
			// Step C5 — admin channel so the admin queue's expired tab
			// updates without a manual refresh.
			e.hub.PublishJSON(
				realtime.ChannelAdmin,
				"community_subscription_expired",
				payload,
			)
			// Community channel so any open viewer of the member list
			// updates their counts.
			e.hub.PublishJSON(
				realtime.ChannelCommunity(x.CommunityID),
				"community_member_changed",
				gin.H{"communityId": x.CommunityID},
			)
		}
		// Step C6 — persistent inbox row. Best-effort. Empty snippet so
		// the app renders a localized default body.
		if e.userNotifs != nil {
			_ = e.userNotifs.Insert(
				x.UserID,
				"community_subscription_expired",
				nil,
				"",
				"",
				nil,
			)
		}
		if e.notifier != nil {
			e.notifier.PushToUser(
				context.Background(),
				x.UserID,
				"community_subscription_expired",
				nil,
			)
		}
	}
}

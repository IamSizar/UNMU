package realtime

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"
	"time"

	"github.com/lib/pq"
)

// PgListener is a goroutine that holds an open Postgres LISTEN connection
// and forwards NOTIFY payloads into the in-process Hub.
//
// Postgres channels we subscribe to (created by migration 0004):
//
//	expert_application_events  — { type, applicationId, userId, status, ... }
//	user_role_events           — { userId, oldRole, newRole, expertId }
//	expert_post_events         — { type, postId, expertId, visibility }
//
// On each NOTIFY, the listener parses the payload and republishes onto the
// matching in-process channel(s) via Hub.PublishJSON.
type PgListener struct {
	hub *Hub
	dsn string
}

func NewPgListener(hub *Hub, dsn string) *PgListener {
	return &PgListener{hub: hub, dsn: dsn}
}

// Start spawns the listener goroutine. Cancel ctx to stop it. Returns
// immediately; reconnects on its own if the connection drops.
func (l *PgListener) Start(ctx context.Context) {
	go l.run(ctx)
}

func (l *PgListener) run(ctx context.Context) {
	reportProblem := func(et pq.ListenerEventType, err error) {
		if err != nil {
			log.Printf("[realtime] pq listener: %v", err)
		}
	}

	listener := pq.NewListener(l.dsn, 2*time.Second, time.Minute, reportProblem)
	defer listener.Close()

	channels := []string{
		"expert_application_events",
		"user_role_events",
		"expert_post_events",
		"audit_log_events",
		"subscription_events",
		"community_subscription_events",
		"post_like_events",
		"post_comment_events",
		"notification_events",
		// Support chat (mig 0029) — user ↔ admin direct messages.
		// Listener fans messages to the user's WS channel + admin channel.
		"support_message_events",
		// Support thread metadata changes (pin / unpin, mig 0030).
		"support_thread_events",
		// Community co-ownership (mig 0032). Invitation lifecycle +
		// ownership table changes. Direct-routed channels (each event
		// has its own channel) — the dispatch is just a passthrough.
		"community_invitation_sent",
		"community_invitation_accepted",
		"community_invitation_rejected",
		"community_invitation_cancelled",
		"community_co_owner_added",
		"community_co_owner_removed",
	}
	for _, ch := range channels {
		if err := listener.Listen(ch); err != nil {
			log.Printf("[realtime] LISTEN %s failed: %v", ch, err)
			return
		}
	}
	log.Printf("[realtime] listening on %d Postgres channels", len(channels))

	for {
		select {
		case <-ctx.Done():
			return
		case n := <-listener.Notify:
			if n == nil {
				// Reconnect signal — listener handles it; we just continue.
				continue
			}
			l.dispatch(n.Channel, n.Extra)
		case <-time.After(60 * time.Second):
			// Periodic ping — pq.Listener does this internally already, but
			// being explicit costs nothing and gives us a clear log line if
			// the connection silently dies.
			_ = listener.Ping()
		}
	}
}

// dispatch parses a NOTIFY payload and forwards it to the Hub.
func (l *PgListener) dispatch(pgChannel, payload string) {
	var raw map[string]any
	if err := json.Unmarshal([]byte(payload), &raw); err != nil {
		log.Printf("[realtime] bad payload on %s: %v", pgChannel, err)
		return
	}

	switch pgChannel {
	case "expert_application_events":
		l.dispatchApplication(raw)
	case "user_role_events":
		l.dispatchRoleChange(raw)
	case "expert_post_events":
		l.dispatchPost(raw)
	case "audit_log_events":
		// Every audit log row goes to all connected admins as an
		// `audit_log_created` event. The admin dashboard's AuditLog page
		// listens for this and prepends the row.
		l.hub.PublishJSON(ChannelAdmin, "audit_log_created", raw)
	case "subscription_events":
		l.dispatchSubscription(raw)
	case "community_subscription_events":
		l.dispatchCommunitySubscription(raw)
	case "post_like_events":
		l.dispatchPostLike(raw)
	case "post_comment_events":
		l.dispatchPostComment(raw)
	case "support_message_events":
		l.dispatchSupportMessage(raw)
	case "support_thread_events":
		l.dispatchSupportThread(raw)
	case "notification_events":
		l.dispatchNotification(raw)
	// ── Community co-ownership (mig 0032) ────────────────────────
	// Direct-routed: same channel name → same WS event name. The
	// invitee gets the "sent" event on their personal channel; the
	// inviter gets "accepted/rejected" on theirs; co-owner table
	// changes broadcast to admins (the network page) + the community
	// channel so subscribers can see the ownership shift live.
	case "community_invitation_sent":
		if uid, ok := numI64(raw["invitedUserId"]); ok {
			l.hub.PublishJSON(ChannelUser(uid), "community_invitation_received", raw)
		}
		l.hub.PublishJSON(ChannelAdmin, "community_invitation_sent", raw)
	case "community_invitation_accepted":
		if uid, ok := numI64(raw["invitedBy"]); ok {
			l.hub.PublishJSON(ChannelUser(uid), "community_invitation_accepted", raw)
		}
		l.hub.PublishJSON(ChannelAdmin, "community_invitation_accepted", raw)
	case "community_invitation_rejected":
		if uid, ok := numI64(raw["invitedBy"]); ok {
			l.hub.PublishJSON(ChannelUser(uid), "community_invitation_rejected", raw)
		}
		l.hub.PublishJSON(ChannelAdmin, "community_invitation_rejected", raw)
	case "community_invitation_cancelled":
		if uid, ok := numI64(raw["invitedUserId"]); ok {
			l.hub.PublishJSON(ChannelUser(uid), "community_invitation_cancelled", raw)
		}
		l.hub.PublishJSON(ChannelAdmin, "community_invitation_cancelled", raw)
	case "community_co_owner_added":
		l.hub.PublishJSON(ChannelAdmin, "community_co_owner_added", raw)
	case "community_co_owner_removed":
		l.hub.PublishJSON(ChannelAdmin, "community_co_owner_removed", raw)
	default:
		log.Printf("[realtime] unknown channel %q", pgChannel)
	}
}

// numI64 — coerce a JSON-decoded numeric value into int64. JSON
// numbers come back as float64 from encoding/json by default.
func numI64(v any) (int64, bool) {
	switch x := v.(type) {
	case float64:
		return int64(x), true
	case int64:
		return x, true
	case int:
		return int64(x), true
	}
	return 0, false
}

// dispatchPostLike fans out like / unlike events to the expert's channel
// (so all subscribed viewers' cards update count) and to admins.
func (l *PgListener) dispatchPostLike(p map[string]any) {
	evType, _ := p["type"].(string) // "liked" | "unliked"
	expertID, _ := p["expertId"].(string)
	if evType == "" {
		return
	}
	wireType := "post_" + evType
	if expertID != "" {
		l.hub.PublishJSON(ChannelExpert(expertID), wireType, p)
	}
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
}

// dispatchPostComment fans out comment create / delete to the expert's
// channel and admins.
func (l *PgListener) dispatchPostComment(p map[string]any) {
	evType, _ := p["type"].(string) // "created" | "deleted"
	expertID, _ := p["expertId"].(string)
	if evType == "" {
		return
	}
	wireType := "post_comment_" + evType
	if expertID != "" {
		l.hub.PublishJSON(ChannelExpert(expertID), wireType, p)
	}
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
}

// dispatchNotification — recipient-only push (the user the notification is
// addressed to). Bell + count update instantly.
func (l *PgListener) dispatchNotification(p map[string]any) {
	userID := toInt64(p["userId"])
	if userID == 0 {
		return
	}
	l.hub.PublishJSON(ChannelUser(userID), "notification_created", p)
}

// dispatchSubscription routes subscription lifecycle events to the right
// channels. The user (subscriber) gets state updates so the Flutter expert
// profile + My Subs screen react live; admins get every event so the
// Subscriptions page + sidebar pending count update without polling.
func (l *PgListener) dispatchSubscription(p map[string]any) {
	evType, _ := p["type"].(string)
	userID := toInt64(p["userId"])
	if evType == "" {
		return
	}
	wireType := "subscription_" + evType
	if userID > 0 {
		l.hub.PublishJSON(ChannelUser(userID), wireType, p)
	}
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
}

// dispatchCommunitySubscription — paid community membership events.
// Mirrors dispatchSubscription but also fans out to the community channel
// so any open client viewing the community detail page sees member-count
// changes live (the AdminAccept handler also broadcasts member_changed
// directly; this gives a PG-trigger fallback for multi-replica setups).
func (l *PgListener) dispatchCommunitySubscription(p map[string]any) {
	evType, _ := p["type"].(string)
	userID := toInt64(p["userId"])
	communityID, _ := p["communityId"].(string)
	if evType == "" {
		return
	}
	wireType := "community_subscription_" + evType
	if userID > 0 {
		l.hub.PublishJSON(ChannelUser(userID), wireType, p)
	}
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
	if communityID != "" {
		l.hub.PublishJSON(ChannelCommunity(communityID), wireType, p)
	}
}

// dispatchSupportMessage — built-in support chat (mig 0029). Fan a
// message to:
//   * the THREAD OWNER's user channel  → so the user's chat screen
//     gets the live message, and the settings bell can blink for
//     admin replies on other devices
//   * the ADMIN channel                → so the admin dashboard's
//     toaster + sidebar badge + inbox refresh instantly
//
// `threadUserId` is the thread owner (the user whose support thread
// this is), distinct from `senderUserId` (could be the user themselves
// or an admin replying). We always route on `threadUserId` so admin
// replies still reach the right user channel.
//
// Mig 0030 added three event types alongside the original `sent`:
// `edited`, `deleted`. Same routing logic applies — clients update
// their in-memory bubble by message id.
func (l *PgListener) dispatchSupportMessage(p map[string]any) {
	evType, _ := p["type"].(string) // 'sent' | 'edited' | 'deleted'
	if evType == "" {
		return
	}
	wireType := "support_message_" + evType
	if threadUserID := toInt64(p["threadUserId"]); threadUserID > 0 {
		l.hub.PublishJSON(ChannelUser(threadUserID), wireType, p)
	}
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
}

// dispatchSupportThread — pin / unpin events from mig 0030. Single
// `support_thread_events` channel covers both via the `type` field.
// Routed identically to messages — user + admin.
func (l *PgListener) dispatchSupportThread(p map[string]any) {
	evType, _ := p["type"].(string) // 'pinned' | 'unpinned'
	if evType == "" {
		return
	}
	wireType := "support_thread_" + evType
	if threadUserID := toInt64(p["threadUserId"]); threadUserID > 0 {
		l.hub.PublishJSON(ChannelUser(threadUserID), wireType, p)
	}
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
}

func (l *PgListener) dispatchApplication(p map[string]any) {
	evType, _ := p["type"].(string) // submitted | approved | rejected
	userID := toInt64(p["userId"])
	if evType == "" {
		return
	}

	switch evType {
	case "submitted":
		// New pending application — admins want to see it.
		l.hub.PublishJSON(ChannelAdmin, "application_submitted", p)
	case "approved":
		l.hub.PublishJSON(ChannelUser(userID), "application_approved", p)
		l.hub.PublishJSON(ChannelAdmin, "application_resolved", p)
	case "rejected":
		l.hub.PublishJSON(ChannelUser(userID), "application_rejected", p)
		l.hub.PublishJSON(ChannelAdmin, "application_resolved", p)
	}
}

func (l *PgListener) dispatchRoleChange(p map[string]any) {
	userID := toInt64(p["userId"])
	if userID == 0 {
		return
	}
	// The user themselves needs to refresh their session.
	l.hub.PublishJSON(ChannelUser(userID), "user_role_changed", p)
	// Admins also want to see role changes — drives the Users page table
	// auto-refresh + audit log feed.
	l.hub.PublishJSON(ChannelAdmin, "user_role_changed", p)
}

func (l *PgListener) dispatchPost(p map[string]any) {
	expertID, _ := p["expertId"].(string)
	evType, _ := p["type"].(string)
	// Step-5: payload type tells us whether this was create / edit / hide /
	// delete. Wire types are stable so old clients listening only for
	// `post_published` keep working when a new post is created.
	wireType := "post_published"
	switch evType {
	case "edited":
		wireType = "post_edited"
	case "hidden":
		wireType = "post_hidden"
	case "deleted":
		wireType = "post_deleted"
	}
	if expertID != "" {
		l.hub.PublishJSON(ChannelExpert(expertID), wireType, p)
	}
	// Admins also want to see content lifecycle events for moderation.
	l.hub.PublishJSON(ChannelAdmin, wireType, p)
}

// toInt64 handles the reality that JSON numbers come through as float64.
func toInt64(v any) int64 {
	switch x := v.(type) {
	case float64:
		return int64(x)
	case int64:
		return x
	case int:
		return int64(x)
	case json.Number:
		n, _ := x.Int64()
		return n
	}
	return 0
}

// Compile-time check that pq is imported even on builds where the listener
// isn't directly referenced — avoids "imported and not used" if someone
// removes the listener from main.go later.
var _ = sql.ErrNoRows

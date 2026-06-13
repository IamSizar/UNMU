package services

import (
	"context"
	"log"
	"strconv"
	"strings"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

// SocialPushNotifier sends an FCM push to the RECIPIENT of a social
// notification (someone liked / commented on your post, a subscription
// changed, etc.).
//
// It's driven off the realtime `notification_events` Postgres channel, so it
// automatically covers every notification type the DB triggers create —
// when a new user_notifications row is inserted, the recipient's devices get
// a push (e.g. "Sizar liked your post") even when the app is closed.
//
// Best-effort: every failure is logged, never propagated. No-op when fcm is
// nil (FCM disabled because no Firebase service account is configured).
type SocialPushNotifier struct {
	notifs *repositories.UserNotificationsRepository
	tokens *repositories.PushTokenRepository
	prefs  *repositories.NotificationPrefsRepository
	fcm    *FCMSender
}

func NewSocialPushNotifier(
	notifs *repositories.UserNotificationsRepository,
	tokens *repositories.PushTokenRepository,
	prefs *repositories.NotificationPrefsRepository,
	fcm *FCMSender,
) *SocialPushNotifier {
	return &SocialPushNotifier{notifs: notifs, tokens: tokens, prefs: prefs, fcm: fcm}
}

// Notify loads notification [notificationID] and pushes it to [userID]'s
// devices. Safe to call from a goroutine in the realtime listener.
func (s *SocialPushNotifier) Notify(notificationID, userID int64) {
	if s == nil || s.fcm == nil || userID == 0 || notificationID == 0 {
		return
	}
	n, err := s.notifs.Get(notificationID)
	if err != nil || n == nil {
		return
	}

	// Respect the recipient's notification preferences.
	if s.prefs != nil {
		if p, perr := s.prefs.GetOrDefault(userID); perr == nil && p != nil {
			if !p.PushEnabled {
				return
			}
			switch n.Type {
			case "post_liked":
				if !p.LikesEnabled {
					return
				}
			case "post_commented":
				if !p.CommentsEnabled {
					return
				}
			case "subscription_active", "subscription_rejected", "subscription_expired":
				if !p.SubscriptionsEnabled {
					return
				}
			}
		}
	}

	tokens, err := s.tokens.ListForUser(userID)
	if err != nil || len(tokens) == 0 {
		return
	}

	title, body := socialPushText(n)
	data := map[string]string{
		"kind":           "social",
		"type":           n.Type,
		"notificationId": strconv.FormatInt(n.ID, 10),
	}
	if n.PostID != nil {
		data["post_id"] = strconv.FormatInt(*n.PostID, 10)
	}

	if _, err := s.fcm.SendToTokens(context.Background(), tokens, title, body, data); err != nil {
		log.Printf("[social-push] send failed (user=%d type=%s): %v", userID, n.Type, err)
	}
}

// socialPushText builds the (title, body) for a notification. Title = the
// actor's name; body = the human action. Falls back to a generic line for
// notification types we don't have bespoke copy for.
func socialPushText(n *models.UserNotification) (string, string) {
	actor := "Someone"
	if n.ActorName != nil && strings.TrimSpace(*n.ActorName) != "" {
		actor = strings.TrimSpace(*n.ActorName)
	}
	switch n.Type {
	case "post_liked":
		return actor, "liked your post"
	case "post_commented":
		if n.BodySnippet != nil && strings.TrimSpace(*n.BodySnippet) != "" {
			return actor, "commented: " + truncateRunes(strings.TrimSpace(*n.BodySnippet), 120)
		}
		return actor, "commented on your post"
	default:
		if n.BodySnippet != nil && strings.TrimSpace(*n.BodySnippet) != "" {
			return "UNMU", strings.TrimSpace(*n.BodySnippet)
		}
		return "UNMU", "You have a new notification"
	}
}

// truncateRunes shortens a string to at most max runes (not bytes), appending
// an ellipsis — keeps multi-byte (Arabic) text from being cut mid-character.
func truncateRunes(s string, max int) string {
	r := []rune(s)
	if len(r) <= max {
		return s
	}
	return string(r[:max]) + "…"
}

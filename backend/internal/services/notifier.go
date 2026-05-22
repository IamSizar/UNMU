package services

import (
	"context"
	"log"

	"halalstocks/internal/repositories"
)

// Notifier sends a user a push notification (FCM) rendered in the
// language they picked (users.locale, mig 0043), honoring their
// notification preferences (mig 0041).
//
// It is strictly best-effort: every failure is logged and swallowed so a
// push problem can never break the action that triggered it (approving a
// member, accepting a subscription, …). The persistent inbox row is still
// written by the individual handlers via UserNotificationsRepository —
// this service only owns the device push.
type Notifier struct {
	users  *repositories.UserRepository
	prefs  *repositories.NotificationPrefsRepository
	tokens *repositories.PushTokenRepository
	fcm    *FCMSender // nullable — push silently disabled when nil
}

func NewNotifier(
	users *repositories.UserRepository,
	prefs *repositories.NotificationPrefsRepository,
	tokens *repositories.PushTokenRepository,
	fcm *FCMSender,
) *Notifier {
	return &Notifier{users: users, prefs: prefs, tokens: tokens, fcm: fcm}
}

// PushToUser renders the template for notifType in the recipient's locale
// and pushes it to all of their registered devices. It is a no-op
// (logged where useful) when push transport is unconfigured, the type has
// no template, the user opted out, or the user has no devices.
func (n *Notifier) PushToUser(
	ctx context.Context,
	userID int64,
	notifType string,
	params map[string]string,
) {
	if n == nil || n.fcm == nil {
		return // push transport not configured (e.g. local dev without Firebase)
	}

	// Resolve the recipient's language (default English).
	locale := "en"
	if u, err := n.users.GetByID(userID); err != nil {
		log.Printf("[notifier] load user %d: %v", userID, err)
	} else if u != nil && u.Locale != "" {
		locale = u.Locale
	}

	title, body, category, ok := RenderNotification(notifType, locale, params)
	if !ok {
		log.Printf("[notifier] no template for type %q", notifType)
		return
	}

	// Respect the user's preferences: master switch + the category toggle.
	if p, err := n.prefs.GetOrDefault(userID); err != nil {
		log.Printf("[notifier] load prefs %d: %v", userID, err)
	} else if !p.PushEnabled || !categoryEnabled(p, category) {
		return
	}

	tokens, err := n.tokens.ListForUser(userID)
	if err != nil {
		log.Printf("[notifier] load tokens %d: %v", userID, err)
		return
	}
	if len(tokens) == 0 {
		return
	}

	// data rides alongside the visible push so the app can deep-link.
	data := map[string]string{"type": notifType}
	for k, v := range params {
		data[k] = v
	}

	res, err := n.fcm.SendToTokens(ctx, tokens, title, body, data)
	if err != nil {
		log.Printf("[notifier] push to user %d failed: %v", userID, err)
		return
	}
	// Prune tokens FCM rejected as dead so the next send skips them.
	for _, dead := range res.InvalidTokens {
		_ = n.tokens.DeleteToken(dead)
	}
}

// PushToUsers fans a single notification out to many recipients, each
// rendered in their own language. Used for community content events
// (new post / poll). Best-effort per user; one failure never stops the
// rest. Pass the same params for everyone (e.g. {author, community}).
func (n *Notifier) PushToUsers(
	ctx context.Context,
	userIDs []int64,
	notifType string,
	params map[string]string,
) {
	if n == nil || n.fcm == nil {
		return
	}
	for _, uid := range userIDs {
		n.PushToUser(ctx, uid, notifType, params)
	}
}

// categoryEnabled maps a template category to its preference flag.
// CatGeneral notifications are gated only by the master push switch.
func categoryEnabled(p *repositories.NotificationPrefs, cat NotifCategory) bool {
	switch cat {
	case CatLikes:
		return p.LikesEnabled
	case CatComments:
		return p.CommentsEnabled
	case CatSubscriptions:
		return p.SubscriptionsEnabled
	case CatCommunities:
		return p.CommunitiesEnabled
	case CatMarketing:
		return p.MarketingEnabled
	default:
		return true
	}
}

package services

import (
	"sort"
	"strings"
)

// Bilingual push-notification copy, keyed by notification type.
//
// The persistent inbox row (user_notifications) is localized on-device by
// the Flutter app (it maps `type` → a localized title and shows the
// dynamic body_snippet as-is). This registry exists for the OTHER place a
// notification appears — the phone's OS tray (FCM push) — which the OS
// renders from text the backend sends, so the backend must pick the
// recipient's language itself (users.locale, mig 0043).
//
// Dynamic values (names, community titles) arrive as {placeholder} tokens
// and are inserted verbatim — never translated — matching the app-wide
// rule that user content stays in its authored language.

// NotifCategory maps a notification type to the per-user preference
// toggle that gates it (mig 0041). CatGeneral is gated only by the
// master push_enabled switch.
type NotifCategory string

const (
	CatGeneral       NotifCategory = ""
	CatLikes         NotifCategory = "likes"
	CatComments      NotifCategory = "comments"
	CatSubscriptions NotifCategory = "subscriptions"
	CatCommunities   NotifCategory = "communities"
	CatMarketing     NotifCategory = "marketing"
)

// NotifTemplate is the bilingual push copy for one notification type.
type NotifTemplate struct {
	Category NotifCategory
	TitleEn  string
	BodyEn   string
	TitleAr  string
	BodyAr   string
}

// notifTemplates — the registry. Add an entry when a new notification
// type starts sending a push. Keep the {placeholder} tokens identical
// across En/Ar so the same params map fills both.
var notifTemplates = map[string]NotifTemplate{
	// Community membership ------------------------------------------------
	// Sent to the community OWNER when someone requests to join.
	"community_join_request": {
		Category: CatCommunities,
		TitleEn:  "New join request",
		BodyEn:   "{requester} requested to join {community}.",
		TitleAr:  "طلب انضمام جديد",
		BodyAr:   "طلب {requester} الانضمام إلى {community}.",
	},
	// Sent to the community OWNER when a new member is approved.
	"community_new_member": {
		Category: CatCommunities,
		TitleEn:  "New member",
		BodyEn:   "{member} joined {community}.",
		TitleAr:  "عضو جديد",
		BodyAr:   "انضم {member} إلى {community}.",
	},
	"community_member_approved": {
		Category: CatCommunities,
		TitleEn:  "Welcome to {community}",
		BodyEn:   "Your request to join {community} was approved.",
		TitleAr:  "مرحباً بك في {community}",
		BodyAr:   "تمت الموافقة على طلب انضمامك إلى {community}.",
	},

	// Expert subscription lifecycle --------------------------------------
	// Sent to the EXPERT when someone subscribes to them.
	"expert_new_subscriber": {
		Category: CatSubscriptions,
		TitleEn:  "New subscriber",
		BodyEn:   "{subscriber} subscribed to you.",
		TitleAr:  "مشترك جديد",
		BodyAr:   "اشترك {subscriber} لديك.",
	},
	"subscription_active": {
		Category: CatSubscriptions,
		TitleEn:  "Subscription active",
		BodyEn:   "Your subscription is now active.",
		TitleAr:  "الاشتراك مُفعَّل",
		BodyAr:   "أصبح اشتراكك نشطاً الآن.",
	},
	"subscription_rejected": {
		Category: CatSubscriptions,
		TitleEn:  "Subscription declined",
		BodyEn:   "Your subscription request was declined.",
		TitleAr:  "تم رفض الاشتراك",
		BodyAr:   "تم رفض طلب اشتراكك.",
	},
	"subscription_expired": {
		Category: CatSubscriptions,
		TitleEn:  "Subscription expired",
		BodyEn:   "Your subscription has expired.",
		TitleAr:  "انتهى الاشتراك",
		BodyAr:   "انتهى اشتراكك.",
	},

	// Community subscription lifecycle -----------------------------------
	"community_subscription_active": {
		Category: CatCommunities,
		TitleEn:  "Welcome to {community}",
		BodyEn:   "Your request to join {community} was approved.",
		TitleAr:  "مرحباً بك في {community}",
		BodyAr:   "تمت الموافقة على طلب انضمامك إلى {community}.",
	},
	"community_subscription_rejected": {
		Category: CatSubscriptions,
		TitleEn:  "Community subscription declined",
		BodyEn:   "Your community subscription request was declined.",
		TitleAr:  "تم رفض اشتراك المجتمع",
		BodyAr:   "تم رفض طلب اشتراكك في المجتمع.",
	},
	"community_subscription_expired": {
		Category: CatSubscriptions,
		TitleEn:  "Community subscription expired",
		BodyEn:   "Your community subscription has expired.",
		TitleAr:  "انتهى اشتراك المجتمع",
		BodyAr:   "انتهى اشتراكك في المجتمع.",
	},

	// Community content (fanned out to members) --------------------------
	"community_new_post": {
		Category: CatCommunities,
		TitleEn:  "New post in {community}",
		BodyEn:   "{author} shared a new post.",
		TitleAr:  "منشور جديد في {community}",
		BodyAr:   "نشر {author} منشوراً جديداً.",
	},
	"poll_created": {
		Category: CatCommunities,
		TitleEn:  "New poll in {community}",
		BodyEn:   "{author} started a poll.",
		TitleAr:  "استطلاع جديد في {community}",
		BodyAr:   "بدأ {author} استطلاعاً.",
	},
	"poll_closed": {
		Category: CatCommunities,
		TitleEn:  "Poll closed in {community}",
		BodyEn:   "The poll results are in.",
		TitleAr:  "أُغلق الاستطلاع في {community}",
		BodyAr:   "ظهرت نتائج الاستطلاع.",
	},

	// Support -------------------------------------------------------------
	// Sent to the user when an admin replies to their support ticket.
	"support_reply": {
		Category: CatGeneral,
		TitleEn:  "Support replied",
		BodyEn:   "You have a new reply from support.",
		TitleAr:  "رد فريق الدعم",
		BodyAr:   "لديك رد جديد من فريق الدعم.",
	},
}

// AllNotificationTypes returns every registered notification type,
// sorted. Used by the temporary admin smoke-test endpoint.
func AllNotificationTypes() []string {
	out := make([]string, 0, len(notifTemplates))
	for k := range notifTemplates {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// RenderNotification builds the localized (title, body) for a type in the
// given locale, substituting {key} tokens from params. Returns ok=false
// when the type has no template. Falls back to English when an Arabic
// string is missing or the locale is anything other than "ar".
func RenderNotification(
	notifType, locale string,
	params map[string]string,
) (title, body string, category NotifCategory, ok bool) {
	t, found := notifTemplates[notifType]
	if !found {
		return "", "", CatGeneral, false
	}

	title, body = t.TitleEn, t.BodyEn
	if strings.ToLower(strings.TrimSpace(locale)) == "ar" {
		if t.TitleAr != "" {
			title = t.TitleAr
		}
		if t.BodyAr != "" {
			body = t.BodyAr
		}
	}

	return substituteParams(title, params),
		substituteParams(body, params),
		t.Category, true
}

// substituteParams replaces every {key} occurrence with params[key].
// Unknown tokens are left untouched.
func substituteParams(s string, params map[string]string) string {
	if len(params) == 0 || !strings.Contains(s, "{") {
		return s
	}
	for k, v := range params {
		s = strings.ReplaceAll(s, "{"+k+"}", v)
	}
	return s
}

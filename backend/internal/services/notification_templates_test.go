package services

import (
	"strings"
	"testing"
)

func TestRenderNotification_English(t *testing.T) {
	title, body, cat, ok := RenderNotification(
		"community_member_approved", "en",
		map[string]string{"community": "Halaltek"},
	)
	if !ok {
		t.Fatal("expected template to exist")
	}
	if title != "Welcome to Halaltek" {
		t.Errorf("en title = %q", title)
	}
	if body != "Your request to join Halaltek was approved." {
		t.Errorf("en body = %q", body)
	}
	if cat != CatCommunities {
		t.Errorf("category = %q, want communities", cat)
	}
}

func TestRenderNotification_Arabic(t *testing.T) {
	enTitle, _, _, _ := RenderNotification(
		"community_member_approved", "en",
		map[string]string{"community": "Halaltek"},
	)
	arTitle, arBody, _, ok := RenderNotification(
		"community_member_approved", "ar",
		map[string]string{"community": "Halaltek"},
	)
	if !ok {
		t.Fatal("expected template to exist")
	}
	if arTitle == enTitle {
		t.Errorf("arabic title should differ from english, both = %q", arTitle)
	}
	// The dynamic community name stays literal (never translated).
	if !strings.Contains(arTitle, "Halaltek") {
		t.Errorf("arabic title dropped the literal name: %q", arTitle)
	}
	if !strings.Contains(arBody, "Halaltek") {
		t.Errorf("arabic body dropped the literal name: %q", arBody)
	}
	// No unsubstituted placeholder should remain.
	if strings.Contains(arTitle, "{") || strings.Contains(arBody, "{") {
		t.Errorf("unsubstituted token remains: title=%q body=%q", arTitle, arBody)
	}
}

func TestRenderNotification_CommunitySubscriptionActive(t *testing.T) {
	// The type wired into AdminAccept — substitutes the community name in
	// both languages and keeps it literal.
	en, _, cat, ok := RenderNotification(
		"community_subscription_active", "en",
		map[string]string{"community": "Halaltek"},
	)
	if !ok {
		t.Fatal("expected template to exist")
	}
	if en != "Welcome to Halaltek" {
		t.Errorf("en title = %q", en)
	}
	if cat != CatCommunities {
		t.Errorf("category = %q, want communities", cat)
	}
	ar, arBody, _, _ := RenderNotification(
		"community_subscription_active", "ar",
		map[string]string{"community": "Halaltek"},
	)
	if ar == en {
		t.Errorf("arabic title should differ from english")
	}
	if !strings.Contains(ar, "Halaltek") || !strings.Contains(arBody, "Halaltek") {
		t.Errorf("arabic dropped the literal name: title=%q body=%q", ar, arBody)
	}
}

func TestRenderNotification_CommunityJoinRequest(t *testing.T) {
	params := map[string]string{"requester": "Caesar", "community": "Halaltek"}
	en, enBody, cat, ok := RenderNotification("community_join_request", "en", params)
	if !ok {
		t.Fatal("expected template to exist")
	}
	if cat != CatCommunities {
		t.Errorf("category = %q, want communities", cat)
	}
	if enBody != "Caesar requested to join Halaltek." {
		t.Errorf("en body = %q", enBody)
	}
	arTitle, arBody, _, _ := RenderNotification("community_join_request", "ar", params)
	if arTitle == en {
		t.Errorf("arabic title should differ from english")
	}
	// Both literal names preserved, untranslated, no leftover tokens.
	if !strings.Contains(arBody, "Caesar") || !strings.Contains(arBody, "Halaltek") {
		t.Errorf("arabic body dropped a literal name: %q", arBody)
	}
	if strings.Contains(arBody, "{") {
		t.Errorf("unsubstituted token remains: %q", arBody)
	}
}

func TestRenderNotification_NewSubscriberAndMember(t *testing.T) {
	// Expert new subscriber.
	_, body, cat, ok := RenderNotification(
		"expert_new_subscriber", "ar", map[string]string{"subscriber": "Caesar"},
	)
	if !ok || cat != CatSubscriptions {
		t.Fatalf("expert_new_subscriber: ok=%v cat=%q", ok, cat)
	}
	if !strings.Contains(body, "Caesar") || strings.Contains(body, "{") {
		t.Errorf("expert_new_subscriber ar body = %q", body)
	}
	// Community new member.
	_, mBody, mCat, ok := RenderNotification(
		"community_new_member", "ar",
		map[string]string{"member": "Caesar", "community": "Halaltek"},
	)
	if !ok || mCat != CatCommunities {
		t.Fatalf("community_new_member: ok=%v cat=%q", ok, mCat)
	}
	if !strings.Contains(mBody, "Caesar") || !strings.Contains(mBody, "Halaltek") ||
		strings.Contains(mBody, "{") {
		t.Errorf("community_new_member ar body = %q", mBody)
	}
}

func TestRenderNotification_SupportReply(t *testing.T) {
	en, _, cat, ok := RenderNotification("support_reply", "en", nil)
	if !ok || cat != CatGeneral {
		t.Fatalf("support_reply: ok=%v cat=%q", ok, cat)
	}
	ar, _, _, _ := RenderNotification("support_reply", "ar", nil)
	if ar == en {
		t.Errorf("support_reply ar should differ from en")
	}
}

func TestRenderNotification_CommunityContent(t *testing.T) {
	p := map[string]string{"author": "Caesar", "community": "Halaltek"}
	title, body, cat, ok := RenderNotification("community_new_post", "ar", p)
	if !ok || cat != CatCommunities {
		t.Fatalf("community_new_post: ok=%v cat=%q", ok, cat)
	}
	if !strings.Contains(title, "Halaltek") || !strings.Contains(body, "Caesar") {
		t.Errorf("community_new_post ar: title=%q body=%q", title, body)
	}
	if strings.Contains(title, "{") || strings.Contains(body, "{") {
		t.Errorf("unsubstituted token: title=%q body=%q", title, body)
	}
	if _, _, _, ok := RenderNotification("poll_created", "ar", p); !ok {
		t.Error("poll_created missing")
	}
	if t2, _, _, ok := RenderNotification("poll_closed", "ar", p); !ok ||
		!strings.Contains(t2, "Halaltek") {
		t.Errorf("poll_closed ar title=%q ok=%v", t2, ok)
	}
}

func TestRenderNotification_UnknownType(t *testing.T) {
	if _, _, _, ok := RenderNotification("does_not_exist", "en", nil); ok {
		t.Error("unknown type should return ok=false")
	}
}

func TestRenderNotification_UnknownLocaleFallsBackToEnglish(t *testing.T) {
	title, _, _, _ := RenderNotification(
		"subscription_active", "fr", nil,
	)
	if title != "Subscription active" {
		t.Errorf("unknown locale should fall back to english, got %q", title)
	}
}

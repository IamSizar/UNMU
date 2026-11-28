package services

import (
	"context"
	"sort"
	"strings"
	"sync"
	"testing"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
)

// fakePusher records every push instead of sending it.
type fakePusher struct {
	mu    sync.Mutex
	calls []fakePush
}

type fakePush struct {
	user   int64
	typ    string
	params map[string]string
}

func (f *fakePusher) PushToUser(_ context.Context, userID int64, notifType string, params map[string]string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, fakePush{userID, notifType, params})
}

func (f *fakePusher) users() []int64 {
	f.mu.Lock()
	defer f.mu.Unlock()
	var ids []int64
	for _, c := range f.calls {
		ids = append(ids, c.user)
	}
	sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
	return ids
}

// fakeRecipients returns fixed user lists.
type fakeRecipients struct {
	newItem []int64
	savers  map[int64][]int64
}

func (f fakeRecipients) NewItemRecipients(context.Context) ([]int64, error) { return f.newItem, nil }
func (f fakeRecipients) SaverRecipients(_ context.Context, id int64) ([]int64, error) {
	return f.savers[id], nil
}

func newTestNotifier(push *fakePusher, rec fakeRecipients) *PulseNotifier {
	return &PulseNotifier{push: push, recipients: rec}
}

func pulseTestItem(id int64) models.PulseAdminItem {
	return models.PulseAdminItem{ID: id, PulseDate: "2026-10-22", Slot: "global", TitleEn: "English title", TitleAr: "عنوان"}
}

func TestPulseNotifier_SingleNewItemGoesToEveryoneWhoWantsIt(t *testing.T) {
	push := &fakePusher{}
	n := newTestNotifier(push, fakeRecipients{newItem: []int64{1, 2, 3}})
	n.sendPublished(context.Background(), []models.PulseAdminItem{pulseTestItem(7)})

	if got := push.users(); len(got) != 3 || got[0] != 1 || got[2] != 3 {
		t.Fatalf("recipients = %v, want [1 2 3]", got)
	}
	c := push.calls[0]
	if c.typ != "pulse_new" || c.params["itemId"] != "7" || c.params["titleEn"] != "English title" || c.params["titleAr"] != "عنوان" {
		t.Errorf("unexpected push: %+v", c)
	}
}

func TestPulseNotifier_SeveralItemsAtOnceSendOneCombinedPush(t *testing.T) {
	push := &fakePusher{}
	n := newTestNotifier(push, fakeRecipients{newItem: []int64{1, 2}})
	n.sendPublished(context.Background(), []models.PulseAdminItem{pulseTestItem(1), pulseTestItem(2), pulseTestItem(3), pulseTestItem(4)})

	if len(push.calls) != 2 { // one per user, not one per item
		t.Fatalf("got %d pushes, want 2 (one per user)", len(push.calls))
	}
	if c := push.calls[0]; c.typ != "pulse_new_many" || c.params["count"] != "4" {
		t.Errorf("unexpected combined push: %+v", c)
	}
}

func TestPulseNotifier_ChangesGoOnlyToSavers(t *testing.T) {
	push := &fakePusher{}
	n := newTestNotifier(push, fakeRecipients{
		newItem: []int64{1, 2, 3, 4},
		savers:  map[int64][]int64{9: {2, 4}},
	})
	n.sendChanged(context.Background(), models.PulseChangeCorrected, pulseTestItem(9))

	if got := push.users(); len(got) != 2 || got[0] != 2 || got[1] != 4 {
		t.Fatalf("recipients = %v, want only the savers [2 4]", got)
	}
	if push.calls[0].typ != "pulse_corrected" {
		t.Errorf("type = %s, want pulse_corrected", push.calls[0].typ)
	}
	push.calls = nil
	n.sendChanged(context.Background(), models.PulseChangeUpdated, pulseTestItem(9))
	if push.calls[0].typ != "pulse_updated" {
		t.Errorf("type = %s, want pulse_updated", push.calls[0].typ)
	}
}

func TestPulseNotifier_NobodyToNotifyIsFine(t *testing.T) {
	push := &fakePusher{}
	n := newTestNotifier(push, fakeRecipients{})
	n.sendPublished(context.Background(), []models.PulseAdminItem{pulseTestItem(1)})
	n.sendPublished(context.Background(), nil)
	n.sendChanged(context.Background(), models.PulseChangeUpdated, pulseTestItem(1))
	if len(push.calls) != 0 {
		t.Errorf("expected no pushes, got %d", len(push.calls))
	}
}

func TestPulseNotifier_NilIsSafe(t *testing.T) {
	var n *PulseNotifier
	n.OnPublished(context.Background(), []models.PulseAdminItem{pulseTestItem(1)})
	n.OnChange(context.Background(), "published", pulseTestItem(1))
}

func TestPulseTemplates_RenderInBothLanguages(t *testing.T) {
	params := pulseItemParams(pulseTestItem(5))
	for _, typ := range []string{"pulse_new", "pulse_updated", "pulse_corrected"} {
		titleEn, bodyEn, _, ok := RenderNotification(typ, "en", params)
		if !ok || bodyEn != "English title" || strings.Contains(titleEn+bodyEn, "{") {
			t.Errorf("%s (en): %q / %q ok=%v", typ, titleEn, bodyEn, ok)
		}
		titleAr, bodyAr, _, ok := RenderNotification(typ, "ar", params)
		if !ok || bodyAr != "عنوان" || strings.Contains(titleAr+bodyAr, "{") {
			t.Errorf("%s (ar): %q / %q ok=%v", typ, titleAr, bodyAr, ok)
		}
	}
	_, body, _, _ := RenderNotification("pulse_new_many", "ar", map[string]string{"count": "4"})
	if !strings.Contains(body, "4") || strings.Contains(body, "{") {
		t.Errorf("combined Arabic copy not filled in: %q", body)
	}
}

func TestPulseCategoryGating(t *testing.T) {
	on := &repositories.NotificationPrefs{
		PushEnabled: true, PulseEnabled: true, PulseNewEnabled: true,
		PulseUpdatesEnabled: true, PulseCorrectionsEnabled: true, PulseSavedEnabled: true,
	}
	for _, cat := range []NotifCategory{CatPulseNew, CatPulseUpdate, CatPulseCorrection} {
		if !categoryEnabled(on, cat) {
			t.Errorf("%s should be enabled when everything is on", cat)
		}
	}
	cases := []struct {
		name   string
		mutate func(p *repositories.NotificationPrefs)
		cat    NotifCategory
	}{
		{"master off blocks new", func(p *repositories.NotificationPrefs) { p.PulseEnabled = false }, CatPulseNew},
		{"master off blocks updates", func(p *repositories.NotificationPrefs) { p.PulseEnabled = false }, CatPulseUpdate},
		{"new switch off", func(p *repositories.NotificationPrefs) { p.PulseNewEnabled = false }, CatPulseNew},
		{"updates switch off", func(p *repositories.NotificationPrefs) { p.PulseUpdatesEnabled = false }, CatPulseUpdate},
		{"corrections switch off", func(p *repositories.NotificationPrefs) { p.PulseCorrectionsEnabled = false }, CatPulseCorrection},
		{"saved-items switch off blocks updates", func(p *repositories.NotificationPrefs) { p.PulseSavedEnabled = false }, CatPulseUpdate},
		{"saved-items switch off blocks corrections", func(p *repositories.NotificationPrefs) { p.PulseSavedEnabled = false }, CatPulseCorrection},
	}
	for _, c := range cases {
		p := *on
		c.mutate(&p)
		if categoryEnabled(&p, c.cat) {
			t.Errorf("%s: %s should be blocked", c.name, c.cat)
		}
	}
	// Turning off "saved" must not silence brand-new items.
	p := *on
	p.PulseSavedEnabled = false
	if !categoryEnabled(&p, CatPulseNew) {
		t.Error("the saved-items switch must not affect new-item pushes")
	}
}

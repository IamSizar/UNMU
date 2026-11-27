package repositories

import (
	"context"
	"testing"

	"halalstocks/internal/pulse"
)

// OPOS 137988: a saved item used to vanish from Saved (and stop opening)
// as soon as a newer item replaced it in its slot, because replacement
// archives the old item and the read side only returned published rows.
// A replaced item must stay in Saved and keep opening; an item an approver
// deliberately took down (archive action) must not.
//
// Needs PULSE_TEST_DSN (see pulse_integration_test.go).
func TestPulseSavedSurvivesReplacement(t *testing.T) {
	f := newCMSFixture(t)
	reader := NewPulseRepository(openPulseTestDB(t))
	ctx := context.Background()
	readerID := f.author.UserID

	publish := func(date, slot string) int64 {
		it := f.create(cmsInput(date, slot))
		f.must(it.ID, f.author, pulse.DoSubmit)
		f.must(it.ID, f.approver, pulse.DoApprove)
		f.must(it.ID, f.approver, pulse.DoPublish)
		return it.ID
	}
	savedIDs := func() map[int64]bool {
		items, _, err := reader.Saved(ctx, readerID, 50, 0)
		if err != nil {
			t.Fatalf("saved: %v", err)
		}
		m := map[int64]bool{}
		for _, it := range items {
			m[it.ID] = true
		}
		return m
	}

	const d = "1991-03-03"
	first := publish(d, "global")
	if err := reader.Save(ctx, readerID, first); err != nil {
		t.Fatalf("save: %v", err)
	}
	second := publish(d, "global") // replaces first

	if !savedIDs()[first] {
		t.Error("replaced item disappeared from Saved")
	}
	if _, err := reader.Item(ctx, readerID, first); err != nil {
		t.Errorf("replaced saved item no longer opens: %v", err)
	}
	day, err := reader.Day(ctx, readerID, d)
	if err != nil {
		t.Fatalf("day: %v", err)
	}
	for _, it := range day.Items {
		if it.ID == first {
			t.Error("replaced item must not show on the day itself")
		}
	}
	_ = second

	takenDown := publish(d, "gulf")
	if err := reader.Save(ctx, readerID, takenDown); err != nil {
		t.Fatalf("save: %v", err)
	}
	if _, err := f.apply(takenDown, f.approver, pulse.DoArchive,
		PulseApplyOptions{Note: "wrong figures"}); err != nil {
		t.Fatalf("archive: %v", err)
	}
	if savedIDs()[takenDown] {
		t.Error("an item taken down by an approver must leave Saved")
	}
	if _, err := reader.Item(ctx, readerID, takenDown); err != ErrPulseNotFound {
		t.Errorf("taken-down item opens: err=%v", err)
	}
}

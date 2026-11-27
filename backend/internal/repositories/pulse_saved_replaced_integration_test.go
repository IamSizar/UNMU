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

	// Review of PR #5 ↓

	t.Run("replacement is recorded as a link, not note text", func(t *testing.T) {
		old, err := f.repo.Get(ctx, first)
		if err != nil {
			t.Fatal(err)
		}
		if old.ReplacedBy == nil || *old.ReplacedBy != second {
			t.Fatalf("ReplacedBy = %v, want %d", old.ReplacedBy, second)
		}
	})

	t.Run("a takedown note that looks like a replacement note does not count", func(t *testing.T) {
		spoof := publish(d, "opportunity")
		if err := reader.Save(ctx, readerID, spoof); err != nil {
			t.Fatal(err)
		}
		if _, err := f.apply(spoof, f.approver, pulse.DoArchive,
			PulseApplyOptions{Note: ReplacedNotePrefix + "1"}); err != nil {
			t.Fatal(err)
		}
		if savedIDs()[spoof] {
			t.Error("item archived with a look-alike note is still in Saved")
		}
	})

	t.Run("only users who saved a replaced item can open it", func(t *testing.T) {
		otherID := f.reviewer.UserID // never saved it
		if _, err := reader.Item(ctx, otherID, first); err != ErrPulseNotFound {
			t.Errorf("non-saver opened a replaced item: err=%v", err)
		}
	})

	t.Run("a replaced item can be taken down, once", func(t *testing.T) {
		if _, err := f.apply(first, f.approver, pulse.DoArchive,
			PulseApplyOptions{Note: "legal request"}); err != nil {
			t.Fatalf("taking down a replaced item: %v", err)
		}
		if savedIDs()[first] {
			t.Error("taken-down replaced item still in Saved")
		}
		if _, err := reader.Item(ctx, readerID, first); err != ErrPulseNotFound {
			t.Errorf("taken-down replaced item opens: err=%v", err)
		}
		_, err := f.apply(first, f.approver, pulse.DoArchive, PulseApplyOptions{})
		if ruleKind(err) != "state" {
			t.Errorf("second takedown: %s, want state error", ruleKind(err))
		}
	})
}

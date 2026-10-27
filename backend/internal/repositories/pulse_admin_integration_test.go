package repositories

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/pulse"
)

// Integration test for the Pulse CMS repository (workflow, history, staff,
// analytics). Runs only when PULSE_TEST_DSN is set; see pulse_integration_test.go.

type cmsFixture struct {
	t                                 *testing.T
	repo                              *PulseAdminRepository
	author, reviewer, approver, admin pulse.Actor
	userIDs                           []int64
	itemIDs                           []int64
}

func newCMSFixture(t *testing.T) *cmsFixture {
	db := openPulseTestDB(t)
	f := &cmsFixture{t: t, repo: NewPulseAdminRepository(db)}
	suffix := time.Now().UnixNano()
	mk := func(label, role string) int64 {
		var id int64
		err := db.QueryRow(`INSERT INTO users (email, password_hash, role) VALUES ($1,'x',$2) RETURNING id`,
			fmt.Sprintf("pulse-cms-%s-%d@test.invalid", label, suffix), role).Scan(&id)
		if err != nil {
			t.Fatalf("fixture user: %v", err)
		}
		f.userIDs = append(f.userIDs, id)
		return id
	}
	roles := func(r ...string) map[string]bool {
		m := map[string]bool{}
		for _, x := range r {
			m[x] = true
		}
		return m
	}
	f.author = pulse.Actor{UserID: mk("author", "USER"), Roles: roles(models.PulseRoleEditor)}
	f.reviewer = pulse.Actor{UserID: mk("reviewer", "USER"), Roles: roles(models.PulseRoleReviewer)}
	f.approver = pulse.Actor{UserID: mk("approver", "USER"), Roles: roles(models.PulseRoleApprover)}
	f.admin = pulse.Actor{UserID: mk("admin", "ADMIN"), IsAdmin: true, Roles: roles()}

	t.Cleanup(func() {
		for _, id := range f.itemIDs {
			db.Exec(`DELETE FROM pulse_items WHERE id = $1`, id)
		}
		for _, id := range f.userIDs {
			db.Exec(`DELETE FROM pulse_staff WHERE user_id = $1`, id)
			db.Exec(`DELETE FROM pulse_events WHERE user_id = $1`, id)
			db.Exec(`DELETE FROM users WHERE id = $1`, id)
		}
	})
	return f
}

func cmsInput(date, slot string) models.PulseItemInput {
	verified := time.Now().Add(-time.Hour)
	return models.PulseItemInput{
		PulseDate: date, Slot: slot, Classification: models.PulseConfirmed,
		IsSensitive: slot == models.PulseSlotSharia,
		TitleAr:     "عنوان", TitleEn: "Title " + slot, SummaryAr: "ملخص", SummaryEn: "Summary",
		SourceName: "Source", VerifiedAt: &verified,
	}
}

// ruleKind names the kind of rule error ("ok" when err is nil).
func ruleKind(err error) string {
	var re *pulse.RuleError
	if errors.As(err, &re) {
		return re.Kind
	}
	if err == nil {
		return "ok"
	}
	return "other: " + err.Error()
}

func (f *cmsFixture) create(in models.PulseItemInput) *models.PulseAdminItem {
	f.t.Helper()
	it, err := f.repo.Create(context.Background(), f.author, in)
	if err != nil {
		f.t.Fatalf("create: %v", err)
	}
	f.itemIDs = append(f.itemIDs, it.ID)
	return it
}

func (f *cmsFixture) apply(id int64, who pulse.Actor, do string, o PulseApplyOptions) (*models.PulseAdminItem, error) {
	return f.repo.Apply(context.Background(), id, who, do, o)
}

// must applies an action that is expected to succeed.
func (f *cmsFixture) must(id int64, who pulse.Actor, do string) *models.PulseAdminItem {
	f.t.Helper()
	it, err := f.apply(id, who, do, PulseApplyOptions{})
	if err != nil {
		f.t.Fatalf("%s: %v", do, err)
	}
	return it
}

func TestPulseCMSWorkflow(t *testing.T) {
	f := newCMSFixture(t)
	ctx := context.Background()
	const day = "1991-02-01"

	t.Run("only editors create; edits bump the version and keep history", func(t *testing.T) {
		if _, err := f.repo.Create(ctx, f.reviewer, cmsInput(day, "global")); ruleKind(err) != "forbidden" {
			t.Errorf("reviewer create: %s, want forbidden", ruleKind(err))
		}
		it := f.create(cmsInput(day, "global"))
		if it.Status != "draft" || it.Version != 1 {
			t.Fatalf("new item: %+v", it)
		}
		in := cmsInput(day, "global")
		in.TitleEn = "Edited title"
		it, err := f.repo.Update(ctx, it.ID, f.author, in)
		if err != nil || it.Version != 2 || it.TitleEn != "Edited title" {
			t.Fatalf("update: %+v err=%v", it, err)
		}
		vs, _ := f.repo.Versions(ctx, it.ID)
		log, _ := f.repo.ChangeLog(ctx, it.ID)
		if len(vs) != 2 || vs[0].Version != 2 || len(log) != 2 || log[0].Action != "created" || log[1].Action != "edited" {
			t.Errorf("history wrong: %d versions, log=%+v", len(vs), log)
		}
	})

	t.Run("incomplete items cannot be submitted", func(t *testing.T) {
		in := cmsInput(day, "gulf")
		in.TitleEn, in.SourceName = "", ""
		it := f.create(in)
		_, err := f.apply(it.ID, f.author, pulse.DoSubmit, PulseApplyOptions{})
		var re *pulse.RuleError
		if !errors.As(err, &re) || re.Kind != "invalid" || re.Fields["titleEn"] == "" || re.Fields["sourceName"] == "" {
			t.Errorf("submit incomplete: %v", err)
		}
	})

	t.Run("sensitive item: review first, four-eyes, then publish", func(t *testing.T) {
		it := f.create(cmsInput(day, "sharia"))
		f.must(it.ID, f.author, pulse.DoSubmit)

		if _, err := f.repo.Update(ctx, it.ID, f.author, cmsInput(day, "sharia")); ruleKind(err) != "state" {
			t.Errorf("editing an in-review item: %s, want state", ruleKind(err))
		}
		if _, err := f.apply(it.ID, f.approver, pulse.DoApprove, PulseApplyOptions{}); ruleKind(err) != "state" {
			t.Errorf("approve before review: %s, want state", ruleKind(err))
		}
		authorReviewer := pulse.Actor{UserID: f.author.UserID, Roles: map[string]bool{models.PulseRoleReviewer: true}}
		if _, err := f.apply(it.ID, authorReviewer, pulse.DoReview, PulseApplyOptions{}); ruleKind(err) != "forbidden" {
			t.Errorf("author reviewing own item: %s, want forbidden", ruleKind(err))
		}
		f.must(it.ID, f.reviewer, pulse.DoReview)
		authorApprover := pulse.Actor{UserID: f.author.UserID, Roles: map[string]bool{models.PulseRoleApprover: true}}
		if _, err := f.apply(it.ID, authorApprover, pulse.DoApprove, PulseApplyOptions{}); ruleKind(err) != "forbidden" {
			t.Errorf("author approving own item: %s, want forbidden", ruleKind(err))
		}
		got := f.must(it.ID, f.approver, pulse.DoApprove)
		if got.Status != "approved" || got.ApprovedBy == nil || got.ReviewedBy == nil {
			t.Fatalf("after approve: %+v", got)
		}
		got = f.must(it.ID, f.approver, pulse.DoPublish)
		if got.Status != "published" || got.PublishedAt == nil {
			t.Fatalf("after publish: %+v", got)
		}
	})

	t.Run("reject needs a note and sends the item back to draft", func(t *testing.T) {
		it := f.create(cmsInput(day, "opportunity"))
		f.must(it.ID, f.author, pulse.DoSubmit)
		if _, err := f.apply(it.ID, f.reviewer, pulse.DoReject, PulseApplyOptions{}); ruleKind(err) != "invalid" {
			t.Errorf("reject without note: %s, want invalid", ruleKind(err))
		}
		got, err := f.apply(it.ID, f.reviewer, pulse.DoReject, PulseApplyOptions{Note: "Source is weak"})
		if err != nil || got.Status != "draft" || got.ReviewedBy != nil {
			t.Fatalf("reject: %+v err=%v", got, err)
		}
	})

	t.Run("publishing a second item replaces the first for the same slot", func(t *testing.T) {
		const d = "1991-02-02"
		first := f.create(cmsInput(d, "global"))
		f.must(first.ID, f.author, pulse.DoSubmit)
		f.must(first.ID, f.approver, pulse.DoApprove)
		f.must(first.ID, f.approver, pulse.DoPublish)

		second := f.create(cmsInput(d, "global"))
		f.must(second.ID, f.author, pulse.DoSubmit)
		f.must(second.ID, f.approver, pulse.DoApprove)
		f.must(second.ID, f.admin, pulse.DoPublish)

		old, _ := f.repo.Get(ctx, first.ID)
		if old.Status != "archived" {
			t.Errorf("replaced item status = %s, want archived", old.Status)
		}
		log, _ := f.repo.ChangeLog(ctx, first.ID)
		if last := log[len(log)-1]; last.Action != "archived" || last.Note == "" {
			t.Errorf("replacement not logged: %+v", last)
		}
	})

	t.Run("schedule, unschedule and the due-item promotion", func(t *testing.T) {
		it := f.create(cmsInput("1991-02-03", "gulf"))
		f.must(it.ID, f.author, pulse.DoSubmit)
		f.must(it.ID, f.approver, pulse.DoApprove)

		past := time.Now().Add(-time.Hour)
		if _, err := f.apply(it.ID, f.approver, pulse.DoSchedule, PulseApplyOptions{PublishAt: &past}); ruleKind(err) != "invalid" {
			t.Errorf("schedule in the past: %s, want invalid", ruleKind(err))
		}
		future := time.Now().Add(2 * time.Hour)
		got, err := f.apply(it.ID, f.approver, pulse.DoSchedule, PulseApplyOptions{PublishAt: &future})
		if err != nil || got.Status != "scheduled" {
			t.Fatalf("schedule: %+v err=%v", got, err)
		}
		if got = f.must(it.ID, f.approver, pulse.DoUnschedule); got.Status != "approved" || got.PublishAt != nil {
			t.Fatalf("unschedule: %+v", got)
		}
		f.apply(it.ID, f.approver, pulse.DoSchedule, PulseApplyOptions{PublishAt: &future})

		// Not due yet: this item must not be promoted.
		early, _ := f.repo.PromoteDue(ctx, time.Now())
		for _, p := range early {
			if p.ID == it.ID {
				t.Error("item promoted before its time")
			}
		}
		// Due: promoted exactly once, logged as a system action.
		promoted, err := f.repo.PromoteDue(ctx, future.Add(time.Minute))
		found := false
		for _, p := range promoted {
			found = found || (p.ID == it.ID && p.Status == "published")
		}
		if err != nil || !found {
			t.Fatalf("promotion failed: %+v err=%v", promoted, err)
		}
		again, _ := f.repo.PromoteDue(ctx, future.Add(time.Minute))
		for _, p := range again {
			if p.ID == it.ID {
				t.Error("item promoted twice")
			}
		}
		log, _ := f.repo.ChangeLog(ctx, it.ID)
		if last := log[len(log)-1]; last.Action != "published" || last.ActorID != nil {
			t.Errorf("scheduler publish should be a system action: %+v", last)
		}
	})

	t.Run("a correction needs a second person: propose, then a different approver applies", func(t *testing.T) {
		it := f.create(cmsInput("1991-02-04", "global"))
		f.must(it.ID, f.author, pulse.DoSubmit)
		f.must(it.ID, f.approver, pulse.DoApprove)
		f.must(it.ID, f.approver, pulse.DoPublish)

		fix := cmsInput("1991-02-04", "global")
		fix.TitleEn = "Corrected headline"
		// Input rules.
		if _, err := f.repo.ProposeCorrection(ctx, it.ID, f.approver, "corrected", fix, " "); ruleKind(err) != "invalid" {
			t.Errorf("proposal without a note: %s, want invalid", ruleKind(err))
		}
		if _, err := f.repo.ProposeCorrection(ctx, it.ID, f.approver, "banana", fix, "x"); ruleKind(err) != "invalid" {
			t.Errorf("bad kind: %s, want invalid", ruleKind(err))
		}
		if _, err := f.repo.ProposeCorrection(ctx, it.ID, f.reviewer, "corrected", fix, "typo"); ruleKind(err) != "forbidden" {
			t.Errorf("reviewer proposing: %s, want forbidden", ruleKind(err))
		}
		// Proposing changes NOTHING on the live item.
		pending, err := f.repo.ProposeCorrection(ctx, it.ID, f.approver, "corrected", fix, "Fixed a wrong figure")
		if err != nil || pending == nil || pending.Input.TitleEn != "Corrected headline" {
			t.Fatalf("propose: %+v err=%v", pending, err)
		}
		live, _ := f.repo.Get(ctx, it.ID)
		if live.TitleEn == "Corrected headline" || live.Version != 1 {
			t.Fatalf("proposal changed the live item: %+v", live)
		}
		// The proposer cannot apply or reject their own proposal.
		if _, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.approver, true, ""); ruleKind(err) != "forbidden" {
			t.Errorf("self-approval: %s, want forbidden", ruleKind(err))
		}
		if _, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.approver, false, "never mind"); ruleKind(err) != "forbidden" {
			t.Errorf("self-rejection: %s, want forbidden", ruleKind(err))
		}
		// An editor cannot apply one, and someone else cannot overwrite it.
		if _, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.author, true, ""); ruleKind(err) != "forbidden" {
			t.Errorf("editor applying: %s, want forbidden", ruleKind(err))
		}
		if _, err := f.repo.ProposeCorrection(ctx, it.ID, f.admin, "updated", fix, "mine"); ruleKind(err) != "state" {
			t.Errorf("second open proposal: %s, want state", ruleKind(err))
		}
		// A different approver (the admin holds every role) applies it.
		got, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.admin, true, "looks right")
		if err != nil || got.Status != "published" || got.TitleEn != "Corrected headline" ||
			got.ChangeKind == nil || *got.ChangeKind != "corrected" || got.LastChangedAt == nil || got.Version != 2 {
			t.Fatalf("apply: %+v err=%v", got, err)
		}
		if p, _ := f.repo.PendingCorrection(ctx, it.ID); p != nil {
			t.Error("the proposal should be closed after it was applied")
		}
		vs, _ := f.repo.Versions(ctx, it.ID)
		if len(vs) != 2 || vs[0].Reason != "correction" {
			t.Fatalf("versions after correction: %+v", vs)
		}
		// The previous wording survives in the older snapshot.
		if !strings.Contains(string(vs[1].Snapshot), "Title global") {
			t.Errorf("old version lost: %s", vs[1].Snapshot)
		}
		// The change log shows who proposed and who applied.
		evs, _ := f.repo.ChangeLog(ctx, it.ID)
		var actions []string
		for _, e := range evs {
			actions = append(actions, e.Action)
		}
		if !strings.Contains(strings.Join(actions, ","), "correction_proposed") ||
			!strings.Contains(strings.Join(actions, ","), "corrected") {
			t.Errorf("change log missing the two-step trail: %v", actions)
		}
		// A correction cannot move the item to another day or slot.
		moved := cmsInput("1999-01-01", "gulf")
		moved.TitleEn = "Moved?"
		if _, err := f.repo.ProposeCorrection(ctx, it.ID, f.approver, "updated", moved, "try to move"); err != nil {
			t.Fatal(err)
		}
		got, _, _ = f.repo.ResolveCorrection(ctx, it.ID, f.admin, true, "")
		if got == nil || got.PulseDate != "1991-02-04" || got.Slot != "global" {
			t.Errorf("correction moved the item: %+v", got)
		}
	})

	t.Run("a rejected correction leaves the item alone and needs a reason", func(t *testing.T) {
		it := f.create(cmsInput("1991-02-07", "global"))
		f.must(it.ID, f.author, pulse.DoSubmit)
		f.must(it.ID, f.approver, pulse.DoApprove)
		f.must(it.ID, f.approver, pulse.DoPublish)
		fix := cmsInput("1991-02-07", "global")
		fix.TitleEn = "Should not go live"
		if _, err := f.repo.ProposeCorrection(ctx, it.ID, f.approver, "corrected", fix, "wrong idea"); err != nil {
			t.Fatal(err)
		}
		if _, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.admin, false, " "); ruleKind(err) != "invalid" {
			t.Errorf("rejection without a reason: %s, want invalid", ruleKind(err))
		}
		got, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.admin, false, "figure is right as is")
		if err != nil || got.TitleEn == "Should not go live" || got.Version != 1 {
			t.Fatalf("reject: %+v err=%v", got, err)
		}
		if _, _, err := f.repo.ResolveCorrection(ctx, it.ID, f.admin, true, ""); ruleKind(err) != "state" {
			t.Errorf("resolving with nothing pending: %s, want state", ruleKind(err))
		}
	})

	t.Run("a sensitive item cannot be approved by its own reviewer", func(t *testing.T) {
		it := f.create(cmsInput("1991-02-08", "sharia"))
		f.must(it.ID, f.author, pulse.DoSubmit)
		// The admin holds every role: they review, so they may not also approve.
		f.must(it.ID, f.admin, pulse.DoReview)
		if _, err := f.apply(it.ID, f.admin, pulse.DoApprove, PulseApplyOptions{}); ruleKind(err) != "forbidden" {
			t.Errorf("reviewer approving a sensitive item: %s, want forbidden", ruleKind(err))
		}
		if _, err := f.apply(it.ID, f.approver, pulse.DoApprove, PulseApplyOptions{}); err != nil {
			t.Errorf("a different approver should be allowed: %v", err)
		}
	})

	t.Run("a future-dated item cannot be published early", func(t *testing.T) {
		// Regression: a far-future pulse_date used to go live at once, leaking
		// into the archive and the "new Pulse" push before its day.
		it := f.create(cmsInput("2999-01-01", "opportunity"))
		f.must(it.ID, f.author, pulse.DoSubmit)
		f.must(it.ID, f.approver, pulse.DoApprove)
		if _, err := f.apply(it.ID, f.approver, pulse.DoPublish, PulseApplyOptions{}); ruleKind(err) != "state" {
			t.Errorf("publishing a future-dated item: %s, want state", ruleKind(err))
		}
		// The scheduler must also leave it alone even when its time is due.
		f.repo.db.Exec(`UPDATE pulse_items SET status='scheduled', publish_at = NOW() - interval '1 minute' WHERE id=$1`, it.ID)
		promoted, err := f.repo.PromoteDue(ctx, time.Now())
		if err != nil {
			t.Fatal(err)
		}
		for _, p := range promoted {
			if p.ID == it.ID {
				t.Error("scheduler published a future-dated item")
			}
		}
	})

	t.Run("only drafts can be deleted", func(t *testing.T) {
		d := f.create(cmsInput("1991-02-05", "global"))
		if err := f.repo.Delete(ctx, d.ID, f.author); err != nil {
			t.Fatalf("delete draft: %v", err)
		}
		if _, err := f.repo.Get(ctx, d.ID); !errors.Is(err, ErrPulseNotFound) {
			t.Errorf("deleted item still found: %v", err)
		}
		p := f.create(cmsInput("1991-02-06", "global"))
		f.must(p.ID, f.author, pulse.DoSubmit)
		if err := f.repo.Delete(ctx, p.ID, f.admin); ruleKind(err) != "state" {
			t.Errorf("deleting an in-review item: %s, want state", ruleKind(err))
		}
	})

	t.Run("list filters and pages", func(t *testing.T) {
		items, _, err := f.repo.List(ctx, PulseListFilter{Date: day}, 50, 0)
		if err != nil || len(items) < 3 {
			t.Fatalf("list by date: %d items err=%v", len(items), err)
		}
		published, _, _ := f.repo.List(ctx, PulseListFilter{Date: day, Status: "published"}, 50, 0)
		for _, it := range published {
			if it.Status != "published" {
				t.Errorf("status filter leaked %s", it.Status)
			}
		}
		page, more, _ := f.repo.List(ctx, PulseListFilter{Date: day}, 1, 0)
		if len(page) != 1 || !more {
			t.Errorf("paging: %d items more=%v", len(page), more)
		}
	})

	t.Run("staff: add by email, roles take effect, unknown email rejected", func(t *testing.T) {
		var email string
		f.repo.db.QueryRow(`SELECT email FROM users WHERE id = $1`, f.reviewer.UserID).Scan(&email)
		if err := f.repo.AddStaff(ctx, email, models.PulseRoleReviewer, f.admin.UserID); err != nil {
			t.Fatal(err)
		}
		if err := f.repo.AddStaff(ctx, email, models.PulseRoleReviewer, f.admin.UserID); err != nil {
			t.Errorf("adding twice should be a no-op: %v", err)
		}
		actor, err := f.repo.ActorFor(ctx, f.reviewer.UserID)
		if err != nil || !actor.Has(models.PulseRoleReviewer) || actor.Has(models.PulseRoleApprover) || actor.IsAdmin {
			t.Errorf("actor roles wrong: %+v err=%v", actor, err)
		}
		adminActor, _ := f.repo.ActorFor(ctx, f.admin.UserID)
		if !adminActor.IsAdmin || !adminActor.Has(models.PulseRoleApprover) {
			t.Error("admin should hold every role")
		}
		if err := f.repo.AddStaff(ctx, "nobody-here@test.invalid", models.PulseRoleEditor, f.admin.UserID); ruleKind(err) != "invalid" {
			t.Errorf("unknown email: %s, want invalid", ruleKind(err))
		}
		if err := f.repo.AddStaff(ctx, email, "boss", f.admin.UserID); ruleKind(err) != "invalid" {
			t.Errorf("unknown role: %s, want invalid", ruleKind(err))
		}
		members, _ := f.repo.ListStaff(ctx)
		var id int64
		for _, m := range members {
			if m.UserID == f.reviewer.UserID {
				id = m.ID
			}
		}
		if id == 0 {
			t.Fatal("added staff member not listed")
		}
		f.repo.RemoveStaff(ctx, id)
		if actor, _ = f.repo.ActorFor(ctx, f.reviewer.UserID); actor.Has(models.PulseRoleReviewer) {
			t.Error("role still present after removal")
		}
	})

	t.Run("analytics totals and per-item rows", func(t *testing.T) {
		var itemID int64
		f.repo.db.QueryRow(`SELECT id FROM pulse_items WHERE pulse_date = '1991-02-04' AND slot = 'global'`).Scan(&itemID)
		uid := f.author.UserID
		for _, ev := range []string{"open_item", "open_item", "read_complete", "save", "share"} {
			f.repo.db.Exec(`INSERT INTO pulse_events (user_id, item_id, event, created_at)
			                VALUES ($1,$2,$3,'1991-02-04 10:00:00+03')`, uid, itemID, ev)
		}
		for _, d := range []string{"1991-02-04", "1991-02-05"} {
			f.repo.db.Exec(`INSERT INTO pulse_events (user_id, event, created_at) VALUES ($1,'view_day',$2::timestamptz)`,
				uid, d+" 09:00:00+03")
		}
		a, err := f.repo.Analytics(ctx, "1991-02-04", "1991-02-05")
		if err != nil {
			t.Fatal(err)
		}
		if a.DayViews != 2 || a.ItemOpens != 2 || a.UniqueReaders != 1 || a.Saves != 1 || a.Shares != 1 {
			t.Errorf("totals wrong: %+v", a)
		}
		if a.ReadCompletion != 0.5 || a.ReturnRate != 1 {
			t.Errorf("rates wrong: completion=%v return=%v", a.ReadCompletion, a.ReturnRate)
		}
		if len(a.Items) == 0 || a.Items[0].ItemID != itemID || a.Items[0].Opens != 2 {
			t.Errorf("per-item rows wrong: %+v", a.Items)
		}
	})
}

func TestPulseRecipients(t *testing.T) {
	f := newCMSFixture(t)
	ctx := context.Background()
	db := f.repo.db

	// Four people with a device; the fixture's four users play them.
	// author: defaults · reviewer: Pulse master off · approver: "new" off · admin: "saved" off
	ids := []int64{f.author.UserID, f.reviewer.UserID, f.approver.UserID, f.admin.UserID}
	for i, id := range ids {
		if _, err := db.Exec(`INSERT INTO user_push_tokens (user_id, token, platform) VALUES ($1,$2,'ios')`,
			id, fmt.Sprintf("pulse-test-token-%d-%d", id, time.Now().UnixNano())); err != nil {
			t.Fatalf("token %d: %v", i, err)
		}
	}
	t.Cleanup(func() {
		for _, id := range ids {
			db.Exec(`DELETE FROM user_push_tokens WHERE user_id = $1`, id)
			db.Exec(`DELETE FROM user_notification_prefs WHERE user_id = $1`, id)
		}
	})
	set := func(id int64, col string) {
		db.Exec(`INSERT INTO user_notification_prefs (user_id) VALUES ($1) ON CONFLICT DO NOTHING`, id)
		if _, err := db.Exec(`UPDATE user_notification_prefs SET `+col+` = FALSE WHERE user_id = $1`, id); err != nil {
			t.Fatalf("set %s: %v", col, err)
		}
	}
	set(f.reviewer.UserID, "pulse_enabled")
	set(f.approver.UserID, "pulse_new_enabled")
	set(f.admin.UserID, "pulse_saved_enabled")

	has := func(list []int64, id int64) bool {
		for _, x := range list {
			if x == id {
				return true
			}
		}
		return false
	}
	got, err := f.repo.NewItemRecipients(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if !has(got, f.author.UserID) || !has(got, f.admin.UserID) {
		t.Errorf("default users should get new-item pushes: %v", got)
	}
	if has(got, f.reviewer.UserID) || has(got, f.approver.UserID) {
		t.Errorf("users with the Pulse master / new switch off must be skipped: %v", got)
	}

	// Savers: everyone saves the item; only people who still allow saved-item
	// changes (and Pulse overall) are returned.
	item := f.create(cmsInput("1991-03-01", "global"))
	f.must(item.ID, f.author, pulse.DoSubmit)
	f.must(item.ID, f.approver, pulse.DoApprove)
	f.must(item.ID, f.approver, pulse.DoPublish)
	for _, id := range ids {
		db.Exec(`INSERT INTO pulse_saves (user_id, item_id) VALUES ($1,$2)`, id, item.ID)
	}
	savers, err := f.repo.SaverRecipients(ctx, item.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !has(savers, f.author.UserID) || !has(savers, f.approver.UserID) {
		t.Errorf("author and approver should be told about changes: %v", savers)
	}
	if has(savers, f.reviewer.UserID) || has(savers, f.admin.UserID) {
		t.Errorf("master-off and saved-off users must be skipped: %v", savers)
	}
	// A user who did NOT save the item is never a saver recipient.
	db.Exec(`DELETE FROM pulse_saves WHERE user_id = $1 AND item_id = $2`, f.author.UserID, item.ID)
	savers, _ = f.repo.SaverRecipients(ctx, item.ID)
	if has(savers, f.author.UserID) {
		t.Error("someone who did not save the item must not be notified about it")
	}
}

func TestPulsePrefsRoundTrip(t *testing.T) {
	f := newCMSFixture(t)
	prefs := NewNotificationPrefsRepository(f.repo.db)
	uid := f.author.UserID
	t.Cleanup(func() { f.repo.db.Exec(`DELETE FROM user_notification_prefs WHERE user_id = $1`, uid) })

	p, err := prefs.GetOrDefault(uid)
	if err != nil {
		t.Fatal(err)
	}
	if !p.PulseEnabled || !p.PulseNewEnabled || !p.PulseUpdatesEnabled || !p.PulseCorrectionsEnabled || !p.PulseSavedEnabled {
		t.Errorf("Pulse switches should all default to on: %+v", p)
	}
	off := false
	p, err = prefs.Update(uid, PrefsMutation{PulseNewEnabled: &off, PulseSavedEnabled: &off})
	if err != nil {
		t.Fatal(err)
	}
	if p.PulseNewEnabled || p.PulseSavedEnabled || !p.PulseEnabled || !p.PulseUpdatesEnabled || !p.PulseCorrectionsEnabled {
		t.Errorf("only the two switches sent should change: %+v", p)
	}
	// Untouched, older settings are unaffected.
	if !p.PushEnabled || !p.LikesEnabled {
		t.Errorf("existing preferences changed by a Pulse update: %+v", p)
	}
}

func TestPulseStockSearch(t *testing.T) {
	f := newCMSFixture(t)
	ctx := context.Background()
	db := f.repo.db
	tag := fmt.Sprintf("%d", time.Now().UnixNano()%1_000_000)
	var id int64
	if err := db.QueryRow(`INSERT INTO stocks (ticker, exchange, name) VALUES ($1,'TEST',$2) RETURNING id`,
		"QZX"+tag, "Quartz 100% Holdings "+tag).Scan(&id); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Exec(`DELETE FROM stocks WHERE id = $1`, id) })

	byTicker, err := f.repo.SearchStocks(ctx, "qzx"+tag, 20)
	if err != nil || len(byTicker) != 1 || byTicker[0].ID != int(id) {
		t.Fatalf("ticker search (case-insensitive): %+v err=%v", byTicker, err)
	}
	byName, _ := f.repo.SearchStocks(ctx, "quartz 100% hold", 20)
	if len(byName) != 1 {
		t.Errorf("name search with a literal %%: %d results, want 1", len(byName))
	}
	if wild, _ := f.repo.SearchStocks(ctx, "100%", 20); len(wild) != 1 {
		t.Errorf("a percent sign must match literally, got %d results", len(wild))
	}
	if none, _ := f.repo.SearchStocks(ctx, "no-such-stock-"+tag, 20); len(none) != 0 {
		t.Errorf("unexpected results: %+v", none)
	}
}

package repositories

import (
	"context"
	"fmt"
	"testing"
	"time"

	"halalstocks/internal/models"
)

// Integration tests for job_runs (migration 0062) and the Pulse auto-draft
// repository. Run only when PULSE_TEST_DSN is set.

func TestJobRunClaim(t *testing.T) {
	db := openPulseTestDB(t)
	repo := NewJobRunRepository(db)
	ctx := context.Background()
	job := fmt.Sprintf("test_job_%d", time.Now().UnixNano())
	day := time.Date(2026, 11, 28, 0, 0, 0, 0, time.UTC)
	t.Cleanup(func() { db.Exec(`DELETE FROM job_runs WHERE job_name = $1`, job) })

	mustClaim := func(want bool, why string) JobRunKey {
		t.Helper()
		key, got, err := repo.Claim(ctx, job, day)
		if err != nil || got != want {
			t.Fatalf("%s: claim=%v err=%v, want %v", why, got, err, want)
		}
		return key
	}
	k := mustClaim(true, "first claim of the day")
	mustClaim(false, "second replica while running")
	if err := repo.Finish(ctx, k, JobRunFailed, "x"); err != nil {
		t.Fatal(err)
	}
	k = mustClaim(true, "retry after failure (attempt 2)")
	repo.Finish(ctx, k, JobRunFailed, "x")
	k = mustClaim(true, "retry after failure (attempt 3)")
	if k.Attempt != 3 {
		t.Fatalf("want attempt 3, got %d", k.Attempt)
	}
	repo.Finish(ctx, k, JobRunFailed, "x")
	mustClaim(false, "no 4th attempt")

	// A stale 'running' row is taken over, and the stale attempt's late
	// Finish must not overwrite the new attempt.
	db.Exec(`UPDATE job_runs SET status='running', started_at = NOW() - interval '3 hours' WHERE job_name=$1`, job)
	stale := k
	k = mustClaim(true, "stale running row")
	repo.Finish(ctx, stale, JobRunFailed, "late")
	var status string
	db.QueryRow(`SELECT status FROM job_runs WHERE job_name=$1`, job).Scan(&status)
	if status != JobRunRunning {
		t.Fatalf("late finish of a stale attempt overwrote the new one: %s", status)
	}
	repo.Finish(ctx, k, JobRunSucceeded, "ok")
	mustClaim(false, "done for the day")

	if _, ok, err := repo.ForceStart(ctx, job, day); err != nil || !ok {
		t.Fatalf("manual run after success: %v %v", ok, err)
	}
	if _, ok, _ := repo.ForceStart(ctx, job, day); ok {
		t.Fatal("manual run while running must be refused")
	}
	runs, err := repo.Recent(ctx, 50)
	if err != nil || len(runs) == 0 {
		t.Fatalf("recent: %v %v", runs, err)
	}
}

func TestPulseAutoDraftRepo(t *testing.T) {
	db := openPulseTestDB(t)
	repo := NewPulseAdminRepository(db)
	ctx := context.Background()
	date := "2031-01-0" + fmt.Sprint(time.Now().UnixNano()%9+1)
	t.Cleanup(func() { db.Exec(`DELETE FROM pulse_items WHERE pulse_date = $1`, date) })

	taken, err := repo.TakenSlots(ctx, date)
	if err != nil || len(taken) != 0 {
		t.Fatalf("empty day: %v %v", taken, err)
	}
	in := models.PulseItemInput{PulseDate: date, Slot: "sharia", Classification: "analysis", IsSensitive: true,
		TitleAr: "ع", TitleEn: "t", SummaryAr: "ع", SummaryEn: "s", DetailsAr: "ع", DetailsEn: "d",
		EvidenceAr: "ع", EvidenceEn: "e", SourceName: "UNMU Sharia screening"}
	it, err := repo.CreateAutoDraft(ctx, in)
	if err != nil {
		t.Fatal(err)
	}
	if it.Status != models.PulseStatusDraft || it.CreatedBy != nil {
		t.Errorf("want draft with no author, got status=%s createdBy=%v", it.Status, it.CreatedBy)
	}
	var note string
	var actor *int64
	db.QueryRow(`SELECT note, actor_id FROM pulse_item_events WHERE item_id=$1`, it.ID).Scan(&note, &actor)
	if note != AutoDraftNote || actor != nil {
		t.Errorf("change log: note=%q actor=%v", note, actor)
	}
	taken, _ = repo.TakenSlots(ctx, date)
	if !taken["sharia"] || len(taken) != 1 {
		t.Errorf("taken: %v", taken)
	}
}

func TestRecentShariahChanges(t *testing.T) {
	db := openPulseTestDB(t)
	repo := NewPulseAdminRepository(db)
	ticker := fmt.Sprintf("ZT%d", time.Now().UnixNano()%1000000)
	var stockID int64
	if err := db.QueryRow(`INSERT INTO stocks (ticker, exchange, name) VALUES ($1,'NASDAQ','Test Co') RETURNING id`,
		ticker).Scan(&stockID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Exec(`DELETE FROM stocks WHERE id = $1`, stockID) })
	today := time.Now().UTC().Format("2006-01-02")
	old := time.Now().UTC().AddDate(0, -1, 0).Format("2006-01-02")
	for _, r := range [][2]string{{"HALAL", old}, {"MIXED", today}} {
		if _, err := db.Exec(`INSERT INTO shariah_status (stock_id, status, as_of_date, reason) VALUES ($1,$2,$3,'debt up')`,
			stockID, r[0], r[1]); err != nil {
			t.Fatal(err)
		}
	}
	got, err := repo.RecentShariahChanges(context.Background(), time.Now().AddDate(0, 0, -7))
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, c := range got {
		if c.Ticker == ticker {
			found = c.From == "HALAL" && c.To == "MIXED" && c.Reason == "debt up"
		}
	}
	if !found {
		t.Fatalf("change for %s not found: %+v", ticker, got)
	}
}

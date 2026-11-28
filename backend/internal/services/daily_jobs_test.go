package services

import (
	"context"
	"errors"
	"testing"
	"time"

	"halalstocks/internal/repositories"
)

type fakeJobStore struct {
	claimed  map[string]bool
	finished map[string]string
	running  bool
}

func newFakeJobStore() *fakeJobStore {
	return &fakeJobStore{claimed: map[string]bool{}, finished: map[string]string{}}
}

func (f *fakeJobStore) Claim(_ context.Context, job string, day time.Time) (repositories.JobRunKey, bool, error) {
	k := job + day.Format("2006-01-02")
	key := repositories.JobRunKey{Job: job, Day: day, Attempt: 1}
	if f.claimed[k] {
		return key, false, nil
	}
	f.claimed[k] = true
	return key, true, nil
}

func (f *fakeJobStore) ForceStart(_ context.Context, job string, day time.Time) (repositories.JobRunKey, bool, error) {
	return repositories.JobRunKey{Job: job, Day: day, Attempt: 1}, !f.running, nil
}

func (f *fakeJobStore) Finish(_ context.Context, key repositories.JobRunKey, status, _ string) error {
	f.finished[key.Job] = status
	return nil
}

func TestIsDailyJobDue(t *testing.T) {
	at := func(h int) time.Time { return time.Date(2026, 11, 28, h, 30, 0, 0, time.UTC) }
	if isDailyJobDue(at(2), 3) {
		t.Error("02:30 must not run a 03:00 job")
	}
	if !isDailyJobDue(at(3), 3) || !isDailyJobDue(at(22), 3) {
		t.Error("at or after the hour (catch-up after sleep) must run")
	}
	// A Baghdad-time clock must be read in UTC.
	baghdad := time.Date(2026, 11, 28, 5, 0, 0, 0, time.FixedZone("B", 3*3600)) // 02:00 UTC
	if isDailyJobDue(baghdad, 3) {
		t.Error("due check must use UTC")
	}
}

func TestTickRunsDueJobsOnceInOrder(t *testing.T) {
	store := newFakeJobStore()
	r := NewDailyJobRunner(store)
	r.now = func() time.Time { return time.Date(2026, 11, 28, 4, 0, 0, 0, time.UTC) }
	var order []string
	add := func(name string, hour int) {
		r.Register(DailyJob{Name: name, HourUTC: hour, Run: func(context.Context) (string, error) {
			order = append(order, name)
			return "ok", nil
		}})
	}
	add(JobPulseAutodraft, 3)
	add(JobScreeningRefresh, 2)
	r.tick(context.Background())
	r.tick(context.Background()) // same day: no second run
	if len(order) != 2 || order[0] != JobScreeningRefresh || order[1] != JobPulseAutodraft {
		t.Fatalf("want screening then autodraft once, got %v", order)
	}
	if store.finished[JobPulseAutodraft] != "succeeded" {
		t.Errorf("finish not recorded: %v", store.finished)
	}
}

func TestFailedRunIsRecorded(t *testing.T) {
	store := newFakeJobStore()
	r := NewDailyJobRunner(store)
	r.now = func() time.Time { return time.Date(2026, 11, 28, 9, 0, 0, 0, time.UTC) }
	r.Register(DailyJob{Name: JobScreeningRefresh, HourUTC: 2, Run: func(context.Context) (string, error) {
		return "", errors.New("boom")
	}})
	r.tick(context.Background())
	if store.finished[JobScreeningRefresh] != "failed" {
		t.Fatalf("want failed, got %v", store.finished)
	}
}

func TestRunNow(t *testing.T) {
	store := newFakeJobStore()
	r := NewDailyJobRunner(store)
	ran := 0
	r.Register(DailyJob{Name: JobPulseAutodraft, HourUTC: 23, Run: func(context.Context) (string, error) {
		ran++
		return "done", nil
	}})
	if _, err := r.RunNow(context.Background(), "nope"); err == nil {
		t.Error("unknown job must error")
	}
	if got, err := r.RunNow(context.Background(), JobPulseAutodraft); err != nil || got != "done" || ran != 1 {
		t.Fatalf("run now ignores the hour: got %q %v ran=%d", got, err, ran)
	}
	store.running = true
	if _, err := r.RunNow(context.Background(), JobPulseAutodraft); err == nil {
		t.Error("must refuse while a run is in progress")
	}
}

// daily_jobs.go — runs each registered job once per UTC day, at or after
// its hour (docs/pulse/AUTODRAFT.md).
//
// Why in-process and not a Railway cron service: the jobs need the same
// config and repos as the API, and the job_runs row makes "once a day"
// safe across replicas. Railway may sleep the service when idle; the
// first tick after it wakes catches up a missed day.
package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"time"

	"halalstocks/internal/repositories"
)

// Job names, also used in job_runs.job_name and the admin "run now" URL.
const (
	JobScreeningRefresh = "screening_refresh"
	JobPulseAutodraft   = "pulse_autodraft"
)

// dailyJobOrder is the order jobs run in on one tick: the screening
// refresh first, so the drafts read today's verdicts.
var dailyJobOrder = []string{JobScreeningRefresh, JobPulseAutodraft, JobStoreRefunds}

// ErrJobAlreadyRunning is returned by RunNow while a run is in progress.
var ErrJobAlreadyRunning = errors.New("job is already running")

// dailyJobTick is how often the runner checks whether a job is due.
const dailyJobTick = 10 * time.Minute

// dailyJobTimeout caps a single run so a hung provider can't hold the day.
const dailyJobTimeout = 30 * time.Minute

// DailyJob is one job the runner owns. Run returns a short summary that
// is stored in job_runs.detail.
type DailyJob struct {
	Name    string
	HourUTC int
	Run     func(ctx context.Context) (string, error)
}

// jobRunStore is the slice of JobRunRepository the runner needs.
type jobRunStore interface {
	Claim(ctx context.Context, job string, day time.Time) (repositories.JobRunKey, bool, error)
	ForceStart(ctx context.Context, job string, day time.Time) (repositories.JobRunKey, bool, error)
	Finish(ctx context.Context, key repositories.JobRunKey, status, detail string) error
}

// DailyJobRunner ticks and starts due jobs.
type DailyJobRunner struct {
	store jobRunStore
	jobs  map[string]DailyJob
	now   func() time.Time
}

// NewDailyJobRunner returns a runner with no jobs.
func NewDailyJobRunner(store jobRunStore) *DailyJobRunner {
	return &DailyJobRunner{store: store, jobs: map[string]DailyJob{}, now: time.Now}
}

// Register adds a job. Call before Start.
func (r *DailyJobRunner) Register(j DailyJob) {
	r.jobs[j.Name] = j
}

// Names lists the registered job names.
func (r *DailyJobRunner) Names() []string {
	names := make([]string, 0, len(r.jobs))
	for n := range r.jobs {
		names = append(names, n)
	}
	return names
}

// isDailyJobDue reports whether a job with this hour may run at now (UTC).
func isDailyJobDue(now time.Time, hourUTC int) bool {
	return now.UTC().Hour() >= hourUTC
}

// utcDay is the calendar day (UTC midnight) the run belongs to.
func utcDay(now time.Time) time.Time {
	y, m, d := now.UTC().Date()
	return time.Date(y, m, d, 0, 0, 0, 0, time.UTC)
}

// Start launches the background loop; it returns at once.
func (r *DailyJobRunner) Start(ctx context.Context) {
	go func() {
		r.tick(ctx)
		t := time.NewTicker(dailyJobTick)
		defer t.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				r.tick(ctx)
			}
		}
	}()
}

// tick starts every due job that can claim today, in dailyJobOrder.
func (r *DailyJobRunner) tick(ctx context.Context) {
	now := r.now()
	for _, name := range dailyJobOrder {
		j, ok := r.jobs[name]
		if !ok || !isDailyJobDue(now, j.HourUTC) {
			continue
		}
		key, won, err := r.store.Claim(ctx, j.Name, utcDay(now))
		if err != nil {
			log.Printf("[daily-jobs] WARN %v", err)
			continue
		}
		if won {
			r.execute(ctx, j, key)
		}
	}
}

// RunNow runs a job immediately (admin "run now"). It returns an error if
// the job is unknown or already running.
func (r *DailyJobRunner) RunNow(ctx context.Context, name string) (string, error) {
	j, ok := r.jobs[name]
	if !ok {
		return "", fmt.Errorf("unknown job %q", name)
	}
	key, won, err := r.store.ForceStart(ctx, name, utcDay(r.now()))
	if err != nil {
		return "", err
	}
	if !won {
		return "", ErrJobAlreadyRunning
	}
	return r.execute(ctx, j, key)
}

// execute runs a claimed job and records the outcome.
func (r *DailyJobRunner) execute(ctx context.Context, j DailyJob, key repositories.JobRunKey) (string, error) {
	runCtx, cancel := context.WithTimeout(ctx, dailyJobTimeout)
	defer cancel()
	log.Printf("[daily-jobs] %s started for %s (attempt %d)", j.Name, key.Day.Format("2006-01-02"), key.Attempt)
	detail, err := j.Run(runCtx)
	status := repositories.JobRunSucceeded
	if err != nil {
		status = repositories.JobRunFailed
		detail = err.Error()
		CaptureError(err, map[string]string{"job": j.Name})
	}
	if ferr := r.store.Finish(context.Background(), key, status, detail); ferr != nil {
		log.Printf("[daily-jobs] WARN %v", ferr)
	}
	log.Printf("[daily-jobs] %s %s: %s", j.Name, status, detail)
	return detail, err
}

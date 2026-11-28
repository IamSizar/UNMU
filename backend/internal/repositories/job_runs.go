// job_runs: the once-per-day lock and history for the in-process daily
// jobs (migration 0062, docs/pulse/AUTODRAFT.md).
package repositories

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Job run statuses stored in job_runs.status.
const (
	JobRunRunning   = "running"
	JobRunSucceeded = "succeeded"
	JobRunFailed    = "failed"
)

// maxJobAttempts is how many times a daily run may be tried on one day.
const maxJobAttempts = 3

// staleJobAfter is how long a 'running' row may sit before another
// replica treats the run as dead (process restarted mid-run) and retakes it.
const staleJobAfter = "2 hours"

// JobRun is one row of job_runs.
type JobRun struct {
	ID         int64      `json:"id"`
	JobName    string     `json:"jobName"`
	RunDate    string     `json:"runDate"`
	Status     string     `json:"status"`
	Attempts   int        `json:"attempts"`
	Detail     string     `json:"detail"`
	StartedAt  time.Time  `json:"startedAt"`
	FinishedAt *time.Time `json:"finishedAt,omitempty"`
}

// JobRunRepository reads and writes job_runs.
type JobRunRepository struct {
	db *sql.DB
}

// NewJobRunRepository returns a repository on db.
func NewJobRunRepository(db *sql.DB) *JobRunRepository {
	return &JobRunRepository{db: db}
}

// JobRunKey identifies one attempt: Finish only updates the row while it
// still belongs to this attempt, so a stale run that finishes late cannot
// overwrite the run that took over from it.
type JobRunKey struct {
	Job     string
	Day     time.Time
	Attempt int
}

// claimSQL inserts the day's row, or retakes it when the WHERE allows.
// RETURNING yields no row when the existing row may not be retaken.
const claimSQL = `
	INSERT INTO job_runs (job_name, run_date, status)
	VALUES ($1, $2, 'running')
	ON CONFLICT (job_name, run_date) DO UPDATE
	   SET status = 'running', attempts = job_runs.attempts + 1,
	       detail = '', started_at = NOW(), finished_at = NULL
	 WHERE `

// Claim takes the (job, day) slot for a scheduled run. ok means run now:
// no row yet, the last attempt failed under the retry limit, or a
// 'running' row went stale. One atomic statement, so two replicas can
// never both win.
func (r *JobRunRepository) Claim(ctx context.Context, job string, day time.Time) (JobRunKey, bool, error) {
	return r.claim(ctx, claimSQL+`
	       (job_runs.status = 'failed' AND job_runs.attempts < $3)
	    OR (job_runs.status = 'running' AND job_runs.started_at < NOW() - $4::interval)
	RETURNING attempts`, []any{job, day.Format("2006-01-02"), maxJobAttempts, staleJobAfter})
}

// ForceStart claims the day for a manual "run now" from the dashboard. It
// wins unless a run is in progress (and not stale).
func (r *JobRunRepository) ForceStart(ctx context.Context, job string, day time.Time) (JobRunKey, bool, error) {
	return r.claim(ctx, claimSQL+`
	       job_runs.status <> 'running'
	    OR job_runs.started_at < NOW() - $3::interval
	RETURNING attempts`, []any{job, day.Format("2006-01-02"), staleJobAfter})
}

// claim runs a claim statement; args[0] is the job name, args[1] the day.
func (r *JobRunRepository) claim(ctx context.Context, query string, args []any) (JobRunKey, bool, error) {
	key := JobRunKey{Job: args[0].(string)}
	key.Day, _ = time.Parse("2006-01-02", args[1].(string))
	err := r.db.QueryRowContext(ctx, query, args...).Scan(&key.Attempt)
	if errors.Is(err, sql.ErrNoRows) {
		return key, false, nil
	}
	if err != nil {
		return key, false, fmt.Errorf("claiming job %s for %s: %w", key.Job, args[1], err)
	}
	return key, true, nil
}

// Finish records the outcome of a claimed attempt.
func (r *JobRunRepository) Finish(ctx context.Context, key JobRunKey, status, detail string) error {
	_, err := r.db.ExecContext(ctx, `
		UPDATE job_runs SET status = $3, detail = $4, finished_at = NOW()
		 WHERE job_name = $1 AND run_date = $2 AND attempts = $5 AND status = 'running'`,
		key.Job, key.Day.Format("2006-01-02"), status, detail, key.Attempt)
	if err != nil {
		return fmt.Errorf("finishing job %s: %w", key.Job, err)
	}
	return nil
}

// Recent lists the latest runs, newest first.
func (r *JobRunRepository) Recent(ctx context.Context, limit int) ([]JobRun, error) {
	rows, err := r.db.QueryContext(ctx, `
		SELECT id, job_name, run_date::text, status, attempts, detail, started_at, finished_at
		  FROM job_runs ORDER BY started_at DESC LIMIT $1`, limit)
	if err != nil {
		return nil, fmt.Errorf("listing job runs: %w", err)
	}
	defer rows.Close()
	runs := []JobRun{}
	for rows.Next() {
		var jr JobRun
		var fin sql.NullTime
		if err := rows.Scan(&jr.ID, &jr.JobName, &jr.RunDate, &jr.Status,
			&jr.Attempts, &jr.Detail, &jr.StartedAt, &fin); err != nil {
			return nil, fmt.Errorf("scanning job run: %w", err)
		}
		if fin.Valid {
			jr.FinishedAt = &fin.Time
		}
		runs = append(runs, jr)
	}
	return runs, rows.Err()
}

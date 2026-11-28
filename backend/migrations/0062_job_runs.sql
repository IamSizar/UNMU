-- 0062_job_runs.sql — one row per (daily job, day) so a job runs once a day.
--
-- Used by the in-process daily job runner (screening refresh, Pulse
-- auto-draft). The UNIQUE (job_name, run_date) row is the lock: several
-- replicas can tick at the same time and only one claims the day. A failed
-- run is retried (attempts < 3); a run stuck in 'running' for 2 hours is
-- taken over. See docs/pulse/AUTODRAFT.md.
BEGIN;

CREATE TABLE IF NOT EXISTS job_runs (
    id           BIGSERIAL   PRIMARY KEY,
    job_name     TEXT        NOT NULL CHECK (length(btrim(job_name)) > 0),
    run_date     DATE        NOT NULL,
    status       TEXT        NOT NULL
                 CHECK (status IN ('running', 'succeeded', 'failed')),
    attempts     INTEGER     NOT NULL DEFAULT 1 CHECK (attempts >= 1),
    detail       TEXT        NOT NULL DEFAULT '',
    started_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at  TIMESTAMPTZ,
    UNIQUE (job_name, run_date)
);

CREATE INDEX IF NOT EXISTS idx_job_runs_started_at
    ON job_runs (started_at DESC);

COMMIT;

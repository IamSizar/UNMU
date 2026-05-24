-- 0047_transcode_jobs.sql
--
-- Persistent work queue for the FFmpeg transcode worker (the in-app video
-- "quality" gear). One row per video/reel post. The worker sweeps for
-- video posts that have a source media_url but no variants yet, enqueues a
-- row here, then claims + processes them. Persisting the queue means jobs
-- survive a backend restart and a permanently-broken source video stops
-- retrying after `attempts` hits the cap (instead of looping forever).
--
--   status: 'pending' | 'running' | 'done' | 'failed'
CREATE TABLE IF NOT EXISTS transcode_jobs (
    post_id    BIGINT PRIMARY KEY REFERENCES posts(id) ON DELETE CASCADE,
    source_url TEXT        NOT NULL,
    status     TEXT        NOT NULL DEFAULT 'pending',
    attempts   INT         NOT NULL DEFAULT 0,
    error      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transcode_jobs_status
    ON transcode_jobs (status, created_at);

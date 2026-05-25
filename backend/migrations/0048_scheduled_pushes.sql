-- 0048_scheduled_pushes.sql
--
-- Admin "schedule / countdown" push notifications. An admin picks a future
-- time (days/hours/minutes/seconds from now) in the dashboard; the row is
-- stored here and a background sender (services/scheduled_push_sender.go)
-- fires it via FCM when send_at passes. Survives a dashboard close / laptop
-- sleep because it lives server-side, not in a browser timer.
--
--   status: 'pending' | 'sending' | 'sent' | 'failed' | 'cancelled'
--   target: all | ios | android | web | user | role | community
CREATE TABLE IF NOT EXISTS scheduled_pushes (
    id            BIGSERIAL PRIMARY KEY,
    title         TEXT        NOT NULL,
    body          TEXT        NOT NULL,
    data          JSONB,
    target        TEXT        NOT NULL DEFAULT 'all',
    user_id       BIGINT,
    role          TEXT,
    community_id  TEXT,
    send_at       TIMESTAMPTZ NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'pending',
    success_count INT         NOT NULL DEFAULT 0,
    failure_count INT         NOT NULL DEFAULT 0,
    recipients    INT         NOT NULL DEFAULT 0,
    error         TEXT,
    created_by    BIGINT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    sent_at       TIMESTAMPTZ
);

-- The sender scans only pending rows that are due — keep that cheap.
CREATE INDEX IF NOT EXISTS idx_scheduled_pushes_due
    ON scheduled_pushes (status, send_at);

-- 0060_push_send_log.sql — record every admin "send now" push.
--
-- The dashboard's "Recent sends" list showed hard-coded sample rows (fake
-- audiences and open rates) because nothing recorded sends. One row per
-- POST /api/admin/push/send; read by GET /api/admin/push/history.
BEGIN;

CREATE TABLE IF NOT EXISTS push_send_log (
    id             BIGSERIAL PRIMARY KEY,
    title          TEXT        NOT NULL,
    body           TEXT        NOT NULL,
    target         TEXT        NOT NULL,
    recipients     INTEGER     NOT NULL CHECK (recipients >= 0),
    success_count  INTEGER     NOT NULL CHECK (success_count >= 0),
    failure_count  INTEGER     NOT NULL CHECK (failure_count >= 0),
    send_error     TEXT,
    sent_by        BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_send_log_created_at
    ON push_send_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_send_log_sent_by
    ON push_send_log (sent_by);

COMMIT;

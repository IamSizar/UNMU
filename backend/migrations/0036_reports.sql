-- User-submitted abuse / safety reports. One row per report. Required for
-- App Store + Play Store policy (users must have a way to report
-- objectionable content).
--
-- target_type is a free-form string so we can extend without DDL changes:
--   post       — a Post row (article / video / reel)
--   user       — another User row
--   comment    — a comment on a post (id refs post_comments.id)
--   community  — a Community row
--   message    — a community chat message
--
-- target_id is TEXT because some targets are int64 PKs and others are
-- UUIDs (expert_id, post_id is bigserial → store as string for one shape).
CREATE TABLE IF NOT EXISTS reports (
    id              BIGSERIAL PRIMARY KEY,
    reporter_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type     VARCHAR(32)  NOT NULL,
    target_id       TEXT         NOT NULL,
    reason          VARCHAR(64)  NOT NULL,
    details         TEXT,

    -- Lifecycle: open → resolved_action_taken | resolved_no_action | dismissed
    status          VARCHAR(32)  NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open',
                                      'resolved_action_taken',
                                      'resolved_no_action',
                                      'dismissed')),
    resolved_by     BIGINT       REFERENCES users(id) ON DELETE SET NULL,
    resolved_at     TIMESTAMPTZ,
    resolution_note TEXT,

    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- Admin queue queries hit (status, created_at).
CREATE INDEX IF NOT EXISTS idx_reports_status_created_at
    ON reports (status, created_at DESC);

-- Drill-in by target: "show me every report about this user / post".
CREATE INDEX IF NOT EXISTS idx_reports_target
    ON reports (target_type, target_id);

-- Optional dedupe guard — keep ONE open report per (reporter, target)
-- so a user can't spam-flag the same thing while it's still in queue.
CREATE UNIQUE INDEX IF NOT EXISTS uniq_reports_open_per_reporter_target
    ON reports (reporter_id, target_type, target_id)
    WHERE status = 'open';

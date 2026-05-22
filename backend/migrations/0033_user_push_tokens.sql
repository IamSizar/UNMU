-- 0033_user_push_tokens.sql
--
-- Per-device push notification tokens. Multiple rows per user (one
-- device per row). The token itself is globally unique — Apple / Google
-- guarantee no collisions across installs — so we upsert by token, not
-- by (user, platform). This lets a device follow its user across
-- sign-in / sign-out cycles without leaking stale rows.

CREATE TABLE IF NOT EXISTS user_push_tokens (
    id          BIGSERIAL PRIMARY KEY,
    user_id     BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token       TEXT        NOT NULL UNIQUE,
    platform    VARCHAR(16) NOT NULL,    -- 'ios' | 'android' | 'web'
    last_seen   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Fast lookup of all tokens for a single user (e.g. send-to-self
-- notifications, mute-on-device flows).
CREATE INDEX IF NOT EXISTS idx_push_tokens_user_id ON user_push_tokens (user_id);

-- Fast "give me all tokens" for admin broadcast — last_seen DESC so
-- the most-recently-active devices win during paginated send batches.
CREATE INDEX IF NOT EXISTS idx_push_tokens_last_seen ON user_push_tokens (last_seen DESC);

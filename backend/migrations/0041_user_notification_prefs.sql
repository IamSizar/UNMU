-- Per-user notification preferences. One row per user; created lazily
-- on first read (the API helper inserts a defaults row when a user
-- hasn't touched their settings yet).
--
-- Categories chosen to roughly mirror the user-facing notification
-- "kinds" the inbox already produces:
--   * likes_enabled         — "X liked your post"
--   * comments_enabled      — "X commented on your post"
--   * subscriptions_enabled — paid expert / community subscription
--                             lifecycle (accepted / rejected / expired)
--   * communities_enabled   — community invitations + member changes
--   * marketing_enabled     — promo / announcement broadcasts
--                             (opt-in by default per App-Store policy)
--
-- The master `push_enabled` flag is the global kill switch — when it's
-- false the admin broadcast endpoint filters this user out, and the
-- per-user senders should short-circuit before queuing a push.
CREATE TABLE IF NOT EXISTS user_notification_prefs (
    user_id               BIGINT PRIMARY KEY
                          REFERENCES users(id) ON DELETE CASCADE,
    push_enabled          BOOLEAN NOT NULL DEFAULT TRUE,
    email_enabled         BOOLEAN NOT NULL DEFAULT TRUE,

    likes_enabled         BOOLEAN NOT NULL DEFAULT TRUE,
    comments_enabled      BOOLEAN NOT NULL DEFAULT TRUE,
    subscriptions_enabled BOOLEAN NOT NULL DEFAULT TRUE,
    communities_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
    marketing_enabled     BOOLEAN NOT NULL DEFAULT FALSE,

    updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

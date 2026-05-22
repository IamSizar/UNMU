-- =============================================================================
-- Step-7 — bookmark / save posts.
--
-- Mirrors the post_likes table shape but with no count column on posts (the
-- saved count isn't shown publicly anywhere in the UI). Just a (post, user)
-- pair so we can quickly answer "is this saved by me" and list the user's
-- saved posts.
--
-- No NOTIFY trigger — saving is private, doesn't need realtime fan-out.
--
-- Idempotent.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS post_saves (
    post_id    BIGINT      NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    user_id    BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (post_id, user_id)
);

-- For the saved-posts list, sort by when the user saved it (newest first)
-- — that's what humans expect from a bookmarks list.
CREATE INDEX IF NOT EXISTS post_saves_user_idx
    ON post_saves(user_id, created_at DESC);

COMMIT;

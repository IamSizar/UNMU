-- =============================================================================
-- 0020 — Post authoring v2 (audit items 4.15 / 4.16 / 4.18)
--
-- Three orthogonal additions, one migration:
--
--   4.15  drafts + scheduling
--         posts.status: 'draft' | 'scheduled' | 'published' (CHECK)
--         posts.publish_at: NULL except when status='scheduled'
--         partial index over scheduled rows so the publisher tick is O(scheduled)
--         not O(posts).
--
--   4.16  edit history
--         post_versions: a snapshot per edit. Auto-written by the
--         UpdateExpertPost handler. Owner + admin can read.
--
--   4.18  inline image attachments
--         post_attachments: many-to-one against posts. Each row holds a
--         /uploads/images/<x>.jpg URL + a sort_order. UI caps at 5 per
--         article.
--
-- 4.17 (markdown rendering) is a client-side change — no schema needed
-- since `posts.body` is already TEXT.
--
-- Idempotent: every column / table / index uses IF NOT EXISTS.
-- =============================================================================

-- ── 4.15 drafts + scheduling ──────────────────────────────────────────
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS status     TEXT NOT NULL DEFAULT 'published',
    ADD COLUMN IF NOT EXISTS publish_at TIMESTAMPTZ;

-- Add the CHECK in a separate step so re-running doesn't fail on the
-- already-present constraint. We drop and re-add to make the script
-- idempotent across partially-applied databases.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'posts_status_check'
    ) THEN
        ALTER TABLE posts
            ADD CONSTRAINT posts_status_check
            CHECK (status IN ('draft','scheduled','published'));
    END IF;
END$$;

-- Partial index — only scheduled rows. The publisher tick scans this
-- (typically ≤ a few rows) instead of the full posts table.
CREATE INDEX IF NOT EXISTS idx_posts_scheduled
    ON posts (publish_at) WHERE status = 'scheduled';

-- Index for the studio's drafts list — author + status hits the
-- studio's "show me my drafts" query directly.
CREATE INDEX IF NOT EXISTS idx_posts_author_status
    ON posts (author_id, status, created_at DESC);

-- ── 4.16 edit history ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS post_versions (
    id          BIGSERIAL PRIMARY KEY,
    post_id     BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    -- editor_id may NULL out if the user is later deleted, but the
    -- version row stays so the audit trail isn't lost.
    editor_id   BIGINT REFERENCES users(id) ON DELETE SET NULL,
    title       TEXT,
    body        TEXT NOT NULL,
    tickers     JSONB NOT NULL DEFAULT '[]'::jsonb,
    edited_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_post_versions_post
    ON post_versions (post_id, edited_at DESC);

-- ── 4.18 inline image attachments ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS post_attachments (
    id          BIGSERIAL PRIMARY KEY,
    post_id     BIGINT NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    url         TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_post_attachments_post
    ON post_attachments (post_id, sort_order);

-- =============================================================================
-- 0021 — Chat v2 (audit items 5.16 / 5.17 / 5.18 / 5.19 / 5.21 / 5.22)
--
-- Six features in one migration. Realtime / typing-indicators (5.19)
-- have no DB footprint — they're WS-only events.
--
--   5.16  Inline $TICKER cards          — no schema change. Server still
--                                          stores plain text; client
--                                          parses + renders below the
--                                          bubble. Listed here so the
--                                          migration log mentions every
--                                          item.
--
--   5.17  Chat search (per community)   — GIN index on a tsvector over
--                                          community_messages.body. Body
--                                          column itself untouched.
--
--   5.18  Read receipts                 — community_message_reads join
--                                          table + per-user opt-out
--                                          (users.read_receipts_enabled).
--
--   5.19  Typing indicators             — no schema change.
--
--   5.21  Chat polls                    — community_polls,
--                                          community_poll_options,
--                                          community_poll_votes.
--                                          Polls hang off a chat message
--                                          so they appear inline in the
--                                          stream.
--
--   5.22  Edit own message              — community_messages.edited_at +
--                                          original_body for diff.
-- =============================================================================

-- ── 5.17 search index ──────────────────────────────────────────────
-- 'simple' (no stemming) keeps `$AAPL` and Arabic words searchable
-- without language assumptions. GIN over the generated tsvector.
ALTER TABLE community_messages
    ADD COLUMN IF NOT EXISTS search_tsv tsvector
    GENERATED ALWAYS AS (
        to_tsvector('simple', COALESCE(body, ''))
    ) STORED;

CREATE INDEX IF NOT EXISTS idx_community_messages_search_tsv
    ON community_messages USING GIN (search_tsv);

-- pg_trgm enables substring search beyond tsvector token boundaries
-- (e.g. partial cashtags). Best-effort — if the role lacks CREATE
-- EXTENSION we fall back to FTS-only and the trigram index is skipped.
DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
EXCEPTION WHEN insufficient_privilege THEN
    NULL;
END$$;

-- Trigram index, only created when pg_trgm is actually present.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm') THEN
        CREATE INDEX IF NOT EXISTS idx_community_messages_body_trgm
            ON community_messages USING GIN (body gin_trgm_ops);
    END IF;
END$$;

-- ── 5.18 read receipts ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_message_reads (
    message_id BIGINT NOT NULL REFERENCES community_messages(id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    read_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (message_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_community_message_reads_user
    ON community_message_reads (user_id, read_at DESC);

-- Per-user opt-out. Default TRUE — receipts visible to everyone unless
-- the user explicitly turns them off. When OFF: this user's reads stop
-- being recorded AND their own messages stop showing receipts (mutual
-- reciprocity, matches WhatsApp / Signal semantics).
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS read_receipts_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- ── 5.21 polls ─────────────────────────────────────────────────────
-- A poll hangs off a host community_message — the bubble rendering
-- pulls the poll record by message_id and the message body becomes the
-- "context" line above the question (often empty).
CREATE TABLE IF NOT EXISTS community_polls (
    id            BIGSERIAL PRIMARY KEY,
    message_id    BIGINT NOT NULL UNIQUE
                  REFERENCES community_messages(id) ON DELETE CASCADE,
    community_id  TEXT NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    author_id     BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    question      TEXT   NOT NULL,
    is_anonymous  BOOLEAN NOT NULL DEFAULT FALSE,
    closed_at     TIMESTAMPTZ,
    expires_at    TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_community_polls_community
    ON community_polls (community_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_polls_expiring
    ON community_polls (expires_at)
    WHERE closed_at IS NULL AND expires_at IS NOT NULL;

CREATE TABLE IF NOT EXISTS community_poll_options (
    id          BIGSERIAL PRIMARY KEY,
    poll_id     BIGINT NOT NULL REFERENCES community_polls(id) ON DELETE CASCADE,
    label       TEXT NOT NULL,
    sort_order  INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX IF NOT EXISTS idx_community_poll_options_poll
    ON community_poll_options (poll_id, sort_order);

-- One vote per user per poll (D13=A). Voting again replaces the
-- previous vote via DELETE + INSERT in the handler.
CREATE TABLE IF NOT EXISTS community_poll_votes (
    poll_id    BIGINT NOT NULL REFERENCES community_polls(id) ON DELETE CASCADE,
    option_id  BIGINT NOT NULL REFERENCES community_poll_options(id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    voted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (poll_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_community_poll_votes_option
    ON community_poll_votes (option_id);

-- ── 5.22 edit own message ──────────────────────────────────────────
-- edited_at: NULL for never-edited rows so the client trivially flips
-- the "edited" pill.
-- original_body: snapshot of the body BEFORE the first edit. Used by
-- the admin dashboard to compare the current body against the original
-- for moderation. Subsequent edits don't update it (we keep the
-- original-original).
ALTER TABLE community_messages
    ADD COLUMN IF NOT EXISTS edited_at     TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS original_body TEXT;

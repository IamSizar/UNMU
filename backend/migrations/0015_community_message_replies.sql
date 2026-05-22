-- =============================================================================
-- 0015 — Reply support for community messages.
--
-- Adds `parent_id` so a message can quote / reply to another message
-- in the same community. Self-referential FK with ON DELETE SET NULL
-- so a deleted parent doesn't take its replies down (the reply just
-- loses its quote preview).
--
-- An index on parent_id is intentionally omitted — replies are not
-- queried by parent in the chat list (we always read newest-first
-- per community); the JOIN we use to render quote previews uses
-- the PK on the parent row directly.
--
-- Idempotent — `IF NOT EXISTS` so re-running is a no-op.
-- =============================================================================

BEGIN;

ALTER TABLE community_messages
  ADD COLUMN IF NOT EXISTS parent_id BIGINT
    REFERENCES community_messages(id) ON DELETE SET NULL;

COMMIT;

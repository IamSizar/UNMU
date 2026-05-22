-- 0018_community_message_pinned.sql
--
-- "Pin a message" feature for community owners. Adds a single
-- nullable `pinned_at` timestamp to community_messages — non-null =
-- pinned, with the timestamp doubling as the ordering key (newest
-- pin floats to the top of the pinned bar).
--
-- Why a column instead of a separate `pinned_messages` table:
--   * One message can be pinned at most (state is per-row, no
--     many-to-many),
--   * Reads always need to know "is this message pinned" — keeping
--     it on the same row avoids a JOIN on every list call,
--   * The existing chat broadcast carries the message struct so
--     toggling pin/unpin is just a regular row patch + WS event.
--
-- We don't enforce "only the community owner can pin" at the schema
-- level — that's the handler's job (it has access to user role +
-- community.owner_id).

ALTER TABLE community_messages
  ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMPTZ;

-- Partial index — only pinned rows. Keeps the index small (most
-- messages will never be pinned) while still making the "list pinned
-- messages in this community" query a fast index scan.
CREATE INDEX IF NOT EXISTS idx_community_messages_pinned
  ON community_messages(community_id, pinned_at DESC)
  WHERE pinned_at IS NOT NULL;

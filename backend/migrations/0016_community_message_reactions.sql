-- 0016_community_message_reactions.sql
--
-- Per-message emoji reactions for community chat. Long-pressing a
-- message on mobile opens a floating action bar with the recommended
-- emoji set (👏 👍 👎 🔥) plus Reply / Copy. Each row here = one
-- (user, emoji) pair on a given message.
--
-- PK is the (message_id, user_id, emoji) triplet so:
--   * a single user can stack multiple distinct emojis on one message
--     (e.g. 👍 + 🔥),
--   * but tapping the same emoji twice is a no-op insert — the toggle
--     handler reads first and chooses INSERT vs DELETE.
--
-- ON DELETE CASCADE on both FKs so a deleted message / deleted user
-- doesn't leave orphan reaction rows.

CREATE TABLE IF NOT EXISTS community_message_reactions (
  message_id BIGINT      NOT NULL REFERENCES community_messages(id) ON DELETE CASCADE,
  user_id    BIGINT      NOT NULL REFERENCES users(id)              ON DELETE CASCADE,
  emoji      TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (message_id, user_id, emoji)
);

-- Index for the per-message aggregation hit on every chat list call —
-- "give me all reaction rows for the last 50 messages" walks this.
CREATE INDEX IF NOT EXISTS idx_community_message_reactions_msg
  ON community_message_reactions(message_id);

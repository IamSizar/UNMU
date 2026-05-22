-- 0017_community_message_attachments.sql
--
-- Voice messages in community chat. We extend the existing
-- community_messages row with three optional attachment columns
-- instead of building a side table — every message can carry at
-- most one attachment, so a 1:1 column expansion is the simplest
-- shape and keeps the read-path JOIN-free.
--
-- attachment_type is a free TEXT today ('audio' is the only value),
-- left open so future feature work can drop in 'image' / 'video'
-- without another migration.

ALTER TABLE community_messages
  ADD COLUMN IF NOT EXISTS attachment_url         TEXT,
  ADD COLUMN IF NOT EXISTS attachment_type        TEXT,
  ADD COLUMN IF NOT EXISTS attachment_duration_ms INT;

-- A message must have either a non-empty body OR an attachment
-- (or both). Without this guard you could insert a row with empty
-- text and no audio and the chat screen would render an awkward
-- empty bubble.
ALTER TABLE community_messages DROP CONSTRAINT IF EXISTS community_messages_body_or_attachment;
ALTER TABLE community_messages
  ADD CONSTRAINT community_messages_body_or_attachment
  CHECK (
    (body IS NOT NULL AND length(body) > 0)
    OR (attachment_url IS NOT NULL AND length(attachment_url) > 0)
  );

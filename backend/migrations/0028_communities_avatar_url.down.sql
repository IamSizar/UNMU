-- Reverse of 0028 — drop the avatar_url column.
ALTER TABLE communities
    DROP COLUMN IF EXISTS avatar_url;

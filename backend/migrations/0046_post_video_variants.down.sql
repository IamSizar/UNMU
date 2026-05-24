-- Down: drop the per-post video quality variants column.
ALTER TABLE posts
    DROP COLUMN IF EXISTS video_variants;

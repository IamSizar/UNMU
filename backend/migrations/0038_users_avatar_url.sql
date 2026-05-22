-- Adds the user-profile avatar URL column. Today the Flutter app stores
-- the avatar path in SharedPreferences (local-only), which means new
-- devices see no avatar. Once Phase 2.4 ships, the upload flow writes
-- to S3 and stores the public URL here so the avatar persists across
-- installs / devices.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- =============================================================================
-- 0028 — Community avatars.
--
-- Up to now `communities.cover_url` was the only image associated with a
-- community: a wide banner shown at the top of the community detail
-- page. Lists / cards rendered an auto-generated initials tile because
-- there was no compact identity image.
--
-- Adds a separate, nullable `avatar_url` so admins + owners can upload
-- a square logo distinct from the cover. When null, the UI falls back
-- to the initials tile (with a contrast fix for region-tinted bgs).
-- =============================================================================

ALTER TABLE communities
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;

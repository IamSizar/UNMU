-- Reverse of 0027 — restore NOT NULL on communities.region_code.
--
-- Any rows that were created via the proposal flow with a NULL region
-- would block the constraint, so backfill them with 'GLOBAL' first.
-- 'GLOBAL' is the same default used by the Discover screen's "Global"
-- pill, so existing communities stay visible in that bucket.

UPDATE communities SET region_code = 'GLOBAL' WHERE region_code IS NULL;

ALTER TABLE communities
    ALTER COLUMN region_code SET NOT NULL;

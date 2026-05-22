-- =============================================================================
-- 0027 — Make `communities.region_code` nullable.
--
-- The community-proposals flow (migration 0011) lets an expert pick
-- "No specific region" — submitted as empty string, written as NULL via
-- `NULLIF($1, '')` in the approve repo. The communities table was
-- created in 0001 with `region_code TEXT NOT NULL`, which rejected those
-- inserts with:
--
--     pq: null value in column "region_code" of relation "communities"
--     violates not-null constraint (23502)
--
-- Every read path in the codebase already treats region_code as
-- optionally null (`COALESCE(region_code, '')` in the social repo, the
-- admin dashboard list shows `—` for empty, the proposal repo writes
-- via NULLIF). Dropping the NOT NULL aligns the schema with how the
-- rest of the system already behaves.
-- =============================================================================

ALTER TABLE communities
    ALTER COLUMN region_code DROP NOT NULL;

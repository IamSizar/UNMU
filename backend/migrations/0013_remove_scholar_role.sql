-- =============================================================================
-- 0013 — Remove the SCHOLAR role.
--
-- Decision: scholar and expert had the same backend powers — same posting,
-- subscriptions, community ownership. The split was purely semantic
-- (religious authority vs financial analyst). We're collapsing them
-- into a single EXPERT role to simplify the system.
--
-- What this migration does:
--
--   1. Promotes every user with role='SCHOLAR' to role='EXPERT'.
--   2. Promotes every experts.tier='scholar' row to tier='expert'.
--   3. Drops + recreates the role check constraint without the SCHOLAR option.
--   4. Drops + recreates the experts tier check constraint without 'scholar'.
--
-- Idempotent — re-running produces zero changes once applied.
-- =============================================================================

BEGIN;

-- ── 1. Promote every SCHOLAR user → EXPERT ────────────────────────
UPDATE users
   SET role = 'EXPERT',
       updated_at = NOW()
 WHERE role = 'SCHOLAR';

-- ── 2. Promote every scholar tier → expert tier ───────────────────
UPDATE experts
   SET tier = 'expert',
       updated_at = NOW()
 WHERE tier = 'scholar';

-- ── 3. Recreate users.role check constraint without SCHOLAR ───────
-- Drop unconditionally (handles re-runs cleanly because DROP IF EXISTS).
ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
  ADD CONSTRAINT users_role_check
  CHECK (role = ANY (ARRAY['USER', 'EXPERT', 'ADMIN']));

-- ── 4. Recreate experts.tier check constraint without 'scholar' ──
ALTER TABLE experts DROP CONSTRAINT IF EXISTS experts_tier_check;
ALTER TABLE experts
  ADD CONSTRAINT experts_tier_check
  CHECK (tier = ANY (ARRAY['expert']));

COMMIT;

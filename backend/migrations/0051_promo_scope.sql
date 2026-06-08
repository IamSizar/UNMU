-- 0051_promo_scope.sql
--
-- Promo-code targeting. A code can now be limited to a kind of purchase:
--   'all'       — applies to any subscription (default; previous behaviour)
--   'expert'    — only expert subscriptions
--   'community' — only community subscriptions
--
-- The validate/redeem endpoints check this against the purchase context so a
-- community-only code can't be used on an expert sub, and vice-versa.
ALTER TABLE promo_codes
    ADD COLUMN IF NOT EXISTS scope TEXT NOT NULL DEFAULT 'all';

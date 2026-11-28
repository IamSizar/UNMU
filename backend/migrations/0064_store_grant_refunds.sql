-- 0064_store_grant_refunds.sql — refunds of tier purchases.
--
-- Each grant now records exactly what it added, so a refund can take back
-- only the unused part of that purchase:
--   subscription_id  the expert_subscriptions / community_subscriptions row
--                    (per target_type) the grant extended or opened;
--   period_start/end the span of access the grant added to that row.
-- refunded_at is set once a refund was applied (makes refunds idempotent).
-- Grants from before this migration (none in production) keep NULLs and
-- a refund only marks them. See docs/payments/REFUNDS_PLAN.md.
BEGIN;

ALTER TABLE store_access_grants
    ADD COLUMN IF NOT EXISTS subscription_id BIGINT,
    ADD COLUMN IF NOT EXISTS period_start    TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS period_end      TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS refunded_at     TIMESTAMPTZ;

ALTER TABLE store_access_grants DROP CONSTRAINT IF EXISTS store_access_grants_period_check;
ALTER TABLE store_access_grants ADD CONSTRAINT store_access_grants_period_check
    CHECK (period_end IS NULL OR period_start IS NULL OR period_end > period_start);

CREATE INDEX IF NOT EXISTS idx_store_access_grants_subscription
    ON store_access_grants (target_type, subscription_id);

COMMIT;

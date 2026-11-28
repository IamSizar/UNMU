-- Reverts 0064_store_grant_refunds.sql.
BEGIN;
DROP INDEX IF EXISTS idx_store_access_grants_subscription;
ALTER TABLE store_access_grants DROP CONSTRAINT IF EXISTS store_access_grants_period_check;
ALTER TABLE store_access_grants
    DROP COLUMN IF EXISTS refunded_at,
    DROP COLUMN IF EXISTS period_end,
    DROP COLUMN IF EXISTS period_start,
    DROP COLUMN IF EXISTS subscription_id;
COMMIT;

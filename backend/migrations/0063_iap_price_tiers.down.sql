-- Reverts 0063_iap_price_tiers.sql. Tier prices written into the
-- *_price_cents columns are kept (the old free prices are not restored).
-- Fails if a community subscription was paid through a store; remove
-- those rows first.
BEGIN;
DROP TABLE IF EXISTS store_access_grants;
ALTER TABLE community_subscriptions
    DROP CONSTRAINT IF EXISTS community_subscriptions_payment_method_check;
ALTER TABLE community_subscriptions
    ADD CONSTRAINT community_subscriptions_payment_method_check
    CHECK (payment_method IN ('cash', 'fib'));
ALTER TABLE communities DROP CONSTRAINT IF EXISTS communities_price_tier_check;
ALTER TABLE experts DROP CONSTRAINT IF EXISTS experts_price_tier_check;
ALTER TABLE communities DROP COLUMN IF EXISTS price_tier;
ALTER TABLE experts DROP COLUMN IF EXISTS price_tier;
COMMIT;

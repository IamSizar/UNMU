-- 0063_iap_price_tiers.sql — subscriptions move to in-app purchase only.
--
-- Experts and paid communities now pick one of four fixed price tiers
-- (t1..t4) instead of a free price, because each tier is one store product
-- (com.unmu.access.<tier>.<month|year>) created once in App Store Connect
-- and Play Console. The *_price_cents columns stay and always hold the
-- tier's price, so existing reads (payouts, display) keep working.
-- Existing prices map to the nearest tier by monthly price.
--
-- store_access_grants records every store transaction that granted access,
-- so one purchase can be used once (UNIQUE store + transaction_ref).
-- community_subscriptions.payment_method gains apple_iap / google_iap.
-- See docs/payments/IAP_ONLY_PLAN.md.
BEGIN;

ALTER TABLE experts     ADD COLUMN IF NOT EXISTS price_tier TEXT;
ALTER TABLE communities ADD COLUMN IF NOT EXISTS price_tier TEXT;

-- Nearest tier by monthly price (t1 $4.99, t2 $9.99, t3 $19.99, t4 $49.99).
UPDATE experts SET price_tier = CASE
    WHEN monthly_price_cents < 750  THEN 't1'
    WHEN monthly_price_cents < 1500 THEN 't2'
    WHEN monthly_price_cents < 3500 THEN 't3'
    ELSE 't4' END
WHERE price_tier IS NULL;

UPDATE communities SET price_tier = CASE
    WHEN join_price_monthly_cents < 750  THEN 't1'
    WHEN join_price_monthly_cents < 1500 THEN 't2'
    WHEN join_price_monthly_cents < 3500 THEN 't3'
    ELSE 't4' END
WHERE price_tier IS NULL
  AND (join_price_monthly_cents > 0 OR join_price_yearly_cents > 0);

-- Prices follow the tier.
UPDATE experts SET
    monthly_price_cents = CASE price_tier WHEN 't1' THEN 499 WHEN 't2' THEN 999 WHEN 't3' THEN 1999 ELSE 4999 END,
    yearly_price_cents  = CASE price_tier WHEN 't1' THEN 4999 WHEN 't2' THEN 9999 WHEN 't3' THEN 19999 ELSE 49999 END,
    price_currency = 'usd';

UPDATE communities SET
    join_price_monthly_cents = CASE price_tier WHEN 't1' THEN 499 WHEN 't2' THEN 999 WHEN 't3' THEN 1999 ELSE 4999 END,
    join_price_yearly_cents  = CASE price_tier WHEN 't1' THEN 4999 WHEN 't2' THEN 9999 WHEN 't3' THEN 19999 ELSE 49999 END,
    price_currency = 'usd'
WHERE price_tier IS NOT NULL;

ALTER TABLE experts ALTER COLUMN price_tier SET DEFAULT 't2';
ALTER TABLE experts ALTER COLUMN price_tier SET NOT NULL;
ALTER TABLE experts DROP CONSTRAINT IF EXISTS experts_price_tier_check;
ALTER TABLE experts ADD CONSTRAINT experts_price_tier_check
    CHECK (price_tier IN ('t1', 't2', 't3', 't4'));
-- NULL = free community.
ALTER TABLE communities DROP CONSTRAINT IF EXISTS communities_price_tier_check;
ALTER TABLE communities ADD CONSTRAINT communities_price_tier_check
    CHECK (price_tier IS NULL OR price_tier IN ('t1', 't2', 't3', 't4'));

ALTER TABLE community_subscriptions
    DROP CONSTRAINT IF EXISTS community_subscriptions_payment_method_check;
ALTER TABLE community_subscriptions
    ADD CONSTRAINT community_subscriptions_payment_method_check
    CHECK (payment_method IN ('cash', 'fib', 'apple_iap', 'google_iap'));

CREATE TABLE IF NOT EXISTS store_access_grants (
    id              BIGSERIAL   PRIMARY KEY,
    store           TEXT        NOT NULL CHECK (store IN ('apple', 'google')),
    transaction_ref TEXT        NOT NULL CHECK (length(btrim(transaction_ref)) > 0),
    user_id         BIGINT      NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    target_type     TEXT        NOT NULL CHECK (target_type IN ('expert', 'community')),
    target_id       TEXT        NOT NULL,
    product_id      TEXT        NOT NULL,
    price_cents     INTEGER     NOT NULL CHECK (price_cents >= 0),
    granted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (store, transaction_ref)
);

CREATE INDEX IF NOT EXISTS idx_store_access_grants_user
    ON store_access_grants (user_id, granted_at DESC);

COMMIT;

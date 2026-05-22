-- =============================================================================
-- 0024 — per-expert subscription pricing + cash-receipt image.
--
-- Step B of the Subscriptions audit:
--   * B2  — kill the global PriceMonthlyCents/PriceYearlyCents constants
--           by storing per-expert prices on the experts row. Defaults
--           preserve current behaviour ($10/mo, $96/yr USD).
--   * B10 — let users attach an image of their cash receipt when
--           submitting a subscription so the admin reviews against
--           a photo, not just a text reference. Same pattern as
--           expert applications mig 0023.
-- =============================================================================

-- Per-expert pricing on the experts row. NOT NULL with sensible
-- defaults so backfill is automatic.
ALTER TABLE experts
    ADD COLUMN IF NOT EXISTS monthly_price_cents INT NOT NULL DEFAULT 1000,
    ADD COLUMN IF NOT EXISTS yearly_price_cents  INT NOT NULL DEFAULT 9600,
    ADD COLUMN IF NOT EXISTS price_currency      TEXT NOT NULL DEFAULT 'usd';

-- Both prices must be >= 0 (no negative pricing). We allow 0 to mean
-- "this expert is free for that plan", same convention as paid
-- communities (mig 0022).
ALTER TABLE experts
    DROP CONSTRAINT IF EXISTS experts_prices_nonneg;
ALTER TABLE experts
    ADD CONSTRAINT experts_prices_nonneg
        CHECK (monthly_price_cents >= 0 AND yearly_price_cents >= 0);

-- Cash-receipt image URL on the subscription row. Nullable — the
-- existing flow without an image keeps working untouched.
ALTER TABLE expert_subscriptions
    ADD COLUMN IF NOT EXISTS receipt_url TEXT;

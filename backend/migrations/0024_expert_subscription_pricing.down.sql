ALTER TABLE expert_subscriptions DROP COLUMN IF EXISTS receipt_url;
ALTER TABLE experts DROP CONSTRAINT IF EXISTS experts_prices_nonneg;
ALTER TABLE experts
    DROP COLUMN IF EXISTS monthly_price_cents,
    DROP COLUMN IF EXISTS yearly_price_cents,
    DROP COLUMN IF EXISTS price_currency;

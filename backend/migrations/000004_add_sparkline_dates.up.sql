ALTER TABLE market_indexes
ADD COLUMN IF NOT EXISTS sparkline_dates JSONB;
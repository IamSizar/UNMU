-- 0044_fundamentals_unique.sql
-- The FundamentalRepository.CreateOrUpdate upsert uses
-- `ON CONFLICT (stock_id, as_of_date, source)`, but the table was originally
-- created without a matching unique constraint (the demo data was loaded via
-- raw INSERTs, so this path was never exercised). Add the constraint so
-- provider ingests (EODHD, AlphaVantage, …) can upsert fundamentals.
--
-- Safe: verified no existing (stock_id, as_of_date, source) duplicates.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fundamentals_stock_id_as_of_date_source_key'
    ) THEN
        ALTER TABLE fundamentals
            ADD CONSTRAINT fundamentals_stock_id_as_of_date_source_key
            UNIQUE (stock_id, as_of_date, source);
    END IF;
END$$;

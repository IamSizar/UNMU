-- Market indexes table
CREATE TABLE IF NOT EXISTS market_indexes (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(50) UNIQUE NOT NULL,
    name VARCHAR(255) NOT NULL,
    price DECIMAL(20, 4),
    change DECIMAL(20, 4),
    change_percent DECIMAL(20, 4),
    category VARCHAR(50),
    sparkline JSONB,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
-- Market sentiment (Fear & Greed) table
-- We only keep the latest status or a history. For now, let's keep it simple with latest.
CREATE TABLE IF NOT EXISTS market_sentiment (
    id SERIAL PRIMARY KEY,
    value INTEGER NOT NULL,
    label VARCHAR(50) NOT NULL,
    color VARCHAR(20) NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
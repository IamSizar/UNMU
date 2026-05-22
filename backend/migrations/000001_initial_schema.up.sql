-- Users table
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    name VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Stocks table
CREATE TABLE IF NOT EXISTS stocks (
    id SERIAL PRIMARY KEY,
    ticker VARCHAR(50) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    country VARCHAR(100),
    region_code VARCHAR(10),
    sector VARCHAR(100),
    industry VARCHAR(100),
    description TEXT,
    market_cap BIGINT,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(ticker, exchange)
);

-- Financial fundamentals table
CREATE TABLE IF NOT EXISTS fundamentals (
    id SERIAL PRIMARY KEY,
    stock_id INTEGER NOT NULL REFERENCES stocks(id) ON DELETE CASCADE,
    total_assets DECIMAL(20, 2),
    total_debt DECIMAL(20, 2),
    cash_and_equiv DECIMAL(20, 2),
    total_revenue DECIMAL(20, 2),
    interest_income DECIMAL(20, 2),
    interest_expense DECIMAL(20, 2),
    net_income DECIMAL(20, 2),
    dividends_per_share DECIMAL(10, 4),
    as_of_date DATE,
    source VARCHAR(100),
    raw_json JSONB,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sharia status table
CREATE TABLE IF NOT EXISTS shariah_status (
    id SERIAL PRIMARY KEY,
    stock_id INTEGER NOT NULL REFERENCES stocks(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL, -- HALAL, HARAM, MIXED, UNKNOWN
    grade VARCHAR(5), -- A, B, C, F
    debt_ratio DECIMAL(5, 2),
    haram_income_ratio DECIMAL(5, 2),
    purification_rate DECIMAL(5, 2),
    pays_zakat BOOLEAN DEFAULT FALSE,
    explanation TEXT,
    reason TEXT,
    as_of_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(stock_id, as_of_date) -- Prevent duplicates: one status per stock per date
);

-- User portfolios (watched stocks)
CREATE TABLE IF NOT EXISTS user_portfolios (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    stock_id INTEGER NOT NULL REFERENCES stocks(id) ON DELETE CASCADE,
    shares DECIMAL(15, 4) DEFAULT 0,
    avg_buy_price DECIMAL(10, 2),
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, stock_id)
);

-- Notifications table
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    stock_id INTEGER REFERENCES stocks(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL, -- STATUS_CHANGE, PURIFICATION_CHANGE, etc.
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Analyst ratings table
CREATE TABLE IF NOT EXISTS analyst_ratings (
    id SERIAL PRIMARY KEY,
    stock_id INTEGER NOT NULL REFERENCES stocks(id) ON DELETE CASCADE,
    analyst_name VARCHAR(255),
    rating VARCHAR(20), -- BUY, HOLD, SELL
    target_price DECIMAL(10, 2),
    rating_date DATE,
    source VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Ads table
CREATE TABLE IF NOT EXISTS ads (
    id SERIAL PRIMARY KEY,
    company_name VARCHAR(255) NOT NULL,
    title VARCHAR(255) NOT NULL,
    description TEXT,
    image_url VARCHAR(500),
    target_url VARCHAR(500),
    region_code VARCHAR(10),
    is_active BOOLEAN DEFAULT TRUE,
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Promo codes table
CREATE TABLE IF NOT EXISTS promo_codes (
    id SERIAL PRIMARY KEY,
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_type VARCHAR(20) NOT NULL, -- PERCENTAGE, FIXED
    discount_value DECIMAL(10, 2) NOT NULL,
    max_uses INTEGER,
    used_count INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT TRUE,
    valid_from DATE,
    valid_until DATE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User promo usage table
CREATE TABLE IF NOT EXISTS user_promo_usage (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    promo_code_id INTEGER NOT NULL REFERENCES promo_codes(id) ON DELETE CASCADE,
    used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(user_id, promo_code_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_stocks_ticker ON stocks(ticker);
CREATE INDEX IF NOT EXISTS idx_stocks_region ON stocks(region_code);
CREATE INDEX IF NOT EXISTS idx_stocks_active ON stocks(is_active);
CREATE INDEX IF NOT EXISTS idx_fundamentals_stock ON fundamentals(stock_id);
CREATE INDEX IF NOT EXISTS idx_shariah_status_stock ON shariah_status(stock_id);
CREATE INDEX IF NOT EXISTS idx_shariah_status_date ON shariah_status(as_of_date);
CREATE INDEX IF NOT EXISTS idx_user_portfolios_user ON user_portfolios(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_analyst_ratings_stock ON analyst_ratings(stock_id);


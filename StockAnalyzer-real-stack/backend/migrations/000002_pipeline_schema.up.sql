-- Enhanced schema for production pipeline with time-series snapshots

-- Tracked symbols table (which symbols we actively monitor)
CREATE TABLE IF NOT EXISTS tracked_symbols (
    id SERIAL PRIMARY KEY,
    symbol VARCHAR(50) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    is_tracked BOOLEAN DEFAULT TRUE,
    priority INTEGER DEFAULT 0, -- Higher priority = process first
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(symbol, exchange)
);

-- Stock snapshots table (time-series of fundamentals + market data)
CREATE TABLE IF NOT EXISTS stock_snapshots (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(50) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    company_name VARCHAR(255),
    country VARCHAR(100),
    sector VARCHAR(100),
    industry VARCHAR(100),
    description TEXT,
    
    -- Market data
    price DECIMAL(20, 4),
    market_cap BIGINT,
    shares_outstanding BIGINT,
    currency VARCHAR(10),
    
    -- Income Statement
    revenue DECIMAL(20, 2),
    operating_income DECIMAL(20, 2),
    net_income DECIMAL(20, 2),
    interest_income DECIMAL(20, 2),
    interest_expense DECIMAL(20, 2),
    other_income DECIMAL(20, 2),
    
    -- Balance Sheet
    total_assets DECIMAL(20, 2),
    total_liabilities DECIMAL(20, 2),
    total_debt DECIMAL(20, 2),
    short_term_debt DECIMAL(20, 2),
    long_term_debt DECIMAL(20, 2),
    cash_and_equivalents DECIMAL(20, 2),
    short_term_investments DECIMAL(20, 2),
    
    -- Cash Flow
    operating_cash_flow DECIMAL(20, 2),
    financing_cash_flow DECIMAL(20, 2),
    interest_paid DECIMAL(20, 2),
    
    -- Timings
    fiscal_year_end VARCHAR(10),
    last_report_date DATE,
    snapshot_date TIMESTAMP NOT NULL,
    
    -- Metadata
    provider_name VARCHAR(50),
    data_quality VARCHAR(20), -- COMPLETE, PARTIAL, INSUFFICIENT
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    -- Indexes for efficient querying
    CONSTRAINT idx_snapshots_symbol_date UNIQUE (symbol, exchange, snapshot_date)
);

-- Shariah results table (latest result per symbol)
CREATE TABLE IF NOT EXISTS shariah_results (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(50) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL, -- HALAL, HARAM, DOUBTFUL, NEEDS_REVIEW, MIXED
    status_reason TEXT,
    detailed_breakdown TEXT, -- JSON
    evaluated_at TIMESTAMP NOT NULL,
    
    -- Financial ratios
    debt_ratio DECIMAL(5, 2),
    haram_income_ratio DECIMAL(5, 2),
    cash_to_market_cap_ratio DECIMAL(5, 2),
    purification_rate DECIMAL(5, 2),
    
    -- Grade (A, B, C, F)
    grade VARCHAR(5),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE(symbol, exchange)
);

-- Shariah result history (track status changes over time)
CREATE TABLE IF NOT EXISTS shariah_result_history (
    id BIGSERIAL PRIMARY KEY,
    symbol VARCHAR(50) NOT NULL,
    exchange VARCHAR(50) NOT NULL,
    old_status VARCHAR(20),
    new_status VARCHAR(20) NOT NULL,
    old_grade VARCHAR(5),
    new_grade VARCHAR(5),
    status_reason TEXT,
    detailed_breakdown TEXT,
    evaluated_at TIMESTAMP NOT NULL,
    
    -- Financial ratios at time of change
    debt_ratio DECIMAL(5, 2),
    haram_income_ratio DECIMAL(5, 2),
    cash_to_market_cap_ratio DECIMAL(5, 2),
    purification_rate DECIMAL(5, 2),
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_tracked_symbols_tracked ON tracked_symbols(is_tracked, priority DESC);
CREATE INDEX IF NOT EXISTS idx_snapshots_symbol ON stock_snapshots(symbol, exchange);
CREATE INDEX IF NOT EXISTS idx_snapshots_date ON stock_snapshots(snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_snapshots_symbol_date ON stock_snapshots(symbol, exchange, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS idx_shariah_results_symbol ON shariah_results(symbol, exchange);
CREATE INDEX IF NOT EXISTS idx_shariah_results_status ON shariah_results(status);
CREATE INDEX IF NOT EXISTS idx_shariah_history_symbol ON shariah_result_history(symbol, exchange);
CREATE INDEX IF NOT EXISTS idx_shariah_history_date ON shariah_result_history(evaluated_at DESC);
CREATE INDEX IF NOT EXISTS idx_shariah_history_status_change ON shariah_result_history(old_status, new_status);

-- Function to automatically create history entry when status changes
CREATE OR REPLACE FUNCTION log_shariah_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Only log if status actually changed
    IF OLD.status IS DISTINCT FROM NEW.status THEN
        INSERT INTO shariah_result_history (
            symbol, exchange, old_status, new_status, old_grade, new_grade,
            status_reason, detailed_breakdown, evaluated_at,
            debt_ratio, haram_income_ratio, cash_to_market_cap_ratio, purification_rate
        ) VALUES (
            NEW.symbol, NEW.exchange, OLD.status, NEW.status, OLD.grade, NEW.grade,
            NEW.status_reason, NEW.detailed_breakdown, NEW.evaluated_at,
            NEW.debt_ratio, NEW.haram_income_ratio, NEW.cash_to_market_cap_ratio, NEW.purification_rate
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to log status changes
CREATE TRIGGER shariah_status_change_trigger
    AFTER UPDATE ON shariah_results
    FOR EACH ROW
    WHEN (OLD.status IS DISTINCT FROM NEW.status)
    EXECUTE FUNCTION log_shariah_status_change();


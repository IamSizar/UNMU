-- =============================================================================
-- Seed demo stocks — gives the local backend usable data without running
-- the live ingestion pipeline (which needs API keys + can hit rate limits).
--
-- Inserts ~25 popular tickers across regions, with paired `fundamentals`
-- and `shariah_status` rows so every grade (A, B, C, F) is represented.
--
-- Idempotent — uses ON CONFLICT to skip rows that already exist. Safe to
-- re-run after live ingestion fills in real data; this script will not
-- overwrite anything.
--
-- Run with:
--   psql "$DATABASE_URL" -f backend/migrations/0006_seed_demo_stocks.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. stocks — core identity rows.
-- -----------------------------------------------------------------------------
INSERT INTO stocks (ticker, exchange, name, country, region_code, sector, industry, market_cap) VALUES
    ('AAPL',    'NASDAQ', 'Apple Inc.',                'United States',  'US',     'Technology',         'Consumer Electronics', 3400000000000),
    ('MSFT',    'NASDAQ', 'Microsoft Corporation',     'United States',  'US',     'Technology',         'Software',             3100000000000),
    ('NVDA',    'NASDAQ', 'NVIDIA Corporation',        'United States',  'US',     'Technology',         'Semiconductors',       2900000000000),
    ('GOOGL',   'NASDAQ', 'Alphabet Inc.',             'United States',  'US',     'Communication',      'Internet',             2100000000000),
    ('AMZN',    'NASDAQ', 'Amazon.com Inc.',           'United States',  'US',     'Consumer',           'E-Commerce',           1900000000000),
    ('TSLA',    'NASDAQ', 'Tesla Inc.',                'United States',  'US',     'Consumer',           'Auto Manufacturers',    800000000000),
    ('META',    'NASDAQ', 'Meta Platforms Inc.',       'United States',  'US',     'Communication',      'Internet',             1300000000000),
    ('JPM',     'NYSE',   'JPMorgan Chase & Co.',      'United States',  'US',     'Financial',          'Banks',                 600000000000),
    ('BAC',     'NYSE',   'Bank of America Corp.',     'United States',  'US',     'Financial',          'Banks',                 350000000000),
    ('XOM',     'NYSE',   'Exxon Mobil Corporation',   'United States',  'US',     'Energy',             'Oil & Gas',             480000000000),

    ('2222',    'TADAWUL','Saudi Aramco',              'Saudi Arabia',   'GCC',    'Energy',             'Oil & Gas',           1900000000000),
    ('1180',    'TADAWUL','Al Rajhi Bank',             'Saudi Arabia',   'GCC',    'Financial',          'Islamic Banking',      90000000000),
    ('7010',    'TADAWUL','STC',                       'Saudi Arabia',   'GCC',    'Communication',      'Telecom',              60000000000),
    ('EMAAR',   'DFM',    'Emaar Properties',          'United Arab Emirates','GCC','Real Estate',       'Real Estate Dev.',     16000000000),
    ('FAB',     'ADX',    'First Abu Dhabi Bank',      'United Arab Emirates','GCC','Financial',         'Banks',                40000000000),
    ('QNBK',    'QSE',    'Qatar National Bank',       'Qatar',          'GCC',    'Financial',          'Banks',                42000000000),

    ('CIB',     'EGX',    'Commercial Intl Bank',      'Egypt',          'MENA',   'Financial',          'Banks',                  6000000000),
    ('VAC',     'ASE',    'Hikma Pharmaceuticals',     'Jordan',         'MENA',   'Healthcare',         'Pharmaceuticals',        4500000000),

    ('ASML',    'AEX',    'ASML Holding NV',           'Netherlands',    'EU',     'Technology',         'Semiconductors',       340000000000),
    ('SAP',     'XETRA',  'SAP SE',                    'Germany',        'EU',     'Technology',         'Software',             220000000000),
    ('NESN',    'SIX',    'Nestle SA',                 'Switzerland',    'EU',     'Consumer',           'Food',                 280000000000),

    ('TSM',     'TWSE',   'Taiwan Semiconductor',      'Taiwan',         'ASIA',   'Technology',         'Semiconductors',       780000000000),
    ('BABA',    'NYSE',   'Alibaba Group',             'China',          'CN',     'Consumer',           'E-Commerce',           200000000000),
    ('TCEHY',   'OTC',    'Tencent Holdings',          'China',          'CN',     'Communication',      'Internet',             420000000000),
    ('700',     'HKEX',   'Tencent Holdings',          'China',          'CN',     'Communication',      'Internet',             420000000000)
ON CONFLICT (ticker, exchange) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2. fundamentals — one row per stock with realistic-ish numbers so the
--    Shariah engine has something to chew on.
-- -----------------------------------------------------------------------------
INSERT INTO fundamentals (stock_id, total_assets, total_debt, cash_and_equiv, total_revenue, interest_income, interest_expense, net_income, dividends_per_share, as_of_date, source)
SELECT id, ta, td, cash, rev, intinc, intexp, ni, dps, '2025-01-01', 'demo_seed'
FROM (VALUES
    ('AAPL',    'NASDAQ',  365000000000.00,  111000000000.00,  62000000000.00,  385000000000.00,    900000000.00,  3700000000.00,  100000000000.00, 0.96),
    ('MSFT',    'NASDAQ',  515000000000.00,   65000000000.00, 110000000000.00,  245000000000.00,   2400000000.00,  2900000000.00,   88000000000.00, 3.00),
    ('NVDA',    'NASDAQ',   65000000000.00,    9000000000.00,  26000000000.00,   60000000000.00,    300000000.00,   200000000.00,   30000000000.00, 0.16),
    ('GOOGL',   'NASDAQ',  402000000000.00,   28000000000.00, 110000000000.00,  300000000000.00,   3500000000.00,   400000000.00,   75000000000.00, 0.00),
    ('AMZN',    'NASDAQ',  470000000000.00,  150000000000.00,  87000000000.00,  580000000000.00,   2500000000.00,  3200000000.00,   30000000000.00, 0.00),
    ('TSLA',    'NASDAQ',   97000000000.00,    9500000000.00,  29000000000.00,   97000000000.00,    900000000.00,   100000000.00,    7800000000.00, 0.00),
    ('META',    'NASDAQ',  220000000000.00,   18000000000.00,  70000000000.00,  150000000000.00,   2000000000.00,   400000000.00,   40000000000.00, 0.50),
    ('JPM',     'NYSE',    3700000000000.00, 720000000000.00, 950000000000.00,  170000000000.00, 95000000000.00, 70000000000.00,    49000000000.00, 4.20),
    ('BAC',     'NYSE',    3200000000000.00, 600000000000.00, 800000000000.00,  100000000000.00, 78000000000.00, 60000000000.00,    27000000000.00, 0.96),
    ('XOM',     'NYSE',    380000000000.00,   42000000000.00,  30000000000.00,  340000000000.00,    200000000.00,   900000000.00,   36000000000.00, 3.80),
    ('2222',    'TADAWUL', 600000000000.00,   50000000000.00, 100000000000.00,  450000000000.00,    400000000.00,  1500000000.00,  121000000000.00, 0.65),
    ('1180',    'TADAWUL', 220000000000.00,   16000000000.00,  20000000000.00,   25000000000.00,    150000000.00,    50000000.00,   17000000000.00, 1.50),
    ('7010',    'TADAWUL', 150000000000.00,   33000000000.00,  18000000000.00,   65000000000.00,    100000000.00,   400000000.00,   12000000000.00, 4.00),
    ('EMAAR',   'DFM',     130000000000.00,   30000000000.00,  10000000000.00,   25000000000.00,     80000000.00,   400000000.00,    7000000000.00, 0.50),
    ('FAB',     'ADX',     1100000000000.00, 220000000000.00, 250000000000.00,   30000000000.00, 24000000000.00, 18000000000.00,    14000000000.00, 0.70),
    ('QNBK',    'QSE',     1300000000000.00, 240000000000.00, 200000000000.00,   33000000000.00, 27000000000.00, 20000000000.00,    14000000000.00, 0.65),
    ('CIB',     'EGX',     650000000000.00,  100000000000.00, 110000000000.00,    9000000000.00,  6500000000.00,  4500000000.00,    3000000000.00, 4.00),
    ('VAC',     'ASE',      4500000000.00,    1200000000.00,    700000000.00,    2700000000.00,     50000000.00,    80000000.00,     400000000.00, 0.20),
    ('ASML',    'AEX',     43000000000.00,   5000000000.00,  6000000000.00,    27000000000.00,    300000000.00,   100000000.00,     8000000000.00, 6.40),
    ('SAP',     'XETRA',   62000000000.00,  11000000000.00,  9000000000.00,    32000000000.00,    400000000.00,   200000000.00,     6000000000.00, 2.20),
    ('NESN',    'SIX',     140000000000.00,  53000000000.00,  6000000000.00,    93000000000.00,    600000000.00,  1500000000.00,    13000000000.00, 3.10),
    ('TSM',     'TWSE',    150000000000.00,  17000000000.00, 50000000000.00,    70000000000.00,    400000000.00,   300000000.00,    25000000000.00, 1.40),
    ('BABA',    'NYSE',    250000000000.00,  35000000000.00, 80000000000.00,    130000000000.00,   1500000000.00,   500000000.00,    10000000000.00, 0.00),
    ('TCEHY',   'OTC',     290000000000.00,  35000000000.00, 70000000000.00,    85000000000.00,    900000000.00,   300000000.00,    20000000000.00, 0.00),
    ('700',     'HKEX',    290000000000.00,  35000000000.00, 70000000000.00,    85000000000.00,    900000000.00,   300000000.00,    20000000000.00, 0.00)
) AS f(ticker, exchange, ta, td, cash, rev, intinc, intexp, ni, dps)
JOIN stocks s ON s.ticker = f.ticker AND s.exchange = f.exchange
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3. shariah_status — one row per stock with grade + debt/haram ratios.
-- -----------------------------------------------------------------------------
INSERT INTO shariah_status (stock_id, status, grade, debt_ratio, haram_income_ratio, purification_rate, pays_zakat, explanation, reason, as_of_date)
SELECT id, status, grade, dr, hir, pr, pz, expl, reason, '2025-01-01'
FROM (VALUES
    ('AAPL',    'NASDAQ', 'COMPLIANT',     'B',  30.40,  0.23, 0.23, false, 'Debt slightly elevated but under threshold; impure income negligible.',  'Hardware revenue dominates'),
    ('MSFT',    'NASDAQ', 'COMPLIANT',     'A',  12.62,  0.98, 0.98, false, 'Low debt, minor cloud financing income.',                                'Software-led revenue'),
    ('NVDA',    'NASDAQ', 'COMPLIANT',     'A',  13.85,  0.50, 0.50, false, 'Healthy balance sheet, semiconductor focus.',                            'Chip design'),
    ('GOOGL',   'NASDAQ', 'COMPLIANT',     'B',   6.97,  1.16, 1.16, false, 'Some interest income from cash deposits.',                               'Ad business core'),
    ('AMZN',    'NASDAQ', 'DOUBTFUL',      'C',  31.91,  0.43, 0.43, true,  'Debt above 30% threshold by some methodologies.',                        'High-debt growth model'),
    ('TSLA',    'NASDAQ', 'COMPLIANT',     'B',   9.79,  0.93, 0.93, false, 'Auto + energy; debt ratio well under threshold.',                        'EV manufacturer'),
    ('META',    'NASDAQ', 'COMPLIANT',     'B',   8.18,  1.33, 1.33, false, 'Ad-driven revenue; minor interest income.',                              'Social platforms'),
    ('JPM',     'NYSE',   'NON_COMPLIANT', 'F',  19.46, 55.88, 55.88, true,  'Conventional banking — interest is core business.',                      'Riba-based'),
    ('BAC',     'NYSE',   'NON_COMPLIANT', 'F',  18.75, 78.00, 78.00, true,  'Conventional banking.',                                                   'Riba-based'),
    ('XOM',     'NYSE',   'COMPLIANT',     'A',  11.05,  0.06, 0.06, false, 'Oil & gas, low debt.',                                                    'Energy'),
    ('2222',    'TADAWUL','COMPLIANT',     'A',   8.33,  0.09, 0.09, true,  'State-backed energy giant, very clean balance sheet.',                    'Aramco'),
    ('1180',    'TADAWUL','COMPLIANT',     'A',   7.27,  0.60, 0.60, true,  'Islamic bank — fully Shariah-compliant by design.',                       'Islamic banking'),
    ('7010',    'TADAWUL','COMPLIANT',     'C',  22.00,  0.62, 0.62, false, 'Telecom; some interest income from cash.',                                'Telecom'),
    ('EMAAR',   'DFM',    'COMPLIANT',     'B',  23.08,  0.32, 0.32, false, 'Real estate; debt high but within threshold.',                            'Property dev.'),
    ('FAB',     'ADX',    'NON_COMPLIANT', 'F',  20.00, 80.00, 80.00, true,  'Conventional banking.',                                                   'Riba-based'),
    ('QNBK',    'QSE',    'NON_COMPLIANT', 'F',  18.46, 81.82, 81.82, true,  'Conventional banking.',                                                   'Riba-based'),
    ('CIB',     'EGX',    'NON_COMPLIANT', 'F',  15.38, 72.22, 72.22, true,  'Conventional banking.',                                                   'Riba-based'),
    ('VAC',     'ASE',    'COMPLIANT',     'B',  26.67,  1.85, 1.85, false, 'Pharma; minor interest income.',                                           'Healthcare'),
    ('ASML',    'AEX',    'COMPLIANT',     'A',  11.63,  1.11, 1.11, false, 'Semiconductors, low debt.',                                                'Chip equipment'),
    ('SAP',     'XETRA',  'COMPLIANT',     'B',  17.74,  1.25, 1.25, false, 'Software; low debt.',                                                      'Enterprise SaaS'),
    ('NESN',    'SIX',    'DOUBTFUL',      'C',  37.86,  0.65, 0.65, false, 'Debt above threshold; some food categories questionable.',                'Consumer staples'),
    ('TSM',     'TWSE',   'COMPLIANT',     'A',  11.33,  0.57, 0.57, false, 'Semiconductor foundry; clean balance sheet.',                              'Chip foundry'),
    ('BABA',    'NYSE',   'COMPLIANT',     'B',  14.00,  1.15, 1.15, false, 'E-commerce; minor interest income from float.',                            'Tmall + cloud'),
    ('TCEHY',   'OTC',    'COMPLIANT',     'B',  12.07,  1.06, 1.06, false, 'Internet platforms; gaming + payments.',                                   'WeChat ecosystem'),
    ('700',     'HKEX',   'COMPLIANT',     'B',  12.07,  1.06, 1.06, false, 'Internet platforms; gaming + payments.',                                   'WeChat ecosystem')
) AS sh(ticker, exchange, status, grade, dr, hir, pr, pz, expl, reason)
JOIN stocks s ON s.ticker = sh.ticker AND s.exchange = sh.exchange
ON CONFLICT (stock_id, as_of_date) DO NOTHING;

COMMIT;

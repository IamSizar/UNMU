# Financial API Providers Guide

## Current Supported Providers

### 1. **Alpha Vantage** (Currently Active)
- **Free Tier**: 5 calls/minute, 500 calls/day
- **Limitation**: Uses predefined stock list (only ~33 popular stocks)
- **API Key**: Already configured in `.env`
- **Status**: ✅ Fully implemented

### 2. **Financial Modeling Prep (FMP)** (Available)
- **Free Tier**: 250 requests/day
- **Better**: Can fetch full stock universe (all stocks, not just predefined list)
- **API Key**: You already have one: `F6FegPuKcKze6tRJ8fw7Fd57fmUDCReU`
- **Status**: ✅ Fully implemented
- **Website**: https://site.financialmodelingprep.com/

## How to Switch to FMP

### Step 1: Update `.env` file

Edit `backend/.env` and change:

```bash
# Change from:
STOCK_API_PROVIDER=alphavantage

# To:
STOCK_API_PROVIDER=fmp
STOCK_API_KEY=F6FegPuKcKze6tRJ8fw7Fd57fmUDCReU
```

### Step 2: Restart the backend

```bash
cd backend
go run cmd/api/main.go
```

### Step 3: Run ingestion (to get full stock universe)

```bash
cd backend
go run cmd/ingest/main.go
```

## Other Free API Options

### 3. **DataJockey** (Recommended for Full Coverage)
- **Free Tier**: Free API key (no credit card)
- **Coverage**: All US stocks from SEC filings
- **Fundamentals**: ✅ Yes (Income Statement, Balance Sheet, Cash Flow)
- **Website**: https://datajockey.io/
- **Pros**: 
  - Clean data from SEC filings
  - No credit card required
  - Better coverage than predefined lists
- **Status**: ❌ Not yet implemented (would need to add provider)

### 4. **Polygon.io** (Good for Real-time)
- **Free Tier**: Limited free tier
- **Coverage**: US stocks
- **Website**: https://polygon.io/
- **Status**: ❌ Not yet implemented

### 5. **Yahoo Finance API** (Unofficial, Free)
- **Free**: Yes (unofficial API)
- **Coverage**: Global stocks
- **Limitation**: Unofficial, may break
- **Status**: ❌ Not yet implemented

## Comparison

| Provider | Free Tier | Stock Universe | Fundamentals | Implementation Status |
|----------|-----------|----------------|--------------|----------------------|
| **Alpha Vantage** | 500/day | Predefined (~33) | ✅ Yes | ✅ Implemented |
| **FMP** | 250/day | **Full universe** | ✅ Yes | ✅ Implemented |
| **DataJockey** | Free | **All US stocks** | ✅ Yes | ❌ Not implemented |

## Recommendation

**For better stock coverage, switch to FMP:**
1. You already have the API key
2. It's already implemented
3. It can fetch the full stock universe (not just predefined list)
4. Just need to change one line in `.env`

**For even better coverage later, consider DataJockey:**
- Would need to implement a new provider
- But provides access to all US stocks from SEC filings

## How to Add a New Provider

If you want to add a new provider (like DataJockey):

1. Create `backend/internal/marketdata/datajockey_provider.go`
2. Implement the `MarketDataProvider` interface:
   - `FetchStockUniverse(regionCode string)`
   - `FetchFundamentalsBatch(tickers []string)`
   - `SearchStocks(query string)`
3. Add provider selection in `backend/cmd/ingest/main.go`
4. Add API key to config in `backend/internal/config/config.go`
5. Update `.env` with new provider name and API key


# How to Switch API Providers

## Quick Switch to FMP (You Already Have the Key!)

### Step 1: Update `.env` file

Open `backend/.env` and change:

```bash
# Change this line:
STOCK_API_PROVIDER=alphavantage

# To:
STOCK_API_PROVIDER=fmp

# And add/update:
STOCK_API_KEY=F6FegPuKcKze6tRJ8fw7Fd57fmUDCReU
```

### Step 2: Restart Backend

```bash
cd backend
# Stop current server (Ctrl+C if running)
go run cmd/api/main.go
```

### Step 3: Run Ingestion (Optional - to refresh data)

```bash
cd backend
go run cmd/ingest/main.go
```

## Available Providers

### ✅ 1. Financial Modeling Prep (FMP) - RECOMMENDED
- **Status**: Fully implemented
- **Free Tier**: 250 requests/day
- **Your API Key**: `F6FegPuKcKze6tRJ8fw7Fd57fmUDCReU`
- **Pros**: 
  - Better rate limits than Alpha Vantage
  - Good fundamentals coverage
  - Search functionality works well
- **Cons**: Still uses predefined stock list (same limitation as Alpha Vantage)

### ✅ 2. Alpha Vantage (Current)
- **Status**: Fully implemented
- **Free Tier**: 500 requests/day, 5 calls/minute
- **Your API Key**: `PM0TRN8263MZLHY8`
- **Pros**: 
  - More requests per day
  - Well-established API
- **Cons**: 
  - Strict rate limits (12 seconds between calls)
  - Uses predefined stock list

## Better Options (Need Implementation)

### 3. DataJockey (Best for Full Stock Universe)
- **Website**: https://datajockey.io/
- **Free Tier**: Free API key (no credit card)
- **Coverage**: All US stocks from SEC filings
- **Pros**:
  - ✅ Can fetch ALL stocks (not just predefined list)
  - ✅ Clean data from SEC filings
  - ✅ No credit card required
  - ✅ Good fundamentals coverage
- **How to Get**:
  1. Go to https://datajockey.io/
  2. Sign up for free account
  3. Get your API key
  4. I can help implement the provider

### 4. Polygon.io
- **Website**: https://polygon.io/
- **Free Tier**: Limited
- **Coverage**: US stocks
- **Pros**: Good real-time data
- **Cons**: Limited free tier

### 5. Yahoo Finance (Unofficial)
- **Free**: Yes
- **Coverage**: Global
- **Pros**: Free, wide coverage
- **Cons**: Unofficial API, may break

## Recommendation

**For Now**: Switch to FMP (you already have it set up)
- Better rate limits
- Same functionality
- Just change one line in `.env`

**For Future**: Consider DataJockey
- Would give you access to ALL stocks (not just 33 predefined ones)
- Would need to implement the provider (I can help with this)

## How to Add a New Provider

If you want to add DataJockey or another provider:

1. **Get API Key**: Sign up at the provider's website
2. **Create Provider File**: `backend/internal/marketdata/datajockey_provider.go`
3. **Implement Interface**: Follow the pattern from `fmp_provider.go`
4. **Add to Config**: Update `backend/internal/config/config.go`
5. **Add to Ingestion**: Update `backend/cmd/ingest/main.go`
6. **Update .env**: Add provider name and API key

I can help implement any new provider you choose!


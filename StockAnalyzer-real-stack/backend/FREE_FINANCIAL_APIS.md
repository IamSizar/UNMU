# Free Financial Data APIs with Fundamentals

## Best Options for Free Financial Fundamentals

### 1. **Alpha Vantage** ⭐ RECOMMENDED
- **Free Tier**: 5 API calls/minute, 500 calls/day
- **Fundamentals**: ✅ Yes (Income Statement, Balance Sheet, Cash Flow)
- **Coverage**: US stocks, ETFs, mutual funds
- **API Endpoints**:
  - `INCOME_STATEMENT` - Annual/quarterly income statements
  - `BALANCE_SHEET` - Annual/quarterly balance sheets
  - `CASH_FLOW` - Cash flow statements
  - `OVERVIEW` - Company overview with key metrics
- **Website**: https://www.alphavantage.co/
- **Pros**: Well-established, good documentation, reliable
- **Cons**: Rate limits (500/day), may need multiple API keys for higher volume

### 2. **DataJockey**
- **Free Tier**: Free API key (no credit card)
- **Fundamentals**: ✅ Yes (from SEC filings)
- **Coverage**: US stocks
- **Website**: https://datajockey.io/
- **Pros**: Clean data from SEC filings, no credit card required
- **Cons**: Unknown rate limits, newer service

### 3. **SEC API (sec-api.io)**
- **Free Tier**: 100 calls/month
- **Fundamentals**: ✅ Yes (SEC/EDGAR filings)
- **Coverage**: US stocks (5,000+ companies, data back to 1998)
- **Website**: https://sec-api.io/
- **Pros**: Direct from SEC, comprehensive historical data
- **Cons**: Low free tier limit (100/month), requires parsing SEC filings

### 4. **Financial Datasets**
- **Free Tier**: 1,000 requests/minute (developer plan)
- **Fundamentals**: ✅ Yes (standardized financial statements)
- **Coverage**: Comprehensive
- **Website**: https://findmymoat.com/free/data-apis
- **Pros**: High rate limit, standardized data
- **Cons**: May require registration/approval

## Recommendation: Alpha Vantage

**Why Alpha Vantage is the best choice:**
1. ✅ **Proven track record** - Widely used, stable API
2. ✅ **Good free tier** - 500 calls/day is reasonable for development
3. ✅ **Complete fundamentals** - Income statements, balance sheets, cash flow
4. ✅ **Easy integration** - Well-documented REST API
5. ✅ **No credit card required** - Just sign up for free API key

**Rate Limit Strategy:**
- 500 calls/day = ~20 stocks/day (if fetching income + balance sheet for each)
- For production, you may need:
  - Multiple API keys (one per 500 calls/day)
  - Or upgrade to paid tier ($49.99/month for 75 calls/minute)

## Implementation Notes

Alpha Vantage provides:
- `INCOME_STATEMENT` endpoint with annual/quarterly data
- `BALANCE_SHEET` endpoint with assets, liabilities, equity
- `OVERVIEW` endpoint with key financial ratios

The data format is JSON and includes all fields needed for Sharia screening:
- Total revenue
- Interest income/expense
- Net income
- Total assets
- Total debt
- Cash and equivalents


# Alpha Vantage Setup Guide

## Getting Your Free API Key

1. **Visit**: https://www.alphavantage.co/support/#api-key
2. **Fill out the form** with:
   - First Name
   - Last Name
   - Email
   - Organization (optional)
3. **Submit** - You'll receive your API key via email immediately
4. **Free Tier Limits**:
   - 5 API calls per minute
   - 500 API calls per day

## Configuration

Add your Alpha Vantage API key to `.env`:

```env
STOCK_API_PROVIDER=alphavantage
ALPHA_VANTAGE_API_KEY=your_api_key_here
```

## What Alpha Vantage Provides

✅ **Company Overview** (`OVERVIEW`):
- Company name, description, sector, industry
- Market capitalization
- Key financial ratios

✅ **Income Statement** (`INCOME_STATEMENT`):
- Total revenue
- Interest income
- Interest expense
- Net income
- Annual and quarterly reports

✅ **Balance Sheet** (`BALANCE_SHEET`):
- Total assets
- Total debt (long-term + short-term)
- Cash and cash equivalents
- Annual and quarterly reports

✅ **Stock Search** (`SYMBOL_SEARCH`):
- Search stocks by keyword

## Rate Limits

- **5 calls/minute** = 1 call every 12 seconds
- **500 calls/day** = ~20 stocks/day (if fetching income + balance sheet)

For production with more stocks, consider:
- Multiple free API keys (one per 500 calls/day)
- Paid tier: $49.99/month for 75 calls/minute

## Testing

After adding your API key, test the ingestion:

```bash
cd backend
go run cmd/ingest/main.go
```

You should see:
- Stocks being fetched with sector/industry/description
- Fundamentals being fetched successfully
- Sharia screening running with financial data


# Populating Stock Data

## Why You Don't See Stocks

The database is currently empty. You need to run **data ingestion** to fetch stocks from the EODHD API and populate the database.

## Quick Start

**Run data ingestion:**
```bash
cd backend
./run-ingestion.sh
```

Or manually:
```bash
cd backend
export $(cat .env | grep -v '^#' | xargs)
go run cmd/ingest/main.go
```

## What Happens During Ingestion

1. **Fetches Stock Universe** - Gets list of stocks for each region:
   - GCC (Gulf Cooperation Council)
   - MENA (Middle East & North Africa)
   - US
   - EU (Europe)
   - ASIA
   - CN (China)
   - GLOBAL

2. **Fetches Fundamentals** - Gets financial data for each stock:
   - Total assets, debt, revenue
   - Interest income/expense
   - Net income, dividends

3. **Runs Shariah Screening** - Analyzes each stock:
   - Checks for haram activities
   - Calculates debt ratio
   - Calculates non-halal income ratio
   - Assigns grade (A, B, C, F)
   - Generates explanation

## How Long Does It Take?

- **First run**: 10-30 minutes (depends on API rate limits)
- **Subsequent runs**: Faster (only updates changed data)
- **API Rate Limits**: EODHD allows 5 requests/second

## Monitor Progress

You'll see output like:
```
Starting data ingestion...
Fetching stocks for region: GCC
Fetching stocks for region: MENA
Processing fundamentals batch 1-200 of 5000
...
```

## After Ingestion Completes

1. ✅ Stocks will appear in the app
2. ✅ You can browse by region
3. ✅ Shariah status will be available
4. ✅ You can search for stocks

## Troubleshooting

### Ingestion Fails
- Check EODHD API key is correct in `.env`
- Verify API quota hasn't been exceeded
- Check network connection
- Review error messages in the output

### No Stocks After Ingestion
- Check database: `psql -U zaidaqrawi -d halalstocks -c "SELECT COUNT(*) FROM stocks;"`
- Verify ingestion completed without errors
- Check if stocks are marked as active: `SELECT COUNT(*) FROM stocks WHERE is_active = TRUE;`

### Slow Ingestion
- This is normal for first run
- EODHD API has rate limits (5 req/sec)
- Large regions (US, GLOBAL) take longer
- Subsequent runs are faster (only updates)

## Running Ingestion Periodically

Set up a cron job to run every 12 hours:
```bash
# Edit crontab
crontab -e

# Add this line (runs at 1 AM and 1 PM daily)
0 1,13 * * * cd /path/to/halalstocks/backend && ./run-ingestion.sh >> /tmp/ingestion.log 2>&1
```

## Quick Check

After ingestion, verify stocks are loaded:
```bash
psql -U zaidaqrawi -d halalstocks -c "SELECT COUNT(*) as total_stocks, COUNT(DISTINCT region_code) as regions FROM stocks WHERE is_active = TRUE;"
```

You should see stocks from multiple regions!


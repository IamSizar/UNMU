# Check Ingestion Progress

## Monitor Ingestion

**Check the log file:**
```bash
tail -f /tmp/ingestion.log
```

**Or check database progress:**
```bash
# Count stocks added so far
psql -U zaidaqrawi -d halalstocks -c "SELECT COUNT(*) FROM stocks;"

# See which regions have stocks
psql -U zaidaqrawi -d halalstocks -c "SELECT region_code, COUNT(*) FROM stocks GROUP BY region_code;"
```

## What to Expect

The ingestion will:
1. Fetch stocks for each region (GCC, MENA, US, EU, ASIA, CN, GLOBAL)
2. Process fundamentals in batches of 200
3. Run Shariah screening

**This takes 10-30 minutes** depending on:
- Number of stocks per region
- EODHD API rate limits (5 req/sec)
- Network speed

## Quick Status Check

```bash
# Total stocks
psql -U zaidaqrawi -d halalstocks -c "SELECT COUNT(*) as total_stocks FROM stocks;"

# Stocks with Shariah status
psql -U zaidaqrawi -d halalstocks -c "SELECT COUNT(DISTINCT stock_id) as stocks_with_status FROM shariah_status;"

# Stocks by region
psql -U zaidaqrawi -d halalstocks -c "SELECT region_code, COUNT(*) FROM stocks WHERE is_active = TRUE GROUP BY region_code ORDER BY COUNT(*) DESC;"
```

## When It's Done

Once you see stocks in the database, refresh your app and you should see:
- Stocks in region tabs
- Shariah grades (A, B, C, F)
- Ability to search stocks


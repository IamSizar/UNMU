# Pipeline Quick Start Guide

## ✅ Setup Complete!

The production data pipeline is now ready to use with your existing FMP provider.

## What's Ready

1. ✅ **Database migrations** - Applied (version 2)
2. ✅ **FMP Provider Adapter** - Bridges existing FMP provider to new pipeline
3. ✅ **Daily Update Pipeline** - Ready to run
4. ✅ **Shariah Engine Integration** - Uses existing shariah package

## Quick Start

### 1. Add Symbols to Track

```sql
-- Add some stocks to track
INSERT INTO tracked_symbols (symbol, exchange, is_tracked, priority) VALUES
  ('AAPL', 'NASDAQ', TRUE, 1),
  ('MSFT', 'NASDAQ', TRUE, 1),
  ('GOOGL', 'NASDAQ', TRUE, 1),
  ('TSLA', 'NASDAQ', TRUE, 1),
  ('META', 'NASDAQ', TRUE, 1)
ON CONFLICT (symbol, exchange) DO NOTHING;
```

### 2. Configure API Key (if not already set)

Make sure your `.env` file has:
```bash
STOCK_API_KEY=your_fmp_api_key
STOCK_API_PROVIDER=fmp
```

### 3. Run the Pipeline

```bash
cd backend
go run cmd/daily_update/main.go
```

## What Happens

1. **Fetches Data**: Uses your existing FMP provider to fetch fundamentals
2. **Stores Snapshots**: Saves time-series data in `stock_snapshots` table
3. **Evaluates Shariah**: Runs stocks through Shariah screening engine
4. **Detects Changes**: Automatically logs status changes to `shariah_result_history`
5. **Updates Results**: Stores latest status in `shariah_results` table

## Check Results

### View Latest Shariah Results
```sql
SELECT symbol, exchange, status, grade, evaluated_at 
FROM shariah_results 
ORDER BY evaluated_at DESC;
```

### View Status Changes
```sql
SELECT symbol, exchange, old_status, new_status, evaluated_at
FROM shariah_result_history
ORDER BY evaluated_at DESC
LIMIT 10;
```

### View Recent Snapshots
```sql
SELECT symbol, snapshot_date, provider_name, data_quality, revenue, total_assets, total_debt
FROM stock_snapshots
ORDER BY snapshot_date DESC
LIMIT 10;
```

## Schedule Daily Runs

### Using Cron (Linux/Mac)
```bash
# Edit crontab
crontab -e

# Add this line to run daily at 2 AM
0 2 * * * cd /path/to/halalstocks/backend && /usr/local/go/bin/go run cmd/daily_update/main.go >> /var/log/halalstocks/pipeline.log 2>&1
```

### Using systemd (Linux)
Create `/etc/systemd/system/halalstocks-pipeline.service`:
```ini
[Unit]
Description=Halal Stocks Daily Update Pipeline
After=network.target postgresql.service

[Service]
Type=oneshot
User=your_user
WorkingDirectory=/path/to/halalstocks/backend
Environment="PATH=/usr/local/go/bin:/usr/bin:/bin"
ExecStart=/usr/local/go/bin/go run cmd/daily_update/main.go
```

Create `/etc/systemd/system/halalstocks-pipeline.timer`:
```ini
[Unit]
Description=Run Halal Stocks Pipeline Daily
Requires=halalstocks-pipeline.service

[Timer]
OnCalendar=daily
OnCalendar=02:00
Persistent=true

[Install]
WantedBy=timers.target
```

Enable and start:
```bash
sudo systemctl enable halalstocks-pipeline.timer
sudo systemctl start halalstocks-pipeline.timer
```

## Monitoring

The pipeline logs structured JSON to stdout. You can:
- Redirect to a file: `go run cmd/daily_update/main.go > pipeline.log 2>&1`
- Use `jq` to parse: `go run cmd/daily_update/main.go | jq '.symbol, .status'`
- Monitor with log aggregation tools

## Troubleshooting

### No symbols processed
- Check `tracked_symbols` table has entries with `is_tracked = TRUE`
- Verify API key is set correctly

### Provider failures
- Check API key is valid
- Verify rate limits (FMP: 250 requests/day free tier)
- Check network connectivity

### Database errors
- Verify PostgreSQL is running
- Check connection string in `.env`
- Ensure migrations are applied

## Next Steps

1. **Add more symbols**: Populate `tracked_symbols` with stocks you want to monitor
2. **Schedule runs**: Set up cron or systemd timer for daily updates
3. **Monitor results**: Check `shariah_results` and `shariah_result_history` tables
4. **Add more providers**: Implement additional providers for better data coverage

## Integration with Existing System

The pipeline works alongside your existing:
- ✅ API server (`cmd/api/main.go`)
- ✅ Ingestion service (`cmd/ingest/main.go`)
- ✅ Shariah screening (`internal/shariah/`)

The new pipeline uses the same database and can run independently or alongside existing services.


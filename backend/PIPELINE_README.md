# Production Data Pipeline for Islamic Stock Screening

This document describes the production-ready data pipeline system for fetching, aggregating, and screening stock data from multiple external APIs.

## Architecture Overview

The pipeline is designed with a modular, extensible architecture:

```
┌─────────────────┐
│  Daily Update   │
│     Pipeline    │
└────────┬────────┘
         │
         ├───► Provider Registry (Multi-API with Fallback)
         │     ├─── FMP Provider
         │     ├─── Alpha Vantage Provider
         │     └─── DataJockey Provider
         │
         ├───► Shariah Engine
         │     ├─── Activity Screening
         │     └─── Financial Ratio Analysis
         │
         └───► Repository (PostgreSQL)
               ├─── Stock Snapshots (Time-Series)
               ├─── Shariah Results (Latest)
               └─── Shariah History (Status Changes)
```

## Key Components

### 1. Unified Data Model (`internal/pipeline/models.go`)

**StockSnapshot**: Canonical internal representation of stock data from any provider
- Market data (price, market cap, shares)
- Income statement (revenue, income, interest)
- Balance sheet (assets, debt, cash)
- Cash flow statements
- Data quality assessment (COMPLETE, PARTIAL, INSUFFICIENT)

**ShariahResult**: Result of Shariah compliance evaluation
- Status: HALAL, HARAM, DOUBTFUL, NEEDS_REVIEW, MIXED
- Financial ratios used in evaluation
- Detailed breakdown (JSON)
- Grade (A, B, C, F)

### 2. Multi-Provider Architecture (`internal/pipeline/provider.go`)

**Provider Interface**: Standard interface for all data providers
```go
type Provider interface {
    Name() string
    FetchSnapshot(ctx context.Context, symbol, exchange string) (*StockSnapshot, error)
    FetchSnapshotsBulk(ctx context.Context, symbols, exchanges []string) (map[string]*StockSnapshot, []error)
    IsAvailable(ctx context.Context) bool
}
```

**Provider Registry**: Manages multiple providers with automatic fallback
- Tries providers in priority order
- Falls back to next provider if data is incomplete
- Returns best available snapshot even if partial

### 3. Shariah Engine (`internal/pipeline/shariah_engine.go`)

**ShariahEngine Interface**: Evaluates stock compliance
- Activity screening (business activity filters)
- Financial ratio screening (debt, interest income, cash ratios)
- Returns structured result with detailed breakdown

**Standard Implementation**:
- Integrates with existing `internal/shariah` package
- Calculates financial ratios
- Applies Shariah rules and thresholds
- Handles missing data gracefully

### 4. Repository Layer (`internal/pipeline/repository.go`)

**Database Operations**:
- `UpsertStock`: Update basic stock information
- `InsertSnapshot`: Store time-series fundamentals
- `UpsertLatestShariahResult`: Update latest compliance status
- `GetLastShariahResult`: Retrieve previous status for change detection
- `ListTrackedSymbols`: Get all symbols to process

**Automatic Status Change Tracking**:
- Database trigger logs status changes to `shariah_result_history`
- Tracks old → new status transitions
- Preserves financial ratios at time of change

### 5. Daily Update Pipeline (`internal/pipeline/daily_update.go`)

**Features**:
- Worker pool pattern for concurrent processing
- Per-symbol timeout (2 minutes)
- Comprehensive error handling (one failure doesn't stop batch)
- Statistics tracking (success, failures, status changes)
- Graceful shutdown on SIGINT/SIGTERM

**Process Flow**:
1. Get list of tracked symbols
2. For each symbol (in parallel):
   - Fetch snapshot from providers (with fallback)
   - Store snapshot in database
   - Evaluate Shariah compliance
   - Detect status changes
   - Update latest result
3. Log statistics and completion

## Database Schema

### Tables

**tracked_symbols**: Symbols to monitor
- `symbol`, `exchange` (unique)
- `is_tracked` (boolean)
- `priority` (processing order)

**stock_snapshots**: Time-series fundamentals
- All financial data fields
- `snapshot_date` (timestamp)
- `provider_name`, `data_quality`
- Unique constraint: (symbol, exchange, snapshot_date)

**shariah_results**: Latest compliance status
- `symbol`, `exchange` (unique)
- `status`, `grade`
- Financial ratios
- `evaluated_at`

**shariah_result_history**: Status change log
- Tracks old → new status transitions
- Automatically populated by database trigger
- Includes financial ratios at time of change

### Migrations

Run migrations:
```bash
migrate -path migrations -database "postgres://user:pass@localhost/halalstocks?sslmode=disable" up
```

## Configuration

### Environment Variables

```bash
# Database
DB_HOST=localhost
DB_PORT=5432
DB_USER=your_username
DB_PASSWORD=your_password
DB_NAME=halalstocks
DB_SSLMODE=disable

# Primary Provider (FMP)
STOCK_API_KEY=your_fmp_api_key
STOCK_API_PROVIDER=fmp

# Secondary Provider (Alpha Vantage)
ALPHA_VANTAGE_API_KEY=your_alpha_vantage_key

# Tertiary Provider (DataJockey)
DATAJOCKEY_API_KEY=your_datajockey_key

# Logging
LOG_LEVEL=info  # debug, info, warn, error
```

## Running the Pipeline

### Manual Run

```bash
go run cmd/daily_update/main.go
```

### Scheduled Run (Cron)

Add to crontab for daily execution at 2 AM:
```bash
0 2 * * * cd /path/to/backend && /usr/local/go/bin/go run cmd/daily_update/main.go >> /var/log/halalstocks/daily_update.log 2>&1
```

### Docker/Kubernetes

The pipeline can be run as a containerized job:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-stock-update
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: pipeline
            image: halalstocks-backend:latest
            command: ["go", "run", "cmd/daily_update/main.go"]
            env:
            - name: DB_HOST
              value: "postgres"
            - name: STOCK_API_KEY
              valueFrom:
                secretKeyRef:
                  name: api-keys
                  key: fmp-key
```

## Adding a New Provider

1. **Implement Provider Interface** (`internal/pipeline/providers/`)

```go
package providers

type NewProvider struct {
    apiKey string
    // ... other fields
}

func (p *NewProvider) Name() string {
    return "NewProvider"
}

func (p *NewProvider) FetchSnapshot(ctx context.Context, symbol, exchange string) (*pipeline.StockSnapshot, error) {
    // 1. Make API calls to fetch data
    // 2. Map API response to StockSnapshot
    // 3. Return snapshot
}

func (p *NewProvider) FetchSnapshotsBulk(ctx context.Context, symbols, exchanges []string) (map[string]*StockSnapshot, []error) {
    // Implement bulk fetch if API supports it
    // Otherwise, fetch individually with rate limiting
}

func (p *NewProvider) IsAvailable(ctx context.Context) bool {
    // Check if provider is available (API key valid, not rate limited, etc.)
}
```

2. **Register in Main** (`cmd/daily_update/main.go`)

```go
if cfg.NewProviderAPIKey != "" {
    newProvider := providers.NewNewProvider(cfg.NewProviderAPIKey, logger)
    providerList = append(providerList, newProvider)
}
```

3. **Add Configuration**

Add to `internal/config/config.go`:
```go
NewProviderAPIKey string
```

## Data Quality & Completeness

The pipeline uses a **data quality assessment** system:

- **COMPLETE**: All critical fields present (≥80% completeness)
- **PARTIAL**: Some critical fields missing (50-80% completeness)
- **INSUFFICIENT**: Too many fields missing (<50% completeness)

**Critical Fields** for Shariah screening:
- Revenue
- Total Assets
- Total Debt (can be 0)
- Cash and Equivalents
- Price
- Market Cap

If data is insufficient, the Shariah engine returns `NEEDS_REVIEW` status rather than making assumptions.

## Error Handling

- **Provider Failures**: Logged but don't stop pipeline (fallback to next provider)
- **Symbol Failures**: One symbol failure doesn't affect others
- **Database Errors**: Logged with context, pipeline continues
- **Timeout**: Each symbol has 2-minute timeout
- **Graceful Shutdown**: SIGINT/SIGTERM allows in-flight work to complete

## Monitoring & Observability

### Statistics

The pipeline tracks:
- Total symbols processed
- Success/failure counts
- Status changes detected
- Provider failure counts
- Duration

### Logging

Structured JSON logging with:
- Symbol and exchange context
- Provider names
- Error details
- Performance metrics

### Health Checks

Add health endpoint (optional):
```go
// GET /health
{
  "status": "healthy",
  "last_run": "2024-01-15T02:00:00Z",
  "symbols_processed": 1500,
  "success_rate": 0.98
}
```

## Performance Considerations

- **Concurrency**: Configurable worker pool (default: 5 workers)
- **Rate Limiting**: Built into providers (respects API limits)
- **Database Indexes**: Optimized for symbol + date queries
- **Bulk Operations**: Used when providers support it
- **Timeouts**: Prevent hanging on slow APIs

## Testing

### Unit Tests

```bash
go test ./internal/pipeline/...
```

### Integration Tests

```bash
# Requires test database
DB_NAME=halalstocks_test go test ./internal/pipeline/... -tags=integration
```

### Manual Testing

```bash
# Test single symbol
go run cmd/daily_update/main.go --symbol AAPL --exchange NASDAQ

# Test with debug logging
LOG_LEVEL=debug go run cmd/daily_update/main.go
```

## Troubleshooting

### Common Issues

1. **No providers available**
   - Check API keys in environment
   - Verify `STOCK_API_PROVIDER` is set correctly

2. **Database connection errors**
   - Verify `DB_*` environment variables
   - Check PostgreSQL is running
   - Verify database exists

3. **Rate limiting**
   - Reduce worker count
   - Add delays in provider implementations
   - Use bulk endpoints when available

4. **Incomplete data**
   - Check provider API responses
   - Verify API keys have correct permissions
   - Try different providers

## Future Enhancements

- [ ] Real-time updates (webhook-based)
- [ ] Provider health monitoring
- [ ] Automatic provider failover
- [ ] Data quality scoring improvements
- [ ] Historical data backfill
- [ ] Prometheus metrics export
- [ ] Alerting on status changes

## License

[Your License Here]


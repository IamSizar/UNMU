# Production Data Pipeline - Architecture Document

## Executive Summary

This document describes a production-ready, multi-provider data pipeline for Islamic stock screening. The system fetches stock fundamentals from multiple external APIs, aggregates and normalizes the data, runs Shariah compliance screening, and stores results in PostgreSQL with automatic change detection.

## Design Principles

1. **Modularity**: Easy to add new data providers
2. **Resilience**: Failures in one provider don't stop the pipeline
3. **Data Quality**: Explicit assessment and handling of incomplete data
4. **Extensibility**: Clear interfaces for adding features
5. **Observability**: Comprehensive logging and statistics

## System Architecture

### Component Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                    Daily Update Pipeline                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │   Worker 1    │  │   Worker 2   │  │   Worker N   │     │
│  └──────┬────────┘  └──────┬───────┘  └──────┬────────┘     │
└─────────┼──────────────────┼──────────────────┼──────────────┘
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │
          ┌──────────────────┴──────────────────┐
          │                                      │
    ┌─────▼─────┐                        ┌─────▼─────┐
    │  Provider │                        │ Shariah   │
    │  Registry │                        │  Engine   │
    └─────┬─────┘                        └─────┬─────┘
          │                                    │
    ┌─────┼─────┐                              │
    │     │     │                              │
┌───▼──┐ ┼ ┌───▼──┐                    ┌──────▼──────┐
│ FMP  │ │ │ Alpha│                    │  Activity   │
│      │ │ │Vant. │                    │  Checker    │
└──────┘ │ └──────┘                    └─────────────┘
         │                                    │
    ┌────▼────┐                        ┌──────▼──────┐
    │DataJockey│                       │   Ratio    │
    │         │                       │ Calculator  │
    └─────────┘                       └─────────────┘
          │                                    │
          └──────────────┬─────────────────────┘
                         │
                  ┌──────▼──────┐
                  │  Repository │
                  │ (PostgreSQL)│
                  └─────────────┘
```

## Data Flow

### 1. Symbol Discovery
```
tracked_symbols table → ListTrackedSymbols() → []SymbolExchange
```

### 2. Data Fetching (Multi-Provider with Fallback)
```
Symbol → Provider Registry
  ├─► Try Provider 1 (FMP)
  │   ├─► Success + Complete → Return
  │   └─► Partial/Fail → Continue
  ├─► Try Provider 2 (Alpha Vantage)
  │   ├─► Success + Complete → Return
  │   └─► Partial/Fail → Continue
  └─► Try Provider 3 (DataJockey)
      └─► Return best available (even if partial)
```

### 3. Data Storage
```
StockSnapshot → Repository
  ├─► UpsertStock() → tracked_symbols
  └─► InsertSnapshot() → stock_snapshots (time-series)
```

### 4. Shariah Evaluation
```
StockSnapshot → ShariahEngine.Evaluate()
  ├─► ActivityChecker.CheckActivity()
  │   └─► Uses existing shariah.CheckHaramActivity()
  ├─► RatioCalculator.CalculateRatios()
  │   ├─► Debt Ratio = TotalDebt / TotalAssets
  │   ├─► Haram Income = InterestIncome / Revenue
  │   └─► Cash Ratio = (Cash + ST Inv) / MarketCap
  └─► Apply Rules
      ├─► Activity Haram → HARAM (Grade F)
      ├─► Debt > 30% → HARAM (Grade F)
      ├─► Haram Income > 5% → HARAM (Grade F)
      ├─► Haram Income 3-5% → MIXED (Grade C)
      ├─► Haram Income 0-3% → MIXED (Grade B)
      └─► All Pass → HALAL (Grade A)
```

### 5. Status Change Detection
```
New ShariahResult → Repository
  ├─► GetLastShariahResult() → Previous Result
  ├─► Compare Status
  │   └─► If Changed:
  │       └─► Database Trigger → shariah_result_history
  └─► UpsertLatestShariahResult() → shariah_results
```

## Data Model

### StockSnapshot (Unified Internal Model)

```go
type StockSnapshot struct {
    // Identity
    Symbol, Exchange, CompanyName, Country, Sector, Industry, Description
    
    // Market Data
    Price, MarketCap, SharesOutstanding, Currency
    
    // Income Statement
    Revenue, OperatingIncome, NetIncome
    InterestIncome, InterestExpense, OtherIncome
    
    // Balance Sheet
    TotalAssets, TotalLiabilities, TotalDebt
    ShortTermDebt, LongTermDebt
    CashAndEquivalents, ShortTermInvestments
    
    // Cash Flow
    OperatingCashFlow, FinancingCashFlow, InterestPaid
    
    // Metadata
    FiscalYearEnd, LastReportDate, SnapshotDate
    ProviderName, DataQuality
}
```

**Data Quality Levels**:
- `COMPLETE`: ≥80% of critical fields present
- `PARTIAL`: 50-80% of critical fields present
- `INSUFFICIENT`: <50% of critical fields present

### ShariahResult

```go
type ShariahResult struct {
    Symbol, Exchange
    Status: HALAL | HARAM | DOUBTFUL | NEEDS_REVIEW | MIXED
    StatusReason: string
    DetailedBreakdown: JSON string
    EvaluatedAt: timestamp
    
    // Financial Ratios
    DebtRatio, HaramIncomeRatio, CashToMarketCapRatio, PurificationRate
    
    // Grade
    Grade: A | B | C | F
}
```

## Database Schema

### Time-Series Design

**stock_snapshots**: Stores historical fundamentals
- Unique constraint: `(symbol, exchange, snapshot_date)`
- Allows tracking changes over time
- Indexed for efficient queries

**shariah_results**: Latest status per symbol
- Unique constraint: `(symbol, exchange)`
- Always contains most recent evaluation

**shariah_result_history**: Status change log
- Automatically populated by database trigger
- Tracks transitions: `old_status → new_status`
- Includes financial ratios at time of change

### Indexes

```sql
-- Fast symbol lookups
CREATE INDEX idx_snapshots_symbol ON stock_snapshots(symbol, exchange);
CREATE INDEX idx_snapshots_date ON stock_snapshots(snapshot_date DESC);

-- Status queries
CREATE INDEX idx_shariah_results_status ON shariah_results(status);
CREATE INDEX idx_shariah_history_status_change ON shariah_result_history(old_status, new_status);
```

## Provider Architecture

### Interface Contract

All providers must implement:
```go
type Provider interface {
    Name() string
    FetchSnapshot(ctx, symbol, exchange) (*StockSnapshot, error)
    FetchSnapshotsBulk(ctx, symbols, exchanges) (map[string]*StockSnapshot, []error)
    IsAvailable(ctx) bool
}
```

### Fallback Strategy

1. **Priority Order**: Providers tried in registration order
2. **Completeness Check**: Snapshot must pass `IsComplete()` to be accepted
3. **Best Partial**: If no complete snapshot, return best partial
4. **Error Aggregation**: All errors collected for debugging

### Rate Limiting

Each provider implements its own rate limiting:
- **FMP**: 240 requests/minute (250ms delay)
- **Alpha Vantage**: 5 requests/minute (12s delay)
- **DataJockey**: 30 requests/minute (2s delay)

## Shariah Engine

### Two-Stage Evaluation

**Stage 1: Activity Screening**
- Checks sector, industry, description
- Uses keyword matching against prohibited activities
- If haram activity found → Immediate HARAM (Grade F)

**Stage 2: Financial Ratio Screening**
- Calculates ratios from fundamentals
- Applies AAOIFI thresholds:
  - Debt Ratio ≤ 30%
  - Haram Income Ratio ≤ 5%
- Returns appropriate status and grade

### Handling Missing Data

- **Insufficient Data**: Returns `NEEDS_REVIEW` (Grade C)
- **Partial Data**: Evaluates with available ratios
- **No Data**: Returns `DOUBTFUL` (Grade C)

**Safe Defaults**: Never assumes compliance when data is missing.

## Concurrency Model

### Worker Pool Pattern

```
Main Thread
  ├─► ListTrackedSymbols() → []SymbolExchange
  ├─► Create Job Channel (buffered)
  ├─► Start N Workers (goroutines)
  │   └─► Each worker:
  │       ├─► Read from job channel
  │       ├─► Process symbol (2min timeout)
  │       └─► Write result to results channel
  └─► Collect results, aggregate statistics
```

**Benefits**:
- Controlled concurrency (respects rate limits)
- Per-symbol timeout (prevents hanging)
- Graceful shutdown (SIGINT/SIGTERM)

## Error Handling Strategy

### Levels of Resilience

1. **Provider Level**: One provider failure → try next
2. **Symbol Level**: One symbol failure → continue with others
3. **Batch Level**: Collect all errors, log statistics

### Error Types

- **Provider Unavailable**: Skip, try next
- **API Rate Limit**: Log, continue (provider handles retry)
- **Timeout**: Log, mark as failed, continue
- **Database Error**: Log with context, continue
- **Invalid Data**: Log, mark as `NEEDS_REVIEW`, continue

## Performance Characteristics

### Throughput

- **Workers**: 5 concurrent (configurable)
- **Per Symbol**: ~2-5 seconds (depends on provider)
- **Daily Batch**: ~1500 symbols in ~30-60 minutes

### Resource Usage

- **Database Connections**: Pooled (default: 25)
- **Memory**: ~50MB per worker
- **Network**: Rate-limited by providers

### Scalability

- **Horizontal**: Run multiple pipeline instances (different symbol sets)
- **Vertical**: Increase worker count (respect rate limits)
- **Database**: Partition by symbol range if needed

## Monitoring & Observability

### Metrics Tracked

- Total symbols processed
- Success/failure counts
- Status changes detected
- Provider failure counts
- Processing duration
- Data quality distribution

### Logging

Structured JSON logs with:
- Symbol and exchange context
- Provider names
- Error details with stack traces
- Performance timings

### Health Checks

Optional HTTP endpoint:
```go
GET /health
{
  "status": "healthy",
  "last_run": "2024-01-15T02:00:00Z",
  "symbols_processed": 1500,
  "success_rate": 0.98
}
```

## Security Considerations

1. **API Keys**: Stored in environment variables, never in code
2. **Database**: Connection string from environment
3. **Secrets**: Use secret management (Vault, AWS Secrets Manager)
4. **Network**: All API calls use HTTPS
5. **Timeouts**: Prevent resource exhaustion

## Testing Strategy

### Unit Tests
- Provider implementations
- Shariah engine logic
- Repository operations

### Integration Tests
- End-to-end pipeline run
- Database operations
- Provider fallback logic

### Manual Testing
- Single symbol processing
- Provider switching
- Status change detection

## Deployment

### Local Development
```bash
go run cmd/daily_update/main.go
```

### Production (Cron)
```bash
0 2 * * * /path/to/daily_update >> /var/log/pipeline.log 2>&1
```

### Containerized (Kubernetes)
```yaml
apiVersion: batch/v1
kind: CronJob
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: pipeline
            image: halalstocks-backend:latest
            command: ["go", "run", "cmd/daily_update/main.go"]
```

## Future Enhancements

1. **Real-time Updates**: Webhook-based for critical symbols
2. **Provider Health**: Automatic health checks and failover
3. **Data Quality ML**: ML-based completeness scoring
4. **Historical Backfill**: Backfill missing historical data
5. **Metrics Export**: Prometheus metrics endpoint
6. **Alerting**: Notifications on status changes
7. **Caching**: Redis cache for frequently accessed symbols

## Conclusion

This pipeline provides a robust, extensible foundation for Islamic stock screening with:
- Multi-provider support with automatic fallback
- Comprehensive error handling
- Time-series data storage
- Automatic status change detection
- Production-ready observability

The modular design makes it easy to add new providers, enhance the Shariah engine, or extend functionality without major refactoring.


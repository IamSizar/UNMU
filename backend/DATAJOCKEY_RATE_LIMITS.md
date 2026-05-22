# DataJockey Rate Limits

## Current Issue

DataJockey API is returning "Too many requests from this API key, please try again later" when fetching fundamentals for multiple stocks.

## Solution Applied

1. **Reduced Rate Limiter**: Changed from 10 requests/second to **1 request per 2 seconds** (30 requests/minute)
2. **Rate Limit Detection**: Added detection for 429 status codes and "Too many requests" errors
3. **Automatic Backoff**: When rate limited, waits 10 seconds before next request

## Recommendations

### For Production Use:

1. **Batch Processing**: Process stocks in smaller batches with delays between batches
2. **Retry Logic**: Implement exponential backoff for rate limit errors
3. **Caching**: Cache fundamentals data to avoid repeated API calls
4. **Alternative**: Consider using Alpha Vantage or FMP for bulk ingestion, and DataJockey only for search/on-demand requests

### Current Rate Limiter Settings:

```go
limiter: rate.NewLimiter(rate.Every(2*time.Second), 1) // 1 request per 2 seconds
```

This means:
- **30 requests per minute**
- **1,800 requests per hour**
- **43,200 requests per day**

### DataJockey Free Tier Limits:

Based on the error messages, the free tier appears to have strict limits. You may need to:
- Upgrade to a paid plan for higher limits
- Use DataJockey only for on-demand searches
- Use Alpha Vantage or FMP for bulk ingestion

## Workaround

For now, the ingestion will:
1. Process stocks slowly (1 per 2 seconds)
2. Automatically wait 10 seconds when rate limited
3. Continue with remaining stocks after rate limit expires

This will take longer but should avoid hitting rate limits.


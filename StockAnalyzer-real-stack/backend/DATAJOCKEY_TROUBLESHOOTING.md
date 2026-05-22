# DataJockey API Troubleshooting

## Current Issue: 401 "No API key provided"

The DataJockey API is returning 401 errors, which means the authentication method might be incorrect.

## What We've Tried

1. ✅ Query parameter: `?api_key=...`
2. ✅ Header: `X-API-Key: ...`
3. ✅ Header: `Authorization: Bearer ...`

All methods return: `{"error": "No API key provided"}`

## Possible Issues

### 1. API Key Format
Your API key: `f87d23e621e7d523d7b2df3092e66d3f8459271006ab11ee9c59`

This looks like it might be:
- A different type of key (not a standard API key)
- Missing a prefix or suffix
- Needs to be activated/verified first

### 2. Base URL
Current: `https://api.datajockey.io/v1`

Might need to be:
- `https://datajockey.io/api/v1`
- `https://api.datajockey.io/api/v1`
- Different version number

### 3. Endpoints
Current endpoints we're using:
- `/v1/stocks`
- `/v1/fundamentals/{ticker}`
- `/v1/stocks/search`

These might be incorrect. Need to check DataJockey's actual API documentation.

## Next Steps

1. **Check DataJockey Dashboard**: Log into your DataJockey account and verify:
   - The API key is correct and active
   - There are any usage limits or restrictions
   - The correct base URL and endpoints

2. **Review API Documentation**: Visit https://datajockey.io/docs (if available) to see:
   - Correct authentication method
   - Correct base URL
   - Correct endpoint paths
   - Request/response format

3. **Test with curl**: Once we know the correct format, we can test:
   ```bash
   curl -X GET "https://correct-url.com/endpoint" \
     -H "Correct-Header: your-api-key"
   ```

## Alternative: Use FMP or Alpha Vantage

If DataJockey continues to have issues, you can switch back:

**FMP:**
```bash
# In .env:
STOCK_API_PROVIDER=fmp
STOCK_API_KEY=F6FegPuKcKze6tRJ8fw7Fd57fmUDCReU
```

**Alpha Vantage:**
```bash
# In .env:
STOCK_API_PROVIDER=alphavantage
ALPHA_VANTAGE_API_KEY=PM0TRN8263MZLHY8
```

## Need Help?

Please check:
1. Your DataJockey account dashboard for the correct API key format
2. DataJockey's API documentation for authentication method
3. Share the correct authentication format so we can update the provider


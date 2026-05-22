package marketdata

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"

	"golang.org/x/time/rate"
)

// DefaultProvider is a flexible provider that can work with various stock APIs
type DefaultProvider struct {
	apiKey  string
	baseURL string
	client  *http.Client
	limiter *rate.Limiter
}

// NewDefaultProvider creates a new default provider
func NewDefaultProvider(apiKey, baseURL string) *DefaultProvider {
	return &DefaultProvider{
		apiKey:  apiKey,
		baseURL: baseURL,
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		limiter: rate.NewLimiter(rate.Every(time.Second), 10), // 10 requests per second
	}
}

// FetchStockUniverse fetches stocks for a region
// This is a template - adjust based on your actual API
func (p *DefaultProvider) FetchStockUniverse(regionCode string) ([]StockFromAPI, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return nil, fmt.Errorf("rate limit error: %w", err)
	}

	// Example endpoint - adjust based on your API
	endpoint := fmt.Sprintf("%s/v1/stocks", p.baseURL)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	// Add API key as header (common pattern)
	req.Header.Set("X-API-Key", p.apiKey)
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", p.apiKey))
	req.Header.Set("Content-Type", "application/json")

	// Add query parameters
	q := req.URL.Query()
	q.Set("region", regionCode)
	q.Set("active", "true")
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch stocks: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, fmt.Errorf("failed to read response: %w", err)
	}

	// Parse response - adjust based on your API response format
	var apiResponse struct {
		Data []StockFromAPI `json:"data"`
	}

	if err := json.Unmarshal(body, &apiResponse); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return apiResponse.Data, nil
}

// FetchFundamentalsBatch fetches financial data for multiple tickers
func (p *DefaultProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
	var results []FundamentalsFromAPI

	for _, ticker := range tickers {
		ctx := context.Background()
		if err := p.limiter.Wait(ctx); err != nil {
			continue
		}

		endpoint := fmt.Sprintf("%s/v1/fundamentals/%s", p.baseURL, ticker)
		req, err := http.NewRequest("GET", endpoint, nil)
		if err != nil {
			continue
		}

		req.Header.Set("X-API-Key", p.apiKey)
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", p.apiKey))

		resp, err := p.client.Do(req)
		if err != nil {
			continue
		}

		if resp.StatusCode == http.StatusOK {
			var fundamental FundamentalsFromAPI
			if err := json.NewDecoder(resp.Body).Decode(&fundamental); err == nil {
				results = append(results, fundamental)
			}
		}
		resp.Body.Close()
	}

	return results, nil
}

// SearchStocks searches for stocks by name or ticker
func (p *DefaultProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return nil, fmt.Errorf("rate limit error: %w", err)
	}

	endpoint := fmt.Sprintf("%s/v1/search", p.baseURL)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("X-API-Key", p.apiKey)
	req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", p.apiKey))

	q := req.URL.Query()
	q.Set("q", query)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to search stocks: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var apiResponse struct {
		Results []StockFromAPI `json:"results"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&apiResponse); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	return apiResponse.Results, nil
}

// FetchIndexes implements MarketDataProvider
func (p *DefaultProvider) FetchIndexes() ([]IndexData, error) {
	return []IndexData{}, nil
}
func (p *DefaultProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	return FearAndGreedData{}, nil
}

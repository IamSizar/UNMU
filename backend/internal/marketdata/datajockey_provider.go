package marketdata

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"strings"
	"time"

	"golang.org/x/time/rate"
)

// DataJockeyProvider implements MarketDataProvider for DataJockey API
type DataJockeyProvider struct {
	apiKey  string
	baseURL string
	client  *http.Client
	limiter *rate.Limiter
}

// NewDataJockeyProvider creates a new DataJockey provider
func NewDataJockeyProvider(apiKey string) *DataJockeyProvider {
	return &DataJockeyProvider{
		apiKey:  apiKey,
		baseURL: "https://api.datajockey.io/v0",
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		limiter: rate.NewLimiter(rate.Every(2*time.Second), 1), // 1 request per 2 seconds (30 per minute)
	}
}

// DataJockeyStockResponse represents stock listing from DataJockey
type DataJockeyStockResponse struct {
	Symbol    string `json:"symbol"`
	Name      string `json:"name"`
	Exchange  string `json:"exchange"`
	Sector    string `json:"sector"`
	Industry  string `json:"industry"`
	Country   string `json:"country"`
	MarketCap int64  `json:"market_cap"`
}

// DataJockeyFundamentalsResponse represents fundamentals from DataJockey
type DataJockeyFundamentalsResponse struct {
	Currency    string `json:"currency"`
	CompanyInfo struct {
		CIK    string `json:"cik"`
		Ticker string `json:"ticker"`
		Name   string `json:"name"`
	} `json:"company_info"`
	FinancialData struct {
		Annual struct {
			TotalAssets map[string]float64 `json:"total_assets"`
			TotalDebt   map[string]float64 `json:"total_debt"`
			Revenue     map[string]float64 `json:"revenue"`
			NetIncome   map[string]float64 `json:"net_income"`
		} `json:"annual"`
	} `json:"financial_data"`
}

// FetchStockUniverse fetches all stocks
// Note: DataJockey doesn't have a stock list endpoint, so we return a predefined list
// Users should use the search feature to find stocks by ticker
func (p *DataJockeyProvider) FetchStockUniverse(regionCode string) ([]StockFromAPI, error) {
	// DataJockey doesn't provide a stock list endpoint
	// Return a predefined list of popular stocks by region
	popularStocks := p.getPopularStocksByRegion(regionCode)

	var stocks []StockFromAPI
	for _, tickerExchange := range popularStocks {
		parts := strings.Split(tickerExchange, ":")
		if len(parts) != 2 {
			continue
		}
		ticker := parts[0]
		exchange := parts[1]

		stockRegion := p.getRegionFromExchange(exchange)
		if regionCode != "GLOBAL" && stockRegion != regionCode {
			continue
		}

		stocks = append(stocks, StockFromAPI{
			Ticker:     ticker,
			Exchange:   exchange,
			Name:       ticker, // Will be updated when fundamentals are fetched
			RegionCode: stockRegion,
		})
	}

	return stocks, nil
}

// getPopularStocksByRegion returns a list of popular stock tickers:exchange by region
func (p *DataJockeyProvider) getPopularStocksByRegion(regionCode string) []string {
	usStocks := []string{
		"AAPL:NASDAQ", "MSFT:NASDAQ", "GOOGL:NASDAQ", "AMZN:NASDAQ", "TSLA:NASDAQ",
		"META:NASDAQ", "NVDA:NASDAQ", "JPM:NYSE", "V:NYSE", "JNJ:NYSE",
		"WMT:NYSE", "PG:NYSE", "MA:NYSE", "DIS:NYSE", "NFLX:NASDAQ",
		"BAC:NYSE", "XOM:NYSE", "CVX:NYSE", "HD:NYSE", "MCD:NYSE",
	}

	gccStocks := []string{
		"2222:TADAWUL", "1120:TADAWUL", "2010:TADAWUL", // Saudi stocks
		"EMAAR:DFM", "ADCB:ADX", // UAE stocks
	}

	asiaStocks := []string{
		"TCS:NSE", "RELIANCE:NSE", "INFY:NSE", // India
		"0700:HKEX", "0941:HKEX", // Hong Kong
	}

	euStocks := []string{
		"ASML:AMS", "SAP:FRA", "NOVN:SWX", // Europe
	}

	switch regionCode {
	case "US":
		return usStocks
	case "GCC", "MENA":
		return gccStocks
	case "ASIA":
		return asiaStocks
	case "EU":
		return euStocks
	case "CN":
		return []string{"BABA:NYSE", "JD:NASDAQ", "NIO:NYSE"} // Chinese stocks listed in US
	case "GLOBAL":
		return append(append(append(usStocks, gccStocks...), asiaStocks...), euStocks...)
	default:
		return usStocks
	}
}

// FetchFundamentalsBatch fetches financial data for multiple tickers with parallel processing
func (p *DataJockeyProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
	if len(tickers) == 0 {
		return []FundamentalsFromAPI{}, nil
	}

	// Use channels for concurrent processing with rate limiting
	type result struct {
		data FundamentalsFromAPI
		err  error
	}

	resultsChan := make(chan result, len(tickers))
	semaphore := make(chan struct{}, 3) // Limit concurrent requests to 3

	// Fetch fundamentals in parallel with rate limiting
	for _, ticker := range tickers {
		go func(t string) {
			semaphore <- struct{}{}        // Acquire semaphore
			defer func() { <-semaphore }() // Release semaphore

			ctx := context.Background()
			if err := p.limiter.Wait(ctx); err != nil {
				resultsChan <- result{err: err}
				return
			}

			fundamental, err := p.fetchSingleFundamental(t)
			if err != nil {
				resultsChan <- result{err: err}
				return
			}

			if fundamental != nil {
				resultsChan <- result{data: *fundamental}
			} else {
				resultsChan <- result{err: fmt.Errorf("no data for ticker %s", t)}
			}
		}(ticker)
	}

	// Collect results
	var results []FundamentalsFromAPI
	for i := 0; i < len(tickers); i++ {
		res := <-resultsChan
		if res.err == nil {
			results = append(results, res.data)
		}
	}

	return results, nil
}

// fetchSingleFundamental fetches fundamentals for a single ticker
func (p *DataJockeyProvider) fetchSingleFundamental(ticker string) (*FundamentalsFromAPI, error) {
	endpoint := fmt.Sprintf("%s/company/financials", p.baseURL)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("Content-Type", "application/json")

	q := req.URL.Query()
	q.Set("apikey", p.apiKey)
	q.Set("ticker", ticker)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)

	if resp.StatusCode != http.StatusOK {
		if resp.StatusCode == 429 || strings.Contains(string(bodyBytes), "Too many requests") {
			log.Printf("DataJockey rate limit hit for %s, waiting...", ticker)
			time.Sleep(10 * time.Second)
		}
		return nil, fmt.Errorf("API error: %d", resp.StatusCode)
	}

	var fundamental DataJockeyFundamentalsResponse
	if err := json.Unmarshal(bodyBytes, &fundamental); err != nil {
		return nil, err
	}

	if strings.Contains(string(bodyBytes), "error") {
		return nil, fmt.Errorf("API returned error for ticker %s", ticker)
	}

	// Get the latest year's data
	var latestYear string
	allYears := make(map[string]bool)
	for year := range fundamental.FinancialData.Annual.TotalAssets {
		allYears[year] = true
	}
	for year := range fundamental.FinancialData.Annual.Revenue {
		allYears[year] = true
	}
	for year := range fundamental.FinancialData.Annual.TotalDebt {
		allYears[year] = true
	}
	for year := range fundamental.FinancialData.Annual.NetIncome {
		allYears[year] = true
	}

	for year := range allYears {
		if latestYear == "" || year > latestYear {
			latestYear = year
		}
	}

	if latestYear == "" {
		return nil, fmt.Errorf("no financial data available for ticker %s", ticker)
	}

	var totalAssets, totalDebt, totalRevenue, netIncome float64
	if val, ok := fundamental.FinancialData.Annual.TotalAssets[latestYear]; ok {
		totalAssets = val
	}
	if val, ok := fundamental.FinancialData.Annual.TotalDebt[latestYear]; ok {
		totalDebt = val
	}
	if val, ok := fundamental.FinancialData.Annual.Revenue[latestYear]; ok {
		totalRevenue = val
	}
	if val, ok := fundamental.FinancialData.Annual.NetIncome[latestYear]; ok {
		netIncome = val
	}

	asOfDateStr := fmt.Sprintf("%s-12-31", latestYear)
	rawJSON, _ := json.Marshal(fundamental)

	return &FundamentalsFromAPI{
		Ticker:            fundamental.CompanyInfo.Ticker,
		CompanyName:       fundamental.CompanyInfo.Name, // Extract company name from DataJockey response
		TotalAssets:       totalAssets,
		TotalDebt:         totalDebt,
		CashAndEquiv:      0,
		TotalRevenue:      totalRevenue,
		InterestIncome:    0,
		InterestExpense:   0,
		NetIncome:         netIncome,
		DividendsPerShare: 0,
		AsOfDate:          asOfDateStr,
		RawJSON:           string(rawJSON),
	}, nil
}

// SearchStocks searches for stocks by name or ticker
func (p *DataJockeyProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return nil, fmt.Errorf("rate limit error: %w", err)
	}

	// DataJockey doesn't have a search endpoint
	// Try to fetch fundamentals for the query (assuming it's a ticker)
	// If successful, return the stock
	endpoint := fmt.Sprintf("%s/company/financials", p.baseURL)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")

	q := req.URL.Query()
	q.Set("apikey", p.apiKey)
	q.Set("ticker", strings.ToUpper(query)) // Assume query is a ticker
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to search stocks: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		// Ticker not found or invalid
		return []StockFromAPI{}, nil
	}

	bodyBytes, _ := io.ReadAll(resp.Body)
	var fundamental DataJockeyFundamentalsResponse
	if err := json.Unmarshal(bodyBytes, &fundamental); err != nil {
		return []StockFromAPI{}, nil
	}

	// If we got fundamentals, the ticker exists
	stock := StockFromAPI{
		Ticker:     fundamental.CompanyInfo.Ticker,
		Exchange:   "NYSE", // Default, DataJockey doesn't provide exchange in fundamentals
		Name:       fundamental.CompanyInfo.Name,
		RegionCode: "US", // Default, can be improved
	}

	return []StockFromAPI{stock}, nil
}

// FetchIndexes implements MarketDataProvider
func (p *DataJockeyProvider) FetchIndexes() ([]IndexData, error) {
	return []IndexData{}, nil
}

// FetchFearAndGreed implements MarketDataProvider
func (p *DataJockeyProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	return FearAndGreedData{}, nil
}

// FetchExchangeRate implements MarketDataProvider
func (p *DataJockeyProvider) FetchExchangeRate(from, to string) (float64, error) {
	if from == to {
		return 1.0, nil
	}
	return 0, fmt.Errorf("FetchExchangeRate not implemented for DataJockeyProvider")
}

// Helper functions
func (p *DataJockeyProvider) getRegionFromExchange(exchange string) string {
	exchange = strings.ToUpper(exchange)

	// US exchanges
	if p.contains([]string{"NASDAQ", "NYSE", "AMEX", "OTC"}, exchange) {
		return "US"
	}

	// GCC/MENA
	if p.contains([]string{"TADAWUL", "DFM", "ADX", "BHB", "KSE", "MSM"}, exchange) {
		return "GCC"
	}

	// Europe
	if p.contains([]string{"LSE", "FRA", "XETR", "AMS", "MIL", "PAR", "SWX"}, exchange) {
		return "EU"
	}

	// Asia
	if p.contains([]string{"NSE", "BSE", "SGX", "KLSE", "IDX"}, exchange) {
		return "ASIA"
	}

	// China
	if p.contains([]string{"SSE", "SZSE", "HKEX"}, exchange) {
		return "CN"
	}

	return "GLOBAL"
}

func (p *DataJockeyProvider) contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

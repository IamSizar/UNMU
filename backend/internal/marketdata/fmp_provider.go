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

// FMPProvider implements MarketDataProvider for Financial Modeling Prep API
type FMPProvider struct {
	apiKey  string
	baseURL string
	client  *http.Client
	limiter *rate.Limiter
}

// NewFMPProvider creates a new FMP provider
func NewFMPProvider(apiKey string) *FMPProvider {
	return &FMPProvider{
		apiKey:  apiKey,
		baseURL: "https://financialmodelingprep.com/api/v3",
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		limiter: rate.NewLimiter(rate.Every(time.Second), 5), // 5 requests per second (FMP free tier limit)
	}
}

// FMPStockResponse represents FMP stock listing response
type FMPStockResponse struct {
	Symbol            string  `json:"symbol"`
	Name              string  `json:"name"`
	Price             float64 `json:"price"`
	Exchange          string  `json:"exchange"`
	ExchangeShortName string  `json:"exchangeShortName"`
	Type              string  `json:"type"`
	Region            string  `json:"region"`
	Currency          string  `json:"currency"`
	MarketCap         int64   `json:"marketCap"`
}

// FMPProfileResponse represents company profile from FMP
type FMPProfileResponse struct {
	Symbol            string  `json:"symbol"`
	Price             float64 `json:"price"`
	Beta              float64 `json:"beta"`
	VolAvg            int64   `json:"volAvg"`
	MktCap            int64   `json:"mktCap"`
	LastDiv           float64 `json:"lastDiv"`
	Range             string  `json:"range"`
	Changes           float64 `json:"changes"`
	CompanyName       string  `json:"companyName"`
	Currency          string  `json:"currency"`
	CIK               string  `json:"cik"`
	ISIN              string  `json:"isin"`
	CUSIP             string  `json:"cusip"`
	Exchange          string  `json:"exchange"`
	ExchangeShortName string  `json:"exchangeShortName"`
	Industry          string  `json:"industry"`
	Website           string  `json:"website"`
	Description       string  `json:"description"`
	CEO               string  `json:"ceo"`
	Sector            string  `json:"sector"`
	Country           string  `json:"country"`
	FullTimeEmployees string  `json:"fullTimeEmployees"`
	Phone             string  `json:"phone"`
	Address           string  `json:"address"`
	City              string  `json:"city"`
	State             string  `json:"state"`
	Zip               string  `json:"zip"`
	DCFDiff           float64 `json:"dcfDiff"`
	DCF               float64 `json:"dcf"`
	Image             string  `json:"image"`
	IPODate           string  `json:"ipoDate"`
	DefaultImage      bool    `json:"defaultImage"`
	IsEtf             bool    `json:"isEtf"`
	IsActivelyTrading bool    `json:"isActivelyTrading"`
}

// FMPIncomeStatementResponse represents income statement from FMP
type FMPIncomeStatementResponse struct {
	Date                             string  `json:"date"`
	Symbol                           string  `json:"symbol"`
	ReportedCurrency                 string  `json:"reportedCurrency"`
	Revenue                          float64 `json:"revenue"`
	CostOfRevenue                    float64 `json:"costOfRevenue"`
	GrossProfit                      float64 `json:"grossProfit"`
	ResearchAndDevelopmentExpenses   float64 `json:"researchAndDevelopmentExpenses"`
	GeneralAndAdministrativeExpenses float64 `json:"generalAndAdministrativeExpenses"`
	TotalExpenses                    float64 `json:"totalExpenses"`
	OperatingIncome                  float64 `json:"operatingIncome"`
	InterestExpense                  float64 `json:"interestExpense"`
	InterestIncome                   float64 `json:"interestIncome"`
	NetIncome                        float64 `json:"netIncome"`
}

// FMPBalanceSheetResponse represents balance sheet from FMP
type FMPBalanceSheetResponse struct {
	Date                    string  `json:"date"`
	Symbol                  string  `json:"symbol"`
	ReportedCurrency        string  `json:"reportedCurrency"`
	TotalAssets             float64 `json:"totalAssets"`
	TotalDebt               float64 `json:"totalDebt"`
	CashAndCashEquivalents  float64 `json:"cashAndCashEquivalents"`
	TotalLiabilities        float64 `json:"totalLiabilities"`
	TotalStockholdersEquity float64 `json:"totalStockholdersEquity"`
}

// FetchStockUniverse fetches stocks for a given region
// Note: FMP's /stock/list endpoint is deprecated. This implementation uses
// a predefined list of popular stocks and fetches their profiles.
func (p *FMPProvider) FetchStockUniverse(regionCode string) ([]StockFromAPI, error) {
	// Define popular stocks by region
	popularStocks := p.getPopularStocksByRegion(regionCode)

	if len(popularStocks) == 0 {
		return []StockFromAPI{}, nil
	}

	var stocks []StockFromAPI
	regionMap := mapRegionCode(regionCode)

	// Fetch profiles for each stock (batch in chunks to respect rate limits)
	chunkSize := 5 // Process 5 stocks at a time
	for i := 0; i < len(popularStocks); i += chunkSize {
		end := i + chunkSize
		if end > len(popularStocks) {
			end = len(popularStocks)
		}

		for _, tickerExchange := range popularStocks[i:end] {
			parts := strings.Split(tickerExchange, ":")
			if len(parts) != 2 {
				continue
			}
			ticker := parts[0]
			exchange := parts[1]

			ctx := context.Background()
			if err := p.limiter.Wait(ctx); err != nil {
				continue
			}

			profile, err := p.fetchProfile(ticker)
			if err != nil {
				// If profile fetch fails, create basic stock entry
				stockRegion := getRegionFromExchange(exchange)
				if regionCode == "GLOBAL" || stockRegion == regionCode || contains(regionMap, exchange) {
					stocks = append(stocks, StockFromAPI{
						Ticker:     ticker,
						Exchange:   exchange,
						Name:       ticker,
						RegionCode: stockRegion,
					})
				}
				continue
			}

			stockRegion := getRegionFromExchange(profile.Exchange)

			// Filter by region if specified
			if regionCode != "GLOBAL" && stockRegion != regionCode && !contains(regionMap, profile.Exchange) {
				continue
			}

			var marketCap int64
			if profile.MktCap > 0 {
				marketCap = profile.MktCap
			}

			stocks = append(stocks, StockFromAPI{
				Ticker:      profile.Symbol,
				Exchange:    profile.Exchange,
				Name:        profile.CompanyName,
				Country:     profile.Country,
				RegionCode:  stockRegion,
				Sector:      profile.Sector,
				Industry:    profile.Industry,
				Description: profile.Description,
				MarketCap:   marketCap,
			})
		}
	}

	return stocks, nil
}

// getPopularStocksByRegion returns a list of popular stock tickers:exchange by region
func (p *FMPProvider) getPopularStocksByRegion(regionCode string) []string {
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

// fetchProfile fetches company profile for a ticker
func (p *FMPProvider) fetchProfile(ticker string) (*FMPProfileResponse, error) {
	endpoint := fmt.Sprintf("%s/profile/%s", p.baseURL, ticker)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(body))
	}

	var profiles []FMPProfileResponse
	if err := json.NewDecoder(resp.Body).Decode(&profiles); err != nil {
		return nil, err
	}

	if len(profiles) == 0 {
		return nil, fmt.Errorf("no profile found for %s", ticker)
	}

	return &profiles[0], nil
}

// FetchFundamentalsBatch fetches financial data for multiple tickers
func (p *FMPProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
	var results []FundamentalsFromAPI

	for _, ticker := range tickers {
		ctx := context.Background()
		if err := p.limiter.Wait(ctx); err != nil {
			log.Printf("Rate limit error for %s: %v", ticker, err)
			continue
		}

		// Fetch income statement
		incomeStmt, err := p.fetchIncomeStatement(ticker)
		if err != nil {
			log.Printf("Error fetching income statement for %s: %v", ticker, err)
			continue
		}

		// Fetch balance sheet
		balanceSheet, err := p.fetchBalanceSheet(ticker)
		if err != nil {
			log.Printf("Error fetching balance sheet for %s: %v", ticker, err)
			continue
		}

		// Fetch profile to get company name
		profile, _ := p.fetchProfile(ticker)
		companyName := ""
		if profile != nil {
			companyName = profile.CompanyName
		}

		// Combine data
		fundamental := FundamentalsFromAPI{
			Ticker:            ticker,
			CompanyName:       companyName,
			TotalAssets:       balanceSheet.TotalAssets,
			TotalDebt:         balanceSheet.TotalDebt,
			CashAndEquiv:      balanceSheet.CashAndCashEquivalents,
			TotalRevenue:      incomeStmt.Revenue,
			InterestIncome:    incomeStmt.InterestIncome,
			InterestExpense:   incomeStmt.InterestExpense,
			NetIncome:         incomeStmt.NetIncome,
			DividendsPerShare: 0, // FMP doesn't provide this directly
			AsOfDate:          incomeStmt.Date,
		}

		results = append(results, fundamental)
		log.Printf("Successfully fetched fundamentals for %s", ticker)
	}

	return results, nil
}

// SearchStocks searches for stocks by name or ticker
func (p *FMPProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return nil, fmt.Errorf("rate limit error: %w", err)
	}

	endpoint := fmt.Sprintf("%s/search", p.baseURL)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	q := req.URL.Query()
	q.Set("query", query)
	q.Set("limit", "50")
	q.Set("apikey", p.apiKey)
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

	var fmpStocks []FMPStockResponse
	if err := json.NewDecoder(resp.Body).Decode(&fmpStocks); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	var stocks []StockFromAPI
	for _, fmpStock := range fmpStocks {
		stocks = append(stocks, StockFromAPI{
			Ticker:     fmpStock.Symbol,
			Exchange:   fmpStock.Exchange,
			Name:       fmpStock.Name,
			Country:    fmpStock.Region,
			RegionCode: getRegionFromExchange(fmpStock.Exchange),
			MarketCap:  fmpStock.MarketCap,
		})
	}

	return stocks, nil
}

// fetchIncomeStatement fetches income statement for a ticker
func (p *FMPProvider) fetchIncomeStatement(ticker string) (*FMPIncomeStatementResponse, error) {
	endpoint := fmt.Sprintf("%s/income-statement/%s", p.baseURL, ticker)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("period", "annual")
	q.Set("limit", "1")
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		log.Printf("FMP income statement API error for %s: status %d, body: %s", ticker, resp.StatusCode, string(bodyBytes))
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var statements []FMPIncomeStatementResponse
	if err := json.Unmarshal(bodyBytes, &statements); err != nil {
		log.Printf("FMP income statement parse error for %s: %v, body: %s", ticker, err, string(bodyBytes))
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if len(statements) == 0 {
		return nil, fmt.Errorf("no income statement found")
	}

	return &statements[0], nil
}

// fetchBalanceSheet fetches balance sheet for a ticker
func (p *FMPProvider) fetchBalanceSheet(ticker string) (*FMPBalanceSheetResponse, error) {
	endpoint := fmt.Sprintf("%s/balance-sheet-statement/%s", p.baseURL, ticker)
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("period", "annual")
	q.Set("limit", "1")
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		log.Printf("FMP balance sheet API error for %s: status %d, body: %s", ticker, resp.StatusCode, string(bodyBytes))
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var statements []FMPBalanceSheetResponse
	if err := json.Unmarshal(bodyBytes, &statements); err != nil {
		log.Printf("FMP balance sheet parse error for %s: %v, body: %s", ticker, err, string(bodyBytes))
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	if len(statements) == 0 {
		return nil, fmt.Errorf("no balance sheet found")
	}

	return &statements[0], nil
}

// FetchIndexes implements MarketDataProvider
func (p *FMPProvider) FetchIndexes() ([]IndexData, error) {
	return []IndexData{}, nil
}

// FetchFearAndGreed implements MarketDataProvider
func (p *FMPProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	return FearAndGreedData{}, nil
}

// FetchExchangeRate implements MarketDataProvider
func (p *FMPProvider) FetchExchangeRate(from, to string) (float64, error) {
	if from == to {
		return 1.0, nil
	}
	return 0, fmt.Errorf("FetchExchangeRate not implemented for FMPProvider")
}

// Helper functions
func getRegionFromExchange(exchange string) string {
	exchange = strings.ToUpper(exchange)

	// US exchanges
	if contains([]string{"NASDAQ", "NYSE", "AMEX", "OTC"}, exchange) {
		return "US"
	}

	// GCC/MENA
	if contains([]string{"TADAWUL", "DFM", "ADX", "BHB", "KSE", "MSM"}, exchange) {
		return "GCC"
	}

	// Europe
	if contains([]string{"LSE", "FRA", "XETR", "AMS", "MIL", "PAR"}, exchange) {
		return "EU"
	}

	// Asia
	if contains([]string{"NSE", "BSE", "SGX", "KLSE", "IDX"}, exchange) {
		return "ASIA"
	}

	// China
	if contains([]string{"SSE", "SZSE", "HKEX"}, exchange) {
		return "CN"
	}

	return "GLOBAL"
}

func mapRegionCode(regionCode string) []string {
	regionMap := map[string][]string{
		"US":     {"NASDAQ", "NYSE", "AMEX", "OTC"},
		"GCC":    {"TADAWUL", "DFM", "ADX", "BHB", "KSE", "MSM"},
		"MENA":   {"TADAWUL", "DFM", "ADX", "BHB", "KSE", "MSM", "EGX"},
		"EU":     {"LSE", "FRA", "XETR", "AMS", "MIL", "PAR"},
		"ASIA":   {"NSE", "BSE", "SGX", "KLSE", "IDX"},
		"CN":     {"SSE", "SZSE", "HKEX"},
		"GLOBAL": {},
	}

	if exchanges, ok := regionMap[regionCode]; ok {
		return exchanges
	}
	return []string{}
}

func contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

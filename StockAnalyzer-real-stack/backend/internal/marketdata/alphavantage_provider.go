package marketdata

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/time/rate"
)

// AlphaVantageQuoteResponse represents global quote from Alpha Vantage
type AlphaVantageQuoteResponse struct {
	Quote struct {
		Symbol           string `json:"01. symbol"`
		Open             string `json:"02. open"`
		High             string `json:"03. high"`
		Low              string `json:"04. low"`
		Price            string `json:"05. price"`
		Volume           string `json:"06. volume"`
		LatestTradingDay string `json:"07. latest trading day"`
		PreviousClose    string `json:"08. previous close"`
		Change           string `json:"09. change"`
		ChangePercent    string `json:"10. change percent"`
	} `json:"Global Quote"`
}

// AlphaVantageProvider implements MarketDataProvider for Alpha Vantage API
type AlphaVantageProvider struct {
	apiKey  string
	baseURL string
	client  *http.Client
	limiter *rate.Limiter

	mu              sync.RWMutex
	cachedIndices   []IndexData
	cachedSentiment FearAndGreedData
	store           MarketStore
}

// NewAlphaVantageProvider creates a new Alpha Vantage provider
func NewAlphaVantageProvider(apiKey string) *AlphaVantageProvider {
	return &AlphaVantageProvider{
		apiKey:  apiKey,
		baseURL: "https://www.alphavantage.co/query",
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		limiter: rate.NewLimiter(rate.Every(12*time.Second), 1), // 5 calls per minute = 1 call per 12 seconds
	}
}

// SetStore sets the persistence store for the provider
func (p *AlphaVantageProvider) SetStore(store MarketStore) {
	p.store = store
	// Load initial data from store if available
	p.loadFromStore()
}

func (p *AlphaVantageProvider) loadFromStore() {
	if p.store == nil {
		return
	}

	indices, err := p.store.GetAllIndexes()
	if err == nil && len(indices) > 0 {
		p.mu.Lock()
		p.cachedIndices = indices
		p.mu.Unlock()
		log.Printf("Loaded %d indexes from DB", len(indices))
	}

	sentiment, err := p.store.GetLatestSentiment()
	if err == nil && sentiment.Label != "" {
		p.mu.Lock()
		p.cachedSentiment = sentiment
		p.mu.Unlock()
		log.Printf("Loaded sentiment (%s) from DB", sentiment.Label)
	}
}

// AlphaVantageOverviewResponse represents company overview from Alpha Vantage
type AlphaVantageOverviewResponse struct {
	Symbol                     string `json:"Symbol"`
	Name                       string `json:"Name"`
	Description                string `json:"Description"`
	CIK                        string `json:"CIK"`
	Exchange                   string `json:"Exchange"`
	Currency                   string `json:"Currency"`
	Country                    string `json:"Country"`
	Sector                     string `json:"Sector"`
	Industry                   string `json:"Industry"`
	Address                    string `json:"Address"`
	FullTimeEmployees          string `json:"FullTimeEmployees"`
	FiscalYearEnd              string `json:"FiscalYearEnd"`
	LatestQuarter              string `json:"LatestQuarter"`
	MarketCapitalization       string `json:"MarketCapitalization"`
	EBITDA                     string `json:"EBITDA"`
	PERatio                    string `json:"PERatio"`
	PEGRatio                   string `json:"PEGRatio"`
	BookValue                  string `json:"BookValue"`
	DividendPerShare           string `json:"DividendPerShare"`
	DividendYield              string `json:"DividendYield"`
	EPS                        string `json:"EPS"`
	RevenuePerShareTTM         string `json:"RevenuePerShareTTM"`
	ProfitMargin               string `json:"ProfitMargin"`
	OperatingMarginTTM         string `json:"OperatingMarginTTM"`
	ReturnOnAssetsTTM          string `json:"ReturnOnAssetsTTM"`
	ReturnOnEquityTTM          string `json:"ReturnOnEquityTTM"`
	RevenueTTM                 string `json:"RevenueTTM"`
	GrossProfitTTM             string `json:"GrossProfitTTM"`
	DilutedEPSTTM              string `json:"DilutedEPSTTM"`
	QuarterlyEarningsGrowthYOY string `json:"QuarterlyEarningsGrowthYOY"`
	QuarterlyRevenueGrowthYOY  string `json:"QuarterlyRevenueGrowthYOY"`
	AnalystTargetPrice         string `json:"AnalystTargetPrice"`
	TrailingPE                 string `json:"TrailingPE"`
	ForwardPE                  string `json:"ForwardPE"`
	PriceToSalesRatioTTM       string `json:"PriceToSalesRatioTTM"`
	PriceToBookRatio           string `json:"PriceToBookRatio"`
	EVToRevenue                string `json:"EVToRevenue"`
	EVToEBITDA                 string `json:"EVToEBITDA"`
	Beta                       string `json:"Beta"`
	WeekHigh52                 string `json:"52WeekHigh"`
	WeekLow52                  string `json:"52WeekLow"`
	DayMovingAverage50         string `json:"50DayMovingAverage"`
	DayMovingAverage200        string `json:"200DayMovingAverage"`
	SharesOutstanding          string `json:"SharesOutstanding"`
	DividendDate               string `json:"DividendDate"`
	ExDividendDate             string `json:"ExDividendDate"`
}

// AlphaVantageIncomeStatementResponse represents income statement from Alpha Vantage
type AlphaVantageIncomeStatementResponse struct {
	Symbol           string                     `json:"symbol"`
	AnnualReports    []AlphaVantageIncomeReport `json:"annualReports"`
	QuarterlyReports []AlphaVantageIncomeReport `json:"quarterlyReports"`
}

type AlphaVantageIncomeReport struct {
	FiscalDateEnding                  string `json:"fiscalDateEnding"`
	ReportedCurrency                  string `json:"reportedCurrency"`
	GrossProfit                       string `json:"grossProfit"`
	TotalRevenue                      string `json:"totalRevenue"`
	CostOfRevenue                     string `json:"costOfRevenue"`
	CostofGoodsAndServicesSold        string `json:"costofGoodsAndServicesSold"`
	OperatingIncome                   string `json:"operatingIncome"`
	SellingGeneralAndAdministrative   string `json:"sellingGeneralAndAdministrative"`
	ResearchAndDevelopment            string `json:"researchAndDevelopment"`
	OperatingExpenses                 string `json:"operatingExpenses"`
	InvestmentIncomeNet               string `json:"investmentIncomeNet"`
	NetInterestIncome                 string `json:"netInterestIncome"`
	InterestIncome                    string `json:"interestIncome"`
	InterestExpense                   string `json:"interestExpense"`
	NonInterestIncome                 string `json:"nonInterestIncome"`
	NonInterestExpense                string `json:"nonInterestExpense"`
	IncomeBeforeTax                   string `json:"incomeBeforeTax"`
	IncomeTaxExpense                  string `json:"incomeTaxExpense"`
	InterestAndDebtExpense            string `json:"interestAndDebtExpense"`
	NetIncomeFromContinuingOperations string `json:"netIncomeFromContinuingOperations"`
	ComprehensiveIncomeNetOfTax       string `json:"comprehensiveIncomeNetOfTax"`
	EBIT                              string `json:"ebit"`
	EBITDA                            string `json:"ebitda"`
	NetIncome                         string `json:"netIncome"`
}

// AlphaVantageBalanceSheetResponse represents balance sheet from Alpha Vantage
type AlphaVantageBalanceSheetResponse struct {
	Symbol           string                      `json:"symbol"`
	AnnualReports    []AlphaVantageBalanceReport `json:"annualReports"`
	QuarterlyReports []AlphaVantageBalanceReport `json:"quarterlyReports"`
}

type AlphaVantageBalanceReport struct {
	FiscalDateEnding                       string `json:"fiscalDateEnding"`
	ReportedCurrency                       string `json:"reportedCurrency"`
	TotalAssets                            string `json:"totalAssets"`
	TotalCurrentAssets                     string `json:"totalCurrentAssets"`
	CashAndCashEquivalentsAtCarryingValue  string `json:"cashAndCashEquivalentsAtCarryingValue"`
	CashAndShortTermInvestments            string `json:"cashAndShortTermInvestments"`
	Inventory                              string `json:"inventory"`
	CurrentNetReceivables                  string `json:"currentNetReceivables"`
	TotalNonCurrentAssets                  string `json:"totalNonCurrentAssets"`
	PropertyPlantEquipment                 string `json:"propertyPlantEquipment"`
	AccumulatedDepreciationAmortizationPPE string `json:"accumulatedDepreciationAmortizationPPE"`
	IntangibleAssets                       string `json:"intangibleAssets"`
	IntangibleAssetsExcludingGoodwill      string `json:"intangibleAssetsExcludingGoodwill"`
	Goodwill                               string `json:"goodwill"`
	Investments                            string `json:"investments"`
	LongTermInvestments                    string `json:"longTermInvestments"`
	ShortTermInvestments                   string `json:"shortTermInvestments"`
	OtherCurrentAssets                     string `json:"otherCurrentAssets"`
	OtherNonCurrentAssets                  string `json:"otherNonCurrentAssets"`
	TotalLiabilities                       string `json:"totalLiabilities"`
	TotalCurrentLiabilities                string `json:"totalCurrentLiabilities"`
	CurrentAccountsPayable                 string `json:"currentAccountsPayable"`
	DeferredRevenue                        string `json:"deferredRevenue"`
	CurrentDebt                            string `json:"currentDebt"`
	ShortTermDebt                          string `json:"shortTermDebt"`
	TotalNonCurrentLiabilities             string `json:"totalNonCurrentLiabilities"`
	CapitalLeaseObligations                string `json:"capitalLeaseObligations"`
	LongTermDebt                           string `json:"longTermDebt"`
	CurrentLongTermDebt                    string `json:"currentLongTermDebt"`
	LongTermDebtNoncurrent                 string `json:"longTermDebtNoncurrent"`
	ShortLongTermDebtTotal                 string `json:"shortLongTermDebtTotal"`
	OtherCurrentLiabilities                string `json:"otherCurrentLiabilities"`
	OtherNonCurrentLiabilities             string `json:"otherNonCurrentLiabilities"`
	TotalShareholderEquity                 string `json:"totalShareholderEquity"`
	TreasuryStock                          string `json:"treasuryStock"`
	RetainedEarnings                       string `json:"retainedEarnings"`
	CommonStock                            string `json:"commonStock"`
	CommonStockSharesOutstanding           string `json:"commonStockSharesOutstanding"`
}

// FetchStockUniverse fetches stocks for a given region
// Note: Alpha Vantage doesn't have a stock list endpoint, so we'll use a predefined list
func (p *AlphaVantageProvider) FetchStockUniverse(regionCode string) ([]StockFromAPI, error) {
	// Use predefined popular stocks (same as FMP provider)
	popularStocks := p.getPopularStocksByRegion(regionCode)

	if len(popularStocks) == 0 {
		return []StockFromAPI{}, nil
	}

	var stocks []StockFromAPI
	regionMap := p.mapRegionCode(regionCode)

	// Fetch overview for each stock
	for _, tickerExchange := range popularStocks {
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

		overview, err := p.fetchOverview(ticker)
		if err != nil {
			// If overview fetch fails, create basic stock entry
			stockRegion := p.getRegionFromExchange(exchange)
			if regionCode == "GLOBAL" || stockRegion == regionCode || p.contains(regionMap, exchange) {
				stocks = append(stocks, StockFromAPI{
					Ticker:     ticker,
					Exchange:   exchange,
					Name:       ticker,
					RegionCode: stockRegion,
				})
			}
			continue
		}

		stockRegion := p.getRegionFromExchange(overview.Exchange)

		// Filter by region if specified
		if regionCode != "GLOBAL" && stockRegion != regionCode && !p.contains(regionMap, overview.Exchange) {
			continue
		}

		var marketCap int64
		if overview.MarketCapitalization != "" && overview.MarketCapitalization != "None" {
			// Market cap is in string format like "1000000000" (in base currency)
			if mc, err := parseNumericString(overview.MarketCapitalization); err == nil {
				marketCap = int64(mc)
			}
		}

		stocks = append(stocks, StockFromAPI{
			Ticker:      overview.Symbol,
			Exchange:    overview.Exchange,
			Name:        overview.Name,
			Country:     overview.Country,
			RegionCode:  stockRegion,
			Sector:      overview.Sector,
			Industry:    overview.Industry,
			Description: overview.Description,
			MarketCap:   marketCap,
		})
	}

	return stocks, nil
}

// FetchFundamentalsBatch fetches financial data for multiple tickers
func (p *AlphaVantageProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
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

		// Get the most recent annual report
		var latestIncome AlphaVantageIncomeReport
		var latestBalance AlphaVantageBalanceReport
		var asOfDate string

		if len(incomeStmt.AnnualReports) > 0 {
			latestIncome = incomeStmt.AnnualReports[0]
			asOfDate = latestIncome.FiscalDateEnding
		}

		if len(balanceSheet.AnnualReports) > 0 {
			latestBalance = balanceSheet.AnnualReports[0]
			if asOfDate == "" {
				asOfDate = latestBalance.FiscalDateEnding
			}
		}

		// Parse numeric values
		totalAssets, _ := parseNumericString(latestBalance.TotalAssets)
		totalDebt, _ := parseNumericString(latestBalance.LongTermDebt)
		// Add short-term debt if available
		if shortTermDebt, err := parseNumericString(latestBalance.ShortTermDebt); err == nil {
			totalDebt += shortTermDebt
		}
		cashAndEquiv, _ := parseNumericString(latestBalance.CashAndCashEquivalentsAtCarryingValue)
		totalRevenue, _ := parseNumericString(latestIncome.TotalRevenue)
		interestIncome, _ := parseNumericString(latestIncome.InterestIncome)
		interestExpense, _ := parseNumericString(latestIncome.InterestExpense)
		netIncome, _ := parseNumericString(latestIncome.NetIncome)

		// Get dividend per share, company name, sector, industry, market cap from overview
		var dividendsPerShare float64
		companyName := ""
		sector := ""
		industry := ""
		var marketCap int64
		overview, err := p.fetchOverview(ticker)
		if err == nil && overview != nil {
			if overview.DividendPerShare != "" && overview.DividendPerShare != "None" {
				dividendsPerShare, _ = parseNumericString(overview.DividendPerShare)
			}
			companyName = overview.Name
			sector = overview.Sector
			industry = overview.Industry
			if overview.MarketCapitalization != "" && overview.MarketCapitalization != "None" {
				if mc, err := parseNumericString(overview.MarketCapitalization); err == nil {
					marketCap = int64(mc)
				}
			}
		}

		// Create JSON representation
		rawJSON, _ := json.Marshal(map[string]interface{}{
			"income_statement": latestIncome,
			"balance_sheet":    latestBalance,
		})

		fundamental := FundamentalsFromAPI{
			Ticker:            ticker,
			CompanyName:       companyName,
			Sector:            sector,
			Industry:          industry,
			MarketCap:         marketCap,
			TotalAssets:       totalAssets,
			TotalDebt:         totalDebt,
			CashAndEquiv:      cashAndEquiv,
			TotalRevenue:      totalRevenue,
			InterestIncome:    interestIncome,
			InterestExpense:   interestExpense,
			NetIncome:         netIncome,
			DividendsPerShare: dividendsPerShare,
			AsOfDate:          asOfDate,
			RawJSON:           string(rawJSON),
		}

		results = append(results, fundamental)
		log.Printf("Successfully fetched fundamentals for %s", ticker)
	}

	return results, nil
}

// SearchStocks searches for stocks by name or ticker
// Note: Alpha Vantage doesn't have a search endpoint, so we'll use SYMBOL_SEARCH
func (p *AlphaVantageProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return nil, fmt.Errorf("rate limit error: %w", err)
	}

	endpoint := p.baseURL
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	q := req.URL.Query()
	q.Set("function", "SYMBOL_SEARCH")
	q.Set("keywords", query)
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

	var searchResponse struct {
		BestMatches []struct {
			Symbol      string `json:"1. symbol"`
			Name        string `json:"2. name"`
			Type        string `json:"3. type"`
			Region      string `json:"4. region"`
			MarketOpen  string `json:"5. marketOpen"`
			MarketClose string `json:"6. marketClose"`
			Timezone    string `json:"7. timezone"`
			Currency    string `json:"8. currency"`
			MatchScore  string `json:"9. matchScore"`
		} `json:"bestMatches"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&searchResponse); err != nil {
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	var stocks []StockFromAPI
	for _, match := range searchResponse.BestMatches {
		// Extract exchange from symbol or use region
		exchange := "NYSE" // Default
		if strings.Contains(match.Symbol, ".") {
			parts := strings.Split(match.Symbol, ".")
			if len(parts) > 1 {
				exchange = parts[1]
			}
		}

		stocks = append(stocks, StockFromAPI{
			Ticker:     match.Symbol,
			Exchange:   exchange,
			Name:       match.Name,
			Country:    match.Region,
			RegionCode: p.getRegionFromExchange(exchange),
		})
	}

	return stocks, nil
}

// StartBackgroundRefresh starts a background goroutine to refresh indexes
func (p *AlphaVantageProvider) StartBackgroundRefresh() {
	go func() {
		// Initial fetch
		log.Println("Starting initial market indexes fetch...")
		p.refreshCachedIndexes()

		ticker := time.NewTicker(10 * time.Minute) // Every 10 minutes
		defer ticker.Stop()

		for range ticker.C {
			log.Println("Refreshing market indexes...")
			p.refreshCachedIndexes()
		}
	}()
}

func (p *AlphaVantageProvider) refreshCachedIndexes() {
	indices, err := p.fetchIndicesNow()
	if err != nil {
		log.Printf("Error refreshing indexes: %v", err)
	}

	sentiment, err := p.fetchSentimentNow()
	if err != nil {
		log.Printf("Error refreshing sentiment: %v", err)
	}

	p.mu.Lock()
	if len(indices) > 0 {
		p.cachedIndices = indices
	}
	if sentiment.Label != "" {
		p.cachedSentiment = sentiment
	}
	p.mu.Unlock()
	log.Printf("Successfully refreshed %d indexes and sentiment", len(indices))

	// Persistence to DB
	if p.store != nil {
		for _, idx := range indices {
			if err := p.store.UpsertIndex(idx); err != nil {
				log.Printf("Error persisting index %s: %v", idx.Symbol, err)
			}
		}
		if sentiment.Label != "" {
			if err := p.store.SaveSentiment(sentiment); err != nil {
				log.Printf("Error persisting sentiment: %v", err)
			}
		}
	}
}

func (p *AlphaVantageProvider) fetchIndicesNow() ([]IndexData, error) {
	indices := []struct {
		Symbol   string
		Name     string
		Category string
	}{
		{"SPY", "S&P 500", "Benchmarks"},
		{"QQQ", "Nasdaq 100", "Benchmarks"},
		{"DIA", "Dow Jones", "Benchmarks"},
		{"VXX", "VIX Fear Gauge", "Health"},
		{"IWM", "Russell 2000", "Health"},
		{"URTH", "MSCI World", "Global"},
		{"FEZ", "Euro Stoxx 50", "Global"},
		{"EWU", "FTSE 100", "Global"},
		{"EWJ", "Nikkei 225", "Global"},
		{"EWH", "Hang Seng", "Global"},
		{"UUP", "US Dollar Index", "Macro"},
	}

	var results []IndexData

	for _, idx := range indices {
		// Fetch quote for current price/change
		quote, err := p.fetchQuote(idx.Symbol)
		if err != nil {
			log.Printf("Error fetching quote for %s: %v", idx.Symbol, err)
			continue
		}

		// Fetch daily time series for sparkline
		sparkline, sparklineDates := p.fetchSparkline(idx.Symbol)

		price, _ := parseNumericString(quote.Quote.Price)
		change, _ := parseNumericString(quote.Quote.Change)
		changePctStr := strings.TrimSuffix(quote.Quote.ChangePercent, "%")
		changePercent, _ := parseNumericString(changePctStr)

		results = append(results, IndexData{
			Symbol:         idx.Symbol,
			Name:           idx.Name,
			Price:          price,
			Change:         change,
			ChangePercent:  changePercent,
			Category:       idx.Category,
			Sparkline:      sparkline,
			SparklineDates: sparklineDates,
		})
	}

	// Fetch 10Y Treasury Yield separately
	yield, spark10y, dates10y, err := p.fetchTreasuryYieldWithSparkline()
	if err == nil {
		results = append(results, IndexData{
			Symbol:         "TNX",
			Name:           "US 10Y Yield",
			Price:          yield,
			Category:       "Macro",
			Sparkline:      spark10y,
			SparklineDates: dates10y,
		})
	}

	// Fetch Crude Oil (WTI)
	oil, sparkOil, datesOil, err := p.fetchCrudeOilWithSparkline()
	if err == nil {
		results = append(results, IndexData{
			Symbol:         "CL",
			Name:           "Crude Oil",
			Price:          oil,
			Category:       "Macro",
			Sparkline:      sparkOil,
			SparklineDates: datesOil,
		})
	}

	return results, nil
}

func (p *AlphaVantageProvider) fetchSparkline(symbol string) ([]float64, []string) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return []float64{}, []string{}
	}

	endpoint := p.baseURL
	req, _ := http.NewRequest("GET", endpoint, nil)
	q := req.URL.Query()
	q.Set("function", "TIME_SERIES_DAILY")
	q.Set("symbol", symbol)
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return []float64{}, []string{}
	}
	defer resp.Body.Close()

	var timeSeries struct {
		Data map[string]struct {
			Close string `json:"4. close"`
		} `json:"Time Series (Daily)"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&timeSeries); err != nil {
		return []float64{}, []string{}
	}

	// Sort dates and get last 100
	var dates []string
	for date := range timeSeries.Data {
		dates = append(dates, date)
	}
	sort.Strings(dates)

	limit := 100
	if len(dates) > limit {
		dates = dates[len(dates)-limit:]
	}

	var sparkline []float64
	var sparklineDates []string
	for _, date := range dates {
		val, _ := parseNumericString(timeSeries.Data[date].Close)
		sparkline = append(sparkline, val)
		sparklineDates = append(sparklineDates, date)
	}

	return sparkline, sparklineDates
}

func (p *AlphaVantageProvider) fetchTreasuryYieldWithSparkline() (float64, []float64, []string, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return 0, nil, nil, err
	}

	endpoint := p.baseURL
	req, _ := http.NewRequest("GET", endpoint, nil)
	q := req.URL.Query()
	q.Set("function", "TREASURY_YIELD")
	q.Set("interval", "daily")
	q.Set("maturity", "10year")
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return 0, nil, nil, err
	}
	defer resp.Body.Close()

	var yieldResp struct {
		Data []struct {
			Date  string `json:"date"`
			Value string `json:"value"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&yieldResp); err != nil {
		return 0, nil, nil, err
	}

	if len(yieldResp.Data) == 0 {
		return 0, nil, nil, fmt.Errorf("no yield data found")
	}

	latest, _ := parseNumericString(yieldResp.Data[0].Value)

	var sparkline []float64
	var sparklineDates []string
	limit := 100
	if len(yieldResp.Data) < limit {
		limit = len(yieldResp.Data)
	}
	// Data is usually latest first, so reverse for chart
	for i := limit - 1; i >= 0; i-- {
		val, _ := parseNumericString(yieldResp.Data[i].Value)
		sparkline = append(sparkline, val)
		sparklineDates = append(sparklineDates, yieldResp.Data[i].Date)
	}

	return latest, sparkline, sparklineDates, nil
}

func (p *AlphaVantageProvider) fetchCrudeOilWithSparkline() (float64, []float64, []string, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return 0, nil, nil, err
	}

	endpoint := p.baseURL
	req, _ := http.NewRequest("GET", endpoint, nil)
	q := req.URL.Query()
	q.Set("function", "WTI")
	q.Set("interval", "daily")
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return 0, nil, nil, err
	}
	defer resp.Body.Close()

	var oilResp struct {
		Data []struct {
			Date  string `json:"date"`
			Value string `json:"value"`
		} `json:"data"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&oilResp); err != nil {
		return 0, nil, nil, err
	}

	if len(oilResp.Data) == 0 {
		return 0, nil, nil, fmt.Errorf("no oil data found")
	}

	latest, _ := parseNumericString(oilResp.Data[0].Value)

	var sparkline []float64
	var sparklineDates []string
	limit := 100
	if len(oilResp.Data) < limit {
		limit = len(oilResp.Data)
	}
	for i := limit - 1; i >= 0; i-- {
		val, _ := parseNumericString(oilResp.Data[i].Value)
		sparkline = append(sparkline, val)
		sparklineDates = append(sparklineDates, oilResp.Data[i].Date)
	}

	return latest, sparkline, sparklineDates, nil
}

// FetchIndexes implements MarketDataProvider, returns cached data
func (p *AlphaVantageProvider) FetchIndexes() ([]IndexData, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()

	// If cache is empty, return empty list rather than blocking
	// The background refresh handles population
	if len(p.cachedIndices) == 0 {
		return []IndexData{}, nil
	}

	return p.cachedIndices, nil
}

// FetchFearAndGreed implements MarketDataProvider, returns cached sentiment data
func (p *AlphaVantageProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	p.mu.RLock()
	defer p.mu.RUnlock()

	// If cache is empty, return a default/neutral value
	if p.cachedSentiment.Label == "" {
		return FearAndGreedData{
			Value:       50,
			Label:       "Neutral",
			Color:       "#FFCC00",
			LastUpdated: time.Now().Format("2006-01-02 15:04:05"),
		}, nil
	}

	return p.cachedSentiment, nil
}

func (p *AlphaVantageProvider) mapSentiment(score float64) (int, string, string) {
	// Map -1.0..1.0 to 0..100
	value := int((score + 1.0) * 50.0)
	if value < 0 {
		value = 0
	}
	if value > 100 {
		value = 100
	}

	var label string
	var color string

	if value < 25 {
		label = "Extreme Fear"
		color = "#FF3B30"
	} else if value < 45 {
		label = "Fear"
		color = "#FF9500"
	} else if value < 55 {
		label = "Neutral"
		color = "#FFCC00"
	} else if value < 75 {
		label = "Greed"
		color = "#34C759"
	} else {
		label = "Extreme Greed"
		color = "#30B0C7"
	}

	return value, label, color
}

func (p *AlphaVantageProvider) fetchSentimentNow() (FearAndGreedData, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return FearAndGreedData{}, err
	}

	endpoint := p.baseURL
	req, _ := http.NewRequest("GET", endpoint, nil)
	q := req.URL.Query()
	q.Set("function", "NEWS_SENTIMENT")
	q.Set("apikey", p.apiKey)
	q.Set("limit", "10") // Just get latest 10 articles for efficiency
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return FearAndGreedData{}, err
	}
	defer resp.Body.Close()

	var sentimentResp struct {
		SentimentScore string `json:"overall_sentiment_score"` // This might be in top level or aggregate
		Feed           []struct {
			SentimentScore float64 `json:"overall_sentiment_score"`
		} `json:"feed"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&sentimentResp); err != nil {
		return FearAndGreedData{}, err
	}

	if len(sentimentResp.Feed) == 0 {
		return FearAndGreedData{}, fmt.Errorf("no sentiment data found")
	}

	// Calculate average sentiment from latest feed
	var total float64
	for _, f := range sentimentResp.Feed {
		total += f.SentimentScore
	}
	avgScore := total / float64(len(sentimentResp.Feed))

	value, label, color := p.mapSentiment(avgScore)

	return FearAndGreedData{
		Value:       value,
		Label:       label,
		Color:       color,
		LastUpdated: time.Now().Format("2006-01-02 15:04:05"),
	}, nil
}

func (p *AlphaVantageProvider) fetchOverview(ticker string) (*AlphaVantageOverviewResponse, error) {
	endpoint := p.baseURL
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("function", "OVERVIEW")
	q.Set("symbol", ticker)
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

	var overview AlphaVantageOverviewResponse
	if err := json.NewDecoder(resp.Body).Decode(&overview); err != nil {
		return nil, err
	}

	// Check for API error messages
	if overview.Symbol == "" {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("no data returned: %s", string(body))
	}

	return &overview, nil
}

func (p *AlphaVantageProvider) fetchIncomeStatement(ticker string) (*AlphaVantageIncomeStatementResponse, error) {
	endpoint := p.baseURL
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("function", "INCOME_STATEMENT")
	q.Set("symbol", ticker)
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		log.Printf("Alpha Vantage income statement API error for %s: status %d, body: %s", ticker, resp.StatusCode, string(bodyBytes))
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var incomeStmt AlphaVantageIncomeStatementResponse
	if err := json.Unmarshal(bodyBytes, &incomeStmt); err != nil {
		log.Printf("Alpha Vantage income statement parse error for %s: %v, body: %s", ticker, err, string(bodyBytes))
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	// Check for API error messages in response
	if strings.Contains(string(bodyBytes), "Error Message") || strings.Contains(string(bodyBytes), "Note") || strings.Contains(string(bodyBytes), "Information") {
		log.Printf("Alpha Vantage API error/info message for %s: %s", ticker, string(bodyBytes))
		return nil, fmt.Errorf("API error: %s", string(bodyBytes))
	}

	// Check for API error messages
	if incomeStmt.Symbol == "" {
		log.Printf("No income statement data for %s, response: %s", ticker, string(bodyBytes))
		return nil, fmt.Errorf("no income statement data returned")
	}

	return &incomeStmt, nil
}

func (p *AlphaVantageProvider) fetchBalanceSheet(ticker string) (*AlphaVantageBalanceSheetResponse, error) {
	endpoint := p.baseURL
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("function", "BALANCE_SHEET")
	q.Set("symbol", ticker)
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	bodyBytes, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK {
		log.Printf("Alpha Vantage balance sheet API error for %s: status %d, body: %s", ticker, resp.StatusCode, string(bodyBytes))
		return nil, fmt.Errorf("API returned status %d: %s", resp.StatusCode, string(bodyBytes))
	}

	var balanceSheet AlphaVantageBalanceSheetResponse
	if err := json.Unmarshal(bodyBytes, &balanceSheet); err != nil {
		log.Printf("Alpha Vantage balance sheet parse error for %s: %v, body: %s", ticker, err, string(bodyBytes))
		return nil, fmt.Errorf("failed to parse response: %w", err)
	}

	// Check for API error messages in response
	if strings.Contains(string(bodyBytes), "Error Message") || strings.Contains(string(bodyBytes), "Note") || strings.Contains(string(bodyBytes), "Information") {
		log.Printf("Alpha Vantage API error/info message for %s: %s", ticker, string(bodyBytes))
		return nil, fmt.Errorf("API error: %s", string(bodyBytes))
	}

	// Check for API error messages
	if balanceSheet.Symbol == "" {
		log.Printf("No balance sheet data for %s, response: %s", ticker, string(bodyBytes))
		return nil, fmt.Errorf("no balance sheet data returned")
	}

	return &balanceSheet, nil
}

// getPopularStocksByRegion returns a list of popular stock tickers:exchange by region
func (p *AlphaVantageProvider) getPopularStocksByRegion(regionCode string) []string {
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

// Helper functions (shared with FMP provider logic)

func (p *AlphaVantageProvider) getRegionFromExchange(exchange string) string {
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

func (p *AlphaVantageProvider) mapRegionCode(regionCode string) []string {
	regionMap := map[string][]string{
		"US":     {"NASDAQ", "NYSE", "AMEX", "OTC"},
		"GCC":    {"TADAWUL", "DFM", "ADX", "BHB", "KSE", "MSM"},
		"MENA":   {"TADAWUL", "DFM", "ADX", "BHB", "KSE", "MSM", "EGX"},
		"EU":     {"LSE", "FRA", "XETR", "AMS", "MIL", "PAR", "SWX"},
		"ASIA":   {"NSE", "BSE", "SGX", "KLSE", "IDX"},
		"CN":     {"SSE", "SZSE", "HKEX"},
		"GLOBAL": {},
	}

	if exchanges, ok := regionMap[regionCode]; ok {
		return exchanges
	}
	return []string{}
}

func (p *AlphaVantageProvider) contains(slice []string, item string) bool {
	for _, s := range slice {
		if s == item {
			return true
		}
	}
	return false
}

func (p *AlphaVantageProvider) fetchQuote(symbol string) (*AlphaVantageQuoteResponse, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return nil, err
	}

	endpoint := p.baseURL
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return nil, err
	}

	q := req.URL.Query()
	q.Set("function", "GLOBAL_QUOTE")
	q.Set("symbol", symbol)
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var quote AlphaVantageQuoteResponse
	if err := json.NewDecoder(resp.Body).Decode(&quote); err != nil {
		return nil, err
	}

	if quote.Quote.Symbol == "" {
		return nil, fmt.Errorf("no quote data found for %s", symbol)
	}

	return &quote, nil
}

// FetchExchangeRate fetches currency exchange rate from Alpha Vantage
func (p *AlphaVantageProvider) FetchExchangeRate(from, to string) (float64, error) {
	ctx := context.Background()
	if err := p.limiter.Wait(ctx); err != nil {
		return 0, fmt.Errorf("rate limit error: %w", err)
	}

	endpoint := p.baseURL
	req, err := http.NewRequest("GET", endpoint, nil)
	if err != nil {
		return 0, err
	}

	q := req.URL.Query()
	q.Set("function", "CURRENCY_EXCHANGE_RATE")
	q.Set("from_currency", from)
	q.Set("to_currency", to)
	q.Set("apikey", p.apiKey)
	req.URL.RawQuery = q.Encode()

	resp, err := p.client.Do(req)
	if err != nil {
		return 0, err
	}
	defer resp.Body.Close()

	var exchangeResponse struct {
		RealtimeRate struct {
			ExchangeRate string `json:"5. Exchange Rate"`
		} `json:"Realtime Currency Exchange Rate"`
	}

	if err := json.NewDecoder(resp.Body).Decode(&exchangeResponse); err != nil {
		return 0, err
	}

	if exchangeResponse.RealtimeRate.ExchangeRate == "" {
		// Fallback for mock/local development if API fails or key is missing
		if from == to {
			return 1.0, nil
		}
		return 0, fmt.Errorf("no exchange rate data found from %s to %s", from, to)
	}

	return parseNumericString(exchangeResponse.RealtimeRate.ExchangeRate)
}

// parseNumericString parses a numeric string that may contain commas or be "None"
func parseNumericString(s string) (float64, error) {
	if s == "" || s == "None" || s == "null" {
		return 0, fmt.Errorf("empty or None value")
	}

	// Remove commas
	s = strings.ReplaceAll(s, ",", "")

	var result float64
	_, err := fmt.Sscanf(s, "%f", &result)
	return result, err
}

package marketdata

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"time"
)

type EODHDProvider struct {
	APIKey string
	Client *http.Client
}

func NewEODHDProvider(apiKey string) *EODHDProvider {
	return &EODHDProvider{
		APIKey: apiKey,
		Client: &http.Client{Timeout: 30 * time.Second},
	}
}

type EODHDFundamentalResponse struct {
	General struct {
		Code        string `json:"Code"`
		Type        string `json:"Type"`
		Name        string `json:"Name"`
		Exchange    string `json:"Exchange"`
		Currency    string `json:"CurrencyCode"`
		Country     string `json:"CountryName"`
		Sector      string `json:"Sector"`
		Industry    string `json:"Industry"`
		Description string `json:"Description"`
	} `json:"General"`
	Highlights struct {
		MarketCap  float64 `json:"MarketCapitalization"` // Note: EODHD sometimes uses string? Checking docs. Usually float/int for capitalization.
		RevenueTTM float64 `json:"RevenueTTM"`
	} `json:"Highlights"`
	Financials struct {
		Balance_Sheet struct {
			Quarterly map[string]struct {
				TotalAssets            string `json:"totalAssets"` // EODHD returns numbers as strings often
				TotalLiab              string `json:"totalLiab"`
				TotalDebt              string `json:"longTermDebt"` // Approximation for total debt if total isn't explicit? EODHD has shortLongTermDebtTotal + longTermDebt
				ShortLongTermDebtTotal string `json:"shortLongTermDebtTotal"`
				CashAndEquivalents     string `json:"cashAndEquivalents"`
			} `json:"quarterly"`
		} `json:"Balance_Sheet"`
		Income_Statement struct {
			Quarterly map[string]struct {
				TotalRevenue   string `json:"totalRevenue"`
				InterestIncome string `json:"interestIncome"` // Key logic
				NetIncome      string `json:"netIncome"`
			} `json:"quarterly"`
		} `json:"Income_Statement"`
	} `json:"Financials"`
}

// Ensure interface compliance
var _ MarketDataProvider = &EODHDProvider{}

// SearchStocks implements MarketDataProvider
func (p *EODHDProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	// Mock implementation for now, as EODHD Search API is different endpoint
	// and we are focused on fundamentals ingestion.
	return []StockFromAPI{}, nil
}

// FetchStockUniverse returns specific list for MVP test (limited API calls)
func (p *EODHDProvider) FetchStockUniverse(region string) ([]StockFromAPI, error) {
	// User requested LIMITED calls. Hardcode a few test tickers.
	// In production, this would scan the exchange.
	tickers := []StockFromAPI{
		{Ticker: "AAPL", Exchange: "US", Name: "Apple Inc.", Country: "USA", RegionCode: "US"},
		{Ticker: "MSFT", Exchange: "US", Name: "Microsoft Corp.", Country: "USA", RegionCode: "US"},
		{Ticker: "TSLA", Exchange: "US", Name: "Tesla Inc.", Country: "USA", RegionCode: "US"},
	}
	return tickers, nil
}

func (p *EODHDProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
	var results []FundamentalsFromAPI

	for _, ticker := range tickers {
		// EODHD Format: TICKER.EXCHANGE
		// Default to US for now
		symbol := fmt.Sprintf("%s.US", ticker)
		url := fmt.Sprintf("https://eodhd.com/api/fundamentals/%s?api_token=%s", symbol, p.APIKey)

		resp, err := p.Client.Get(url)
		if err != nil {
			fmt.Printf("Error fetching %s: %v\n", ticker, err)
			continue
		}
		defer resp.Body.Close()

		if resp.StatusCode != http.StatusOK {
			fmt.Printf("Error fetching %s: Status %d\n", ticker, resp.StatusCode)
			body, _ := io.ReadAll(resp.Body)
			fmt.Printf("Body: %s\n", string(body))
			continue
		}

		body, _ := io.ReadAll(resp.Body)

		var data EODHDFundamentalResponse
		if err := json.Unmarshal(body, &data); err != nil {
			fmt.Printf("JSON Error for %s: %v\n", ticker, err)
			continue
		}

		// Find latest quarter
		latestDate := ""
		for date := range data.Financials.Balance_Sheet.Quarterly {
			if date > latestDate {
				latestDate = date
			}
		}

		if latestDate == "" {
			fmt.Printf("No quarterly data found for %s\n", ticker)
			continue
		}

		bs := data.Financials.Balance_Sheet.Quarterly[latestDate]
		is := data.Financials.Income_Statement.Quarterly[latestDate]

		totalAssets := parseStringFloat(bs.TotalAssets)
		totalDebt := parseStringFloat(bs.ShortLongTermDebtTotal)
		if totalDebt == 0 {
			totalDebt = parseStringFloat(bs.TotalDebt)
		}

		totalRevenue := parseStringFloat(is.TotalRevenue)
		interestIncome := parseStringFloat(is.InterestIncome)
		netIncome := parseStringFloat(is.NetIncome)
		cashAndEquiv := parseStringFloat(bs.CashAndEquivalents)

		results = append(results, FundamentalsFromAPI{
			Ticker:      data.General.Code,
			CompanyName: data.General.Name,
			// Sector/Industry/Desc are in Stock object, but Fundamentals object in provider.go doesn't have them.
			// The IngestionService handles merging.
			TotalAssets:    totalAssets,
			TotalDebt:      totalDebt,
			CashAndEquiv:   cashAndEquiv,
			TotalRevenue:   totalRevenue,
			InterestIncome: interestIncome,
			NetIncome:      netIncome,
			AsOfDate:       latestDate,
			RawJSON:        "",
		})

		// Rate limit kindness
		time.Sleep(1 * time.Second)
	}

	return results, nil
}

// FetchIndexes implements MarketDataProvider
func (p *EODHDProvider) FetchIndexes() ([]IndexData, error) {
	return []IndexData{}, nil
}

func parseStringFloat(s string) float64 {
	var f float64
	fmt.Sscanf(s, "%f", &f)
	return f
}
func (p *EODHDProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	return FearAndGreedData{}, nil
}

// FetchExchangeRate implements MarketDataProvider
func (p *EODHDProvider) FetchExchangeRate(from, to string) (float64, error) {
	if from == to {
		return 1.0, nil
	}
	return 0, fmt.Errorf("FetchExchangeRate not implemented for EODHDProvider")
}

package marketdata

// StockFromAPI represents stock data from external API
type StockFromAPI struct {
	Ticker      string
	Exchange    string
	Name        string
	Country     string
	RegionCode  string
	Sector      string
	Industry    string
	Description string
	MarketCap   int64
}

// FundamentalsFromAPI represents financial data from external API
type FundamentalsFromAPI struct {
	Ticker            string
	CompanyName       string // Company name from API (if available)
	Sector            string
	Industry          string
	MarketCap         int64
	TotalAssets       float64
	TotalDebt         float64
	CashAndEquiv      float64
	TotalRevenue      float64
	InterestIncome    float64
	InterestExpense   float64
	NetIncome         float64
	DividendsPerShare float64
	AsOfDate          string
	RawJSON           string
}

// IndexData represents market index data
type IndexData struct {
	Symbol         string    `json:"symbol"`
	Name           string    `json:"name"`
	Price          float64   `json:"price"`
	Change         float64   `json:"change"`
	ChangePercent  float64   `json:"change_percent"`
	Category       string    `json:"category"`
	Sparkline      []float64 `json:"sparkline"`
	SparklineDates []string  `json:"sparkline_dates"`
}

// FearAndGreedData represents market sentiment data
type FearAndGreedData struct {
	Value        int      `json:"value"`
	Label        string   `json:"label"`
	Color        string   `json:"color"`
	LastUpdated  string   `json:"last_updated"`
	PreviousDate string   `json:"previous_date"`
	Trend        []int    `json:"trend"`
	TrendDates   []string `json:"trend_dates"`
}

// MarketDataProvider interface for fetching stock data
type MarketDataProvider interface {
	// FetchStockUniverse fetches all stocks for a given region
	FetchStockUniverse(regionCode string) ([]StockFromAPI, error)

	// FetchFundamentalsBatch fetches financial data for multiple tickers
	FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error)

	// SearchStocks searches for stocks by name or ticker
	SearchStocks(query string) ([]StockFromAPI, error)

	// FetchIndexes fetches market indexes
	FetchIndexes() ([]IndexData, error)

	// FetchFearAndGreed fetches market sentiment data
	FetchFearAndGreed() (FearAndGreedData, error)

	// FetchExchangeRate fetches currency exchange rate
	FetchExchangeRate(from, to string) (float64, error)
}

// MarketStore interface for persisting market data
type MarketStore interface {
	UpsertIndex(idx IndexData) error
	GetAllIndexes() ([]IndexData, error)
	SaveSentiment(data FearAndGreedData) error
	GetLatestSentiment() (FearAndGreedData, error)
}

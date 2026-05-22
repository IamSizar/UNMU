package marketdata

import (
	"fmt"
	"math"
	"math/rand"
	"time"
)

// MockProvider is a deterministic in-memory MarketDataProvider — no
// external API calls, no quotas, no flakiness. Returns synthetic but
// realistic-looking quotes, fundamentals, indexes, and sentiment.
//
// Why we ship this:
//   * Free-tier external APIs (AlphaVantage / FMP / etc.) keep getting
//     rate-limited or deprecated mid-development, which makes local
//     iteration painful.
//   * The rest of the app exercises every code path identically whether
//     the provider is real or mock.
//   * Switching back is a single .env line: `STOCK_API_PROVIDER=alphavantage`.
//
// Pricing model: each ticker gets a base price (deterministic from the
// ticker's hash) and walks slightly each day. Same ticker queried on the
// same day always returns the same price — caches stay coherent. Day-to-
// day drift is small (±2-3%) so charts look natural.
type MockProvider struct{}

func NewMockProvider() *MockProvider {
	return &MockProvider{}
}

// ─── Helpers ────────────────────────────────────────────────────────

// Deterministic seed per ticker — so the same ticker always produces
// the same baseline numbers. Hash + day-of-year creates the daily walk.
//
// Uses uint64 internally because FNV constants overflow int64; cast to
// int64 at the boundary because rand.NewSource expects an int64 seed.
func tickerSeed(ticker string) int64 {
	var h uint64 = 14695981039346656037 // FNV offset basis
	for _, b := range []byte(ticker) {
		h ^= uint64(b)
		h *= 1099511628211 // FNV prime
	}
	return int64(h)
}

func basePrice(ticker string) float64 {
	r := rand.New(rand.NewSource(tickerSeed(ticker)))
	// $5 — $500 base price.
	return 5 + r.Float64()*495
}

// Deterministic daily walk — same input always produces the same output.
func dayWalk(ticker string, day int) float64 {
	r := rand.New(rand.NewSource(tickerSeed(ticker) + int64(day)*7919))
	// Small daily drift, mostly between -3% and +3%.
	return (r.Float64()*0.06 - 0.03)
}

// Today's price = base * cumulative drift over recent days.
func currentQuote(ticker string) (price, change, changePct float64) {
	now := time.Now()
	day := now.YearDay() + (now.Year()-2020)*365
	p := basePrice(ticker)
	for i := 0; i < day; i++ {
		p *= (1 + dayWalk(ticker, i))
	}
	// Round to cents.
	p = math.Round(p*100) / 100

	// Today's change is just today's walk × base of yesterday.
	prev := basePrice(ticker)
	for i := 0; i < day-1; i++ {
		prev *= (1 + dayWalk(ticker, i))
	}
	change = math.Round((p-prev)*100) / 100
	if prev > 0 {
		changePct = math.Round((change/prev)*10000) / 100
	}
	return p, change, changePct
}

// ─── Universe / company data ────────────────────────────────────────

// FetchStockUniverse — for the mock, we don't supplement what the DB
// already has. The DB seed (`0006_seed_demo_stocks.sql`) is the source
// of truth for the catalog. Returning an empty slice means "no new
// stocks to add" — the existing 25 seeded stocks remain available via
// the `stocks` table.
func (p *MockProvider) FetchStockUniverse(regionCode string) ([]StockFromAPI, error) {
	return []StockFromAPI{}, nil
}

// SearchStocks — same: defer to the DB-backed search in the public
// handler, which queries the `stocks` table directly. Return empty.
func (p *MockProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	return []StockFromAPI{}, nil
}

// FetchFundamentalsBatch — synthetic fundamentals. Numbers are
// proportional to a base scale derived from the ticker hash so that
// big-ticker stocks (AAPL, MSFT) read as bigger than small-caps.
func (p *MockProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
	out := make([]FundamentalsFromAPI, 0, len(tickers))
	for _, t := range tickers {
		r := rand.New(rand.NewSource(tickerSeed(t)))
		scale := 1e9 + r.Float64()*5e11 // $1B – $500B
		out = append(out, FundamentalsFromAPI{
			Ticker:            t,
			MarketCap:         int64(scale),
			TotalAssets:       scale * (0.6 + r.Float64()*0.5),
			TotalDebt:         scale * (0.10 + r.Float64()*0.30), // 10-40% debt ratio
			CashAndEquiv:      scale * (0.05 + r.Float64()*0.15),
			TotalRevenue:      scale * (0.20 + r.Float64()*0.35),
			InterestIncome:    scale * (0.001 + r.Float64()*0.004),
			InterestExpense:   scale * (0.005 + r.Float64()*0.015),
			NetIncome:         scale * (0.05 + r.Float64()*0.20),
			DividendsPerShare: r.Float64() * 4,
			AsOfDate:          time.Now().Format("2006-01-02"),
			RawJSON:           "{}",
		})
	}
	return out, nil
}

// ─── Indexes ────────────────────────────────────────────────────────

var mockIndexes = []struct {
	symbol, name, category string
}{
	{"SPY", "S&P 500", "US"},
	{"QQQ", "Nasdaq 100", "US"},
	{"DIA", "Dow Jones", "US"},
	{"IWM", "Russell 2000", "US"},
	{"VXX", "VIX", "US"},
	{"URTH", "MSCI World", "GLOBAL"},
	{"FEZ", "Euro Stoxx 50", "EU"},
	{"EWU", "FTSE 100", "EU"},
	{"EWJ", "Nikkei 225", "ASIA"},
	{"EWH", "Hang Seng", "ASIA"},
	{"UUP", "USD Index", "FX"},
}

// FetchIndexes returns realistic-looking quotes for the canonical set
// of market indexes. Each refresh nudges the prices via the daily walk
// so the indexes screen feels alive.
func (p *MockProvider) FetchIndexes() ([]IndexData, error) {
	out := make([]IndexData, 0, len(mockIndexes))
	for _, idx := range mockIndexes {
		price, change, changePct := currentQuote(idx.symbol)
		// 30-day sparkline so the index card has a chart.
		spark := make([]float64, 30)
		sparkDates := make([]string, 30)
		now := time.Now()
		base := basePrice(idx.symbol)
		for i := 0; i < 30; i++ {
			day := now.AddDate(0, 0, -29+i).YearDay()
			base *= (1 + dayWalk(idx.symbol, day))
			spark[i] = math.Round(base*100) / 100
			sparkDates[i] = now.AddDate(0, 0, -29+i).Format("2006-01-02")
		}
		out = append(out, IndexData{
			Symbol:         idx.symbol,
			Name:           idx.name,
			Price:          price,
			Change:         change,
			ChangePercent:  changePct,
			Category:       idx.category,
			Sparkline:      spark,
			SparklineDates: sparkDates,
		})
	}
	return out, nil
}

// ─── Sentiment ──────────────────────────────────────────────────────

// FetchFearAndGreed returns a value that drifts day-to-day around 50
// (neutral). Color/label maps to the standard CNN F&G zones.
func (p *MockProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	now := time.Now()
	dayKey := fmt.Sprintf("FNG-%d-%d", now.Year(), now.YearDay())
	r := rand.New(rand.NewSource(tickerSeed(dayKey)))
	value := 30 + r.Intn(60) // 30 – 89, never extreme

	label, color := fngLabel(value)

	// 30-day trend so the chart reads.
	trend := make([]int, 30)
	trendDates := make([]string, 30)
	for i := 0; i < 30; i++ {
		d := now.AddDate(0, 0, -29+i)
		k := fmt.Sprintf("FNG-%d-%d", d.Year(), d.YearDay())
		rr := rand.New(rand.NewSource(tickerSeed(k)))
		trend[i] = 30 + rr.Intn(60)
		trendDates[i] = d.Format("2006-01-02")
	}

	return FearAndGreedData{
		Value:        value,
		Label:        label,
		Color:        color,
		LastUpdated:  now.Format(time.RFC3339),
		PreviousDate: now.AddDate(0, 0, -1).Format("2006-01-02"),
		Trend:        trend,
		TrendDates:   trendDates,
	}, nil
}

func fngLabel(v int) (label, color string) {
	switch {
	case v <= 24:
		return "Extreme Fear", "#E53935"
	case v <= 44:
		return "Fear", "#FB8C00"
	case v <= 55:
		return "Neutral", "#FDD835"
	case v <= 74:
		return "Greed", "#7CB342"
	default:
		return "Extreme Greed", "#43A047"
	}
}

// ─── Exchange rate ──────────────────────────────────────────────────

// FetchExchangeRate — static mock rates between common currencies.
// USD-anchored. Adjust if the app starts caring about precise FX.
func (p *MockProvider) FetchExchangeRate(from, to string) (float64, error) {
	rates := map[string]float64{
		"USD": 1.00,
		"EUR": 0.92,
		"GBP": 0.79,
		"AED": 3.67,
		"SAR": 3.75,
		"JPY": 152.40,
		"CNY": 7.24,
	}
	f := rates[from]
	t := rates[to]
	if f == 0 || t == 0 {
		return 0, fmt.Errorf("unknown currency: %s -> %s", from, to)
	}
	return t / f, nil
}

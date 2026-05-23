package marketdata

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// EODHDProvider talks to eodhd.com. The app's "stocks" side is a Shariah
// screener (fundamentals → Halal verdict), so the method that matters here
// is FetchFundamentalsBatch. Index/price work is handled separately.
type EODHDProvider struct {
	APIKey string
	Client *http.Client
	store  MarketStore // optional — set via SetStore for index persistence

	mu            sync.RWMutex
	cachedIndices []IndexData // populated by StartBackgroundRefresh / lazy fetch
}

func NewEODHDProvider(apiKey string) *EODHDProvider {
	return &EODHDProvider{
		APIKey: apiKey,
		Client: &http.Client{Timeout: 30 * time.Second},
	}
}

// SetStore wires a persistence store (used by the index refresh path).
func (p *EODHDProvider) SetStore(store MarketStore) { p.store = store }

// ─────────────────────────────────────────────────────────────────────────
// Ticker → EODHD symbol mapping.
//
// Only the tickers EODHD actually covers (verified live, 2026-05-23) are
// listed. Anything NOT in this map — the Gulf/MENA names (2222, 1180, 7010,
// EMAAR, FAB, QNBK, CIB) which EODHD doesn't carry, plus VAC (seeded as
// "Hikma" but VAC.US is a different company) — resolves to "" so callers
// SKIP it and leave any existing (demo) data untouched. Those get real data
// once a Gulf-capable second provider is added.
// ─────────────────────────────────────────────────────────────────────────
var eodhdSymbolMap = map[string]string{
	// US
	"AAPL": "AAPL.US", "AMZN": "AMZN.US", "BAC": "BAC.US", "GOOGL": "GOOGL.US",
	"JPM": "JPM.US", "META": "META.US", "MSFT": "MSFT.US", "NVDA": "NVDA.US",
	"TSLA": "TSLA.US", "XOM": "XOM.US",
	// China / ADRs / HK
	"BABA": "BABA.US", "TCEHY": "TCEHY.US", "700": "0700.HK",
	// Asia (US-listed ADR)
	"TSM": "TSM.US",
	// Europe
	"ASML": "ASML.US", "SAP": "SAP.US", "NESN": "NESN.SW",
}

// eodhdSymbol resolves the EODHD symbol for an app ticker, or "" if EODHD
// has no coverage for it.
func eodhdSymbol(ticker string) string {
	return eodhdSymbolMap[strings.ToUpper(strings.TrimSpace(ticker))]
}

// ─── EODHD fundamentals JSON (only the fields we use) ────────────────────
//
// EODHD returns most financial-statement numbers as JSON strings (e.g.
// "371082000000.00") and null where a line item is absent. parseStringFloat
// tolerates both ("" → 0).

type eodhdBalanceQuarter struct {
	TotalAssets                 string `json:"totalAssets"`
	ShortLongTermDebtTotal      string `json:"shortLongTermDebtTotal"` // total debt (short + long)
	LongTermDebt                string `json:"longTermDebt"`           // fallback when the total is null
	Cash                        string `json:"cash"`
	CashAndShortTermInvestments string `json:"cashAndShortTermInvestments"` // fallback for cash
	NetReceivables              string `json:"netReceivables"`
}

type eodhdIncomeQuarter struct {
	TotalRevenue      string `json:"totalRevenue"`
	InterestIncome    string `json:"interestIncome"`
	NetInterestIncome string `json:"netInterestIncome"` // fallback for banks
	NetIncome         string `json:"netIncome"`
}

type eodhdFundamentals struct {
	General struct {
		Code         string `json:"Code"`
		Name         string `json:"Name"`
		Sector       string `json:"Sector"`
		Industry     string `json:"Industry"`
		CurrencyCode string `json:"CurrencyCode"`
	} `json:"General"`
	Highlights struct {
		MarketCap float64 `json:"MarketCapitalization"`
	} `json:"Highlights"`
	Financials struct {
		BalanceSheet struct {
			Quarterly map[string]eodhdBalanceQuarter `json:"quarterly"`
		} `json:"Balance_Sheet"`
		IncomeStatement struct {
			Quarterly map[string]eodhdIncomeQuarter `json:"quarterly"`
		} `json:"Income_Statement"`
	} `json:"Financials"`
}

// FetchFundamentalsBatch fetches real fundamentals for every covered ticker.
// Uncovered tickers are silently skipped (omitted from the result) so the
// caller can leave their existing rows alone.
func (p *EODHDProvider) FetchFundamentalsBatch(tickers []string) ([]FundamentalsFromAPI, error) {
	var results []FundamentalsFromAPI

	for _, ticker := range tickers {
		symbol := eodhdSymbol(ticker)
		if symbol == "" {
			fmt.Printf("[eodhd] skip %s — no EODHD coverage (left on existing data)\n", ticker)
			continue
		}

		url := fmt.Sprintf("https://eodhd.com/api/fundamentals/%s?api_token=%s", symbol, p.APIKey)
		resp, err := p.Client.Get(url)
		if err != nil {
			fmt.Printf("[eodhd] fetch %s (%s) failed: %v\n", ticker, symbol, err)
			continue
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			fmt.Printf("[eodhd] fetch %s (%s) status %d: %s\n", ticker, symbol, resp.StatusCode, truncate(string(body), 120))
			continue
		}

		var data eodhdFundamentals
		if err := json.Unmarshal(body, &data); err != nil {
			fmt.Printf("[eodhd] parse %s failed: %v\n", ticker, err)
			continue
		}

		bsDate := latestQuarter(data.Financials.BalanceSheet.Quarterly)
		isDate := latestQuarter(data.Financials.IncomeStatement.Quarterly)
		if bsDate == "" {
			fmt.Printf("[eodhd] no balance-sheet data for %s\n", ticker)
			continue
		}
		bs := data.Financials.BalanceSheet.Quarterly[bsDate]
		is := data.Financials.IncomeStatement.Quarterly[isDate]

		totalDebt := parseStringFloat(bs.ShortLongTermDebtTotal)
		if totalDebt == 0 {
			totalDebt = parseStringFloat(bs.LongTermDebt)
		}
		cash := parseStringFloat(bs.Cash)
		if cash == 0 {
			cash = parseStringFloat(bs.CashAndShortTermInvestments)
		}
		interestIncome := parseStringFloat(is.InterestIncome)
		if interestIncome == 0 {
			interestIncome = parseStringFloat(is.NetInterestIncome)
		}

		results = append(results, FundamentalsFromAPI{
			Ticker:         ticker, // keep the APP ticker so the caller can match the DB row
			CompanyName:    data.General.Name,
			Sector:         data.General.Sector,
			Industry:       data.General.Industry,
			MarketCap:      int64(data.Highlights.MarketCap),
			TotalAssets:    parseStringFloat(bs.TotalAssets),
			TotalDebt:      totalDebt,
			CashAndEquiv:   cash,
			TotalRevenue:   parseStringFloat(is.TotalRevenue),
			InterestIncome: interestIncome,
			NetIncome:      parseStringFloat(is.NetIncome),
			AsOfDate:       bsDate,
			RawJSON:        "",
		})

		// Be polite to the API even though the paid plan allows 100k/day.
		time.Sleep(250 * time.Millisecond)
	}

	return results, nil
}

// latestQuarter returns the most recent quarter key (YYYY-MM-DD sorts
// lexically) present in an EODHD quarterly map.
func latestQuarter[V any](q map[string]V) string {
	latest := ""
	for date := range q {
		if date > latest {
			latest = date
		}
	}
	return latest
}

func parseStringFloat(s string) float64 {
	s = strings.TrimSpace(s)
	if s == "" {
		return 0
	}
	var f float64
	fmt.Sscanf(s, "%f", &f)
	return f
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// ─── Interface methods not used by the fundamentals/Shariah path ─────────
//
// The catalog is DB-seeded (source of truth), DB-backed search is used, and
// indexes/sentiment/FX are handled separately — so these return empty/safe
// values just like the mock provider does.

var _ MarketDataProvider = &EODHDProvider{}

func (p *EODHDProvider) FetchStockUniverse(regionCode string) ([]StockFromAPI, error) {
	return []StockFromAPI{}, nil
}

func (p *EODHDProvider) SearchStocks(query string) ([]StockFromAPI, error) {
	return []StockFromAPI{}, nil
}

// ─── Indexes ─────────────────────────────────────────────────────────────
//
// The app shows 13 indexes (the rows in `market_indexes`). EODHD doesn't have
// every one as a native index, so equity benchmarks use their tradeable ETF
// proxy (SPY=S&P 500, QQQ=Nasdaq, …), crude oil uses USO (WTI oil ETF), and
// the 10Y yield uses TNX.INDX. The app's display Symbol is kept (e.g. "SPY")
// so it matches the existing market_indexes rows; only the fetch uses the
// EODHD symbol. All 13 verified live 2026-05-23.

// Symbol = the app's market_indexes key (kept stable so upserts update in
// place). EODHD = the symbol we fetch. Scale multiplies the close (TNX is
// quoted ×10 by CBOE, so ÷10 gives the real yield %).
//
// Where a true index exists on EODHD we use it (.INDX) so the value matches
// what Google/Bloomberg show. Four indices have NO index symbol on this EODHD
// plan (Russell 2000, FTSE 100, MSCI World, WTI crude) — those keep a
// tradeable ETF proxy, which tracks the same thing but at a different scale.
// Symbol = the app's market_indexes key (kept stable so upserts update in
// place). Source = which API to fetch from ("eodhd" or "yahoo"); Sym = the
// symbol for that source. Scale multiplies the close (TNX is quoted ×10 by
// CBOE, so ÷10 gives the real yield %).
//
// All 13 resolve to the TRUE index value (matches Google/Bloomberg). EODHD
// covers most; the four it lacks (Russell 2000, FTSE 100, MSCI World, WTI
// crude — licensed/commodity) come from Yahoo Finance's free chart API.
var eodhdIndexDefs = []struct {
	Symbol, Source, Sym, Name, Category string
	Scale                               float64
}{
	{"SPY", "eodhd", "GSPC.INDX", "S&P 500", "Benchmarks", 1},
	{"QQQ", "eodhd", "NDX.INDX", "Nasdaq 100", "Benchmarks", 1},
	{"DIA", "eodhd", "DJI.INDX", "Dow Jones", "Benchmarks", 1},
	{"IWM", "yahoo", "^RUT", "Russell 2000", "Health", 1},
	{"VXX", "eodhd", "VIX.INDX", "VIX Fear Gauge", "Health", 1},
	{"URTH", "yahoo", "^990100-USD-STRD", "MSCI World", "Global", 1},
	{"FEZ", "eodhd", "SX5E.INDX", "Euro Stoxx 50", "Global", 1},
	{"EWU", "yahoo", "^FTSE", "FTSE 100", "Global", 1},
	{"EWJ", "eodhd", "N225.INDX", "Nikkei 225", "Global", 1},
	{"EWH", "eodhd", "HSI.INDX", "Hang Seng", "Global", 1},
	{"UUP", "eodhd", "DXY.INDX", "US Dollar Index", "Macro", 1},
	{"CL", "yahoo", "CL=F", "Crude Oil", "Macro", 1},
	{"TNX", "eodhd", "TNX.INDX", "US 10Y Yield", "Macro", 0.1}, // CBOE quotes ×10 → real yield %
}

type eodhdEODPoint struct {
	Date  string  `json:"date"`
	Close float64 `json:"close"`
}

// fetchIndexEOD pulls ~150 calendar days of daily closes (≈100 trading days),
// ascending, for one EODHD symbol. 100 points is enough for the expert
// "share chart" 90-day window and the detail screen's 3M range — all real.
func (p *EODHDProvider) fetchIndexEOD(eodhdSym string) ([]eodhdEODPoint, error) {
	from := time.Now().AddDate(0, 0, -150).Format("2006-01-02")
	url := fmt.Sprintf("https://eodhd.com/api/eod/%s?api_token=%s&fmt=json&order=a&from=%s",
		eodhdSym, p.APIKey, from)
	resp, err := p.Client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("status %d: %s", resp.StatusCode, truncate(string(body), 80))
	}
	var pts []eodhdEODPoint
	if err := json.NewDecoder(resp.Body).Decode(&pts); err != nil {
		return nil, err
	}
	return pts, nil
}

// yahooChart is the slice of Yahoo's /v8/finance/chart response we use.
type yahooChart struct {
	Chart struct {
		Result []struct {
			Timestamp  []int64 `json:"timestamp"`
			Indicators struct {
				Quote []struct {
					Close []*float64 `json:"close"`
				} `json:"quote"`
			} `json:"indicators"`
		} `json:"result"`
	} `json:"chart"`
}

// fetchYahooEOD pulls ~6 months of daily closes from Yahoo Finance's free,
// no-key chart API — used for the indices EODHD's plan doesn't carry
// (Russell 2000, FTSE 100, MSCI World, WTI crude). Returns ascending points
// shaped like fetchIndexEOD so the rest of the pipeline is identical.
func (p *EODHDProvider) fetchYahooEOD(sym string) ([]eodhdEODPoint, error) {
	u := "https://query1.finance.yahoo.com/v8/finance/chart/" +
		url.PathEscape(sym) + "?range=6mo&interval=1d"
	req, err := http.NewRequest(http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	// Yahoo blocks default Go user-agents — present a browser UA.
	req.Header.Set("User-Agent",
		"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36")
	resp, err := p.Client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("yahoo status %d: %s", resp.StatusCode, truncate(string(body), 80))
	}
	var yc yahooChart
	if err := json.NewDecoder(resp.Body).Decode(&yc); err != nil {
		return nil, err
	}
	if len(yc.Chart.Result) == 0 || len(yc.Chart.Result[0].Indicators.Quote) == 0 {
		return nil, fmt.Errorf("yahoo: empty result for %s", sym)
	}
	r := yc.Chart.Result[0]
	closes := r.Indicators.Quote[0].Close
	out := make([]eodhdEODPoint, 0, len(r.Timestamp))
	for i, ts := range r.Timestamp {
		if i >= len(closes) || closes[i] == nil {
			continue // skip non-trading / null days
		}
		out = append(out, eodhdEODPoint{
			Date:  time.Unix(ts, 0).UTC().Format("2006-01-02"),
			Close: *closes[i],
		})
	}
	return out, nil
}

// fetchIndicesNow fetches real data for all 13 indexes and builds the
// price/change/sparkline shape the app expects. Any index whose symbol fails
// is skipped (its existing stored row is left as-is).
func (p *EODHDProvider) fetchIndicesNow() []IndexData {
	out := make([]IndexData, 0, len(eodhdIndexDefs))
	for _, def := range eodhdIndexDefs {
		var pts []eodhdEODPoint
		var err error
		if def.Source == "yahoo" {
			pts, err = p.fetchYahooEOD(def.Sym)
		} else {
			pts, err = p.fetchIndexEOD(def.Sym)
		}
		if err != nil || len(pts) < 2 {
			log.Printf("[index] %s (%s:%s) skipped: %v", def.Symbol, def.Source, def.Sym, err)
			continue
		}
		scale := def.Scale
		if scale == 0 {
			scale = 1
		}
		// Last up to 100 closes → sparkline (covers share 7/30/90-day slices
		// and the detail screen's ranges up to 3M, all real).
		start := 0
		if len(pts) > 100 {
			start = len(pts) - 100
		}
		window := pts[start:]
		spark := make([]float64, len(window))
		dates := make([]string, len(window))
		for i, pt := range window {
			spark[i] = round2(pt.Close * scale)
			dates[i] = pt.Date
		}
		price := pts[len(pts)-1].Close * scale
		prev := pts[len(pts)-2].Close * scale
		change := price - prev
		changePct := 0.0
		if prev != 0 {
			changePct = change / prev * 100
		}
		out = append(out, IndexData{
			Symbol:         def.Symbol,
			Name:           def.Name,
			Price:          round2(price),
			Change:         round2(change),
			ChangePercent:  round2(changePct),
			Category:       def.Category,
			Sparkline:      spark,
			SparklineDates: dates,
		})
		time.Sleep(120 * time.Millisecond)
	}
	return out
}

func (p *EODHDProvider) refreshIndicesCache() {
	idx := p.fetchIndicesNow()
	if len(idx) == 0 {
		return
	}
	p.mu.Lock()
	p.cachedIndices = idx
	p.mu.Unlock()
	if p.store != nil {
		for _, i := range idx {
			if err := p.store.UpsertIndex(i); err != nil {
				log.Printf("[eodhd] persist index %s: %v", i.Symbol, err)
			}
		}
	}
	log.Printf("[eodhd] refreshed %d/%d indexes", len(idx), len(eodhdIndexDefs))
}

// StartBackgroundRefresh kicks off an initial index fetch then refreshes
// every 10 minutes. Mirrors the AlphaVantage provider.
func (p *EODHDProvider) StartBackgroundRefresh() {
	go func() {
		log.Println("[eodhd] initial index fetch…")
		p.refreshIndicesCache()
		ticker := time.NewTicker(10 * time.Minute)
		defer ticker.Stop()
		for range ticker.C {
			p.refreshIndicesCache()
		}
	}()
}

// FetchIndexes returns the cached indexes; on a cold start (cache empty) it
// fetches synchronously so the first request still gets real data.
func (p *EODHDProvider) FetchIndexes() ([]IndexData, error) {
	p.mu.RLock()
	cached := p.cachedIndices
	p.mu.RUnlock()
	if len(cached) > 0 {
		return cached, nil
	}
	idx := p.fetchIndicesNow()
	if len(idx) > 0 {
		p.mu.Lock()
		p.cachedIndices = idx
		p.mu.Unlock()
		if p.store != nil {
			for _, i := range idx {
				_ = p.store.UpsertIndex(i)
			}
		}
	}
	return idx, nil
}

func round2(f float64) float64 { return math.Round(f*100) / 100 }

// FetchFearAndGreed — EODHD has no Fear & Greed feed; return a neutral
// reading so the sentiment screen stays well-formed.
func (p *EODHDProvider) FetchFearAndGreed() (FearAndGreedData, error) {
	return FearAndGreedData{
		Value:       50,
		Label:       "Neutral",
		Color:       "#FDD835",
		LastUpdated: time.Now().Format(time.RFC3339),
	}, nil
}

// FetchExchangeRate — USD-anchored static table (same approach as the mock).
func (p *EODHDProvider) FetchExchangeRate(from, to string) (float64, error) {
	if from == to {
		return 1.0, nil
	}
	rates := map[string]float64{
		"USD": 1.00, "EUR": 0.92, "GBP": 0.79, "AED": 3.67,
		"SAR": 3.75, "JPY": 152.40, "CNY": 7.24, "CHF": 0.88, "HKD": 7.82,
	}
	f, t := rates[from], rates[to]
	if f == 0 || t == 0 {
		return 0, fmt.Errorf("unknown currency: %s -> %s", from, to)
	}
	return t / f, nil
}

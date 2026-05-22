package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"halalstocks/internal/pipeline"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// FMPProvider implements the Provider interface for Financial Modeling Prep API
type FMPProvider struct {
	apiKey  string
	baseURL string
	client  *http.Client
	logger  *slog.Logger
}

// NewFMPProvider creates a new FMP provider
func NewFMPProvider(apiKey string, logger *slog.Logger) *FMPProvider {
	if logger == nil {
		logger = slog.Default()
	}
	
	return &FMPProvider{
		apiKey:  apiKey,
		baseURL: "https://financialmodelingprep.com/api/v3",
		client: &http.Client{
			Timeout: 30 * time.Second,
		},
		logger: logger,
	}
}

func (p *FMPProvider) Name() string {
	return "FMP"
}

func (p *FMPProvider) IsAvailable(ctx context.Context) bool {
	// Simple check: if we have an API key, we're available
	return p.apiKey != ""
}

func (p *FMPProvider) FetchSnapshot(ctx context.Context, symbol string, exchange string) (*pipeline.StockSnapshot, error) {
	snapshot := &pipeline.StockSnapshot{
		Symbol:      symbol,
		Exchange:    exchange,
		SnapshotDate: time.Now().UTC(),
		ProviderName: p.Name(),
	}

	// Fetch profile (company info)
	if err := p.fetchProfile(ctx, snapshot); err != nil {
		p.logger.Warn("Failed to fetch profile", "symbol", symbol, "error", err)
	}

	// Fetch key metrics (market data)
	if err := p.fetchKeyMetrics(ctx, snapshot); err != nil {
		p.logger.Warn("Failed to fetch key metrics", "symbol", symbol, "error", err)
	}

	// Fetch income statement
	if err := p.fetchIncomeStatement(ctx, snapshot); err != nil {
		p.logger.Warn("Failed to fetch income statement", "symbol", symbol, "error", err)
	}

	// Fetch balance sheet
	if err := p.fetchBalanceSheet(ctx, snapshot); err != nil {
		p.logger.Warn("Failed to fetch balance sheet", "symbol", symbol, "error", err)
	}

	// Fetch cash flow
	if err := p.fetchCashFlow(ctx, snapshot); err != nil {
		p.logger.Warn("Failed to fetch cash flow", "symbol", symbol, "error", err)
	}

	snapshot.AssessQuality()
	return snapshot, nil
}

func (p *FMPProvider) FetchSnapshotsBulk(ctx context.Context, symbols []string, exchanges []string) (map[string]*pipeline.StockSnapshot, []error) {
	results := make(map[string]*pipeline.StockSnapshot)
	var errors []error

	// FMP doesn't have a true bulk endpoint, so we'll fetch individually
	// but with rate limiting
	for i, symbol := range symbols {
		exchange := ""
		if i < len(exchanges) {
			exchange = exchanges[i]
		}

		snapshot, err := p.FetchSnapshot(ctx, symbol, exchange)
		if err != nil {
			errors = append(errors, fmt.Errorf("%s: %w", symbol, err))
			continue
		}
		results[symbol] = snapshot

		// Rate limiting: 1 request per 250ms (240 requests/minute)
		time.Sleep(250 * time.Millisecond)
	}

	return results, errors
}

func (p *FMPProvider) fetchProfile(ctx context.Context, snapshot *pipeline.StockSnapshot) error {
	url := fmt.Sprintf("%s/profile/%s?apikey=%s", p.baseURL, snapshot.Symbol, p.apiKey)
	
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var profiles []map[string]interface{}
	if err := json.Unmarshal(body, &profiles); err != nil {
		return err
	}

	if len(profiles) == 0 {
		return fmt.Errorf("no profile data")
	}

	profile := profiles[0]
	
	if name, ok := profile["companyName"].(string); ok {
		snapshot.CompanyName = name
	}
	if sector, ok := profile["sector"].(string); ok {
		snapshot.Sector = sector
	}
	if industry, ok := profile["industry"].(string); ok {
		snapshot.Industry = industry
	}
	if country, ok := profile["country"].(string); ok {
		snapshot.Country = country
	}
	if desc, ok := profile["description"].(string); ok {
		snapshot.Description = desc
	}
	if currency, ok := profile["currency"].(string); ok {
		snapshot.Currency = currency
	}

	return nil
}

func (p *FMPProvider) fetchKeyMetrics(ctx context.Context, snapshot *pipeline.StockSnapshot) error {
	url := fmt.Sprintf("%s/key-metrics-ttm/%s?apikey=%s", p.baseURL, snapshot.Symbol, p.apiKey)
	
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var metrics []map[string]interface{}
	if err := json.Unmarshal(body, &metrics); err != nil {
		return err
	}

	if len(metrics) == 0 {
		return fmt.Errorf("no metrics data")
	}

	metric := metrics[0]
	
	if price, ok := metric["priceToBookRatioTTM"].(float64); ok {
		// FMP doesn't directly give price, we'd need another endpoint
		// For now, skip price from metrics
		_ = price
	}
	if marketCap, ok := metric["marketCap"].(float64); ok {
		snapshot.MarketCap = marketCap
	}
	if shares, ok := metric["sharesOutstanding"].(float64); ok {
		snapshot.SharesOutstanding = shares
	}

	return nil
}

func (p *FMPProvider) fetchIncomeStatement(ctx context.Context, snapshot *pipeline.StockSnapshot) error {
	url := fmt.Sprintf("%s/income-statement/%s?limit=1&apikey=%s", p.baseURL, snapshot.Symbol, p.apiKey)
	
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var statements []map[string]interface{}
	if err := json.Unmarshal(body, &statements); err != nil {
		return err
	}

	if len(statements) == 0 {
		return fmt.Errorf("no income statement data")
	}

	stmt := statements[0]
	
	if revenue, ok := stmt["revenue"].(float64); ok {
		snapshot.Revenue = revenue
	}
	if opIncome, ok := stmt["operatingIncome"].(float64); ok {
		snapshot.OperatingIncome = opIncome
	}
	if netIncome, ok := stmt["netIncome"].(float64); ok {
		snapshot.NetIncome = netIncome
	}
	if intIncome, ok := stmt["interestIncome"].(float64); ok {
		snapshot.InterestIncome = intIncome
	}
	if intExpense, ok := stmt["interestExpense"].(float64); ok {
		snapshot.InterestExpense = intExpense
	}
	if date, ok := stmt["date"].(string); ok {
		if t, err := time.Parse("2006-01-02", date); err == nil {
			snapshot.LastReportDate = t
		}
	}

	return nil
}

func (p *FMPProvider) fetchBalanceSheet(ctx context.Context, snapshot *pipeline.StockSnapshot) error {
	url := fmt.Sprintf("%s/balance-sheet-statement/%s?limit=1&apikey=%s", p.baseURL, snapshot.Symbol, p.apiKey)
	
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var sheets []map[string]interface{}
	if err := json.Unmarshal(body, &sheets); err != nil {
		return err
	}

	if len(sheets) == 0 {
		return fmt.Errorf("no balance sheet data")
	}

	sheet := sheets[0]
	
	if assets, ok := sheet["totalAssets"].(float64); ok {
		snapshot.TotalAssets = assets
	}
	if liabilities, ok := sheet["totalLiabilities"].(float64); ok {
		snapshot.TotalLiabilities = liabilities
	}
	if debt, ok := sheet["totalDebt"].(float64); ok {
		snapshot.TotalDebt = debt
	}
	if stDebt, ok := sheet["shortTermDebt"].(float64); ok {
		snapshot.ShortTermDebt = stDebt
	}
	if ltDebt, ok := sheet["longTermDebt"].(float64); ok {
		snapshot.LongTermDebt = ltDebt
	}
	if cash, ok := sheet["cashAndCashEquivalents"].(float64); ok {
		snapshot.CashAndEquivalents = cash
	}
	if stInv, ok := sheet["shortTermInvestments"].(float64); ok {
		snapshot.ShortTermInvestments = stInv
	}

	return nil
}

func (p *FMPProvider) fetchCashFlow(ctx context.Context, snapshot *pipeline.StockSnapshot) error {
	url := fmt.Sprintf("%s/cash-flow-statement/%s?limit=1&apikey=%s", p.baseURL, snapshot.Symbol, p.apiKey)
	
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return err
	}

	resp, err := p.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status: %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return err
	}

	var flows []map[string]interface{}
	if err := json.Unmarshal(body, &flows); err != nil {
		return err
	}

	if len(flows) == 0 {
		return fmt.Errorf("no cash flow data")
	}

	flow := flows[0]
	
	if opCF, ok := flow["operatingCashFlow"].(float64); ok {
		snapshot.OperatingCashFlow = opCF
	}
	if finCF, ok := flow["financingCashFlow"].(float64); ok {
		snapshot.FinancingCashFlow = finCF
	}
	if intPaid, ok := flow["interestPaid"].(float64); ok {
		snapshot.InterestPaid = intPaid
	}

	return nil
}


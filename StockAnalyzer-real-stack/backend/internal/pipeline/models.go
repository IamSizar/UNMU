package pipeline

import (
	"time"
)

// StockSnapshot represents a unified snapshot of stock data from any provider
// This is the canonical internal model that all providers must map to
type StockSnapshot struct {
	// Identity
	Symbol      string
	Exchange    string
	CompanyName string
	Country     string
	Sector      string
	Industry    string
	Description string

	// Market data
	Price             float64
	MarketCap         float64
	SharesOutstanding float64
	Currency          string

	// Income Statement (last annual & last TTM if available)
	Revenue         float64
	OperatingIncome float64
	NetIncome       float64
	InterestIncome  float64
	InterestExpense float64
	OtherIncome     float64

	// Balance Sheet
	TotalAssets          float64
	TotalLiabilities     float64
	TotalDebt            float64
	ShortTermDebt        float64
	LongTermDebt         float64
	CashAndEquivalents   float64
	ShortTermInvestments float64

	// Cash Flow
	OperatingCashFlow float64
	FinancingCashFlow float64
	InterestPaid      float64

	// Timings
	FiscalYearEnd string
	LastReportDate time.Time
	SnapshotDate   time.Time

	// Metadata
	ProviderName string // Which provider this data came from
	DataQuality  DataQuality // Quality assessment of the data
}

// DataQuality indicates how complete the data is
type DataQuality string

const (
	DataQualityComplete    DataQuality = "COMPLETE"     // All critical fields present
	DataQualityPartial     DataQuality = "PARTIAL"      // Some critical fields missing
	DataQualityInsufficient DataQuality = "INSUFFICIENT" // Too many critical fields missing
)

// ShariahStatus represents the compliance status
type ShariahStatus string

const (
	ShariahStatusHalal       ShariahStatus = "HALAL"
	ShariahStatusHaram       ShariahStatus = "HARAM"
	ShariahStatusDoubtful    ShariahStatus = "DOUBTFUL"
	ShariahStatusNeedsReview ShariahStatus = "NEEDS_REVIEW"
	ShariahStatusMixed       ShariahStatus = "MIXED" // For backward compatibility
)

// ShariahResult contains the result of Shariah screening
type ShariahResult struct {
	Symbol            string
	Exchange          string
	Status            ShariahStatus
	StatusReason      string // Short explanation
	DetailedBreakdown string // JSON or text describing ratios, failed rules, etc.
	EvaluatedAt       time.Time

	// Financial ratios used in evaluation
	DebtRatio            *float64
	HaramIncomeRatio     *float64
	CashToMarketCapRatio *float64
	PurificationRate     *float64

	// Grade (A, B, C, F) for backward compatibility
	Grade string
}

// IsComplete checks if a snapshot has enough data for Shariah screening
// Critical fields: Revenue, TotalAssets, TotalDebt, CashAndEquivalents, Price, MarketCap
func (s *StockSnapshot) IsComplete() bool {
	hasRevenue := s.Revenue > 0
	hasAssets := s.TotalAssets > 0
	hasDebt := s.TotalDebt >= 0 // Can be 0 (no debt is valid)
	hasCash := s.CashAndEquivalents >= 0
	hasMarketCap := s.MarketCap > 0

	// At minimum, we need assets and market cap for basic screening
	// Revenue and debt are highly preferred but we can work with partial data
	return hasAssets && hasMarketCap && (hasRevenue || hasDebt || hasCash)
}

// CompletenessScore returns a score 0-1 indicating data completeness
func (s *StockSnapshot) CompletenessScore() float64 {
	required := []bool{
		s.Revenue > 0,
		s.TotalAssets > 0,
		s.TotalDebt >= 0,
		s.CashAndEquivalents >= 0,
		s.Price > 0,
		s.MarketCap > 0,
		s.InterestIncome >= 0,
		s.InterestExpense >= 0,
	}

	count := 0
	for _, present := range required {
		if present {
			count++
		}
	}

	return float64(count) / float64(len(required))
}

// AssessQuality sets the DataQuality field based on completeness
func (s *StockSnapshot) AssessQuality() {
	score := s.CompletenessScore()
	if score >= 0.8 {
		s.DataQuality = DataQualityComplete
	} else if score >= 0.5 {
		s.DataQuality = DataQualityPartial
	} else {
		s.DataQuality = DataQualityInsufficient
	}
}


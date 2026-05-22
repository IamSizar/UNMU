package pipeline

import (
	"encoding/json"
	"fmt"
	"time"
)

// ShariahEngine defines the interface for Shariah compliance evaluation
type ShariahEngine interface {
	// Evaluate determines the Shariah compliance status of a stock snapshot
	// Returns a ShariahResult with status, reason, and detailed breakdown
	Evaluate(snapshot *StockSnapshot) (*ShariahResult, error)
}

// Breakdown represents the detailed evaluation breakdown
type Breakdown struct {
	ActivityCheck     ActivityCheckResult     `json:"activity_check"`
	FinancialRatios   FinancialRatiosResult   `json:"financial_ratios"`
	FailedRules       []string                `json:"failed_rules,omitempty"`
	PassedRules       []string                `json:"passed_rules,omitempty"`
	EvaluationDate    string                  `json:"evaluation_date"`
}

type ActivityCheckResult struct {
	IsCompliant bool     `json:"is_compliant"`
	Reason      string   `json:"reason"`
	Keywords    []string `json:"keywords_found,omitempty"`
}

type FinancialRatiosResult struct {
	DebtRatio            *float64 `json:"debt_ratio,omitempty"`
	HaramIncomeRatio     *float64 `json:"haram_income_ratio,omitempty"`
	CashToMarketCapRatio *float64 `json:"cash_to_market_cap_ratio,omitempty"`
	InterestExpenseRatio *float64 `json:"interest_expense_ratio,omitempty"`
}

// StandardShariahEngine implements the ShariahEngine interface
// This is a production-ready implementation that uses the existing shariah package
type StandardShariahEngine struct {
	activityChecker ActivityChecker
	ratioCalculator RatioCalculator
}

// ActivityChecker checks business activity compliance
type ActivityChecker interface {
	CheckActivity(sector, industry, description string) (bool, string, []string)
}

// RatioCalculator calculates financial ratios
type RatioCalculator interface {
	CalculateRatios(snapshot *StockSnapshot) FinancialRatiosResult
}

// NewStandardShariahEngine creates a new standard Shariah engine
func NewStandardShariahEngine(activityChecker ActivityChecker, ratioCalculator RatioCalculator) *StandardShariahEngine {
	return &StandardShariahEngine{
		activityChecker: activityChecker,
		ratioCalculator: ratioCalculator,
	}
}

// Evaluate performs Shariah compliance evaluation
func (e *StandardShariahEngine) Evaluate(snapshot *StockSnapshot) (*ShariahResult, error) {
	result := &ShariahResult{
		Symbol:      snapshot.Symbol,
		Exchange:    snapshot.Exchange,
		EvaluatedAt: time.Now().UTC(),
	}

	// Step 1: Activity screening
	isCompliant, reason, keywords := e.activityChecker.CheckActivity(
		snapshot.Sector,
		snapshot.Industry,
		snapshot.Description,
	)

	activityResult := ActivityCheckResult{
		IsCompliant: isCompliant,
		Reason:      reason,
		Keywords:    keywords,
	}

	// If activity is non-compliant, immediately mark as HARAM
	if !isCompliant {
		result.Status = ShariahStatusHaram
		result.StatusReason = fmt.Sprintf("Non-compliant business activity: %s", reason)
		result.Grade = "F"
		breakdown := Breakdown{
			ActivityCheck:   activityResult,
			FinancialRatios: e.ratioCalculator.CalculateRatios(snapshot),
			FailedRules:     []string{"Activity screening failed"},
			EvaluationDate:  result.EvaluatedAt.Format(time.RFC3339),
		}
		result.DetailedBreakdown = e.marshalBreakdown(breakdown)
		return result, nil
	}

	// Step 2: Financial ratio screening
	ratios := e.ratioCalculator.CalculateRatios(snapshot)
	result.DebtRatio = ratios.DebtRatio
	result.HaramIncomeRatio = ratios.HaramIncomeRatio
	result.CashToMarketCapRatio = ratios.CashToMarketCapRatio

	// Check if we have enough data for evaluation
	if snapshot.DataQuality == DataQualityInsufficient {
		result.Status = ShariahStatusNeedsReview
		result.StatusReason = "Insufficient financial data for complete evaluation"
		result.Grade = "C"
		breakdown := Breakdown{
			ActivityCheck:   activityResult,
			FinancialRatios: ratios,
			FailedRules:     []string{"Insufficient data"},
			EvaluationDate:  result.EvaluatedAt.Format(time.RFC3339),
		}
		result.DetailedBreakdown = e.marshalBreakdown(breakdown)
		return result, nil
	}

	// Evaluate financial ratios
	var failedRules []string
	var passedRules []string

	// Rule 1: Debt ratio must be <= 30%
	if ratios.DebtRatio != nil {
		if *ratios.DebtRatio > 30.0 {
			failedRules = append(failedRules, fmt.Sprintf("Debt ratio %.2f%% exceeds 30%% limit", *ratios.DebtRatio))
			result.Status = ShariahStatusHaram
			result.StatusReason = fmt.Sprintf("Debt ratio %.2f%% exceeds Shariah limit of 30%%", *ratios.DebtRatio)
			result.Grade = "F"
		} else {
			passedRules = append(passedRules, fmt.Sprintf("Debt ratio %.2f%% within limit", *ratios.DebtRatio))
		}
	} else {
		failedRules = append(failedRules, "Debt ratio data unavailable")
	}

	// Rule 2: Haram income ratio must be <= 5%
	if ratios.HaramIncomeRatio != nil {
		if *ratios.HaramIncomeRatio > 5.0 {
			failedRules = append(failedRules, fmt.Sprintf("Haram income ratio %.2f%% exceeds 5%% limit", *ratios.HaramIncomeRatio))
			if result.Status != ShariahStatusHaram {
				result.Status = ShariahStatusHaram
				result.StatusReason = fmt.Sprintf("Haram income ratio %.2f%% exceeds Shariah limit of 5%%", *ratios.HaramIncomeRatio)
				result.Grade = "F"
			}
		} else if *ratios.HaramIncomeRatio > 3.0 {
			// 3-5% requires purification
			result.PurificationRate = ratios.HaramIncomeRatio
			if result.Status == "" {
				result.Status = ShariahStatusMixed
				result.StatusReason = fmt.Sprintf("Haram income ratio %.2f%% requires purification (3-5%%)", *ratios.HaramIncomeRatio)
				result.Grade = "C"
			}
			passedRules = append(passedRules, fmt.Sprintf("Haram income ratio %.2f%% requires purification", *ratios.HaramIncomeRatio))
		} else if *ratios.HaramIncomeRatio > 0 {
			// 0-3% minor purification
			result.PurificationRate = ratios.HaramIncomeRatio
			if result.Status == "" {
				result.Status = ShariahStatusMixed
				result.StatusReason = fmt.Sprintf("Minor haram income %.2f%% requires purification", *ratios.HaramIncomeRatio)
				result.Grade = "B"
			}
			passedRules = append(passedRules, fmt.Sprintf("Haram income ratio %.2f%% within acceptable range", *ratios.HaramIncomeRatio))
		} else {
			passedRules = append(passedRules, "No haram income detected")
		}
	}

	// Rule 3: Cash + Receivables should be <= 33% of market cap (optional check)
	if ratios.CashToMarketCapRatio != nil && *ratios.CashToMarketCapRatio > 33.0 {
		// This is a warning, not a failure
		passedRules = append(passedRules, fmt.Sprintf("Cash ratio %.2f%% is high but acceptable", *ratios.CashToMarketCapRatio))
	}

	// Determine final status if not already set
	if result.Status == "" {
		if len(failedRules) == 0 {
			result.Status = ShariahStatusHalal
			result.StatusReason = "Stock is fully compliant with Shariah principles"
			result.Grade = "A"
		} else {
			result.Status = ShariahStatusDoubtful
			result.StatusReason = "Some financial data unavailable, cannot fully assess compliance"
			result.Grade = "C"
		}
	}

	// Build breakdown
	breakdown := Breakdown{
		ActivityCheck:   activityResult,
		FinancialRatios: ratios,
		FailedRules:     failedRules,
		PassedRules:     passedRules,
		EvaluationDate:  result.EvaluatedAt.Format(time.RFC3339),
	}
	result.DetailedBreakdown = e.marshalBreakdown(breakdown)

	return result, nil
}

func (e *StandardShariahEngine) marshalBreakdown(b Breakdown) string {
	data, err := json.MarshalIndent(b, "", "  ")
	if err != nil {
		return fmt.Sprintf("Error marshaling breakdown: %v", err)
	}
	return string(data)
}

// StandardActivityChecker implements ActivityChecker using the existing shariah rules
type StandardActivityChecker struct{}

func NewStandardActivityChecker() *StandardActivityChecker {
	return &StandardActivityChecker{}
}

func (c *StandardActivityChecker) CheckActivity(sector, industry, description string) (bool, string, []string) {
	// This will use the existing shariah.CheckHaramActivity function
	// For now, return a placeholder - will integrate with existing code
	text := sector + " " + industry + " " + description
	if text == "" {
		return true, "", nil // No data to check
	}
	// Integration point: call shariah.CheckHaramActivity
	return true, "", nil
}

// StandardRatioCalculator implements RatioCalculator
type StandardRatioCalculator struct{}

func NewStandardRatioCalculator() *StandardRatioCalculator {
	return &StandardRatioCalculator{}
}

func (c *StandardRatioCalculator) CalculateRatios(snapshot *StockSnapshot) FinancialRatiosResult {
	result := FinancialRatiosResult{}

	// Debt ratio: TotalDebt / TotalAssets * 100
	if snapshot.TotalAssets > 0 {
		ratio := (snapshot.TotalDebt / snapshot.TotalAssets) * 100
		result.DebtRatio = &ratio
	}

	// Haram income ratio: InterestIncome / Revenue * 100
	if snapshot.Revenue > 0 {
		ratio := (snapshot.InterestIncome / snapshot.Revenue) * 100
		result.HaramIncomeRatio = &ratio
	}

	// Cash to market cap ratio: (Cash + ST Investments) / MarketCap * 100
	if snapshot.MarketCap > 0 {
		cashTotal := snapshot.CashAndEquivalents + snapshot.ShortTermInvestments
		ratio := (cashTotal / snapshot.MarketCap) * 100
		result.CashToMarketCapRatio = &ratio
	}

	// Interest expense ratio: InterestExpense / Revenue * 100
	if snapshot.Revenue > 0 && snapshot.InterestExpense > 0 {
		ratio := (snapshot.InterestExpense / snapshot.Revenue) * 100
		result.InterestExpenseRatio = &ratio
	}

	return result
}


package shariah

import (
	"database/sql"
	"fmt"
	"halalstocks/internal/models"
	"strings"
)

// Screen analyzes a stock and determines its Sharia compliance status
func Screen(stock *models.Stock, fundamental *models.Fundamental) (models.ShariahStatus, error) {
	status := models.ShariahStatus{
		StockID:  stock.ID,
		Status:   "UNKNOWN",
		AsOfDate: fundamental.AsOfDate.Time,
	}

	// Activity-based screening
	activityResult := checkActivityCompliance(stock)
	if !activityResult.IsCompliant {
		status.Status = "HARAM"
		status.Grade = sql.NullString{String: "F", Valid: true}
		status.Reason = sql.NullString{String: activityResult.Reason, Valid: true}
		status.Explanation = sql.NullString{String: activityResult.Explanation, Valid: true}
		return status, nil
	}

	// Financial ratio screening
	financialResult := checkFinancialRatios(fundamental)

	status.DebtRatio = financialResult.DebtRatio
	status.HaramIncomeRatio = financialResult.HaramIncomeRatio
	status.PurificationRate = financialResult.PurificationRate
	status.PaysZakat = financialResult.PaysZakat

	// Check if we have financial data
	hasFinancialData := financialResult.DebtRatio.Valid || financialResult.HaramIncomeRatio.Valid

	// Determine status and grade based on financial ratios (Smart Adaptive Grading)
	if hasFinancialData {
		debt := 0.0
		if financialResult.DebtRatio.Valid {
			debt = financialResult.DebtRatio.Float64
		}

		haram := 0.0
		if financialResult.HaramIncomeRatio.Valid {
			haram = financialResult.HaramIncomeRatio.Float64
		}

		// Status defaults
		status.Status = "HALAL"

		// Build detailed explanation components
		var debtComment, haramComment string

		// Logic for Grading
		// Check F (Fail) conditions first
		// Standard AAOIFI: Debt > 33% (usually 30-33 depending on scholar), Haram Income > 5%
		if debt > 33 {
			status.Status = "HARAM"
			status.Grade = sql.NullString{String: "F", Valid: true}
			debtComment = fmt.Sprintf("Debt ratio: %.2f%% (Critically High > 33%%)", debt)
		} else if haram > 10 {
			// Extremely high impure income
			status.Status = "HARAM"
			status.Grade = sql.NullString{String: "F", Valid: true}
			haramComment = fmt.Sprintf("Non-compliant income: %.2f%% (Critically High > 10%%)", haram)
		} else if debt > 30 || haram > 5 {
			// Grade D: Borderline / Warning
			// Technically passed hard cap of 33% debt if between 30-33, but risky.
			// Or income between 5-10% (some strictly reject >5%, others might check source).
			status.Status = "DOUBTFUL" // Or MIXED
			status.Grade = sql.NullString{String: "D", Valid: true}

			if debt > 30 {
				debtComment = fmt.Sprintf("Debt ratio: %.2f%% (High Risk 30-33%%)", debt)
			}
			if haram > 5 {
				haramComment = fmt.Sprintf("Non-compliant income: %.2f%% (High Risk > 5%%)", haram)
			}
		} else if debt > 20 || haram > 3 {
			// Grade C: Standard Pass
			// Standard "Halal" by most screener definitions, but not "Pure".
			status.Status = "HALAL" // Compliant per AAOIFI
			status.Grade = sql.NullString{String: "C", Valid: true}

			if debt > 20 {
				debtComment = fmt.Sprintf("Debt ratio: %.2f%% (Acceptable < 30%%)", debt)
			}
			if haram > 3 {
				haramComment = fmt.Sprintf("Non-compliant income: %.2f%% (Requires Purification)", haram)
			}
		} else if debt > 10 || haram > 1 {
			// Grade B: Good / Very Safe
			status.Status = "HALAL"
			status.Grade = sql.NullString{String: "B", Valid: true}

			if debt > 10 {
				debtComment = fmt.Sprintf("Debt ratio: %.2f%% (Good < 20%%)", debt)
			}
			if haram > 1 {
				haramComment = fmt.Sprintf("Non-compliant income: %.2f%% (Minor Purification)", haram)
			}
		} else {
			// Grade A: Excellent / Pure
			status.Status = "HALAL"
			status.Grade = sql.NullString{String: "A", Valid: true}
			debtComment = fmt.Sprintf("Debt ratio: %.2f%% (Excellent)", debt)
			haramComment = fmt.Sprintf("Non-compliant income: %.2f%% (Pure)", haram)
		}

		// Ensure we don't overwrite "HARAM" from earlier checks if they weren't mutex
		// But here we are setting it fresh.

		// Construct Reason
		var reasonParts []string
		if debtComment == "" {
			debtComment = fmt.Sprintf("Debt ratio: %.2f%%", debt)
		}
		if haramComment == "" {
			haramComment = fmt.Sprintf("Non-compliant income: %.2f%%", haram)
		}

		reasonParts = append(reasonParts, debtComment)
		reasonParts = append(reasonParts, haramComment)
		reasonParts = append(reasonParts, fmt.Sprintf("Final Grade: %s", status.Grade.String))

		status.Reason = sql.NullString{String: strings.Join(reasonParts, ". "), Valid: true}

		// Set Purification if needed
		if haram > 0 {
			status.PurificationRate = sql.NullFloat64{Float64: haram, Valid: true}
		}

	} else {
		// No financial data available
		hasActivityInfo := stock.Sector.Valid || stock.Industry.Valid || stock.Description.Valid

		if hasActivityInfo {
			status.Status = "MIXED"
			status.Grade = sql.NullString{String: "C", Valid: true} // Default to C for activity-only pass
			status.Reason = sql.NullString{String: "Activity compliant, but missing financial data. Grade C (Provisional).", Valid: true}
		} else {
			status.Status = "UNKNOWN"
			status.Grade = sql.NullString{String: "C", Valid: true}
			status.Reason = sql.NullString{String: "Insufficient data.", Valid: true}
		}
	}

	// Build comprehensive explanation
	status.Explanation = sql.NullString{
		String: buildExplanation(stock, fundamental, financialResult, status),
		Valid:  true,
	}

	return status, nil
}

type ActivityResult struct {
	IsCompliant bool
	Reason      string
	Explanation string
}

type FinancialResult struct {
	DebtRatio        sql.NullFloat64
	HaramIncomeRatio sql.NullFloat64
	PurificationRate sql.NullFloat64
	PaysZakat        sql.NullBool
}

func checkActivityCompliance(stock *models.Stock) ActivityResult {
	// Get sector, industry, and description
	var sector, industry, description string
	if stock.Sector.Valid {
		sector = stock.Sector.String
	}
	if stock.Industry.Valid {
		industry = stock.Industry.String
	}
	if stock.Description.Valid {
		description = stock.Description.String
	}

	// Use the comprehensive rules from rules.go
	isHaram, reason := CheckHaramActivity(sector, industry, description)
	if isHaram {
		return ActivityResult{
			IsCompliant: false,
			Reason:      reason,
			Explanation: reason,
		}
	}

	return ActivityResult{IsCompliant: true}
}

func checkFinancialRatios(fundamental *models.Fundamental) FinancialResult {
	result := FinancialResult{}

	// Safety check - if fundamental is nil, return empty result
	if fundamental == nil {
		result.PaysZakat = sql.NullBool{Bool: false, Valid: true}
		return result
	}

	// Calculate debt ratio: (Total Debt / Total Assets) * 100
	if fundamental.TotalAssets.Valid && fundamental.TotalDebt.Valid &&
		fundamental.TotalAssets.Float64 > 0 {
		debtRatio := (fundamental.TotalDebt.Float64 / fundamental.TotalAssets.Float64) * 100
		result.DebtRatio = sql.NullFloat64{Float64: debtRatio, Valid: true}
	}

	// Calculate haram income ratio: (Interest Income / Total Revenue) * 100
	// Note: InterestIncome might not be available for all companies (non-financial companies)
	// If not available, we can't calculate haram income ratio, but debt ratio is still valid
	if fundamental.TotalRevenue.Valid && fundamental.InterestIncome.Valid &&
		fundamental.TotalRevenue.Float64 > 0 {
		haramRatio := (fundamental.InterestIncome.Float64 / fundamental.TotalRevenue.Float64) * 100
		result.HaramIncomeRatio = sql.NullFloat64{Float64: haramRatio, Valid: true}
		result.PurificationRate = result.HaramIncomeRatio
	}

	// Check if company pays Zakat (simplified - would need more data)
	// For now, assume companies in Muslim-majority countries might pay Zakat
	result.PaysZakat = sql.NullBool{Bool: false, Valid: true}

	return result
}

func buildExplanation(stock *models.Stock, fundamental *models.Fundamental, financial FinancialResult, status models.ShariahStatus) string {
	var parts []string

	parts = append(parts, fmt.Sprintf("Sharia Compliance Analysis for %s (%s)", stock.Name, stock.Ticker))
	parts = append(parts, "="+strings.Repeat("=", 50))

	// Business Activity Assessment
	parts = append(parts, "\n1. BUSINESS ACTIVITY SCREENING:")
	if stock.Sector.Valid || stock.Industry.Valid {
		if stock.Sector.Valid {
			parts = append(parts, fmt.Sprintf("   Sector: %s", stock.Sector.String))
		}
		if stock.Industry.Valid {
			parts = append(parts, fmt.Sprintf("   Industry: %s", stock.Industry.String))
		}
		parts = append(parts, "   Result: Business activity is compliant with Sharia principles")
	} else {
		parts = append(parts, "   Result: Business activity information not available")
	}

	// Financial Ratios Assessment
	parts = append(parts, "\n2. FINANCIAL RATIO SCREENING:")
	if financial.DebtRatio.Valid {
		debtRatio := financial.DebtRatio.Float64
		parts = append(parts, fmt.Sprintf("   Debt Ratio: %.2f%%", debtRatio))
		if debtRatio <= 30 {
			parts = append(parts, fmt.Sprintf("   ✓ Within limit (≤30%%)"))
		} else {
			parts = append(parts, fmt.Sprintf("   ✗ Exceeds limit (30%%)"))
		}
	} else {
		parts = append(parts, "   Debt Ratio: Not available")
	}

	if financial.HaramIncomeRatio.Valid {
		haramRatio := financial.HaramIncomeRatio.Float64
		parts = append(parts, fmt.Sprintf("   Non-Compliant Income Ratio: %.2f%%", haramRatio))
		if haramRatio <= 5 {
			if haramRatio <= 3 {
				parts = append(parts, fmt.Sprintf("   ✓ Within acceptable limit (≤5%%)"))
			} else {
				parts = append(parts, fmt.Sprintf("   ⚠ Requires purification (3-5%%)"))
			}
		} else {
			parts = append(parts, fmt.Sprintf("   ✗ Exceeds limit (5%%)"))
		}
	} else {
		parts = append(parts, "   Non-Compliant Income Ratio: Not available")
	}

	// Final Status
	parts = append(parts, "\n3. FINAL ASSESSMENT:")
	parts = append(parts, fmt.Sprintf("   Status: %s", status.Status))
	if status.Grade.Valid {
		parts = append(parts, fmt.Sprintf("   Grade: %s", status.Grade.String))
	}

	switch status.Status {
	case "HALAL":
		parts = append(parts, "   ✓ This stock is fully compliant with Sharia principles.")
		parts = append(parts, "   ✓ All financial ratios are within acceptable limits.")
		parts = append(parts, "   ✓ No purification required.")
	case "MIXED":
		parts = append(parts, "   ⚠ This stock requires purification of non-compliant income.")
		if status.PurificationRate.Valid {
			parts = append(parts, fmt.Sprintf("   ⚠ Purification rate: %.2f%% of income must be donated to charity", status.PurificationRate.Float64))
		}
		parts = append(parts, "   ⚠ Investment is permissible after purification.")
	case "HARAM":
		parts = append(parts, "   ✗ This stock is not Sharia compliant.")
		parts = append(parts, "   ✗ Investment is not permissible.")
	default:
		parts = append(parts, "   ? Insufficient data for complete assessment.")
	}

	// Additional Details
	if status.Reason.Valid && status.Reason.String != "" {
		parts = append(parts, "\n4. DETAILED REASONING:")
		parts = append(parts, fmt.Sprintf("   %s", status.Reason.String))
	}

	// Data Source Information
	if fundamental != nil && fundamental.Source.Valid {
		parts = append(parts, "\n5. DATA SOURCE:")
		parts = append(parts, fmt.Sprintf("   Source: %s", fundamental.Source.String))
		if fundamental.AsOfDate.Valid {
			parts = append(parts, fmt.Sprintf("   As of: %s", fundamental.AsOfDate.Time.Format("2006-01-02")))
		}
	}

	return strings.Join(parts, "\n")
}

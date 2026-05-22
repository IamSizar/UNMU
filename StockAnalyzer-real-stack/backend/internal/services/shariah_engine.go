package services

import (
	"database/sql"
	"halalstocks/internal/models"
	"strings"
	"time"
)

type ShariahEngineService struct{}

func NewShariahEngineService() *ShariahEngineService {
	return &ShariahEngineService{}
}

// Result holds the screening outcome
type ScreeningResult struct {
	Status           string
	Grade            string
	DebtRatio        float64
	HaramIncomeRatio float64
	PurificationRate float64
	Explanation      string
	Reason           string
	PaysZakat        bool
}

// Non-compliant sectors (MVP list)
var prohibitedSectors = []string{
	"Banks",
	"Insurance",
	"Beverages - Brewers",
	"Beverages - Wineries & Distilleries",
	"Gambling",
	"Tobacco",
	"Aerospace & Defense", // Often included in weapons
	"Asset Management",
	"Credit Services",
}

// ScreenStock evaluates a stock based on its fundamentals and sector
func (s *ShariahEngineService) ScreenStock(stock *models.Stock, f *models.Fundamental) *models.ShariahStatus {
	// 1. Sector Screening (Qualitative)
	sector := ""
	industry := ""
	if stock.Sector.Valid {
		sector = stock.Sector.String
	}
	if stock.Industry.Valid {
		industry = stock.Industry.String
	}

	for _, prohibited := range prohibitedSectors {
		if strings.Contains(sector, prohibited) || strings.Contains(industry, prohibited) {
			return &models.ShariahStatus{
				StockID:     stock.ID,
				Status:      "NON_COMPLIANT",
				Grade:       sql.NullString{String: "F", Valid: true},
				Reason:      sql.NullString{String: "Prohibited Business Activity: " + prohibited, Valid: true},
				Explanation: sql.NullString{String: "The company operates in a non-compliant sector.", Valid: true},
				AsOfDate:    time.Now(),
				PaysZakat:   sql.NullBool{Bool: false, Valid: true},
			}
		}
	}

	// 2. Data Availability Check (MVP Step 5: Data Gaps Handling)
	// We need Market Cap, Total Debt, Total Revenue, and Interest Income to run the full screen.
	if !stock.MarketCap.Valid || f == nil || !f.TotalDebt.Valid || !f.TotalRevenue.Valid {
		return &models.ShariahStatus{
			StockID:     stock.ID,
			Status:      "UNKNOWN",
			Reason:      sql.NullString{String: "Missing Critical Data: Market Cap or Financials", Valid: true},
			Explanation: sql.NullString{String: "Insufficient data to perform Shariah screening.", Valid: true},
			AsOfDate:    time.Now(),
		}
	}

	marketCap := float64(stock.MarketCap.Int64)
	totalDebt := f.TotalDebt.Float64
	totalRevenue := f.TotalRevenue.Float64
	interestIncome := 0.0
	if f.InterestIncome.Valid {
		interestIncome = f.InterestIncome.Float64
	}

	// 3. Financial Ratio Screening (Quantitative)

	// A. Interest-Bearing Debt Ratio
	// Formula: Interest-bearing debt / Market capitalization
	// Threshold: <= 33% (0.33)
	debtRatio := 0.0
	if marketCap > 0 {
		debtRatio = totalDebt / marketCap
	}

	// B. Income Purity Check
	// Formula: Interest income / Total revenue
	// Threshold: <= 5% (0.05)
	// Note: Ideally this should include ALL non-compliant income, but for MVP we use Interest Income as proxy if detailed breakdown is missing.
	haramIncomeRatio := 0.0
	if totalRevenue > 0 {
		haramIncomeRatio = interestIncome / totalRevenue
	}

	// 4. Evaluation Logic
	status := "HALAL" // Default to compliant
	grade := "A"
	reasons := []string{}
	explanation := "Passes all Shariah screening criteria."

	// Check Debt Ratio
	if debtRatio > 0.33 {
		status = "NON_COMPLIANT"
		grade = "F"
		reasons = append(reasons, "High Debt Ratio (>33%)")
	} else if debtRatio > 0.30 {
		// Borderline handling
		if status == "HALAL" {
			grade = "C" // Downgrade grade but keep status compliant or mark as doubtful
			explanation = "Passes screening but Debt Ratio is high (borderline)."
		}
	}

	// Check Income Ratio
	if haramIncomeRatio > 0.05 {
		status = "NON_COMPLIANT"
		grade = "F"
		reasons = append(reasons, "High Impure Income (>5%)")
	}

	// Update Explanation if failed
	if status == "NON_COMPLIANT" {
		explanation = "Appears Non-Compliant based on financial ratios."
	}
	if len(reasons) > 0 {
		explanation += " Failed rules: " + strings.Join(reasons, ", ") + "."
	}

	// 5. Purification Guidance (MVP)
	// Estimated purification = Non-compliant income / Total income
	purificationRate := haramIncomeRatio

	// Zakat Status (Simplification)
	// If the company is compliant, it is generally subject to Zakat calculation rules.
	paysZakat := (status == "HALAL")

	return &models.ShariahStatus{
		StockID:          stock.ID,
		Status:           status,
		Grade:            sql.NullString{String: grade, Valid: true},
		DebtRatio:        sql.NullFloat64{Float64: debtRatio, Valid: true},
		HaramIncomeRatio: sql.NullFloat64{Float64: haramIncomeRatio, Valid: true},
		PurificationRate: sql.NullFloat64{Float64: purificationRate, Valid: true},
		PaysZakat:        sql.NullBool{Bool: paysZakat, Valid: true},
		Explanation:      sql.NullString{String: explanation, Valid: true},
		Reason:           sql.NullString{String: strings.Join(reasons, ", "), Valid: len(reasons) > 0},
		AsOfDate:         time.Now(),
	}
}

package handlers

import (
	"net/http"
	"strconv"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

type ToolsHandler struct {
	portfolioRepo *repositories.PortfolioRepository
	stockRepo     *repositories.StockRepository
	shariahRepo   *repositories.ShariahStatusRepository
	fundamentalRepo *repositories.FundamentalRepository
}

func NewToolsHandler(
	portfolioRepo *repositories.PortfolioRepository,
	stockRepo *repositories.StockRepository,
	shariahRepo *repositories.ShariahStatusRepository,
	fundamentalRepo *repositories.FundamentalRepository,
) *ToolsHandler {
	return &ToolsHandler{
		portfolioRepo:    portfolioRepo,
		stockRepo:       stockRepo,
		shariahRepo:     shariahRepo,
		fundamentalRepo: fundamentalRepo,
	}
}

// CalculateZakat handles GET /api/tools/zakat
func (h *ToolsHandler) CalculateZakat(c *gin.Context) {
	userID := c.GetInt64("user_id")
	
	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	totalZakat := 0.0
	var breakdown []gin.H

	for _, portfolio := range portfolios {
		if !portfolio.Shares.Valid || portfolio.Shares.Float64 == 0 {
			continue
		}

		// Get stock and Sharia status
		stock, _ := h.stockRepo.GetByID(portfolio.StockID)
		if stock == nil {
			continue
		}

		shariahStatus, _ := h.shariahRepo.GetLatestStatus(stock.ID)
		if shariahStatus == nil || shariahStatus.Status != "HALAL" {
			continue // Only calculate Zakat on Halal stocks
		}

		// Get current price (simplified - would need market data)
		// For now, use avg buy price
		currentPrice := 0.0
		if portfolio.AvgBuyPrice.Valid {
			currentPrice = portfolio.AvgBuyPrice.Float64
		}

		stockValue := portfolio.Shares.Float64 * currentPrice
		zakatAmount := stockValue * 0.025 // 2.5% Zakat rate

		totalZakat += zakatAmount
		breakdown = append(breakdown, gin.H{
			"stock_id":    stock.ID,
			"ticker":      stock.Ticker,
			"name":        stock.Name,
			"shares":      portfolio.Shares.Float64,
			"value":       stockValue,
			"zakat_amount": zakatAmount,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"total_zakat": totalZakat,
		"breakdown":   breakdown,
	})
}

// CalculatePurification handles GET /api/tools/purification
//
// SHARIAH-REVIEW: purification methodology needs sign-off from a Shariah advisor
// before this number is presented to users as an obligation, not a suggestion.
// Current approach (the common retail-screener convention, e.g. Zoya/Musaffa):
//   purification amount = shares_held × dividends_per_share × haram_income_ratio
// i.e. the same non-halal income ratio the screener already uses to grade the
// stock is applied to the dividend actually received, since that ratio is the
// company's own estimate of how much of its income is impure. Some scholars use
// net income mix instead of the same ratio, or require purification on capital
// gains too — those variants are NOT implemented and should be confirmed.
func (h *ToolsHandler) CalculatePurification(c *gin.Context) {
	userID := c.GetInt64("user_id")

	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	totalDividends := 0.0
	totalPurification := 0.0
	var breakdown []gin.H

	for _, portfolio := range portfolios {
		if !portfolio.Shares.Valid || portfolio.Shares.Float64 <= 0 {
			continue
		}

		stock, _ := h.stockRepo.GetByID(portfolio.StockID)
		if stock == nil {
			continue
		}

		shariahStatus, _ := h.shariahRepo.GetLatestStatus(stock.ID)
		if shariahStatus == nil {
			continue
		}
		// Only compliant/mixed stocks carry a purification obligation — a HARAM
		// holding shouldn't be held at all, and its dividend isn't "purifiable."
		if shariahStatus.Status != "HALAL" && shariahStatus.Status != "MIXED" {
			continue
		}

		fundamental, _ := h.fundamentalRepo.GetLatestFundamental(stock.ID)
		if fundamental == nil || !fundamental.DividendsPerShare.Valid || fundamental.DividendsPerShare.Float64 <= 0 {
			continue
		}

		haramRatio := 0.0
		if shariahStatus.HaramIncomeRatio.Valid {
			haramRatio = shariahStatus.HaramIncomeRatio.Float64 / 100.0
		}
		if haramRatio <= 0 {
			continue // nothing to purify
		}

		dividendReceived := portfolio.Shares.Float64 * fundamental.DividendsPerShare.Float64
		purificationAmount := dividendReceived * haramRatio

		totalDividends += dividendReceived
		totalPurification += purificationAmount

		breakdown = append(breakdown, gin.H{
			"stock_id":             stock.ID,
			"ticker":               stock.Ticker,
			"name":                 stock.Name,
			"shares":               portfolio.Shares.Float64,
			"dividend_per_share":   fundamental.DividendsPerShare.Float64,
			"dividend_received":    dividendReceived,
			"haram_income_ratio":   haramRatio,
			"purification_amount":  purificationAmount,
			"as_of_date":           fundamental.AsOfDate.Time,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"total_dividends_received": totalDividends,
		"total_purification_due":   totalPurification,
		"breakdown":                breakdown,
		"methodology": gin.H{
			"formula": "dividend_received × haram_income_ratio",
			"note":    "Purification obligations should be donated to charity without expectation of religious reward. Confirm methodology with a qualified Shariah advisor.",
			"status":  "pending_scholar_review",
		},
	})
}

// CalculateDCA handles GET /api/tools/dca
func (h *ToolsHandler) CalculateDCA(c *gin.Context) {
	monthlyAmount, _ := strconv.ParseFloat(c.Query("monthly"), 64)
	years, _ := strconv.Atoi(c.DefaultQuery("years", "10"))
	rate, _ := strconv.ParseFloat(c.DefaultQuery("rate", "0.08"), 64) // Default 8% annual return

	if monthlyAmount <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Monthly amount must be greater than 0"})
		return
	}

	if years <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Years must be greater than 0"})
		return
	}

	// DCA calculation: Future Value = P * (((1 + r)^n - 1) / r)
	// Where P = monthly payment, r = monthly rate, n = number of months
	monthlyRate := rate / 12.0
	months := years * 12
	
	totalInvested := monthlyAmount * float64(months)
	
	var futureValue float64
	if monthlyRate > 0 {
		futureValue = monthlyAmount * ((pow(1+monthlyRate, float64(months)) - 1) / monthlyRate)
	} else {
		futureValue = totalInvested
	}

	projectedGain := futureValue - totalInvested

	// Generate year-by-year breakdown
	var breakdown []gin.H
	for year := 1; year <= years; year++ {
		yearMonths := year * 12
		yearInvested := monthlyAmount * float64(yearMonths)
		
		var yearValue float64
		if monthlyRate > 0 {
			yearValue = monthlyAmount * ((pow(1+monthlyRate, float64(yearMonths)) - 1) / monthlyRate)
		} else {
			yearValue = yearInvested
		}
		
		breakdown = append(breakdown, gin.H{
			"year":         year,
			"invested":     yearInvested,
			"projected_value": yearValue,
			"gain":         yearValue - yearInvested,
		})
	}

	c.JSON(http.StatusOK, gin.H{
		"monthly_amount":  monthlyAmount,
		"years":            years,
		"annual_rate":     rate,
		"total_invested":   totalInvested,
		"projected_value":  futureValue,
		"projected_gain":   projectedGain,
		"breakdown":        breakdown,
	})
}

func pow(base, exp float64) float64 {
	if exp == 0 {
		return 1.0
	}
	if exp < 0 {
		return 1.0 / pow(base, -exp)
	}
	result := 1.0
	for i := 0; i < int(exp); i++ {
		result *= base
	}
	// Handle fractional part
	fractional := exp - float64(int(exp))
	if fractional > 0 {
		result *= 1 + fractional*(base-1)
	}
	return result
}

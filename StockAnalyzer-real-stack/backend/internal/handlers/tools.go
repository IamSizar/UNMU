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

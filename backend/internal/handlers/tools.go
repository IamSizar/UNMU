package handlers

import (
	"log"
	"math"
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
	// settingsRepo backs the nisab/gold/silver-price config below.
	// Nullable — CalculateZakat falls back to always treating nisab as
	// met (i.e. the old, pre-nisab behavior) when nil, so wiring is
	// optional and nothing breaks if it's left unset.
	settingsRepo *repositories.AppSettingsRepository
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

// SetZakatConfig wires the nisab/gold/silver price settings. Optional —
// main.go calls this post-construction.
func (h *ToolsHandler) SetZakatConfig(settingsRepo *repositories.AppSettingsRepository) {
	h.settingsRepo = settingsRepo
}

// CalculateZakat handles GET /api/tools/zakat
//
// Query params (all optional, default 0) let the caller include assets
// the app has no other record of — cash on hand, physical/digital gold
// and silver, and a catch-all "other" bucket:
//
//	?cash=1500&gold_grams=20&silver_grams=0&other_assets=0
//
// SHARIAH-REVIEW — this implements ONE common methodology, not the only
// one:
//   - Zakat is only due once total zakatable wealth meets or exceeds
//     nisab (the silver-standard threshold — see AppSettingsRepository.
//     ZakatNisabUSD's doc comment for why silver vs. gold was chosen).
//   - Zakat is calculated at a flat 2.5% of total zakatable wealth, with
//     NO hawl (lunar-year holding period) check — the app has no
//     acquisition-date tracking that would let it verify a full year has
//     passed on each asset. This calculator assumes the user is
//     evaluating wealth already held for a full year; it does not verify
//     it. That gap should be either implemented (would need per-asset
//     acquisition dates) or explicitly disclosed to the user before this
//     is treated as authoritative.
//   - Only HALAL-status stocks are counted; HARAM holdings are excluded
//     (their zakat treatment is a separate, unresolved fiqh question the
//     app does not attempt to answer).
func (h *ToolsHandler) CalculateZakat(c *gin.Context) {
	userID := c.GetInt64("user_id")

	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	cash := nonNegativeQueryFloat(c, "cash")
	goldGrams := nonNegativeQueryFloat(c, "gold_grams")
	silverGrams := nonNegativeQueryFloat(c, "silver_grams")
	otherAssets := nonNegativeQueryFloat(c, "other_assets")

	// Fallback constants match AppSettingsRepository's own defaults —
	// used only if SetZakatConfig was never called (main.go always calls
	// it; this is a landmine guard against a future refactor dropping
	// that wiring, not an expected runtime path).
	goldPricePerGram, silverPricePerGram, nisabThreshold := 75.0, 0.85, 520.0
	if h.settingsRepo != nil {
		goldPricePerGram = h.settingsRepo.ZakatGoldPricePerGramUSD()
		silverPricePerGram = h.settingsRepo.ZakatSilverPricePerGramUSD()
		nisabThreshold = h.settingsRepo.ZakatNisabUSD()
	}
	goldValue := goldGrams * goldPricePerGram
	silverValue := silverGrams * silverPricePerGram

	var stockBreakdown []gin.H
	totalStockValue := 0.0

	for _, portfolio := range portfolios {
		if !portfolio.Shares.Valid || portfolio.Shares.Float64 == 0 {
			continue
		}

		// Get stock and Sharia status
		stock, err := h.stockRepo.GetByID(portfolio.StockID)
		if err != nil {
			log.Printf("[zakat] load stock %d for user %d: %v", portfolio.StockID, userID, err)
			continue
		}
		if stock == nil {
			continue
		}

		shariahStatus, err := h.shariahRepo.GetLatestStatus(stock.ID)
		if err != nil {
			log.Printf("[zakat] load status for stock %d: %v", stock.ID, err)
			continue
		}
		if shariahStatus == nil || shariahStatus.Status != "HALAL" {
			continue // Only Zakat-eligible on Halal holdings — see doc comment above
		}

		// Get current price (simplified - would need market data)
		// For now, use avg buy price
		currentPrice := 0.0
		if portfolio.AvgBuyPrice.Valid {
			currentPrice = portfolio.AvgBuyPrice.Float64
		}

		stockValue := portfolio.Shares.Float64 * currentPrice
		totalStockValue += stockValue

		// stock_id/ticker/name/shares/value/zakat_amount is the pre-existing
		// wire shape lib/screens/tools/zakat_calculator_screen.dart already
		// parses — kept exactly as-is at the top-level `breakdown` array
		// (a plain list, not the richer object this endpoint now also
		// returns) so the current app doesn't silently show an empty
		// portfolio tab. New per-asset fields (cash/gold/silver/nisab) are
		// added alongside it rather than replacing it.
		stockBreakdown = append(stockBreakdown, gin.H{
			"stock_id": stock.ID,
			"ticker":   stock.Ticker,
			"name":     stock.Name,
			"shares":   portfolio.Shares.Float64,
			"value":    roundCents(stockValue),
		})
	}

	totalWealth := totalStockValue + cash + goldValue + silverValue + otherAssets
	nisabMet := totalWealth >= nisabThreshold
	totalZakat := 0.0
	if nisabMet {
		totalZakat = totalWealth * 0.025
	}

	// Per-stock zakat_amount, filled in after nisabMet is known (a stock's
	// individual zakat isn't meaningful in isolation — it's total wealth
	// that's compared against nisab — but the old response shape carried
	// this field per row, so it's populated as "this stock's 2.5% share,
	// given zakat is due at all" rather than dropped.
	for i, row := range stockBreakdown {
		value := row["value"].(float64)
		amount := 0.0
		if nisabMet {
			amount = value * 0.025
		}
		stockBreakdown[i]["zakat_amount"] = roundCents(amount)
	}

	c.JSON(http.StatusOK, gin.H{
		"total_zakat":     roundCents(totalZakat),
		"total_wealth":    roundCents(totalWealth),
		"nisab_threshold": roundCents(nisabThreshold),
		"nisab_met":       nisabMet,
		"breakdown":       stockBreakdown, // flat array — see comment above
		"assets": gin.H{
			"stocks_total": roundCents(totalStockValue),
			"cash":         roundCents(cash),
			"gold_value":   roundCents(goldValue),
			"silver_value": roundCents(silverValue),
			"other_assets": roundCents(otherAssets),
		},
	})
}

// nonNegativeQueryFloat parses a query param as a float, clamping garbage
// or negative input to 0. Negative wealth inputs (e.g. cash=-999999) would
// otherwise let a user reduce or zero out their own zakat calculation.
func nonNegativeQueryFloat(c *gin.Context, key string) float64 {
	v, err := strconv.ParseFloat(c.DefaultQuery(key, "0"), 64)
	if err != nil || v < 0 {
		return 0
	}
	return v
}

// roundCents rounds a money figure to 2 decimal places before it's shown
// to a user as something they may act on (donate, transfer).
func roundCents(v float64) float64 {
	return math.Round(v*100) / 100
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

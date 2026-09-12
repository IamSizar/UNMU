package handlers

import (
	"log"
	"math"
	"net/http"
	"strconv"
	"halalstocks/internal/models"
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

// eligibleHolding pairs a portfolio row with its resolved stock + Shariah
// status, once both are known to exist.
type eligibleHolding struct {
	Portfolio *models.UserPortfolio
	Stock     *models.Stock
	Status    *models.ShariahStatus
}

// loadEligibleHoldings batch-loads stocks + Shariah statuses for a user's
// entire portfolio in 2 queries (not 2-per-row), then filters to rows with
// shares > 0 whose status passes accept. Shared by CalculateZakat and
// CalculatePurification, which previously duplicated this exact loop with
// a per-row stockRepo.GetByID + shariahRepo.GetLatestStatus call each —
// an N+1 pattern that meant ~2N DB round-trips per request for an N-stock
// portfolio.
func (h *ToolsHandler) loadEligibleHoldings(
	userID int64,
	accept func(status *models.ShariahStatus) bool,
) ([]eligibleHolding, error) {
	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		return nil, err
	}

	stockIDs := make([]int64, 0, len(portfolios))
	for _, p := range portfolios {
		if p.Shares.Valid && p.Shares.Float64 > 0 {
			stockIDs = append(stockIDs, p.StockID)
		}
	}

	var stocksByID map[int64]*models.Stock
	var statusByID map[int64]*models.ShariahStatus
	if len(stockIDs) > 0 {
		stocksByID, err = h.stockRepo.GetByIDs(stockIDs)
		if err != nil {
			log.Printf("[tools] batch-load stocks for user %d: %v", userID, err)
			stocksByID = map[int64]*models.Stock{}
		}
		statusByID, err = h.shariahRepo.GetLatestStatusBatch(stockIDs)
		if err != nil {
			log.Printf("[tools] batch-load statuses for user %d: %v", userID, err)
			statusByID = map[int64]*models.ShariahStatus{}
		}
	}

	holdings := make([]eligibleHolding, 0, len(stockIDs))
	for _, p := range portfolios {
		if !p.Shares.Valid || p.Shares.Float64 <= 0 {
			continue
		}
		stock := stocksByID[p.StockID]
		if stock == nil {
			continue
		}
		status := statusByID[p.StockID]
		if !accept(status) {
			continue
		}
		holdings = append(holdings, eligibleHolding{Portfolio: p, Stock: stock, Status: status})
	}
	return holdings, nil
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

	holdings, err := h.loadEligibleHoldings(userID, func(s *models.ShariahStatus) bool {
		return s != nil && s.Status == "HALAL" // Only Zakat-eligible on Halal holdings — see doc comment above
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	cash := nonNegativeQueryFloat(c, "cash")
	goldGrams := nonNegativeQueryFloat(c, "gold_grams")
	silverGrams := nonNegativeQueryFloat(c, "silver_grams")
	otherAssets := nonNegativeQueryFloat(c, "other_assets")
	goldPricePerGram, silverPricePerGram, nisabThreshold := h.zakatPricing()
	goldValue := goldGrams * goldPricePerGram
	silverValue := silverGrams * silverPricePerGram

	stockBreakdown, totalStockValue := buildZakatStockBreakdown(holdings)
	totalWealth := totalStockValue + cash + goldValue + silverValue + otherAssets
	nisabMet := totalWealth >= nisabThreshold
	totalZakat := 0.0
	if nisabMet {
		totalZakat = totalWealth * 0.025
	}

	// zakat_amount per row, filled in now that nisabMet is known. To keep
	// sum(breakdown[].zakat_amount) == total_zakat exactly (previously it
	// didn't: total_zakat counted cash/gold/silver/other too, while every
	// breakdown row only ever covered its own stock's share), a synthetic
	// row folds in the non-stock assets' zakat under one line item.
	nonStockValue := cash + goldValue + silverValue + otherAssets
	stockBreakdown = finalizeZakatBreakdown(stockBreakdown, nonStockValue, nisabMet)

	c.JSON(http.StatusOK, gin.H{
		"total_zakat":     roundCents(totalZakat),
		"total_wealth":    roundCents(totalWealth),
		"nisab_threshold": roundCents(nisabThreshold),
		"nisab_met":       nisabMet,
		"breakdown":       stockBreakdown, // flat array — see buildZakatStockBreakdown
		"assets": gin.H{
			"stocks_total": roundCents(totalStockValue),
			"cash":         roundCents(cash),
			"gold_value":   roundCents(goldValue),
			"silver_value": roundCents(silverValue),
			"other_assets": roundCents(otherAssets),
		},
	})
}

// zakatPricing returns (goldPricePerGram, silverPricePerGram, nisabThreshold),
// falling back to AppSettingsRepository's own defaults if SetZakatConfig was
// never called (main.go always calls it; this is a landmine guard against a
// future refactor dropping that wiring, not an expected runtime path).
func (h *ToolsHandler) zakatPricing() (goldPricePerGram, silverPricePerGram, nisabThreshold float64) {
	goldPricePerGram, silverPricePerGram, nisabThreshold = 75.0, 0.85, 520.0
	if h.settingsRepo != nil {
		goldPricePerGram = h.settingsRepo.ZakatGoldPricePerGramUSD()
		silverPricePerGram = h.settingsRepo.ZakatSilverPricePerGramUSD()
		nisabThreshold = h.settingsRepo.ZakatNisabUSD()
	}
	return
}

// buildZakatStockBreakdown builds the pre-existing wire shape
// lib/screens/tools/zakat_calculator_screen.dart already parses — a flat
// array of {stock_id, ticker, name, shares, value}, zakat_amount filled in
// later by finalizeZakatBreakdown once nisabMet is known.
func buildZakatStockBreakdown(holdings []eligibleHolding) (rows []gin.H, totalStockValue float64) {
	for _, h := range holdings {
		currentPrice := 0.0
		if h.Portfolio.AvgBuyPrice.Valid {
			currentPrice = h.Portfolio.AvgBuyPrice.Float64
		}
		stockValue := h.Portfolio.Shares.Float64 * currentPrice
		totalStockValue += stockValue

		rows = append(rows, gin.H{
			"stock_id": h.Stock.ID,
			"ticker":   h.Stock.Ticker,
			"name":     h.Stock.Name,
			"shares":   h.Portfolio.Shares.Float64,
			"value":    roundCents(stockValue),
		})
	}
	return rows, totalStockValue
}

// finalizeZakatBreakdown fills in each row's zakat_amount (2.5% of that
// row's value once zakat is due at all) and appends a synthetic row for
// non-stock assets, so summing every row's zakat_amount reproduces
// total_zakat exactly.
func finalizeZakatBreakdown(rows []gin.H, nonStockValue float64, nisabMet bool) []gin.H {
	pct := func(v float64) float64 {
		if !nisabMet {
			return 0
		}
		return roundCents(v * 0.025)
	}
	for i, row := range rows {
		value, _ := row["value"].(float64)
		rows[i]["zakat_amount"] = pct(value)
	}
	if nonStockValue > 0 {
		rows = append(rows, gin.H{
			"stock_id":     nil,
			"ticker":       "OTHER",
			"name":         "Cash, gold, silver & other assets",
			"value":        roundCents(nonStockValue),
			"zakat_amount": pct(nonStockValue),
		})
	}
	return rows
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

	// Only compliant/mixed stocks carry a purification obligation — a HARAM
	// holding shouldn't be held at all, and its dividend isn't "purifiable."
	holdings, err := h.loadEligibleHoldings(userID, func(s *models.ShariahStatus) bool {
		return s != nil && (s.Status == "HALAL" || s.Status == "MIXED")
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	totalDividends := 0.0
	totalPurification := 0.0
	var breakdown []gin.H

	for _, holding := range holdings {
		portfolio, stock, shariahStatus := holding.Portfolio, holding.Stock, holding.Status

		// Fundamentals (dividend-per-share) have no batch-lookup method yet,
		// unlike stocks/statuses above — a smaller, pre-existing N+1 left
		// as-is since it wasn't part of what this pass fixed.
		fundamental, err := h.fundamentalRepo.GetLatestFundamental(stock.ID)
		if err != nil {
			log.Printf("[purification] load fundamental for stock %d: %v", stock.ID, err)
			continue
		}
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

		row := gin.H{
			"stock_id":            stock.ID,
			"ticker":              stock.Ticker,
			"name":                stock.Name,
			"shares":              portfolio.Shares.Float64,
			"dividend_per_share":  fundamental.DividendsPerShare.Float64,
			"dividend_received":   roundCents(dividendReceived),
			"haram_income_ratio":  haramRatio,
			"purification_amount": roundCents(purificationAmount),
		}
		if fundamental.AsOfDate.Valid {
			row["as_of_date"] = fundamental.AsOfDate.Time
		}
		breakdown = append(breakdown, row)
	}

	c.JSON(http.StatusOK, gin.H{
		"total_dividends_received": roundCents(totalDividends),
		"total_purification_due":   roundCents(totalPurification),
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

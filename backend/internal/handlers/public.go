package handlers

import (
	"database/sql"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
)

type PublicHandler struct {
	stockRepo       *repositories.StockRepository
	fundamentalRepo *repositories.FundamentalRepository
	shariahRepo     *repositories.ShariahStatusRepository
	analystRepo     *repositories.AnalystRatingRepository
	shariahEngine   *services.ShariahEngineService
}

func NewPublicHandler(
	stockRepo *repositories.StockRepository,
	fundamentalRepo *repositories.FundamentalRepository,
	shariahRepo *repositories.ShariahStatusRepository,
	analystRepo *repositories.AnalystRatingRepository,
	shariahEngine *services.ShariahEngineService,
) *PublicHandler {
	return &PublicHandler{
		stockRepo:       stockRepo,
		fundamentalRepo: fundamentalRepo,
		shariahRepo:     shariahRepo,
		analystRepo:     analystRepo,
		shariahEngine:   shariahEngine,
	}
}

// SearchStocks handles GET /api/search?q={query}
func (h *PublicHandler) SearchStocks(c *gin.Context) {
	query := c.Query("q")
	if query == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Query parameter 'q' is required"})
		return
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit > 100 {
		limit = 100
	}

	stocks, err := h.stockRepo.Search(query, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to search stocks"})
		return
	}

	// Use batch loading to fetch all Sharia statuses in one query
	stockIDs := make([]int64, len(stocks))
	for i, stock := range stocks {
		stockIDs[i] = stock.ID
	}
	statusMap, _ := h.shariahRepo.GetLatestStatusBatch(stockIDs)

	// Build response using the pre-fetched status map
	var results []gin.H
	for _, stock := range stocks {
		stockData := gin.H{
			"id":       stock.ID,
			"ticker":   stock.Ticker,
			"exchange": stock.Exchange,
			"name":     stock.Name,
		}

		if stock.Country.Valid {
			stockData["country"] = stock.Country.String
		}
		if stock.RegionCode.Valid {
			stockData["region_code"] = stock.RegionCode.String
		}
		if stock.Sector.Valid {
			stockData["sector"] = stock.Sector.String
		}
		if stock.Industry.Valid {
			stockData["industry"] = stock.Industry.String
		}

		// Get Sharia status from the pre-fetched map
		if shariahStatus, exists := statusMap[stock.ID]; exists && shariahStatus != nil {
			stockData["shariah_status"] = gin.H{
				"status":             shariahStatus.Status,
				"grade":              getStringValue(shariahStatus.Grade),
				"debt_ratio":         getFloatValue(shariahStatus.DebtRatio),
				"haram_income_ratio": getFloatValue(shariahStatus.HaramIncomeRatio),
				"purification_rate":  getFloatValue(shariahStatus.PurificationRate),
				"pays_zakat":         getBoolValue(shariahStatus.PaysZakat),
				"explanation":        getStringValue(shariahStatus.Explanation),
				"reason":             getStringValue(shariahStatus.Reason),
			}
		}

		results = append(results, stockData)
	}

	c.JSON(http.StatusOK, gin.H{"stocks": results})
}

// GetStockDetails handles GET /api/stocks/:ticker
func (h *PublicHandler) GetStockDetails(c *gin.Context) {
	ticker := c.Param("ticker")
	exchange := c.DefaultQuery("exchange", "")

	if exchange == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Exchange parameter is required"})
		return
	}

	stock, err := h.stockRepo.GetByTickerAndExchange(ticker, exchange)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get stock"})
		return
	}
	if stock == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Stock not found"})
		return
	}

	// Get fundamentals
	fundamental, _ := h.fundamentalRepo.GetLatestFundamental(stock.ID)

	// Get Sharia status
	shariahStatus, _ := h.shariahRepo.GetLatestStatus(stock.ID)

	// On-Demand Screening: If status is missing or old (optional check), run screening engine
	if shariahStatus == nil {
		if fundamental != nil {
			// Calculate status
			newStatus := h.shariahEngine.ScreenStock(stock, fundamental)

			// Save to DB
			if err := h.shariahRepo.CreateOrUpdate(newStatus); err == nil {
				shariahStatus = newStatus
			}
		}
	}

	// Get analyst ratings
	ratings, _ := h.analystRepo.GetByStockID(stock.ID)

	response := gin.H{
		"stock": buildStockResponse(stock),
	}

	if fundamental != nil {
		response["fundamentals"] = buildFundamentalResponse(fundamental)
	}

	if shariahStatus != nil {
		response["shariah_status"] = buildShariahResponse(shariahStatus)
	}

	if len(ratings) > 0 {
		response["analyst_ratings"] = buildAnalystRatingsResponse(ratings)
	}

	c.JSON(http.StatusOK, response)
}

// GetStocksByRegion handles GET /api/regions/:code/stocks
func (h *PublicHandler) GetStocksByRegion(c *gin.Context) {
	regionCode := c.Param("code")

	// Handle "GLOBAL" as a special case - return all stocks
	if regionCode == "GLOBAL" {
		regionCode = ""
	}

	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	if limit > 100 {
		limit = 100
	}
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	var stocks []*models.Stock
	var statusMap map[int64]*models.ShariahStatus
	var err error

	// Use optimized method that fetches stocks with Sharia status in one query
	if regionCode == "" {
		// For GLOBAL, get all stocks with statuses
		stocks, statusMap, err = h.stockRepo.GetAllWithShariahStatus(limit, offset)
	} else {
		stocks, statusMap, err = h.stockRepo.GetByRegionWithShariahStatus(regionCode, limit, offset)
	}

	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get stocks"})
		return
	}

	// Build response using the pre-fetched status map
	var results []gin.H
	for _, stock := range stocks {
		stockData := gin.H{
			"id":       stock.ID,
			"ticker":   stock.Ticker,
			"exchange": stock.Exchange,
			"name":     stock.Name,
		}

		if stock.Country.Valid {
			stockData["country"] = stock.Country.String
		}
		if stock.RegionCode.Valid {
			stockData["region_code"] = stock.RegionCode.String
		}
		if stock.Sector.Valid {
			stockData["sector"] = stock.Sector.String
		}
		if stock.Industry.Valid {
			stockData["industry"] = stock.Industry.String
		}

		// Get Sharia status from the pre-fetched map
		if shariahStatus, exists := statusMap[stock.ID]; exists && shariahStatus != nil {
			stockData["shariah_status"] = gin.H{
				"status":             shariahStatus.Status,
				"grade":              getStringValue(shariahStatus.Grade),
				"debt_ratio":         getFloatValue(shariahStatus.DebtRatio),
				"haram_income_ratio": getFloatValue(shariahStatus.HaramIncomeRatio),
				"purification_rate":  getFloatValue(shariahStatus.PurificationRate),
				"pays_zakat":         getBoolValue(shariahStatus.PaysZakat),
				"explanation":        getStringValue(shariahStatus.Explanation),
				"reason":             getStringValue(shariahStatus.Reason),
			}
		}

		results = append(results, stockData)
	}

	c.JSON(http.StatusOK, gin.H{"stocks": results})
}

// Helper functions
func buildStockResponse(stock *models.Stock) gin.H {
	data := gin.H{
		"id":       stock.ID,
		"ticker":   stock.Ticker,
		"exchange": stock.Exchange,
		"name":     stock.Name,
	}
	if stock.Country.Valid {
		data["country"] = stock.Country.String
	}
	if stock.RegionCode.Valid {
		data["region_code"] = stock.RegionCode.String
	}
	if stock.Sector.Valid {
		data["sector"] = stock.Sector.String
	}
	if stock.Industry.Valid {
		data["industry"] = stock.Industry.String
	}
	if stock.Description.Valid {
		data["description"] = stock.Description.String
	}
	if stock.MarketCap.Valid {
		data["market_cap"] = stock.MarketCap.Int64
	}
	return data
}

func buildFundamentalResponse(f *models.Fundamental) gin.H {
	data := gin.H{}
	if f.TotalAssets.Valid {
		data["total_assets"] = f.TotalAssets.Float64
	}
	if f.TotalDebt.Valid {
		data["total_debt"] = f.TotalDebt.Float64
	}
	if f.CashAndEquiv.Valid {
		data["cash_and_equiv"] = f.CashAndEquiv.Float64
	}
	if f.TotalRevenue.Valid {
		data["total_revenue"] = f.TotalRevenue.Float64
	}
	if f.InterestIncome.Valid {
		data["interest_income"] = f.InterestIncome.Float64
	}
	if f.InterestExpense.Valid {
		data["interest_expense"] = f.InterestExpense.Float64
	}
	if f.NetIncome.Valid {
		data["net_income"] = f.NetIncome.Float64
	}
	if f.DividendsPerShare.Valid {
		data["dividends_per_share"] = f.DividendsPerShare.Float64
	}
	if f.AsOfDate.Valid {
		data["as_of_date"] = f.AsOfDate.Time.Format("2006-01-02")
	}
	return data
}

func buildShariahResponse(s *models.ShariahStatus) gin.H {
	data := gin.H{
		"status": s.Status,
	}
	if s.Grade.Valid {
		data["grade"] = s.Grade.String
	}
	if s.DebtRatio.Valid {
		data["debt_ratio"] = s.DebtRatio.Float64
	}
	if s.HaramIncomeRatio.Valid {
		data["haram_income_ratio"] = s.HaramIncomeRatio.Float64
	}
	if s.PurificationRate.Valid {
		data["purification_rate"] = s.PurificationRate.Float64
	}
	if s.PaysZakat.Valid {
		data["pays_zakat"] = s.PaysZakat.Bool
	}
	if s.Explanation.Valid {
		data["explanation"] = s.Explanation.String
	}
	if s.Reason.Valid {
		data["reason"] = s.Reason.String
	}
	if !s.AsOfDate.IsZero() {
		data["as_of_date"] = s.AsOfDate.Format("2006-01-02")
	}
	return data
}

func buildAnalystRatingsResponse(ratings []*models.AnalystRating) []gin.H {
	var results []gin.H
	for _, r := range ratings {
		data := gin.H{}
		if r.AnalystName.Valid {
			data["analyst_name"] = r.AnalystName.String
		}
		if r.Rating.Valid {
			data["rating"] = r.Rating.String
		}
		if r.TargetPrice.Valid {
			data["target_price"] = r.TargetPrice.Float64
		}
		if r.RatingDate.Valid {
			data["rating_date"] = r.RatingDate.Time.Format("2006-01-02")
		}
		if r.Source.Valid {
			data["source"] = r.Source.String
		}
		results = append(results, data)
	}
	return results
}

func getStringValue(ns sql.NullString) string {
	if ns.Valid {
		return ns.String
	}
	return ""
}

func getFloatValue(nf sql.NullFloat64) *float64 {
	if nf.Valid {
		return &nf.Float64
	}
	return nil
}

func getBoolValue(nb sql.NullBool) *bool {
	if nb.Valid {
		return &nb.Bool
	}
	return nil
}

package handlers

import (
	"database/sql"
	"net/http"
	"strconv"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

type UserHandler struct {
	portfolioRepo *repositories.PortfolioRepository
	notificationRepo *repositories.NotificationRepository
	// stockRepo/shariahRepo enrich GetPortfolio's response with ticker/
	// name/compliance status. Nullable so existing tests/wiring that don't
	// pass them still compile — GetPortfolio falls back to the bare
	// stock_id/shares/avg_buy_price shape when either is nil.
	stockRepo   *repositories.StockRepository
	shariahRepo *repositories.ShariahStatusRepository
}

func NewUserHandler(
	portfolioRepo *repositories.PortfolioRepository,
	notificationRepo *repositories.NotificationRepository,
) *UserHandler {
	return &UserHandler{
		portfolioRepo:    portfolioRepo,
		notificationRepo: notificationRepo,
	}
}

// SetPortfolioEnrichment wires the stock + Shariah-status repos used to
// enrich GetPortfolio's response. Optional — main.go calls this post-
// construction; without it, GetPortfolio returns the bare portfolio rows.
func (h *UserHandler) SetPortfolioEnrichment(stockRepo *repositories.StockRepository, shariahRepo *repositories.ShariahStatusRepository) {
	h.stockRepo = stockRepo
	h.shariahRepo = shariahRepo
}

// GetPortfolio handles GET /api/user/portfolio
//
// The response nests a `stock` object (id/ticker/exchange/name/
// shariah_status) alongside the top-level stock_id/shares/avg_buy_price —
// this is NOT a new shape invented for the Portfolio screen, it's the
// shape lib/screens/watchlist/watchlist_screen.dart has always expected
// (it reads item['stock']['ticker'], item['stock']['exchange'],
// item['stock']['shariah_status']['grade'], and falls back to a bare
// "Stock ID: N" placeholder card when `stock` is null — see that file's
// _WatchlistCard). Before this change, GetPortfolio returned bare
// models.UserPortfolio structs with no `stock` key at all, so watchlist
// was ALWAYS rendering the placeholder fallback in production, silently:
// grade filters, the halal/mixed summary counts, and tapping a row to
// open stock detail were all no-ops. This fixes that pre-existing bug as
// a side effect of building the shape the Portfolio screen also needs.
func (h *UserHandler) GetPortfolio(c *gin.Context) {
	userID := c.GetInt64("user_id")

	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	// Batch-load stocks + statuses (2 queries total) instead of the
	// previous 2-queries-per-row N+1 — a 50-holding portfolio otherwise
	// meant ~100 sequential round-trips on every screen open.
	var stocksByID map[int64]*models.Stock
	var statusByID map[int64]*models.ShariahStatus
	if h.stockRepo != nil {
		stockIDs := make([]int64, len(portfolios))
		for i, p := range portfolios {
			stockIDs[i] = p.StockID
		}
		stocksByID, _ = h.stockRepo.GetByIDs(stockIDs)
		if h.shariahRepo != nil {
			statusByID, _ = h.shariahRepo.GetLatestStatusBatch(stockIDs)
		}
	}

	entries := make([]gin.H, 0, len(portfolios))
	for _, p := range portfolios {
		entry := gin.H{"stock_id": p.StockID}
		if p.Shares.Valid {
			entry["shares"] = p.Shares.Float64
		}
		if p.AvgBuyPrice.Valid {
			entry["avg_buy_price"] = p.AvgBuyPrice.Float64
		}

		if stock := stocksByID[p.StockID]; stock != nil {
			stockJSON := gin.H{
				"id":       stock.ID,
				"ticker":   stock.Ticker,
				"exchange": stock.Exchange,
				"name":     stock.Name,
			}
			if status := statusByID[p.StockID]; status != nil {
				stockJSON["shariah_status"] = buildShariahResponse(status)
			}
			entry["stock"] = stockJSON
		}

		entries = append(entries, entry)
	}

	c.JSON(http.StatusOK, gin.H{"portfolio": entries})
}

// AddToPortfolio handles POST /api/user/portfolio
func (h *UserHandler) AddToPortfolio(c *gin.Context) {
	userID := c.GetInt64("user_id")
	
	var req struct {
		StockID     int64   `json:"stock_id" binding:"required"`
		Shares      float64 `json:"shares"`
		AvgBuyPrice float64 `json:"avg_buy_price"`
	}
	
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	portfolio := &models.UserPortfolio{
		UserID:      userID,
		StockID:     req.StockID,
		Shares:      sql.NullFloat64{Float64: req.Shares, Valid: req.Shares > 0},
		AvgBuyPrice: sql.NullFloat64{Float64: req.AvgBuyPrice, Valid: req.AvgBuyPrice > 0},
	}

	if err := h.portfolioRepo.AddToPortfolio(portfolio); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to add to portfolio"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Added to portfolio", "portfolio": portfolio})
}

// RemoveFromPortfolio handles DELETE /api/user/portfolio/:stock_id
func (h *UserHandler) RemoveFromPortfolio(c *gin.Context) {
	userID := c.GetInt64("user_id")
	stockID, _ := strconv.ParseInt(c.Param("stock_id"), 10, 64)

	if err := h.portfolioRepo.RemoveFromPortfolio(userID, stockID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to remove from portfolio"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Removed from portfolio"})
}

// GetNotifications handles GET /api/user/notifications
func (h *UserHandler) GetNotifications(c *gin.Context) {
	userID := c.GetInt64("user_id")
	
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	offset, _ := strconv.Atoi(c.DefaultQuery("offset", "0"))

	notifications, err := h.notificationRepo.GetUserNotifications(userID, limit, offset)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get notifications"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"notifications": notifications})
}

// MarkNotificationRead handles PUT /api/user/notifications/:id/read
func (h *UserHandler) MarkNotificationRead(c *gin.Context) {
	notificationID, _ := strconv.ParseInt(c.Param("id"), 10, 64)

	if err := h.notificationRepo.MarkAsRead(notificationID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to mark notification as read"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"message": "Notification marked as read"})
}

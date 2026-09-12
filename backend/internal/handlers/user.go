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

// portfolioEntryResponse is what the Flutter portfolio screen actually
// needs to render a row — the bare UserPortfolio model only carries IDs.
type portfolioEntryResponse struct {
	StockID       int64   `json:"stockId"`
	Ticker        string  `json:"ticker"`
	Name          string  `json:"name"`
	Shares        float64 `json:"shares"`
	AvgBuyPrice   float64 `json:"avgBuyPrice"`
	ShariahStatus string  `json:"shariahStatus"`
	ShariahGrade  string  `json:"shariahGrade,omitempty"`
}

// GetPortfolio handles GET /api/user/portfolio
func (h *UserHandler) GetPortfolio(c *gin.Context) {
	userID := c.GetInt64("user_id")

	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	if h.stockRepo == nil || h.shariahRepo == nil {
		c.JSON(http.StatusOK, gin.H{"portfolio": portfolios})
		return
	}

	entries := make([]portfolioEntryResponse, 0, len(portfolios))
	for _, p := range portfolios {
		entry := portfolioEntryResponse{StockID: p.StockID, ShariahStatus: "UNKNOWN"}
		if p.Shares.Valid {
			entry.Shares = p.Shares.Float64
		}
		if p.AvgBuyPrice.Valid {
			entry.AvgBuyPrice = p.AvgBuyPrice.Float64
		}

		if stock, err := h.stockRepo.GetByID(p.StockID); err == nil && stock != nil {
			entry.Ticker = stock.Ticker
			entry.Name = stock.Name
		}
		if status, err := h.shariahRepo.GetLatestStatus(p.StockID); err == nil && status != nil {
			entry.ShariahStatus = status.Status
			if status.Grade.Valid {
				entry.ShariahGrade = status.Grade.String
			}
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

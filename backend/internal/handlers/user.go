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

// GetPortfolio handles GET /api/user/portfolio
func (h *UserHandler) GetPortfolio(c *gin.Context) {
	userID := c.GetInt64("user_id")
	
	portfolios, err := h.portfolioRepo.GetUserPortfolio(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to get portfolio"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"portfolio": portfolios})
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

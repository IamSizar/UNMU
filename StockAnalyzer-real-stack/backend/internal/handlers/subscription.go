package handlers

import (
	"halalstocks/internal/repositories"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

type SubscriptionHandler struct {
	userRepo *repositories.UserRepository
}

func NewSubscriptionHandler(userRepo *repositories.UserRepository) *SubscriptionHandler {
	return &SubscriptionHandler{userRepo: userRepo}
}

type UpgradeRequest struct {
	Tier string `json:"tier" binding:"required,oneof=FREE PREMIUM"`
}

func (h *SubscriptionHandler) Upgrade(c *gin.Context) {
	userID := c.MustGet("userID").(int64)

	var req UpgradeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// In a real app, verify payment here
	// For demo, we just upgrade immediately

	var endDate *time.Time
	if req.Tier == "PREMIUM" {
		// Set to 1 year from now for example
		inOneYear := time.Now().AddDate(1, 0, 0)
		endDate = &inOneYear
	}

	if err := h.userRepo.UpdateSubscription(userID, req.Tier, "ACTIVE", endDate); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update subscription"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Subscription updated successfully",
		"tier":    req.Tier,
	})
}

func (h *SubscriptionHandler) Cancel(c *gin.Context) {
	userID := c.MustGet("userID").(int64)

	// Downgrade to FREE
	if err := h.userRepo.UpdateSubscription(userID, "FREE", "CANCELED", nil); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to cancel subscription"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"message": "Subscription canceled successfully",
	})
}

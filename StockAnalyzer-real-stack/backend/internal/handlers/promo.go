package handlers

import (
	"net/http"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

type PromoHandler struct {
	promoRepo *repositories.PromoCodeRepository
}

func NewPromoHandler(promoRepo *repositories.PromoCodeRepository) *PromoHandler {
	return &PromoHandler{promoRepo: promoRepo}
}

type ValidatePromoRequest struct {
	Code string `json:"code" binding:"required"`
}

type ValidatePromoResponse struct {
	Valid         bool    `json:"valid"`
	DiscountType  string  `json:"discount_type,omitempty"`
	DiscountValue float64 `json:"discount_value,omitempty"`
	Message       string  `json:"message,omitempty"`
}

// ValidatePromo handles POST /api/promo/validate
func (h *PromoHandler) ValidatePromo(c *gin.Context) {
	var req ValidatePromoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetInt64("user_id")
	
	promo, err := h.promoRepo.GetByCode(req.Code)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate promo code"})
		return
	}

	if promo == nil || !promo.IsActive {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "Invalid or inactive promo code",
		})
		return
	}

	// Check if user has already used this code
	used, err := h.promoRepo.HasUserUsedCode(userID, promo.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check promo usage"})
		return
	}

	if used {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "You have already used this promo code",
		})
		return
	}

	// Check max uses
	if promo.MaxUses.Valid && promo.UsedCount >= promo.MaxUses.Int64 {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "Promo code has reached maximum uses",
		})
		return
	}

	c.JSON(http.StatusOK, ValidatePromoResponse{
		Valid:         true,
		DiscountType:  promo.DiscountType,
		DiscountValue: promo.DiscountValue,
		Message:       "Promo code is valid",
	})
}


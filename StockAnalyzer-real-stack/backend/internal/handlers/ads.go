package handlers

import (
	"net/http"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

type AdsHandler struct {
	adRepo *repositories.AdRepository
}

func NewAdsHandler(adRepo *repositories.AdRepository) *AdsHandler {
	return &AdsHandler{adRepo: adRepo}
}

// GetAds handles GET /api/ads?region_code={code}
func (h *AdsHandler) GetAds(c *gin.Context) {
	regionCode := c.DefaultQuery("region_code", "GLOBAL")

	ads, err := h.adRepo.GetActiveAdsByRegion(regionCode)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch ads"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"ads": ads})
}

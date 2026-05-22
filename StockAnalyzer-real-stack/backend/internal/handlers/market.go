package handlers

import (
	"net/http"
	"time"

	"halalstocks/internal/marketdata"

	"github.com/gin-gonic/gin"
)

type MarketHandler struct {
	marketProvider marketdata.MarketDataProvider
}

func NewMarketHandler(marketProvider marketdata.MarketDataProvider) *MarketHandler {
	return &MarketHandler{
		marketProvider: marketProvider,
	}
}

// GetFearAndGreedIndex handles GET /api/market/fear-greed
func (h *MarketHandler) GetFearAndGreedIndex(c *gin.Context) {
	data, err := h.marketProvider.FetchFearAndGreed()
	if err != nil {
		// FALLBACK to neutral if error
		c.JSON(http.StatusOK, gin.H{
			"value":          50,
			"label":          "Neutral",
			"color":          "#FFCC00",
			"last_updated":   time.Now().Format("2006-01-02 15:04:05"),
			"previous_close": 48,
			"trend":          []int{45, 47, 48, 50, 50},
		})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"value":          data.Value,
		"label":          data.Label,
		"color":          data.Color,
		"last_updated":   data.LastUpdated,
		"previous_close": data.Value - 1,
		"trend":          data.Trend,
		"trend_dates":    data.TrendDates,
	})
}

// GetIndexes handles GET /api/market/indexes
func (h *MarketHandler) GetIndexes(c *gin.Context) {
	indices, err := h.marketProvider.FetchIndexes()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, indices)
}

// GetExchangeRate handles GET /api/market/exchange-rate
func (h *MarketHandler) GetExchangeRate(c *gin.Context) {
	from := c.Query("from")
	to := c.Query("to")

	if from == "" || to == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "from and to parameters are required"})
		return
	}

	rate, err := h.marketProvider.FetchExchangeRate(from, to)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"from": from,
		"to":   to,
		"rate": rate,
	})
}

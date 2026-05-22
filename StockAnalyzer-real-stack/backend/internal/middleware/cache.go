package middleware

import (
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
)

// CacheMiddleware adds cache headers to responses
func CacheMiddleware(duration time.Duration) gin.HandlerFunc {
	return func(c *gin.Context) {
		// Only cache GET requests
		if c.Request.Method == http.MethodGet {
			maxAge := int(duration.Seconds())
			c.Header("Cache-Control", fmt.Sprintf("public, max-age=%d", maxAge))
			c.Header("Expires", time.Now().Add(duration).Format(http.TimeFormat))
		}
		c.Next()
	}
}


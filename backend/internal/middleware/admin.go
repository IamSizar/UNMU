package middleware

import (
	"halalstocks/internal/repositories"
	"net/http"

	"github.com/gin-gonic/gin"
)

// RequireAdmin must be chained AFTER AuthMiddleware. It looks up the
// authenticated user's role in the database and aborts unless the role is
// 'ADMIN'. We hit the DB instead of trusting the JWT because the existing
// JWT only carries user_id + email — the role can change after a token was
// issued (e.g. when an application is approved).
func RequireAdmin(users *repositories.UserRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		v, exists := c.Get("user_id")
		if !exists {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			c.Abort()
			return
		}
		userID, ok := v.(int64)
		if !ok {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
			c.Abort()
			return
		}

		user, err := users.GetByID(userID)
		if err != nil || user == nil {
			c.JSON(http.StatusUnauthorized, gin.H{"error": "user not found"})
			c.Abort()
			return
		}
		if user.Role != "ADMIN" {
			c.JSON(http.StatusForbidden, gin.H{"error": "admin only"})
			c.Abort()
			return
		}

		c.Set("user_role", user.Role)
		c.Next()
	}
}

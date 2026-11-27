package middleware

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// CORS lets browsers call the API only from the allowed origins (the admin
// dashboard). Mobile apps send no Origin header and are unaffected. With
// allowAny (dev only) every origin is echoed back.
//
// No Allow-Credentials header is sent: the API uses bearer tokens, never
// cookies, so browsers never need to attach credentials.
func CORS(allowed []string, allowAny bool) gin.HandlerFunc {
	return func(c *gin.Context) {
		origin := c.GetHeader("Origin")
		c.Writer.Header().Add("Vary", "Origin")
		ok := origin != "" && OriginAllowed(origin, allowed, allowAny)
		if ok {
			h := c.Writer.Header()
			h.Set("Access-Control-Allow-Origin", origin)
			h.Set("Access-Control-Allow-Headers", "Content-Type, Content-Length, Accept-Encoding, X-CSRF-Token, Authorization, accept, origin, Cache-Control, X-Requested-With")
			h.Set("Access-Control-Allow-Methods", "POST, OPTIONS, GET, PUT, PATCH, DELETE")
		}
		if c.Request.Method == http.MethodOptions {
			if ok {
				c.AbortWithStatus(http.StatusNoContent)
			} else {
				c.AbortWithStatus(http.StatusForbidden)
			}
			return
		}
		c.Next()
	}
}

// OriginAllowed is the shared origin check for REST (CORS) and the
// WebSocket handshake. An empty origin (native app, server-to-server) is
// allowed: CORS only protects browsers.
func OriginAllowed(origin string, allowed []string, allowAny bool) bool {
	if origin == "" || allowAny {
		return true
	}
	for _, a := range allowed {
		if a == origin {
			return true
		}
	}
	return false
}

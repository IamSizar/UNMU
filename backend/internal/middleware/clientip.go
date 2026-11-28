package middleware

import (
	"fmt"

	"github.com/gin-gonic/gin"
)

// ConfigureClientIP decides where c.ClientIP() — and so the auth rate
// limiter — gets the caller's address.
//
// By default gin trusts every proxy and returns the LEFTMOST X-Forwarded-For
// entry, which the caller writes, so one fake IP per request defeated the
// limiter (review of PR #5). Here no proxy is trusted for X-Forwarded-For;
// the only header believed is [trustedHeader], which the hosting platform's
// edge sets and overwrites (Railway: X-Real-IP, see
// https://docs.railway.com/networking/public-networking/specs-and-limits).
// With an empty header, or when it is absent, the TCP peer address is used.
func ConfigureClientIP(router *gin.Engine, trustedHeader string) error {
	if err := router.SetTrustedProxies(nil); err != nil {
		return fmt.Errorf("disabling proxy trust: %w", err)
	}
	router.TrustedPlatform = trustedHeader
	return nil
}

package middleware

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"golang.org/x/time/rate"
)

// RateLimiter is an in-memory, per-client token bucket used on the auth
// endpoints (login, signup, password reset…) to slow down credential
// stuffing and code guessing. Each client (by ClientIP) may make `burst`
// requests at once, refilled at one request per `every`.
//
// In-memory means per instance: fine for the single backend replica on
// Railway; a multi-replica deploy would need a shared store.
type RateLimiter struct {
	mu      sync.Mutex
	clients map[string]*limiterEntry
	burst   int
	every   time.Duration
}

type limiterEntry struct {
	lim      *rate.Limiter
	lastSeen time.Time
}

// idleEviction drops buckets of clients not seen for this long, so the map
// cannot grow without bound.
const idleEviction = 15 * time.Minute

// NewRateLimiter allows `burst` requests at once per client, refilling one
// request per `every`.
func NewRateLimiter(burst int, every time.Duration) *RateLimiter {
	return &RateLimiter{clients: map[string]*limiterEntry{}, burst: burst, every: every}
}

func (l *RateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := time.Now()
	for k, e := range l.clients {
		if now.Sub(e.lastSeen) > idleEviction {
			delete(l.clients, k)
		}
	}
	e, ok := l.clients[key]
	if !ok {
		e = &limiterEntry{lim: rate.NewLimiter(rate.Every(l.every), l.burst)}
		l.clients[key] = e
	}
	e.lastSeen = now
	return e.lim.Allow()
}

// Middleware rejects over-limit requests with 429 and a Retry-After hint.
func (l *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !l.allow(c.ClientIP()) {
			c.Header("Retry-After", "60")
			c.AbortWithStatusJSON(http.StatusTooManyRequests,
				gin.H{"error": "Too many attempts. Please wait a minute and try again."})
			return
		}
		c.Next()
	}
}

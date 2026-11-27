package middleware

import (
	"math"
	"net/http"
	"strconv"
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
// Railway; a multi-replica deploy would need a shared store. The client key
// comes from ClientIP(), so see ConfigureClientIP for what it trusts.
type RateLimiter struct {
	mu         sync.Mutex
	clients    map[string]*limiterEntry
	burst      int
	every      time.Duration
	maxClients int
	lastSweep  time.Time
	now        func() time.Time // injectable clock for tests
}

type limiterEntry struct {
	lim      *rate.Limiter
	lastSeen time.Time
}

// idleEviction drops buckets of clients not seen for this long.
const idleEviction = 15 * time.Minute

// sweepInterval: idle buckets are swept at most this often, not on every
// request (a per-request scan under the lock was O(clients) per login).
const sweepInterval = time.Minute

// defaultMaxClients caps tracked clients so a flood of distinct addresses
// cannot grow memory without bound. Past the cap NEW clients are refused
// (429) until idle ones are swept; known clients keep their buckets.
const defaultMaxClients = 50_000

// NewRateLimiter allows `burst` requests at once per client, refilling one
// request per `every`.
func NewRateLimiter(burst int, every time.Duration) *RateLimiter {
	return &RateLimiter{
		clients:    map[string]*limiterEntry{},
		burst:      burst,
		every:      every,
		maxClients: defaultMaxClients,
		now:        time.Now,
	}
}

func (l *RateLimiter) allow(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	now := l.now()
	if now.Sub(l.lastSweep) >= sweepInterval {
		l.sweep(now)
	}
	e, ok := l.clients[key]
	if !ok {
		if len(l.clients) >= l.maxClients {
			return false
		}
		e = &limiterEntry{lim: rate.NewLimiter(rate.Every(l.every), l.burst)}
		l.clients[key] = e
	}
	e.lastSeen = now
	return e.lim.Allow()
}

// sweep drops idle buckets. Caller holds l.mu.
func (l *RateLimiter) sweep(now time.Time) {
	for k, e := range l.clients {
		if now.Sub(e.lastSeen) > idleEviction {
			delete(l.clients, k)
		}
	}
	l.lastSweep = now
}

// Middleware rejects over-limit requests with 429 and a Retry-After hint
// (seconds until one more attempt is available).
func (l *RateLimiter) Middleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		if !l.allow(c.ClientIP()) {
			// One attempt comes back every `every`, so that is the honest wait.
			wait := int(math.Ceil(l.every.Seconds()))
			c.Header("Retry-After", strconv.Itoa(wait))
			c.AbortWithStatusJSON(http.StatusTooManyRequests,
				gin.H{"error": "Too many attempts. Please wait a few seconds and try again."})
			return
		}
		c.Next()
	}
}

package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

func limitedRouter(l *RateLimiter) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.POST("/login", l.Middleware(), func(c *gin.Context) { c.String(200, "ok") })
	return r
}

func post(r *gin.Engine, ip string) int {
	req := httptest.NewRequest("POST", "/login", nil)
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code
}

func TestRateLimit_BlocksAfterBurst(t *testing.T) {
	r := limitedRouter(NewRateLimiter(3, time.Minute))
	for i := 0; i < 3; i++ {
		if code := post(r, "10.0.0.1"); code != 200 {
			t.Fatalf("request %d: code %d", i, code)
		}
	}
	if code := post(r, "10.0.0.1"); code != http.StatusTooManyRequests {
		t.Fatalf("4th request code = %d, want 429", code)
	}
}

func TestRateLimit_IsPerClient(t *testing.T) {
	r := limitedRouter(NewRateLimiter(1, time.Minute))
	if post(r, "10.0.0.1") != 200 || post(r, "10.0.0.2") != 200 {
		t.Fatal("different clients must not share a bucket")
	}
}

func TestRateLimit_RefillsOverTime(t *testing.T) {
	l := NewRateLimiter(1, 50*time.Millisecond)
	r := limitedRouter(l)
	if post(r, "10.0.0.9") != 200 {
		t.Fatal("first request blocked")
	}
	time.Sleep(80 * time.Millisecond)
	if code := post(r, "10.0.0.9"); code != 200 {
		t.Fatalf("after refill code = %d", code)
	}
}

// Review finding (PR #5): gin trusted every proxy, so ClientIP() returned the
// leftmost, client-controlled X-Forwarded-For value and a fresh fake IP per
// request bypassed the limit. Only the platform's own client-IP header (or
// the TCP peer) may identify the client.
func spoofRouter(t *testing.T, header string) *gin.Engine {
	t.Helper()
	gin.SetMode(gin.TestMode)
	r := gin.New()
	if err := ConfigureClientIP(r, header); err != nil {
		t.Fatal(err)
	}
	l := NewRateLimiter(1, time.Minute)
	r.POST("/login", l.Middleware(), func(c *gin.Context) { c.String(200, "ok") })
	return r
}

func postWith(r *gin.Engine, headers map[string]string) int {
	req := httptest.NewRequest("POST", "/login", nil)
	req.RemoteAddr = "10.9.9.9:1234" // the platform proxy
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w.Code
}

func TestClientIP_SpoofedForwardedForIsIgnored(t *testing.T) {
	r := spoofRouter(t, "X-Real-IP")
	h := map[string]string{"X-Real-IP": "203.0.113.7", "X-Forwarded-For": "1.1.1.1"}
	if postWith(r, h) != 200 {
		t.Fatal("first request blocked")
	}
	h["X-Forwarded-For"] = "2.2.2.2" // a fresh fake IP must not reset the bucket
	if code := postWith(r, h); code != http.StatusTooManyRequests {
		t.Fatalf("spoofed X-Forwarded-For bypassed the limit: %d", code)
	}
}

func TestClientIP_PlatformHeaderSeparatesClients(t *testing.T) {
	r := spoofRouter(t, "X-Real-IP")
	if postWith(r, map[string]string{"X-Real-IP": "203.0.113.7"}) != 200 ||
		postWith(r, map[string]string{"X-Real-IP": "203.0.113.8"}) != 200 {
		t.Fatal("two real clients behind the platform proxy shared a bucket")
	}
}

func TestClientIP_NoHeaderConfiguredUsesPeer(t *testing.T) {
	r := spoofRouter(t, "")
	if postWith(r, map[string]string{"X-Real-IP": "1.1.1.1"}) != 200 {
		t.Fatal("first request blocked")
	}
	if code := postWith(r, map[string]string{"X-Real-IP": "2.2.2.2"}); code != http.StatusTooManyRequests {
		t.Fatalf("with no trusted header, client headers must be ignored: %d", code)
	}
}

// Review finding: every request scanned the whole client map under the lock.
// Idle buckets are now swept at most once per sweep interval, and the map is
// capped so spoofed or real floods cannot grow it without bound.
func TestRateLimit_CapsTrackedClients(t *testing.T) {
	l := NewRateLimiter(5, time.Minute)
	l.maxClients = 2
	r := limitedRouter(l)
	if post(r, "10.0.0.1") != 200 || post(r, "10.0.0.2") != 200 {
		t.Fatal("clients under the cap were blocked")
	}
	if code := post(r, "10.0.0.3"); code != http.StatusTooManyRequests {
		t.Fatalf("client over the cap: code %d, want 429", code)
	}
	if post(r, "10.0.0.1") != 200 {
		t.Fatal("known client must keep working at the cap")
	}
}

func TestRateLimit_SweepsIdleClientsOnInterval(t *testing.T) {
	now := time.Unix(1_000_000, 0)
	l := NewRateLimiter(5, time.Minute)
	l.now = func() time.Time { return now }
	l.allow("a")
	l.allow("b")
	now = now.Add(idleEviction + time.Second)
	l.allow("c") // past the sweep interval: idle a and b are dropped
	l.mu.Lock()
	n := len(l.clients)
	l.mu.Unlock()
	if n != 1 {
		t.Fatalf("tracked clients after sweep = %d, want 1", n)
	}
}

func TestRateLimit_RetryAfterMatchesRefill(t *testing.T) {
	r := limitedRouter(NewRateLimiter(1, 6*time.Second))
	post(r, "10.0.0.5")
	req := httptest.NewRequest("POST", "/login", nil)
	req.RemoteAddr = "10.0.0.5:1"
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusTooManyRequests || w.Header().Get("Retry-After") != "6" {
		t.Fatalf("code %d Retry-After %q, want 429 / 6", w.Code, w.Header().Get("Retry-After"))
	}
}

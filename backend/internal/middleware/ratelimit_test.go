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

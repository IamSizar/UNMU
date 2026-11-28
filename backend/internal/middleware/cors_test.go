package middleware

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
)

func corsRouter(allowed []string, allowAny bool) *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.Use(CORS(allowed, allowAny))
	r.GET("/x", func(c *gin.Context) { c.String(200, "ok") })
	return r
}

func do(r *gin.Engine, method, origin string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, "/x", nil)
	if origin != "" {
		req.Header.Set("Origin", origin)
	}
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	return w
}

func TestCORS_ListedOriginIsEchoed(t *testing.T) {
	w := do(corsRouter([]string{"https://dash.example"}, false), "GET", "https://dash.example")
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "https://dash.example" {
		t.Fatalf("allow-origin = %q", got)
	}
	if w.Header().Get("Vary") != "Origin" {
		t.Fatal("missing Vary: Origin")
	}
}

func TestCORS_UnlistedOriginGetsNoHeader(t *testing.T) {
	w := do(corsRouter([]string{"https://dash.example"}, false), "GET", "https://evil.example")
	if got := w.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Fatalf("unlisted origin allowed: %q", got)
	}
	if w.Code != 200 {
		t.Fatalf("non-browser semantics changed: code %d", w.Code)
	}
}

func TestCORS_UnlistedPreflightRejected(t *testing.T) {
	w := do(corsRouter([]string{"https://dash.example"}, false), "OPTIONS", "https://evil.example")
	if w.Code != http.StatusForbidden {
		t.Fatalf("preflight code = %d, want 403", w.Code)
	}
}

func TestCORS_ListedPreflightOK(t *testing.T) {
	w := do(corsRouter([]string{"https://dash.example"}, false), "OPTIONS", "https://dash.example")
	if w.Code != http.StatusNoContent {
		t.Fatalf("preflight code = %d, want 204", w.Code)
	}
}

func TestCORS_NeverSendsCredentialsHeader(t *testing.T) {
	w := do(corsRouter(nil, true), "GET", "https://anything.example")
	if w.Header().Get("Access-Control-Allow-Credentials") != "" {
		t.Fatal("credentials header must not be sent (bearer tokens only)")
	}
	if w.Header().Get("Access-Control-Allow-Origin") != "https://anything.example" {
		t.Fatal("dev allow-any should echo the origin")
	}
}

func TestOriginAllowed_NoOriginIsAllowed(t *testing.T) {
	// Mobile apps send no Origin header (WebSocket handshake check).
	if !OriginAllowed("", []string{"https://dash.example"}, false) {
		t.Fatal("empty origin must be allowed")
	}
	if OriginAllowed("https://evil.example", []string{"https://dash.example"}, false) {
		t.Fatal("unlisted origin allowed")
	}
}

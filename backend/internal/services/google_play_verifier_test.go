package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakePlay serves purchases.subscriptionsv2.get and records acknowledge calls.
type fakePlay struct {
	mu    sync.Mutex
	subs  map[string]map[string]any // purchase token -> SubscriptionPurchaseV2 JSON
	acked []string
}

func (f *fakePlay) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	const pkg = "/androidpublisher/v3/applications/com.easytech.stocks/purchases/"
	switch {
	case r.Method == http.MethodGet && strings.HasPrefix(r.URL.Path, pkg+"subscriptionsv2/tokens/"):
		token := strings.TrimPrefix(r.URL.Path, pkg+"subscriptionsv2/tokens/")
		sub, ok := f.subs[token]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"code":404,"message":"not found"}}`))
			return
		}
		_ = json.NewEncoder(w).Encode(sub)
	case r.Method == http.MethodPost && strings.HasSuffix(r.URL.Path, ":acknowledge"):
		f.acked = append(f.acked, r.URL.Path)
		_, _ = w.Write([]byte(`{}`))
	default:
		w.WriteHeader(http.StatusBadRequest)
	}
}

func playSub(state, product string, expires time.Time, test bool) map[string]any {
	s := map[string]any{
		"subscriptionState":    state,
		"acknowledgementState": "ACKNOWLEDGEMENT_STATE_PENDING",
		"latestOrderId":        "GPA.1",
		"startTime":            expires.Add(-30 * 24 * time.Hour).Format(time.RFC3339),
		"lineItems": []map[string]any{{
			"productId": product, "expiryTime": expires.Format(time.RFC3339),
		}},
	}
	if test {
		s["testPurchase"] = map[string]any{}
	}
	return s
}

func newFakePlayVerifier(t *testing.T, f *fakePlay) *GooglePlayVerifier {
	t.Helper()
	srv := httptest.NewServer(f)
	t.Cleanup(srv.Close)
	v, err := newGooglePlayVerifierForEndpoint(context.Background(), srv.URL+"/", "com.easytech.stocks")
	if err != nil {
		t.Fatalf("verifier: %v", err)
	}
	return v
}

func TestGooglePlayVerify_ActiveSubscription(t *testing.T) {
	exp := time.Now().Add(24 * time.Hour).UTC().Truncate(time.Second)
	f := &fakePlay{subs: map[string]map[string]any{
		"tok1": playSub("SUBSCRIPTION_STATE_ACTIVE", "com.unmu.premium.monthly", exp, false),
	}}
	got, err := newFakePlayVerifier(t, f).Verify(context.Background(), "tok1", "com.unmu.premium.monthly")
	if err != nil {
		t.Fatalf("verify: %v", err)
	}
	if got.ExpiresDate == nil || !got.ExpiresDate.Equal(exp) || got.OrderID != "GPA.1" ||
		got.Acknowledged || got.Test || got.ProductID != "com.unmu.premium.monthly" {
		t.Fatalf("unexpected result: %+v", got)
	}
}

func TestGooglePlayVerify_Refusals(t *testing.T) {
	future := time.Now().Add(time.Hour)
	f := &fakePlay{subs: map[string]map[string]any{
		"pending": playSub("SUBSCRIPTION_STATE_PENDING", "com.unmu.premium.monthly", future, false),
		"onhold":  playSub("SUBSCRIPTION_STATE_ON_HOLD", "com.unmu.premium.monthly", future, false),
		"expired": playSub("SUBSCRIPTION_STATE_EXPIRED", "com.unmu.premium.monthly", future, false),
		"other":   playSub("SUBSCRIPTION_STATE_ACTIVE", "com.unmu.premium.yearly", future, false),
	}}
	v := newFakePlayVerifier(t, f)
	cases := map[string]string{
		"pending": "com.unmu.premium.monthly", "onhold": "com.unmu.premium.monthly",
		"expired": "com.unmu.premium.monthly", "other": "com.unmu.premium.monthly",
		"unknown": "com.unmu.premium.monthly", "": "com.unmu.premium.monthly",
	}
	for token, product := range cases {
		if _, err := v.Verify(context.Background(), token, product); err == nil {
			t.Errorf("token %q accepted", token)
		}
	}
	if _, err := v.Verify(context.Background(), "pending", ""); err == nil {
		t.Error("empty product id accepted")
	}
}

// A cancelled subscription keeps access until its expiry; grace period too.
func TestGooglePlayVerify_CanceledAndGraceStillEntitled(t *testing.T) {
	future := time.Now().Add(time.Hour)
	f := &fakePlay{subs: map[string]map[string]any{
		"canceled": playSub("SUBSCRIPTION_STATE_CANCELED", "com.unmu.premium.monthly", future, false),
		"grace":    playSub("SUBSCRIPTION_STATE_IN_GRACE_PERIOD", "com.unmu.premium.monthly", future, false),
	}}
	v := newFakePlayVerifier(t, f)
	for _, token := range []string{"canceled", "grace"} {
		if _, err := v.Verify(context.Background(), token, "com.unmu.premium.monthly"); err != nil {
			t.Errorf("%s refused: %v", token, err)
		}
	}
}

func TestGooglePlayVerify_TestPurchaseSetting(t *testing.T) {
	f := &fakePlay{subs: map[string]map[string]any{
		"t": playSub("SUBSCRIPTION_STATE_ACTIVE", "com.unmu.premium.monthly", time.Now().Add(time.Hour), true),
	}}
	v := newFakePlayVerifier(t, f)
	got, err := v.Verify(context.Background(), "t", "com.unmu.premium.monthly")
	if err != nil || !got.Test {
		t.Fatalf("test purchase with tests allowed: %+v, %v", got, err)
	}
	v.rejectTest = true
	if _, err := v.Verify(context.Background(), "t", "com.unmu.premium.monthly"); err == nil {
		t.Fatal("test purchase accepted with tests disallowed")
	}
}

func TestGooglePlayAcknowledge(t *testing.T) {
	f := &fakePlay{subs: map[string]map[string]any{}}
	v := newFakePlayVerifier(t, f)
	if err := v.Acknowledge(context.Background(), "com.unmu.premium.monthly", "tok1"); err != nil {
		t.Fatalf("acknowledge: %v", err)
	}
	want := "/androidpublisher/v3/applications/com.easytech.stocks/purchases/subscriptions/com.unmu.premium.monthly/tokens/tok1:acknowledge"
	if len(f.acked) != 1 || f.acked[0] != want {
		t.Fatalf("acknowledge calls = %v, want [%s]", f.acked, want)
	}
}

func TestNewGooglePlayVerifier_SoftFailsWithoutCredentials(t *testing.T) {
	t.Setenv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON", "")
	t.Setenv("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE", "")
	t.Setenv("GOOGLE_PLAY_API_ENDPOINT", "")
	if v := NewGooglePlayVerifier(context.Background()); v != nil {
		t.Fatal("verifier built without credentials")
	}
}

// The no-auth test endpoint is only honoured for loopback addresses.
func TestGooglePlayEndpointMustBeLoopback(t *testing.T) {
	for url, want := range map[string]bool{
		"http://127.0.0.1:9/": true, "http://localhost:9/": true,
		"https://androidpublisher.googleapis.com/": false, "http://10.0.0.5/": false,
	} {
		if got := isLoopbackURL(url); got != want {
			t.Errorf("isLoopbackURL(%q) = %v, want %v", url, got, want)
		}
	}
}

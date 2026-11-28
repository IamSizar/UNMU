package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// A receipt from ANOTHER app (any app's valid receipt passes Apple's
// verifyReceipt) must not unlock UNMU subscriptions.
func bundleServer(t *testing.T, bundleID string) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		receipt := map[string]any{}
		if bundleID != "" {
			receipt["bundle_id"] = bundleID
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":      0,
			"environment": "Production",
			"receipt":     receipt,
			"latest_receipt_info": []map[string]any{{
				"transaction_id":   "T1",
				"product_id":       "com.unmu.premium.monthly",
				"purchase_date_ms": "1729200000000",
			}},
		})
	}))
}

func bundleVerifier(url string) *AppleIAPVerifier {
	return &AppleIAPVerifier{
		sharedSecret: "s",
		prodURL:      url,
		sandboxURL:   "http://unused",
		bundleID:     "com.easytech.stocksanalyzer",
		httpClient:   &http.Client{Timeout: 5 * time.Second},
	}
}

func TestVerifyReceipt_MatchingBundleAccepted(t *testing.T) {
	srv := bundleServer(t, "com.easytech.stocksanalyzer")
	defer srv.Close()
	if _, err := bundleVerifier(srv.URL).VerifyReceipt(context.Background(), "r", "com.unmu.premium.monthly"); err != nil {
		t.Fatalf("matching bundle rejected: %v", err)
	}
}

func TestVerifyReceipt_OtherAppRejected(t *testing.T) {
	srv := bundleServer(t, "com.someone.else")
	defer srv.Close()
	if _, err := bundleVerifier(srv.URL).VerifyReceipt(context.Background(), "r", "com.unmu.premium.monthly"); err == nil {
		t.Fatal("receipt from another app accepted")
	}
}

func TestVerifyReceipt_MissingBundleRejected(t *testing.T) {
	srv := bundleServer(t, "")
	defer srv.Close()
	if _, err := bundleVerifier(srv.URL).VerifyReceipt(context.Background(), "r", "com.unmu.premium.monthly"); err == nil {
		t.Fatal("receipt without bundle_id accepted")
	}
}

func TestNewAppleIAPVerifier_BundleFromEnvOrDefault(t *testing.T) {
	t.Setenv("APPLE_IAP_SHARED_SECRET", "s")
	t.Setenv("APPLE_BUNDLE_ID", "")
	if got := NewAppleIAPVerifier().bundleID; got != "com.easytech.stocksanalyzer" {
		t.Errorf("default bundle = %q", got)
	}
	t.Setenv("APPLE_BUNDLE_ID", " com.example.other ")
	if got := NewAppleIAPVerifier().bundleID; got != "com.example.other" {
		t.Errorf("env bundle = %q", got)
	}
}

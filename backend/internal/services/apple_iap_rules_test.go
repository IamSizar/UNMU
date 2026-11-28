package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"
)

// An empty product id used to match ANY product in the receipt.
func TestVerifyReceipt_EmptyProductRejected(t *testing.T) {
	srv := bundleServer(t, "com.easytech.stocksanalyzer")
	defer srv.Close()
	if _, err := bundleVerifier(srv.URL).VerifyReceipt(context.Background(), "r", ""); err == nil {
		t.Fatal("empty product id accepted")
	}
}

func sandboxOnlyServers(t *testing.T) (prod, sandbox *httptest.Server) {
	t.Helper()
	prod = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"status": 21007})
	}))
	sandbox = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status": 0, "environment": "Sandbox",
			"receipt": map[string]any{"bundle_id": "com.easytech.stocksanalyzer"},
			"latest_receipt_info": []map[string]any{{
				"transaction_id": "S1", "original_transaction_id": "S1",
				"product_id": "com.unmu.premium.monthly", "purchase_date_ms": "1729200000000",
			}},
		})
	}))
	return prod, sandbox
}

func TestVerifyReceipt_SandboxRejectedWhenDisallowed(t *testing.T) {
	prod, sandbox := sandboxOnlyServers(t)
	defer prod.Close()
	defer sandbox.Close()
	v := &AppleIAPVerifier{
		sharedSecret: "s", prodURL: prod.URL, sandboxURL: sandbox.URL,
		bundleID: "com.easytech.stocksanalyzer", rejectSandbox: true,
		httpClient: &http.Client{Timeout: 5 * time.Second},
	}
	if _, err := v.VerifyReceipt(context.Background(), "r", "com.unmu.premium.monthly"); err == nil {
		t.Fatal("sandbox receipt accepted with sandbox disabled")
	}
	v.rejectSandbox = false
	if _, err := v.VerifyReceipt(context.Background(), "r", "com.unmu.premium.monthly"); err != nil {
		t.Fatalf("sandbox receipt refused with sandbox allowed: %v", err)
	}
}

// App Review buys with sandbox receipts against the production server, so
// sandbox stays allowed unless APPLE_IAP_ALLOW_SANDBOX turns it off.
func TestNewAppleIAPVerifier_SandboxSetting(t *testing.T) {
	t.Setenv("APPLE_IAP_SHARED_SECRET", "s")
	for value, wantReject := range map[string]bool{"": false, "true": false, "false": true, "0": true} {
		t.Setenv("APPLE_IAP_ALLOW_SANDBOX", value)
		if got := NewAppleIAPVerifier().rejectSandbox; got != wantReject {
			t.Errorf("APPLE_IAP_ALLOW_SANDBOX=%q: rejectSandbox = %v, want %v", value, got, wantReject)
		}
	}
}

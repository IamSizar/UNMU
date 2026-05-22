package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

// TestNewAppleIAPVerifier_SoftFail — same soft-fail contract as the email
// sender: missing env returns nil so the handler can degrade to 503.
func TestNewAppleIAPVerifier_SoftFail(t *testing.T) {
	old := os.Getenv("APPLE_IAP_SHARED_SECRET")
	defer os.Setenv("APPLE_IAP_SHARED_SECRET", old)
	os.Unsetenv("APPLE_IAP_SHARED_SECRET")

	if got := NewAppleIAPVerifier(); got != nil {
		t.Fatalf("got %+v, want nil when secret unset", got)
	}
}

// TestVerifyReceipt_ProdAcceptedTransaction — happy path against a
// production-style response.
func TestVerifyReceipt_ProdAcceptedTransaction(t *testing.T) {
	prodSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":      0,
			"environment": "Production",
			"latest_receipt_info": []map[string]any{
				{
					"transaction_id":          "TXN_111",
					"original_transaction_id": "TXN_111",
					"product_id":              "com.unmu.expert.x.monthly",
					"purchase_date_ms":        "1729200000000", // 2024-10-17
					"expires_date_ms":         "1731792000000", // ~30d later
				},
			},
		})
	}))
	defer prodSrv.Close()

	v := &AppleIAPVerifier{
		sharedSecret: "test-secret",
		prodURL:      prodSrv.URL,
		sandboxURL:   "http://unused",
		httpClient:   &http.Client{Timeout: 5 * time.Second},
	}

	txn, err := v.VerifyReceipt(context.Background(), "base64-receipt", "com.unmu.expert.x.monthly")
	if err != nil {
		t.Fatalf("VerifyReceipt error: %v", err)
	}
	if txn.TransactionID != "TXN_111" {
		t.Errorf("TransactionID = %q, want TXN_111", txn.TransactionID)
	}
	if txn.Environment != "Production" {
		t.Errorf("Environment = %q, want Production", txn.Environment)
	}
	if txn.ExpiresDate == nil {
		t.Errorf("ExpiresDate = nil, want a non-nil time")
	}
	if txn.PurchaseDate.IsZero() {
		t.Errorf("PurchaseDate is zero, want a parsed timestamp")
	}
}

// TestVerifyReceipt_SandboxFallback — Apple's documented 21007 status
// means "you sent a sandbox receipt to production; retry against sandbox".
// We must follow that hop transparently.
func TestVerifyReceipt_SandboxFallback(t *testing.T) {
	prodSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"status": 21007})
	}))
	defer prodSrv.Close()

	sandboxSrv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":      0,
			"environment": "Sandbox",
			"latest_receipt_info": []map[string]any{
				{
					"transaction_id":          "TXN_SANDBOX",
					"original_transaction_id": "TXN_SANDBOX",
					"product_id":              "com.unmu.expert.x.monthly",
					"purchase_date_ms":        "1729200000000",
					"expires_date_ms":         "1731792000000",
				},
			},
		})
	}))
	defer sandboxSrv.Close()

	v := &AppleIAPVerifier{
		sharedSecret: "test-secret",
		prodURL:      prodSrv.URL,
		sandboxURL:   sandboxSrv.URL,
		httpClient:   &http.Client{Timeout: 5 * time.Second},
	}

	txn, err := v.VerifyReceipt(context.Background(), "base64-receipt", "")
	if err != nil {
		t.Fatalf("VerifyReceipt error: %v", err)
	}
	if txn.Environment != "Sandbox" {
		t.Errorf("Environment = %q, want Sandbox", txn.Environment)
	}
	if txn.TransactionID != "TXN_SANDBOX" {
		t.Errorf("TransactionID = %q, want TXN_SANDBOX", txn.TransactionID)
	}
}

// TestVerifyReceipt_BadStatusErrors — any non-zero status that isn't the
// sandbox-fallback signal must surface as a generic error (we don't want
// callers branching on Apple's internal status codes).
func TestVerifyReceipt_BadStatusErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"status": 21002}) // bad receipt data
	}))
	defer srv.Close()

	v := &AppleIAPVerifier{
		sharedSecret: "x",
		prodURL:      srv.URL,
		sandboxURL:   srv.URL,
		httpClient:   &http.Client{Timeout: 5 * time.Second},
	}

	if _, err := v.VerifyReceipt(context.Background(), "bad", ""); err == nil {
		t.Fatal("expected error for non-zero status, got nil")
	}
}

// TestVerifyReceipt_NoMatchingProduct — when the response only contains
// transactions for other SKUs, we must error rather than silently return
// a wrong-product transaction.
func TestVerifyReceipt_NoMatchingProduct(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{
			"status":      0,
			"environment": "Production",
			"latest_receipt_info": []map[string]any{
				{
					"transaction_id":          "TXN_OTHER",
					"original_transaction_id": "TXN_OTHER",
					"product_id":              "com.unmu.other.product",
					"purchase_date_ms":        "1729200000000",
				},
			},
		})
	}))
	defer srv.Close()

	v := &AppleIAPVerifier{
		sharedSecret: "x",
		prodURL:      srv.URL,
		sandboxURL:   srv.URL,
		httpClient:   &http.Client{Timeout: 5 * time.Second},
	}
	if _, err := v.VerifyReceipt(context.Background(), "r", "com.unmu.expert.x.monthly"); err == nil {
		t.Fatal("expected error for product mismatch, got nil")
	}
}

// TestVerifyReceipt_NilReceiver — defensive: calling on nil sender must
// error rather than panic.
func TestVerifyReceipt_NilReceiver(t *testing.T) {
	var v *AppleIAPVerifier
	if _, err := v.VerifyReceipt(context.Background(), "r", ""); err == nil {
		t.Fatal("expected error from nil verifier, got nil")
	}
}

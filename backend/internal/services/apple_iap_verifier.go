package services

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

// AppleIAPVerifier wraps Apple's verifyReceipt endpoint. It's the legacy
// receipt-validation API (Apple still supports it as of 2026, even though
// they recommend the App Store Server API v2 for new integrations). We
// pick verifyReceipt because:
//
//  1. Configuration is trivial — one shared secret, fetched from App Store
//     Connect → My Apps → In-App Purchases → App-Specific Shared Secret.
//  2. It accepts the raw receipt blob that the Flutter in_app_purchase
//     plugin hands us via `PurchaseDetails.verificationData
//     .serverVerificationData`. No JWS decoding on the client side.
//  3. Auto sandbox/prod handling: try production first, fall back to
//     sandbox on the documented 21007 error code.
//
// When APPLE_IAP_SHARED_SECRET is unset, NewAppleIAPVerifier returns nil.
// The IAP handler then refuses Apple verifications with a clear 503 so an
// operator knows what to configure.
type AppleIAPVerifier struct {
	sharedSecret string
	prodURL      string
	sandboxURL   string
	httpClient   *http.Client
}

// NewAppleIAPVerifier — soft-fails to nil when the shared secret is unset.
func NewAppleIAPVerifier() *AppleIAPVerifier {
	secret := strings.TrimSpace(os.Getenv("APPLE_IAP_SHARED_SECRET"))
	if secret == "" {
		return nil
	}
	prodURL := strings.TrimSpace(os.Getenv("APPLE_IAP_PROD_URL"))
	if prodURL == "" {
		prodURL = "https://buy.itunes.apple.com/verifyReceipt"
	}
	sandboxURL := strings.TrimSpace(os.Getenv("APPLE_IAP_SANDBOX_URL"))
	if sandboxURL == "" {
		sandboxURL = "https://sandbox.itunes.apple.com/verifyReceipt"
	}
	log.Printf("[apple-iap] verifier configured (prod=%s sandbox=%s)", prodURL, sandboxURL)
	return &AppleIAPVerifier{
		sharedSecret: secret,
		prodURL:      prodURL,
		sandboxURL:   sandboxURL,
		httpClient:   &http.Client{Timeout: 15 * time.Second},
	}
}

// AppleVerifiedTransaction is the slice of Apple's response that the
// handler / repo actually persist. Apple returns a much larger payload
// (full receipt + every renewal); we extract just the latest transaction
// for the given product.
type AppleVerifiedTransaction struct {
	TransactionID         string
	OriginalTransactionID string
	ProductID             string
	Environment           string    // "Production" or "Sandbox"
	PurchaseDate          time.Time
	ExpiresDate           *time.Time // nil for non-subscription products
	RawPayload            []byte    // the per-transaction JSON blob, for audit
}

// VerifyReceipt sends the receipt to Apple, picks the most recent
// transaction for `expectedProductID` (when non-empty), and returns it.
// Empty expectedProductID matches any product — useful when the client
// hasn't told us which SKU it bought (or when restoring purchases).
//
// Errors are intentionally generic ("verification failed") so we don't
// leak Apple's status codes to the API caller; the codes are logged.
func (v *AppleIAPVerifier) VerifyReceipt(
	ctx context.Context,
	receiptData string,
	expectedProductID string,
) (*AppleVerifiedTransaction, error) {
	if v == nil {
		return nil, fmt.Errorf("apple-iap: verifier not configured")
	}
	receiptData = strings.TrimSpace(receiptData)
	if receiptData == "" {
		return nil, fmt.Errorf("apple-iap: empty receipt")
	}

	// Try production first; if Apple returns 21007 ("sandbox receipt sent
	// to production"), retry against sandbox. This is the canonical flow
	// per Apple's own docs.
	resp, env, err := v.callApple(ctx, v.prodURL, receiptData)
	if err != nil {
		return nil, err
	}
	if resp.Status == 21007 {
		resp, env, err = v.callApple(ctx, v.sandboxURL, receiptData)
		if err != nil {
			return nil, err
		}
	}
	if resp.Status != 0 {
		log.Printf("[apple-iap] verifyReceipt status=%d env=%s — see %s",
			resp.Status, env,
			"https://developer.apple.com/documentation/appstorereceipts/status")
		return nil, fmt.Errorf("apple-iap: verification failed (status %d)", resp.Status)
	}

	txn, err := pickLatestTransaction(resp, expectedProductID)
	if err != nil {
		return nil, err
	}
	txn.Environment = env
	return txn, nil
}

// callApple is the single-endpoint POST helper. Returns the decoded
// response plus the environment string we should record.
func (v *AppleIAPVerifier) callApple(
	ctx context.Context,
	endpoint, receiptData string,
) (appleVerifyResponse, string, error) {
	reqBody, _ := json.Marshal(map[string]any{
		"receipt-data":             receiptData,
		"password":                 v.sharedSecret,
		"exclude-old-transactions": false,
	})

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(reqBody))
	if err != nil {
		return appleVerifyResponse{}, "", fmt.Errorf("apple-iap: build request: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := v.httpClient.Do(req)
	if err != nil {
		return appleVerifyResponse{}, "", fmt.Errorf("apple-iap: dial: %w", err)
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return appleVerifyResponse{}, "", fmt.Errorf("apple-iap: read body: %w", err)
	}
	if resp.StatusCode != http.StatusOK {
		return appleVerifyResponse{}, "", fmt.Errorf("apple-iap: %s returned %d: %s",
			endpoint, resp.StatusCode, truncForLog(body, 200))
	}

	var decoded appleVerifyResponse
	if err := json.Unmarshal(body, &decoded); err != nil {
		return appleVerifyResponse{}, "", fmt.Errorf("apple-iap: decode: %w", err)
	}
	env := decoded.Environment
	if env == "" {
		if endpoint == v.sandboxURL {
			env = "Sandbox"
		} else {
			env = "Production"
		}
	}
	return decoded, env, nil
}

// appleVerifyResponse mirrors the subset of Apple's verifyReceipt JSON we
// care about. The full schema is documented at:
// https://developer.apple.com/documentation/appstorereceipts/responsebody
type appleVerifyResponse struct {
	Status            int                       `json:"status"`
	Environment       string                    `json:"environment"`
	LatestReceiptInfo []appleVerifyTransaction  `json:"latest_receipt_info"`
	Receipt           appleVerifyReceiptInner   `json:"receipt"`
}

type appleVerifyReceiptInner struct {
	InApp []appleVerifyTransaction `json:"in_app"`
}

type appleVerifyTransaction struct {
	TransactionID         string `json:"transaction_id"`
	OriginalTransactionID string `json:"original_transaction_id"`
	ProductID             string `json:"product_id"`
	// Apple uses millisecond Unix epochs encoded as strings here. We do
	// the parsing in pickLatestTransaction.
	PurchaseDateMS string `json:"purchase_date_ms"`
	ExpiresDateMS  string `json:"expires_date_ms"`
}

// pickLatestTransaction selects the most-recent transaction matching
// (or any, when expectedProductID is empty). Subscriptions live in
// latest_receipt_info; consumables / non-renewing live in receipt.in_app.
// We check both and pick whichever wins on purchase_date.
func pickLatestTransaction(
	resp appleVerifyResponse,
	expectedProductID string,
) (*AppleVerifiedTransaction, error) {
	candidates := append([]appleVerifyTransaction{}, resp.LatestReceiptInfo...)
	candidates = append(candidates, resp.Receipt.InApp...)

	var best *appleVerifyTransaction
	var bestMS int64

	for i := range candidates {
		t := &candidates[i]
		if expectedProductID != "" && t.ProductID != expectedProductID {
			continue
		}
		ms, _ := strconv.ParseInt(t.PurchaseDateMS, 10, 64)
		if best == nil || ms > bestMS {
			best = t
			bestMS = ms
		}
	}
	if best == nil {
		return nil, fmt.Errorf("apple-iap: no transactions for product %q", expectedProductID)
	}

	purchasedAt := time.UnixMilli(bestMS).UTC()
	var expiresAt *time.Time
	if best.ExpiresDateMS != "" {
		if ms, err := strconv.ParseInt(best.ExpiresDateMS, 10, 64); err == nil && ms > 0 {
			t := time.UnixMilli(ms).UTC()
			expiresAt = &t
		}
	}

	raw, _ := json.Marshal(best)
	return &AppleVerifiedTransaction{
		TransactionID:         best.TransactionID,
		OriginalTransactionID: best.OriginalTransactionID,
		ProductID:             best.ProductID,
		PurchaseDate:          purchasedAt,
		ExpiresDate:           expiresAt,
		RawPayload:            raw,
	}, nil
}

func truncForLog(b []byte, n int) string {
	if len(b) <= n {
		return string(b)
	}
	return string(b[:n]) + "…"
}

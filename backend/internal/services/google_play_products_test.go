package services

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// fakePlayProducts serves purchases.products get / consume for one token.
func fakePlayProducts(t *testing.T, purchase map[string]any, consumed *[]string) *GooglePlayVerifier {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		const prefix = "/androidpublisher/v3/applications/com.easytech.stocks/purchases/products/com.unmu.access.t2.month/tokens/"
		switch {
		case r.Method == http.MethodGet && r.URL.Path == prefix+"tok":
			_ = json.NewEncoder(w).Encode(purchase)
		case r.Method == http.MethodPost && strings.HasPrefix(r.URL.Path, prefix) && strings.HasSuffix(r.URL.Path, ":consume"):
			*consumed = append(*consumed, r.URL.Path)
		default:
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":{"code":404,"message":"not found"}}`))
		}
	}))
	t.Cleanup(srv.Close)
	v, err := newGooglePlayVerifierForEndpoint(context.Background(), srv.URL+"/", "com.easytech.stocks")
	if err != nil {
		t.Fatalf("verifier: %v", err)
	}
	return v
}

func TestGooglePlayVerifyProduct(t *testing.T) {
	var consumed []string
	ctx := context.Background()
	v := fakePlayProducts(t, map[string]any{"purchaseState": 0, "orderId": "GPA.9", "purchaseTimeMillis": "1729200000000"}, &consumed)
	p, err := v.VerifyProduct(ctx, "tok", "com.unmu.access.t2.month")
	if err != nil || p.OrderID != "GPA.9" || p.Consumed || p.Test {
		t.Fatalf("got %+v %v", p, err)
	}
	if err := v.ConsumeProduct(ctx, "com.unmu.access.t2.month", "tok"); err != nil || len(consumed) != 1 {
		t.Fatalf("consume: %v %v", err, consumed)
	}
	if _, err := v.VerifyProduct(ctx, "other", "com.unmu.access.t2.month"); err == nil {
		t.Fatal("unknown token must fail")
	}
}

func TestGooglePlayVerifyProduct_Refusals(t *testing.T) {
	var consumed []string
	ctx := context.Background()
	pending := fakePlayProducts(t, map[string]any{"purchaseState": 2}, &consumed)
	if _, err := pending.VerifyProduct(ctx, "tok", "com.unmu.access.t2.month"); err == nil {
		t.Fatal("pending purchase must fail")
	}
	test := fakePlayProducts(t, map[string]any{"purchaseState": 0, "purchaseType": 0}, &consumed)
	test.rejectTest = true
	if _, err := test.VerifyProduct(ctx, "tok", "com.unmu.access.t2.month"); err == nil {
		t.Fatal("test purchase must fail when disallowed")
	}
}

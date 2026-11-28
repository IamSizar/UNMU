// google_play_products.go — verification of one-time (consumable) Play
// products: the tier products com.unmu.access.<tier>.<month|year> that
// pay for expert and community access. Subscriptions (Premium) stay in
// google_play_verifier.go.
package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strings"
	"time"
)

// Play ProductPurchase.purchaseState values.
const (
	playProductPurchased = 0
	playPurchaseTypeTest = 0 // purchaseType for licence-tester purchases
)

// GoogleVerifiedProduct is a paid one-time product purchase.
type GoogleVerifiedProduct struct {
	PurchaseToken string
	OrderID       string
	ProductID     string
	Test          bool
	Consumed      bool
	PurchaseDate  time.Time
	RawPayload    []byte
}

// VerifyProduct fetches the one-time purchase. Anything not in the
// purchased state, or (when disallowed) a test purchase, is an error.
// An already-consumed purchase is returned as is: whether it may still
// grant anything is decided by store_access_grants (one use per token).
func (v *GooglePlayVerifier) VerifyProduct(ctx context.Context, purchaseToken, productID string) (*GoogleVerifiedProduct, error) {
	if v == nil {
		return nil, errors.New("google-play: verifier not configured")
	}
	purchaseToken, productID = strings.TrimSpace(purchaseToken), strings.TrimSpace(productID)
	if purchaseToken == "" || productID == "" {
		return nil, errors.New("google-play: purchase token and product id required")
	}
	p, err := v.svc.Purchases.Products.Get(v.packageName, productID, purchaseToken).Context(ctx).Do()
	if err != nil {
		log.Printf("[google-play] products.get: %v", err)
		return nil, errors.New("google-play: verification failed")
	}
	if p.PurchaseState != playProductPurchased {
		return nil, fmt.Errorf("google-play: purchase state is %d, not purchased", p.PurchaseState)
	}
	isTest := p.PurchaseType != nil && *p.PurchaseType == playPurchaseTypeTest
	if isTest && v.rejectTest {
		return nil, errors.New("google-play: test purchases are not accepted")
	}
	raw, err := p.MarshalJSON()
	if err != nil {
		return nil, fmt.Errorf("google-play: encode payload: %w", err)
	}
	return &GoogleVerifiedProduct{
		PurchaseToken: purchaseToken, OrderID: p.OrderId, ProductID: productID,
		Test: isTest, Consumed: p.ConsumptionState == 1,
		PurchaseDate: time.UnixMilli(p.PurchaseTimeMillis).UTC(), RawPayload: raw,
	}, nil
}

// ConsumeProduct marks the purchase used so the buyer can buy the same
// tier again (for another expert or a renewal). Consuming also
// acknowledges it; an unacknowledged purchase is refunded after 3 days.
func (v *GooglePlayVerifier) ConsumeProduct(ctx context.Context, productID, purchaseToken string) error {
	if v == nil {
		return errors.New("google-play: verifier not configured")
	}
	if err := v.svc.Purchases.Products.Consume(v.packageName, productID, purchaseToken).Context(ctx).Do(); err != nil {
		return fmt.Errorf("google-play: consume: %w", err)
	}
	return nil
}

// voidedLookback is how far back the Voided Purchases API can look.
const voidedLookback = 30 * 24 * time.Hour

// ListVoidedProductTokens returns the purchase tokens of one-time
// products refunded, charged back or cancelled in the last 30 days.
func (v *GooglePlayVerifier) ListVoidedProductTokens(ctx context.Context) ([]string, error) {
	if v == nil {
		return nil, errors.New("google-play: verifier not configured")
	}
	since := time.Now().Add(-voidedLookback).UnixMilli()
	var tokens []string
	page := ""
	for {
		call := v.svc.Purchases.Voidedpurchases.List(v.packageName).
			StartTime(since).Type(0).MaxResults(1000).Context(ctx)
		if page != "" {
			call = call.Token(page)
		}
		resp, err := call.Do()
		if err != nil {
			return nil, fmt.Errorf("google-play: voided purchases: %w", err)
		}
		for _, p := range resp.VoidedPurchases {
			if p != nil && p.PurchaseToken != "" {
				tokens = append(tokens, p.PurchaseToken)
			}
		}
		if resp.TokenPagination == nil || resp.TokenPagination.NextPageToken == "" {
			return tokens, nil
		}
		page = resp.TokenPagination.NextPageToken
	}
}

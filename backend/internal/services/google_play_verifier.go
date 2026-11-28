package services

import (
	"context"
	"errors"
	"fmt"
	"log"
	"net"
	"net/url"
	"os"
	"strings"
	"time"

	"google.golang.org/api/androidpublisher/v3"
	"google.golang.org/api/option"
)

// GooglePlayVerifier checks Android subscription purchases with the Google
// Play Developer API (purchases.subscriptionsv2.get) and acknowledges them
// (purchases.subscriptions.acknowledge). Google refunds a purchase that is
// not acknowledged within three days.
//
// Configuration:
//   - GOOGLE_PLAY_SERVICE_ACCOUNT_JSON (the key JSON) or
//     GOOGLE_PLAY_SERVICE_ACCOUNT_FILE (a path to it) — a service account
//     with access to the app in Play Console. Unset → nil verifier and the
//     endpoint answers 503.
//   - GOOGLE_PLAY_PACKAGE_NAME — default com.easytech.stocks.
//   - GOOGLE_PLAY_ALLOW_TEST — license-tester purchases, allowed unless
//     set to false/0/no/off (Play review and internal testing use them).
//   - GOOGLE_PLAY_API_ENDPOINT — local testing only: a loopback URL that is
//     called without authentication.
type GooglePlayVerifier struct {
	svc         *androidpublisher.Service
	packageName string
	rejectTest  bool
}

const defaultGooglePlayPackage = "com.easytech.stocks"

// GoogleVerifiedSubscription is what the handler and repository need.
type GoogleVerifiedSubscription struct {
	PurchaseToken       string
	LinkedPurchaseToken string
	OrderID             string
	ProductID           string
	State               string
	Test                bool
	Acknowledged        bool
	PurchaseDate        time.Time
	ExpiresDate         *time.Time
	RawPayload          []byte
}

// NewGooglePlayVerifier — soft-fails to nil when nothing is configured.
func NewGooglePlayVerifier(ctx context.Context) *GooglePlayVerifier {
	pkg := strings.TrimSpace(os.Getenv("GOOGLE_PLAY_PACKAGE_NAME"))
	if pkg == "" {
		pkg = defaultGooglePlayPackage
	}
	if endpoint := strings.TrimSpace(os.Getenv("GOOGLE_PLAY_API_ENDPOINT")); endpoint != "" {
		v, err := newGooglePlayVerifierForEndpoint(ctx, endpoint, pkg)
		if err != nil {
			log.Printf("[google-play] test endpoint refused: %v", err)
			return nil
		}
		v.rejectTest = sandboxDisallowed(os.Getenv("GOOGLE_PLAY_ALLOW_TEST"))
		return v
	}
	creds, err := googlePlayCredentials()
	if err != nil || creds == nil {
		if err != nil {
			log.Printf("[google-play] credentials: %v", err)
		}
		return nil
	}
	svc, err := androidpublisher.NewService(ctx, option.WithAuthCredentialsJSON(option.ServiceAccount, creds))
	if err != nil {
		log.Printf("[google-play] client: %v", err)
		return nil
	}
	v := &GooglePlayVerifier{svc: svc, packageName: pkg,
		rejectTest: sandboxDisallowed(os.Getenv("GOOGLE_PLAY_ALLOW_TEST"))}
	log.Printf("[google-play] verifier configured (package=%s test_allowed=%t)", pkg, !v.rejectTest)
	return v
}

func googlePlayCredentials() ([]byte, error) {
	if raw := strings.TrimSpace(os.Getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")); raw != "" {
		return []byte(raw), nil
	}
	path := strings.TrimSpace(os.Getenv("GOOGLE_PLAY_SERVICE_ACCOUNT_FILE"))
	if path == "" {
		return nil, nil
	}
	b, err := os.ReadFile(path)
	if err != nil {
		return nil, fmt.Errorf("read service account file: %w", err)
	}
	return b, nil
}

// newGooglePlayVerifierForEndpoint talks to a local fake of the Play API
// without credentials. Only loopback URLs are allowed so a misconfigured
// server can never send unauthenticated calls elsewhere.
func newGooglePlayVerifierForEndpoint(ctx context.Context, endpoint, pkg string) (*GooglePlayVerifier, error) {
	if !isLoopbackURL(endpoint) {
		return nil, fmt.Errorf("GOOGLE_PLAY_API_ENDPOINT must be a loopback URL, got %q", endpoint)
	}
	svc, err := androidpublisher.NewService(ctx,
		option.WithEndpoint(endpoint), option.WithoutAuthentication())
	if err != nil {
		return nil, fmt.Errorf("google-play test client: %w", err)
	}
	return &GooglePlayVerifier{svc: svc, packageName: pkg}, nil
}

func isLoopbackURL(raw string) bool {
	u, err := url.Parse(raw)
	if err != nil {
		return false
	}
	host := u.Hostname()
	if host == "localhost" {
		return true
	}
	ip := net.ParseIP(host)
	return ip != nil && ip.IsLoopback()
}

// entitledStates are the states in which the buyer still has access until
// the line item's expiry: active, a failed renewal in its grace period,
// and cancelled (auto-renew off) but not yet lapsed.
var entitledStates = map[string]bool{
	"SUBSCRIPTION_STATE_ACTIVE":          true,
	"SUBSCRIPTION_STATE_IN_GRACE_PERIOD": true,
	"SUBSCRIPTION_STATE_CANCELED":        true,
}

// Verify fetches the subscription for purchaseToken and returns the line
// item for productID. Any state without access, a different product, or
// (when disallowed) a test purchase is an error.
func (v *GooglePlayVerifier) Verify(ctx context.Context, purchaseToken, productID string) (*GoogleVerifiedSubscription, error) {
	if v == nil {
		return nil, errors.New("google-play: verifier not configured")
	}
	purchaseToken, productID = strings.TrimSpace(purchaseToken), strings.TrimSpace(productID)
	if purchaseToken == "" || productID == "" {
		return nil, errors.New("google-play: purchase token and product id required")
	}
	sub, err := v.svc.Purchases.Subscriptionsv2.Get(v.packageName, purchaseToken).Context(ctx).Do()
	if err != nil {
		log.Printf("[google-play] subscriptionsv2.get: %v", err)
		return nil, errors.New("google-play: verification failed")
	}
	if !entitledStates[sub.SubscriptionState] {
		return nil, fmt.Errorf("google-play: subscription is %s", sub.SubscriptionState)
	}
	if sub.TestPurchase != nil && v.rejectTest {
		return nil, errors.New("google-play: test purchases are not accepted")
	}
	return buildGoogleVerified(sub, purchaseToken, productID)
}

func buildGoogleVerified(sub *androidpublisher.SubscriptionPurchaseV2, token, productID string) (*GoogleVerifiedSubscription, error) {
	var item *androidpublisher.SubscriptionPurchaseLineItem
	for _, li := range sub.LineItems {
		if li != nil && li.ProductId == productID {
			item = li
			break
		}
	}
	if item == nil {
		return nil, fmt.Errorf("google-play: purchase is not for product %q", productID)
	}
	out := &GoogleVerifiedSubscription{
		PurchaseToken:       token,
		LinkedPurchaseToken: sub.LinkedPurchaseToken,
		OrderID:             sub.LatestOrderId,
		ProductID:           item.ProductId,
		State:               sub.SubscriptionState,
		Test:                sub.TestPurchase != nil,
		Acknowledged:        sub.AcknowledgementState == "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED",
	}
	if exp, err := time.Parse(time.RFC3339, item.ExpiryTime); err == nil {
		exp = exp.UTC()
		out.ExpiresDate = &exp
	}
	if start, err := time.Parse(time.RFC3339, sub.StartTime); err == nil {
		out.PurchaseDate = start.UTC()
	} else {
		out.PurchaseDate = time.Now().UTC()
	}
	raw, err := sub.MarshalJSON()
	if err != nil {
		return nil, fmt.Errorf("google-play: encode payload: %w", err)
	}
	out.RawPayload = raw
	return out, nil
}

// Acknowledge confirms the purchase to Google. Required within three days
// (the app also acknowledges via completePurchase; doing it twice is fine).
func (v *GooglePlayVerifier) Acknowledge(ctx context.Context, productID, purchaseToken string) error {
	if v == nil {
		return errors.New("google-play: verifier not configured")
	}
	err := v.svc.Purchases.Subscriptions.Acknowledge(v.packageName, productID, purchaseToken,
		&androidpublisher.SubscriptionPurchasesAcknowledgeRequest{}).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("google-play: acknowledge: %w", err)
	}
	return nil
}

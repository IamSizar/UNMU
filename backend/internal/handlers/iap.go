package handlers

import (
	"errors"
	"fmt"
	"log"
	"net/http"
	"strings"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// IAPHandler owns the in-app-purchase verification endpoints. Today it
// only knows about Apple (StoreKit) — Google Play / Stripe can plug in
// the same shape later.
type IAPHandler struct {
	appleVerifier *services.AppleIAPVerifier // nullable
	appleTxRepo   *repositories.AppleIAPTransactionRepository
	expertSubRepo *repositories.ExpertSubscriptionRepository
	userRepo      *repositories.UserRepository
	// Google Play (wired by SetGooglePlay; nil → 503).
	googleVerifier *services.GooglePlayVerifier
	googleRepo     *repositories.GooglePlayPurchaseRepository
	// Tier products for expert/community access (SetAccessGrants; nil → 503).
	grantRepo *repositories.StoreAccessGrantRepository
}

func NewIAPHandler(
	appleVerifier *services.AppleIAPVerifier,
	appleTxRepo *repositories.AppleIAPTransactionRepository,
	expertSubRepo *repositories.ExpertSubscriptionRepository,
	userRepo *repositories.UserRepository,
) *IAPHandler {
	return &IAPHandler{
		appleVerifier: appleVerifier,
		appleTxRepo:   appleTxRepo,
		expertSubRepo: expertSubRepo,
		userRepo:      userRepo,
	}
}

// verifyAppleBody — request shape for POST /me/iap/apple/verify.
//
//	receiptData — the base64 receipt blob the Flutter `in_app_purchase`
//	              plugin gives us via verificationData.serverVerificationData.
//	productId   — the SKU the user just bought (e.g.
//	              "com.unmu.expert.<expertId>.monthly"). Required: we pick
//	              the latest transaction for exactly this product.
//	expertId    — optional. The expert always comes from the verified
//	              SKU; when sent, it must match that SKU or the request
//	              is refused (it used to be trusted as-is, so buying one
//	              expert's subscription could unlock another's).
type verifyAppleBody struct {
	ReceiptData string `json:"receiptData" binding:"required"`
	ProductID   string `json:"productId"`
	ExpertID    string `json:"expertId"`
}

// VerifyApple — POST /api/me/iap/apple/verify
//
// Hits Apple's verifyReceipt endpoint (auto-falls back to sandbox), then
// (a) persists the transaction for idempotency / audit, and (b) flips
// the user's matching expert_subscription to active when expertId is set.
//
// Returns 503 when APPLE_IAP_SHARED_SECRET isn't configured on the
// server — same graceful-degrade pattern as /admin/push/send.
func (h *IAPHandler) VerifyApple(c *gin.Context) {
	if h.appleVerifier == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "Apple IAP not configured (set APPLE_IAP_SHARED_SECRET " +
				"in backend/.env from App Store Connect → My Apps → " +
				"In-App Purchases → App-Specific Shared Secret)",
		})
		return
	}

	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		// Auth middleware should have caught this — defensive 401.
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	var body verifyAppleBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	body.ReceiptData = strings.TrimSpace(body.ReceiptData)
	if body.ReceiptData == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "receiptData required"})
		return
	}

	body.ProductID = strings.TrimSpace(body.ProductID)
	body.ExpertID = strings.TrimSpace(body.ExpertID)
	if err := checkVerifyRequest(body.ProductID, body.ExpertID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	verified, err := h.appleVerifier.VerifyReceipt(
		c.Request.Context(),
		body.ReceiptData,
		body.ProductID,
	)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Persist (or fetch existing) for idempotency.
	tx, inserted, err := h.appleTxRepo.Upsert(
		userID,
		verified.TransactionID,
		verified.OriginalTransactionID,
		verified.ProductID,
		verified.Environment,
		verified.PurchaseDate,
		verified.ExpiresDate,
		verified.RawPayload,
	)
	// Replay protection: the subscription (original_transaction_id)
	// belongs to the first account that verified it, renewals included.
	if errors.Is(err, repositories.ErrAppleSubOwnedByAnotherUser) {
		c.JSON(http.StatusConflict, gin.H{
			"error": "This receipt belongs to another account.",
			"code":  "RECEIPT_OWNED_BY_ANOTHER_USER",
		})
		return
	}
	if err != nil {
		log.Printf("[apple-iap] persist transaction for user %d: %v", userID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save the purchase"})
		return
	}

	proActivated := h.grantEntitlements(userID, appleEntitlement(verified),
		models.PaymentMethodAppleIAP, "apple_iap:"+intToStr(tx.ID))

	response := gin.H{
		"id":            tx.ID,
		"transactionId": tx.TransactionID,
		"productId":     tx.ProductID,
		"environment":   tx.Environment,
		"purchaseDate":  tx.PurchaseDate,
		"expiresDate":   tx.ExpiresDate,
		"new":           inserted,
	}
	if proActivated != nil {
		response["proActivated"] = *proActivated
	}
	c.JSON(http.StatusOK, response)
}

// activateExpertSubscription activates (or, on renewal, extends) the
// user's subscription to expertID. The cash/FIB flow creates a "pending"
// row that an admin approves; a store purchase is already paid, so the sub
// is immediately active. paymentRef points at the stored store record
// ("apple_iap:<row id>" / "google_play:<row id>") for the admin dashboard.
func (h *IAPHandler) activateExpertSubscription(
	userID int64,
	expertID string,
	e storeEntitlement,
	paymentMethod, paymentRef string,
) error {
	// Same rule as Premium: an expired (or expiry-less) purchase must not
	// re-activate a subscription.
	if err := requireCurrentSubscription(e); err != nil {
		return err
	}
	// Map product → plan. Convention: SKUs end in ".monthly" / ".yearly".
	plan := models.PlanMonthly
	if strings.HasSuffix(strings.ToLower(e.ProductID), ".yearly") {
		plan = models.PlanYearly
	}
	return h.expertSubRepo.ActivateFromIAP(
		userID, expertID,
		string(plan),
		paymentMethod,
		paymentRef,
		e.PurchaseDate,
		e.ExpiresDate,
	)
}

// proProductIDs are the SKUs for the general app-wide Premium tier,
// defined client-side in lib/services/iap_service.dart
// (IAPService.monthlySubscriptionId/annualSubscriptionId). Kept as an
// explicit allowlist rather than a substring/suffix heuristic (like
// activateExpertSubscription's ".monthly"/".yearly" check) because this
// path writes directly to users.subscription_tier — a typo'd pattern
// match here would silently grant or deny Premium to every purchaser.
var proProductIDs = map[string]bool{
	"com.unmu.premium.monthly": true,
	"com.unmu.premium.yearly":  true,
}

func isProProductID(productID string) bool {
	return proProductIDs[strings.ToLower(strings.TrimSpace(productID))]
}

// activateProSubscription grants the app-wide Premium tier after Apple
// has verified the purchase — the counterpart to activateExpertSubscription
// for the general (non-expert-scoped) Pro tier.
//
// A verified receipt only proves the receipt is authentic, NOT that the
// subscription period it describes is still current — Apple's
// verifyReceipt endpoint has no separate "is this active right now"
// flag, and pickLatestTransaction (internal/services/apple_iap_verifier.go)
// doesn't check expiry either. Without an explicit check here, a user
// could replay their own old, now-expired-or-cancelled receipt at any
// time to re-grant themselves Premium indefinitely. So: reject (as a
// no-op, not an error — the payment WAS real, just not current) any
// transaction whose ExpiresDate has already passed.
//
// SHARIAH-REVIEW: N/A (not a fiqh question) but flagged for product
// awareness — this only handles the ACTIVATION path, gated by the expiry
// check above. There is still no corresponding downgrade-on-expiry job:
// if a subscription lapses (cancelled, payment failed) without a fresh
// verify call, subscription_status stays "ACTIVE" until whatever
// end_date was last recorded passes — there's no proactive sweep that
// flips it to EXPIRED the moment it lapses. Apple's App Store Server
// Notifications (a webhook, not implemented here) is the standard way to
// learn about cancellations without waiting for the client to call this
// endpoint again; until that exists, entitlement freshness depends on
// the client re-verifying periodically, not on the backend knowing
// proactively.
func (h *IAPHandler) activateProSubscription(userID int64, e storeEntitlement) error {
	if err := requireCurrentSubscription(e); err != nil {
		return err
	}
	return h.userRepo.UpdateSubscription(userID, "PREMIUM", "ACTIVE", e.ExpiresDate)
}

// requireCurrentSubscription refuses a receipt whose subscription has
// expired, or whose expiry Apple did not report (every UNMU product is a
// subscription, so a missing expiry means we cannot tell it is current).
// Without it, an old receipt could be replayed to re-grant access forever.
func requireCurrentSubscription(e storeEntitlement) error {
	if e.ExpiresDate == nil {
		return fmt.Errorf("iap: purchase of %s has no expiry date", e.ProductID)
	}
	if e.ExpiresDate.Before(timeNow()) {
		return fmt.Errorf("iap: purchase of %s expired at %s",
			e.ProductID, e.ExpiresDate.Format(time.RFC3339))
	}
	return nil
}

// Expert SKUs are com.unmu.expert.<expertId>.<plan>, matching
// IAPService.expertIdFromProductId in the Flutter app.
const expertSKUPrefix = "com.unmu.expert."

var expertSKUPlans = []string{".monthly", ".yearly"}

// expertIDFromProductID returns the expert id inside an expert SKU, or ""
// for any other product.
func expertIDFromProductID(productID string) string {
	rest, ok := strings.CutPrefix(productID, expertSKUPrefix)
	if !ok {
		return ""
	}
	for _, plan := range expertSKUPlans {
		if id, found := strings.CutSuffix(rest, plan); found {
			return id
		}
	}
	return ""
}

// checkVerifyRequest validates the client's productId / expertId before
// calling Apple: the product is required, and an expertId must be the one
// inside that product's SKU.
func checkVerifyRequest(productID, expertID string) error {
	if productID == "" {
		return errors.New("productId required")
	}
	if expertID != "" && expertID != expertIDFromProductID(productID) {
		return errors.New("expertId does not match the purchased product")
	}
	return nil
}

// timeNow — a var, not a direct time.Now() call, so a future test can
// stub "now" without needing a full clock-injection refactor of this
// handler.
var timeNow = time.Now

// intToStr — tiny helper to avoid pulling strconv into the import set
// twice (the package already uses it via gin).
func intToStr(i int64) string {
	if i == 0 {
		return "0"
	}
	neg := false
	if i < 0 {
		neg = true
		i = -i
	}
	var buf [20]byte
	pos := len(buf)
	for i > 0 {
		pos--
		buf[pos] = byte('0' + i%10)
		i /= 10
	}
	if neg {
		pos--
		buf[pos] = '-'
	}
	return string(buf[pos:])
}

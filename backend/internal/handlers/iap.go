package handlers

import (
	"fmt"
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
	appleVerifier *services.AppleIAPVerifier   // nullable
	appleTxRepo   *repositories.AppleIAPTransactionRepository
	expertSubRepo *repositories.ExpertSubscriptionRepository
	userRepo      *repositories.UserRepository
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
//	              "com.unmu.expert.<expertId>.monthly"). Optional but
//	              recommended — we pick the latest matching transaction
//	              when set, else the latest of any product in the receipt.
//	expertId    — when the SKU represents an expert subscription, the
//	              expert UUID to attach the resulting expert_subscription
//	              row to. Optional — when omitted we just persist the
//	              transaction without creating a subscription row (the
//	              client can call /experts/:id/subscriptions separately).
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

	verified, err := h.appleVerifier.VerifyReceipt(
		c.Request.Context(),
		body.ReceiptData,
		strings.TrimSpace(body.ProductID),
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
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error": "Failed to persist transaction: " + err.Error(),
		})
		return
	}

	// Replay protection: if this transaction belongs to a different user,
	// refuse. (Could happen if a leaked receipt is re-used by an
	// attacker.) When inserted=false we already had a row — verify owner.
	if !inserted && tx.UserID != userID {
		c.JSON(http.StatusConflict, gin.H{
			"error": "This receipt belongs to another account.",
			"code":  "RECEIPT_OWNED_BY_ANOTHER_USER",
		})
		return
	}

	// If an expertId is present and looks like an expert subscription,
	// activate the matching sub. Mapping is intentionally loose — the
	// product ID is whatever the operator set up in App Store Connect.
	if expertID := strings.TrimSpace(body.ExpertID); expertID != "" {
		_ = h.activateExpertSubscription(userID, expertID, verified, tx.ID)
	}
	// proActivated distinguishes "not a Pro SKU" from "was a Pro SKU but
	// activation failed" from "activated successfully", so the Flutter
	// client can tell the difference instead of assuming success just
	// because the HTTP call returned 200 — a verified-but-unactivated
	// purchase should prompt a retry, not silently show as Premium only
	// after the user happens to reload.
	var proActivated *bool
	if isProProductID(verified.ProductID) {
		// The general app-wide Pro tier — see activateProSubscription's
		// doc comment. This was the one gap that made the whole feature a
		// no-op end to end: the Flutter purchase screen and the real IAP
		// wiring both already existed, but nothing on this side ever
		// called UserRepository.UpdateSubscription, so a completed
		// purchase never actually granted Premium.
		ok := true
		if err := h.activateProSubscription(userID, verified); err != nil {
			ok = false
			// Best-effort, matching activateExpertSubscription's pattern:
			// the payment is already verified and the transaction is
			// already persisted above, so we don't fail the whole request
			// over an entitlement-write error — but it IS worth knowing
			// about, since it means a paying user doesn't get Premium.
			services.CaptureError(err, map[string]string{
				"handler": "iap.VerifyApple", "stage": "activate_pro",
			})
		}
		proActivated = &ok
	}

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

// activateExpertSubscription is best-effort. The cash/FIB flow already
// creates a "pending" expert_subscription row that admin approves; the
// IAP flow short-circuits that — Apple verified the payment, so the sub
// is immediately active.
//
// If no pending subscription exists yet, the client is expected to also
// POST /experts/:id/subscriptions with paymentMethod=apple_iap (which
// will reference this transaction). We don't auto-create one here to
// keep the data model simple.
func (h *IAPHandler) activateExpertSubscription(
	userID int64,
	expertID string,
	verified *services.AppleVerifiedTransaction,
	appleTxRowID int64,
) error {
	// Map product → plan. Convention: SKUs end in ".monthly" / ".yearly".
	plan := models.PlanMonthly
	if strings.HasSuffix(strings.ToLower(verified.ProductID), ".yearly") {
		plan = models.PlanYearly
	}
	// We use payment_ref to carry the apple transaction PK so the admin
	// dashboard can drill in. Format: "apple_iap:<row id>".
	paymentRef := "apple_iap:" + intToStr(appleTxRowID)
	return h.expertSubRepo.ActivateFromIAP(
		userID, expertID,
		string(plan),
		models.PaymentMethodAppleIAP,
		paymentRef,
		verified.PurchaseDate,
		verified.ExpiresDate,
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
func (h *IAPHandler) activateProSubscription(userID int64, verified *services.AppleVerifiedTransaction) error {
	// Every SKU that reaches here (isProProductID's allowlist) is a
	// subscription product, so ExpiresDate should always be populated —
	// apple_iap_verifier.go's pickLatestTransaction only leaves it nil
	// when expires_date_ms was empty, unparseable, or <= 0. Treat that as
	// "can't verify this purchase is current" and refuse, same as an
	// actually-expired date — the original code only checked the latter,
	// so a malformed/missing expiry from Apple silently skipped the
	// expiry gate entirely and granted Premium with no expiry at all.
	if verified.ExpiresDate == nil {
		return fmt.Errorf("apple-iap: receipt for product %s has no parseable expiry date — refusing to activate Pro without one",
			verified.ProductID)
	}
	if verified.ExpiresDate.Before(timeNow()) {
		return fmt.Errorf("apple-iap: receipt for product %s has already expired (expiresDate=%s) — not activating Pro",
			verified.ProductID, verified.ExpiresDate.Format(time.RFC3339))
	}
	return h.userRepo.UpdateSubscription(userID, "PREMIUM", "ACTIVE", verified.ExpiresDate)
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

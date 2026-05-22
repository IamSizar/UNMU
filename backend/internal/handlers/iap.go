package handlers

import (
	"net/http"
	"strings"

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

	c.JSON(http.StatusOK, gin.H{
		"id":                   tx.ID,
		"transactionId":        tx.TransactionID,
		"productId":            tx.ProductID,
		"environment":          tx.Environment,
		"purchaseDate":         tx.PurchaseDate,
		"expiresDate":          tx.ExpiresDate,
		"new":                  inserted,
	})
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

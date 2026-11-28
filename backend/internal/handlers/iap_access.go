// iap_access.go — buying access to an expert or a community with a tier
// product (com.unmu.access.<tier>.<month|year>), the only way to pay for
// them since cash/FIB were cut off. See docs/payments/IAP_ONLY_PLAN.md.
//
//	POST /api/me/iap/access/apple   {receiptData, productId, transactionId, targetType, targetId}
//	POST /api/me/iap/access/google  {purchaseToken, productId, targetType, targetId}
//
// The app buys the target's current tier. If the tier changed between
// checkout and verification, the paid purchase is still honoured with
// days pro-rated to the current price (never refused: the buyer has paid).
// Each store transaction grants once (store_access_grants); sending it
// again for the same target answers 200 with alreadyApplied, for anything
// else 409.
package handlers

import (
	"context"
	"database/sql"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// SetAccessGrants wires the tier-product endpoints (nil → 503).
func (h *IAPHandler) SetAccessGrants(repo *repositories.StoreAccessGrantRepository) {
	h.grantRepo = repo
}

// accessTarget is the part shared by both store requests.
type accessTarget struct {
	ProductID  string `json:"productId"`
	TargetType string `json:"targetType"`
	TargetID   string `json:"targetId"`
}

type accessAppleBody struct {
	accessTarget
	ReceiptData   string `json:"receiptData"`
	TransactionID string `json:"transactionId"`
}

type accessGoogleBody struct {
	accessTarget
	PurchaseToken string `json:"purchaseToken"`
}

// accessPurchase is a checked request: what was bought and for whom.
type accessPurchase struct {
	userID      int64
	tier, plan  string // bought
	currentTier string // the target's tier now
	target      accessTarget
}

// grantDays is the plan length, pro-rated down when the buyer paid a
// cheaper tier than the target's current one (minimum one day).
func (p *accessPurchase) grantDays() int {
	full := int(models.DurationForPlan(p.plan) / (24 * time.Hour))
	paid := models.TierPriceCents(p.tier, p.plan)
	current := models.TierPriceCents(p.currentTier, p.plan)
	if current <= 0 || paid >= current {
		return full
	}
	return max(1, full*paid/current)
}

// httpError carries a status and message back to the gin handler.
type httpError struct {
	status int
	msg    string
	code   string
}

func (e *httpError) Error() string { return e.msg }

func (e *httpError) write(c *gin.Context) {
	body := gin.H{"error": e.msg}
	if e.code != "" {
		body["code"] = e.code
	}
	c.JSON(e.status, body)
}

// checkAccessRequest validates the target and product against the
// target's current tier, before any store call.
func (h *IAPHandler) checkAccessRequest(ctx context.Context, userID int64, t accessTarget) (*accessPurchase, *httpError) {
	t.ProductID, t.TargetType, t.TargetID = strings.TrimSpace(t.ProductID), strings.TrimSpace(t.TargetType), strings.TrimSpace(t.TargetID)
	if t.TargetType != repositories.GrantTargetExpert && t.TargetType != repositories.GrantTargetCommunity {
		return nil, &httpError{status: http.StatusBadRequest, msg: "targetType must be expert or community"}
	}
	if t.TargetID == "" {
		return nil, &httpError{status: http.StatusBadRequest, msg: "targetId required"}
	}
	tier, plan, ok := models.ParseAccessProductID(t.ProductID)
	if !ok {
		return nil, &httpError{status: http.StatusBadRequest, msg: "productId is not an access product"}
	}
	storedID, current, err := h.grantRepo.TargetPriceTier(ctx, t.TargetType, t.TargetID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, &httpError{status: http.StatusNotFound, msg: t.TargetType + " not found"}
	}
	if err != nil {
		log.Printf("[iap-access] tier lookup %s %s: %v", t.TargetType, t.TargetID, err)
		return nil, &httpError{status: http.StatusInternalServerError, msg: "Failed to check the price"}
	}
	// current == "": the community turned free during checkout. The buyer
	// has paid, so the purchase is still honoured (grantDays: full length).
	t.TargetID = storedID // the id as stored, so a retry always matches the grant
	return &accessPurchase{userID: userID, tier: tier, plan: plan, currentTier: current, target: t}, nil
}

// applyGrant records the purchase and answers the request.
func (h *IAPHandler) applyGrant(c *gin.Context, p *accessPurchase, g repositories.StoreGrant) bool {
	g.UserID, g.TargetType, g.TargetID = p.userID, p.target.TargetType, p.target.TargetID
	g.ProductID, g.Plan, g.Days = p.target.ProductID, p.plan, p.grantDays()
	g.PriceCents = models.TierPriceCents(p.tier, p.plan)
	expires, err := h.grantRepo.Grant(c.Request.Context(), g)
	already := errors.Is(err, repositories.ErrGrantAlreadyApplied)
	switch {
	case already:
	case errors.Is(err, repositories.ErrGrantUsedElsewhere):
		c.JSON(http.StatusConflict, gin.H{"error": "This purchase was already used.", "code": "PURCHASE_ALREADY_USED"})
		return false
	case err != nil:
		services.CaptureError(err, map[string]string{"handler": "iap_access", "store": g.Store})
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Payment verified but access could not be granted. Please contact support."})
		return false
	}
	resp := gin.H{"targetType": g.TargetType, "targetId": g.TargetID, "alreadyApplied": already}
	if !already {
		resp["expiresAt"] = expires.UTC().Format(time.RFC3339)
	}
	c.JSON(http.StatusOK, resp)
	return true
}

// accessUser returns the caller, or answers 503/401 and returns 0.
func (h *IAPHandler) accessUser(c *gin.Context, storeReady bool) int64 {
	if !storeReady || h.grantRepo == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "In-app purchases are not configured on the server"})
		return 0
	}
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
	}
	return userID
}

// BuyAccessApple — POST /api/me/iap/access/apple
func (h *IAPHandler) BuyAccessApple(c *gin.Context) {
	userID := h.accessUser(c, h.appleVerifier != nil)
	if userID == 0 {
		return
	}
	var body accessAppleBody
	if err := c.ShouldBindJSON(&body); err != nil || strings.TrimSpace(body.ReceiptData) == "" || strings.TrimSpace(body.TransactionID) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "receiptData and transactionId required"})
		return
	}
	p, herr := h.checkAccessRequest(c.Request.Context(), userID, body.accessTarget)
	if herr != nil {
		herr.write(c)
		return
	}
	v, err := h.appleVerifier.VerifyReceiptTransaction(c.Request.Context(), body.ReceiptData, p.target.ProductID, body.TransactionID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	row, _, err := h.appleTxRepo.Upsert(userID, v.TransactionID, v.OriginalTransactionID,
		v.ProductID, v.Environment, v.PurchaseDate, v.ExpiresDate, v.RawPayload)
	if errors.Is(err, repositories.ErrAppleSubOwnedByAnotherUser) {
		c.JSON(http.StatusConflict, gin.H{"error": "This receipt belongs to another account.", "code": "RECEIPT_OWNED_BY_ANOTHER_USER"})
		return
	}
	if err != nil {
		log.Printf("[iap-access] persist apple transaction for user %d: %v", userID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save the purchase"})
		return
	}
	h.applyGrant(c, p, repositories.StoreGrant{Store: "apple", TransactionRef: v.TransactionID,
		PaymentMethod: models.PaymentMethodAppleIAP, PaymentRef: "apple_iap:" + intToStr(row.ID)})
}

// BuyAccessGoogle — POST /api/me/iap/access/google
func (h *IAPHandler) BuyAccessGoogle(c *gin.Context) {
	userID := h.accessUser(c, h.googleVerifier != nil)
	if userID == 0 {
		return
	}
	var body accessGoogleBody
	if err := c.ShouldBindJSON(&body); err != nil || strings.TrimSpace(body.PurchaseToken) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "purchaseToken required"})
		return
	}
	p, herr := h.checkAccessRequest(c.Request.Context(), userID, body.accessTarget)
	if herr != nil {
		herr.write(c)
		return
	}
	ctx := c.Request.Context()
	v, err := h.googleVerifier.VerifyProduct(ctx, body.PurchaseToken, p.target.ProductID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	granted := h.applyGrant(c, p, repositories.StoreGrant{Store: "google", TransactionRef: v.PurchaseToken,
		PaymentMethod: models.PaymentMethodGoogleIAP, PaymentRef: "google_play:" + v.OrderID})
	if granted && !v.Consumed {
		if err := h.googleVerifier.ConsumeProduct(ctx, v.ProductID, v.PurchaseToken); err != nil {
			services.CaptureError(err, map[string]string{"handler": "iap_access", "stage": "consume"})
		}
	}
}

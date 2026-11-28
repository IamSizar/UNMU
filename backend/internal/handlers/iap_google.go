package handlers

import (
	"context"
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

// storeEntitlement is the store-neutral part of a verified purchase that
// the activation code needs (Apple receipt or Google Play subscription).
type storeEntitlement struct {
	ProductID    string
	PurchaseDate time.Time
	ExpiresDate  *time.Time
}

func appleEntitlement(v *services.AppleVerifiedTransaction) storeEntitlement {
	return storeEntitlement{ProductID: v.ProductID, PurchaseDate: v.PurchaseDate, ExpiresDate: v.ExpiresDate}
}

// grantEntitlements activates whatever the verified product unlocks: an
// expert subscription (expert read from the SKU) or app-wide Premium.
// Returns proActivated for Premium SKUs (nil otherwise) so the app can
// tell "verified but not activated" from success and retry.
func (h *IAPHandler) grantEntitlements(
	userID int64, e storeEntitlement, paymentMethod, paymentRef string,
) *bool {
	if expertID := expertIDFromProductID(e.ProductID); expertID != "" {
		err := h.activateExpertSubscription(userID, expertID, e, paymentMethod, paymentRef)
		if err != nil && !errors.Is(err, repositories.ErrActiveSubExists) {
			log.Printf("[iap] expert sub not activated (user %d, product %s): %v",
				userID, e.ProductID, err)
		}
	}
	if !isProProductID(e.ProductID) {
		return nil
	}
	ok := true
	if err := h.activateProSubscription(userID, e); err != nil {
		// The payment is verified and stored, so the request still
		// succeeds, but a paying user without Premium must be visible.
		ok = false
		services.CaptureError(err, map[string]string{
			"handler": "iap", "stage": "activate_pro", "method": paymentMethod,
		})
	}
	return &ok
}

// SetGooglePlay wires Google Play verification (nil verifier → 503).
func (h *IAPHandler) SetGooglePlay(v *services.GooglePlayVerifier, repo *repositories.GooglePlayPurchaseRepository) {
	h.googleVerifier = v
	h.googleRepo = repo
}

// verifyGoogleBody — request shape for POST /me/iap/google/verify.
// purchaseToken is PurchaseDetails.verificationData.serverVerificationData
// on Android; productId and expertId follow the Apple endpoint's rules.
type verifyGoogleBody struct {
	PurchaseToken string `json:"purchaseToken" binding:"required"`
	ProductID     string `json:"productId"`
	ExpertID      string `json:"expertId"`
}

// VerifyGoogle — POST /api/me/iap/google/verify
//
// Checks the subscription with Google Play, stores it (one owner per
// purchase-token chain), activates what it unlocks, then acknowledges it
// to Google if the app has not already done so.
func (h *IAPHandler) VerifyGoogle(c *gin.Context) {
	if h.googleVerifier == nil || h.googleRepo == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "Google Play purchases not configured (set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON)",
		})
		return
	}
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body verifyGoogleBody
	if err := c.ShouldBindJSON(&body); err != nil || strings.TrimSpace(body.PurchaseToken) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "purchaseToken required"})
		return
	}
	body.ProductID, body.ExpertID = strings.TrimSpace(body.ProductID), strings.TrimSpace(body.ExpertID)
	if err := checkVerifyRequest(body.ProductID, body.ExpertID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	verified, err := h.googleVerifier.Verify(c.Request.Context(), strings.TrimSpace(body.PurchaseToken), body.ProductID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	row, err := h.googleRepo.Upsert(googlePurchaseRow(userID, verified))
	if errors.Is(err, repositories.ErrStorePurchaseOwnedByAnotherUser) {
		c.JSON(http.StatusConflict, gin.H{
			"error": "This purchase belongs to another account.",
			"code":  "RECEIPT_OWNED_BY_ANOTHER_USER",
		})
		return
	}
	if err != nil {
		log.Printf("[google-play] persist purchase for user %d: %v", userID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save the purchase"})
		return
	}

	e := storeEntitlement{ProductID: verified.ProductID, PurchaseDate: verified.PurchaseDate, ExpiresDate: verified.ExpiresDate}
	proActivated := h.grantEntitlements(userID, e, models.PaymentMethodGoogleIAP, "google_play:"+intToStr(row.ID))
	if !verified.Acknowledged {
		h.acknowledgeGoogle(c.Request.Context(), verified)
	}

	response := gin.H{
		"id":          row.ID,
		"productId":   verified.ProductID,
		"orderId":     verified.OrderID,
		"state":       verified.State,
		"test":        verified.Test,
		"expiresDate": verified.ExpiresDate,
	}
	if proActivated != nil {
		response["proActivated"] = *proActivated
	}
	c.JSON(http.StatusOK, response)
}

// acknowledgeGoogle is best effort: the app acknowledges too, and the next
// verify retries. An unacknowledged purchase is refunded by Google after
// three days, so a failure is reported.
func (h *IAPHandler) acknowledgeGoogle(ctx context.Context, v *services.GoogleVerifiedSubscription) {
	if err := h.googleVerifier.Acknowledge(ctx, v.ProductID, v.PurchaseToken); err != nil {
		services.CaptureError(err, map[string]string{"handler": "iap.VerifyGoogle", "stage": "acknowledge"})
	}
}

func googlePurchaseRow(userID int64, v *services.GoogleVerifiedSubscription) repositories.GooglePlayPurchase {
	return repositories.GooglePlayPurchase{
		UserID:              userID,
		PurchaseToken:       v.PurchaseToken,
		LinkedPurchaseToken: v.LinkedPurchaseToken,
		OrderID:             v.OrderID,
		ProductID:           v.ProductID,
		SubscriptionState:   v.State,
		IsTest:              v.Test,
		PurchaseDate:        v.PurchaseDate,
		ExpiresDate:         v.ExpiresDate,
		RawPayload:          v.RawPayload,
	}
}

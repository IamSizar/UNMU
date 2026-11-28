// apple_notifications.go — App Store Server Notifications v2 webhook.
//
//	POST /api/webhooks/apple/notifications  {"signedPayload": "<JWS>"}
//
// Public (Apple calls it); trust comes only from the signature check in
// services.AppleNotificationVerifier. A REFUND or REVOKE of a tier
// product takes back what the purchase granted. Any non-2xx makes Apple
// retry, so failures to apply a refund answer 500. Every other type is
// acknowledged and ignored. See docs/payments/REFUNDS_PLAN.md.
package handlers

import (
	"context"
	"log"
	"net/http"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// appleNotificationParser is the verifier (an interface for tests).
type appleNotificationParser interface {
	Parse(signedPayload string) (*services.AppleNotification, error)
}

// storeRefunder applies a refund (StoreAccessGrantRepository.Revoke).
type storeRefunder interface {
	Revoke(ctx context.Context, store, transactionRef string) (repositories.RevokeResult, error)
}

// AppleNotificationsHandler handles the webhook.
type AppleNotificationsHandler struct {
	parser   appleNotificationParser
	refunder storeRefunder
}

// NewAppleNotificationsHandler builds the handler.
func NewAppleNotificationsHandler(p appleNotificationParser, r storeRefunder) *AppleNotificationsHandler {
	return &AppleNotificationsHandler{parser: p, refunder: r}
}

// maxAppleNotificationBytes caps the public body (real ones are ~10 KB).
const maxAppleNotificationBytes = 64 << 10

// appleRefundTypes take access back.
var appleRefundTypes = map[string]bool{"REFUND": true, "REVOKE": true}

// Receive — POST /api/webhooks/apple/notifications
func (h *AppleNotificationsHandler) Receive(c *gin.Context) {
	c.Request.Body = http.MaxBytesReader(c.Writer, c.Request.Body, maxAppleNotificationBytes)
	var body struct {
		SignedPayload string `json:"signedPayload"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.SignedPayload == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "signedPayload required"})
		return
	}
	n, err := h.parser.Parse(body.SignedPayload)
	if err != nil {
		log.Printf("[apple-notifications] rejected: %v", err)
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid notification"})
		return
	}
	txn := n.Transaction
	if txn == nil {
		c.Status(http.StatusOK)
		return
	}
	if _, _, isAccess := models.ParseAccessProductID(txn.ProductID); !isAccess {
		c.Status(http.StatusOK)
		return
	}
	if n.Type == "REFUND_REVERSED" {
		log.Printf("[apple-notifications] refund reversed for transaction %s; re-grant by hand if needed", txn.TransactionID)
	}
	if !appleRefundTypes[n.Type] {
		c.Status(http.StatusOK)
		return
	}
	res, err := h.refunder.Revoke(c.Request.Context(), "apple", txn.TransactionID)
	if err != nil {
		services.CaptureError(err, map[string]string{"handler": "apple_notifications", "type": n.Type})
		c.JSON(http.StatusInternalServerError, gin.H{"error": "refund not applied"})
		return
	}
	log.Printf("[apple-notifications] %s %s (%s): %s", n.Type, txn.TransactionID, n.Environment, res)
	c.Status(http.StatusOK)
}

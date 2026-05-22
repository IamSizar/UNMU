package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// PayoutsHandler — Phase 3.4.
//
// Two surfaces:
//   * Expert (auth-gated): request / list / cancel own payouts.
//   * Admin (admin-gated): list pending queue, mark paid, reject.
//
// Methods accepted on creation: "bank" | "fib" | "paypal" | "other".
// The payment-details JSONB is operator-readable free-form so we can
// support every region's preferred channel without DDL churn.
type PayoutsHandler struct {
	payouts *repositories.PayoutsRepository
	subs    *repositories.ExpertSubscriptionRepository
	users   *repositories.UserRepository
	audits  *repositories.AuditRepository
}

func NewPayoutsHandler(
	payouts *repositories.PayoutsRepository,
	subs *repositories.ExpertSubscriptionRepository,
	users *repositories.UserRepository,
	audits *repositories.AuditRepository,
) *PayoutsHandler {
	return &PayoutsHandler{payouts: payouts, subs: subs, users: users, audits: audits}
}

var allowedPayoutMethods = map[string]bool{
	"bank":   true,
	"fib":    true,
	"paypal": true,
	"other":  true,
}

// resolveExpertSelf — ensures the caller is an expert and returns
// (userID, expertID).
func (h *PayoutsHandler) resolveExpertSelf(c *gin.Context) (int64, string, bool) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return 0, "", false
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return 0, "", false
	}
	if !user.ExpertID.Valid || strings.TrimSpace(user.ExpertID.String) == "" {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "Only experts can request payouts.",
			"code":  "NOT_EXPERT",
		})
		return 0, "", false
	}
	return userID, user.ExpertID.String, true
}

// ─── /me/expert/payouts (GET + POST) ────────────────────────────────────

type payoutRequestBody struct {
	AmountCents    int            `json:"amountCents" binding:"required,min=1"`
	Method         string         `json:"method"      binding:"required"`
	PaymentDetails map[string]any `json:"paymentDetails"`
}

// RequestPayout — POST /api/me/expert/payouts/request
func (h *PayoutsHandler) RequestPayout(c *gin.Context) {
	userID, expertID, ok := h.resolveExpertSelf(c)
	if !ok {
		return
	}
	var body payoutRequestBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	method := strings.ToLower(strings.TrimSpace(body.Method))
	if !allowedPayoutMethods[method] {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "method must be bank|fib|paypal|other",
		})
		return
	}

	// Pull the expert's lifetime revenue so the repo can enforce the
	// "can't withdraw more than you've earned" rule.
	totals, err := h.subs.TotalsForExpert(expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	p, err := h.payouts.Create(
		userID, expertID,
		body.AmountCents, totals.Currency, method,
		body.PaymentDetails,
		totals.LifetimeRevenue,
	)
	if err != nil {
		if errors.Is(err, repositories.ErrInsufficientBalance) {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "Requested amount exceeds your available balance.",
				"code":  "INSUFFICIENT_BALANCE",
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, _ = h.audits.Write(
		"PAYOUT_REQUESTED", models.SeverityInfo,
		&userID, ptrStr(strconv.FormatInt(p.ID, 10)), ptrStr("payout"),
		fmt.Sprintf("user_id=%d requested payout %d for %d cents (%s, %s)",
			userID, p.ID, p.AmountCents, p.Currency, p.Method),
		map[string]any{
			"amountCents": p.AmountCents,
			"method":      p.Method,
			"currency":    p.Currency,
		},
	)

	c.JSON(http.StatusCreated, p)
}

// ListMyPayouts — GET /api/me/expert/payouts
//
// Returns the expert's history + the current available balance so
// the earnings screen can render the "Available to withdraw" tile in
// the same call.
func (h *PayoutsHandler) ListMyPayouts(c *gin.Context) {
	userID, expertID, ok := h.resolveExpertSelf(c)
	if !ok {
		return
	}
	totals, err := h.subs.TotalsForExpert(expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	available, err := h.payouts.AvailableBalance(userID, totals.LifetimeRevenue)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	limit, _ := strconv.Atoi(c.Query("limit"))
	rows, err := h.payouts.ListForUser(userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"availableCents":   available,
		"lifetimeCents":    totals.LifetimeRevenue,
		"currency":         totals.Currency,
		"payouts":          rows,
	})
}

// CancelMyPayout — POST /api/me/expert/payouts/:id/cancel
func (h *PayoutsHandler) CancelMyPayout(c *gin.Context) {
	userID, _, ok := h.resolveExpertSelf(c)
	if !ok {
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	p, err := h.payouts.CancelMine(id, userID)
	if err != nil {
		if errors.Is(err, repositories.ErrPayoutNotFound) {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "Payout not found or already processed.",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, p)
}

// ─── /admin/payouts ─────────────────────────────────────────────────────

// AdminList — GET /api/admin/payouts?status=pending
func (h *PayoutsHandler) AdminList(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	offset, _ := strconv.Atoi(c.Query("offset"))
	filter := repositories.AdminPayoutFilter{
		Status: strings.TrimSpace(c.Query("status")),
		Limit:  limit,
		Offset: offset,
	}
	rows, total, err := h.payouts.ListAdmin(filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"payouts": rows,
		"total":   total,
		"limit":   filter.Limit,
		"offset":  filter.Offset,
	})
}

// AdminPendingCount — GET /api/admin/payouts/pending-count
func (h *PayoutsHandler) AdminPendingCount(c *gin.Context) {
	n, err := h.payouts.CountPending()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

type adminResolveBody struct {
	Status string `json:"status" binding:"required"` // paid | rejected
	Note   string `json:"note"`
}

// AdminResolve — POST /api/admin/payouts/:id/resolve
//
// Flips the row to 'paid' or 'rejected'. Once flipped the row is
// read-only — re-flipping would let an admin retroactively rewrite
// history.
func (h *PayoutsHandler) AdminResolve(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	if adminID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body adminResolveBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	body.Status = strings.ToLower(strings.TrimSpace(body.Status))

	p, err := h.payouts.AdminResolve(id, adminID, body.Status, body.Note)
	if err != nil {
		if errors.Is(err, repositories.ErrPayoutNotFound) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "Payout not found or already processed.",
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	severity := models.SeverityInfo
	if body.Status == "rejected" {
		severity = models.SeverityWarning
	}
	auditTarget := strconv.FormatInt(id, 10)
	auditKind := "payout"
	_, _ = h.audits.Write(
		"PAYOUT_"+strings.ToUpper(body.Status), severity,
		&adminID, &auditTarget, &auditKind,
		fmt.Sprintf("admin_id=%d resolved payout %d as %s", adminID, id, body.Status),
		map[string]any{"status": body.Status, "note": body.Note},
	)
	c.JSON(http.StatusOK, p)
}

// _ — keeps the unused-import lint check satisfied if sql.ErrNoRows
// branches are ever removed. Defensive, costs nothing.
var _ = sql.ErrNoRows

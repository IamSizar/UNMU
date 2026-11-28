package handlers

import (
	"errors"
	"halalstocks/internal/models"
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ExpertSubscriptionHandler exposes:
//
//   user side:
//     POST   /api/experts/:id/subscribe        — create pending request
//     GET    /api/me/subscriptions             — list own subs
//     GET    /api/me/subscriptions/expert/:id  — current sub for one expert
//     DELETE /api/subscriptions/:id            — cancel
//
//   admin side:
//     GET    /api/admin/subscriptions          — list (filter by status)
type ExpertSubscriptionHandler struct {
	subs    *repositories.ExpertSubscriptionRepository
	users   *repositories.UserRepository
	experts *repositories.SocialRepository
	// hub is wired post-construction via SetHub so the handler can
	// broadcast subscription_accepted / subscription_rejected events
	// on the subscriber's user channel for in-app notifications.
	// May be nil during tests.
	hub *realtime.Hub
	// userNotifs persists subscription lifecycle events to the
	// unified inbox so they survive past the realtime snackbar and
	// show up in the user's notification history. Wired post-
	// construction via SetUserNotifications. May be nil.
	userNotifs *repositories.UserNotificationsRepository
	// notifier sends localized device pushes for lifecycle events.
	// Wired post-construction via SetNotifier. May be nil.
	notifier *services.Notifier
}

func NewExpertSubscriptionHandler(
	subs *repositories.ExpertSubscriptionRepository,
	users *repositories.UserRepository,
	experts *repositories.SocialRepository,
) *ExpertSubscriptionHandler {
	return &ExpertSubscriptionHandler{subs: subs, users: users, experts: experts}
}

// SetHub attaches the realtime hub after construction. Same setter
// pattern used elsewhere (SocialHandler.SetHub /
// SocialHandler.SetEventsRepo) so this handler's constructor
// signature stays stable across the codebase.
func (h *ExpertSubscriptionHandler) SetHub(hub *realtime.Hub) {
	h.hub = hub
}

// SetUserNotifications wires the inbox writer so subscription
// lifecycle events (active / rejected / expired) become
// persistent rows in the user's notification history, not just
// transient realtime toasts.
func (h *ExpertSubscriptionHandler) SetUserNotifications(
	repo *repositories.UserNotificationsRepository,
) {
	h.userNotifs = repo
}

// SetNotifier wires the localized push sender. Best-effort: when nil
// lifecycle events still write the inbox row but send no device push.
func (h *ExpertSubscriptionHandler) SetNotifier(n *services.Notifier) {
	h.notifier = n
}

// =============================================================================
// USER ENDPOINTS
// =============================================================================

// Subscribe — POST /api/experts/:id/subscriptions
//
// Cash and FIB were cut off (docs/payments/IAP_ONLY_PLAN.md): access is
// bought only through the App Store or Google Play, via
// POST /api/me/iap/access/apple|google. Old app versions get 410 with a
// message they can show.
func (h *ExpertSubscriptionHandler) Subscribe(c *gin.Context) {
	c.JSON(http.StatusGone, gin.H{
		"error": "Please update the app to subscribe through the App Store or Google Play.",
		"code":  "STORE_PURCHASE_REQUIRED",
	})
}

// MySubscriptions — GET /api/me/subscriptions
func (h *ExpertSubscriptionHandler) MySubscriptions(c *gin.Context) {
	userID, ok := authedUserID(c)
	if !ok {
		return
	}
	expertID := c.Query("expertId")
	subs, err := h.subs.ListMine(userID, expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if subs == nil {
		subs = []*models.ExpertSubscription{}
	}
	c.JSON(http.StatusOK, gin.H{"subscriptions": subs})
}

// MySubscriptionForExpert — GET /api/me/subscriptions/expert/:id
//
// Returns the most-recent subscription for the current user/expert pair, or
// `{ "status": "none" }` when none exists. Lets the Flutter expert profile
// render the right CTA without paginating through the full list.
func (h *ExpertSubscriptionHandler) MySubscriptionForExpert(c *gin.Context) {
	userID, ok := authedUserID(c)
	if !ok {
		return
	}
	expertID := c.Param("id")
	subs, err := h.subs.ListMine(userID, expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(subs) == 0 {
		c.JSON(http.StatusOK, gin.H{"status": "none"})
		return
	}
	c.JSON(http.StatusOK, subs[0])
}

// Cancel — DELETE /api/subscriptions/:id
//
// Step B4 — broadcasts `subscription_cancelled` on the user's channel
// AND on the admin channel so the admin queue updates in real time,
// and writes a persistent inbox row so the user finds the event in
// their notification history.
func (h *ExpertSubscriptionHandler) Cancel(c *gin.Context) {
	userID, ok := authedUserID(c)
	if !ok {
		return
	}
	id, ok := pathID(c)
	if !ok {
		return
	}

	sub, err := h.subs.Cancel(id, userID)
	if err != nil {
		if errors.Is(err, repositories.ErrSubNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "subscription not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Realtime fan-out — let the admin queue refresh + the user's other
	// devices flip the UI without a manual reload.
	if h.hub != nil && sub != nil {
		var expertName string
		if e, _ := h.experts.GetExpert(sub.ExpertID); e != nil {
			expertName = e.Name
		}
		payload := gin.H{
			"subscriptionId": sub.ID,
			"expertId":       sub.ExpertID,
			"expertName":     expertName,
			"status":         sub.Status,
		}
		h.hub.PublishJSON(realtime.ChannelUser(sub.UserID), "subscription_cancelled", payload)
		h.hub.PublishJSON(realtime.ChannelAdmin, "subscription_cancelled", payload)
	}
	// Persistent inbox row.
	if h.userNotifs != nil && sub != nil {
		var expertName string
		if e, _ := h.experts.GetExpert(sub.ExpertID); e != nil {
			expertName = e.Name
		}
		_ = h.userNotifs.Insert(
			sub.UserID,
			"subscription_cancelled",
			nil,
			expertName,
			"Your subscription was cancelled.",
			nil,
		)
	}
	c.JSON(http.StatusOK, sub)
}

// =============================================================================
// ADMIN ENDPOINTS
// =============================================================================

// AdminList — GET /api/admin/subscriptions
//
// Query params:
//   ?status=pending|active|rejected|cancelled|expired
//   ?paymentMethod=cash|fib
//   ?q=<email/name/expert>
//   ?cursor=<lastId>      — keyset pagination by id-desc
//   ?limit=<n>            — clamped to [1, 100], default 50
func (h *ExpertSubscriptionHandler) AdminList(c *gin.Context) {
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	switch status {
	case "", models.SubStatusPending, models.SubStatusActive,
		models.SubStatusRejected, models.SubStatusCancelled, models.SubStatusExpired:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status filter"})
		return
	}
	method := strings.ToLower(strings.TrimSpace(c.Query("paymentMethod")))
	switch method {
	case "", models.PaymentMethodCash, models.PaymentMethodFIB:
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid paymentMethod filter"})
		return
	}
	limit := 50
	if s := c.Query("limit"); s != "" {
		if v, err := strconv.Atoi(s); err == nil {
			limit = v
		}
	}
	var cursor int64
	if s := c.Query("cursor"); s != "" {
		if v, err := strconv.ParseInt(s, 10, 64); err == nil {
			cursor = v
		}
	}
	subs, err := h.subs.ListByStatus(repositories.AdminSubFilter{
		Status:        status,
		Query:         c.Query("q"),
		PaymentMethod: method,
		Cursor:        cursor,
		Limit:         limit,
	})
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if subs == nil {
		subs = []*models.ExpertSubscription{}
	}
	c.JSON(http.StatusOK, gin.H{"subscriptions": subs})
}

// AdminTotals — GET /api/admin/subscriptions/totals
//
// Active count, pending count, sum of active price_cents (revenue running
// at any given moment). Drives the headline strip on the admin
// Subscriptions page so admins see "X active · $Y/period" at a glance.
func (h *ExpertSubscriptionHandler) AdminTotals(c *gin.Context) {
	t, err := h.subs.AdminTotals()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, t)
}

// AdminGet — GET /api/admin/subscriptions/:id
//
// Single-row fetch for the detail-page drill-in. Returns 404 if the row
// doesn't exist. The detail page uses this on mount + after every
// Accept / Reject so the screen stays coherent with the DB.
func (h *ExpertSubscriptionHandler) AdminGet(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	sub, err := h.subs.AdminGetByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if sub == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "subscription not found"})
		return
	}
	c.JSON(http.StatusOK, sub)
}

// AdminPendingCount — GET /api/admin/subscriptions/pending-count
//
// Cheap endpoint for the sidebar badge.
func (h *ExpertSubscriptionHandler) AdminPendingCount(c *gin.Context) {
	n, err := h.subs.CountPending()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// subscriberDisplayName resolves a user's display name (name, falling
// back to email) for use in another user's notification.
func subscriberDisplayName(users *repositories.UserRepository, userID int64) string {
	u, err := users.GetByID(userID)
	if err != nil || u == nil {
		return ""
	}
	if u.Name.Valid && strings.TrimSpace(u.Name.String) != "" {
		return strings.TrimSpace(u.Name.String)
	}
	return u.Email
}

// =============================================================================
// helpers (id parsing only — auth helpers are reused from expert_application.go)
// =============================================================================

// Marker to keep `strconv` used even if all call sites move into other
// helpers later. (We do use it in AdminList for cursor parsing.)
var _ = strconv.ParseInt

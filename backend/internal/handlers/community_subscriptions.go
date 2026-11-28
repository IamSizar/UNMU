package handlers

import (
	"errors"
	"net/http"
	"strconv"
	"strings"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// CommunitySubscriptionsHandler — REST surface for paid community
// memberships (mig 0022 + audit/notify hardening in mig 0025).
//
// Mirrors the expert subscription handler so the user + admin flows
// feel consistent. Step-C of the Subscriptions audit:
//   * Persistent inbox rows on every state change (`SetUserNotifications`).
//   * Realtime fan-out to user + admin + community channels.
//   * Typed 409 codes so the front-end can react cleanly.
//   * AdminList accepts query / paymentMethod / cursor / limit.
//   * AdminTotals returns active count + pending count + revenue.
//   * AdminListForUser exposes "view this user's other community subs".
type CommunitySubscriptionsHandler struct {
	subs       *repositories.CommunitySubscriptionsRepository
	social     *repositories.SocialRepository
	users      *repositories.UserRepository
	hub        *realtime.Hub
	userNotifs *repositories.UserNotificationsRepository // optional, set via SetUserNotifications
	notifier   *services.Notifier                        // optional, set via SetNotifier
}

func NewCommunitySubscriptionsHandler(
	subs *repositories.CommunitySubscriptionsRepository,
	social *repositories.SocialRepository,
	users *repositories.UserRepository,
	hub *realtime.Hub,
) *CommunitySubscriptionsHandler {
	return &CommunitySubscriptionsHandler{
		subs: subs, social: social, users: users, hub: hub,
	}
}

// SetUserNotifications — wire the inbox writer post-construction. Best-
// effort: when nil the handler still works, lifecycle events just don't
// land in the user's notification history.
func (h *CommunitySubscriptionsHandler) SetUserNotifications(
	repo *repositories.UserNotificationsRepository,
) {
	h.userNotifs = repo
}

// SetNotifier — wire the push sender post-construction. Best-effort:
// when nil (or push transport unconfigured) lifecycle events still write
// the inbox row, they just don't fan out a localized device push.
func (h *CommunitySubscriptionsHandler) SetNotifier(n *services.Notifier) {
	h.notifier = n
}

// =============================================================================
// User endpoints
// =============================================================================

// Subscribe — POST /api/communities/:id/subscribe
//
// Cash and FIB were cut off (docs/payments/IAP_ONLY_PLAN.md): access is
// bought only through the App Store or Google Play, via
// POST /api/me/iap/access/apple|google. Old app versions get 410 with a
// message they can show.
func (h *CommunitySubscriptionsHandler) Subscribe(c *gin.Context) {
	c.JSON(http.StatusGone, gin.H{
		"error": "Please update the app to subscribe through the App Store or Google Play.",
		"code":  "STORE_PURCHASE_REQUIRED",
	})
}

// MySubscriptions — GET /api/me/community-subscriptions
//
// Auth required. Returns the caller's full subscription history,
// newest-first. Drives the social hub's "Pending payment" sub-section
// + the user's own subscription list.
func (h *CommunitySubscriptionsHandler) MySubscriptions(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	rows, err := h.subs.ListMine(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []*repositories.CommunitySubscription{}
	}
	c.JSON(http.StatusOK, gin.H{"subscriptions": rows})
}

// Cancel — DELETE /api/community-subscriptions/:id
//
// User-initiated cancel. Flips status to cancelled and (if active)
// removes the membership row.
//
// Step C4 — broadcasts `community_subscription_cancelled` even for
// pending cancellations so the admin queue updates without refresh.
// The Cancel SQL also fires the audit + NOTIFY triggers from mig 0025
// so the persistent audit log records the change.
func (h *CommunitySubscriptionsHandler) Cancel(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	id, perr := strconv.ParseInt(c.Param("id"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	preCancel, _ := h.subs.GetByID(id)
	if err := h.subs.Cancel(id, userID); err != nil {
		if errors.Is(err, repositories.ErrCommSubNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "subscription not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// member-changed for the community channel — only fires when an
	// active sub was just cancelled (since pending subs never had a
	// member row).
	if h.hub != nil && preCancel != nil && preCancel.Status == "active" {
		h.hub.PublishJSON(
			realtime.ChannelCommunity(preCancel.CommunityID),
			"community_member_changed",
			gin.H{
				"communityId": preCancel.CommunityID,
				"userId":      preCancel.UserID,
				"change":      "removed",
			},
		)
	}
	// Persistent inbox row so cancel survives the snackbar.
	if h.userNotifs != nil && preCancel != nil {
		_ = h.userNotifs.Insert(
			preCancel.UserID,
			"community_subscription_cancelled",
			nil,
			preCancel.CommunityName,
			"Your community subscription was cancelled.",
			nil,
		)
	}
	c.JSON(http.StatusOK, gin.H{"cancelled": true})
}

// =============================================================================
// Admin endpoints
// =============================================================================

// AdminList — GET /api/admin/community-subscriptions
//
// Query:
//
//	?status=pending|active|rejected|cancelled|expired
//	?paymentMethod=cash|fib
//	?q=<email/name/community>
//	?cursor=<lastId>
//	?limit=<n>     (1..100, default 50)
func (h *CommunitySubscriptionsHandler) AdminList(c *gin.Context) {
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	switch status {
	case "", "pending", "active", "rejected", "cancelled", "expired":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status filter"})
		return
	}
	method := strings.ToLower(strings.TrimSpace(c.Query("paymentMethod")))
	switch method {
	case "", "cash", "fib":
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
	rows, err := h.subs.ListByStatus(repositories.AdminCommSubFilter{
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
	if rows == nil {
		rows = []*repositories.CommunitySubscription{}
	}
	c.JSON(http.StatusOK, gin.H{"subscriptions": rows})
}

// AdminPendingCount — GET /api/admin/community-subscriptions/pending-count
func (h *CommunitySubscriptionsHandler) AdminPendingCount(c *gin.Context) {
	n, err := h.subs.CountPending()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// AdminTotals — GET /api/admin/community-subscriptions/totals
//
// Active count, pending count, revenue running on accepted-active rows.
// Mirrors expert subs totals so the admin's mental model stays the same.
func (h *CommunitySubscriptionsHandler) AdminTotals(c *gin.Context) {
	t, err := h.subs.AdminTotals()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, t)
}

// AdminListForUser — GET /api/admin/users/:id/community-subscriptions
//
// Powers the "other subs by this user" link from the detail page (C11).
func (h *CommunitySubscriptionsHandler) AdminListForUser(c *gin.Context) {
	uid, perr := strconv.ParseInt(c.Param("id"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	rows, err := h.subs.ListForUser(uid)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []*repositories.CommunitySubscription{}
	}
	c.JSON(http.StatusOK, gin.H{"subscriptions": rows})
}

// AdminGet — GET /api/admin/community-subscriptions/:id
func (h *CommunitySubscriptionsHandler) AdminGet(c *gin.Context) {
	id, perr := strconv.ParseInt(c.Param("id"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
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


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
// Body:
//
//	{
//	  "plan":          "monthly" | "yearly",
//	  "paymentMethod": "cash" | "fib",
//	  "paymentRef":    "<optional reference>",
//	  "receiptUrl":    "<optional cash-receipt image URL>",
//	  "userNote":      "<optional note for admin>"
//	}
//
// Validates that the community has a non-zero price for the chosen
// plan, then writes a pending row. The `comm_subs_notify` trigger
// (mig 0025) fans the event out to user + admin + community channels;
// no manual hub.Publish call needed here.
func (h *CommunitySubscriptionsHandler) Subscribe(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	communityID := c.Param("id")
	if communityID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "community id required"})
		return
	}

	community, err := h.social.GetCommunity(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if community == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
		return
	}

	var body struct {
		Plan          string `json:"plan"`
		PaymentMethod string `json:"paymentMethod"`
		PaymentRef    string `json:"paymentRef"`
		ReceiptURL    string `json:"receiptUrl"`
		UserNote      string `json:"userNote"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Plan = strings.ToLower(strings.TrimSpace(body.Plan))
	body.PaymentMethod = strings.ToLower(strings.TrimSpace(body.PaymentMethod))

	switch body.Plan {
	case "monthly", "yearly":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "plan must be monthly|yearly"})
		return
	}
	switch body.PaymentMethod {
	case "cash", "fib":
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "paymentMethod must be cash|fib"})
		return
	}

	priceCents := community.JoinPriceMonthlyCents
	if body.Plan == "yearly" {
		priceCents = community.JoinPriceYearlyCents
	}
	if priceCents <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "this community is free for that plan — just join, no payment needed",
		})
		return
	}

	currency := community.PriceCurrency
	if currency == "" {
		currency = "usd"
	}

	sub, err := h.subs.Create(repositories.CreateCommSubParams{
		UserID:        userID,
		CommunityID:   communityID,
		Plan:          body.Plan,
		PaymentMethod: body.PaymentMethod,
		PaymentRef:    body.PaymentRef,
		ReceiptURL:    body.ReceiptURL,
		UserNote:      body.UserNote,
		PriceCents:    priceCents,
		Currency:      currency,
	})
	if err != nil {
		switch {
		case errors.Is(err, repositories.ErrPendingCommSubExists):
			c.JSON(http.StatusConflict, gin.H{
				"error": "you already have a pending subscription for this community",
				"code":  "PENDING_EXISTS",
			})
		case errors.Is(err, repositories.ErrActiveCommSubExists):
			c.JSON(http.StatusConflict, gin.H{
				"error": "you already have an active subscription for this community",
				"code":  "ACTIVE_EXISTS",
			})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Tell the community owner that someone requested to join, so they
	// can act on the pending queue. Best-effort; never blocks the join.
	if community.OwnerID != nil && *community.OwnerID != userID {
		ownerID := *community.OwnerID
		requester := ""
		if u, uerr := h.users.GetByID(userID); uerr == nil && u != nil {
			if u.Name.Valid && strings.TrimSpace(u.Name.String) != "" {
				requester = strings.TrimSpace(u.Name.String)
			} else {
				requester = u.Email
			}
		}
		if h.userNotifs != nil {
			_ = h.userNotifs.Insert(
				ownerID,
				"community_join_request",
				&userID,
				requester,
				community.Name,
				nil,
			)
		}
		if h.notifier != nil {
			h.notifier.PushToUser(
				c.Request.Context(),
				ownerID,
				"community_join_request",
				map[string]string{"requester": requester, "community": community.Name},
			)
		}
	}

	c.JSON(http.StatusCreated, sub)
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

// AdminAccept — POST /api/admin/community-subscriptions/:id/accept
//
// Flips pending → active, sets expires_at, AND inserts the
// community_members row in the same transaction. Broadcasts
// `community_subscription_active` on the subscriber's user channel
// AND a `community_member_changed` event on the community channel
// so the owner's Members tab updates live.
func (h *CommunitySubscriptionsHandler) AdminAccept(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	if adminID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	id, perr := strconv.ParseInt(c.Param("id"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	sub, err := h.subs.Accept(id, adminID)
	if err != nil {
		switch {
		case errors.Is(err, repositories.ErrCommSubNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "subscription not found"})
		case errors.Is(err, repositories.ErrCommSubNotPending):
			c.JSON(http.StatusConflict, gin.H{
				"error": "subscription is not pending",
				"code":  "NOT_PENDING",
			})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}
	if h.hub != nil && sub != nil {
		// Member-changed on the community channel so the Members tab
		// refreshes live (the trigger covers user/admin channels).
		h.hub.PublishJSON(
			realtime.ChannelCommunity(sub.CommunityID),
			"community_member_changed",
			gin.H{
				"communityId": sub.CommunityID,
				"userId":      sub.UserID,
				"change":      "added",
			},
		)
	}
	// Welcome inbox row.
	if h.userNotifs != nil && sub != nil {
		_ = h.userNotifs.Insert(
			sub.UserID,
			"community_subscription_active",
			nil,
			sub.CommunityName,
			"", // body localized on-device by kind; community name is the title
			nil,
		)
	}
	// Localized device push in the member's chosen language.
	if h.notifier != nil && sub != nil {
		h.notifier.PushToUser(
			c.Request.Context(),
			sub.UserID,
			"community_subscription_active",
			map[string]string{"community": sub.CommunityName},
		)
	}
	// Tell the community owner they have a new member. Best-effort.
	if sub != nil {
		if comm, cerr := h.social.GetCommunity(sub.CommunityID); cerr == nil &&
			comm != nil && comm.OwnerID != nil && *comm.OwnerID != sub.UserID {
			ownerID := *comm.OwnerID
			member := subscriberDisplayName(h.users, sub.UserID)
			if h.userNotifs != nil {
				_ = h.userNotifs.Insert(
					ownerID, "community_new_member", &sub.UserID, member, sub.CommunityName, nil,
				)
			}
			if h.notifier != nil {
				h.notifier.PushToUser(
					c.Request.Context(), ownerID, "community_new_member",
					map[string]string{"member": member, "community": sub.CommunityName},
				)
			}
		}
	}
	c.JSON(http.StatusOK, sub)
}

// AdminReject — POST /api/admin/community-subscriptions/:id/reject
//
// Body: { "reason": "<optional>" }
func (h *CommunitySubscriptionsHandler) AdminReject(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	if adminID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	id, perr := strconv.ParseInt(c.Param("id"), 10, 64)
	if perr != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	_ = c.ShouldBindJSON(&body)
	sub, err := h.subs.Reject(id, body.Reason)
	if err != nil {
		switch {
		case errors.Is(err, repositories.ErrCommSubNotFound):
			c.JSON(http.StatusNotFound, gin.H{"error": "subscription not found"})
		case errors.Is(err, repositories.ErrCommSubNotPending):
			c.JSON(http.StatusConflict, gin.H{
				"error": "subscription is not pending",
				"code":  "NOT_PENDING",
			})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}
	// Persistent inbox row so the rejection isn't only a snackbar.
	// Empty snippet → app renders a localized default body; a custom
	// admin reason (data) is shown as-is when provided.
	if h.userNotifs != nil && sub != nil {
		_ = h.userNotifs.Insert(
			sub.UserID,
			"community_subscription_rejected",
			nil,
			sub.CommunityName,
			body.Reason,
			nil,
		)
	}
	if h.notifier != nil && sub != nil {
		h.notifier.PushToUser(
			c.Request.Context(),
			sub.UserID,
			"community_subscription_rejected",
			nil,
		)
	}
	// Audit + realtime fan-out are handled by the SQL triggers (mig 0025);
	// no extra hub.Publish call needed here. The adminID is left unused
	// only because the audit trigger reads `accepted_by` — we still
	// reference it via the URL auth so it's available to future code.
	_ = adminID
	c.JSON(http.StatusOK, sub)
}

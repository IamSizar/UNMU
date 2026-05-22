package handlers

import (
	"database/sql"
	"errors"
	"halalstocks/internal/models"
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// ExpertApplicationHandler exposes the endpoints behind step 1 of the
// "expert + community" feature. Three flows live here:
//
//   * User submits / withdraws an application
//   * User checks own application
//   * Admin lists, approves, rejects, and demotes
type ExpertApplicationHandler struct {
	apps       *repositories.ExpertApplicationRepository
	users      *repositories.UserRepository
	userNotifs *repositories.UserNotificationsRepository // optional, set via SetUserNotifications
	hub        *realtime.Hub                             // optional, set via SetHub
}

func NewExpertApplicationHandler(
	apps *repositories.ExpertApplicationRepository,
	users *repositories.UserRepository,
) *ExpertApplicationHandler {
	return &ExpertApplicationHandler{apps: apps, users: users}
}

// SetUserNotifications wires the inbox writer so approve/reject lay
// down a persistent row in addition to the realtime broadcast. Optional —
// when nil, the handler still works but lifecycle events vanish with the
// snackbar.
func (h *ExpertApplicationHandler) SetUserNotifications(
	repo *repositories.UserNotificationsRepository,
) {
	h.userNotifs = repo
}

// SetHub wires the realtime hub so demote can publish a `user_role_changed`
// event without going through the SQL trigger (the trigger fires on
// status changes; demote happens on a different surface).
func (h *ExpertApplicationHandler) SetHub(hub *realtime.Hub) {
	h.hub = hub
}

// =============================================================================
// User-facing endpoints (auth required)
// =============================================================================

type submitApplicationRequest struct {
	FullName    string   `json:"fullName" binding:"required"`
	Expertise   string   `json:"expertise" binding:"required"`
	Bio         string   `json:"bio" binding:"required,min=20"`
	Credentials []string `json:"credentials"`
	Country     string   `json:"country"`
	SampleLinks []string `json:"sampleLinks"`
	ResumeURL   string   `json:"resumeUrl"`
	AvatarURL   string   `json:"avatarUrl"`
}

// Submit creates a new pending application for the authenticated user.
//
// Rejects users who are already EXPERT/ADMIN, users who already have a
// pending application (HTTP 409), and users still inside the post-rejection
// cool-down window (HTTP 429 with `retryAfterSeconds`).
func (h *ExpertApplicationHandler) Submit(c *gin.Context) {
	userID, ok := authedUserID(c)
	if !ok {
		return
	}

	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "user lookup failed"})
		return
	}
	if user.Role != "USER" {
		c.JSON(http.StatusConflict, gin.H{"error": "only regular users can apply for expert status"})
		return
	}

	var req submitApplicationRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	app := &models.ExpertApplication{
		UserID:      userID,
		FullName:    req.FullName,
		Expertise:   req.Expertise,
		Bio:         req.Bio,
		Credentials: req.Credentials,
		SampleLinks: req.SampleLinks,
	}
	if req.Country != "" {
		app.Country = &req.Country
	}
	if req.ResumeURL != "" {
		app.ResumeURL = &req.ResumeURL
	}
	if req.AvatarURL != "" {
		app.AvatarURL = &req.AvatarURL
	}

	retryAfter, err := h.apps.Create(app)
	if err != nil {
		switch {
		case errors.Is(err, repositories.ErrPendingApplicationExists):
			c.JSON(http.StatusConflict, gin.H{
				"error": "you already have a pending application",
				"code":  "PENDING_EXISTS",
			})
			return
		case errors.Is(err, repositories.ErrReapplyTooSoon):
			c.JSON(http.StatusTooManyRequests, gin.H{
				"error":             "you can re-apply after the cool-down period",
				"code":              "REAPPLY_COOLDOWN",
				"retryAfterSeconds": int(retryAfter.Seconds()),
			})
			return
		}
		log.Printf("expert application create failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to submit application"})
		return
	}

	c.JSON(http.StatusCreated, app)
}

// MyApplication returns the authenticated user's most recent application,
// or { "status": "none" } if they've never applied.
func (h *ExpertApplicationHandler) MyApplication(c *gin.Context) {
	userID, ok := authedUserID(c)
	if !ok {
		return
	}
	app, err := h.apps.LatestForUser(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "lookup failed"})
		return
	}
	if app == nil {
		c.JSON(http.StatusOK, gin.H{"status": "none"})
		return
	}
	c.JSON(http.StatusOK, app)
}

// Withdraw — DELETE /api/me/expert-applications/:id
//
// The applicant cancels their own pending application. 404 if the row
// doesn't exist OR doesn't belong to the caller OR isn't pending — we
// don't distinguish so the user can't probe other users' app ids.
func (h *ExpertApplicationHandler) Withdraw(c *gin.Context) {
	userID, ok := authedUserID(c)
	if !ok {
		return
	}
	appID, ok := pathID(c)
	if !ok {
		return
	}
	if err := h.apps.Withdraw(appID, userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "no pending application with that id"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"withdrawn": true})
}

// =============================================================================
// Admin-only endpoints (require RequireAdmin middleware)
// =============================================================================

// List returns applications, optionally filtered by ?status= and ?q=
// (email/name ILIKE), keyset-paginated by ?cursor=<lastId>&limit=<n>.
func (h *ExpertApplicationHandler) List(c *gin.Context) {
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
	apps, err := h.apps.ListByStatus(repositories.AdminListFilter{
		Status: c.Query("status"),
		Query:  c.Query("q"),
		Cursor: cursor,
		Limit:  limit,
	})
	if err != nil {
		log.Printf("list applications failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "list failed"})
		return
	}
	if apps == nil {
		apps = []models.ExpertApplication{}
	}
	c.JSON(http.StatusOK, gin.H{"applications": apps})
}

// PendingCount — GET /api/admin/expert-applications/pending-count
//
// Cheap COUNT(*) for the sidebar badge. Mirrors the subscription
// pending-count pattern.
func (h *ExpertApplicationHandler) PendingCount(c *gin.Context) {
	n, err := h.apps.PendingCount()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// Get — GET /api/admin/expert-applications/:id
//
// Single-row fetch for the admin detail-page drill-in. 404 if the
// application doesn't exist.
func (h *ExpertApplicationHandler) Get(c *gin.Context) {
	id, ok := pathID(c)
	if !ok {
		return
	}
	app, err := h.apps.GetByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "fetch failed"})
		return
	}
	if app == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "application not found"})
		return
	}
	// Best-effort: enrich with reviewer email for the timeline UI.
	if app.ReviewedBy != nil {
		if u, e := h.users.GetByID(*app.ReviewedBy); e == nil && u != nil {
			app.ReviewerEmail = u.Email
		}
	}
	c.JSON(http.StatusOK, app)
}

// Approve promotes the applicant to EXPERT in a single transaction.
//
// Maps repository sentinel errors to HTTP statuses so admin UI can react
// cleanly: 404 (gone), 409 (already-decided), else 500.
func (h *ExpertApplicationHandler) Approve(c *gin.Context) {
	appID, ok := pathID(c)
	if !ok {
		return
	}
	reviewerID, ok := authedUserID(c)
	if !ok {
		return
	}

	app, err := h.apps.Approve(appID, reviewerID)
	if err != nil {
		switch {
		case errors.Is(err, repositories.ErrApplicationNotPending):
			c.JSON(http.StatusConflict, gin.H{
				"error": "application is not pending",
				"code":  "NOT_PENDING",
			})
			return
		}
		log.Printf("approve failed: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if app == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "application not found"})
		return
	}

	// Welcome inbox row — best-effort. Mirrors the expert-subscription pattern
	// so the new expert sees their welcome message in the notifications inbox
	// after the realtime banner disappears.
	if h.userNotifs != nil {
		_ = h.userNotifs.Insert(
			app.UserID,
			"expert_application_approved",
			nil,
			"",
			"You're now a verified expert. Welcome aboard — start posting!",
			nil,
		)
	}
	c.JSON(http.StatusOK, app)
}

type rejectRequest struct {
	Reason string `json:"reason"`
}

// Reject marks an application rejected with an optional reason.
func (h *ExpertApplicationHandler) Reject(c *gin.Context) {
	appID, ok := pathID(c)
	if !ok {
		return
	}
	reviewerID, ok := authedUserID(c)
	if !ok {
		return
	}

	var req rejectRequest
	_ = c.ShouldBindJSON(&req) // body is optional

	app, err := h.apps.Reject(appID, reviewerID, req.Reason)
	if err != nil {
		switch {
		case errors.Is(err, repositories.ErrApplicationNotPending):
			c.JSON(http.StatusConflict, gin.H{
				"error": "application is not pending",
				"code":  "NOT_PENDING",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if app == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "no application with that id"})
		return
	}

	// Persistent inbox row so the rejection isn't only a snackbar.
	if h.userNotifs != nil {
		snippet := "Your expert application was not approved."
		if req.Reason != "" {
			snippet = req.Reason
		}
		_ = h.userNotifs.Insert(
			app.UserID,
			"expert_application_rejected",
			nil,
			"",
			snippet,
			nil,
		)
	}
	c.JSON(http.StatusOK, app)
}

// Demote — POST /api/admin/users/:id/demote-expert
//
// Soft-undo of an expert approval. Flips role back to USER, nullifies
// expert_id. Leaves the experts row in place so historical posts/subs
// stay valid (foreign keys unchanged). Used for typo recovery.
func (h *ExpertApplicationHandler) Demote(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.apps.DemoteExpert(id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "user not found or not an expert"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Notify both the user (their UI must drop expert affordances) and the
	// admin channel (sidebar / role chips must refresh).
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelUser(id),
			"user_role_changed",
			gin.H{"userId": id, "role": "USER"},
		)
		h.hub.PublishJSON(
			realtime.ChannelAdmin,
			"user_role_changed",
			gin.H{"userId": id, "role": "USER"},
		)
	}
	if h.userNotifs != nil {
		_ = h.userNotifs.Insert(
			id,
			"expert_demoted",
			nil,
			"",
			"Your expert status was removed by an administrator.",
			nil,
		)
	}
	c.JSON(http.StatusOK, gin.H{"demoted": true})
}

// =============================================================================
// helpers
// =============================================================================

func authedUserID(c *gin.Context) (int64, bool) {
	v, exists := c.Get("user_id")
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return 0, false
	}
	id, ok := v.(int64)
	if !ok {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "invalid token"})
		return 0, false
	}
	return id, true
}

func pathID(c *gin.Context) (int64, bool) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return 0, false
	}
	return id, true
}

// Unused import shim — `strings` is used inside the repo package; the
// handler imports it for future query trimming. Kept so adding `q`-trim
// here later doesn't need an import-add round-trip.
var _ = strings.TrimSpace

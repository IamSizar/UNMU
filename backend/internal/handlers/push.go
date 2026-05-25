package handlers

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// PushHandler owns the per-device token registration endpoint and the
// admin broadcast endpoint. Held by main.go so the routes are wired
// once at boot.
type PushHandler struct {
	tokens *repositories.PushTokenRepository
	fcm    *services.FCMSender // nullable — endpoint returns 503 when nil
	// Wired post-construction for the temporary test-all endpoint.
	notifier *services.Notifier
	users    *repositories.UserRepository
	// Scheduled "countdown" pushes (mig 0048). Wired post-construction.
	scheduled *repositories.ScheduledPushRepository
}

// SetScheduledRepo wires the scheduled-push store used by the schedule
// endpoints. Safe to leave nil (then those endpoints 503).
func (h *PushHandler) SetScheduledRepo(r *repositories.ScheduledPushRepository) {
	h.scheduled = r
}

// normalizeTarget lower-cases + defaults the broadcast target to "all".
func normalizeTarget(t string) string {
	t = strings.ToLower(strings.TrimSpace(t))
	if t == "" {
		return "all"
	}
	return t
}

// validateSendTarget returns a 400 message if the target spec is invalid,
// or "" when it's good. Shared by AdminSend + ScheduleSend.
func validateSendTarget(b sendBody) string {
	switch normalizeTarget(b.Target) {
	case "all", "ios", "android", "web":
		return ""
	case "user":
		if b.UserID <= 0 {
			return "target=user requires userId"
		}
	case "role":
		role := strings.ToUpper(strings.TrimSpace(b.Role))
		if role != "USER" && role != "EXPERT" && role != "ADMIN" {
			return "target=role requires role=USER|EXPERT|ADMIN"
		}
	case "community":
		if strings.TrimSpace(b.CommunityID) == "" {
			return "target=community requires communityId"
		}
	default:
		return "target must be all|ios|android|web|user|role|community"
	}
	return ""
}

func NewPushHandler(
	tokens *repositories.PushTokenRepository,
	fcm *services.FCMSender,
) *PushHandler {
	return &PushHandler{tokens: tokens, fcm: fcm}
}

// SetTestDeps wires the deps used by AdminTestAllNotifications (the
// temporary smoke-test endpoint). Safe to leave nil in prod.
func (h *PushHandler) SetTestDeps(n *services.Notifier, users *repositories.UserRepository) {
	h.notifier = n
	h.users = users
}

// AdminTestAllNotifications — POST /api/admin/push/test-all
//
// TEMPORARY smoke test. Fires every notification type at every user via
// the real Notifier — each rendered in that user's chosen language and
// honoring their settings. Only users with a registered device token
// actually receive a push. Remove this endpoint (and SetTestDeps) once
// delivery is verified.
func (h *PushHandler) AdminTestAllNotifications(c *gin.Context) {
	if h.notifier == nil || h.users == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "test deps not wired"})
		return
	}
	ids, err := h.users.AllUserIDs()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	types := services.AllNotificationTypes()
	// Sample params covering every placeholder used across templates.
	params := map[string]string{
		"author":     "Test",
		"community":  "Test Community",
		"subscriber": "Test User",
		"member":     "Test User",
		"requester":  "Test User",
	}
	for _, t := range types {
		h.notifier.PushToUsers(c.Request.Context(), ids, t, params)
	}
	c.JSON(http.StatusOK, gin.H{
		"users": len(ids),
		"types": len(types),
		"sent":  len(ids) * len(types),
		"note":  "delivered only to users with a registered device token",
	})
}

// registerTokenBody — request shape for /api/me/push-token.
type registerTokenBody struct {
	Token    string `json:"token"`
	Platform string `json:"platform"` // "ios" / "android" / "web"
}

// RegisterToken — POST /api/me/push-token
//
// Idempotent upsert keyed on the token. Authenticated; the auth
// middleware has already placed user_id in the gin context.
//
// Called by the Flutter PushTokenService once it has a fresh FCM
// token, and again on every onTokenRefresh event so a rotated token
// gets persisted immediately.
func (h *PushHandler) RegisterToken(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body registerTokenBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Token = strings.TrimSpace(body.Token)
	body.Platform = strings.ToLower(strings.TrimSpace(body.Platform))
	if body.Token == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "token required"})
		return
	}
	if body.Platform != "ios" && body.Platform != "android" && body.Platform != "web" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "platform must be ios|android|web",
		})
		return
	}
	id, err := h.tokens.Upsert(userID, body.Token, body.Platform)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"id": id})
}

// sendBody — request shape for /api/admin/push/send.
//
// Target choices:
//
//	"all"       — every token in user_push_tokens (default)
//	"user"      — only tokens belonging to the user named by UserID
//	"ios"       — every iOS token (platform filter)
//	"android"   — every Android token (platform filter)
//	"role"      — every user whose role == Role ("USER"/"EXPERT"/"ADMIN")
//	"community" — every member of the community named by CommunityID
type sendBody struct {
	Title       string            `json:"title"`
	Body        string            `json:"body"`
	Data        map[string]string `json:"data,omitempty"`
	Target      string            `json:"target,omitempty"`
	UserID      int64             `json:"userId,omitempty"`
	Role        string            `json:"role,omitempty"`
	CommunityID string            `json:"communityId,omitempty"`
}

// AdminSend — POST /api/admin/push/send
//
// Admin-only. The route is registered under the admin middleware so
// non-admin callers get 403 before reaching this code.
//
// Returns a count of successful + failed sends so the admin dashboard
// can show "Sent to 14,238 devices · 12 failures". Invalid tokens are
// pruned from the DB before responding.
func (h *PushHandler) AdminSend(c *gin.Context) {
	if h.fcm == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{
			"error": "FCM not configured (set FIREBASE_PROJECT_ID + " +
				"GOOGLE_APPLICATION_CREDENTIALS env vars on the server)",
		})
		return
	}
	var body sendBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Title = strings.TrimSpace(body.Title)
	body.Body = strings.TrimSpace(body.Body)
	if body.Title == "" || body.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title and body required"})
		return
	}

	if msg := validateSendTarget(body); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}
	target := normalizeTarget(body.Target)
	tokens, err := h.tokens.ResolveTokens(
		target, body.UserID, body.Role, body.CommunityID,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(tokens) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"success_count": 0,
			"failure_count": 0,
			"recipients":    0,
			"target":        target,
		})
		return
	}

	// 5 min ceiling: 10k tokens / 500 batch × ~1s/batch ≈ 20s real time,
	// but cellular fan-out can be slow. 5 min covers reasonable
	// broadcast sizes without holding the request forever.
	ctx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Minute)
	defer cancel()

	result, sendErr := h.fcm.SendToTokens(ctx, tokens, body.Title, body.Body, body.Data)
	// Prune invalid tokens regardless of partial errors — they'll
	// just keep failing on every future broadcast otherwise.
	for _, t := range result.InvalidTokens {
		_ = h.tokens.DeleteToken(t)
	}
	if sendErr != nil {
		c.JSON(http.StatusInternalServerError, gin.H{
			"error":          sendErr.Error(),
			"success_count":  result.SuccessCount,
			"failure_count":  result.FailureCount,
			"invalid_tokens": result.InvalidTokens,
		})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"success_count":  result.SuccessCount,
		"failure_count":  result.FailureCount,
		"recipients":     len(tokens),
		"target":         target,
		"invalid_tokens": result.InvalidTokens,
	})
}

// scheduleBody = sendBody + when to fire it. The dashboard sends
// `sendInSeconds` (total countdown from now, computed from its
// days/hours/minutes/seconds picker); an absolute RFC3339 `sendAt` is also
// accepted as an alternative.
type scheduleBody struct {
	sendBody
	SendInSeconds int64  `json:"sendInSeconds,omitempty"`
	SendAt        string `json:"sendAt,omitempty"`
	// Recurrence (optional). Repeat: none|minutely|hourly|daily|weekly|monthly.
	// RepeatDays: weekdays 0=Sun…6=Sat, required when Repeat="weekly".
	Repeat     string `json:"repeat,omitempty"`
	RepeatDays []int  `json:"repeatDays,omitempty"`
}

// validRepeatKinds is the closed set the scheduler knows how to advance.
var validRepeatKinds = map[string]bool{
	"none": true, "minutely": true, "hourly": true,
	"daily": true, "weekly": true, "monthly": true,
}

// ScheduleSend — POST /api/admin/push/schedule
//
// Queues a push to fire at a future time. A background sender
// (services.ScheduledPushSender) delivers it when due, so it survives the
// dashboard being closed. Admin-only (route under admin middleware).
func (h *PushHandler) ScheduleSend(c *gin.Context) {
	if h.scheduled == nil {
		c.JSON(http.StatusServiceUnavailable,
			gin.H{"error": "scheduling not configured"})
		return
	}
	var b scheduleBody
	if err := c.ShouldBindJSON(&b); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	b.Title = strings.TrimSpace(b.Title)
	b.Body = strings.TrimSpace(b.Body)
	if b.Title == "" || b.Body == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title and body required"})
		return
	}
	if msg := validateSendTarget(b.sendBody); msg != "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": msg})
		return
	}

	var sendAt time.Time
	switch {
	case b.SendInSeconds > 0:
		sendAt = time.Now().Add(time.Duration(b.SendInSeconds) * time.Second)
	case b.SendAt != "":
		t, err := time.Parse(time.RFC3339, b.SendAt)
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": "invalid sendAt (use RFC3339)"})
			return
		}
		sendAt = t
	default:
		c.JSON(http.StatusBadRequest,
			gin.H{"error": "sendInSeconds or sendAt required"})
		return
	}
	if sendAt.Before(time.Now().Add(2 * time.Second)) {
		c.JSON(http.StatusBadRequest, gin.H{"error": "send time must be in the future"})
		return
	}

	// Recurrence (optional). Default to one-shot.
	repeat := strings.ToLower(strings.TrimSpace(b.Repeat))
	if repeat == "" {
		repeat = "none"
	}
	if !validRepeatKinds[repeat] {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid repeat kind"})
		return
	}
	var repeatDays []int64
	if repeat == "weekly" {
		seen := map[int]bool{}
		for _, d := range b.RepeatDays {
			if d < 0 || d > 6 {
				c.JSON(http.StatusBadRequest, gin.H{"error": "repeatDays must be 0–6 (Sun–Sat)"})
				return
			}
			if !seen[d] {
				seen[d] = true
				repeatDays = append(repeatDays, int64(d))
			}
		}
		if len(repeatDays) == 0 {
			c.JSON(http.StatusBadRequest, gin.H{"error": "weekly repeat needs at least one weekday"})
			return
		}
	}

	rec := repositories.ScheduledPush{
		Title:      b.Title,
		Body:       b.Body,
		Data:       b.Data,
		Target:     normalizeTarget(b.Target),
		SendAt:     sendAt,
		RepeatKind: repeat,
		RepeatDays: repeatDays,
	}
	if b.UserID > 0 {
		rec.UserID = &b.UserID
	}
	if role := strings.ToUpper(strings.TrimSpace(b.Role)); role != "" {
		rec.Role = &role
	}
	if cid := strings.TrimSpace(b.CommunityID); cid != "" {
		rec.CommunityID = &cid
	}
	saved, err := h.scheduled.Create(rec)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, saved)
}

// ListScheduled — GET /api/admin/push/scheduled
func (h *PushHandler) ListScheduled(c *gin.Context) {
	if h.scheduled == nil {
		c.JSON(http.StatusServiceUnavailable,
			gin.H{"error": "scheduling not configured"})
		return
	}
	list, err := h.scheduled.List(100)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": list})
}

// CancelScheduled — DELETE /api/admin/push/scheduled/:id
func (h *PushHandler) CancelScheduled(c *gin.Context) {
	if h.scheduled == nil {
		c.JSON(http.StatusServiceUnavailable,
			gin.H{"error": "scheduling not configured"})
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	ok, err := h.scheduled.Cancel(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if !ok {
		c.JSON(http.StatusConflict,
			gin.H{"error": "not pending (already sent or cancelled)"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"cancelled": true})
}

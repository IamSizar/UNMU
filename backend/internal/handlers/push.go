package handlers

import (
	"context"
	"net/http"
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

	target := strings.ToLower(strings.TrimSpace(body.Target))
	if target == "" {
		target = "all"
	}

	var tokens []string
	var err error
	switch target {
	case "all":
		tokens, err = h.tokens.ListAllTokens("")
	case "ios", "android", "web":
		tokens, err = h.tokens.ListAllTokens(target)
	case "user":
		if body.UserID <= 0 {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "target=user requires userId",
			})
			return
		}
		tokens, err = h.tokens.ListForUser(body.UserID)
	case "role":
		role := strings.ToUpper(strings.TrimSpace(body.Role))
		if role != "USER" && role != "EXPERT" && role != "ADMIN" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "target=role requires role=USER|EXPERT|ADMIN",
			})
			return
		}
		tokens, err = h.tokens.ListForRole(role)
	case "community":
		cid := strings.TrimSpace(body.CommunityID)
		if cid == "" {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "target=community requires communityId",
			})
			return
		}
		tokens, err = h.tokens.ListForCommunity(cid)
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "target must be all|ios|android|web|user|role|community",
		})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if len(tokens) == 0 {
		c.JSON(http.StatusOK, gin.H{
			"success_count":  0,
			"failure_count":  0,
			"recipients":     0,
			"target":         target,
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

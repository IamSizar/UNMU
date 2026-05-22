package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// InboxHandler exposes the unified notification inbox — merged
// view of both `notifications` (stock) and `user_notifications`
// (social/sub) tables. Replaces the per-table endpoints on the
// mobile side; the legacy paths remain for any caller that hasn't
// migrated yet.
type InboxHandler struct {
	inbox *repositories.InboxRepository
}

func NewInboxHandler(inbox *repositories.InboxRepository) *InboxHandler {
	return &InboxHandler{inbox: inbox}
}

// List — GET /api/me/inbox?cursor=<RFC3339>&limit=<N>&filter=all|unread
//
// Returns the merged inbox newest-first.
//   - `cursor` (optional): keyset cursor — the oldest currently-loaded
//     item's createdAt. Items strictly older are returned next.
//   - `limit`  (optional): clamped 1..200, default 50.
//   - `filter` (optional): `unread` filters out already-read rows;
//     anything else (or empty) returns the full history.
//
// Response also carries the unified unread count so the mobile
// inbox can update its tab badge without a follow-up call.
func (h *InboxHandler) List(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	var before time.Time
	if raw := strings.TrimSpace(c.Query("cursor")); raw != "" {
		if parsed, err := time.Parse(time.RFC3339Nano, raw); err == nil {
			before = parsed
		} else if parsed, err := time.Parse(time.RFC3339, raw); err == nil {
			before = parsed
		}
	}
	limit := parseLimit(c.Query("limit"), 50)
	unreadOnly := strings.EqualFold(c.Query("filter"), "unread")

	items, err := h.inbox.List(userID, before, limit, unreadOnly)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	unread, _ := h.inbox.UnreadCount(userID)
	c.JSON(http.StatusOK, gin.H{
		"items":       items,
		"unreadCount": unread,
	})
}

// UnreadCount — GET /api/me/inbox/unread-count
//
// Tiny helper for the bell badge on the bottom-nav. Cheaper than
// a full list call because we only run two COUNT(*) queries.
func (h *InboxHandler) UnreadCount(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	n, err := h.inbox.UnreadCount(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"unreadCount": n})
}

// MarkRead — POST /api/me/inbox/:source/:id/read
//
// :source is "social" or "stock" — the unified DTO carries this
// discriminator so the mobile knows which value to send. We
// reject anything else with 400 to keep the routes self-validating.
func (h *InboxHandler) MarkRead(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	source := strings.ToLower(strings.TrimSpace(c.Param("source")))
	if source != "social" && source != "stock" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "source must be social|stock"})
		return
	}
	id, err := strconv.ParseInt(strings.TrimSpace(c.Param("id")), 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.inbox.MarkRead(source, id, userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// MarkAllRead — POST /api/me/inbox/read-all
//
// Returns the number of rows actually flipped so the client can
// reflect the badge change. Idempotent — calling twice when there's
// nothing to read returns 0.
func (h *InboxHandler) MarkAllRead(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	n, err := h.inbox.MarkAllRead(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"marked": n})
}

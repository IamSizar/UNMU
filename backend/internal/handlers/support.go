package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
	"halalstocks/internal/services"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
)

// SupportHandler — built-in user ↔ admin chat surfaced via the mobile
// Settings → "Contact Admin" entry and the admin dashboard's Support
// inbox.
//
// Each authed user has at most ONE thread (DB UNIQUE constraint on
// support_threads.user_id). Re-opening a closed thread is implicit:
// sending another user message flips status back to 'open' via the
// AFTER INSERT trigger from migration 0029.
//
// Audit: every admin mutate (edit / delete / pin / unpin / close)
// writes an `admin_support_*` row to audit_logs via the shared
// AuditRepository so the dashboard's Audit Log page can render a
// "Support" tab with the full paper trail. Admin replies are NOT
// audited (would be noisy — the reply is already visible in the
// thread itself).
type SupportHandler struct {
	repo  *repositories.SupportRepository
	hub   *realtime.Hub
	audit *repositories.AuditRepository
	// Wired post-construction; both optional (may be nil).
	userNotifs *repositories.UserNotificationsRepository
	notifier   *services.Notifier
}

func NewSupportHandler(
	repo *repositories.SupportRepository,
	hub *realtime.Hub,
	audit *repositories.AuditRepository,
) *SupportHandler {
	return &SupportHandler{repo: repo, hub: hub, audit: audit}
}

// SetUserNotifications wires the inbox writer so an admin reply lands in
// the user's notification history. Best-effort; nil is tolerated.
func (h *SupportHandler) SetUserNotifications(repo *repositories.UserNotificationsRepository) {
	h.userNotifs = repo
}

// SetNotifier wires the localized push sender for admin replies.
func (h *SupportHandler) SetNotifier(n *services.Notifier) {
	h.notifier = n
}

// writeAudit centralises the audit pattern for admin support actions.
// Same shape as community_proposals.go — failure to log never blocks
// the action it's recording.
//
// `targetID` is the support thread id (so the admin UI can deep-link
// from a thread to "show audit rows for this thread"). `meta` carries
// the per-action context the detail page needs:
//   - edit  → { messageId, oldBody, newBody }
//   - delete → { messageId }
//   - pin / unpin → { messageId? }
//   - close → { }
func (h *SupportHandler) writeAudit(
	c *gin.Context,
	eventType, severity string,
	threadID int64,
	summary string,
	meta map[string]any,
) {
	if h.audit == nil {
		return
	}
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	var actor *int64
	if userID != 0 {
		actor = &userID
	}
	targetKind := "support_thread"
	targetIDStr := strconv.FormatInt(threadID, 10)
	_, _ = h.audit.Write(
		eventType, severity, actor, &targetIDStr, &targetKind, summary, meta,
	)
}

// ─── per-user rate limiter ──────────────────────────────────────────
//
// Lightweight in-memory throttle: 1 user message per 2 seconds. Prevents
// accidental double-taps + a basic spam guard. Survives process restarts
// fine (worst case a user gets one extra free message after a deploy).
var supportRateLimit = struct {
	mu       sync.Mutex
	lastSent map[int64]time.Time
}{lastSent: make(map[int64]time.Time)}

func supportTakeToken(userID int64, minGap time.Duration) bool {
	supportRateLimit.mu.Lock()
	defer supportRateLimit.mu.Unlock()
	now := time.Now()
	if last, ok := supportRateLimit.lastSent[userID]; ok && now.Sub(last) < minGap {
		return false
	}
	supportRateLimit.lastSent[userID] = now
	return true
}

// ─── user-facing routes ──────────────────────────────────────────────

// MyThread — GET /api/me/support/thread.
// Returns the current user's thread metadata (status, unread, etc.).
// Auto-creates the thread if it doesn't exist yet so the mobile screen
// always has something to render.
func (h *SupportHandler) MyThread(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	t, err := h.repo.EnsureThread(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"thread": t})
}

// MyMessages — GET /api/me/support/messages.
// Returns the user's chat history (oldest → newest). Auto-creates the
// thread on first call so a fresh user sees an empty list, not a 404.
func (h *SupportHandler) MyMessages(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	t, err := h.repo.EnsureThread(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	msgs, err := h.repo.ListMessages(t.ID, 200)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"thread": t, "messages": msgs})
}

// Send — POST /api/me/support/messages.
// Body: { "body": "Hi, the app crashes on iOS 17 when…" }
//
// Validation:
//   * Body 1..2000 chars after trim.
//   * Rate-limited to 1 message per 2 seconds per user.
//
// On success the AFTER INSERT trigger updates the thread's snapshot
// fields and pg_notify fires; the realtime listener dispatches to the
// admin channel AND the user's own channel (multi-device sync).
func (h *SupportHandler) Send(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if !supportTakeToken(userID, 2*time.Second) {
		c.JSON(http.StatusTooManyRequests, gin.H{
			"error": "Please wait a moment before sending another message.",
			"code":  "SUPPORT_RATE_LIMIT",
		})
		return
	}

	var body struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	text := strings.TrimSpace(body.Body)
	if len(text) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message body required"})
		return
	}
	if len(text) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message too long (max 2000)"})
		return
	}

	t, err := h.repo.EnsureThread(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	msg, err := h.repo.InsertMessage(t.ID, userID, "user", text)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, gin.H{"message": msg})
}

// MarkRead — POST /api/me/support/read. Zeroes the user-side unread
// counter (admin replies are considered "seen"). Idempotent.
func (h *SupportHandler) MarkRead(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	if err := h.repo.MarkUserRead(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// ─── admin-facing routes ─────────────────────────────────────────────

// AdminListThreads — GET /api/admin/support/threads?status=open
func (h *SupportHandler) AdminListThreads(c *gin.Context) {
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	if status != "" && status != "open" && status != "closed" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status"})
		return
	}
	limit := parseLimit(c.Query("limit"), 100)
	rows, err := h.repo.AdminListThreads(status, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"threads": rows})
}

// AdminPendingCount — GET /api/admin/support/pending-count.
// Drives the sidebar red-dot badge on the admin dashboard.
func (h *SupportHandler) AdminPendingCount(c *gin.Context) {
	n, err := h.repo.AdminPendingCount()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// AdminThread — GET /api/admin/support/threads/:id.
// Returns the thread + full message history. Also zeroes
// `unread_admin` so the badge ticks down the moment an admin opens the
// thread (matches the mobile read-on-open behaviour).
func (h *SupportHandler) AdminThread(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	t, err := h.repo.GetThreadByID(id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "thread not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	msgs, err := h.repo.ListMessages(t.ID, 500)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Mark-as-read on open. Best-effort — never block the read on a
	// counter update failure.
	_ = h.repo.MarkAdminRead(id)
	t.UnreadAdmin = 0
	c.JSON(http.StatusOK, gin.H{"thread": t, "messages": msgs})
}

// AdminReply — POST /api/admin/support/threads/:id/messages.
// Body: { "body": "Sure, what device are you on?" }
//
// Sets sender_role='admin' (note: SenderUserID is the admin's own id,
// useful when multiple admins reply). The thread trigger bumps
// unread_user so the receiving user's bell turns on.
func (h *SupportHandler) AdminReply(c *gin.Context) {
	threadID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	if adminID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	text := strings.TrimSpace(body.Body)
	if len(text) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message body required"})
		return
	}
	if len(text) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message too long (max 2000)"})
		return
	}
	// Verify thread exists so we can return 404 (vs the FK violation
	// shape on bogus IDs).
	thread, terr := h.repo.GetThreadByID(threadID)
	if terr != nil {
		if errors.Is(terr, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "thread not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": terr.Error()})
		return
	}
	msg, err := h.repo.InsertMessage(threadID, adminID, "admin", text)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Let the user know support replied — inbox row (with a preview of
	// the reply text as data) + a localized device push. Best-effort.
	if thread != nil && thread.UserID != 0 {
		if h.userNotifs != nil {
			_ = h.userNotifs.Insert(
				thread.UserID, "support_reply", &adminID, "", truncate(text, 120), nil,
			)
		}
		if h.notifier != nil {
			h.notifier.PushToUser(
				c.Request.Context(), thread.UserID, "support_reply", nil,
			)
		}
	}
	c.JSON(http.StatusCreated, gin.H{"message": msg})
}

// truncate shortens s to at most n runes, adding an ellipsis when cut.
func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n]) + "…"
}

// ─── edit / delete / pin (mig 0030) ─────────────────────────────────

// EditMyMessage — PATCH /api/me/support/messages/:id.
// Body: { "body": "fixed typo" }
//
// Validates: caller is auth'd, message exists, is NOT soft-deleted,
// is OWNED by the caller (sender_user_id matches), and the body is
// 1..2000 chars. Returns the updated row. Realtime echo on
// support_message_events publishes a `support_message_edited` event.
func (h *SupportHandler) EditMyMessage(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	msgID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	body, ok := h.readBody(c)
	if !ok {
		return
	}
	// Authorization: own-message only for non-admins. We also block
	// editing deleted messages (the repo enforces this too).
	existing, err := h.repo.GetMessageByID(msgID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing.DeletedAt != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot edit a deleted message"})
		return
	}
	if existing.SenderUserID != userID {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "you can only edit your own messages",
		})
		return
	}
	updated, err := h.repo.UpdateMessageBody(msgID, body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"message": updated})
}

// AdminEditMessage — PATCH /api/admin/support/messages/:id.
// Admins can edit ANY message (typo cleanup, redacting PII the user
// accidentally pasted, etc.). Same body shape + 1..2000 char limit.
//
// Writes `admin_support_message_edit` to audit_logs with the full
// before/after body so a future audit detail view can render a diff
// without recomputing it.
func (h *SupportHandler) AdminEditMessage(c *gin.Context) {
	msgID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	body, ok := h.readBody(c)
	if !ok {
		return
	}
	existing, err := h.repo.GetMessageByID(msgID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if existing.DeletedAt != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot edit a deleted message"})
		return
	}
	oldBody := existing.Body
	updated, err := h.repo.UpdateMessageBody(msgID, body)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(
		c, "admin_support_message_edit", "info",
		existing.ThreadID,
		fmt.Sprintf("Edited message #%d", msgID),
		map[string]any{
			"messageId": msgID,
			"oldBody":   oldBody,
			"newBody":   updated.Body,
		},
	)
	c.JSON(http.StatusOK, gin.H{"message": updated})
}

// AdminDeleteMessage — DELETE /api/admin/support/messages/:id.
// Soft-delete: row remains, body is hidden ("[message deleted]" in
// the UI). If the deleted message was pinned, the FK ON DELETE SET
// NULL doesn't fire (we're not deleting the row) but the message
// keeps its pin reference dead-pointing to a deleted message. We
// proactively clear the pin in that case.
func (h *SupportHandler) AdminDeleteMessage(c *gin.Context) {
	msgID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	existing, err := h.repo.GetMessageByID(msgID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "message not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := h.repo.SoftDeleteMessage(msgID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// If this message was the thread's pinned message, clear the pin.
	thread, _ := h.repo.GetThreadByID(existing.ThreadID)
	if thread != nil && thread.PinnedMessageID != nil &&
		*thread.PinnedMessageID == msgID {
		_ = h.repo.SetPinned(existing.ThreadID, 0)
	}
	// Audit — `warning` severity (deletion is a destructive action,
	// matches the existing post-deletion audit pattern).
	h.writeAudit(
		c, "admin_support_message_delete", "warning",
		existing.ThreadID,
		fmt.Sprintf("Deleted message #%d", msgID),
		map[string]any{
			"messageId": msgID,
			// Preserve the original body so the audit detail page can
			// show what was removed (the row's body column is kept,
			// but auditors viewing only the log line shouldn't need
			// to cross-reference the message row).
			"deletedBody": existing.Body,
		},
	)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// AdminPinMessage — POST /api/admin/support/threads/:id/pin.
// Body: { "messageId": 42 }  — pin this message.
//       { "messageId": 0  }  — clear the pin.
// Single-pin per thread; a new pin replaces the old.
func (h *SupportHandler) AdminPinMessage(c *gin.Context) {
	threadID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body struct {
		MessageID int64 `json:"messageId"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if err := h.repo.SetPinned(threadID, body.MessageID); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// Audit — pin or unpin depending on payload. `messageId=0` means
	// "clear the pin"; anything else is a new pin (replaces the old).
	if body.MessageID == 0 {
		h.writeAudit(
			c, "admin_support_thread_unpin", "info",
			threadID,
			"Cleared pinned message",
			map[string]any{},
		)
	} else {
		h.writeAudit(
			c, "admin_support_thread_pin", "info",
			threadID,
			fmt.Sprintf("Pinned message #%d", body.MessageID),
			map[string]any{"messageId": body.MessageID},
		)
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// readBody — shared helper for the edit handlers. Returns the trimmed,
// length-validated body and `true`, or writes an error response and
// returns false. Keeps the per-handler boilerplate short.
func (h *SupportHandler) readBody(c *gin.Context) (string, bool) {
	var body struct {
		Body string `json:"body"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return "", false
	}
	text := strings.TrimSpace(body.Body)
	if len(text) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message body required"})
		return "", false
	}
	if len(text) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "message too long (max 2000)"})
		return "", false
	}
	return text, true
}

// AdminClose — POST /api/admin/support/threads/:id/close.
// Sets status='closed'. The user can re-open by sending another message
// (the message INSERT trigger flips it back to 'open' automatically).
func (h *SupportHandler) AdminClose(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.repo.SetStatus(id, "closed"); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "thread not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	// Fan a thread-closed event to the user so their chat screen can
	// show "Conversation closed by admin." Best-effort.
	if h.hub != nil {
		t, _ := h.repo.GetThreadByID(id)
		if t != nil {
			h.hub.PublishJSON(
				realtime.ChannelUser(t.UserID),
				"support_thread_closed",
				map[string]any{"threadId": id},
			)
			h.hub.PublishJSON(
				realtime.ChannelAdmin,
				"support_thread_closed",
				map[string]any{"threadId": id, "userId": t.UserID},
			)
		}
	}
	// Audit — closing a thread is a state change worth recording so
	// the platform can answer "who closed thread #42 and when".
	h.writeAudit(
		c, "admin_support_thread_close", "info",
		id,
		fmt.Sprintf("Closed thread #%d", id),
		map[string]any{},
	)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

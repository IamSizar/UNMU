package handlers

import (
	"log"
	"net/http"
	"strconv"
	"strings"

	"halalstocks/internal/repositories"
	"halalstocks/internal/services"

	"github.com/gin-gonic/gin"
)

// SetSendLog wires the send-history store (mig 0060). Without it sends
// still work; they are just not recorded and History returns 503.
func (h *PushHandler) SetSendLog(log *repositories.PushSendLogRepository) {
	h.sendLog = log
}

// History — GET /api/admin/push/history?limit=N
//
// Newest admin "send now" pushes first (capped at 100).
func (h *PushHandler) History(c *gin.Context) {
	if h.sendLog == nil {
		c.JSON(http.StatusServiceUnavailable, gin.H{"error": "push history not configured"})
		return
	}
	limit, _ := strconv.Atoi(c.Query("limit"))
	items, err := h.sendLog.Recent(limit)
	if err != nil {
		log.Printf("[push] history: %v", err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load push history"})
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

// recordSend stores one admin send. Best effort: the push already went
// out, so a logging failure must not turn the response into an error.
func (h *PushHandler) recordSend(
	c *gin.Context, body sendBody, target string, recipients int,
	result services.SendResult, sendErr error,
) {
	if h.sendLog == nil {
		return
	}
	// Keep which role a role-targeted send went to (e.g. "role:EXPERT").
	if target == "role" && body.Role != "" {
		target = "role:" + strings.ToUpper(body.Role)
	}
	entry := repositories.PushSend{
		Title: body.Title, Body: body.Body, Target: target,
		Recipients: recipients, SuccessCount: result.SuccessCount, FailureCount: result.FailureCount,
	}
	if sendErr != nil {
		msg := sendErr.Error()
		entry.SendError = &msg
	}
	if uid, ok := c.Get("user_id"); ok {
		if id, ok := uid.(int64); ok && id != 0 {
			entry.SentBy = &id
		}
	}
	if err := h.sendLog.Record(entry); err != nil {
		log.Printf("[push] record send: %v", err)
	}
}

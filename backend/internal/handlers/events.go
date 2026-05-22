package handlers

import (
	"net/http"
	"strconv"
	"strings"
	"time"

	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// EventsHandler — endpoints for client-side event logging (share taps,
// reel-load failures) and admin-side aggregates (counts in last 24h /
// 7d).
//
// The DB writes go through PostEventsRepository (migration 0010).
// Errors writing events are *swallowed* on the user-facing endpoints
// and *surfaced* on the admin endpoints — failing to log a share must
// never fail the user's flow, but failing to read aggregates is a
// real admin-visible problem we want to know about.
type EventsHandler struct {
	events *repositories.PostEventsRepository
}

func NewEventsHandler(events *repositories.PostEventsRepository) *EventsHandler {
	return &EventsHandler{events: events}
}

// LogShare — POST /api/posts/:id/share-event
//
// Client tells us "the user just tapped Share on this post". We log a
// row in post_events; admin slices it later. No body required, but
// we accept an optional `{"platform":"ios|android"}` for future
// per-platform breakdowns.
func (h *EventsHandler) LogShare(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	postID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body struct {
		Platform string `json:"platform"`
	}
	_ = c.ShouldBindJSON(&body) // optional body, ignore parse errors
	meta := map[string]any{}
	if p := strings.ToLower(strings.TrimSpace(body.Platform)); p != "" {
		meta["platform"] = p
	}
	// Best-effort log — never block the share flow on a DB hiccup.
	_ = h.events.Write(postID, repositories.EventShareTapped, &userID, meta)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// LogReelLoadFailed — POST /api/me/events/reel-load-failed
//
// Client tells us "this reel's video player gave up initialising". We
// see, per-day, which reels are broken in real-world conditions
// (codec, network, CDN, etc) so the admin can sort the worst ones.
//
// Body: { "postId": <int>, "errorKind": "timeout"|"codec"|"network"|"unknown" }
func (h *EventsHandler) LogReelLoadFailed(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	var body struct {
		PostID    int64  `json:"postId"`
		ErrorKind string `json:"errorKind"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.PostID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "postId required"})
		return
	}
	kind := strings.ToLower(strings.TrimSpace(body.ErrorKind))
	if kind == "" {
		kind = "unknown"
	}
	meta := map[string]any{"errorKind": kind}
	_ = h.events.Write(body.PostID, repositories.EventReelLoadFailed, &userID, meta)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// AdminSummary — GET /admin/events/summary?window=24h|7d|30d
//
// Returns counts per event_type in the rolling window. Drives the
// dashboard top cards. Default window is 24h if none / unknown is
// passed; this keeps the URL short for the common case.
func (h *EventsHandler) AdminSummary(c *gin.Context) {
	window := parseWindow(c.Query("window"), 24*time.Hour)
	rows, err := h.events.Summary(window)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"windowHours": int(window.Hours()),
		"counts":      rows,
	})
}

// AdminTimeseries — GET /admin/events/timeseries?window=24h|7d
//
// Hour-bucketed counts, one row per (hour, event_type) pair. Frontend
// reshapes this into a stacked / grouped sparkline.
func (h *EventsHandler) AdminTimeseries(c *gin.Context) {
	window := parseWindow(c.Query("window"), 24*time.Hour)
	rows, err := h.events.HourlyTimeseries(window)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"windowHours": int(window.Hours()),
		"buckets":     rows,
	})
}

// parseWindow accepts "24h", "7d", "30d" and returns the duration; on
// unrecognised input, returns the fallback. Bounded by 30d so a
// pathological client can't ask for an unbounded scan.
func parseWindow(raw string, fallback time.Duration) time.Duration {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "1h":
		return time.Hour
	case "24h", "1d", "":
		if raw == "" {
			return fallback
		}
		return 24 * time.Hour
	case "7d":
		return 7 * 24 * time.Hour
	case "30d":
		return 30 * 24 * time.Hour
	}
	return fallback
}

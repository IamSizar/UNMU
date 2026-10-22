package handlers

import (
	"errors"
	"log"
	"net/http"
	"strconv"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
	"github.com/lib/pq"
)

// =============================================================================
// pulse.go — public (logged-in user) endpoints for UNMU Pulse.
//
//   GET    /api/pulse/today              today's items (max four, slot order)
//   GET    /api/pulse/days/:date         any past day, same shape
//   GET    /api/pulse/items/:id          one item with details + evidence
//   GET    /api/pulse/archive            past items, filter + search, paged
//   GET    /api/pulse/saved              the caller's saved items, paged
//   POST   /api/pulse/items/:id/save     bookmark
//   DELETE /api/pulse/items/:id/save     remove bookmark
//   POST   /api/pulse/events             analytics event (open, share, ...)
//
// All routes sit in the authenticated group (decision 2026-10-22: Pulse needs
// a login). Error bodies keep the app's existing {"error": "<message>"} shape
// so the Flutter client's current error handling works unchanged.
// =============================================================================

// pulseLocation is the time zone that decides which calendar day "today" is.
// Pulse is curated for Iraq / the Gulf, so the day rolls over at midnight in
// UTC+3. Iraq has no daylight saving, so a fixed offset is exact and avoids
// depending on tzdata being installed in the container.
var pulseLocation = time.FixedZone("Asia/Baghdad", 3*60*60)

const (
	pulseDateLayout     = "2006-01-02"
	pulseDefaultPage    = 30
	pulseMaxPage        = 100
	pulseMaxSearchChars = 100
)

// PulseHandler serves published Pulse content to the mobile app.
type PulseHandler struct {
	pulse *repositories.PulseRepository
	now   func() time.Time // injectable clock, so tests can pin "today"
}

// NewPulseHandler builds the handler around the shared repository.
func NewPulseHandler(pulse *repositories.PulseRepository) *PulseHandler {
	return &PulseHandler{pulse: pulse, now: time.Now}
}

// pulseToday returns today's date (YYYY-MM-DD) in the Pulse time zone.
func pulseToday(now time.Time) string {
	return now.In(pulseLocation).Format(pulseDateLayout)
}

// parsePulseDate validates a YYYY-MM-DD string. Empty is allowed and means
// "not given" (ok=true, value "").
func parsePulseDate(s string) (value string, ok bool) {
	if s == "" {
		return "", true
	}
	if _, err := time.Parse(pulseDateLayout, s); err != nil {
		return "", false
	}
	return s, true
}

// parsePulsePaging reads ?limit and ?offset with safe defaults and caps.
func parsePulsePaging(c *gin.Context) (limit, offset int, ok bool) {
	limit, offset = pulseDefaultPage, 0
	if s := c.Query("limit"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 1 {
			return 0, 0, false
		}
		limit = min(n, pulseMaxPage)
	}
	if s := c.Query("offset"); s != "" {
		n, err := strconv.Atoi(s)
		if err != nil || n < 0 {
			return 0, 0, false
		}
		offset = n
	}
	return limit, offset, true
}

func pulseBadRequest(c *gin.Context, msg string) {
	c.JSON(http.StatusBadRequest, gin.H{"error": msg})
}

func pulseServerError(c *gin.Context, what string, err error) {
	// The technical detail goes to the log; the user only sees a friendly line.
	log.Printf("pulse: %s: %v", what, err)
	c.JSON(http.StatusInternalServerError, gin.H{"error": "Something went wrong. Please try again."})
}

func pulseItemID(c *gin.Context) (int64, bool) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id < 1 {
		pulseBadRequest(c, "Invalid Pulse item id")
		return 0, false
	}
	return id, true
}

// Today — GET /api/pulse/today.
func (h *PulseHandler) Today(c *gin.Context) {
	h.serveDay(c, pulseToday(h.now()))
}

// Day — GET /api/pulse/days/:date. Future days are rejected: nothing is
// published for them, and answering would only invite probing.
func (h *PulseHandler) Day(c *gin.Context) {
	date, ok := parsePulseDate(c.Param("date"))
	if !ok || date == "" {
		pulseBadRequest(c, "Date must look like 2026-10-22")
		return
	}
	if date > pulseToday(h.now()) {
		pulseBadRequest(c, "That day has not happened yet")
		return
	}
	h.serveDay(c, date)
}

func (h *PulseHandler) serveDay(c *gin.Context, date string) {
	day, err := h.pulse.Day(c.Request.Context(), c.GetInt64("user_id"), date)
	if err != nil {
		pulseServerError(c, "load day", err)
		return
	}
	c.JSON(http.StatusOK, day)
}

// Item — GET /api/pulse/items/:id.
func (h *PulseHandler) Item(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	item, err := h.pulse.Item(c.Request.Context(), c.GetInt64("user_id"), id)
	if errors.Is(err, repositories.ErrPulseNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "This Pulse item is not available"})
		return
	}
	if err != nil {
		pulseServerError(c, "load item", err)
		return
	}
	c.JSON(http.StatusOK, item)
}

// Archive — GET /api/pulse/archive?from=&to=&q=&limit=&offset=.
func (h *PulseHandler) Archive(c *gin.Context) {
	from, okFrom := parsePulseDate(c.Query("from"))
	to, okTo := parsePulseDate(c.Query("to"))
	limit, offset, okPage := parsePulsePaging(c)
	q := c.Query("q")
	switch {
	case !okFrom || !okTo:
		pulseBadRequest(c, "Dates must look like 2026-10-22")
		return
	case from != "" && to != "" && from > to:
		pulseBadRequest(c, "The start date must be before the end date")
		return
	case !okPage:
		pulseBadRequest(c, "Invalid paging values")
		return
	case len([]rune(q)) > pulseMaxSearchChars:
		pulseBadRequest(c, "Search text is too long")
		return
	}
	items, more, err := h.pulse.Archive(c.Request.Context(), c.GetInt64("user_id"),
		repositories.ArchiveFilter{From: from, To: to, Query: q}, limit, offset)
	if err != nil {
		pulseServerError(c, "load archive", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "hasMore": more})
}

// Saved — GET /api/pulse/saved.
func (h *PulseHandler) Saved(c *gin.Context) {
	limit, offset, ok := parsePulsePaging(c)
	if !ok {
		pulseBadRequest(c, "Invalid paging values")
		return
	}
	items, more, err := h.pulse.Saved(c.Request.Context(), c.GetInt64("user_id"), limit, offset)
	if err != nil {
		pulseServerError(c, "load saved", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "hasMore": more})
}

// Save — POST /api/pulse/items/:id/save.
func (h *PulseHandler) Save(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	err := h.pulse.Save(c.Request.Context(), c.GetInt64("user_id"), id)
	if errors.Is(err, repositories.ErrPulseNotFound) {
		c.JSON(http.StatusNotFound, gin.H{"error": "This Pulse item is not available"})
		return
	}
	if err != nil {
		pulseServerError(c, "save", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"saved": true})
}

// Unsave — DELETE /api/pulse/items/:id/save.
func (h *PulseHandler) Unsave(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	if err := h.pulse.Unsave(c.Request.Context(), c.GetInt64("user_id"), id); err != nil {
		pulseServerError(c, "unsave", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"saved": false})
}

// pulseClientEvents are the analytics events the app is allowed to report;
// together they cover every value of the pulse_events event CHECK.
var pulseClientEvents = map[string]bool{
	models.PulseEventViewDay:      true,
	models.PulseEventOpenItem:     true,
	models.PulseEventReadComplete: true,
	models.PulseEventSave:         true,
	models.PulseEventUnsave:       true,
	models.PulseEventShare:        true,
	models.PulseEventOpenSource:   true,
	models.PulseEventOpenStock:    true,
}

type pulseEventRequest struct {
	Event  string `json:"event"`
	ItemID *int64 `json:"itemId"`
}

// validatePulseEvent checks an event body and returns "" when it is valid.
// view_day is the only event without an item; every other event names one.
func validatePulseEvent(req pulseEventRequest) string {
	if !pulseClientEvents[req.Event] {
		return "Unknown event"
	}
	if req.Event == models.PulseEventViewDay {
		if req.ItemID != nil {
			return "view_day does not take an item"
		}
		return ""
	}
	if req.ItemID == nil || *req.ItemID < 1 {
		return "This event needs an item"
	}
	return ""
}

// RecordEvent — POST /api/pulse/events. Fire-and-forget analytics: the app
// ignores failures, so errors here must never surface to the user.
func (h *PulseHandler) RecordEvent(c *gin.Context) {
	var req pulseEventRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		pulseBadRequest(c, "Invalid event")
		return
	}
	if msg := validatePulseEvent(req); msg != "" {
		pulseBadRequest(c, msg)
		return
	}
	err := h.pulse.RecordEvent(c.Request.Context(), c.GetInt64("user_id"), req.ItemID, req.Event)
	var pgErr *pq.Error
	if errors.As(err, &pgErr) && pgErr.Code == "23503" { // item does not exist
		c.JSON(http.StatusNotFound, gin.H{"error": "This Pulse item is not available"})
		return
	}
	if err != nil {
		pulseServerError(c, "record event", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

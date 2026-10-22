package handlers

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/pulse"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// =============================================================================
// pulse_admin.go — the Pulse CMS API for the admin dashboard.
//
// All routes live under /api/pulse-admin and sit behind AuthMiddleware plus
// RequireStaff (system admin OR a pulse_staff role). The per-action rules
// (who may review, approve, publish...) are enforced in internal/pulse while
// the item row is locked; this file only translates HTTP <-> repository.
//
//	GET    /me                      the caller's Pulse roles
//	GET    /items                   list (status, slot, date, limit, offset)
//	POST   /items                   create a draft
//	GET    /items/:id               one item, any status
//	PUT    /items/:id               edit a draft
//	DELETE /items/:id               delete a draft
//	POST   /items/:id/{submit|review|reject|approve|schedule|unschedule|publish|archive}
//	POST   /items/:id/correct       update / correct a published item
//	GET    /items/:id/versions      stored snapshots
//	GET    /items/:id/events        change log
//	GET    /staff                   role assignments
//	POST   /staff, DELETE /staff/:id    system admin only
//	GET    /analytics               engagement summary
// =============================================================================

const pulseMaxAnalyticsDays = 92

// PulseChangeHook is told when an item goes live or is changed while live, so
// notifications can be sent. event is "published", "updated" or "corrected".
type PulseChangeHook func(ctx context.Context, event string, item models.PulseAdminItem)

// PulseAdminHandler serves the Pulse CMS.
type PulseAdminHandler struct {
	repo     *repositories.PulseAdminRepository
	onChange PulseChangeHook // optional
	now      func() time.Time
}

// NewPulseAdminHandler builds the handler. onChange may be nil.
func NewPulseAdminHandler(repo *repositories.PulseAdminRepository, onChange PulseChangeHook) *PulseAdminHandler {
	return &PulseAdminHandler{repo: repo, onChange: onChange, now: time.Now}
}

const pulseActorKey = "pulse_actor"

// RequireStaff loads the caller's Pulse permissions from the database on every
// request and rejects anyone who has none. Roles are never read from the token,
// so removing a role takes effect immediately.
func (h *PulseAdminHandler) RequireStaff() gin.HandlerFunc {
	return func(c *gin.Context) {
		actor, err := h.repo.ActorFor(c.Request.Context(), c.GetInt64("user_id"))
		if err != nil {
			pulseServerError(c, "load staff roles", err)
			c.Abort()
			return
		}
		if !actor.IsStaff() {
			c.JSON(http.StatusForbidden, gin.H{"error": "You do not have access to Pulse management"})
			c.Abort()
			return
		}
		c.Set(pulseActorKey, actor)
		c.Next()
	}
}

func pulseActor(c *gin.Context) pulse.Actor {
	a, _ := c.Get(pulseActorKey)
	actor, _ := a.(pulse.Actor)
	return actor
}

// pulseRuleResponse maps a repository / rule error to an HTTP response:
// forbidden 403, wrong state 409, invalid data 422, missing 404, else 500.
func pulseRuleResponse(c *gin.Context, what string, err error) {
	var re *pulse.RuleError
	switch {
	case errors.As(err, &re):
		status := map[string]int{"forbidden": http.StatusForbidden, "state": http.StatusConflict}[re.Kind]
		if status == 0 {
			status = http.StatusUnprocessableEntity
		}
		body := gin.H{"error": re.Message}
		if len(re.Fields) > 0 {
			body["fields"] = re.Fields
		}
		c.JSON(status, body)
	case errors.Is(err, repositories.ErrPulseNotFound):
		c.JSON(http.StatusNotFound, gin.H{"error": "Pulse item not found"})
	default:
		pulseServerError(c, what, err)
	}
}

// bindPulseInput reads, trims and validates an item body. It writes the error
// response itself and returns ok=false when the request is not acceptable.
func (h *PulseAdminHandler) bindPulseInput(c *gin.Context, in *models.PulseItemInput) bool {
	if err := c.ShouldBindJSON(in); err != nil {
		pulseBadRequest(c, "Invalid item")
		return false
	}
	*in = pulse.NormalizeInput(*in)
	if errs := pulse.ValidateInput(*in, h.now()); len(errs) > 0 {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "Please fix the highlighted fields", "fields": errs})
		return false
	}
	return true
}

// Me — GET /me.
func (h *PulseAdminHandler) Me(c *gin.Context) {
	a := pulseActor(c)
	roles := []string{}
	for _, r := range []string{models.PulseRoleEditor, models.PulseRoleReviewer, models.PulseRoleApprover} {
		if a.Roles[r] {
			roles = append(roles, r)
		}
	}
	c.JSON(http.StatusOK, gin.H{"userId": a.UserID, "isAdmin": a.IsAdmin, "roles": roles})
}

// List — GET /items.
func (h *PulseAdminHandler) List(c *gin.Context) {
	limit, offset, ok := parsePulsePaging(c)
	date, okDate := parsePulseDate(c.Query("date"))
	if !ok || !okDate {
		pulseBadRequest(c, "Invalid filter values")
		return
	}
	items, more, err := h.repo.List(c.Request.Context(), repositories.PulseListFilter{
		Status: c.Query("status"), Slot: c.Query("slot"), Date: date,
	}, limit, offset)
	if err != nil {
		pulseRuleResponse(c, "list items", err)
		return
	}
	if items == nil {
		items = []models.PulseAdminItem{}
	}
	c.JSON(http.StatusOK, gin.H{"items": items, "hasMore": more})
}

// Create — POST /items.
func (h *PulseAdminHandler) Create(c *gin.Context) {
	var in models.PulseItemInput
	if !h.bindPulseInput(c, &in) {
		return
	}
	it, err := h.repo.Create(c.Request.Context(), pulseActor(c), in)
	if err != nil {
		pulseRuleResponse(c, "create item", err)
		return
	}
	c.JSON(http.StatusCreated, it)
}

// Get — GET /items/:id.
func (h *PulseAdminHandler) Get(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	it, err := h.repo.Get(c.Request.Context(), id)
	if err != nil {
		pulseRuleResponse(c, "get item", err)
		return
	}
	c.JSON(http.StatusOK, it)
}

// Update — PUT /items/:id.
func (h *PulseAdminHandler) Update(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	var in models.PulseItemInput
	if !h.bindPulseInput(c, &in) {
		return
	}
	it, err := h.repo.Update(c.Request.Context(), id, pulseActor(c), in)
	if err != nil {
		pulseRuleResponse(c, "update item", err)
		return
	}
	c.JSON(http.StatusOK, it)
}

// Delete — DELETE /items/:id.
func (h *PulseAdminHandler) Delete(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	if err := h.repo.Delete(c.Request.Context(), id, pulseActor(c)); err != nil {
		pulseRuleResponse(c, "delete item", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"deleted": true})
}

type pulseActionRequest struct {
	Note      string     `json:"note"`
	PublishAt *time.Time `json:"publishAt"`
}

// Action returns the handler for one workflow action (submit, approve, ...).
func (h *PulseAdminHandler) Action(do string) gin.HandlerFunc {
	return func(c *gin.Context) {
		id, ok := pulseItemID(c)
		if !ok {
			return
		}
		var req pulseActionRequest
		// An empty body is fine for most actions.
		if c.Request.ContentLength > 0 {
			if err := c.ShouldBindJSON(&req); err != nil {
				pulseBadRequest(c, "Invalid request")
				return
			}
		}
		it, err := h.repo.Apply(c.Request.Context(), id, pulseActor(c), do,
			repositories.PulseApplyOptions{Note: req.Note, PublishAt: req.PublishAt})
		if err != nil {
			pulseRuleResponse(c, do, err)
			return
		}
		if do == pulse.DoPublish && h.onChange != nil {
			h.onChange(c.Request.Context(), "published", *it)
		}
		c.JSON(http.StatusOK, it)
	}
}

type pulseCorrectRequest struct {
	Kind string                `json:"kind"` // "updated" or "corrected"
	Note string                `json:"note"`
	Item models.PulseItemInput `json:"item"`
}

// Correct — POST /items/:id/correct.
func (h *PulseAdminHandler) Correct(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	var req pulseCorrectRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		pulseBadRequest(c, "Invalid correction")
		return
	}
	// Date and slot cannot change on a live item; placeholders let the shape
	// validation pass and the repository keeps the item's real ones.
	req.Item.PulseDate, req.Item.Slot = "2000-01-01", models.PulseSlotGlobal
	req.Item = pulse.NormalizeInput(req.Item)
	if errs := pulse.ValidateInput(req.Item, h.now()); len(errs) > 0 {
		c.JSON(http.StatusUnprocessableEntity, gin.H{"error": "Please fix the highlighted fields", "fields": errs})
		return
	}
	it, err := h.repo.Correct(c.Request.Context(), id, pulseActor(c), req.Kind, req.Item, req.Note)
	if err != nil {
		pulseRuleResponse(c, "correct item", err)
		return
	}
	if h.onChange != nil {
		h.onChange(c.Request.Context(), req.Kind, *it)
	}
	c.JSON(http.StatusOK, it)
}

// Versions — GET /items/:id/versions.
func (h *PulseAdminHandler) Versions(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	vs, err := h.repo.Versions(c.Request.Context(), id)
	if err != nil {
		pulseRuleResponse(c, "versions", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"versions": vs})
}

// Events — GET /items/:id/events.
func (h *PulseAdminHandler) Events(c *gin.Context) {
	id, ok := pulseItemID(c)
	if !ok {
		return
	}
	log, err := h.repo.ChangeLog(c.Request.Context(), id)
	if err != nil {
		pulseRuleResponse(c, "change log", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"events": log})
}

// ListStaff — GET /staff.
func (h *PulseAdminHandler) ListStaff(c *gin.Context) {
	members, err := h.repo.ListStaff(c.Request.Context())
	if err != nil {
		pulseRuleResponse(c, "list staff", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"staff": members})
}

type pulseStaffRequest struct {
	Email string `json:"email"`
	Role  string `json:"role"`
}

// requireAdminActor answers 403 unless the caller is a system admin.
func requireAdminActor(c *gin.Context) bool {
	if !pulseActor(c).IsAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "Only a system admin can manage Pulse staff"})
		return false
	}
	return true
}

// AddStaff — POST /staff (system admin only).
func (h *PulseAdminHandler) AddStaff(c *gin.Context) {
	if !requireAdminActor(c) {
		return
	}
	var req pulseStaffRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		pulseBadRequest(c, "Invalid request")
		return
	}
	if err := h.repo.AddStaff(c.Request.Context(), req.Email, req.Role, c.GetInt64("user_id")); err != nil {
		pulseRuleResponse(c, "add staff", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// RemoveStaff — DELETE /staff/:id (system admin only).
func (h *PulseAdminHandler) RemoveStaff(c *gin.Context) {
	if !requireAdminActor(c) {
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil || id < 1 {
		pulseBadRequest(c, "Invalid staff id")
		return
	}
	if err := h.repo.RemoveStaff(c.Request.Context(), id); err != nil {
		pulseRuleResponse(c, "remove staff", err)
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// analyticsRange reads ?from&to, defaulting to the last 7 days, and checks the
// range is sane and not larger than pulseMaxAnalyticsDays.
func analyticsRange(fromQ, toQ string, now time.Time) (from, to string, ok bool) {
	to, okTo := parsePulseDate(toQ)
	from, okFrom := parsePulseDate(fromQ)
	if !okTo || !okFrom {
		return "", "", false
	}
	if to == "" {
		to = pulseToday(now)
	}
	if from == "" {
		t, _ := time.Parse(pulseDateLayout, to)
		from = t.AddDate(0, 0, -6).Format(pulseDateLayout)
	}
	f, _ := time.Parse(pulseDateLayout, from)
	t, _ := time.Parse(pulseDateLayout, to)
	if f.After(t) || t.Sub(f) > pulseMaxAnalyticsDays*24*time.Hour {
		return "", "", false
	}
	return from, to, true
}

// Analytics — GET /analytics?from=&to=.
func (h *PulseAdminHandler) Analytics(c *gin.Context) {
	from, to, ok := analyticsRange(c.Query("from"), c.Query("to"), h.now())
	if !ok {
		pulseBadRequest(c, "Pick a valid date range of at most 92 days")
		return
	}
	a, err := h.repo.Analytics(c.Request.Context(), from, to)
	if err != nil {
		pulseRuleResponse(c, "analytics", err)
		return
	}
	c.JSON(http.StatusOK, a)
}

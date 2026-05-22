package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// ReportsHandler owns user-facing report creation + admin-side queue.
type ReportsHandler struct {
	reports *repositories.ReportRepository
	audits  *repositories.AuditRepository
}

func NewReportsHandler(
	reports *repositories.ReportRepository,
	audits *repositories.AuditRepository,
) *ReportsHandler {
	return &ReportsHandler{reports: reports, audits: audits}
}

// allowedTargetTypes — every entity the app currently lets you report.
// Expanding this is a one-line change here + (optionally) a new admin
// drill-in link.
var allowedTargetTypes = map[string]bool{
	"post":      true,
	"user":      true,
	"comment":   true,
	"community": true,
	"message":   true,
}

// allowedReasons — keeps the report drop-down stable. Free-text "other"
// goes into the details field. Mirrored on the Flutter side so a
// dropdown change requires both ends to update.
var allowedReasons = map[string]bool{
	"spam":               true,
	"harassment":         true,
	"hate_speech":        true,
	"violence":           true,
	"sexual_content":     true,
	"financial_scam":     true,
	"impersonation":      true,
	"misinformation":     true,
	"copyright":          true,
	"underage":           true,
	"self_harm":          true,
	"shariah_concern":    true, // domain-specific: non-halal claim
	"other":              true,
}

// createReportBody — request body for POST /me/reports.
type createReportBody struct {
	TargetType string `json:"targetType" binding:"required"`
	TargetID   string `json:"targetId"   binding:"required"`
	Reason     string `json:"reason"     binding:"required"`
	Details    string `json:"details"`
}

// Create — POST /api/me/reports
//
// Authenticated. One open report per (user, target) is enforced by the
// partial unique index — duplicate hits return 409 with a friendly
// message so the UI can render "you've already reported this".
func (h *ReportsHandler) Create(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	var body createReportBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.TargetType = strings.ToLower(strings.TrimSpace(body.TargetType))
	body.TargetID = strings.TrimSpace(body.TargetID)
	body.Reason = strings.ToLower(strings.TrimSpace(body.Reason))

	if !allowedTargetTypes[body.TargetType] {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "targetType must be one of post|user|comment|community|message",
		})
		return
	}
	if body.TargetID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "targetId required"})
		return
	}
	if !allowedReasons[body.Reason] {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "reason must be a known reason code (see /me/reports/reasons)",
		})
		return
	}
	if len(body.Details) > 2000 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "details must be ≤ 2000 characters",
		})
		return
	}
	// Forbid self-reports for user targets — likely a UI mistake.
	if body.TargetType == "user" {
		if reported, err := strconv.ParseInt(body.TargetID, 10, 64); err == nil && reported == userID {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "you can't report yourself",
			})
			return
		}
	}

	rep, err := h.reports.Create(userID, body.TargetType, body.TargetID, body.Reason, body.Details)
	if err != nil {
		if errors.Is(err, repositories.ErrDuplicateOpenReport) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "You've already reported this — our team will review it.",
				"code":  "ALREADY_REPORTED",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Audit — info-level so the trail exists without spamming Severity:Warning.
	_, _ = h.audits.Write(
		"REPORT_SUBMITTED", models.SeverityInfo,
		&userID, ptrStr(body.TargetID), ptrStr(body.TargetType),
		fmt.Sprintf("user_id=%d reported %s/%s as %s",
			userID, body.TargetType, body.TargetID, body.Reason),
		map[string]any{
			"reason":     body.Reason,
			"targetType": body.TargetType,
			"targetId":   body.TargetID,
		},
	)

	c.JSON(http.StatusCreated, rep)
}

// ListReasons — GET /api/me/reports/reasons
//
// Returns the canonical set of reason codes + their target-type support.
// The Flutter dropdown reads this so adding a reason is a backend-only
// change.
func (h *ReportsHandler) ListReasons(c *gin.Context) {
	reasons := make([]string, 0, len(allowedReasons))
	for k := range allowedReasons {
		reasons = append(reasons, k)
	}
	c.JSON(http.StatusOK, gin.H{
		"reasons":     reasons,
		"targetTypes": []string{"post", "user", "comment", "community", "message"},
	})
}

// ListMine — GET /api/me/reports
func (h *ReportsHandler) ListMine(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	limit, _ := strconv.Atoi(c.Query("limit"))
	rows, err := h.reports.ListMine(userID, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"reports": rows})
}

// AdminList — GET /api/admin/reports?status=open&targetType=post
func (h *ReportsHandler) AdminList(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	offset, _ := strconv.Atoi(c.Query("offset"))
	filter := repositories.ReportListFilter{
		Status:     strings.TrimSpace(c.Query("status")),
		TargetType: strings.TrimSpace(c.Query("targetType")),
		Limit:      limit,
		Offset:     offset,
	}
	rows, total, err := h.reports.ListAdmin(filter)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"reports": rows,
		"total":   total,
		"limit":   filter.Limit,
		"offset":  filter.Offset,
	})
}

// AdminPendingCount — GET /api/admin/reports/pending-count
// Powers the sidebar badge in the admin dashboard.
func (h *ReportsHandler) AdminPendingCount(c *gin.Context) {
	n, err := h.reports.CountOpen()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// AdminGet — GET /api/admin/reports/:id
func (h *ReportsHandler) AdminGet(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	rep, err := h.reports.GetByID(id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, rep)
}

// resolveBody — request body for resolve / dismiss.
type resolveBody struct {
	Status string `json:"status" binding:"required"`
	Note   string `json:"note"`
}

// AdminResolve — POST /api/admin/reports/:id/resolve
//
// Flips status to one of: resolved_action_taken, resolved_no_action,
// dismissed. Once resolved, the row is read-only.
func (h *ReportsHandler) AdminResolve(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	if adminID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}

	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body resolveBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}

	rep, err := h.reports.Resolve(id, adminID, body.Status, body.Note)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "Report not found or already resolved.",
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	_, _ = h.audits.Write(
		"REPORT_RESOLVED", models.SeverityWarning,
		&adminID, ptrStr(strconv.FormatInt(id, 10)), ptrStr("report"),
		fmt.Sprintf("admin_id=%d resolved report %d as %s", adminID, id, body.Status),
		map[string]any{"status": body.Status, "note": body.Note},
	)

	c.JSON(http.StatusOK, rep)
}

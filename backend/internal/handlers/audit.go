package handlers

import (
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// AuditHandler exposes the admin-only audit log endpoints.
type AuditHandler struct {
	audits *repositories.AuditRepository
}

func NewAuditHandler(audits *repositories.AuditRepository) *AuditHandler {
	return &AuditHandler{audits: audits}
}

// List — GET /api/admin/audit-logs
//
// Query params (all optional):
//
//	?type=AUTH_LOGIN          — comma-separated event types
//	?severity=info|success|warning|error
//	?actorId=1234
//	?targetId=42              — narrow to one specific entity (e.g. one support thread)
//	?targetKind=support_thread — pair with targetId so we don't collide ids across entity kinds
//	?cursor=8421              — id from previous page (rows older than this id)
//	?limit=50                 — default 50, max 200
func (h *AuditHandler) List(c *gin.Context) {
	f := repositories.ListFilter{}
	if t := c.Query("type"); t != "" {
		for _, part := range strings.Split(t, ",") {
			part = strings.TrimSpace(strings.ToUpper(part))
			if part != "" {
				f.Types = append(f.Types, part)
			}
		}
	}
	f.Severity = strings.ToLower(strings.TrimSpace(c.Query("severity")))
	if f.Severity != "" && f.Severity != "info" && f.Severity != "success" &&
		f.Severity != "warning" && f.Severity != "error" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid severity"})
		return
	}
	if a := c.Query("actorId"); a != "" {
		if id, err := strconv.ParseInt(a, 10, 64); err == nil {
			f.ActorID = &id
		}
	}
	f.TargetID = strings.TrimSpace(c.Query("targetId"))
	f.TargetKind = strings.TrimSpace(c.Query("targetKind"))
	if l := c.Query("limit"); l != "" {
		if n, err := strconv.Atoi(l); err == nil {
			f.Limit = n
		}
	}
	if cur := c.Query("cursor"); cur != "" {
		if n, err := strconv.ParseInt(cur, 10, 64); err == nil {
			f.Cursor = n
		}
	}

	rows, err := h.audits.List(f)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []*models.AuditLog{}
	}
	c.JSON(http.StatusOK, gin.H{"events": rows})
}

// Get — GET /api/admin/audit-logs/:id
//
// Single-row fetch for the detail-page drill-in. 404 when the row
// doesn't exist (audit rows are never deleted, but typo'd ids should
// 404 cleanly).
func (h *AuditHandler) Get(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil || id <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	row, err := h.audits.GetByID(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if row == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "audit row not found"})
		return
	}
	c.JSON(http.StatusOK, row)
}

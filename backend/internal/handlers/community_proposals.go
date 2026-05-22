package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// CommunityProposalsHandler — REST surface for the "expert proposes a
// community, admin approves, expert becomes owner" flow.
//
// Three audiences:
//   * Expert  → POST /me/community-proposals + GET /me/community-proposals
//   * Admin   → GET /admin/community-proposals + approve/reject/pending-count
//   * Realtime→ on approve, fan out an event on the proposing user's
//               WS channel so their studio screen updates live.
type CommunityProposalsHandler struct {
	repo  *repositories.CommunityProposalsRepository
	users *repositories.UserRepository
	hub   *realtime.Hub
	audit *repositories.AuditRepository
}

func NewCommunityProposalsHandler(
	repo *repositories.CommunityProposalsRepository,
	users *repositories.UserRepository,
	hub *realtime.Hub,
	audit *repositories.AuditRepository,
) *CommunityProposalsHandler {
	return &CommunityProposalsHandler{
		repo: repo, users: users, hub: hub, audit: audit,
	}
}

// Submit — POST /api/me/community-proposals
//
// Auth gate: only EXPERT can submit. Body:
//
//   { "name": "Halal Tech Saudi", "regionCode": "SA",
//     "description": "Local discussions about Saudi tech equities." }
//
// Returns 409 if the user already has a pending proposal.
func (h *CommunityProposalsHandler) Submit(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "user not found"})
		return
	}
	role := strings.ToUpper(user.Role)
	if role != "EXPERT" {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "only experts can propose communities",
		})
		return
	}

	var body struct {
		Name        string `json:"name"`
		RegionCode  string `json:"regionCode"`
		Description string `json:"description"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Name = strings.TrimSpace(body.Name)
	body.RegionCode = strings.ToUpper(strings.TrimSpace(body.RegionCode))
	body.Description = strings.TrimSpace(body.Description)
	if len(body.Name) < 3 || len(body.Name) > 60 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name must be 3..60 chars"})
		return
	}
	if len(body.Description) < 10 || len(body.Description) > 500 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "description must be 10..500 chars"})
		return
	}

	p, err := h.repo.Submit(userID, body.Name, body.RegionCode, body.Description)
	if err != nil {
		if errors.Is(err, repositories.ErrPendingExists) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "you already have a pending proposal",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Realtime fan-out — broadcast on the admin channel so the dashboard
	// (Sidebar badge + Proposals page + Toaster) updates the moment a
	// new proposal is filed. Same pattern as `application_submitted`
	// (see realtime/listener.go).
	//
	// We include the proposer's display name + email so the toast can say
	// "Sarah Chen proposed Halal Tech KSA" without an extra fetch on the
	// admin side.
	if h.hub != nil {
		proposerName := strings.TrimSpace(user.Email)
		if user.Name.Valid && strings.TrimSpace(user.Name.String) != "" {
			proposerName = strings.TrimSpace(user.Name.String)
		}
		h.hub.PublishJSON(
			realtime.ChannelAdmin,
			"community_proposal_submitted",
			map[string]any{
				"proposalId":    p.ID,
				"name":          p.Name,
				"regionCode":    p.RegionCode,
				"proposerId":    userID,
				"proposerName":  proposerName,
				"proposerEmail": user.Email,
			},
		)
	}

	c.JSON(http.StatusOK, gin.H{"proposal": p})
}

// ListMine — GET /api/me/community-proposals
//
// Returns every proposal the authed user has ever submitted (any
// status), newest-first. Drives the studio "My proposals" tab.
func (h *CommunityProposalsHandler) ListMine(c *gin.Context) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	rows, err := h.repo.ListMine(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"proposals": rows})
}

// AdminList — GET /api/admin/community-proposals?status=pending
func (h *CommunityProposalsHandler) AdminList(c *gin.Context) {
	status := strings.ToLower(strings.TrimSpace(c.Query("status")))
	if status != "" && status != "pending" && status != "approved" && status != "rejected" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid status filter"})
		return
	}
	limit := parseLimit(c.Query("limit"), 100)
	rows, err := h.repo.AdminList(status, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"proposals": rows})
}

// AdminPendingCount — GET /api/admin/community-proposals/pending-count
//
// Powers the dashboard sidebar badge — same pattern as the existing
// expert-applications pending-count endpoint.
func (h *CommunityProposalsHandler) AdminPendingCount(c *gin.Context) {
	n, err := h.repo.PendingCount()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"count": n})
}

// AdminGet — GET /api/admin/community-proposals/:id
//
// Single-row fetch for the detail-page drill-in. 404 if the proposal
// doesn't exist.
func (h *CommunityProposalsHandler) AdminGet(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	p, err := h.repo.GetByID(id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "proposal not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, p)
}

// AdminApprove — POST /api/admin/community-proposals/:id/approve
//
// Creates the community in one transaction (see repo). Fans out a
// realtime event to the proposer so their studio updates live, and
// audit-logs the approval.
func (h *CommunityProposalsHandler) AdminApprove(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	// Snapshot for the realtime event + audit row.
	proposal, err := h.repo.GetByID(id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "proposal not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	communityID, err := h.repo.Approve(id, adminID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Realtime ping — proposer's studio listens for this and refreshes
	// their owned-communities list without a page reload.
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelUser(proposal.UserID),
			"community_proposal_approved",
			map[string]any{
				"proposalId":  proposal.ID,
				"communityId": communityID,
				"name":        proposal.Name,
			},
		)
	}
	h.writeAudit(c, "admin_community_proposal_approve", "info", map[string]any{
		"proposalId":  proposal.ID,
		"communityId": communityID,
		"proposerId":  proposal.UserID,
	})
	c.JSON(http.StatusOK, gin.H{
		"ok":          true,
		"communityId": communityID,
	})
}

// AdminReject — POST /api/admin/community-proposals/:id/reject
//
// Body: { "reason": "Too narrow scope, please broaden..." }
func (h *CommunityProposalsHandler) AdminReject(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Reason = strings.TrimSpace(body.Reason)
	if len(body.Reason) < 3 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "reason required"})
		return
	}
	proposal, err := h.repo.GetByID(id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "proposal not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if err := h.repo.Reject(id, adminID, body.Reason); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if h.hub != nil {
		h.hub.PublishJSON(
			realtime.ChannelUser(proposal.UserID),
			"community_proposal_rejected",
			map[string]any{
				"proposalId": proposal.ID,
				"reason":     body.Reason,
			},
		)
	}
	h.writeAudit(c, "admin_community_proposal_reject", "warning", map[string]any{
		"proposalId": proposal.ID,
		"proposerId": proposal.UserID,
		"reason":     body.Reason,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// writeAudit centralises the audit pattern. Same shape as
// admin_posts.go — failure to log never blocks the action.
func (h *CommunityProposalsHandler) writeAudit(
	c *gin.Context, eventType, severity string, meta map[string]any,
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
	targetKind := "community_proposal"
	_, _ = h.audit.Write(eventType, severity, actor, nil, &targetKind, "", meta)
}

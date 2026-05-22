// Package handlers — community co-ownership endpoints.
//
// Routes (all under /api/me/* or /api/communities/*):
//
//   POST   /api/me/communities/:id/invitations         — owner invites
//   GET    /api/me/community-invitations               — invitee's pending list
//   GET    /api/me/communities/:id/invitations         — owner's outbox
//   POST   /api/me/community-invitations/:id/accept    — invitee accepts
//   POST   /api/me/community-invitations/:id/reject    — invitee rejects
//   DELETE /api/me/community-invitations/:id           — owner cancels
//   GET    /api/communities/:id/owners                 — public — primary + co-owners
//   DELETE /api/me/communities/:id/owners/:userId      — primary owner demotes a co-owner
package handlers

import (
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"

	"halalstocks/internal/models"
	"halalstocks/internal/realtime"
	"halalstocks/internal/repositories"
)

type CommunityOwnersHandler struct {
	repo   *repositories.CommunityOwnersRepo
	social *repositories.SocialRepository
	users  *repositories.UserRepository
	audits *repositories.AuditRepository
	hub    *realtime.Hub
}

func NewCommunityOwnersHandler(
	repo *repositories.CommunityOwnersRepo,
	social *repositories.SocialRepository,
	users *repositories.UserRepository,
) *CommunityOwnersHandler {
	return &CommunityOwnersHandler{repo: repo, social: social, users: users}
}

func (h *CommunityOwnersHandler) SetAuditRepo(a *repositories.AuditRepository) { h.audits = a }
func (h *CommunityOwnersHandler) SetHub(hub *realtime.Hub)                     { h.hub = hub }

// ── auth helper ─────────────────────────────────────────────────────
// callerID returns the JWT-resolved user id, or writes 401 + 0.
func (h *CommunityOwnersHandler) callerID(c *gin.Context) int64 {
	uid, _ := c.Get("user_id")
	id, _ := uid.(int64)
	if id == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return 0
	}
	return id
}

// requirePrimaryOwner — caller must be the community's primary owner
// (the row in communities.owner_id). Co-owners CANNOT invite or
// remove other co-owners — that authority stays with the original
// owner to prevent a co-owner from pushing the primary out.
func (h *CommunityOwnersHandler) requirePrimaryOwner(
	c *gin.Context, communityID string,
) (callerID int64, ok bool) {
	cid := h.callerID(c)
	if cid == 0 {
		return 0, false
	}
	owner, err := h.social.CommunityOwnerID(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return 0, false
	}
	if owner != cid {
		// Admin override — same pattern as the rest of the codebase.
		if h.users != nil {
			if u, _ := h.users.GetByID(cid); u != nil && u.Role == "ADMIN" {
				return cid, true
			}
		}
		c.JSON(http.StatusForbidden, gin.H{"error": "not the community owner"})
		return 0, false
	}
	return cid, true
}

// ─────────────────────────────────────────────────────────────────────
// Invitations
// ─────────────────────────────────────────────────────────────────────

type sendInvitationReq struct {
	// Caller sends EITHER the platform user id OR the public expert id
	// (`ex_26`). Mobile uses expertId because the /api/experts feed
	// doesn't expose user_id; admin tools that already have the user
	// row send userId directly. Exactly one must be set.
	InvitedUserID   int64  `json:"invitedUserId"`
	InvitedExpertID string `json:"invitedExpertId"`
	Message         string `json:"message"`
}

// SendInvitation — POST /api/me/communities/:id/invitations.
func (h *CommunityOwnersHandler) SendInvitation(c *gin.Context) {
	communityID := c.Param("id")
	callerID, ok := h.requirePrimaryOwner(c, communityID)
	if !ok {
		return
	}
	var req sendInvitationReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	// Resolve invitedExpertId → invitedUserId when needed. Two paths
	// because the mobile picker only has expert id; the admin tools
	// already carry user ids. Either input is fine.
	if req.InvitedUserID == 0 && req.InvitedExpertID != "" {
		uid, err := h.repo.LookupUserByExpertID(strings.TrimSpace(req.InvitedExpertID))
		if err != nil {
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "could not resolve expert to user",
				"code":  "EXPERT_NOT_FOUND",
			})
			return
		}
		req.InvitedUserID = uid
	}
	if req.InvitedUserID == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invitedUserId or invitedExpertId required"})
		return
	}
	// Don't allow inviting yourself.
	if req.InvitedUserID == callerID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot invite yourself"})
		return
	}

	inv, err := h.repo.CreateInvitation(
		communityID, req.InvitedUserID, callerID, strings.TrimSpace(req.Message),
	)
	if err != nil {
		// Map sentinel errors to specific HTTP codes so the mobile UI
		// can show targeted messages.
		switch {
		case errors.Is(err, repositories.ErrInvitationAlreadyPending):
			c.JSON(http.StatusConflict, gin.H{
				"error": "this expert already has a pending invitation",
				"code":  "INVITATION_PENDING",
			})
		case errors.Is(err, repositories.ErrAlreadyOwner):
			c.JSON(http.StatusConflict, gin.H{
				"error": "this user is already an owner",
				"code":  "ALREADY_OWNER",
			})
		case errors.Is(err, repositories.ErrInviteeNotExpert):
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "only verified experts can be invited as co-owners",
				"code":  "NOT_EXPERT",
			})
		default:
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		}
		return
	}

	// Audit + realtime ping the invitee on their user channel.
	h.auditInvitationEvent(c, "send", inv, callerID)
	if h.hub != nil {
		h.hub.PublishJSON(realtime.ChannelUser(inv.InvitedUserID), "community_invitation_received", inv)
	}

	c.JSON(http.StatusOK, gin.H{"invitation": inv})
}

// ListIncoming — GET /api/me/community-invitations[?status=pending].
func (h *CommunityOwnersHandler) ListIncoming(c *gin.Context) {
	cid := h.callerID(c)
	if cid == 0 {
		return
	}
	status := strings.TrimSpace(c.Query("status"))
	invs, err := h.repo.ListIncoming(cid, status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if invs == nil {
		invs = []*repositories.CommunityInvitation{}
	}
	c.JSON(http.StatusOK, gin.H{"invitations": invs})
}

// ListForCommunity — GET /api/me/communities/:id/invitations
// (primary owner's outbox).
func (h *CommunityOwnersHandler) ListForCommunity(c *gin.Context) {
	communityID := c.Param("id")
	if _, ok := h.requirePrimaryOwner(c, communityID); !ok {
		return
	}
	status := strings.TrimSpace(c.Query("status"))
	invs, err := h.repo.ListForCommunity(communityID, status)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if invs == nil {
		invs = []*repositories.CommunityInvitation{}
	}
	c.JSON(http.StatusOK, gin.H{"invitations": invs})
}

// Accept — POST /api/me/community-invitations/:id/accept.
func (h *CommunityOwnersHandler) Accept(c *gin.Context) {
	cid := h.callerID(c)
	if cid == 0 {
		return
	}
	invID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invitation id"})
		return
	}
	inv, err := h.repo.AcceptInvitation(invID, cid)
	if err != nil {
		h.mapInvitationError(c, err)
		return
	}
	h.auditInvitationEvent(c, "accept", inv, cid)
	if h.hub != nil {
		// Tell the inviter so their UI can drop the pending pill.
		h.hub.PublishJSON(realtime.ChannelUser(inv.InvitedBy), "community_invitation_accepted", inv)
	}
	c.JSON(http.StatusOK, gin.H{"invitation": inv})
}

// Reject — POST /api/me/community-invitations/:id/reject.
func (h *CommunityOwnersHandler) Reject(c *gin.Context) {
	cid := h.callerID(c)
	if cid == 0 {
		return
	}
	invID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invitation id"})
		return
	}
	inv, err := h.repo.RejectInvitation(invID, cid)
	if err != nil {
		h.mapInvitationError(c, err)
		return
	}
	h.auditInvitationEvent(c, "reject", inv, cid)
	if h.hub != nil {
		h.hub.PublishJSON(realtime.ChannelUser(inv.InvitedBy), "community_invitation_rejected", inv)
	}
	c.JSON(http.StatusOK, gin.H{"invitation": inv})
}

// Cancel — DELETE /api/me/community-invitations/:id (primary owner).
func (h *CommunityOwnersHandler) Cancel(c *gin.Context) {
	cid := h.callerID(c)
	if cid == 0 {
		return
	}
	invID, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid invitation id"})
		return
	}
	inv, err := h.repo.CancelInvitation(invID, cid)
	if err != nil {
		h.mapInvitationError(c, err)
		return
	}
	h.auditInvitationEvent(c, "cancel", inv, cid)
	c.JSON(http.StatusOK, gin.H{"invitation": inv})
}

// ─────────────────────────────────────────────────────────────────────
// Owners
// ─────────────────────────────────────────────────────────────────────

// ListOwners — GET /api/communities/:id/owners (public; no auth
// gating — anyone can see who runs a community).
func (h *CommunityOwnersHandler) ListOwners(c *gin.Context) {
	communityID := c.Param("id")
	// Primary owner first.
	primaryID, err := h.social.CommunityOwnerID(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	var primary map[string]any
	if primaryID != 0 && h.users != nil {
		u, _ := h.users.GetByID(primaryID)
		if u != nil {
			primary = map[string]any{
				"userId": u.ID,
				"name":   nullToString(u.Name),
				"email":  u.Email,
				"expertId": nullToString(u.ExpertID),
				"role":   "primary",
			}
		}
	}
	co, err := h.repo.ListCoOwners(communityID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if co == nil {
		co = []*repositories.CommunityCoOwner{}
	}
	c.JSON(http.StatusOK, gin.H{
		"primary":   primary,
		"coOwners":  co,
	})
}

// RemoveCoOwner — DELETE /api/me/communities/:id/owners/:userId.
func (h *CommunityOwnersHandler) RemoveCoOwner(c *gin.Context) {
	communityID := c.Param("id")
	callerID, ok := h.requirePrimaryOwner(c, communityID)
	if !ok {
		return
	}
	userIDStr := c.Param("userId")
	userID, err := strconv.ParseInt(userIDStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid userId"})
		return
	}
	// Defensive: can't remove yourself via this route (you'd be
	// removing yourself only if you were a co-owner of a community
	// you somehow own primarily — but the requirePrimaryOwner check
	// already established otherwise).
	if userID == callerID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot remove yourself"})
		return
	}
	if err := h.repo.RemoveCoOwner(communityID, userID); err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "user is not a co-owner"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Audit.
	if h.audits != nil {
		targetID := strconv.FormatInt(userID, 10)
		targetKind := "user"
		_, _ = h.audits.Write(
			models.AuditUserRoleChanged, // closest existing event type
			models.SeverityInfo,
			&callerID,
			&targetID,
			&targetKind,
			fmt.Sprintf("Removed co-owner from community %s", communityID),
			map[string]any{
				"communityId": communityID,
				"removedUser": userID,
				"action":      "co_owner_removed",
			},
		)
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// ─────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────

func (h *CommunityOwnersHandler) mapInvitationError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, repositories.ErrInvitationNotPending):
		c.JSON(http.StatusConflict, gin.H{"error": "invitation is no longer pending"})
	case errors.Is(err, repositories.ErrInvitationWrongUser):
		c.JSON(http.StatusForbidden, gin.H{"error": "invitation does not belong to caller"})
	default:
		if err.Error() == "invitation not found" {
			c.JSON(http.StatusNotFound, gin.H{"error": "invitation not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
	}
}

func (h *CommunityOwnersHandler) auditInvitationEvent(
	c *gin.Context, action string, inv *repositories.CommunityInvitation, actorID int64,
) {
	if h.audits == nil {
		return
	}
	targetID := strconv.FormatInt(inv.ID, 10)
	targetKind := "community_invitation"
	_, _ = h.audits.Write(
		models.AuditUserRoleChanged, // reuse closest event class
		models.SeverityInfo,
		&actorID,
		&targetID,
		&targetKind,
		fmt.Sprintf("Community invitation %s (community=%s)", action, inv.CommunityID),
		map[string]any{
			"action":          action,
			"invitationId":    inv.ID,
			"communityId":     inv.CommunityID,
			"invitedUserId":   inv.InvitedUserID,
			"invitedBy":       inv.InvitedBy,
			"status":          inv.Status,
		},
	)
}

func nullToString(ns sql.NullString) string {
	if ns.Valid {
		return ns.String
	}
	return ""
}

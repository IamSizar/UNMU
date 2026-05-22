package handlers

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"

	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// AdminCommunitiesHandler — admin-direct community CRUD. Lives
// alongside the proposal flow but takes a separate path (admin
// chooses to spin up an "official" community without going through
// an expert proposal). All mutations are audit-logged.
type AdminCommunitiesHandler struct {
	social *repositories.SocialRepository
	users  *repositories.UserRepository
	audit  *repositories.AuditRepository
}

func NewAdminCommunitiesHandler(
	social *repositories.SocialRepository,
	users *repositories.UserRepository,
	audit *repositories.AuditRepository,
) *AdminCommunitiesHandler {
	return &AdminCommunitiesHandler{social: social, users: users, audit: audit}
}

// List — GET /admin/communities
func (h *AdminCommunitiesHandler) List(c *gin.Context) {
	rows, err := h.social.AdminListCommunities()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"communities": rows})
}

// Create — POST /admin/communities
//
// Body: { "id": "c_halal_etf", "name": "Halal ETFs", "tagline": "...",
//         "regionCode": "GL", "ownerId": 1003 }
//
// id + name are required. ownerId is optional (0 → no owner; matches
// the "official admin-managed" pattern, though current policy is
// every community must have an owner — admin can pass any user id).
func (h *AdminCommunitiesHandler) Create(c *gin.Context) {
	var body struct {
		ID         string `json:"id"`
		Name       string `json:"name"`
		Tagline    string `json:"tagline"`
		RegionCode string `json:"regionCode"`
		OwnerID    int64  `json:"ownerId"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.ID = strings.TrimSpace(body.ID)
	body.Name = strings.TrimSpace(body.Name)
	body.RegionCode = strings.ToUpper(strings.TrimSpace(body.RegionCode))

	if !validCommunityID(body.ID) {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "id must be 2..40 chars, lowercase a-z / 0-9 / underscore",
		})
		return
	}
	if len(body.Name) < 3 || len(body.Name) > 60 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "name must be 3..60 chars"})
		return
	}

	if err := h.social.AdminCreateCommunity(
		body.ID, body.Name, body.Tagline, body.RegionCode, body.OwnerID,
	); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(c, "admin_community_create", "info", map[string]any{
		"communityId": body.ID,
		"name":        body.Name,
		"ownerId":     body.OwnerID,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true, "id": body.ID})
}

// Update — PATCH /admin/communities/:id
//
// Body: any subset of {
//   "name", "tagline", "description", "rules", "coverUrl", "avatarUrl",
//   "isPublic", "category", "regionCode", "ownerId", "tags"
// }. Pass `ownerId: -1` to clear the owner explicitly.
//
// `tags` is a full-replace list (not append) — pass [] to clear tags.
func (h *AdminCommunitiesHandler) Update(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	var body struct {
		Name        *string   `json:"name"`
		Tagline     *string   `json:"tagline"`
		Description *string   `json:"description"`
		Rules       *string   `json:"rules"`
		CoverURL    *string   `json:"coverUrl"`
		// AvatarURL (mig 0028) — square logo. Same null-vs-empty-vs-set
		// semantics as CoverURL.
		AvatarURL   *string   `json:"avatarUrl"`
		IsPublic    *bool     `json:"isPublic"`
		Category    *string   `json:"category"`
		RegionCode  *string   `json:"regionCode"`
		OwnerID     *int64    `json:"ownerId"`
		Tags        *[]string `json:"tags"`
		// Step-23 — admin can also flip pricing.
		JoinPriceMonthlyCents *int    `json:"joinPriceMonthlyCents"`
		JoinPriceYearlyCents  *int    `json:"joinPriceYearlyCents"`
		PriceCurrency         *string `json:"priceCurrency"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	upd := repositories.AdminCommunityUpdate{}
	if body.Name != nil {
		s := strings.TrimSpace(*body.Name)
		upd.Name = &s
	}
	if body.Tagline != nil {
		s := strings.TrimSpace(*body.Tagline)
		upd.Tagline = &s
	}
	if body.Description != nil {
		s := strings.TrimSpace(*body.Description)
		upd.Description = &s
	}
	if body.Rules != nil {
		s := strings.TrimSpace(*body.Rules)
		upd.Rules = &s
	}
	if body.CoverURL != nil {
		s := strings.TrimSpace(*body.CoverURL)
		upd.CoverURL = &s
	}
	if body.AvatarURL != nil {
		s := strings.TrimSpace(*body.AvatarURL)
		upd.AvatarURL = &s
	}
	if body.IsPublic != nil {
		upd.IsPublic = body.IsPublic
	}
	if body.Category != nil {
		s := strings.TrimSpace(*body.Category)
		upd.Category = &s
	}
	if body.RegionCode != nil {
		s := strings.ToUpper(strings.TrimSpace(*body.RegionCode))
		upd.RegionCode = &s
	}
	if body.OwnerID != nil {
		upd.OwnerID = body.OwnerID
	}
	if body.JoinPriceMonthlyCents != nil {
		upd.JoinPriceMonthlyCents = body.JoinPriceMonthlyCents
	}
	if body.JoinPriceYearlyCents != nil {
		upd.JoinPriceYearlyCents = body.JoinPriceYearlyCents
	}
	if body.PriceCurrency != nil {
		s := strings.ToLower(strings.TrimSpace(*body.PriceCurrency))
		upd.PriceCurrency = &s
	}
	if err := h.social.AdminUpdateCommunity(id, upd); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if body.Tags != nil {
		if err := h.social.ReplaceCommunityTags(id, *body.Tags); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
	}
	h.writeAudit(c, "admin_community_update", "info", map[string]any{
		"communityId": id,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// Delete — DELETE /admin/communities/:id
func (h *AdminCommunitiesHandler) Delete(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	if err := h.social.AdminDeleteCommunity(id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "community not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(c, "admin_community_delete", "warning", map[string]any{
		"communityId": id,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// ListMembers — GET /admin/communities/:id/members
func (h *AdminCommunitiesHandler) ListMembers(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	rows, err := h.social.AdminListCommunityMembers(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"members": rows})
}

// RemoveMember — DELETE /admin/communities/:id/members/:userId
//
// Admin-only kick. Like the owner-side equivalent, blocks removing
// the community owner — admin must transfer/replace ownership
// first via TransferOwner.
func (h *AdminCommunitiesHandler) RemoveMember(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	targetID, perr := strconv.ParseInt(c.Param("userId"), 10, 64)
	if perr != nil || targetID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}
	ownerID, _ := h.social.CommunityOwnerID(id)
	if ownerID == targetID {
		c.JSON(http.StatusConflict, gin.H{
			"error": "transfer ownership before removing the owner",
		})
		return
	}
	if err := h.social.RemoveMember(id, targetID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{
				"error": "user is not a member of this community",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(c, "admin_community_member_remove", "warning", map[string]any{
		"communityId":  id,
		"targetUserId": targetID,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// TransferOwner — POST /admin/communities/:id/transfer-ownership
//
// Body: { "newOwnerId": <int64> }. Admin override of the owner-side
// transfer flow — useful when the previous owner has gone inactive
// or been banned. New owner must already be a member.
func (h *AdminCommunitiesHandler) TransferOwner(c *gin.Context) {
	id := strings.TrimSpace(c.Param("id"))
	var body struct {
		NewOwnerID int64 `json:"newOwnerId"`
	}
	if err := c.ShouldBindJSON(&body); err != nil || body.NewOwnerID <= 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "newOwnerId required"})
		return
	}
	isMember, err := h.social.IsMemberOfCommunity(body.NewOwnerID, id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if !isMember {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner must be a member of the community",
		})
		return
	}
	// Same role gate as the owner-side flow — only EXPERT (or ADMIN
	// override) can become the new owner of a community.
	target, err := h.users.GetByID(body.NewOwnerID)
	if err != nil || target == nil {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner not found",
		})
		return
	}
	if strings.ToUpper(target.Role) != "EXPERT" &&
		strings.ToUpper(target.Role) != "ADMIN" {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "new owner must be an expert",
		})
		return
	}
	if err := h.social.TransferOwnership(id, body.NewOwnerID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	h.writeAudit(c, "admin_community_transfer_owner", "warning", map[string]any{
		"communityId": id,
		"newOwnerId":  body.NewOwnerID,
	})
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// writeAudit centralises the audit pattern. Failure to log never
// blocks the action.
func (h *AdminCommunitiesHandler) writeAudit(
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
	targetKind := "community"
	_, _ = h.audit.Write(eventType, severity, actor, nil, &targetKind, "", meta)
}

// validCommunityID — admin-supplied id must be lowercase slug-y.
func validCommunityID(id string) bool {
	if len(id) < 2 || len(id) > 40 {
		return false
	}
	for _, r := range id {
		ok := (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_'
		if !ok {
			return false
		}
	}
	return true
}

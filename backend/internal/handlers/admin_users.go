package handlers

import (
	"halalstocks/internal/repositories"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// AdminUsersHandler powers the admin dashboard's Users page — list every
// user with filters, change roles, etc.
type AdminUsersHandler struct {
	users  *repositories.UserRepository
	social *repositories.SocialRepository
}

func NewAdminUsersHandler(
	users *repositories.UserRepository,
	social *repositories.SocialRepository,
) *AdminUsersHandler {
	return &AdminUsersHandler{users: users, social: social}
}

// List — GET /api/admin/users
//
//	?q=<search>     — partial email / name match (case-insensitive)
//	?role=USER|EXPERT|ADMIN
//	?cursor=<id>    — id of last row from previous page (rows older than this id)
//	?limit=<n>      — default 50, max 200
func (h *AdminUsersHandler) List(c *gin.Context) {
	q := strings.TrimSpace(c.Query("q"))
	role := strings.ToUpper(strings.TrimSpace(c.Query("role")))
	if role != "" && role != "USER" && role != "EXPERT" && role != "ADMIN" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid role filter"})
		return
	}

	var cursor int64
	if s := c.Query("cursor"); s != "" {
		if v, err := strconv.ParseInt(s, 10, 64); err == nil {
			cursor = v
		}
	}
	limit := 50
	if s := c.Query("limit"); s != "" {
		if v, err := strconv.Atoi(s); err == nil {
			limit = v
		}
	}

	rows, err := h.users.ListAdminUsers(q, role, cursor, limit)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []repositories.AdminUserRow{}
	}
	c.JSON(http.StatusOK, gin.H{"users": rows})
}

// UpdateRole — PATCH /api/admin/users/:id/role
//
// Body: { "role": "USER" | "EXPERT" | "ADMIN" }
//
// The DB trigger from migration 0005 takes care of writing an audit row +
// firing the realtime user_role_changed event.
func (h *AdminUsersHandler) UpdateRole(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var body struct {
		Role string `json:"role" binding:"required"`
	}
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Role = strings.ToUpper(strings.TrimSpace(body.Role))

	// Don't let the admin demote themselves accidentally — would lock them
	// out of the dashboard.
	uidVal, _ := c.Get("user_id")
	if uid, ok := uidVal.(int64); ok && uid == id && body.Role != "ADMIN" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "cannot demote yourself"})
		return
	}

	if err := h.users.UpdateRole(id, body.Role); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Return the fresh row so the UI can swap in the updated state.
	user, err := h.users.GetByID(id)
	if err != nil || user == nil {
		c.JSON(http.StatusOK, gin.H{"ok": true})
		return
	}
	expertID := ""
	if user.ExpertID.Valid {
		expertID = user.ExpertID.String
	}
	name := ""
	if user.Name.Valid {
		name = user.Name.String
	}
	c.JSON(http.StatusOK, gin.H{
		"id":       user.ID,
		"email":    user.Email,
		"name":     name,
		"role":     user.Role,
		"expertId": expertID,
	})
}

// ListCommunities — GET /api/admin/users/:id/communities
//
// Returns every community the user is a member of, plus the community's
// pricing and the user's most-recent subscription row for each one. Drives
// the "Communities" section on the admin UserDetail page so the team can
// see who's in what + what they paid + the live status of every paid
// membership without bouncing between pages.
func (h *AdminUsersHandler) ListCommunities(c *gin.Context) {
	idStr := c.Param("id")
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if h.social == nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "social repo not wired"})
		return
	}
	rows, err := h.social.AdminListUserCommunities(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if rows == nil {
		rows = []*repositories.AdminUserCommunity{}
	}
	c.JSON(http.StatusOK, gin.H{"communities": rows})
}

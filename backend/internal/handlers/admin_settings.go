package handlers

import (
	"net/http"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"

	"github.com/gin-gonic/gin"
)

// AdminSettingsHandler exposes the global feature flags. The GET is also
// mounted publicly (as /api/app-config) so the mobile app can hide disabled
// features; the PATCH is admin-only (wired under the /admin group).
type AdminSettingsHandler struct {
	settings *repositories.AppSettingsRepository
	audits   *repositories.AuditRepository // nullable
}

func NewAdminSettingsHandler(
	settings *repositories.AppSettingsRepository,
	audits *repositories.AuditRepository,
) *AdminSettingsHandler {
	return &AdminSettingsHandler{settings: settings, audits: audits}
}

// Get — GET /api/admin/settings  AND  GET /api/app-config (public).
// Returns the current flag values.
func (h *AdminSettingsHandler) Get(c *gin.Context) {
	c.JSON(http.StatusOK, h.settings.Flags())
}

type updateSettingsRequest struct {
	CommunityEnabled      *bool `json:"communityEnabled"`
	CommunityChatEnabled  *bool `json:"communityChatEnabled"`
	CommunityPostsEnabled *bool `json:"communityPostsEnabled"`
}

// Update — PATCH /api/admin/settings. Only the keys present in the body are
// changed (pointer fields → nil means "leave as-is"), so the dashboard can
// flip one toggle without clobbering the others. Returns the new flags.
func (h *AdminSettingsHandler) Update(c *gin.Context) {
	var req updateSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	changed := map[string]any{}
	if req.CommunityEnabled != nil {
		if err := h.settings.Set("community_enabled", *req.CommunityEnabled); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save setting"})
			return
		}
		changed["communityEnabled"] = *req.CommunityEnabled
	}
	if req.CommunityChatEnabled != nil {
		if err := h.settings.Set("community_chat_enabled", *req.CommunityChatEnabled); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save setting"})
			return
		}
		changed["communityChatEnabled"] = *req.CommunityChatEnabled
	}
	if req.CommunityPostsEnabled != nil {
		if err := h.settings.Set("community_posts_enabled", *req.CommunityPostsEnabled); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save setting"})
			return
		}
		changed["communityPostsEnabled"] = *req.CommunityPostsEnabled
	}

	// Best-effort audit trail.
	if h.audits != nil && len(changed) > 0 {
		var actorID *int64
		if v, ok := c.Get("user_id"); ok {
			if id, ok2 := v.(int64); ok2 {
				actorID = &id
			}
		}
		_, _ = h.audits.Write(
			"CONFIG_CHANGED", models.SeverityWarning,
			actorID, ptrStr("app_settings"), ptrStr("settings"),
			"admin updated community feature flags",
			changed,
		)
	}

	c.JSON(http.StatusOK, h.settings.Flags())
}

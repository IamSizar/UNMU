package handlers

import (
	"net/http"

	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"halalstocks/internal/shariah"

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

// screeningThresholdsPayload is the wire shape for both the GET and PUT below.
type screeningThresholdsPayload struct {
	DebtFail  float64 `json:"debtFail"`
	DebtWarn  float64 `json:"debtWarn"`
	DebtPass  float64 `json:"debtPass"`
	DebtGood  float64 `json:"debtGood"`
	HaramFail float64 `json:"haramFail"`
	HaramWarn float64 `json:"haramWarn"`
	HaramPass float64 `json:"haramPass"`
	HaramGood float64 `json:"haramGood"`
}

func (h *AdminSettingsHandler) currentThresholds() screeningThresholdsPayload {
	return screeningThresholdsPayload{
		DebtFail:  h.settings.ScreeningDebtFail(),
		DebtWarn:  h.settings.ScreeningDebtWarn(),
		DebtPass:  h.settings.ScreeningDebtPass(),
		DebtGood:  h.settings.ScreeningDebtGood(),
		HaramFail: h.settings.ScreeningHaramFail(),
		HaramWarn: h.settings.ScreeningHaramWarn(),
		HaramPass: h.settings.ScreeningHaramPass(),
		HaramGood: h.settings.ScreeningHaramGood(),
	}
}

// GetScreeningThresholds — GET /api/admin/screening-thresholds.
// Returns the ladder currently in effect (defaults, until an admin overrides them).
func (h *AdminSettingsHandler) GetScreeningThresholds(c *gin.Context) {
	c.JSON(http.StatusOK, h.currentThresholds())
}

// UpdateScreeningThresholds — PUT /api/admin/screening-thresholds.
//
// SHARIAH-REVIEW: this endpoint lets an admin change what the app calls
// "HALAL" for every stock, immediately, for every user. It exists so the
// methodology doesn't require a redeploy — it does NOT exist so the ladder
// gets tuned casually. Restrict who can call it and require sign-off from a
// qualified Shariah advisor before changing production values.
func (h *AdminSettingsHandler) UpdateScreeningThresholds(c *gin.Context) {
	var req screeningThresholdsPayload
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Sanity bounds — percentages, and each "warn/fail" ceiling must sit at or
	// above the corresponding "pass/good" floor, or the grading ladder in
	// screener.go silently misbehaves (e.g. DOUBTFUL never reachable).
	if req.DebtGood < 0 || req.DebtPass < req.DebtGood || req.DebtWarn < req.DebtPass || req.DebtFail < req.DebtWarn ||
		req.HaramGood < 0 || req.HaramPass < req.HaramGood || req.HaramWarn < req.HaramPass || req.HaramFail < req.HaramWarn ||
		req.DebtFail > 100 || req.HaramFail > 100 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "thresholds must be ascending percentages (good ≤ pass ≤ warn ≤ fail ≤ 100)"})
		return
	}

	updates := map[string]float64{
		"screening_debt_fail": req.DebtFail, "screening_debt_warn": req.DebtWarn,
		"screening_debt_pass": req.DebtPass, "screening_debt_good": req.DebtGood,
		"screening_haram_fail": req.HaramFail, "screening_haram_warn": req.HaramWarn,
		"screening_haram_pass": req.HaramPass, "screening_haram_good": req.HaramGood,
	}
	for key, val := range updates {
		if err := h.settings.SetFloat(key, val); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save threshold"})
			return
		}
	}

	// Apply immediately — no restart required.
	shariah.SetThresholds(shariah.Thresholds{
		DebtFail: req.DebtFail, DebtWarn: req.DebtWarn, DebtPass: req.DebtPass, DebtGood: req.DebtGood,
		HaramFail: req.HaramFail, HaramWarn: req.HaramWarn, HaramPass: req.HaramPass, HaramGood: req.HaramGood,
	})

	if h.audits != nil {
		var actorID *int64
		if v, ok := c.Get("user_id"); ok {
			if id, ok2 := v.(int64); ok2 {
				actorID = &id
			}
		}
		auditPayload := map[string]any{}
		for k, v := range updates {
			auditPayload[k] = v
		}
		_, _ = h.audits.Write(
			"CONFIG_CHANGED", models.SeverityWarning,
			actorID, ptrStr("shariah_thresholds"), ptrStr("screening"),
			"admin updated Shariah screening thresholds",
			auditPayload,
		)
	}

	c.JSON(http.StatusOK, h.currentThresholds())
}

type updateSettingsRequest struct {
	CommunityEnabled      *bool `json:"communityEnabled"`
	CommunityChatEnabled  *bool `json:"communityChatEnabled"`
	CommunityPostsEnabled *bool `json:"communityPostsEnabled"`
	TestAccountEnabled    *bool `json:"testAccountEnabled"`
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
	if req.TestAccountEnabled != nil {
		if err := h.settings.Set("test_account_enabled", *req.TestAccountEnabled); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to save setting"})
			return
		}
		changed["testAccountEnabled"] = *req.TestAccountEnabled
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

package handlers

import (
	"halalstocks/internal/repositories"
	"log"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// StudioHandler — the per-expert "studio" endpoints. These power the
// expert dashboard on the mobile app:
//
//	GET   /me/expert/dashboard   — metrics tile + recent subs (Phase 3.1)
//	GET   /me/expert/earnings    — daily revenue history    (Phase 3.3)
//	PATCH /me/expert/pricing     — let an expert change their own price
//	                              tiers, without going through admin
//	                              (Phase 3.2).
//
// All routes are gated by the auth middleware AND by an in-handler
// expert-self check: the caller's user row must have an expert_id, and
// the dashboard always serves that expert's data — there is no
// :expertId param so one expert can never read another's metrics by
// changing a URL.
type StudioHandler struct {
	users   *repositories.UserRepository
	social  *repositories.SocialRepository
	subs    *repositories.ExpertSubscriptionRepository
}

func NewStudioHandler(
	users *repositories.UserRepository,
	social *repositories.SocialRepository,
	subs *repositories.ExpertSubscriptionRepository,
) *StudioHandler {
	return &StudioHandler{users: users, social: social, subs: subs}
}

// resolveMyExpertID — pulls the caller's user row, ensures they're an
// expert (has expert_id), and returns that id. On any failure it writes
// the appropriate 4xx/5xx and returns ("", false) so the handler can
// early-return.
func (h *StudioHandler) resolveMyExpertID(c *gin.Context) (string, bool) {
	uid, _ := c.Get("user_id")
	userID, _ := uid.(int64)
	if userID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return "", false
	}
	user, err := h.users.GetByID(userID)
	if err != nil || user == nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return "", false
	}
	if !user.ExpertID.Valid || strings.TrimSpace(user.ExpertID.String) == "" {
		c.JSON(http.StatusForbidden, gin.H{
			"error": "Only experts have a studio dashboard.",
			"code":  "NOT_EXPERT",
		})
		return "", false
	}
	return user.ExpertID.String, true
}

// ─── /me/expert/dashboard (GET) ─────────────────────────────────────────

// dashboardResponse — one-shot payload powering the studio header row.
// Combines expert pricing + subscriber + engagement totals so the
// mobile screen only does ONE call on mount, not three.
type dashboardResponse struct {
	ExpertID     string                                 `json:"expertId"`
	ExpertName   string                                 `json:"expertName"`
	MonthlyCents int                                    `json:"monthlyPriceCents"`
	YearlyCents  int                                    `json:"yearlyPriceCents"`
	Currency     string                                 `json:"priceCurrency"`
	Subscribers  *repositories.ExpertTotals             `json:"subscribers"`
	Engagement   *repositories.ExpertEngagementTotals   `json:"engagement"`
}

// Dashboard — GET /api/me/expert/dashboard
func (h *StudioHandler) Dashboard(c *gin.Context) {
	expertID, ok := h.resolveMyExpertID(c)
	if !ok {
		return
	}
	expert, err := h.social.GetExpert(expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if expert == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "expert profile missing"})
		return
	}

	subs, err := h.subs.TotalsForExpert(expertID)
	if err != nil {
		log.Printf("[studio] subs totals: %v", err)
	}
	engagement, err := h.social.ExpertEngagementTotalsForExpert(expertID)
	if err != nil {
		log.Printf("[studio] engagement totals: %v", err)
	}

	c.JSON(http.StatusOK, dashboardResponse{
		ExpertID:     expertID,
		ExpertName:   expert.Name,
		MonthlyCents: expert.MonthlyPriceCents,
		YearlyCents:  expert.YearlyPriceCents,
		Currency:     strings.TrimSpace(expert.PriceCurrency),
		Subscribers:  subs,
		Engagement:   engagement,
	})
}

// ─── /me/expert/earnings (GET) ──────────────────────────────────────────

// Earnings — GET /api/me/expert/earnings?days=30
//
// Returns the daily revenue history for the expert. Default window is
// 30 days; capped at 365.
func (h *StudioHandler) Earnings(c *gin.Context) {
	expertID, ok := h.resolveMyExpertID(c)
	if !ok {
		return
	}
	days, _ := strconv.Atoi(c.DefaultQuery("days", "30"))
	if days <= 0 {
		days = 30
	}
	if days > 365 {
		days = 365
	}

	history, err := h.subs.EarningsHistory(expertID, days)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	totals, err := h.subs.TotalsForExpert(expertID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Sum the windowed revenue too — this is the "Last N days" tile on
	// the earnings screen and is cheaper to compute server-side.
	windowed := 0
	for _, p := range history {
		windowed += p.RevenueCents
	}

	c.JSON(http.StatusOK, gin.H{
		"days":            days,
		"windowRevenue":   windowed,
		"lifetimeRevenue": totals.LifetimeRevenue,
		"activeRevenue":   totals.ActiveRevenue,
		"currency":        totals.Currency,
		"history":         history,
	})
}

// ─── /me/expert/pricing (PATCH) ─────────────────────────────────────────

// pricingBody — request body. Both fields are USD cents, validated
// against the same bounds as the admin variant so an expert can't price
// their plan into the millions.
type pricingBody struct {
	MonthlyCents int `json:"monthlyCents" binding:"min=0,max=1000000"`
	YearlyCents  int `json:"yearlyCents"  binding:"min=0,max=10000000"`
}

// SetPricing — PATCH /api/me/expert/pricing
//
// The expert updates their OWN price tiers. Admins still have the
// existing /admin/experts/:id/pricing route for overriding from the
// dashboard; this is the self-serve path.
func (h *StudioHandler) SetPricing(c *gin.Context) {
	expertID, ok := h.resolveMyExpertID(c)
	if !ok {
		return
	}
	var body pricingBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	if body.MonthlyCents < 0 || body.YearlyCents < 0 {
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "prices must be non-negative",
		})
		return
	}
	if err := h.social.SetExpertPricing(
		expertID, body.MonthlyCents, body.YearlyCents, "usd",
	); err != nil {
		log.Printf("[studio] SetExpertPricing(%s): %v", expertID, err)
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	updated, _ := h.social.GetExpert(expertID)
	c.JSON(http.StatusOK, gin.H{
		"ok":     true,
		"expert": updated,
	})
}

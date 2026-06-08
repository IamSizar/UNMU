package handlers

import (
	"database/sql"
	"errors"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

type PromoHandler struct {
	promoRepo *repositories.PromoCodeRepository
	// audits is optional — when wired, RedeemPromo writes a PROMO_REDEEMED
	// audit-log row so admins are alerted that a code was used.
	audits *repositories.AuditRepository
}

func NewPromoHandler(promoRepo *repositories.PromoCodeRepository) *PromoHandler {
	return &PromoHandler{promoRepo: promoRepo}
}

// SetAudits wires the audit repo used for the admin "promo redeemed" alert.
// Safe to leave nil (then redemption just skips the audit write).
func (h *PromoHandler) SetAudits(a *repositories.AuditRepository) { h.audits = a }

type ValidatePromoRequest struct {
	Code string `json:"code" binding:"required"`
	// Context — the kind of purchase the code is being applied to:
	// "expert" or "community". Used to enforce a code's scope. Empty means
	// "no context" → only scope='all' codes will validate.
	Context string `json:"context,omitempty"`
}

type ValidatePromoResponse struct {
	Valid         bool    `json:"valid"`
	DiscountType  string  `json:"discount_type,omitempty"`
	DiscountValue float64 `json:"discount_value,omitempty"`
	Scope         string  `json:"scope,omitempty"`
	Message       string  `json:"message,omitempty"`
}

// evaluatePromoCode runs every eligibility rule for (code, user, context) and
// returns the promo plus a human message. ok=true means the code may be
// applied/redeemed. Shared by ValidatePromo (preview), RedeemPromo (commit),
// AND the subscribe handlers (server-authoritative discount), so every path
// enforces exactly the same rules. err is non-nil only for real DB failures.
func evaluatePromoCode(repo *repositories.PromoCodeRepository, code, context string, userID int64) (promo *models.PromoCode, ok bool, message string, err error) {
	promo, err = repo.GetByCode(code)
	if err != nil {
		return nil, false, "", err
	}
	if promo == nil || !promo.IsActive {
		return promo, false, "Invalid or inactive promo code", nil
	}
	now := time.Now()
	if promo.ValidFrom.Valid && promo.ValidFrom.Time.After(now) {
		return promo, false, "Promo code is not active yet", nil
	}
	if promo.ValidUntil.Valid && promo.ValidUntil.Time.Before(now) {
		return promo, false, "Promo code has expired", nil
	}
	// Scope gate: a non-"all" code only applies to its kind of purchase.
	scope := strings.ToLower(strings.TrimSpace(promo.Scope))
	ctx := strings.ToLower(strings.TrimSpace(context))
	if scope != "" && scope != "all" && scope != ctx {
		if scope == "expert" {
			return promo, false, "This code is only valid for expert subscriptions", nil
		}
		return promo, false, "This code is only valid for community subscriptions", nil
	}
	used, err := repo.HasUserUsedCode(userID, promo.ID)
	if err != nil {
		return nil, false, "", err
	}
	if used {
		return promo, false, "You have already used this promo code", nil
	}
	if promo.MaxUses.Valid && promo.UsedCount >= promo.MaxUses.Int64 {
		return promo, false, "Promo code has reached maximum uses", nil
	}
	return promo, true, "Promo code is valid", nil
}

// discountedCents applies a validated promo to a price (in cents) and returns
// the new price, clamped at 0. PERCENTAGE = % off; FIXED = a whole-currency
// amount off (DiscountValue is in dollars/dinars, converted to cents).
func discountedCents(priceCents int, p *models.PromoCode) int {
	if p == nil || priceCents <= 0 {
		return priceCents
	}
	switch strings.ToUpper(p.DiscountType) {
	case "PERCENTAGE":
		off := int(float64(priceCents) * p.DiscountValue / 100.0)
		priceCents -= off
	case "FIXED":
		priceCents -= int(p.DiscountValue * 100)
	}
	if priceCents < 0 {
		priceCents = 0
	}
	return priceCents
}

// applyPromoAtCheckout applies an optional promo code during a subscription
// purchase. Shared by the expert + community Subscribe handlers so the
// discount is computed server-side (never trusting a client-sent price).
//
// Returns: the possibly-discounted price; the note augmented with the promo
// summary (so an operator verifying a cash payment sees what was applied); a
// user-facing errMsg (caller → 400) when the code is invalid; or dbErr
// (caller → 500). A blank code, no promo repo, or an IAP method is a no-op
// returning the inputs unchanged. On a valid code it records the redemption
// (used_count++ + user_promo_usage) and writes the admin audit alert.
func applyPromoAtCheckout(
	promos *repositories.PromoCodeRepository,
	audits *repositories.AuditRepository,
	code, context string,
	userID int64,
	method string,
	priceCents int,
	note string,
) (newPrice int, newNote, errMsg string, dbErr error) {
	code = strings.TrimSpace(code)
	if code == "" || promos == nil {
		return priceCents, note, "", nil
	}
	// Promo discounts only apply to operator-verified cash/FIB payments;
	// App Store / Play pricing is fixed and can't be discounted here.
	m := strings.ToLower(strings.TrimSpace(method))
	if m != models.PaymentMethodCash && m != models.PaymentMethodFIB {
		return priceCents, note, "", nil
	}
	promo, ok, msg, err := evaluatePromoCode(promos, code, context, userID)
	if err != nil {
		return priceCents, note, "", err
	}
	if !ok {
		return priceCents, note, msg, nil
	}
	after := discountedCents(priceCents, promo)
	if err := promos.RecordUsage(userID, promo.ID); err != nil {
		return priceCents, note, "", err
	}
	if audits != nil {
		uid := userID
		codeRef := promo.Code
		kind := "promo"
		_, _ = audits.Write(
			models.AuditPromoRedeemed, models.SeveritySuccess,
			&uid, &codeRef, &kind,
			"Promo code "+promo.Code+" redeemed ("+context+" subscription)",
			map[string]any{
				"code": promo.Code, "discountType": promo.DiscountType,
				"discountValue": promo.DiscountValue, "scope": promo.Scope,
				"context": context, "priceBeforeCents": priceCents, "priceAfterCents": after,
			},
		)
	}
	summary := "Promo " + promo.Code + " applied"
	if note == "" {
		note = summary
	} else {
		note = note + " | " + summary
	}
	return after, note, "", nil
}

// ValidatePromo — POST /api/promo/validate (auth required).
//
// Returns valid=true only if the code exists, is active, hasn't been
// used by this user, and hasn't hit its max_uses cap. Date validity
// (valid_from / valid_until) is also enforced.
func (h *PromoHandler) ValidatePromo(c *gin.Context) {
	var req ValidatePromoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	userID := c.GetInt64("user_id")

	promo, ok, msg, err := evaluatePromoCode(h.promoRepo, req.Code, req.Context, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate promo code"})
		return
	}
	if !ok {
		c.JSON(http.StatusOK, ValidatePromoResponse{Valid: false, Message: msg})
		return
	}
	c.JSON(http.StatusOK, ValidatePromoResponse{
		Valid:         true,
		DiscountType:  promo.DiscountType,
		DiscountValue: promo.DiscountValue,
		Scope:         promo.Scope,
		Message:       "Promo code is valid",
	})
}

// RedeemPromo — POST /api/promo/redeem (auth required).
//
// The commit step the app calls right AFTER a subscription succeeds: it
// re-validates the code (same rules as ValidatePromo, including scope),
// records the redemption (one row in user_promo_usage + used_count++), and
// writes an admin audit alert. Idempotent per user: a second redeem of the
// same code returns valid=false ("already used"), so a retry can't
// double-count.
func (h *PromoHandler) RedeemPromo(c *gin.Context) {
	var req ValidatePromoRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	userID := c.GetInt64("user_id")

	promo, ok, msg, err := evaluatePromoCode(h.promoRepo, req.Code, req.Context, userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to redeem promo code"})
		return
	}
	if !ok {
		c.JSON(http.StatusOK, ValidatePromoResponse{Valid: false, Message: msg})
		return
	}

	if err := h.promoRepo.RecordUsage(userID, promo.ID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to record promo redemption"})
		return
	}

	// Admin alert: a redeemed code is a meaningful event (it's money off), so
	// log it for the dashboard's activity/audit view. Best-effort.
	if h.audits != nil {
		uid := userID
		codeRef := promo.Code
		kind := "promo"
		_, _ = h.audits.Write(
			models.AuditPromoRedeemed, models.SeveritySuccess,
			&uid, &codeRef, &kind,
			"Promo code "+promo.Code+" redeemed",
			map[string]any{
				"code":          promo.Code,
				"discountType":  promo.DiscountType,
				"discountValue": promo.DiscountValue,
				"scope":         promo.Scope,
				"context":       strings.ToLower(strings.TrimSpace(req.Context)),
			},
		)
	}

	c.JSON(http.StatusOK, ValidatePromoResponse{
		Valid:         true,
		DiscountType:  promo.DiscountType,
		DiscountValue: promo.DiscountValue,
		Scope:         promo.Scope,
		Message:       "Promo code redeemed",
	})
}

// ─── Admin CRUD ─────────────────────────────────────────────────────────

// promoBody — shared shape for create + update.
//
// All fields are pointers so we can distinguish "not in body" from
// "explicitly null/zero". The handler's toMutation() reads the pointers
// and decides which TouchXxx flags to set on the repo-side mutation.
type promoBody struct {
	Code          *string  `json:"code"`
	DiscountType  *string  `json:"discountType"`
	DiscountValue *float64 `json:"discountValue"`
	Scope         *string  `json:"scope"` // "all" | "expert" | "community"
	MaxUses       *int64   `json:"maxUses"`
	IsActive      *bool    `json:"isActive"`
	ValidFrom     *string  `json:"validFrom"`
	ValidUntil    *string  `json:"validUntil"`
}

// parseOptionalDate accepts "" / "YYYY-MM-DD" / RFC3339 and returns a
// *time.Time. "" returns (nil, nil) for the "clear" semantic.
func parseOptionalDate(s string) (*time.Time, error) {
	s = strings.TrimSpace(s)
	if s == "" {
		return nil, nil
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {
		return &t, nil
	}
	if t, err := time.Parse("2006-01-02", s); err == nil {
		return &t, nil
	}
	return nil, errors.New("date must be ISO-8601 or YYYY-MM-DD")
}

func (b promoBody) toMutation() (repositories.PromoMutation, error) {
	m := repositories.PromoMutation{}
	if b.Code != nil {
		m.Code = strings.ToUpper(strings.TrimSpace(*b.Code))
	}
	if b.Scope != nil {
		sc := strings.ToLower(strings.TrimSpace(*b.Scope))
		if sc == "" {
			sc = "all"
		}
		if sc != "all" && sc != "expert" && sc != "community" {
			return m, errors.New("scope must be all, expert, or community")
		}
		m.Scope = sc
	}
	if b.DiscountType != nil {
		dt := strings.ToUpper(strings.TrimSpace(*b.DiscountType))
		if dt != "PERCENTAGE" && dt != "FIXED" {
			return m, errors.New("discountType must be PERCENTAGE or FIXED")
		}
		m.DiscountType = dt
	}
	if b.DiscountValue != nil {
		m.DiscountValue = *b.DiscountValue
	}
	if b.MaxUses != nil {
		// Caller wrote the field — even a zero or negative value should
		// be treated as "touched". For MaxUses we treat 0 / negative as
		// "clear to NULL" (no cap).
		m.TouchMaxUses = true
		if *b.MaxUses > 0 {
			v := *b.MaxUses
			m.MaxUses = &v
		}
	}
	if b.IsActive != nil {
		m.IsActive = b.IsActive
	}
	if b.ValidFrom != nil {
		t, err := parseOptionalDate(*b.ValidFrom)
		if err != nil {
			return m, errors.New("validFrom: " + err.Error())
		}
		m.TouchValidFrom = true
		m.ValidFrom = t
	}
	if b.ValidUntil != nil {
		t, err := parseOptionalDate(*b.ValidUntil)
		if err != nil {
			return m, errors.New("validUntil: " + err.Error())
		}
		m.TouchValidUntil = true
		m.ValidUntil = t
	}
	return m, nil
}

// AdminList — GET /api/admin/promos
func (h *PromoHandler) AdminList(c *gin.Context) {
	promos, err := h.promoRepo.AdminList()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	out := make([]models.PromoCodeJSON, 0, len(promos))
	for _, p := range promos {
		out = append(out, p.ToJSON())
	}
	c.JSON(http.StatusOK, gin.H{"promos": out})
}

// AdminGet — GET /api/admin/promos/:id
func (h *PromoHandler) AdminGet(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	p, err := h.promoRepo.AdminGet(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if p == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "promo not found"})
		return
	}
	c.JSON(http.StatusOK, p.ToJSON())
}

// AdminCreate — POST /api/admin/promos
func (h *PromoHandler) AdminCreate(c *gin.Context) {
	var body promoBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.Code == nil || strings.TrimSpace(*body.Code) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "code is required"})
		return
	}
	if body.DiscountType == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "discountType is required"})
		return
	}
	if body.DiscountValue == nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "discountValue is required"})
		return
	}
	mut, err := body.toMutation()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	p, err := h.promoRepo.Create(mut)
	if err != nil {
		if errors.Is(err, repositories.ErrPromoCodeExists) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "A promo code with that value already exists.",
				"code":  "DUPLICATE_CODE",
			})
			return
		}
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, p.ToJSON())
}

// AdminUpdate — PATCH /api/admin/promos/:id
func (h *PromoHandler) AdminUpdate(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body promoBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	mut, err := body.toMutation()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	p, err := h.promoRepo.Update(id, mut)
	if err != nil {
		if errors.Is(err, repositories.ErrPromoCodeExists) {
			c.JSON(http.StatusConflict, gin.H{
				"error": "Another promo code with that value already exists.",
				"code":  "DUPLICATE_CODE",
			})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if p == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "promo not found"})
		return
	}
	c.JSON(http.StatusOK, p.ToJSON())
}

// AdminDelete — DELETE /api/admin/promos/:id
func (h *PromoHandler) AdminDelete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.promoRepo.Delete(id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "promo not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

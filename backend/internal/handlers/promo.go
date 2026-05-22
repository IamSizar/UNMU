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
}

func NewPromoHandler(promoRepo *repositories.PromoCodeRepository) *PromoHandler {
	return &PromoHandler{promoRepo: promoRepo}
}

type ValidatePromoRequest struct {
	Code string `json:"code" binding:"required"`
}

type ValidatePromoResponse struct {
	Valid         bool    `json:"valid"`
	DiscountType  string  `json:"discount_type,omitempty"`
	DiscountValue float64 `json:"discount_value,omitempty"`
	Message       string  `json:"message,omitempty"`
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

	promo, err := h.promoRepo.GetByCode(req.Code)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to validate promo code"})
		return
	}
	if promo == nil || !promo.IsActive {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "Invalid or inactive promo code",
		})
		return
	}

	// Date window: valid_from <= today <= valid_until (when set).
	now := time.Now()
	if promo.ValidFrom.Valid && promo.ValidFrom.Time.After(now) {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "Promo code is not active yet",
		})
		return
	}
	if promo.ValidUntil.Valid && promo.ValidUntil.Time.Before(now) {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "Promo code has expired",
		})
		return
	}

	used, err := h.promoRepo.HasUserUsedCode(userID, promo.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to check promo usage"})
		return
	}
	if used {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "You have already used this promo code",
		})
		return
	}

	if promo.MaxUses.Valid && promo.UsedCount >= promo.MaxUses.Int64 {
		c.JSON(http.StatusOK, ValidatePromoResponse{
			Valid:   false,
			Message: "Promo code has reached maximum uses",
		})
		return
	}

	c.JSON(http.StatusOK, ValidatePromoResponse{
		Valid:         true,
		DiscountType:  promo.DiscountType,
		DiscountValue: promo.DiscountValue,
		Message:       "Promo code is valid",
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

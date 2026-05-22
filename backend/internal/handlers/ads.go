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

type AdsHandler struct {
	adRepo *repositories.AdRepository
}

func NewAdsHandler(adRepo *repositories.AdRepository) *AdsHandler {
	return &AdsHandler{adRepo: adRepo}
}

// GetAds — GET /api/ads?region_code={code}  (public, unauthenticated)
func (h *AdsHandler) GetAds(c *gin.Context) {
	regionCode := c.DefaultQuery("region_code", "GLOBAL")
	ads, err := h.adRepo.GetActiveAdsByRegion(regionCode)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to fetch ads"})
		return
	}
	out := make([]models.AdJSON, 0, len(ads))
	for _, a := range ads {
		out = append(out, a.ToJSON())
	}
	c.JSON(http.StatusOK, gin.H{"ads": out})
}

// ─── Admin CRUD ─────────────────────────────────────────────────────────

// adMutationBody — request body for create + update. All fields optional
// at the JSON layer; the handler enforces "required on create" (company
// name + title) in the create path.
type adMutationBody struct {
	CompanyName *string `json:"companyName"`
	Title       *string `json:"title"`
	Description *string `json:"description"`
	ImageURL    *string `json:"imageUrl"`
	TargetURL   *string `json:"targetUrl"`
	RegionCode  *string `json:"regionCode"`
	IsActive    *bool   `json:"isActive"`
	StartDate   *string `json:"startDate"` // RFC3339 (or YYYY-MM-DD)
	EndDate     *string `json:"endDate"`
}

func parseDateOrTime(s string) (*time.Time, error) {
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

// toMutation converts the JSON body into a repository AdMutation. Empty
// strings collapse to NULL, which lets the admin clear a column via
// `"description": ""` rather than having to learn the JSON-null trick.
func (b adMutationBody) toMutation() (repositories.AdMutation, error) {
	m := repositories.AdMutation{}
	if b.CompanyName != nil {
		m.CompanyName = strings.TrimSpace(*b.CompanyName)
	}
	if b.Title != nil {
		m.Title = strings.TrimSpace(*b.Title)
	}
	// For nullable text columns we preserve the "field was present" signal
	// by keeping the pointer non-nil even when the value is empty. The
	// repo translates empty strings to SQL NULL via NULLIF($N, '').
	if b.Description != nil {
		v := strings.TrimSpace(*b.Description)
		m.Description = &v
	}
	if b.ImageURL != nil {
		v := strings.TrimSpace(*b.ImageURL)
		m.ImageURL = &v
	}
	if b.TargetURL != nil {
		v := strings.TrimSpace(*b.TargetURL)
		m.TargetURL = &v
	}
	if b.RegionCode != nil {
		v := strings.ToUpper(strings.TrimSpace(*b.RegionCode))
		m.RegionCode = &v
	}
	if b.IsActive != nil {
		m.IsActive = b.IsActive
	}
	if b.StartDate != nil {
		t, err := parseDateOrTime(*b.StartDate)
		if err != nil {
			return m, errors.New("startDate: " + err.Error())
		}
		m.StartDate = t
	}
	if b.EndDate != nil {
		t, err := parseDateOrTime(*b.EndDate)
		if err != nil {
			return m, errors.New("endDate: " + err.Error())
		}
		m.EndDate = t
	}
	return m, nil
}

func strPtrOrNil(s string) *string {
	if s == "" {
		return nil
	}
	return &s
}

// AdminList — GET /api/admin/ads
func (h *AdsHandler) AdminList(c *gin.Context) {
	ads, err := h.adRepo.AdminList()
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	out := make([]models.AdJSON, 0, len(ads))
	for _, a := range ads {
		out = append(out, a.ToJSON())
	}
	c.JSON(http.StatusOK, gin.H{"ads": out})
}

// AdminGet — GET /api/admin/ads/:id
func (h *AdsHandler) AdminGet(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	ad, err := h.adRepo.AdminGet(id)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if ad == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ad not found"})
		return
	}
	c.JSON(http.StatusOK, ad.ToJSON())
}

// AdminCreate — POST /api/admin/ads
func (h *AdsHandler) AdminCreate(c *gin.Context) {
	var body adMutationBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	if body.CompanyName == nil || strings.TrimSpace(*body.CompanyName) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "companyName is required"})
		return
	}
	if body.Title == nil || strings.TrimSpace(*body.Title) == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "title is required"})
		return
	}
	mut, err := body.toMutation()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ad, err := h.adRepo.Create(mut)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusCreated, ad.ToJSON())
}

// AdminUpdate — PATCH /api/admin/ads/:id
func (h *AdsHandler) AdminUpdate(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	var body adMutationBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	mut, err := body.toMutation()
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	ad, err := h.adRepo.Update(id, mut)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	if ad == nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "ad not found"})
		return
	}
	c.JSON(http.StatusOK, ad.ToJSON())
}

// AdminDelete — DELETE /api/admin/ads/:id
func (h *AdsHandler) AdminDelete(c *gin.Context) {
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}
	if err := h.adRepo.Delete(id); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			c.JSON(http.StatusNotFound, gin.H{"error": "ad not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"status": "deleted"})
}

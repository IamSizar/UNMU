package handlers

import (
	"database/sql"
	"fmt"
	"halalstocks/internal/models"
	"halalstocks/internal/repositories"
	"net/http"
	"strconv"
	"strings"

	"github.com/gin-gonic/gin"
)

// AdminStocksHandler — Phase 4.4.
//
// Drives the Stocks page on the admin dashboard:
//   * GET  /admin/stocks            — paginated list joined with latest
//                                     shariah status
//   * GET  /admin/stocks/totals     — counts by grade for the header
//   * POST /admin/stocks/:id/shariah-override — manual grade override
//
// The override path inserts a new shariah_status row with as_of_date =
// CURRENT_DATE. Because every existing read path uses DISTINCT ON
// (stock_id) ORDER BY as_of_date DESC, the override becomes the
// "latest" automatically without needing a separate `is_override`
// column. The audit log captures who flipped it + why.
type AdminStocksHandler struct {
	db     *sql.DB
	audits *repositories.AuditRepository
}

func NewAdminStocksHandler(
	db *sql.DB,
	audits *repositories.AuditRepository,
) *AdminStocksHandler {
	return &AdminStocksHandler{db: db, audits: audits}
}

// adminStockRow — wire shape sent to the React table.
type adminStockRow struct {
	ID          int64   `json:"id"`
	Ticker      string  `json:"ticker"`
	Exchange    string  `json:"exchange"`
	Name        string  `json:"name"`
	Region      string  `json:"region"`
	Sector      string  `json:"sector"`
	Status      string  `json:"status"`
	Grade       string  `json:"grade"`
	DebtRatio   float64 `json:"debtRatio"`
	HaramIncome float64 `json:"haramIncome"`
	IsActive    bool    `json:"isActive"`
}

// List — GET /admin/stocks?region=GCC&grade=A&q=apple&limit=50&offset=0
//
// Returns the latest shariah_status per stock (DISTINCT ON keyed on
// stock_id). Filters are AND-combined and all optional.
func (h *AdminStocksHandler) List(c *gin.Context) {
	limit, _ := strconv.Atoi(c.Query("limit"))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	offset, _ := strconv.Atoi(c.Query("offset"))
	if offset < 0 {
		offset = 0
	}

	region := strings.ToUpper(strings.TrimSpace(c.Query("region")))
	grade := strings.ToUpper(strings.TrimSpace(c.Query("grade")))
	status := strings.ToUpper(strings.TrimSpace(c.Query("status")))
	query := strings.TrimSpace(c.Query("q"))

	// Build WHERE incrementally. The latest_status subquery returns the
	// freshest row per stock so all filter predicates can apply to
	// either stocks or shariah cleanly.
	args := []any{}
	conds := []string{"COALESCE(s.is_active, TRUE)"}

	if region != "" && region != "ALL" {
		args = append(args, region)
		conds = append(conds, fmt.Sprintf("s.region_code = $%d", len(args)))
	}
	if grade != "" && grade != "ALL" {
		args = append(args, grade)
		conds = append(conds, fmt.Sprintf("ls.grade = $%d", len(args)))
	}
	if status != "" && status != "ALL" {
		args = append(args, status)
		conds = append(conds, fmt.Sprintf("ls.status = $%d", len(args)))
	}
	if query != "" {
		args = append(args, "%"+query+"%")
		conds = append(conds, fmt.Sprintf(
			"(s.ticker ILIKE $%d OR s.name ILIKE $%d)",
			len(args), len(args)),
		)
	}

	where := "WHERE " + strings.Join(conds, " AND ")

	// Total count (same WHERE).
	var total int
	totalSQL := `
		WITH latest_status AS (
		  SELECT DISTINCT ON (stock_id) stock_id, status, grade, debt_ratio, haram_income_ratio
		  FROM shariah_status
		  ORDER BY stock_id, as_of_date DESC
		)
		SELECT COUNT(*)
		FROM stocks s
		LEFT JOIN latest_status ls ON ls.stock_id = s.id
		` + where
	if err := h.db.QueryRow(totalSQL, args...).Scan(&total); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	args = append(args, limit, offset)
	rows, err := h.db.Query(`
		WITH latest_status AS (
		  SELECT DISTINCT ON (stock_id)
		    stock_id, status, grade, debt_ratio, haram_income_ratio
		  FROM shariah_status
		  ORDER BY stock_id, as_of_date DESC
		)
		SELECT
		  s.id,
		  s.ticker,
		  COALESCE(s.exchange, ''),
		  s.name,
		  COALESCE(s.region_code, ''),
		  COALESCE(s.sector, ''),
		  COALESCE(ls.status, 'UNKNOWN'),
		  COALESCE(ls.grade, ''),
		  COALESCE(ls.debt_ratio, 0),
		  COALESCE(ls.haram_income_ratio, 0),
		  COALESCE(s.is_active, TRUE)
		FROM stocks s
		LEFT JOIN latest_status ls ON ls.stock_id = s.id
		`+where+`
		ORDER BY s.ticker ASC
		LIMIT $`+strconv.Itoa(len(args)-1)+` OFFSET $`+strconv.Itoa(len(args)),
		args...,
	)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	out := make([]adminStockRow, 0, limit)
	for rows.Next() {
		var r adminStockRow
		if err := rows.Scan(
			&r.ID, &r.Ticker, &r.Exchange, &r.Name, &r.Region, &r.Sector,
			&r.Status, &r.Grade, &r.DebtRatio, &r.HaramIncome, &r.IsActive,
		); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		out = append(out, r)
	}
	c.JSON(http.StatusOK, gin.H{
		"stocks": out,
		"total":  total,
		"limit":  limit,
		"offset": offset,
	})
}

// Totals — GET /admin/stocks/totals
//
// Aggregate counts for the Stocks page's header cards: total / by-status
// / by-grade. Same DISTINCT ON pattern as List so admin overrides
// dominate the pipeline-generated rows.
func (h *AdminStocksHandler) Totals(c *gin.Context) {
	var resp struct {
		Total     int `json:"total"`
		Compliant int `json:"compliant"`
		Mixed     int `json:"mixed"`
		NonCompliant int `json:"nonCompliant"`
		Unknown   int `json:"unknown"`
		ByGrade   map[string]int `json:"byGrade"`
	}
	resp.ByGrade = map[string]int{}

	if err := h.db.QueryRow(`
		WITH latest AS (
		  SELECT DISTINCT ON (stock_id) status, grade
		  FROM shariah_status
		  ORDER BY stock_id, as_of_date DESC
		)
		SELECT
		  (SELECT COUNT(*) FROM stocks WHERE COALESCE(is_active, TRUE)),
		  COUNT(*) FILTER (WHERE status = 'HALAL'),
		  COUNT(*) FILTER (WHERE status = 'MIXED'),
		  COUNT(*) FILTER (WHERE status = 'HARAM'),
		  COUNT(*) FILTER (WHERE status NOT IN ('HALAL','MIXED','HARAM') OR status IS NULL)
		FROM latest
	`).Scan(&resp.Total, &resp.Compliant, &resp.Mixed, &resp.NonCompliant, &resp.Unknown); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	rows, err := h.db.Query(`
		WITH latest AS (
		  SELECT DISTINCT ON (stock_id) grade
		  FROM shariah_status
		  WHERE grade IS NOT NULL AND grade <> ''
		  ORDER BY stock_id, as_of_date DESC
		)
		SELECT grade, COUNT(*) FROM latest GROUP BY grade ORDER BY grade
	`)
	if err == nil {
		defer rows.Close()
		for rows.Next() {
			var g string
			var n int
			if err := rows.Scan(&g, &n); err == nil {
				resp.ByGrade[g] = n
			}
		}
	}

	c.JSON(http.StatusOK, resp)
}

// shariahOverrideBody — request shape for the manual override endpoint.
type shariahOverrideBody struct {
	Status string `json:"status"` // HALAL | MIXED | HARAM | UNKNOWN
	Grade  string `json:"grade"`  // A | B | C | F | ""
	Reason string `json:"reason"`
}

// ShariahOverride — POST /admin/stocks/:id/shariah-override
//
// Inserts a fresh shariah_status row dated today so every read path
// (DISTINCT ON / latest-by-date) returns the override. Reason is
// stored on the row itself AND in the audit log so the override is
// traceable from either side.
func (h *AdminStocksHandler) ShariahOverride(c *gin.Context) {
	uid, _ := c.Get("user_id")
	adminID, _ := uid.(int64)
	if adminID == 0 {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "auth required"})
		return
	}
	id, err := strconv.ParseInt(c.Param("id"), 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid id"})
		return
	}

	var body shariahOverrideBody
	if err := c.ShouldBindJSON(&body); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid body"})
		return
	}
	body.Status = strings.ToUpper(strings.TrimSpace(body.Status))
	body.Grade = strings.ToUpper(strings.TrimSpace(body.Grade))
	body.Reason = strings.TrimSpace(body.Reason)

	switch body.Status {
	case "HALAL", "MIXED", "HARAM", "DOUBTFUL", "UNKNOWN":
	default:
		c.JSON(http.StatusBadRequest, gin.H{
			"error": "status must be HALAL|MIXED|HARAM|DOUBTFUL|UNKNOWN",
		})
		return
	}
	if body.Grade != "" {
		switch body.Grade {
		case "A", "B", "C", "F":
		default:
			c.JSON(http.StatusBadRequest, gin.H{
				"error": "grade must be A|B|C|F (or empty)",
			})
			return
		}
	}

	// Confirm the stock exists + capture before-state for the audit diff.
	var before struct {
		Ticker string
		Status string
		Grade  string
	}
	if err := h.db.QueryRow(`
		SELECT s.ticker,
		       COALESCE(ls.status, 'UNKNOWN'),
		       COALESCE(ls.grade, '')
		FROM stocks s
		LEFT JOIN LATERAL (
		  SELECT status, grade FROM shariah_status
		  WHERE stock_id = s.id
		  ORDER BY as_of_date DESC LIMIT 1
		) ls ON true
		WHERE s.id = $1
	`, id).Scan(&before.Ticker, &before.Status, &before.Grade); err != nil {
		if err == sql.ErrNoRows {
			c.JSON(http.StatusNotFound, gin.H{"error": "stock not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// We prepend an ADMIN-OVERRIDE marker into `reason` so old pipeline
	// rows can be visually distinguished in the audit log + drill-in.
	reasonText := "ADMIN OVERRIDE: " + body.Reason
	if body.Reason == "" {
		reasonText = "ADMIN OVERRIDE (no reason given)"
	}

	if _, err := h.db.Exec(`
		INSERT INTO shariah_status
		    (stock_id, status, grade, reason, as_of_date)
		VALUES ($1, $2, NULLIF($3, ''), $4, CURRENT_DATE)
		ON CONFLICT (stock_id, as_of_date) DO UPDATE
		  SET status = EXCLUDED.status,
		      grade  = EXCLUDED.grade,
		      reason = EXCLUDED.reason,
		      updated_at = NOW()
	`, id, body.Status, body.Grade, reasonText); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	auditTarget := strconv.FormatInt(id, 10)
	auditKind := "stock"
	_, _ = h.audits.Write(
		"STOCK_SHARIAH_OVERRIDE", models.SeverityWarning,
		&adminID, &auditTarget, &auditKind,
		fmt.Sprintf("Admin overrode shariah grade for %s: %s/%s → %s/%s",
			before.Ticker, before.Status, before.Grade, body.Status, body.Grade),
		map[string]any{
			"stockId":   id,
			"ticker":    before.Ticker,
			"oldStatus": before.Status,
			"oldGrade":  before.Grade,
			"newStatus": body.Status,
			"newGrade":  body.Grade,
			"reason":    body.Reason,
		},
	)

	c.JSON(http.StatusOK, gin.H{
		"ok":     true,
		"id":     id,
		"ticker": before.Ticker,
		"status": body.Status,
		"grade":  body.Grade,
	})
}

package handlers

import (
	"database/sql"
	"log"
	"net/http"

	"github.com/gin-gonic/gin"
)

// AdminMetricsHandler — Phase 4.1.
//
// One-shot rollup of every aggregate the admin dashboard cards + charts
// need. We run ~7 SELECT queries against the live DB on each request.
// Heavy reads happen rarely (one admin opening the home page) and most
// queries scan small / well-indexed tables, so we accept the cost
// rather than maintain a denormalised summary table.
//
// Each section degrades independently: if one query fails we log it
// and return zeros for that bucket so the dashboard still renders
// something useful.
type AdminMetricsHandler struct {
	db *sql.DB
}

func NewAdminMetricsHandler(db *sql.DB) *AdminMetricsHandler {
	return &AdminMetricsHandler{db: db}
}

// metricsResponse — wire shape the React Dashboard consumes.
type metricsResponse struct {
	Users         metricsUsers         `json:"users"`
	Subscriptions metricsSubscriptions `json:"subscriptions"`
	Content       metricsContent       `json:"content"`
	Stocks        metricsStocks        `json:"stocks"`
	Trends        metricsTrends        `json:"trends"`
	TopExperts    []metricsTopExpert   `json:"topExperts"`
}

type metricsUsers struct {
	Total    int `json:"total"`
	ThisWeek int `json:"thisWeek"`
	Premium  int `json:"premium"`
	Experts  int `json:"experts"`
}

type metricsSubscriptions struct {
	MonthlyActive       int `json:"monthlyActive"`
	YearlyActive        int `json:"yearlyActive"`
	MRRCents            int `json:"mrrCents"`
	ARRCents            int `json:"arrCents"`
	PendingApplications int `json:"pendingApplications"`
}

type metricsContent struct {
	Articles         int `json:"articles"`
	ArticlesThisWeek int `json:"articlesThisWeek"`
	Videos           int `json:"videos"` // video + reel
	VideosThisWeek   int `json:"videosThisWeek"`
}

type metricsStocks struct {
	Total     int                  `json:"total"`
	Compliant int                  `json:"compliant"` // status = HALAL
	ByGrade   []metricsGradeBucket `json:"byGrade"`
}

type metricsGradeBucket struct {
	Grade string `json:"grade"`
	Count int    `json:"count"`
}

type metricsTrends struct {
	// SubsByMonth — last 8 months of new subscription rows by plan.
	// Keys: month (Sep/Oct/...), monthly, yearly.
	SubsByMonth []metricsSubsMonth `json:"subsByMonth"`
	// ContentByDay — last 7 days of newly-published posts.
	ContentByDay []metricsContentDay `json:"contentByDay"`
}

type metricsSubsMonth struct {
	Month   string `json:"month"`   // 3-letter abbreviation (Sep, Oct, …)
	Monthly int    `json:"monthly"` // new monthly plans started this month
	Yearly  int    `json:"yearly"`
}

type metricsContentDay struct {
	Day      string `json:"day"` // YYYY-MM-DD
	Articles int    `json:"articles"`
	Videos   int    `json:"videos"`
}

type metricsTopExpert struct {
	ExpertID    string `json:"expertId"`
	Name        string `json:"name"`
	Specialty   string `json:"specialty"`
	Followers   int    `json:"followers"`
	Articles    int    `json:"articles"`
	Videos      int    `json:"videos"`
	AvatarURL   string `json:"avatarUrl"`
}

// Metrics — GET /api/admin/metrics
//
// Returns every aggregate the home dashboard needs in one round-trip.
// Failed sub-queries are logged + zeroed out so a single broken count
// doesn't take down the whole screen.
func (h *AdminMetricsHandler) Metrics(c *gin.Context) {
	resp := metricsResponse{
		TopExperts: []metricsTopExpert{},
	}

	// ── users + experts ────────────────────────────────────────────
	if err := h.db.QueryRow(`
		SELECT
		  COUNT(*),
		  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days'),
		  COUNT(*) FILTER (WHERE COALESCE(subscription_tier, 'FREE') = 'PREMIUM'),
		  COUNT(*) FILTER (WHERE COALESCE(role, 'USER') = 'EXPERT')
		FROM users
		WHERE deleted_at IS NULL
	`).Scan(
		&resp.Users.Total, &resp.Users.ThisWeek,
		&resp.Users.Premium, &resp.Users.Experts,
	); err != nil {
		log.Printf("[admin metrics] users: %v", err)
	}

	// ── subscriptions ──────────────────────────────────────────────
	// Counts active rows by plan + sums MRR. Yearly plans are
	// amortised into the MRR by dividing their price by 12.
	var monthlyRevenue, yearlyRevenue sql.NullInt64
	if err := h.db.QueryRow(`
		SELECT
		  COUNT(*) FILTER (WHERE status = 'active' AND plan = 'monthly') AS m_count,
		  COUNT(*) FILTER (WHERE status = 'active' AND plan = 'yearly')  AS y_count,
		  COALESCE(SUM(price_cents) FILTER (WHERE status = 'active' AND plan = 'monthly'), 0) AS m_rev,
		  COALESCE(SUM(price_cents) FILTER (WHERE status = 'active' AND plan = 'yearly'),  0) AS y_rev
		FROM expert_subscriptions
	`).Scan(
		&resp.Subscriptions.MonthlyActive,
		&resp.Subscriptions.YearlyActive,
		&monthlyRevenue,
		&yearlyRevenue,
	); err != nil {
		log.Printf("[admin metrics] subscriptions: %v", err)
	}
	// MRR = monthly active prices + (yearly active prices ÷ 12).
	// ARR = MRR × 12 for the "you're on track for X" framing.
	resp.Subscriptions.MRRCents = int(monthlyRevenue.Int64) + int(yearlyRevenue.Int64/12)
	resp.Subscriptions.ARRCents = resp.Subscriptions.MRRCents * 12

	if err := h.db.QueryRow(`
		SELECT COUNT(*) FROM expert_applications WHERE status = 'pending'
	`).Scan(&resp.Subscriptions.PendingApplications); err != nil {
		log.Printf("[admin metrics] pending apps: %v", err)
	}

	// ── content (posts) ────────────────────────────────────────────
	// "videos" lumps short-form reels in with long-form videos, which
	// matches the home Dashboard's "Short Videos" tile copy.
	if err := h.db.QueryRow(`
		SELECT
		  COUNT(*) FILTER (WHERE post_type = 'article'),
		  COUNT(*) FILTER (WHERE post_type = 'article' AND created_at > NOW() - INTERVAL '7 days'),
		  COUNT(*) FILTER (WHERE post_type IN ('video','reel')),
		  COUNT(*) FILTER (WHERE post_type IN ('video','reel') AND created_at > NOW() - INTERVAL '7 days')
		FROM posts
		WHERE COALESCE(is_hidden, FALSE) = FALSE
		  AND deleted_at IS NULL
	`).Scan(
		&resp.Content.Articles, &resp.Content.ArticlesThisWeek,
		&resp.Content.Videos, &resp.Content.VideosThisWeek,
	); err != nil {
		log.Printf("[admin metrics] content: %v", err)
	}

	// ── stocks ─────────────────────────────────────────────────────
	// Use the latest shariah_status row per stock — multiple rows can
	// exist over time (one per as_of_date), so DISTINCT ON returns the
	// freshest grade for each stock.
	if err := h.db.QueryRow(`
		WITH latest AS (
		  SELECT DISTINCT ON (stock_id) status, grade
		  FROM shariah_status
		  ORDER BY stock_id, as_of_date DESC
		)
		SELECT
		  (SELECT COUNT(*) FROM stocks WHERE COALESCE(is_active, TRUE)),
		  COUNT(*) FILTER (WHERE status = 'HALAL')
		FROM latest
	`).Scan(&resp.Stocks.Total, &resp.Stocks.Compliant); err != nil {
		log.Printf("[admin metrics] stocks counts: %v", err)
	}
	gradeBuckets, err := h.loadGradeBuckets()
	if err != nil {
		log.Printf("[admin metrics] grades: %v", err)
	}
	resp.Stocks.ByGrade = gradeBuckets

	// ── trends ─────────────────────────────────────────────────────
	resp.Trends.SubsByMonth, err = h.loadSubsByMonth()
	if err != nil {
		log.Printf("[admin metrics] subs trend: %v", err)
		resp.Trends.SubsByMonth = []metricsSubsMonth{}
	}
	resp.Trends.ContentByDay, err = h.loadContentByDay()
	if err != nil {
		log.Printf("[admin metrics] content trend: %v", err)
		resp.Trends.ContentByDay = []metricsContentDay{}
	}

	// ── top experts ────────────────────────────────────────────────
	resp.TopExperts, err = h.loadTopExperts()
	if err != nil {
		log.Printf("[admin metrics] top experts: %v", err)
		resp.TopExperts = []metricsTopExpert{}
	}

	c.JSON(http.StatusOK, resp)
}

func (h *AdminMetricsHandler) loadGradeBuckets() ([]metricsGradeBucket, error) {
	rows, err := h.db.Query(`
		WITH latest AS (
		  SELECT DISTINCT ON (stock_id) grade
		  FROM shariah_status
		  WHERE grade IS NOT NULL AND grade <> ''
		  ORDER BY stock_id, as_of_date DESC
		)
		SELECT grade, COUNT(*) FROM latest GROUP BY grade ORDER BY grade
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]metricsGradeBucket, 0)
	for rows.Next() {
		var b metricsGradeBucket
		if err := rows.Scan(&b.Grade, &b.Count); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (h *AdminMetricsHandler) loadSubsByMonth() ([]metricsSubsMonth, error) {
	rows, err := h.db.Query(`
		WITH months AS (
		  SELECT generate_series(
		    date_trunc('month', NOW()) - INTERVAL '7 months',
		    date_trunc('month', NOW()),
		    '1 month'::interval
		  ) AS month_start
		),
		buckets AS (
		  SELECT
		    date_trunc('month', created_at) AS month_start,
		    plan,
		    COUNT(*) AS n
		  FROM expert_subscriptions
		  WHERE created_at > NOW() - INTERVAL '8 months'
		  GROUP BY 1, 2
		)
		SELECT
		  to_char(m.month_start, 'Mon'),
		  COALESCE(SUM(CASE WHEN b.plan = 'monthly' THEN b.n END), 0) AS monthly,
		  COALESCE(SUM(CASE WHEN b.plan = 'yearly'  THEN b.n END), 0) AS yearly
		FROM months m
		LEFT JOIN buckets b ON b.month_start = m.month_start
		GROUP BY m.month_start
		ORDER BY m.month_start ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]metricsSubsMonth, 0, 8)
	for rows.Next() {
		var b metricsSubsMonth
		if err := rows.Scan(&b.Month, &b.Monthly, &b.Yearly); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (h *AdminMetricsHandler) loadContentByDay() ([]metricsContentDay, error) {
	rows, err := h.db.Query(`
		WITH days AS (
		  SELECT generate_series(
		    (CURRENT_DATE - 6)::date,
		    CURRENT_DATE,
		    '1 day'::interval
		  )::date AS day
		),
		buckets AS (
		  SELECT
		    date_trunc('day', created_at)::date AS day,
		    COUNT(*) FILTER (WHERE post_type = 'article')         AS articles,
		    COUNT(*) FILTER (WHERE post_type IN ('video','reel')) AS videos
		  FROM posts
		  WHERE created_at >= (CURRENT_DATE - 6)
		    AND COALESCE(is_hidden, FALSE) = FALSE
		    AND deleted_at IS NULL
		  GROUP BY 1
		)
		SELECT
		  to_char(d.day, 'YYYY-MM-DD'),
		  COALESCE(b.articles, 0),
		  COALESCE(b.videos, 0)
		FROM days d
		LEFT JOIN buckets b ON b.day = d.day
		ORDER BY d.day ASC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]metricsContentDay, 0, 7)
	for rows.Next() {
		var b metricsContentDay
		if err := rows.Scan(&b.Day, &b.Articles, &b.Videos); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (h *AdminMetricsHandler) loadTopExperts() ([]metricsTopExpert, error) {
	rows, err := h.db.Query(`
		SELECT
		  e.id,
		  e.name,
		  COALESCE(e.expertise, '')                                          AS specialty,
		  e.subscriber_count                                                 AS followers,
		  (SELECT COUNT(*) FROM posts p
		    WHERE p.expert_id = e.id AND p.target_type = 'expert'
		      AND p.post_type = 'article'
		      AND COALESCE(p.is_hidden, FALSE) = FALSE
		      AND p.deleted_at IS NULL)                                      AS articles,
		  (SELECT COUNT(*) FROM posts p
		    WHERE p.expert_id = e.id AND p.target_type = 'expert'
		      AND p.post_type IN ('video','reel')
		      AND COALESCE(p.is_hidden, FALSE) = FALSE
		      AND p.deleted_at IS NULL)                                      AS videos,
		  COALESCE(u.avatar_url, '')                                         AS avatar_url
		FROM experts e
		LEFT JOIN users u ON u.expert_id = e.id
		ORDER BY e.subscriber_count DESC NULLS LAST, e.id
		LIMIT 4
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]metricsTopExpert, 0, 4)
	for rows.Next() {
		var t metricsTopExpert
		var followers sql.NullInt64
		if err := rows.Scan(
			&t.ExpertID, &t.Name, &t.Specialty,
			&followers, &t.Articles, &t.Videos, &t.AvatarURL,
		); err != nil {
			return nil, err
		}
		t.Followers = int(followers.Int64)
		out = append(out, t)
	}
	return out, rows.Err()
}

package repositories

import (
	"database/sql"
	"encoding/json"
	"time"
)

// PostEventsRepository handles writes + reads on the `post_events`
// table (migration 0010). Tracks user-facing engagement / reliability
// signals that we shipped today: shares, deep-link opens, reel-load
// failures.
//
// Event types are documented in the migration; new ones can be added
// without a schema change since the column is plain TEXT + a JSONB
// `meta` blob for whatever the call site wants to attach.
type PostEventsRepository struct {
	db *sql.DB
}

func NewPostEventsRepository(db *sql.DB) *PostEventsRepository {
	return &PostEventsRepository{db: db}
}

// Known event types. Stringly-typed in SQL but call sites should use
// these constants so a typo is a compile-error.
const (
	EventShareTapped     = "share_tapped"
	EventDeepLinkOpened  = "deep_link_opened"
	EventReelLoadFailed  = "reel_load_failed"
)

// Write inserts a single event. `userID` may be nil for unauthed
// triggers (e.g. a deep-link tap before sign-in). `meta` is
// optional; pass nil for none.
//
// Errors are returned but never escalated by callers — failing to log
// an event must NEVER fail the underlying request.
func (r *PostEventsRepository) Write(
	postID int64,
	eventType string,
	userID *int64,
	meta map[string]any,
) error {
	metaJSON, err := json.Marshal(metaOrEmpty(meta))
	if err != nil {
		return err
	}
	_, err = r.db.Exec(
		`INSERT INTO post_events (post_id, event_type, user_id, meta) VALUES ($1, $2, $3, $4)`,
		postID, eventType, userID, metaJSON,
	)
	return err
}

// SummaryRow — one event-type bucket in the rolling-window aggregate
// returned to admin. Drives the Dashboard "today's activity" panel.
type SummaryRow struct {
	EventType string `json:"eventType"`
	Count     int64  `json:"count"`
}

// Summary returns counts per event_type in the rolling window ending
// at NOW(). Used by the admin dashboard to show "shares in the last
// 24h", "deep links opened in the last 7d", etc.
func (r *PostEventsRepository) Summary(window time.Duration) ([]SummaryRow, error) {
	rows, err := r.db.Query(
		`SELECT event_type, COUNT(*)::bigint
		   FROM post_events
		  WHERE occurred_at >= NOW() - $1::interval
		  GROUP BY event_type
		  ORDER BY event_type`,
		// pq stringifies the interval — '24 hours', '7 days', etc.
		intervalString(window),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]SummaryRow, 0, 4)
	for rows.Next() {
		var s SummaryRow
		if err := rows.Scan(&s.EventType, &s.Count); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// HourlyTimeseries returns event counts bucketed per-hour within the
// rolling window ending at NOW(). Drives the dashboard sparkline so we
// can see whether failures cluster (deploy regression?) or are evenly
// distributed (background noise).
type TimeseriesRow struct {
	HourBucket time.Time `json:"hourBucket"`
	EventType  string    `json:"eventType"`
	Count      int64     `json:"count"`
}

func (r *PostEventsRepository) HourlyTimeseries(window time.Duration) ([]TimeseriesRow, error) {
	rows, err := r.db.Query(
		`SELECT date_trunc('hour', occurred_at) AS bucket,
		        event_type,
		        COUNT(*)::bigint
		   FROM post_events
		  WHERE occurred_at >= NOW() - $1::interval
		  GROUP BY bucket, event_type
		  ORDER BY bucket ASC`,
		intervalString(window),
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]TimeseriesRow, 0, 64)
	for rows.Next() {
		var t TimeseriesRow
		if err := rows.Scan(&t.HourBucket, &t.EventType, &t.Count); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// metaOrEmpty makes Marshal happy on nil maps.
func metaOrEmpty(m map[string]any) map[string]any {
	if m == nil {
		return map[string]any{}
	}
	return m
}

// intervalString formats a time.Duration as a Postgres interval literal
// at hour resolution, e.g. "24 hours". Admin dashboards never need finer
// granularity than that, and hours keep the numbers readable in the
// generated SQL when a query is logged.
func intervalString(d time.Duration) string {
	hours := int(d.Hours())
	if hours < 1 {
		hours = 1
	}
	if hours == 1 {
		return "1 hour"
	}
	return itoa64(int64(hours)) + " hours"
}

// itoa64 — tiny stdlib-free int64 → decimal converter, mirrors the
// existing helper in social.go so the dependency surface stays the same.
func itoa64(n int64) string {
	if n == 0 {
		return "0"
	}
	neg := n < 0
	if neg {
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}

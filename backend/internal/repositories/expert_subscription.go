package repositories

import (
	"database/sql"
	"errors"
	"fmt"
	"halalstocks/internal/models"
	"strings"
	"time"
)

// ExpertSubscriptionRepository persists rows in expert_subscriptions.
type ExpertSubscriptionRepository struct {
	db *sql.DB
}

func NewExpertSubscriptionRepository(db *sql.DB) *ExpertSubscriptionRepository {
	return &ExpertSubscriptionRepository{db: db}
}

// Common errors surfaced to handlers so they can return precise HTTP codes.
var (
	ErrPendingSubExists = errors.New("a pending subscription already exists for this expert")
	ErrActiveSubExists  = errors.New("you already have an active subscription to this expert")
	ErrSubNotFound      = errors.New("subscription not found")
	ErrSubNotPending    = errors.New("subscription is not in pending state")
)

// ExpiredSubSummary — minimal info for one row that just got
// flipped from active → expired by the background job. Carries
// just enough for the realtime broadcast (user channel + expert
// id) without dragging the whole 17-column model along.
type ExpiredSubSummary struct {
	ID       int64
	UserID   int64
	ExpertID string
}

const subCols = `
	id, user_id, expert_id, plan, status, price_cents, currency,
	payment_method, payment_ref, user_note, rejection_reason,
	created_at, accepted_at, accepted_by, rejected_at, cancelled_at, expires_at,
	receipt_url
`

// CreateParams — destructured for readability; signature was getting long
// once we added receiptURL and currency on top of plan/method/price/etc.
type CreateExpertSubParams struct {
	UserID        int64
	ExpertID      string
	Plan          string
	PaymentMethod string
	PriceCents    int
	Currency      string // optional; falls back to "usd" if empty
	PaymentRef    string
	ReceiptURL    string
	UserNote      string
}

// Create inserts a new pending subscription.
//
// The DB has partial unique indexes that block:
//   - more than one pending row per (user, expert)
//   - more than one active row per (user, expert)
//
// Sprint-A step 1 — those indexes alone don't block the legal-but-
// undesired case of "1 active + 1 new pending" stacking on the same
// (user, expert). Without this guard a subscriber could submit a 2nd
// payment proof and pay twice. We pre-check inside the same call,
// returning ErrActiveSubExists so the handler can map to a typed 409.
//
// We surface the partial-index hits as typed errors too.
func (r *ExpertSubscriptionRepository) Create(p CreateExpertSubParams) (*models.ExpertSubscription, error) {
	// Active-sub pre-check (Sprint A #1). Cheap — backed by the
	// `expert_subs_one_active_per_pair` partial unique index.
	var activeExists bool
	if err := r.db.QueryRow(
		`SELECT EXISTS(
		    SELECT 1 FROM expert_subscriptions
		     WHERE user_id = $1 AND expert_id = $2 AND status = 'active'
		 )`, p.UserID, p.ExpertID,
	).Scan(&activeExists); err != nil {
		return nil, err
	}
	if activeExists {
		return nil, ErrActiveSubExists
	}

	var refArg, noteArg, receiptArg any
	if strings.TrimSpace(p.PaymentRef) != "" {
		refArg = strings.TrimSpace(p.PaymentRef)
	}
	if strings.TrimSpace(p.UserNote) != "" {
		noteArg = strings.TrimSpace(p.UserNote)
	}
	if strings.TrimSpace(p.ReceiptURL) != "" {
		receiptArg = strings.TrimSpace(p.ReceiptURL)
	}
	currency := strings.ToLower(strings.TrimSpace(p.Currency))
	if currency == "" {
		currency = "usd"
	}

	row := r.db.QueryRow(`
		INSERT INTO expert_subscriptions
		    (user_id, expert_id, plan, price_cents, currency,
		     payment_method, payment_ref, user_note, receipt_url)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING `+subCols,
		p.UserID, p.ExpertID, p.Plan, p.PriceCents, currency,
		p.PaymentMethod, refArg, noteArg, receiptArg,
	)
	sub, err := models.ScanSubscription(row)
	if err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "expert_subs_one_pending_per_pair"):
			return nil, ErrPendingSubExists
		case strings.Contains(msg, "expert_subs_one_active_per_pair"):
			return nil, ErrActiveSubExists
		}
		return nil, err
	}
	return sub, nil
}

// GetByID fetches a single subscription.
func (r *ExpertSubscriptionRepository) GetByID(id int64) (*models.ExpertSubscription, error) {
	row := r.db.QueryRow(`SELECT `+subCols+` FROM expert_subscriptions WHERE id = $1`, id)
	sub, err := models.ScanSubscription(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return sub, err
}

// AdminGetByID — same single-row fetch as GetByID, but joined against
// users + experts + reviewer so the response carries display fields the
// admin dashboard's detail page needs (UserEmail, UserName, ExpertName,
// and ReviewerEmail when an admin has acted on the row).
func (r *ExpertSubscriptionRepository) AdminGetByID(
	id int64,
) (*models.ExpertSubscription, error) {
	row := r.db.QueryRow(`
		SELECT s.id, s.user_id, s.expert_id, s.plan, s.status, s.price_cents, s.currency,
		       s.payment_method, s.payment_ref, s.user_note, s.rejection_reason,
		       s.created_at, s.accepted_at, s.accepted_by, s.rejected_at, s.cancelled_at, s.expires_at,
		       s.receipt_url,
		       u.email, COALESCE(u.name, ''), COALESCE(e.name, ''),
		       COALESCE(rev.email, '')
		  FROM expert_subscriptions s
		  JOIN users u        ON u.id = s.user_id
		  LEFT JOIN experts e ON e.id = s.expert_id
		  LEFT JOIN users rev ON rev.id = s.accepted_by
		 WHERE s.id = $1`, id)
	var (
		sub             models.ExpertSubscription
		paymentRef      sql.NullString
		userNote        sql.NullString
		rejectionReason sql.NullString
		acceptedAt      sql.NullTime
		acceptedBy      sql.NullInt64
		rejectedAt      sql.NullTime
		cancelledAt     sql.NullTime
		expiresAt       sql.NullTime
		receiptURL      sql.NullString
	)
	if err := row.Scan(
		&sub.ID, &sub.UserID, &sub.ExpertID, &sub.Plan, &sub.Status,
		&sub.PriceCents, &sub.Currency,
		&sub.PaymentMethod, &paymentRef, &userNote, &rejectionReason,
		&sub.CreatedAt, &acceptedAt, &acceptedBy, &rejectedAt, &cancelledAt, &expiresAt,
		&receiptURL,
		&sub.UserEmail, &sub.UserName, &sub.ExpertName,
		&sub.ReviewerEmail,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if paymentRef.Valid {
		sub.PaymentRef = &paymentRef.String
	}
	if userNote.Valid {
		sub.UserNote = &userNote.String
	}
	if rejectionReason.Valid {
		sub.RejectionReason = &rejectionReason.String
	}
	if acceptedAt.Valid {
		sub.AcceptedAt = &acceptedAt.Time
	}
	if acceptedBy.Valid {
		sub.AcceptedBy = &acceptedBy.Int64
	}
	if rejectedAt.Valid {
		sub.RejectedAt = &rejectedAt.Time
	}
	if cancelledAt.Valid {
		sub.CancelledAt = &cancelledAt.Time
	}
	if expiresAt.Valid {
		sub.ExpiresAt = &expiresAt.Time
	}
	if receiptURL.Valid {
		sub.ReceiptURL = &receiptURL.String
	}
	return &sub, nil
}

// HasActiveAccess returns true when the user holds an active, unexpired
// subscription for the given expert. Used by the post-gating logic in
// the social handler.
func (r *ExpertSubscriptionRepository) HasActiveAccess(userID int64, expertID string) (bool, error) {
	var exists bool
	err := r.db.QueryRow(`
		SELECT EXISTS (
		    SELECT 1 FROM expert_subscriptions
		    WHERE user_id = $1 AND expert_id = $2
		      AND status = 'active'
		      AND expires_at > NOW()
		)
	`, userID, expertID).Scan(&exists)
	return exists, err
}

// ListMine returns every subscription for a user, newest-first. Optionally
// filtered to a single expert. Joins with experts so the row carries the
// human-readable expert name (avoids "e2" appearing in the My Subscriptions
// screen when the client doesn't already have that expert cached).
func (r *ExpertSubscriptionRepository) ListMine(userID int64, expertID string) ([]*models.ExpertSubscription, error) {
	q := `
		SELECT s.id, s.user_id, s.expert_id, s.plan, s.status, s.price_cents, s.currency,
		       s.payment_method, s.payment_ref, s.user_note, s.rejection_reason,
		       s.created_at, s.accepted_at, s.accepted_by, s.rejected_at, s.cancelled_at, s.expires_at,
		       s.receipt_url,
		       COALESCE(e.name, '')
		FROM expert_subscriptions s
		LEFT JOIN experts e ON e.id = s.expert_id
		WHERE s.user_id = $1`
	args := []any{userID}
	if expertID != "" {
		args = append(args, expertID)
		q += ` AND s.expert_id = $2`
	}
	q += ` ORDER BY s.created_at DESC LIMIT 200`

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.ExpertSubscription
	for rows.Next() {
		var (
			sub             models.ExpertSubscription
			paymentRef      sql.NullString
			userNote        sql.NullString
			rejectionReason sql.NullString
			acceptedAt      sql.NullTime
			acceptedBy      sql.NullInt64
			rejectedAt      sql.NullTime
			cancelledAt     sql.NullTime
			expiresAt       sql.NullTime
			receiptURL      sql.NullString
		)
		if err := rows.Scan(
			&sub.ID, &sub.UserID, &sub.ExpertID, &sub.Plan, &sub.Status,
			&sub.PriceCents, &sub.Currency,
			&sub.PaymentMethod, &paymentRef, &userNote, &rejectionReason,
			&sub.CreatedAt, &acceptedAt, &acceptedBy, &rejectedAt, &cancelledAt, &expiresAt,
			&receiptURL,
			&sub.ExpertName,
		); err != nil {
			return nil, err
		}
		if paymentRef.Valid {
			sub.PaymentRef = &paymentRef.String
		}
		if userNote.Valid {
			sub.UserNote = &userNote.String
		}
		if rejectionReason.Valid {
			sub.RejectionReason = &rejectionReason.String
		}
		if acceptedAt.Valid {
			sub.AcceptedAt = &acceptedAt.Time
		}
		if acceptedBy.Valid {
			sub.AcceptedBy = &acceptedBy.Int64
		}
		if rejectedAt.Valid {
			sub.RejectedAt = &rejectedAt.Time
		}
		if cancelledAt.Valid {
			sub.CancelledAt = &cancelledAt.Time
		}
		if expiresAt.Valid {
			sub.ExpiresAt = &expiresAt.Time
		}
		if receiptURL.Valid {
			sub.ReceiptURL = &receiptURL.String
		}
		out = append(out, &sub)
	}
	return out, rows.Err()
}

// AdminSubFilter — search / pagination knobs for the admin Subscriptions
// page.
//
//   * Status        — exact match on s.status. "" → all.
//   * Query         — ILIKE against user email / name + expert name. "" → no
//                     filter.
//   * PaymentMethod — "cash" | "fib" | "" (no filter).
//   * Cursor        — id of the last row from the previous page; rows older
//                     than that id are returned. 0 → newest page.
//   * Limit         — clamped to [1, 100], default 50.
type AdminSubFilter struct {
	Status        string
	Query         string
	PaymentMethod string
	Cursor        int64
	Limit         int
}

// ListByStatus returns rows for the admin dashboard, newest-first, joined
// with the user's email/name and the expert's display name. Cursor-based
// pagination so admins beyond row 200 still see something.
func (r *ExpertSubscriptionRepository) ListByStatus(filter AdminSubFilter) ([]*models.ExpertSubscription, error) {
	limit := filter.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	q := `
		SELECT s.id, s.user_id, s.expert_id, s.plan, s.status, s.price_cents, s.currency,
		       s.payment_method, s.payment_ref, s.user_note, s.rejection_reason,
		       s.created_at, s.accepted_at, s.accepted_by, s.rejected_at, s.cancelled_at, s.expires_at,
		       s.receipt_url,
		       u.email, COALESCE(u.name, ''), COALESCE(e.name, '')
		FROM expert_subscriptions s
		JOIN users u   ON u.id = s.user_id
		LEFT JOIN experts e ON e.id = s.expert_id
	`
	args := []any{}
	conds := []string{}
	if filter.Status != "" {
		args = append(args, filter.Status)
		conds = append(conds, fmt.Sprintf("s.status = $%d", len(args)))
	}
	if filter.PaymentMethod != "" {
		args = append(args, filter.PaymentMethod)
		conds = append(conds, fmt.Sprintf("s.payment_method = $%d", len(args)))
	}
	if s := strings.TrimSpace(filter.Query); s != "" {
		args = append(args, "%"+s+"%")
		conds = append(conds, fmt.Sprintf(
			"(u.email ILIKE $%d OR u.name ILIKE $%d OR e.name ILIKE $%d)",
			len(args), len(args), len(args),
		))
	}
	if filter.Cursor > 0 {
		args = append(args, filter.Cursor)
		conds = append(conds, fmt.Sprintf("s.id < $%d", len(args)))
	}
	if len(conds) > 0 {
		q += " WHERE " + strings.Join(conds, " AND ")
	}
	args = append(args, limit)
	q += fmt.Sprintf(" ORDER BY s.id DESC LIMIT $%d", len(args))

	rows, err := r.db.Query(q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var out []*models.ExpertSubscription
	for rows.Next() {
		var (
			sub             models.ExpertSubscription
			paymentRef      sql.NullString
			userNote        sql.NullString
			rejectionReason sql.NullString
			acceptedAt      sql.NullTime
			acceptedBy      sql.NullInt64
			rejectedAt      sql.NullTime
			cancelledAt     sql.NullTime
			expiresAt       sql.NullTime
			receiptURL      sql.NullString
		)
		if err := rows.Scan(
			&sub.ID, &sub.UserID, &sub.ExpertID, &sub.Plan, &sub.Status,
			&sub.PriceCents, &sub.Currency,
			&sub.PaymentMethod, &paymentRef, &userNote, &rejectionReason,
			&sub.CreatedAt, &acceptedAt, &acceptedBy, &rejectedAt, &cancelledAt, &expiresAt,
			&receiptURL,
			&sub.UserEmail, &sub.UserName, &sub.ExpertName,
		); err != nil {
			return nil, err
		}
		if paymentRef.Valid {
			sub.PaymentRef = &paymentRef.String
		}
		if userNote.Valid {
			sub.UserNote = &userNote.String
		}
		if rejectionReason.Valid {
			sub.RejectionReason = &rejectionReason.String
		}
		if acceptedAt.Valid {
			sub.AcceptedAt = &acceptedAt.Time
		}
		if acceptedBy.Valid {
			sub.AcceptedBy = &acceptedBy.Int64
		}
		if rejectedAt.Valid {
			sub.RejectedAt = &rejectedAt.Time
		}
		if cancelledAt.Valid {
			sub.CancelledAt = &cancelledAt.Time
		}
		if expiresAt.Valid {
			sub.ExpiresAt = &expiresAt.Time
		}
		if receiptURL.Valid {
			sub.ReceiptURL = &receiptURL.String
		}
		out = append(out, &sub)
	}
	return out, rows.Err()
}

// AdminTotals — aggregate counts + sum for the admin Subscriptions header
// strip. Only counts active subs in the revenue figure (pending/rejected/
// cancelled don't represent collected money). Filter by payment_method
// when non-empty.
type AdminSubTotals struct {
	ActiveCount   int    `json:"activeCount"`
	PendingCount  int    `json:"pendingCount"`
	ActiveRevenue int    `json:"activeRevenueCents"`
	Currency      string `json:"currency"`
}

func (r *ExpertSubscriptionRepository) AdminTotals() (*AdminSubTotals, error) {
	row := r.db.QueryRow(`
		SELECT
		  COUNT(*) FILTER (WHERE status = 'active') AS active_count,
		  COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
		  COALESCE(SUM(price_cents) FILTER (WHERE status = 'active'), 0) AS active_revenue,
		  COALESCE(MAX(currency), 'usd')
		  FROM expert_subscriptions
	`)
	var t AdminSubTotals
	if err := row.Scan(&t.ActiveCount, &t.PendingCount, &t.ActiveRevenue, &t.Currency); err != nil {
		return nil, err
	}
	return &t, nil
}

// CountPending returns the number of pending subscriptions — used by the
// admin sidebar badge.
func (r *ExpertSubscriptionRepository) CountPending() (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM expert_subscriptions WHERE status = 'pending'`).Scan(&n)
	return n, err
}

// ExpertTotals — per-expert aggregation, scoped to ONE expert profile.
// Powers the studio dashboard's "metrics" row (Phase 3.1) and the
// earnings screen (Phase 3.3). All counts/sums respect status so we
// never show pending/cancelled revenue as if it had been collected.
type ExpertTotals struct {
	ActiveSubscribers   int    `json:"activeSubscribers"`
	PendingSubscribers  int    `json:"pendingSubscribers"`
	LifetimeSubscribers int    `json:"lifetimeSubscribers"` // includes expired/cancelled
	LifetimeRevenue     int    `json:"lifetimeRevenueCents"`
	ActiveRevenue       int    `json:"activeRevenueCents"`
	Currency            string `json:"currency"`
}

// TotalsForExpert — aggregates expert_subscriptions for ONE expertId.
// Active = subscription still in its paid window. Lifetime revenue
// counts every accepted/active sub the expert has ever sold (cancelled
// ones too — they paid, then later cancelled).
func (r *ExpertSubscriptionRepository) TotalsForExpert(expertID string) (*ExpertTotals, error) {
	row := r.db.QueryRow(`
		SELECT
		  COUNT(*) FILTER (WHERE status = 'active') AS active_count,
		  COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
		  COUNT(*) FILTER (WHERE status IN ('active','cancelled','expired')) AS lifetime_count,
		  COALESCE(SUM(price_cents) FILTER (WHERE status IN ('active','cancelled','expired')), 0) AS lifetime_revenue,
		  COALESCE(SUM(price_cents) FILTER (WHERE status = 'active'), 0) AS active_revenue,
		  COALESCE(MAX(currency), 'usd')
		FROM expert_subscriptions
		WHERE expert_id = $1
	`, expertID)
	var t ExpertTotals
	if err := row.Scan(
		&t.ActiveSubscribers, &t.PendingSubscribers, &t.LifetimeSubscribers,
		&t.LifetimeRevenue, &t.ActiveRevenue, &t.Currency,
	); err != nil {
		return nil, err
	}
	return &t, nil
}

// EarningsDayPoint — one bucket on the earnings chart. Aggregates
// accepted (paid-in-full) subscriptions by accepted_at day. We don't
// pro-rate yearly subscriptions across their lifetime — the full
// price is attributed to the day the payment landed, which matches
// how Stripe / App Store reports work.
type EarningsDayPoint struct {
	Day          string `json:"day"`           // YYYY-MM-DD (UTC)
	RevenueCents int    `json:"revenueCents"`
	NewSubs      int    `json:"newSubs"`
}

// EarningsHistory returns daily revenue for the last [days] days,
// oldest first. Days with no activity are present with revenue=0 so
// charts render a flat line instead of skipping the empty buckets.
func (r *ExpertSubscriptionRepository) EarningsHistory(expertID string, days int) ([]EarningsDayPoint, error) {
	if days <= 0 || days > 365 {
		days = 30
	}
	rows, err := r.db.Query(`
		WITH series AS (
		  SELECT generate_series(
		    (CURRENT_DATE - ($2::int - 1))::date,
		    CURRENT_DATE,
		    '1 day'::interval
		  )::date AS day
		),
		buckets AS (
		  SELECT date_trunc('day', accepted_at)::date AS day,
		         COALESCE(SUM(price_cents), 0) AS revenue,
		         COUNT(*) AS new_subs
		  FROM expert_subscriptions
		  WHERE expert_id = $1
		    AND accepted_at IS NOT NULL
		    AND accepted_at >= (CURRENT_DATE - ($2::int - 1))
		  GROUP BY 1
		)
		SELECT
		  to_char(s.day, 'YYYY-MM-DD'),
		  COALESCE(b.revenue, 0),
		  COALESCE(b.new_subs, 0)
		FROM series s
		LEFT JOIN buckets b ON b.day = s.day
		ORDER BY s.day ASC
	`, expertID, days)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]EarningsDayPoint, 0, days)
	for rows.Next() {
		var p EarningsDayPoint
		if err := rows.Scan(&p.Day, &p.RevenueCents, &p.NewSubs); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// Accept flips a pending subscription to active and computes its expiry.
// The admin's id is stored in accepted_by. Idempotent enough — a non-pending
// subscription returns ErrSubNotPending.
func (r *ExpertSubscriptionRepository) Accept(id, adminID int64) (*models.ExpertSubscription, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var plan, status string
	if err := tx.QueryRow(`
		SELECT plan, status FROM expert_subscriptions WHERE id = $1 FOR UPDATE
	`, id).Scan(&plan, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrSubNotFound
		}
		return nil, err
	}
	if status != models.SubStatusPending {
		return nil, ErrSubNotPending
	}

	now := time.Now()
	expiresAt := now.Add(models.DurationForPlan(plan))

	if _, err := tx.Exec(`
		UPDATE expert_subscriptions
		   SET status      = 'active',
		       accepted_at = $1,
		       accepted_by = $2,
		       expires_at  = $3
		 WHERE id = $4
	`, now, adminID, expiresAt, id); err != nil {
		// The unique partial index on (user, expert) WHERE status='active'
		// blocks accepting if another active sub already exists.
		if strings.Contains(err.Error(), "expert_subs_one_active_per_pair") {
			return nil, ErrActiveSubExists
		}
		return nil, fmt.Errorf("accept: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.GetByID(id)
}

// Reject marks a pending subscription rejected. reason is optional.
//
// FIXED in step B1 — no longer writes the rejecting admin's id into
// `accepted_by`. That column means "admin who accepted" and stomping
// on it on rejection corrupted history. Who rejected is now tracked
// via the audit log only (see audit_subscription_change trigger from
// mig 0007). Transactional + FOR UPDATE so two admins racing on the
// same row don't both succeed.
func (r *ExpertSubscriptionRepository) Reject(id, _ int64, reason string) (*models.ExpertSubscription, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var status string
	if err := tx.QueryRow(
		`SELECT status FROM expert_subscriptions WHERE id = $1 FOR UPDATE`, id,
	).Scan(&status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrSubNotFound
		}
		return nil, err
	}
	if status != models.SubStatusPending {
		return nil, ErrSubNotPending
	}

	var reasonArg any
	if strings.TrimSpace(reason) != "" {
		reasonArg = strings.TrimSpace(reason)
	}
	if _, err := tx.Exec(`
		UPDATE expert_subscriptions
		   SET status           = 'rejected',
		       rejection_reason = $1,
		       rejected_at      = NOW()
		 WHERE id = $2
	`, reasonArg, id); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.GetByID(id)
}

// Cancel — user-initiated. Works on any non-terminal status (pending or
// active). Sets cancelled_at and flips status. Returns the updated row.
func (r *ExpertSubscriptionRepository) Cancel(id, userID int64) (*models.ExpertSubscription, error) {
	res, err := r.db.Exec(`
		UPDATE expert_subscriptions
		   SET status       = 'cancelled',
		       cancelled_at = NOW()
		 WHERE id = $1 AND user_id = $2
		   AND status IN ('pending','active')
	`, id, userID)
	if err != nil {
		return nil, err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		got, err := r.GetByID(id)
		if err != nil {
			return nil, err
		}
		if got == nil || got.UserID != userID {
			return nil, ErrSubNotFound
		}
		// already terminal — return it as-is
		return got, nil
	}
	return r.GetByID(id)
}

// ExpireDue flips every active subscription whose expires_at has
// passed to status='expired'. Returns a summary row per affected
// subscription so the background job can fan out a
// `subscription_expired` realtime event to each user.
//
// Idempotent — re-running with no due rows returns an empty slice.
// Uses RETURNING so the UPDATE and the read happen in one round
// trip with no race window between them.
func (r *ExpertSubscriptionRepository) ExpireDue() ([]ExpiredSubSummary, error) {
	rows, err := r.db.Query(`
		UPDATE expert_subscriptions
		   SET status = 'expired'
		 WHERE status = 'active'
		   AND expires_at IS NOT NULL
		   AND expires_at < NOW()
		RETURNING id, user_id, expert_id
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]ExpiredSubSummary, 0)
	for rows.Next() {
		var s ExpiredSubSummary
		if err := rows.Scan(&s.ID, &s.UserID, &s.ExpertID); err != nil {
			return nil, err
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// ActivateFromIAP inserts a row that is immediately active. Used by the
// Apple/Google IAP verification path, where the store has already
// confirmed payment — there's no admin review step. The expires_at
// comes from the store's renewal date (so when Apple says "expires Jan
// 5", that's exactly what we store).
//
// Returns ErrActiveSubExists when the user already has an overlapping
// active sub for this expert — the caller should treat that as success
// (the receipt was a renewal that we already counted).
func (r *ExpertSubscriptionRepository) ActivateFromIAP(
	userID int64,
	expertID string,
	plan string,
	paymentMethod string,
	paymentRef string,
	purchasedAt time.Time,
	expiresAt *time.Time,
) error {
	priceCents := models.PriceForPlan(plan)
	now := purchasedAt
	if now.IsZero() {
		now = time.Now().UTC()
	}

	_, err := r.db.Exec(`
		INSERT INTO expert_subscriptions
		    (user_id, expert_id, plan, status, price_cents, currency,
		     payment_method, payment_ref, created_at, accepted_at, expires_at)
		VALUES ($1, $2, $3, 'active', $4, 'usd', $5, $6, $7, $7, $8)
	`, userID, expertID, plan, priceCents, paymentMethod, paymentRef, now, expiresAt)
	if err != nil {
		msg := err.Error()
		if strings.Contains(msg, "expert_subs_one_active_per_pair") {
			return ErrActiveSubExists
		}
		return err
	}
	return nil
}

package repositories

import (
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"
)

// =============================================================================
// CommunitySubscriptionsRepository — paid community membership lifecycle
// (mig 0022, item 23).
//
// User submits a payment proof → admin reviews → admin Accepts which
// inserts a community_members row in the same transaction. Mirrors
// ExpertSubscriptionRepository so the admin queue + expirer can share
// the same patterns.
// =============================================================================

type CommunitySubscriptionsRepository struct {
	db *sql.DB
}

func NewCommunitySubscriptionsRepository(db *sql.DB) *CommunitySubscriptionsRepository {
	return &CommunitySubscriptionsRepository{db: db}
}

// Sentinel errors so the handler can map to clean HTTP statuses.
var (
	ErrCommSubNotFound      = errors.New("community subscription not found")
	ErrCommSubNotPending    = errors.New("subscription is not pending")
	ErrPendingCommSubExists = errors.New("pending subscription already exists")
	ErrActiveCommSubExists  = errors.New("active subscription already exists")
	ErrCommunityNotPaid     = errors.New("community is free; no subscription needed")
)

// CommunitySubscription — one row in the table. JSON-tagged for the
// admin dashboard + mobile mySubs flows.
type CommunitySubscription struct {
	ID              int64      `json:"id"`
	UserID          int64      `json:"userId"`
	CommunityID     string     `json:"communityId"`
	Plan            string     `json:"plan"` // monthly | yearly
	Status          string     `json:"status"`
	PriceCents      int        `json:"priceCents"`
	Currency        string     `json:"currency"`
	PaymentMethod   string     `json:"paymentMethod"`
	PaymentRef      *string    `json:"paymentRef,omitempty"`
	// Cash-receipt image URL (mig 0025). Optional /uploads/images/...
	// — admin verifies cash payments against the photo, not just text.
	ReceiptURL      *string    `json:"receiptUrl,omitempty"`
	UserNote        *string    `json:"userNote,omitempty"`
	RejectionReason *string    `json:"rejectionReason,omitempty"`
	CreatedAt       time.Time  `json:"createdAt"`
	AcceptedAt      *time.Time `json:"acceptedAt,omitempty"`
	AcceptedBy      *int64     `json:"acceptedBy,omitempty"`
	RejectedAt      *time.Time `json:"rejectedAt,omitempty"`
	CancelledAt     *time.Time `json:"cancelledAt,omitempty"`
	ExpiresAt       *time.Time `json:"expiresAt,omitempty"`
	// Denormalised at read time so the dashboard / mobile don't have
	// to do follow-up lookups.
	UserEmail     string `json:"userEmail,omitempty"`
	UserName      string `json:"userName,omitempty"`
	CommunityName string `json:"communityName,omitempty"`
	ReviewerEmail string `json:"reviewerEmail,omitempty"`
}

const commSubCols = `
	id, user_id, community_id, plan, status, price_cents, currency,
	payment_method, payment_ref, user_note, rejection_reason,
	created_at, accepted_at, accepted_by, rejected_at, cancelled_at, expires_at,
	receipt_url
`

// scanCommSub — fills nullable fields cleanly. Caller passes either an
// *sql.Row OR an *sql.Rows row already advanced to .Next().
type commSubScanner interface {
	Scan(dest ...any) error
}

func scanCommSub(s commSubScanner) (*CommunitySubscription, error) {
	var x CommunitySubscription
	var (
		paymentRef  sql.NullString
		userNote    sql.NullString
		rejection   sql.NullString
		acceptedAt  sql.NullTime
		acceptedBy  sql.NullInt64
		rejectedAt  sql.NullTime
		cancelledAt sql.NullTime
		expiresAt   sql.NullTime
		receiptURL  sql.NullString
	)
	if err := s.Scan(
		&x.ID, &x.UserID, &x.CommunityID, &x.Plan, &x.Status,
		&x.PriceCents, &x.Currency,
		&x.PaymentMethod, &paymentRef, &userNote, &rejection,
		&x.CreatedAt, &acceptedAt, &acceptedBy,
		&rejectedAt, &cancelledAt, &expiresAt,
		&receiptURL,
	); err != nil {
		return nil, err
	}
	if paymentRef.Valid {
		x.PaymentRef = &paymentRef.String
	}
	if userNote.Valid {
		x.UserNote = &userNote.String
	}
	if rejection.Valid {
		x.RejectionReason = &rejection.String
	}
	if acceptedAt.Valid {
		x.AcceptedAt = &acceptedAt.Time
	}
	if acceptedBy.Valid {
		x.AcceptedBy = &acceptedBy.Int64
	}
	if rejectedAt.Valid {
		x.RejectedAt = &rejectedAt.Time
	}
	if cancelledAt.Valid {
		x.CancelledAt = &cancelledAt.Time
	}
	if expiresAt.Valid {
		x.ExpiresAt = &expiresAt.Time
	}
	if receiptURL.Valid {
		x.ReceiptURL = &receiptURL.String
	}
	return &x, nil
}

// CreateCommSubParams — destructured args. Was getting unwieldy once we
// added receiptUrl + currency on top of the original 6-arg signature.
type CreateCommSubParams struct {
	UserID        int64
	CommunityID   string
	Plan          string
	PaymentMethod string
	PaymentRef    string
	ReceiptURL    string
	UserNote      string
	PriceCents    int
	Currency      string
}

// Create inserts a new pending row. Pulls the price + currency from
// the community's pricing fields based on `plan`. The handler is
// responsible for verifying the community has a non-zero price for
// that plan before calling.
//
// Surfaces ErrPendingCommSubExists / ErrActiveCommSubExists when the
// partial unique indexes block a duplicate row.
//
// Sprint-A step 2 — pre-check that no `active` sub already exists for
// (user, community). The partial unique indexes block "two active"
// and "two pending" but allow "one active + one new pending" — which
// would let a paid user submit a 2nd payment proof. Refuse that.
func (r *CommunitySubscriptionsRepository) Create(p CreateCommSubParams) (*CommunitySubscription, error) {
	// Active-sub pre-check (Sprint A #2).
	var activeExists bool
	if err := r.db.QueryRow(
		`SELECT EXISTS(
		    SELECT 1 FROM community_subscriptions
		     WHERE user_id = $1 AND community_id = $2 AND status = 'active'
		 )`, p.UserID, p.CommunityID,
	).Scan(&activeExists); err != nil {
		return nil, err
	}
	if activeExists {
		return nil, ErrActiveCommSubExists
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
		INSERT INTO community_subscriptions
		    (user_id, community_id, plan, price_cents, currency,
		     payment_method, payment_ref, user_note, receipt_url)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING `+commSubCols,
		p.UserID, p.CommunityID, p.Plan, p.PriceCents, currency,
		p.PaymentMethod, refArg, noteArg, receiptArg,
	)
	sub, err := scanCommSub(row)
	if err != nil {
		msg := err.Error()
		switch {
		case strings.Contains(msg, "comm_subs_one_pending_per_pair"):
			return nil, ErrPendingCommSubExists
		case strings.Contains(msg, "comm_subs_one_active_per_pair"):
			return nil, ErrActiveCommSubExists
		}
		return nil, err
	}
	return sub, nil
}

// GetByID — single-row fetch. Returns (nil, nil) when not found so
// the handler can surface a 404.
func (r *CommunitySubscriptionsRepository) GetByID(id int64) (*CommunitySubscription, error) {
	row := r.db.QueryRow(`SELECT `+commSubCols+` FROM community_subscriptions WHERE id = $1`, id)
	sub, err := scanCommSub(row)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	return sub, err
}

// AdminGetByID — single row joined against users + communities + reviewer
// (LEFT JOIN to handle pending rows where accepted_by is NULL). Includes
// the receipt_url so the detail page can render the cash-receipt image.
func (r *CommunitySubscriptionsRepository) AdminGetByID(id int64) (*CommunitySubscription, error) {
	row := r.db.QueryRow(`
		SELECT s.id, s.user_id, s.community_id, s.plan, s.status,
		       s.price_cents, s.currency, s.payment_method, s.payment_ref,
		       s.user_note, s.rejection_reason, s.created_at,
		       s.accepted_at, s.accepted_by, s.rejected_at,
		       s.cancelled_at, s.expires_at, s.receipt_url,
		       u.email, COALESCE(u.name, ''), c.name,
		       COALESCE(rev.email, '')
		  FROM community_subscriptions s
		  JOIN users u       ON u.id = s.user_id
		  JOIN communities c ON c.id = s.community_id
		  LEFT JOIN users rev ON rev.id = s.accepted_by
		 WHERE s.id = $1`, id)
	var x CommunitySubscription
	var (
		paymentRef  sql.NullString
		userNote    sql.NullString
		rejection   sql.NullString
		acceptedAt  sql.NullTime
		acceptedBy  sql.NullInt64
		rejectedAt  sql.NullTime
		cancelledAt sql.NullTime
		expiresAt   sql.NullTime
		receiptURL  sql.NullString
	)
	if err := row.Scan(
		&x.ID, &x.UserID, &x.CommunityID, &x.Plan, &x.Status,
		&x.PriceCents, &x.Currency,
		&x.PaymentMethod, &paymentRef, &userNote, &rejection,
		&x.CreatedAt, &acceptedAt, &acceptedBy,
		&rejectedAt, &cancelledAt, &expiresAt, &receiptURL,
		&x.UserEmail, &x.UserName, &x.CommunityName,
		&x.ReviewerEmail,
	); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	if paymentRef.Valid {
		x.PaymentRef = &paymentRef.String
	}
	if userNote.Valid {
		x.UserNote = &userNote.String
	}
	if rejection.Valid {
		x.RejectionReason = &rejection.String
	}
	if acceptedAt.Valid {
		x.AcceptedAt = &acceptedAt.Time
	}
	if acceptedBy.Valid {
		x.AcceptedBy = &acceptedBy.Int64
	}
	if rejectedAt.Valid {
		x.RejectedAt = &rejectedAt.Time
	}
	if cancelledAt.Valid {
		x.CancelledAt = &cancelledAt.Time
	}
	if expiresAt.Valid {
		x.ExpiresAt = &expiresAt.Time
	}
	if receiptURL.Valid {
		x.ReceiptURL = &receiptURL.String
	}
	return &x, nil
}

// ListMine returns every subscription a user has, newest-first. Drives
// the user's own "My community subs" screen + the social hub's
// "Pending payment" sub-section.
func (r *CommunitySubscriptionsRepository) ListMine(userID int64) ([]*CommunitySubscription, error) {
	rows, err := r.db.Query(`
		SELECT s.id, s.user_id, s.community_id, s.plan, s.status,
		       s.price_cents, s.currency, s.payment_method, s.payment_ref,
		       s.user_note, s.rejection_reason, s.created_at,
		       s.accepted_at, s.accepted_by, s.rejected_at,
		       s.cancelled_at, s.expires_at, s.receipt_url,
		       '' as ue, '' as un, c.name
		  FROM community_subscriptions s
		  JOIN communities c ON c.id = s.community_id
		 WHERE s.user_id = $1
		 ORDER BY s.created_at DESC LIMIT 200`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]*CommunitySubscription, 0)
	for rows.Next() {
		var x CommunitySubscription
		var (
			paymentRef  sql.NullString
			userNote    sql.NullString
			rejection   sql.NullString
			acceptedAt  sql.NullTime
			acceptedBy  sql.NullInt64
			rejectedAt  sql.NullTime
			cancelledAt sql.NullTime
			expiresAt   sql.NullTime
			receiptURL  sql.NullString
		)
		if err := rows.Scan(
			&x.ID, &x.UserID, &x.CommunityID, &x.Plan, &x.Status,
			&x.PriceCents, &x.Currency,
			&x.PaymentMethod, &paymentRef, &userNote, &rejection,
			&x.CreatedAt, &acceptedAt, &acceptedBy,
			&rejectedAt, &cancelledAt, &expiresAt, &receiptURL,
			&x.UserEmail, &x.UserName, &x.CommunityName,
		); err != nil {
			return nil, err
		}
		if paymentRef.Valid {
			x.PaymentRef = &paymentRef.String
		}
		if userNote.Valid {
			x.UserNote = &userNote.String
		}
		if rejection.Valid {
			x.RejectionReason = &rejection.String
		}
		if acceptedAt.Valid {
			x.AcceptedAt = &acceptedAt.Time
		}
		if acceptedBy.Valid {
			x.AcceptedBy = &acceptedBy.Int64
		}
		if rejectedAt.Valid {
			x.RejectedAt = &rejectedAt.Time
		}
		if cancelledAt.Valid {
			x.CancelledAt = &cancelledAt.Time
		}
		if expiresAt.Valid {
			x.ExpiresAt = &expiresAt.Time
		}
		if receiptURL.Valid {
			x.ReceiptURL = &receiptURL.String
		}
		out = append(out, &x)
	}
	return out, rows.Err()
}

// ListForUser — admin-side: every community sub for a single user. Used
// by the "view this user's other subs" link from CommunitySubscriptionDetail
// (item C11) so admin can spot abuse / multiple paid communities at a glance.
func (r *CommunitySubscriptionsRepository) ListForUser(userID int64) ([]*CommunitySubscription, error) {
	return r.ListMine(userID)
}

// AdminCommSubFilter — search / pagination knobs for the admin
// CommunitySubscriptions page. Mirrors AdminSubFilter on expert subs.
type AdminCommSubFilter struct {
	Status        string
	Query         string
	PaymentMethod string
	Cursor        int64
	Limit         int
}

// ListByStatus — admin queue with status / payment-method / search /
// cursor pagination. Newest-first by id-desc so cursor-based paging
// stays stable against concurrent inserts.
func (r *CommunitySubscriptionsRepository) ListByStatus(filter AdminCommSubFilter) ([]*CommunitySubscription, error) {
	limit := filter.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	q := `
		SELECT s.id, s.user_id, s.community_id, s.plan, s.status,
		       s.price_cents, s.currency, s.payment_method, s.payment_ref,
		       s.user_note, s.rejection_reason, s.created_at,
		       s.accepted_at, s.accepted_by, s.rejected_at,
		       s.cancelled_at, s.expires_at, s.receipt_url,
		       u.email, COALESCE(u.name, ''), c.name
		  FROM community_subscriptions s
		  JOIN users u       ON u.id = s.user_id
		  JOIN communities c ON c.id = s.community_id`
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
			"(u.email ILIKE $%d OR u.name ILIKE $%d OR c.name ILIKE $%d)",
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
	out := make([]*CommunitySubscription, 0)
	for rows.Next() {
		var x CommunitySubscription
		var (
			paymentRef  sql.NullString
			userNote    sql.NullString
			rejection   sql.NullString
			acceptedAt  sql.NullTime
			acceptedBy  sql.NullInt64
			rejectedAt  sql.NullTime
			cancelledAt sql.NullTime
			expiresAt   sql.NullTime
			receiptURL  sql.NullString
		)
		if err := rows.Scan(
			&x.ID, &x.UserID, &x.CommunityID, &x.Plan, &x.Status,
			&x.PriceCents, &x.Currency,
			&x.PaymentMethod, &paymentRef, &userNote, &rejection,
			&x.CreatedAt, &acceptedAt, &acceptedBy,
			&rejectedAt, &cancelledAt, &expiresAt, &receiptURL,
			&x.UserEmail, &x.UserName, &x.CommunityName,
		); err != nil {
			return nil, err
		}
		if paymentRef.Valid {
			x.PaymentRef = &paymentRef.String
		}
		if userNote.Valid {
			x.UserNote = &userNote.String
		}
		if rejection.Valid {
			x.RejectionReason = &rejection.String
		}
		if acceptedAt.Valid {
			x.AcceptedAt = &acceptedAt.Time
		}
		if acceptedBy.Valid {
			x.AcceptedBy = &acceptedBy.Int64
		}
		if rejectedAt.Valid {
			x.RejectedAt = &rejectedAt.Time
		}
		if cancelledAt.Valid {
			x.CancelledAt = &cancelledAt.Time
		}
		if expiresAt.Valid {
			x.ExpiresAt = &expiresAt.Time
		}
		if receiptURL.Valid {
			x.ReceiptURL = &receiptURL.String
		}
		out = append(out, &x)
	}
	return out, rows.Err()
}

// CountPending — sidebar badge.
func (r *CommunitySubscriptionsRepository) CountPending() (int, error) {
	var n int
	err := r.db.QueryRow(
		`SELECT COUNT(*) FROM community_subscriptions WHERE status = 'pending'`,
	).Scan(&n)
	return n, err
}

// AdminCommSubTotals — header strip on the admin queue.
type AdminCommSubTotals struct {
	ActiveCount   int    `json:"activeCount"`
	PendingCount  int    `json:"pendingCount"`
	ActiveRevenue int    `json:"activeRevenueCents"`
	Currency      string `json:"currency"`
}

func (r *CommunitySubscriptionsRepository) AdminTotals() (*AdminCommSubTotals, error) {
	row := r.db.QueryRow(`
		SELECT
		  COUNT(*) FILTER (WHERE status = 'active') AS active_count,
		  COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
		  COALESCE(SUM(price_cents) FILTER (WHERE status = 'active'), 0) AS active_revenue,
		  COALESCE(MAX(currency), 'usd')
		  FROM community_subscriptions
	`)
	var t AdminCommSubTotals
	if err := row.Scan(&t.ActiveCount, &t.PendingCount, &t.ActiveRevenue, &t.Currency); err != nil {
		return nil, err
	}
	return &t, nil
}

// Accept — flip pending → active, set expires_at, AND insert the
// matching community_members row in the same transaction. If the user
// is already a member (somehow), the INSERT silently no-ops via
// ON CONFLICT.
//
// Returns sentinel errors:
//   - ErrCommSubNotFound  → row doesn't exist
//   - ErrCommSubNotPending → row exists but isn't pending
func (r *CommunitySubscriptionsRepository) Accept(
	id, adminID int64,
) (*CommunitySubscription, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Lock the row so a concurrent admin can't double-accept.
	var (
		userID      int64
		communityID string
		plan        string
		status      string
	)
	err = tx.QueryRow(
		`SELECT user_id, community_id, plan, status
		   FROM community_subscriptions WHERE id = $1 FOR UPDATE`,
		id,
	).Scan(&userID, &communityID, &plan, &status)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrCommSubNotFound
	}
	if err != nil {
		return nil, err
	}
	if status != "pending" {
		return nil, ErrCommSubNotPending
	}

	// Plan duration: monthly = 30d, yearly = 365d. Decided by the
	// plan field on the row, not by the community's current pricing
	// (so a price change after submission doesn't change the granted
	// access window).
	var ttl time.Duration
	switch plan {
	case "monthly":
		ttl = 30 * 24 * time.Hour
	case "yearly":
		ttl = 365 * 24 * time.Hour
	default:
		ttl = 30 * 24 * time.Hour
	}
	expiresAt := time.Now().Add(ttl)

	if _, err := tx.Exec(
		`UPDATE community_subscriptions
		    SET status = 'active', accepted_at = NOW(),
		        accepted_by = $1, expires_at = $2
		  WHERE id = $3`,
		adminID, expiresAt, id,
	); err != nil {
		return nil, err
	}
	// Insert the membership row — ON CONFLICT keeps it idempotent.
	if _, err := tx.Exec(
		`INSERT INTO community_members (user_id, community_id)
		 VALUES ($1, $2) ON CONFLICT DO NOTHING`,
		userID, communityID,
	); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.AdminGetByID(id)
}

// Reject — flip pending → rejected with optional reason. Same
// sentinel-error behaviour as Accept.
//
// Step C7 — transactional + `FOR UPDATE` so two admins clicking Reject
// on the same row at the same time can't both succeed.
func (r *CommunitySubscriptionsRepository) Reject(
	id int64, reason string,
) (*CommunitySubscription, error) {
	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	var status string
	if err := tx.QueryRow(
		`SELECT status FROM community_subscriptions WHERE id = $1 FOR UPDATE`, id,
	).Scan(&status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrCommSubNotFound
		}
		return nil, err
	}
	if status != "pending" {
		return nil, ErrCommSubNotPending
	}
	var reasonArg any
	if strings.TrimSpace(reason) != "" {
		reasonArg = strings.TrimSpace(reason)
	}
	if _, err := tx.Exec(
		`UPDATE community_subscriptions
		    SET status = 'rejected', rejected_at = NOW(),
		        rejection_reason = $1
		  WHERE id = $2`,
		reasonArg, id,
	); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return r.AdminGetByID(id)
}

// Cancel — user-initiated. Active → cancelled (also removes the
// member row); pending → cancelled (no member row to remove). Returns
// ErrCommSubNotFound if the row doesn't belong to userID.
func (r *CommunitySubscriptionsRepository) Cancel(id, userID int64) error {
	tx, err := r.db.Begin()
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var (
		ownerID     int64
		communityID string
		status      string
	)
	if err := tx.QueryRow(
		`SELECT user_id, community_id, status
		   FROM community_subscriptions WHERE id = $1 FOR UPDATE`,
		id,
	).Scan(&ownerID, &communityID, &status); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrCommSubNotFound
		}
		return err
	}
	if ownerID != userID {
		return ErrCommSubNotFound
	}
	if status != "pending" && status != "active" {
		return nil // already cancelled / rejected / expired — no-op
	}
	if _, err := tx.Exec(
		`UPDATE community_subscriptions
		    SET status = 'cancelled', cancelled_at = NOW()
		  WHERE id = $1`, id,
	); err != nil {
		return err
	}
	// Active sub also flushes the membership row so the user loses
	// access immediately. Pending subs never had one.
	if status == "active" {
		if _, err := tx.Exec(
			`DELETE FROM community_members
			  WHERE user_id = $1 AND community_id = $2`,
			userID, communityID,
		); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// PromoteExpired — flips active rows whose expires_at has passed to
// 'expired' AND removes the corresponding community_members rows. One
// transaction per row so a partial run leaves DB consistent. Returns
// the freshly expired (userID, communityID) pairs so the expirer
// service can broadcast realtime events.
func (r *CommunitySubscriptionsRepository) PromoteExpired() ([]CommSubExpiry, error) {
	rows, err := r.db.Query(
		`SELECT id, user_id, community_id FROM community_subscriptions
		  WHERE status = 'active'
		    AND expires_at IS NOT NULL
		    AND expires_at <= NOW()`,
	)
	if err != nil {
		return nil, err
	}
	type pending struct {
		id          int64
		userID      int64
		communityID string
	}
	var batch []pending
	for rows.Next() {
		var p pending
		if err := rows.Scan(&p.id, &p.userID, &p.communityID); err != nil {
			rows.Close()
			return nil, err
		}
		batch = append(batch, p)
	}
	rows.Close()
	out := make([]CommSubExpiry, 0, len(batch))
	for _, p := range batch {
		tx, err := r.db.Begin()
		if err != nil {
			continue
		}
		_, err1 := tx.Exec(
			`UPDATE community_subscriptions
			    SET status = 'expired'
			  WHERE id = $1 AND status = 'active'`, p.id,
		)
		_, err2 := tx.Exec(
			`DELETE FROM community_members
			  WHERE user_id = $1 AND community_id = $2`,
			p.userID, p.communityID,
		)
		if err1 != nil || err2 != nil {
			_ = tx.Rollback()
			continue
		}
		if err := tx.Commit(); err != nil {
			continue
		}
		out = append(out, CommSubExpiry{
			SubscriptionID: p.id,
			UserID:         p.userID,
			CommunityID:    p.communityID,
		})
	}
	return out, nil
}

// CommSubExpiry — small return value from PromoteExpired so the
// expirer goroutine can fan out realtime events per affected user.
type CommSubExpiry struct {
	SubscriptionID int64
	UserID         int64
	CommunityID    string
}

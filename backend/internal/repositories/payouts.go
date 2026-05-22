package repositories

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
)

// PayoutsRepository — owns the payout_requests table (mig 0042).
//
// Two read paths:
//   * Per-expert ListForUser drives the "your past requests" list on
//     the Earnings screen. Includes available-balance accounting.
//   * Admin ListAll drives the Payouts admin queue.
type PayoutsRepository struct {
	db *sql.DB
}

func NewPayoutsRepository(db *sql.DB) *PayoutsRepository {
	return &PayoutsRepository{db: db}
}

type Payout struct {
	ID             int64           `json:"id"`
	UserID         int64           `json:"userId"`
	ExpertID       string          `json:"expertId"`
	AmountCents    int             `json:"amountCents"`
	Currency       string          `json:"currency"`
	Method         string          `json:"method"`
	PaymentDetails json.RawMessage `json:"paymentDetails"`
	Status         string          `json:"status"`
	AdminNote      *string         `json:"adminNote,omitempty"`
	ProcessedAt    *time.Time      `json:"processedAt,omitempty"`
	ProcessedBy    *int64          `json:"processedBy,omitempty"`
	RequestedAt    time.Time       `json:"requestedAt"`
	UpdatedAt      time.Time       `json:"updatedAt"`

	// Joined fields (admin queue only).
	UserEmail     string `json:"userEmail,omitempty"`
	UserName      string `json:"userName,omitempty"`
	ProcessorEmail string `json:"processorEmail,omitempty"`
}

// ErrInsufficientBalance — request amount exceeds (lifetime − already
// requested). Caller maps to a friendly 400.
var ErrInsufficientBalance = errors.New("payouts: amount exceeds available balance")

// ErrPayoutNotFound — request not found, already processed, or for
// another user. Caller maps to 404.
var ErrPayoutNotFound = errors.New("payouts: not found")

// payoutCols — column list with the `p.` alias, used by every SELECT
// path that joins through `payout_requests p`.
const payoutCols = `p.id, p.user_id, p.expert_id, p.amount_cents, p.currency,
	p.method, p.payment_details, p.status, p.admin_note,
	p.processed_at, p.processed_by, p.requested_at, p.updated_at`

// payoutColsBare — same column list without the `p.` alias, used by
// INSERT … RETURNING and UPDATE … RETURNING (no alias in scope).
const payoutColsBare = `id, user_id, expert_id, amount_cents, currency,
	method, payment_details, status, admin_note,
	processed_at, processed_by, requested_at, updated_at`

func scanPayout(row interface{ Scan(dest ...any) error }, withJoined bool) (*Payout, error) {
	var p Payout
	var adminNote sql.NullString
	var processedAt sql.NullTime
	var processedBy sql.NullInt64
	var details []byte
	dests := []any{
		&p.ID, &p.UserID, &p.ExpertID, &p.AmountCents, &p.Currency,
		&p.Method, &details, &p.Status, &adminNote,
		&processedAt, &processedBy, &p.RequestedAt, &p.UpdatedAt,
	}
	var userEmail, userName, processorEmail sql.NullString
	if withJoined {
		dests = append(dests, &userEmail, &userName, &processorEmail)
	}
	if err := row.Scan(dests...); err != nil {
		return nil, err
	}
	if len(details) > 0 {
		p.PaymentDetails = details
	} else {
		p.PaymentDetails = json.RawMessage(`{}`)
	}
	if adminNote.Valid {
		p.AdminNote = &adminNote.String
	}
	if processedAt.Valid {
		p.ProcessedAt = &processedAt.Time
	}
	if processedBy.Valid {
		p.ProcessedBy = &processedBy.Int64
	}
	p.UserEmail = userEmail.String
	p.UserName = userName.String
	p.ProcessorEmail = processorEmail.String
	return &p, nil
}

// Create — requested amount must be ≤ available balance. The balance
// check happens inside a single SQL transaction so two concurrent
// requests can't both pass the check and over-withdraw.
//
// Available balance = lifetime revenue − sum(amount of pending + paid
// requests). Rejected/cancelled requests don't count.
func (r *PayoutsRepository) Create(
	userID int64,
	expertID string,
	amountCents int,
	currency, method string,
	paymentDetails map[string]any,
	lifetimeRevenueCents int,
) (*Payout, error) {
	if amountCents <= 0 {
		return nil, errors.New("payouts: amount must be > 0")
	}
	method = strings.TrimSpace(method)
	if method == "" {
		return nil, errors.New("payouts: method is required")
	}
	if currency == "" {
		currency = "usd"
	}
	if paymentDetails == nil {
		paymentDetails = map[string]any{}
	}
	detailsJSON, err := json.Marshal(paymentDetails)
	if err != nil {
		return nil, fmt.Errorf("payouts: marshal details: %w", err)
	}

	tx, err := r.db.Begin()
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	// Lock the user's existing requests so a parallel insert can't
	// slip past the balance check.
	var alreadyRequested sql.NullInt64
	if err := tx.QueryRow(`
		SELECT COALESCE(SUM(amount_cents), 0) FROM payout_requests
		WHERE user_id = $1 AND status IN ('pending', 'paid')
		FOR UPDATE
	`, userID).Scan(&alreadyRequested); err != nil {
		return nil, err
	}
	available := lifetimeRevenueCents - int(alreadyRequested.Int64)
	if amountCents > available {
		return nil, ErrInsufficientBalance
	}

	row := tx.QueryRow(`
		INSERT INTO payout_requests
		    (user_id, expert_id, amount_cents, currency, method, payment_details)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING `+payoutColsBare,
		userID, expertID, amountCents, strings.ToLower(currency), method, detailsJSON,
	)
	p, err := scanPayout(row, false)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return p, nil
}

// AvailableBalance — lifetime revenue minus already-pending-or-paid
// payout requests. Used by the earnings screen so the user knows what
// they can actually request.
func (r *PayoutsRepository) AvailableBalance(userID int64, lifetimeRevenueCents int) (int, error) {
	var alreadyRequested sql.NullInt64
	err := r.db.QueryRow(`
		SELECT COALESCE(SUM(amount_cents), 0) FROM payout_requests
		WHERE user_id = $1 AND status IN ('pending', 'paid')
	`, userID).Scan(&alreadyRequested)
	if err != nil {
		return 0, err
	}
	avail := lifetimeRevenueCents - int(alreadyRequested.Int64)
	if avail < 0 {
		avail = 0
	}
	return avail, nil
}

// ListForUser — newest first. Drives the expert's earnings-screen
// history.
func (r *PayoutsRepository) ListForUser(userID int64, limit int) ([]Payout, error) {
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	rows, err := r.db.Query(`
		SELECT `+payoutCols+`
		FROM payout_requests p
		WHERE p.user_id = $1
		ORDER BY p.requested_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]Payout, 0)
	for rows.Next() {
		p, err := scanPayout(rows, false)
		if err != nil {
			return nil, err
		}
		out = append(out, *p)
	}
	return out, rows.Err()
}

// CancelMine — the expert cancels their own still-pending request.
// Admin-processed requests are read-only; this only flips 'pending'
// rows and only when the caller owns them.
func (r *PayoutsRepository) CancelMine(id, userID int64) (*Payout, error) {
	row := r.db.QueryRow(`
		UPDATE payout_requests
		SET status = 'cancelled', updated_at = NOW()
		WHERE id = $1 AND user_id = $2 AND status = 'pending'
		RETURNING `+payoutColsBare,
		id, userID,
	)
	p, err := scanPayout(row, false)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrPayoutNotFound
	}
	return p, err
}

// ─── admin paths ────────────────────────────────────────────────────────

type AdminPayoutFilter struct {
	Status string // "" = all, else "pending"|"paid"|"rejected"|"cancelled"
	Limit  int
	Offset int
}

// ListAdmin — joins user details for the admin dashboard table.
func (r *PayoutsRepository) ListAdmin(f AdminPayoutFilter) ([]Payout, int, error) {
	if f.Limit <= 0 || f.Limit > 200 {
		f.Limit = 50
	}
	if f.Offset < 0 {
		f.Offset = 0
	}
	args := []any{}
	conds := []string{}
	if f.Status != "" {
		args = append(args, f.Status)
		conds = append(conds, fmt.Sprintf("p.status = $%d", len(args)))
	}
	where := ""
	if len(conds) > 0 {
		where = "WHERE " + strings.Join(conds, " AND ")
	}

	var total int
	if err := r.db.QueryRow(
		`SELECT COUNT(*) FROM payout_requests p `+where, args...,
	).Scan(&total); err != nil {
		return nil, 0, err
	}

	args = append(args, f.Limit, f.Offset)
	rows, err := r.db.Query(`
		SELECT `+payoutCols+`,
		       u.email, COALESCE(u.name, ''),
		       COALESCE(proc.email, '')
		FROM payout_requests p
		JOIN users u ON u.id = p.user_id
		LEFT JOIN users proc ON proc.id = p.processed_by
		`+where+`
		ORDER BY
		  CASE WHEN p.status = 'pending' THEN 0 ELSE 1 END,
		  p.requested_at DESC
		LIMIT $`+fmt.Sprint(len(args)-1)+` OFFSET $`+fmt.Sprint(len(args)),
		args...,
	)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()
	out := make([]Payout, 0)
	for rows.Next() {
		p, err := scanPayout(rows, true)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, *p)
	}
	return out, total, rows.Err()
}

// CountPending — sidebar badge.
func (r *PayoutsRepository) CountPending() (int, error) {
	var n int
	err := r.db.QueryRow(`SELECT COUNT(*) FROM payout_requests WHERE status = 'pending'`).Scan(&n)
	return n, err
}

// AdminResolve — flip status to a terminal value ('paid' | 'rejected').
// Once flipped, the row is read-only.
func (r *PayoutsRepository) AdminResolve(
	id, adminID int64,
	newStatus, note string,
) (*Payout, error) {
	switch newStatus {
	case "paid", "rejected":
	default:
		return nil, fmt.Errorf("payouts: invalid status %q", newStatus)
	}
	var n any
	if strings.TrimSpace(note) != "" {
		n = strings.TrimSpace(note)
	}
	row := r.db.QueryRow(`
		UPDATE payout_requests
		SET status       = $1,
		    admin_note   = $2,
		    processed_at = NOW(),
		    processed_by = $3,
		    updated_at   = NOW()
		WHERE id = $4
		  AND status = 'pending'
		RETURNING `+payoutColsBare,
		newStatus, n, adminID, id,
	)
	p, err := scanPayout(row, false)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrPayoutNotFound
	}
	return p, err
}

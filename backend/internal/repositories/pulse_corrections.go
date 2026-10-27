package repositories

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"halalstocks/internal/models"
	"halalstocks/internal/pulse"
)

// =============================================================================
// pulse_corrections.go — the two-person correction flow for PUBLISHED items.
//
// Decision (Zaid, 2026-10-22): a correction is never applied by the person who
// wrote it. One staff member PROPOSES it (stored in pulse_pending_corrections,
// migration 0057); a DIFFERENT approver APPLIES or REJECTS it. Until then the
// live item is untouched. At most one proposal per item is open at a time.
//
// Every step is written to the append-only change log: correction_proposed,
// then corrected/updated (applied) or correction_rejected.
// =============================================================================

// validateCorrectionInput checks the kind and note shared by propose/resolve.
func validateCorrectionInput(kind, note string) error {
	if kind != models.PulseChangeUpdated && kind != models.PulseChangeCorrected {
		return &pulse.RuleError{Kind: "invalid", Message: "Choose \"updated\" or \"corrected\"",
			Fields: pulse.FieldErrors{"kind": "Choose updated or corrected"}}
	}
	return pulse.ValidateNote(note, true)
}

// ProposeCorrection files (or replaces, when the same person already has one
// open) a correction for a published item. Another person's open proposal is
// never overwritten: it must be applied or rejected first.
func (r *PulseAdminRepository) ProposeCorrection(
	ctx context.Context, id int64, actor pulse.Actor, kind string,
	in models.PulseItemInput, note string,
) (*models.PulsePendingCorrection, error) {
	if err := validateCorrectionInput(kind, note); err != nil {
		return nil, err
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse correction proposal: %w", err)
	}
	defer tx.Rollback()

	it, err := getPulseAdminItem(ctx, tx, id, true)
	if err != nil {
		return nil, err
	}
	if err := pulse.CheckAction(pulse.DoProposeCorrection, *it, actor); err != nil {
		return nil, err
	}
	// Date, slot and sensitivity cannot change on a live item.
	in.PulseDate, in.Slot, in.IsSensitive = it.PulseDate, it.Slot, it.IsSensitive
	if err := checkCorrectionComplete(*it, in); err != nil {
		return nil, err
	}
	existing, err := loadPendingCorrection(ctx, tx, id, true)
	if err != nil {
		return nil, err
	}
	if existing != nil && (existing.ProposedBy == nil || *existing.ProposedBy != actor.UserID) {
		return nil, &pulse.RuleError{Kind: "state",
			Message: "Another correction is already waiting for approval; apply or reject it first"}
	}
	raw, err := json.Marshal(in)
	if err != nil {
		return nil, fmt.Errorf("encoding pulse correction: %w", err)
	}
	by := actor.UserID
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO pulse_pending_corrections (item_id, proposed_by, kind, note, input)
		 VALUES ($1,$2,$3,$4,$5)
		 ON CONFLICT (item_id) DO UPDATE
		   SET proposed_by = EXCLUDED.proposed_by, kind = EXCLUDED.kind,
		       note = EXCLUDED.note, input = EXCLUDED.input,
		       created_at = NOW(), updated_at = NOW()`,
		id, by, kind, strings.TrimSpace(note), raw); err != nil {
		return nil, fmt.Errorf("storing pulse correction proposal for item %d: %w", id, err)
	}
	if err := logPulseEvent(ctx, tx, id, models.PulseActionCorrectionProposed, &by,
		it.Status, it.Status, note); err != nil {
		return nil, err
	}
	pending, err := loadPendingCorrection(ctx, tx, id, false)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse correction proposal: %w", err)
	}
	return pending, nil
}

// PendingCorrection returns the open proposal for an item, or nil.
func (r *PulseAdminRepository) PendingCorrection(
	ctx context.Context, id int64,
) (*models.PulsePendingCorrection, error) {
	return loadPendingCorrection(ctx, r.db, id, false)
}

// ResolveCorrection applies (approve=true) or rejects the open proposal. The
// actor must hold the approver role and must not be the proposer. Rejecting
// needs a note saying why. It returns the live item (changed when approved)
// and the proposal that was resolved.
func (r *PulseAdminRepository) ResolveCorrection(
	ctx context.Context, id int64, actor pulse.Actor, approve bool, note string,
) (*models.PulseAdminItem, *models.PulsePendingCorrection, error) {
	if err := pulse.ValidateNote(note, !approve); err != nil {
		return nil, nil, err
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, nil, fmt.Errorf("starting pulse correction review: %w", err)
	}
	defer tx.Rollback()

	it, err := getPulseAdminItem(ctx, tx, id, true)
	if err != nil {
		return nil, nil, err
	}
	pending, err := loadPendingCorrection(ctx, tx, id, true)
	if err != nil {
		return nil, nil, err
	}
	if pending == nil {
		return nil, nil, &pulse.RuleError{Kind: "state", Message: "There is no correction waiting for approval"}
	}
	if err := pulse.CheckCorrectionReview(*it, pending.ProposedBy, actor); err != nil {
		return nil, nil, err
	}
	by := actor.UserID
	if _, err := tx.ExecContext(ctx, `DELETE FROM pulse_pending_corrections WHERE item_id = $1`, id); err != nil {
		return nil, nil, fmt.Errorf("closing pulse correction proposal for item %d: %w", id, err)
	}
	if !approve {
		if err := logPulseEvent(ctx, tx, id, models.PulseActionCorrectionRejected, &by,
			it.Status, it.Status, note); err != nil {
			return nil, nil, err
		}
		if err := tx.Commit(); err != nil {
			return nil, nil, fmt.Errorf("committing pulse correction rejection: %w", err)
		}
		return it, pending, nil
	}
	if err := checkCorrectionComplete(*it, pending.Input); err != nil {
		return nil, nil, err
	}
	// The recorded reason is the proposer's; the approver's note is appended.
	reason := pending.Note
	if strings.TrimSpace(note) != "" {
		reason += " — approved: " + strings.TrimSpace(note)
	}
	if err := applyCorrectionTx(ctx, tx, it, actor, pending.Kind, pending.Input, reason); err != nil {
		return nil, nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, nil, fmt.Errorf("committing pulse correction: %w", err)
	}
	live, err := getPulseAdminItem(ctx, r.db, id, false)
	return live, pending, err
}

// checkCorrectionComplete: a live item must stay complete after the change.
func checkCorrectionComplete(it models.PulseAdminItem, in models.PulseItemInput) error {
	candidate := it
	candidate.TitleAr, candidate.TitleEn = in.TitleAr, in.TitleEn
	candidate.SummaryAr, candidate.SummaryEn = in.SummaryAr, in.SummaryEn
	candidate.SourceName, candidate.VerifiedAt = in.SourceName, in.VerifiedAt
	if errs := pulse.CompletenessErrors(candidate); len(errs) > 0 {
		return &pulse.RuleError{Kind: "invalid", Message: "A published item must stay complete", Fields: errs}
	}
	return nil
}

// applyCorrectionTx writes an approved correction: the item stays live, shows
// the "updated"/"corrected" marker, keeps the previous version and logs the
// reason. Date, slot and sensitivity cannot change (that would move the item).
func applyCorrectionTx(
	ctx context.Context, tx pulseQuerier, it *models.PulseAdminItem, actor pulse.Actor,
	kind string, in models.PulseItemInput, reason string,
) error {
	in.PulseDate, in.Slot, in.IsSensitive = it.PulseDate, it.Slot, it.IsSensitive
	snapReason, action := "update", models.PulseActionUpdated
	if kind == models.PulseChangeCorrected {
		snapReason, action = "correction", models.PulseActionCorrected
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE pulse_items SET (`+inputColumns+`) =
		   ($3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18),
		   version = version + 1, change_kind = $2, last_changed_at = NOW()
		 WHERE id = $1`,
		append([]any{it.ID, kind}, inputArgs(in)...)...); err != nil {
		return mapPulseDBError(fmt.Errorf("correcting pulse item %d: %w", it.ID, err))
	}
	by := actor.UserID
	if err := snapshotPulseItem(ctx, tx, it.ID, snapReason, &by); err != nil {
		return err
	}
	return logPulseEvent(ctx, tx, it.ID, action, &by, it.Status, it.Status, reason)
}

// loadPendingCorrection reads the open proposal for an item (nil when none).
func loadPendingCorrection(
	ctx context.Context, q pulseQuerier, id int64, lock bool,
) (*models.PulsePendingCorrection, error) {
	query := `SELECT id, item_id, proposed_by, kind, note, input, created_at
	            FROM pulse_pending_corrections WHERE item_id = $1`
	if lock {
		query += ` FOR UPDATE`
	}
	var (
		pc  models.PulsePendingCorrection
		raw []byte
	)
	err := q.QueryRowContext(ctx, query, id).Scan(
		&pc.ID, &pc.ItemID, &pc.ProposedBy, &pc.Kind, &pc.Note, &raw, &pc.CreatedAt)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("loading pulse correction proposal for item %d: %w", id, err)
	}
	if err := json.Unmarshal(raw, &pc.Input); err != nil {
		return nil, fmt.Errorf("decoding pulse correction proposal for item %d: %w", id, err)
	}
	return &pc, nil
}

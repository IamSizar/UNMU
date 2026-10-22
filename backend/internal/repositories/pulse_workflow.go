package repositories

import (
	"context"
	"fmt"
	"strings"
	"time"

	"halalstocks/internal/models"
	"halalstocks/internal/pulse"
)

// =============================================================================
// pulse_workflow.go — the Pulse status workflow:
//
//	draft ─submit→ in_review ─approve→ approved ─publish→ published ─archive→ archived
//	  ↑               │  └review (stays in_review)    └schedule→ scheduled ─(due)→ published
//	  └────reject─────┘
//
// Every transition runs in one transaction: lock the row, ask internal/pulse
// whether the actor may do this NOW, change the row, append the change-log
// entry. Publishing also archives whatever was published before for the same
// day and slot, so the "one live item per slot" rule is never violated.
// =============================================================================

// PulseApplyOptions carries the optional inputs of a transition.
type PulseApplyOptions struct {
	Note      string     // free text; required for reject
	PublishAt *time.Time // required for schedule
}

// transitionSpec describes the row change of one table-driven workflow action.
// In set, $1 is the item id, $2 the new status and $3 (optional) the actor.
type transitionSpec struct {
	logAction string // models.PulseAction*
	toStatus  string
	set       string // extra SET clause (may be empty)
}

var transitions = map[string]transitionSpec{
	pulse.DoSubmit: {models.PulseActionSubmitted, models.PulseStatusInReview,
		`reviewed_by = NULL, reviewed_at = NULL, approved_by = NULL, approved_at = NULL`},
	pulse.DoReject: {models.PulseActionRejected, models.PulseStatusDraft,
		`reviewed_by = NULL, reviewed_at = NULL, approved_by = NULL, approved_at = NULL`},
	pulse.DoApprove: {models.PulseActionApproved, models.PulseStatusApproved,
		`approved_by = $3, approved_at = NOW()`},
	pulse.DoUnschedule: {models.PulseActionUnscheduled, models.PulseStatusApproved,
		`publish_at = NULL`},
	pulse.DoArchive: {models.PulseActionArchived, models.PulseStatusArchived, ``},
}

// Apply performs one workflow action on an item and returns the new state.
func (r *PulseAdminRepository) Apply(
	ctx context.Context, id int64, actor pulse.Actor, do string, opts PulseApplyOptions,
) (*models.PulseAdminItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse %s: %w", do, err)
	}
	defer tx.Rollback()

	it, err := getPulseAdminItem(ctx, tx, id, true)
	if err != nil {
		return nil, err
	}
	if err := pulse.CheckAction(do, *it, actor); err != nil {
		return nil, err
	}
	if err := pulse.ValidateNote(opts.Note, do == pulse.DoReject); err != nil {
		return nil, err
	}
	by := actor.UserID

	switch do {
	case pulse.DoSubmit:
		if errs := pulse.CompletenessErrors(*it); len(errs) > 0 {
			return nil, &pulse.RuleError{Kind: "invalid", Message: "Complete the missing fields first", Fields: errs}
		}
		err = applySimple(ctx, tx, it, do, &by, opts.Note)
	case pulse.DoApprove:
		if err = pulse.CheckApproval(*it); err == nil {
			err = applySimple(ctx, tx, it, do, &by, opts.Note)
		}
	case pulse.DoReject, pulse.DoUnschedule, pulse.DoArchive:
		err = applySimple(ctx, tx, it, do, &by, opts.Note)
	case pulse.DoReview:
		err = applyReview(ctx, tx, it, &by, opts.Note)
	case pulse.DoSchedule:
		err = applySchedule(ctx, tx, it, &by, opts)
	case pulse.DoPublish:
		err = publishPulseTx(ctx, tx, it, &by, opts.Note)
	default:
		err = &pulse.RuleError{Kind: "invalid", Message: "Unsupported action"}
	}
	if err != nil {
		return nil, mapPulseDBError(err)
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse %s: %w", do, err)
	}
	return getPulseAdminItem(ctx, r.db, id, false)
}

// applySimple runs a table-driven transition (status change + log entry).
func applySimple(
	ctx context.Context, q pulseQuerier, it *models.PulseAdminItem,
	do string, actor *int64, note string,
) error {
	spec := transitions[do]
	set := `status = $2`
	args := []any{it.ID, spec.toStatus}
	if spec.set != "" {
		set += `, ` + spec.set
	}
	// Postgres rejects a parameter the statement never mentions, so $3 (the
	// actor) is only sent for the transitions that use it.
	if strings.Contains(spec.set, "$3") {
		args = append(args, actor)
	}
	if _, err := q.ExecContext(ctx, `UPDATE pulse_items SET `+set+` WHERE id = $1`, args...); err != nil {
		return fmt.Errorf("pulse %s on item %d: %w", do, it.ID, err)
	}
	return logPulseEvent(ctx, q, it.ID, spec.logAction, actor, it.Status, spec.toStatus, note)
}

// applyReview records the reviewer; the item stays in review.
func applyReview(ctx context.Context, q pulseQuerier, it *models.PulseAdminItem, actor *int64, note string) error {
	if _, err := q.ExecContext(ctx,
		`UPDATE pulse_items SET reviewed_by = $2, reviewed_at = NOW() WHERE id = $1`,
		it.ID, actor); err != nil {
		return fmt.Errorf("pulse review on item %d: %w", it.ID, err)
	}
	return logPulseEvent(ctx, q, it.ID, models.PulseActionReviewed, actor, it.Status, it.Status, note)
}

// applySchedule queues an approved item for a future publish time.
func applySchedule(
	ctx context.Context, q pulseQuerier, it *models.PulseAdminItem, actor *int64, opts PulseApplyOptions,
) error {
	if opts.PublishAt == nil {
		return &pulse.RuleError{Kind: "invalid", Message: "Pick a publish time",
			Fields: pulse.FieldErrors{"publishAt": "Required"}}
	}
	if err := pulse.CheckSchedule(*opts.PublishAt, time.Now()); err != nil {
		return err
	}
	if _, err := q.ExecContext(ctx,
		`UPDATE pulse_items SET status = 'scheduled', publish_at = $2 WHERE id = $1`,
		it.ID, *opts.PublishAt); err != nil {
		return fmt.Errorf("scheduling pulse item %d: %w", it.ID, err)
	}
	return logPulseEvent(ctx, q, it.ID, models.PulseActionScheduled, actor, it.Status,
		models.PulseStatusScheduled, opts.Note)
}

// publishPulseTx makes an approved / scheduled item live. Whatever was
// published before for the same day and slot is archived first and noted in
// its change log. actor is nil when the scheduler publishes.
func publishPulseTx(ctx context.Context, q pulseQuerier, it *models.PulseAdminItem, actor *int64, note string) error {
	rows, err := q.QueryContext(ctx,
		`UPDATE pulse_items SET status = 'archived'
		  WHERE pulse_date = $1 AND slot = $2 AND status = 'published' AND id <> $3
		RETURNING id`, it.PulseDate, it.Slot, it.ID)
	if err != nil {
		return fmt.Errorf("archiving replaced pulse item: %w", err)
	}
	var replaced []int64
	for rows.Next() {
		var rid int64
		if err := rows.Scan(&rid); err != nil {
			rows.Close()
			return fmt.Errorf("reading replaced pulse item: %w", err)
		}
		replaced = append(replaced, rid)
	}
	rows.Close()
	for _, rid := range replaced {
		msg := fmt.Sprintf("Replaced by item %d", it.ID)
		if err := logPulseEvent(ctx, q, rid, models.PulseActionArchived, actor,
			models.PulseStatusPublished, models.PulseStatusArchived, msg); err != nil {
			return err
		}
	}
	if _, err := q.ExecContext(ctx,
		`UPDATE pulse_items SET status = 'published', published_at = NOW() WHERE id = $1`, it.ID); err != nil {
		return fmt.Errorf("publishing pulse item %d: %w", it.ID, err)
	}
	return logPulseEvent(ctx, q, it.ID, models.PulseActionPublished, actor, it.Status,
		models.PulseStatusPublished, note)
}

// Correct changes a PUBLISHED item: it stays live, shows the "updated" or
// "corrected" marker, keeps the previous version and logs the reason.
// Date, slot and sensitivity cannot change here (that would move the item).
func (r *PulseAdminRepository) Correct(
	ctx context.Context, id int64, actor pulse.Actor, kind string,
	in models.PulseItemInput, note string,
) (*models.PulseAdminItem, error) {
	if kind != models.PulseChangeUpdated && kind != models.PulseChangeCorrected {
		return nil, &pulse.RuleError{Kind: "invalid", Message: "Choose \"updated\" or \"corrected\"",
			Fields: pulse.FieldErrors{"kind": "Choose updated or corrected"}}
	}
	if err := pulse.ValidateNote(note, true); err != nil {
		return nil, err
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse correction: %w", err)
	}
	defer tx.Rollback()

	it, err := getPulseAdminItem(ctx, tx, id, true)
	if err != nil {
		return nil, err
	}
	if err := pulse.CheckAction(pulse.DoCorrect, *it, actor); err != nil {
		return nil, err
	}
	in.PulseDate, in.Slot, in.IsSensitive = it.PulseDate, it.Slot, it.IsSensitive

	// The corrected item is live, so it must still be complete.
	candidate := *it
	candidate.TitleAr, candidate.TitleEn = in.TitleAr, in.TitleEn
	candidate.SummaryAr, candidate.SummaryEn = in.SummaryAr, in.SummaryEn
	candidate.SourceName, candidate.VerifiedAt = in.SourceName, in.VerifiedAt
	if errs := pulse.CompletenessErrors(candidate); len(errs) > 0 {
		return nil, &pulse.RuleError{Kind: "invalid", Message: "A published item must stay complete", Fields: errs}
	}

	reason, action := "update", models.PulseActionUpdated
	if kind == models.PulseChangeCorrected {
		reason, action = "correction", models.PulseActionCorrected
	}
	_, err = tx.ExecContext(ctx,
		`UPDATE pulse_items SET (`+inputColumns+`) =
		   ($3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18),
		   version = version + 1, change_kind = $2, last_changed_at = NOW()
		 WHERE id = $1`,
		append([]any{id, kind}, inputArgs(in)...)...)
	if err != nil {
		return nil, mapPulseDBError(fmt.Errorf("correcting pulse item %d: %w", id, err))
	}
	by := actor.UserID
	if err := snapshotPulseItem(ctx, tx, id, reason, &by); err != nil {
		return nil, err
	}
	if err := logPulseEvent(ctx, tx, id, action, &by, it.Status, it.Status, note); err != nil {
		return nil, err
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse correction: %w", err)
	}
	return getPulseAdminItem(ctx, r.db, id, false)
}

// PromoteDue publishes every scheduled item whose time has come. It is called
// by the background scheduler. FOR UPDATE SKIP LOCKED means two server
// instances can run it at once without publishing the same item twice.
// It returns the items that went live (for notifications).
func (r *PulseAdminRepository) PromoteDue(ctx context.Context, now time.Time) ([]models.PulseAdminItem, error) {
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("starting pulse promote: %w", err)
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx,
		`SELECT id FROM pulse_items
		  WHERE status = 'scheduled' AND publish_at <= $1
		  ORDER BY publish_at FOR UPDATE SKIP LOCKED`, now)
	if err != nil {
		return nil, fmt.Errorf("finding due pulse items: %w", err)
	}
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return nil, fmt.Errorf("reading due pulse item: %w", err)
		}
		ids = append(ids, id)
	}
	rows.Close()

	for _, id := range ids {
		it, err := getPulseAdminItem(ctx, tx, id, false)
		if err != nil {
			return nil, err
		}
		if err := publishPulseTx(ctx, tx, it, nil, "Published on schedule"); err != nil {
			return nil, mapPulseDBError(err)
		}
	}
	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("committing pulse promote: %w", err)
	}
	promoted := make([]models.PulseAdminItem, 0, len(ids))
	for _, id := range ids {
		if it, err := getPulseAdminItem(ctx, r.db, id, false); err == nil {
			promoted = append(promoted, *it)
		}
	}
	return promoted, nil
}

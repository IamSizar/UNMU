package repositories

import (
	"context"
	"fmt"
)

// =============================================================================
// pulse_recipients.go — who should receive a Pulse push notification.
//
// Only users with a registered device are returned. Missing preference rows
// count as "everything on" (the column defaults in migration 0056). The query
// pre-filters by the master switches so we do not load thousands of users just
// for the Notifier to throw them away; the Notifier checks the exact per-event
// switch again before sending (single source of truth for the rules is
// services.categoryEnabled).
// =============================================================================

const pulseRecipientBase = `
SELECT DISTINCT t.user_id
  FROM user_push_tokens t
  JOIN users u ON u.id = t.user_id AND u.deleted_at IS NULL
  LEFT JOIN user_notification_prefs p ON p.user_id = t.user_id`

func (r *PulseAdminRepository) recipientIDs(ctx context.Context, query string, args ...any) ([]int64, error) {
	rows, err := r.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("loading pulse recipients: %w", err)
	}
	defer rows.Close()
	var ids []int64
	for rows.Next() {
		var id int64
		if err := rows.Scan(&id); err != nil {
			return nil, fmt.Errorf("reading pulse recipient: %w", err)
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// NewItemRecipients returns every user who wants "new Pulse" notifications.
func (r *PulseAdminRepository) NewItemRecipients(ctx context.Context) ([]int64, error) {
	return r.recipientIDs(ctx, pulseRecipientBase+`
 WHERE COALESCE(p.push_enabled, TRUE)
   AND COALESCE(p.pulse_enabled, TRUE)
   AND COALESCE(p.pulse_new_enabled, TRUE)`)
}

// SaverRecipients returns the users who saved the item and still want
// notifications about changes to saved items.
func (r *PulseAdminRepository) SaverRecipients(ctx context.Context, itemID int64) ([]int64, error) {
	return r.recipientIDs(ctx, pulseRecipientBase+`
  JOIN pulse_saves s ON s.user_id = t.user_id AND s.item_id = $1
 WHERE COALESCE(p.push_enabled, TRUE)
   AND COALESCE(p.pulse_enabled, TRUE)
   AND COALESCE(p.pulse_saved_enabled, TRUE)`, itemID)
}

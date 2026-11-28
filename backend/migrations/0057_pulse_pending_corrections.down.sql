-- 0057_pulse_pending_corrections.down.sql — reverses 0057.
-- Drops any open correction proposals. Change-log rows already written with the
-- two new actions must be removed first or the old CHECK cannot be restored.
BEGIN;

ALTER TABLE pulse_items DROP CONSTRAINT IF EXISTS pulse_items_approver_not_reviewer;
DELETE FROM pulse_item_events WHERE action IN ('correction_proposed', 'correction_rejected');
ALTER TABLE pulse_item_events DROP CONSTRAINT IF EXISTS pulse_item_events_action_check;
ALTER TABLE pulse_item_events ADD CONSTRAINT pulse_item_events_action_check
    CHECK (action IN ('created', 'edited', 'submitted', 'reviewed',
                      'rejected', 'approved', 'scheduled',
                      'published', 'updated', 'corrected', 'unscheduled',
                      'archived'));
DROP TABLE IF EXISTS pulse_pending_corrections;

COMMIT;

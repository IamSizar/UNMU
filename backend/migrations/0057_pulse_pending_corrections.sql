-- 0057_pulse_pending_corrections.sql — four-eyes for Pulse (Zaid, 2026-10-22).
--
-- 1. A correction to a PUBLISHED item is no longer applied by one person. One
--    staff member proposes it (this table), a DIFFERENT approver applies or
--    rejects it. At most one proposal per item is open at a time.
-- 2. A sensitive item's approver must differ from its reviewer (database-level
--    backstop for the rule the API already checks). NOT VALID: rows approved
--    before this migration are not re-checked, every new row is.
-- Also widens the change-log action list with the two new events.
BEGIN;

CREATE TABLE IF NOT EXISTS pulse_pending_corrections (
    id           BIGSERIAL   PRIMARY KEY,
    item_id      BIGINT      NOT NULL REFERENCES pulse_items(id) ON DELETE CASCADE,
    proposed_by  BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    kind         TEXT        NOT NULL CHECK (kind IN ('updated', 'corrected')),
    note         TEXT        NOT NULL CHECK (length(btrim(note)) > 0),
    input        JSONB       NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- One open proposal per item; also serves the lookup by item.
CREATE UNIQUE INDEX IF NOT EXISTS uq_pulse_pending_corrections_item
    ON pulse_pending_corrections (item_id);
-- FK index for the ON DELETE SET NULL on proposed_by.
CREATE INDEX IF NOT EXISTS idx_pulse_pending_corrections_proposer
    ON pulse_pending_corrections (proposed_by);

ALTER TABLE pulse_item_events DROP CONSTRAINT IF EXISTS pulse_item_events_action_check;
ALTER TABLE pulse_item_events ADD CONSTRAINT pulse_item_events_action_check
    CHECK (action IN ('created', 'edited', 'submitted', 'reviewed',
                      'rejected', 'approved', 'scheduled',
                      'published', 'updated', 'corrected', 'unscheduled',
                      'archived', 'correction_proposed', 'correction_rejected'));

ALTER TABLE pulse_items DROP CONSTRAINT IF EXISTS pulse_items_approver_not_reviewer;
ALTER TABLE pulse_items ADD CONSTRAINT pulse_items_approver_not_reviewer
    CHECK (NOT is_sensitive OR reviewed_by IS NULL OR approved_by IS NULL
           OR approved_by <> reviewed_by) NOT VALID;

COMMIT;

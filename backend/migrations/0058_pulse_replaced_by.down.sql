-- Reverts 0058_pulse_replaced_by.sql. The change-log notes it was backfilled
-- from are untouched, so nothing is lost.
BEGIN;
ALTER TABLE pulse_items DROP CONSTRAINT IF EXISTS pulse_items_replaced_only_archived;
DROP INDEX IF EXISTS idx_pulse_items_replaced_by;
ALTER TABLE pulse_items DROP COLUMN IF EXISTS replaced_by;
COMMIT;

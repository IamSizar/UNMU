-- 0056_pulse.down.sql — reverses 0056_pulse.sql.
-- WARNING: drops every Pulse item, version, change-log row, save and analytics
-- event. Take a backup first if any of it matters.
BEGIN;

ALTER TABLE user_notification_prefs
    DROP COLUMN IF EXISTS pulse_saved_enabled,
    DROP COLUMN IF EXISTS pulse_corrections_enabled,
    DROP COLUMN IF EXISTS pulse_updates_enabled,
    DROP COLUMN IF EXISTS pulse_new_enabled,
    DROP COLUMN IF EXISTS pulse_enabled;

DROP TABLE IF EXISTS pulse_events;
DROP TABLE IF EXISTS pulse_saves;
DROP TABLE IF EXISTS pulse_item_events;
DROP TABLE IF EXISTS pulse_item_versions;
DROP TABLE IF EXISTS pulse_items;
DROP TABLE IF EXISTS pulse_staff;

DROP FUNCTION IF EXISTS pulse_item_events_no_update();
DROP FUNCTION IF EXISTS pulse_touch_updated_at();

COMMIT;

-- 0058_pulse_replaced_by.sql — record Pulse replacements as a link.
--
-- Publishing an item archives the one it replaces in the same day + slot.
-- Readers who saved the replaced item keep it in Saved (OPOS 137988). That
-- used to be decided by matching the change-log NOTE text, which an approver
-- can type by hand (review of PR #5). Now the old item points at the item
-- that replaced it. Taking a replaced item down clears the link, which hides
-- it from Saved.
BEGIN;

ALTER TABLE pulse_items
    ADD COLUMN IF NOT EXISTS replaced_by BIGINT REFERENCES pulse_items(id) ON DELETE SET NULL;

-- FK index (ON DELETE SET NULL lookups); partial: almost every row is NULL.
CREATE INDEX IF NOT EXISTS idx_pulse_items_replaced_by
    ON pulse_items (replaced_by) WHERE replaced_by IS NOT NULL;

-- Backfill from the change log written by the publish step before this
-- migration ("Replaced by item <id>"). Only archived items, only when the
-- replacing item still exists.
UPDATE pulse_items i
   SET replaced_by = r.by_id
  FROM (SELECT DISTINCT ON (e.item_id)
               e.item_id,
               substring(e.note FROM '^Replaced by item ([0-9]+)$')::bigint AS by_id
          FROM pulse_item_events e
         WHERE e.action = 'archived'
         ORDER BY e.item_id, e.created_at DESC, e.id DESC) r
 WHERE i.id = r.item_id
   AND i.status = 'archived'
   AND i.replaced_by IS NULL
   AND r.by_id IS NOT NULL
   AND EXISTS (SELECT 1 FROM pulse_items x WHERE x.id = r.by_id);

-- Only an archived item can be "replaced".
ALTER TABLE pulse_items DROP CONSTRAINT IF EXISTS pulse_items_replaced_only_archived;
ALTER TABLE pulse_items ADD CONSTRAINT pulse_items_replaced_only_archived
    CHECK (replaced_by IS NULL OR status = 'archived');

COMMIT;

-- 0049 down
ALTER TABLE scheduled_pushes
    DROP COLUMN IF EXISTS repeat_kind,
    DROP COLUMN IF EXISTS repeat_days,
    DROP COLUMN IF EXISTS repeat_count;

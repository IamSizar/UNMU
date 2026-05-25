-- 0049_scheduled_push_repeat.sql
--
-- Adds recurrence to admin scheduled pushes (mig 0048). A recurring push
-- stays in status='pending': when the sender fires it, instead of marking it
-- 'sent' it records the result, bumps repeat_count, and re-arms send_at to
-- the next occurrence. Cancelling (status='cancelled') stops the loop.
--
--   repeat_kind : 'none' | 'minutely' | 'hourly' | 'daily' | 'weekly' | 'monthly'
--   repeat_days : weekdays for 'weekly' (0=Sunday … 6=Saturday); NULL otherwise
--   repeat_count: how many times this rule has fired so far
ALTER TABLE scheduled_pushes
    ADD COLUMN IF NOT EXISTS repeat_kind  TEXT      NOT NULL DEFAULT 'none',
    ADD COLUMN IF NOT EXISTS repeat_days  INTEGER[],
    ADD COLUMN IF NOT EXISTS repeat_count INTEGER   NOT NULL DEFAULT 0;

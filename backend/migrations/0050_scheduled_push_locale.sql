-- 0050_scheduled_push_locale.sql
--
-- Bilingual admin push. The admin writes both an English and an Arabic copy
-- once; delivery is split by each recipient's chosen language (users.locale)
-- so everyone gets the notification in their own language automatically.
--
-- title/body remain the default (English) copy. title_ar/body_ar hold the
-- Arabic copy; NULL/empty means Arabic users fall back to the English copy.
ALTER TABLE scheduled_pushes
    ADD COLUMN IF NOT EXISTS title_ar TEXT,
    ADD COLUMN IF NOT EXISTS body_ar  TEXT;

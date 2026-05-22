-- Per-user UI language, synced from the app's language toggle
-- (LanguageController). Lets the backend render notification push
-- titles/bodies in the recipient's chosen language instead of
-- English-only. 'en' default keeps every existing row valid; the
-- client overwrites it via PATCH /me/locale.
--
-- Only 'en' / 'ar' are produced today, but the column is a free TEXT
-- so adding a third language later needs no migration.
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS locale TEXT NOT NULL DEFAULT 'en';

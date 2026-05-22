-- Adds an edited_at marker so the UI can show "(edited)" next to a
-- comment whose body has changed since posting. NULL means never edited.
ALTER TABLE post_comments
    ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ;

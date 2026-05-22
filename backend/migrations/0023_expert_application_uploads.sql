-- =============================================================================
-- 0023 — Expert applications: resume + avatar attachments.
--
-- Step A6 of the Become-Expert audit. Lets a user submit a single PDF
-- (resume / credentials packet) and a single avatar image with their
-- application so admin reviews against documents instead of just text.
--
-- Both columns are NULLABLE for backward compatibility — the existing
-- handler keeps working for clients that don't yet send these fields.
-- =============================================================================

ALTER TABLE expert_applications
    ADD COLUMN IF NOT EXISTS resume_url TEXT,
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;

-- No index needed — these columns are read on the per-row detail page
-- and never used in WHERE/ORDER BY.

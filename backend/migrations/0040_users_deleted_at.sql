-- Soft-delete + anonymization timestamp on users.
--
-- Apple + Google both require the app to let a user delete their
-- account. Hard-deleting the row would cascade-delete every post,
-- comment, community message etc. and leave orphan references all
-- over the place. Soft delete with anonymization:
--
--   * deleted_at IS NOT NULL → user is deactivated, can't log in
--   * the row is renamed to `deleted_<id>@deleted.local` so the
--     original email is freed for re-registration
--   * password_hash is replaced with a sentinel so any leaked
--     pre-deletion hash can't be used against the new tombstone row
--   * authored content (posts, comments) keeps its FK link but
--     shows "Deleted User" in the UI
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_users_deleted_at
    ON users (deleted_at);

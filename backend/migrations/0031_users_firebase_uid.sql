-- Migration 0031 — Firebase Auth integration.
--
-- Adds the firebase_uid column to users. When a user signs in with
-- Google or Apple, the mobile app receives a Firebase ID token whose
-- `sub` claim is the Firebase UID (a 28-char string like "a1b2c3..."').
--
-- The backend's new POST /api/auth/oauth/firebase endpoint verifies that
-- token with the Firebase Admin SDK, then either:
--   * finds the existing user row by firebase_uid (returning user)
--   * or by email (existing email/password user adopting Firebase) and
--     stamps their firebase_uid for next time
--   * or auto-creates a new user row (first-time Firebase signup)
--
-- The column is nullable because every existing user pre-dates Firebase
-- and may never link an OAuth identity. Once a user does link, the
-- UNIQUE index prevents the same Firebase identity from being claimed
-- by two of our rows.

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS firebase_uid TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS users_firebase_uid_unique
    ON users (firebase_uid)
    WHERE firebase_uid IS NOT NULL;

-- Comment for future maintainers reading psql \d users.
COMMENT ON COLUMN users.firebase_uid IS
    'Firebase Auth UID — populated when a user signs in via Google or Apple. NULL for email/password-only accounts.';

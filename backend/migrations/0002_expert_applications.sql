-- =============================================================================
-- Step 1 — Expert applications.
--
-- Adds:
--   * `ADMIN` to the allowed values of users.role
--   * `expert_applications` table — pending requests to become an expert
--   * 1 admin seed account: admin@test.com (password: test)
--
-- Run with:
--   psql "$DATABASE_URL" -f backend/migrations/0002_expert_applications.sql
--
-- Idempotent. Safe to re-run.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Allow `ADMIN` as a role value (in addition to USER / EXPERT / SCHOLAR).
-- -----------------------------------------------------------------------------
ALTER TABLE users
    DROP CONSTRAINT IF EXISTS users_role_check;
ALTER TABLE users
    ADD  CONSTRAINT users_role_check
         CHECK (role IN ('USER','EXPERT','SCHOLAR','ADMIN'));

-- -----------------------------------------------------------------------------
-- 2. expert_applications — a row per submitted request.
--
--    A user may have many historical applications (after a rejection they can
--    re-apply) but at most ONE in `pending` status — enforced by a partial
--    unique index below.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expert_applications (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    full_name         TEXT NOT NULL,
    expertise         TEXT NOT NULL,
    bio               TEXT NOT NULL,
    credentials       JSONB NOT NULL DEFAULT '[]'::jsonb,
    country           TEXT,
    sample_links      JSONB NOT NULL DEFAULT '[]'::jsonb,
    status            TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','approved','rejected')),
    rejection_reason  TEXT,
    submitted_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    reviewed_at       TIMESTAMPTZ,
    reviewed_by       BIGINT REFERENCES users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS expert_applications_user_idx
    ON expert_applications(user_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS expert_applications_status_idx
    ON expert_applications(status, submitted_at DESC);

-- Only one pending application per user at a time.
CREATE UNIQUE INDEX IF NOT EXISTS expert_applications_one_pending_per_user
    ON expert_applications(user_id) WHERE status = 'pending';

-- -----------------------------------------------------------------------------
-- 3. Seed an admin account so the dashboard has someone to log in as.
--    Password is the literal string 'test' (same bcrypt hash as other seeds).
-- -----------------------------------------------------------------------------
INSERT INTO users (id, email, password_hash, name, role, expert_id, subscription_tier, subscription_status, created_at, updated_at)
VALUES
    (1000, 'admin@test.com',
           '$2a$10$9dJhcPWISOsu2asiIlf9N.7/gdoWl8i136OD2DC53G7Lpt393VTH2',
           'Platform Admin', 'ADMIN', NULL, 'PREMIUM', 'ACTIVE', NOW(), NOW())
ON CONFLICT (id) DO NOTHING;

SELECT setval(pg_get_serial_sequence('users','id'),
              GREATEST((SELECT MAX(id) FROM users), 2000));

COMMIT;

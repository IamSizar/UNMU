-- =============================================================================
-- 0022 — Paid community memberships (admin-approved cash / FIB)
--
-- Adds pricing fields to `communities` so an owner can charge for
-- access, and creates `community_subscriptions` to track the
-- pay → admin-review → active → expire lifecycle.
--
-- Mirrors the expert_subscriptions design (see mig 0007) so the
-- pattern stays consistent across the platform: user submits a
-- payment proof, admin verifies it offline (cash drop / FIB
-- transfer), admin clicks Accept which inserts a community_members
-- row in the same transaction.
-- =============================================================================

-- ── 1. Pricing on communities ──────────────────────────────────────
-- Both prices in *cents*. Defaults of 0 mean "free" (the existing
-- behaviour). is_paid is computed at read time as
-- (monthly_cents > 0 OR yearly_cents > 0) — no extra column.
ALTER TABLE communities
    ADD COLUMN IF NOT EXISTS join_price_monthly_cents INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS join_price_yearly_cents  INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS price_currency           TEXT    NOT NULL DEFAULT 'usd';

-- Sanity guard: keep prices non-negative. Done in a DO block so
-- re-running the migration doesn't fail when the constraint already
-- exists.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint WHERE conname = 'communities_prices_nonneg'
    ) THEN
        ALTER TABLE communities ADD CONSTRAINT communities_prices_nonneg
            CHECK (join_price_monthly_cents >= 0 AND join_price_yearly_cents >= 0);
    END IF;
END$$;

-- ── 2. community_subscriptions ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS community_subscriptions (
    id              BIGSERIAL PRIMARY KEY,
    user_id         BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    community_id    TEXT   NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    plan            TEXT   NOT NULL CHECK (plan IN ('monthly','yearly')),
    status          TEXT   NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','active','rejected','cancelled','expired')),
    price_cents     INTEGER NOT NULL,
    currency        TEXT    NOT NULL DEFAULT 'usd',
    payment_method  TEXT    NOT NULL CHECK (payment_method IN ('cash','fib')),
    payment_ref     TEXT,
    user_note       TEXT,
    rejection_reason TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at     TIMESTAMPTZ,
    accepted_by     BIGINT REFERENCES users(id) ON DELETE SET NULL,
    rejected_at     TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ,
    expires_at      TIMESTAMPTZ
);

-- Read paths — admin queue + user's own list + the expirer tick.
CREATE INDEX IF NOT EXISTS idx_comm_subs_user
    ON community_subscriptions (user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comm_subs_community
    ON community_subscriptions (community_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comm_subs_status_created
    ON community_subscriptions (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_comm_subs_expiring
    ON community_subscriptions (expires_at)
    WHERE status = 'active' AND expires_at IS NOT NULL;

-- Block double-pending and double-active per (user, community) — the
-- partial unique indexes match the expert_subscriptions defence.
CREATE UNIQUE INDEX IF NOT EXISTS comm_subs_one_pending_per_pair
    ON community_subscriptions (user_id, community_id) WHERE status = 'pending';
CREATE UNIQUE INDEX IF NOT EXISTS comm_subs_one_active_per_pair
    ON community_subscriptions (user_id, community_id) WHERE status = 'active';

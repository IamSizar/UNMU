-- =============================================================================
-- Step 4 — Expert subscriptions with manual admin acceptance.
--
-- Lifecycle:
--   pending  ─(admin accept)→ active  ─(expires)→ expired
--                          └─(admin reject)→ rejected
--                          └─(user cancel)→ cancelled
--
-- Plans:           monthly ($10) | yearly ($96, ~20% off)
-- Payment methods: cash | fib (First Iraqi Bank)
--
-- Run with:
--   psql "$DATABASE_URL" -f backend/migrations/0007_expert_subscriptions.sql
--
-- Idempotent. Safe to re-run.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. expert_subscriptions — one row per (user, expert, attempt). A user can
--    have many historical rows but at most ONE pending and ONE active per
--    expert at a time (enforced by partial unique indexes below).
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expert_subscriptions (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT      NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
    expert_id         TEXT        NOT NULL REFERENCES experts(id) ON DELETE CASCADE,
    plan              TEXT        NOT NULL
                          CHECK (plan IN ('monthly','yearly')),
    status            TEXT        NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','active','rejected','cancelled','expired')),
    price_cents       INTEGER     NOT NULL,        -- 1000 = $10.00
    currency          TEXT        NOT NULL DEFAULT 'USD',
    payment_method    TEXT        NOT NULL
                          CHECK (payment_method IN ('cash','fib')),
    payment_ref       TEXT,                        -- FIB tx id, cash receipt #, ...
    user_note         TEXT,                        -- optional message from user
    rejection_reason  TEXT,                        -- set when status='rejected'
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    accepted_at       TIMESTAMPTZ,
    accepted_by       BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    rejected_at       TIMESTAMPTZ,
    cancelled_at      TIMESTAMPTZ,
    expires_at        TIMESTAMPTZ                  -- accepted_at + 30 / 365 days
);

CREATE INDEX IF NOT EXISTS expert_subs_user_idx
    ON expert_subscriptions(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS expert_subs_expert_idx
    ON expert_subscriptions(expert_id, status);
CREATE INDEX IF NOT EXISTS expert_subs_status_idx
    ON expert_subscriptions(status, created_at DESC);
CREATE INDEX IF NOT EXISTS expert_subs_active_lookup_idx
    ON expert_subscriptions(user_id, expert_id, status, expires_at);

-- One pending row per (user, expert) — user can't double-submit while
-- waiting for admin verification.
CREATE UNIQUE INDEX IF NOT EXISTS expert_subs_one_pending_per_pair
    ON expert_subscriptions(user_id, expert_id) WHERE status = 'pending';

-- One active row per (user, expert) — extra defence against double-paying.
CREATE UNIQUE INDEX IF NOT EXISTS expert_subs_one_active_per_pair
    ON expert_subscriptions(user_id, expert_id) WHERE status = 'active';

-- -----------------------------------------------------------------------------
-- 2. NOTIFY trigger — every state change broadcasts on `subscription_events`
--    so the realtime listener can fan it out to user + admin clients.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_subscription_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
    ev_type TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        ev_type := 'submitted';
    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.status IS DISTINCT FROM NEW.status THEN
            ev_type := NEW.status;  -- 'active' | 'rejected' | 'cancelled' | 'expired'
        ELSE
            RETURN NEW;
        END IF;
    ELSE
        RETURN NEW;
    END IF;

    payload := json_build_object(
        'type',           ev_type,
        'subscriptionId', NEW.id,
        'userId',         NEW.user_id,
        'expertId',       NEW.expert_id,
        'plan',           NEW.plan,
        'status',         NEW.status,
        'priceCents',     NEW.price_cents,
        'paymentMethod',  NEW.payment_method,
        'paymentRef',     NEW.payment_ref,
        'expiresAt',      NEW.expires_at
    );
    PERFORM pg_notify('subscription_events', payload::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS expert_subs_notify ON expert_subscriptions;
CREATE TRIGGER expert_subs_notify
    AFTER INSERT OR UPDATE ON expert_subscriptions
    FOR EACH ROW EXECUTE FUNCTION notify_subscription_event();

-- -----------------------------------------------------------------------------
-- 3. Audit log integration — every status change writes a row in audit_logs
--    so the admin dashboard's audit feed picks it up automatically.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION audit_subscription_change() RETURNS TRIGGER AS $$
DECLARE
    actor BIGINT;
    sev   TEXT;
    msg   TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        actor := NEW.user_id;
        sev   := 'info';
        msg   := 'New subscription request — ' || NEW.plan || ' ($' ||
                 (NEW.price_cents / 100.0)::TEXT || ', ' || NEW.payment_method || ')';
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        actor := COALESCE(NEW.accepted_by, NEW.user_id);
        CASE NEW.status
            WHEN 'active'    THEN sev := 'success'; msg := 'Subscription accepted (' || NEW.plan || ')';
            WHEN 'rejected'  THEN sev := 'warning'; msg := 'Subscription rejected';
            WHEN 'cancelled' THEN sev := 'info';    msg := 'Subscription cancelled';
            WHEN 'expired'   THEN sev := 'info';    msg := 'Subscription expired';
            ELSE                  RETURN NEW;
        END CASE;
    ELSE
        RETURN NEW;
    END IF;

    PERFORM write_audit(
        'SUBSCRIPTION_CHANGED', sev,
        actor, NEW.id::TEXT, 'subscription',
        msg,
        json_build_object(
            'subscriptionId', NEW.id,
            'userId',         NEW.user_id,
            'expertId',       NEW.expert_id,
            'plan',           NEW.plan,
            'status',         NEW.status,
            'paymentMethod',  NEW.payment_method
        )::jsonb
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS expert_subs_audit ON expert_subscriptions;
CREATE TRIGGER expert_subs_audit
    AFTER INSERT OR UPDATE ON expert_subscriptions
    FOR EACH ROW EXECUTE FUNCTION audit_subscription_change();

COMMIT;

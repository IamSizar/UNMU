-- =============================================================================
-- 0025 — paid community subscriptions: audit + realtime + receipt image
--
-- Step C of the Subscriptions audit:
--   * C1 — write `COMMUNITY_SUB_CHANGED` audit rows on every state change so
--          the AuditLog dashboard surfaces this flow (it was completely
--          invisible before).
--   * C2 — pg_notify trigger on `community_subscription_events`. Listener
--          and repo writes pair so multi-replica deploys still see events.
--   * B10 / C9 mirror — `receipt_url` for cash-receipt image uploads.
-- =============================================================================

-- 1. Receipt image URL (mirrors expert_subscriptions.receipt_url, mig 0024).
ALTER TABLE community_subscriptions
    ADD COLUMN IF NOT EXISTS receipt_url TEXT;

-- 2. NOTIFY trigger — fires on insert + every status change. Listener
--    parses the JSON payload and fans out to user + admin + community
--    channels so the front-end updates without polling.
CREATE OR REPLACE FUNCTION notify_community_subscription_event() RETURNS TRIGGER AS $$
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
        'communityId',    NEW.community_id,
        'plan',           NEW.plan,
        'status',         NEW.status,
        'priceCents',     NEW.price_cents,
        'currency',       NEW.currency,
        'paymentMethod',  NEW.payment_method,
        'paymentRef',     NEW.payment_ref,
        'expiresAt',      NEW.expires_at
    );
    PERFORM pg_notify('community_subscription_events', payload::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS comm_subs_notify ON community_subscriptions;
CREATE TRIGGER comm_subs_notify
    AFTER INSERT OR UPDATE ON community_subscriptions
    FOR EACH ROW EXECUTE FUNCTION notify_community_subscription_event();

-- 3. Audit log integration — every status change writes a row in audit_logs
--    so the admin AuditLog feed picks it up automatically. Same shape as
--    audit_subscription_change (mig 0007:113-152) so the AuditLog UI's
--    type-filter chips can render `COMMUNITY_SUB_CHANGED` consistently.
CREATE OR REPLACE FUNCTION audit_community_subscription_change() RETURNS TRIGGER AS $$
DECLARE
    actor BIGINT;
    sev   TEXT;
    msg   TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        actor := NEW.user_id;
        sev   := 'info';
        msg   := 'New community subscription request — ' || NEW.plan ||
                 ' (' || (NEW.price_cents / 100.0)::TEXT || ' ' ||
                 NEW.currency || ', ' || NEW.payment_method || ')';
    ELSIF TG_OP = 'UPDATE' AND OLD.status IS DISTINCT FROM NEW.status THEN
        actor := COALESCE(NEW.accepted_by, NEW.user_id);
        CASE NEW.status
            WHEN 'active'    THEN sev := 'success'; msg := 'Community subscription accepted (' || NEW.plan || ')';
            WHEN 'rejected'  THEN sev := 'warning'; msg := 'Community subscription rejected';
            WHEN 'cancelled' THEN sev := 'info';    msg := 'Community subscription cancelled';
            WHEN 'expired'   THEN sev := 'info';    msg := 'Community subscription expired';
            ELSE                  RETURN NEW;
        END CASE;
    ELSE
        RETURN NEW;
    END IF;

    PERFORM write_audit(
        'COMMUNITY_SUB_CHANGED', sev,
        actor, NEW.id::TEXT, 'community_subscription',
        msg,
        json_build_object(
            'subscriptionId', NEW.id,
            'userId',         NEW.user_id,
            'communityId',    NEW.community_id,
            'plan',           NEW.plan,
            'status',         NEW.status,
            'priceCents',     NEW.price_cents,
            'currency',       NEW.currency,
            'paymentMethod',  NEW.payment_method
        )::jsonb
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS comm_subs_audit ON community_subscriptions;
CREATE TRIGGER comm_subs_audit
    AFTER INSERT OR UPDATE ON community_subscriptions
    FOR EACH ROW EXECUTE FUNCTION audit_community_subscription_change();

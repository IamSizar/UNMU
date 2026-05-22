-- Migration 0032 — Community co-owners + invitation handshake.
--
-- Lets the primary owner of a community invite other EXPERT users to
-- join the community with publish/moderate rights. The invitee gets a
-- pending invitation; if they accept, a row is added to
-- community_owners and they gain the same rights as the primary owner
-- (publish posts, edit metadata, pin messages, remove members).
--
-- Design:
--   * communities.owner_id stays as the PRIMARY owner — the original
--     creator. It's never null and never moves to the new table. Only
--     the primary owner can invite or remove co-owners or transfer
--     ownership of the community.
--   * community_owners contains CO-OWNERS only (additional owners
--     beyond the primary). The primary owner is NOT duplicated here —
--     application code unions both sources when answering "is this
--     user any kind of owner?"
--   * community_invitations is the handshake state. An invitation is
--     created in `pending` state, becomes `accepted` (then a row is
--     written to community_owners atomically) or `rejected` /
--     `cancelled` / `expired`.
--
-- Authorisation effect:
--   * requireCommunityOwnerOrAdmin (handlers/social.go) is updated to
--     also accept callers found in community_owners.
--   * NotifyEvent triggers on community_owners + community_invitations
--     so the mobile + admin clients can react in real time.

-- ── community_owners ───────────────────────────────────────────────
-- The set of co-owners per community. Primary owner is implicit via
-- communities.owner_id and is NOT stored here.
CREATE TABLE IF NOT EXISTS community_owners (
    community_id TEXT       NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    user_id      BIGINT     NOT NULL REFERENCES users(id)       ON DELETE CASCADE,
    granted_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    granted_by   BIGINT     REFERENCES users(id) ON DELETE SET NULL,
    PRIMARY KEY (community_id, user_id)
);

CREATE INDEX IF NOT EXISTS community_owners_user_idx
    ON community_owners (user_id);

COMMENT ON TABLE community_owners IS
    'Co-owners of a community beyond the primary owner stored in communities.owner_id. Primary owners are NOT duplicated here.';

-- ── community_invitations ──────────────────────────────────────────
-- Handshake records. Each row is a pending → accepted/rejected/
-- cancelled/expired lifecycle. Status transitions are written by
-- handlers; a CHECK constraint keeps the value sane.
CREATE TABLE IF NOT EXISTS community_invitations (
    id              BIGSERIAL  PRIMARY KEY,
    community_id    TEXT       NOT NULL REFERENCES communities(id) ON DELETE CASCADE,
    invited_user_id BIGINT     NOT NULL REFERENCES users(id)       ON DELETE CASCADE,
    invited_by      BIGINT     NOT NULL REFERENCES users(id),
    status          TEXT       NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
    message         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMPTZ
);

-- Most queries hit "show me pending invitations for THIS user" — index
-- the receiver side. Compound on status to make the WHERE more
-- selective on busy databases.
CREATE INDEX IF NOT EXISTS community_invitations_user_status_idx
    ON community_invitations (invited_user_id, status);

-- Also useful when looking at "all invitations sent for THIS community".
CREATE INDEX IF NOT EXISTS community_invitations_community_status_idx
    ON community_invitations (community_id, status);

-- A single user can only have ONE pending invitation per community at
-- a time. Once they accept or reject, the row's status updates rather
-- than spawning a new one. (We allow a fresh `pending` after a previous
-- `rejected` / `cancelled`, hence the partial unique.)
CREATE UNIQUE INDEX IF NOT EXISTS community_invitations_one_pending
    ON community_invitations (community_id, invited_user_id)
    WHERE status = 'pending';

COMMENT ON TABLE community_invitations IS
    'Outstanding invitations sent by a community owner to an expert to become a co-owner.';

-- ── Realtime triggers — fire pg_notify on every state change ──────
-- The Flutter + admin clients listen on these channels via the
-- realtime hub (see internal/realtime/listener.go). Names mirror the
-- pattern used by other tables (community_messages, audit_logs, etc.).

CREATE OR REPLACE FUNCTION notify_community_invitation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    payload JSON;
BEGIN
    payload := json_build_object(
        'id', NEW.id,
        'communityId', NEW.community_id,
        'invitedUserId', NEW.invited_user_id,
        'invitedBy', NEW.invited_by,
        'status', NEW.status,
        'createdAt', NEW.created_at,
        'resolvedAt', NEW.resolved_at
    );
    -- Emit a per-status channel name so the listener can route
    -- without parsing the payload.
    IF TG_OP = 'INSERT' THEN
        PERFORM pg_notify('community_invitation_sent', payload::text);
    ELSIF NEW.status = 'accepted' THEN
        PERFORM pg_notify('community_invitation_accepted', payload::text);
    ELSIF NEW.status = 'rejected' THEN
        PERFORM pg_notify('community_invitation_rejected', payload::text);
    ELSIF NEW.status = 'cancelled' THEN
        PERFORM pg_notify('community_invitation_cancelled', payload::text);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS community_invitation_notify ON community_invitations;
CREATE TRIGGER community_invitation_notify
AFTER INSERT OR UPDATE ON community_invitations
FOR EACH ROW EXECUTE FUNCTION notify_community_invitation();

CREATE OR REPLACE FUNCTION notify_community_owner_change()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    payload JSON;
BEGIN
    IF TG_OP = 'INSERT' THEN
        payload := json_build_object(
            'communityId', NEW.community_id,
            'userId', NEW.user_id,
            'grantedBy', NEW.granted_by,
            'grantedAt', NEW.granted_at
        );
        PERFORM pg_notify('community_co_owner_added', payload::text);
    ELSIF TG_OP = 'DELETE' THEN
        payload := json_build_object(
            'communityId', OLD.community_id,
            'userId', OLD.user_id
        );
        PERFORM pg_notify('community_co_owner_removed', payload::text);
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS community_owner_change_notify ON community_owners;
CREATE TRIGGER community_owner_change_notify
AFTER INSERT OR DELETE ON community_owners
FOR EACH ROW EXECUTE FUNCTION notify_community_owner_change();

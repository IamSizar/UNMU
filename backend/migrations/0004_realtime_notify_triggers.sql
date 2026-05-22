-- =============================================================================
-- Realtime — Postgres NOTIFY triggers for the in-process Hub.
--
-- Adds triggers that emit JSON payloads on three Postgres channels. The Go
-- listener (internal/realtime/listener.go) subscribes to these channels and
-- fans the payloads out to WebSocket clients.
--
-- Channels emitted here:
--   * expert_application_events  — { type, applicationId, userId, status }
--   * user_role_events           — { userId, oldRole, newRole, expertId }
--   * expert_post_events         — { type, postId, expertId, postType, visibility, title }
--
-- Run with:
--   psql "$DATABASE_URL" -f backend/migrations/0004_realtime_notify_triggers.sql
--
-- Idempotent. Safe to re-run.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. expert_applications — fire on INSERT (status='pending') and on UPDATE
--    when status flips to 'approved' or 'rejected'.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_expert_application_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
    ev_type TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        ev_type := 'submitted';
        payload := json_build_object(
            'type',          ev_type,
            'applicationId', NEW.id,
            'userId',        NEW.user_id,
            'status',        NEW.status,
            'fullName',      NEW.full_name,
            'expertise',     NEW.expertise
        );
        PERFORM pg_notify('expert_application_events', payload::text);
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status IN ('approved','rejected') THEN
        payload := json_build_object(
            'type',          NEW.status,
            'applicationId', NEW.id,
            'userId',        NEW.user_id,
            'status',        NEW.status,
            'fullName',      NEW.full_name,
            'rejectionReason', NEW.rejection_reason
        );
        PERFORM pg_notify('expert_application_events', payload::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS expert_application_notify ON expert_applications;
CREATE TRIGGER expert_application_notify
    AFTER INSERT OR UPDATE ON expert_applications
    FOR EACH ROW EXECUTE FUNCTION notify_expert_application_event();

-- -----------------------------------------------------------------------------
-- 2. users.role — when role changes (e.g. USER → EXPERT after approval), the
--    user's currently-open Flutter session should refresh without re-login.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_user_role_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    IF OLD.role IS DISTINCT FROM NEW.role THEN
        payload := json_build_object(
            'userId',   NEW.id,
            'oldRole',  OLD.role,
            'newRole',  NEW.role,
            'expertId', NEW.expert_id
        );
        PERFORM pg_notify('user_role_events', payload::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_role_notify ON users;
CREATE TRIGGER user_role_notify
    AFTER UPDATE OF role ON users
    FOR EACH ROW EXECUTE FUNCTION notify_user_role_event();

-- -----------------------------------------------------------------------------
-- 3. posts — emit when a new expert post is published. Subscribers see this
--    as a "new content" event in their feed.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_expert_post_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    IF NEW.target_type = 'expert' THEN
        payload := json_build_object(
            'type',       'created',
            'postId',     NEW.id,
            'expertId',   NEW.expert_id,
            'authorName', NEW.author_name,
            'postType',   NEW.post_type,
            'visibility', NEW.visibility,
            'title',      NEW.title
        );
        PERFORM pg_notify('expert_post_events', payload::text);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS expert_post_notify ON posts;
CREATE TRIGGER expert_post_notify
    AFTER INSERT ON posts
    FOR EACH ROW EXECUTE FUNCTION notify_expert_post_event();

COMMIT;

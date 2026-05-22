-- =============================================================================
-- Audit log — durable, append-only record of every meaningful event in the
-- system. The admin dashboard reads from this and displays it as a live feed,
-- color-coded per event type.
--
-- Event types (kept in sync with backend/internal/models/audit.go):
--
--   AUTH_LOGIN              ─ a user logged in
--   AUTH_REGISTER           ─ new user signed up
--   AUTH_LOGOUT             ─ user logged out (best-effort)
--   EXPERT_APP_SUBMITTED    ─ user submitted an expert application
--   EXPERT_APP_APPROVED     ─ admin approved an application
--   EXPERT_APP_REJECTED     ─ admin rejected an application
--   USER_ROLE_CHANGED       ─ users.role flipped (any direction)
--   POST_CREATED            ─ expert published an article/video/reel
--   POST_HIDDEN             ─ admin hid a post for moderation
--   SUBSCRIPTION_CHANGED    ─ user changed subscription tier
--
-- Severity levels (drive admin UI color):
--   info | success | warning | error
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1. Table.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS audit_logs (
    id          BIGSERIAL PRIMARY KEY,
    type        TEXT        NOT NULL,
    severity    TEXT        NOT NULL DEFAULT 'info'
                CHECK (severity IN ('info','success','warning','error')),
    actor_id    BIGINT      REFERENCES users(id) ON DELETE SET NULL,
    actor_email TEXT,        -- snapshot at write time so deletes don't lose history
    target_id   TEXT,        -- entity affected (user id, post id, application id, ...)
    target_kind TEXT,        -- "user", "post", "application", "subscription", ...
    summary     TEXT NOT NULL,
    metadata    JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS audit_logs_type_idx     ON audit_logs(type, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_severity_idx ON audit_logs(severity, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_actor_idx    ON audit_logs(actor_id, created_at DESC);
CREATE INDEX IF NOT EXISTS audit_logs_recent_idx   ON audit_logs(created_at DESC);

-- -----------------------------------------------------------------------------
-- 2. Helper function — write_audit(type, severity, actor_id, target_id,
--    target_kind, summary, metadata). The Go backend uses raw INSERTs for
--    most things, but Postgres triggers below also call this so the audit
--    feed stays consistent regardless of how a row was modified.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION write_audit(
    p_type        TEXT,
    p_severity    TEXT,
    p_actor_id    BIGINT,
    p_target_id   TEXT,
    p_target_kind TEXT,
    p_summary     TEXT,
    p_metadata    JSONB DEFAULT '{}'::jsonb
) RETURNS BIGINT AS $$
DECLARE
    new_id      BIGINT;
    actor_email TEXT;
BEGIN
    SELECT email INTO actor_email FROM users WHERE id = p_actor_id;
    INSERT INTO audit_logs (type, severity, actor_id, actor_email, target_id, target_kind, summary, metadata)
    VALUES (p_type, p_severity, p_actor_id, actor_email, p_target_id, p_target_kind, p_summary, p_metadata)
    RETURNING id INTO new_id;
    RETURN new_id;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- 3. NOTIFY — broadcast every new audit row so the admin dashboard can stream
--    them without polling.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_audit_log_event() RETURNS TRIGGER AS $$
BEGIN
    PERFORM pg_notify('audit_log_events', json_build_object(
        'id',         NEW.id,
        'type',       NEW.type,
        'severity',   NEW.severity,
        'actorId',    NEW.actor_id,
        'actorEmail', NEW.actor_email,
        'targetId',   NEW.target_id,
        'targetKind', NEW.target_kind,
        'summary',    NEW.summary,
        'metadata',   NEW.metadata,
        'createdAt',  NEW.created_at
    )::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS audit_logs_notify ON audit_logs;
CREATE TRIGGER audit_logs_notify
    AFTER INSERT ON audit_logs
    FOR EACH ROW EXECUTE FUNCTION notify_audit_log_event();

-- -----------------------------------------------------------------------------
-- 4. Triggers on existing tables — auto-populate the audit log when DB
--    state changes, regardless of which code path made the change.
-- -----------------------------------------------------------------------------

-- expert_applications: log every insert + every status transition.
CREATE OR REPLACE FUNCTION audit_expert_application() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM write_audit(
            'EXPERT_APP_SUBMITTED', 'info',
            NEW.user_id, NEW.id::text, 'application',
            COALESCE(NEW.full_name, '') || ' applied to be an expert',
            json_build_object('expertise', NEW.expertise)::jsonb
        );
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND OLD.status = 'pending' AND NEW.status IN ('approved','rejected') THEN
        PERFORM write_audit(
            CASE NEW.status
                WHEN 'approved' THEN 'EXPERT_APP_APPROVED'
                ELSE                  'EXPERT_APP_REJECTED'
            END,
            CASE NEW.status WHEN 'approved' THEN 'success' ELSE 'warning' END,
            NEW.reviewed_by, NEW.id::text, 'application',
            'Application ' || NEW.status || ' for ' || COALESCE(NEW.full_name, ''),
            json_build_object(
                'applicantUserId', NEW.user_id,
                'reason',          NEW.rejection_reason
            )::jsonb
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS expert_application_audit ON expert_applications;
CREATE TRIGGER expert_application_audit
    AFTER INSERT OR UPDATE ON expert_applications
    FOR EACH ROW EXECUTE FUNCTION audit_expert_application();

-- users.role flip
CREATE OR REPLACE FUNCTION audit_user_role() RETURNS TRIGGER AS $$
BEGIN
    IF OLD.role IS DISTINCT FROM NEW.role THEN
        PERFORM write_audit(
            'USER_ROLE_CHANGED', 'info',
            NEW.id, NEW.id::text, 'user',
            OLD.email || ' role changed: ' || OLD.role || ' → ' || NEW.role,
            json_build_object('oldRole', OLD.role, 'newRole', NEW.role)::jsonb
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_role_audit ON users;
CREATE TRIGGER user_role_audit
    AFTER UPDATE OF role ON users
    FOR EACH ROW EXECUTE FUNCTION audit_user_role();

-- posts: new expert post = audit-worthy event
CREATE OR REPLACE FUNCTION audit_post_created() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.target_type = 'expert' THEN
        PERFORM write_audit(
            'POST_CREATED', 'info',
            NEW.author_id, NEW.id::text, 'post',
            NEW.author_name || ' published a new ' || NEW.post_type,
            json_build_object(
                'expertId',   NEW.expert_id,
                'postType',   NEW.post_type,
                'visibility', NEW.visibility,
                'title',      NEW.title
            )::jsonb
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS post_created_audit ON posts;
CREATE TRIGGER post_created_audit
    AFTER INSERT ON posts
    FOR EACH ROW EXECUTE FUNCTION audit_post_created();

COMMIT;

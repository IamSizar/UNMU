-- =============================================================================
-- Step-5 — let experts edit, hide, and delete their own posts.
--
-- Adds:
--   * posts.is_hidden    — owner-only flag. Hidden rows are excluded from
--                          public lists and the expert's own profile feed
--                          for non-owner viewers, but the expert still sees
--                          them in their studio so they can un-hide later.
--   * posts.updated_at   — bumped on every UPDATE so Flutter / admin can
--                          surface "edited X ago" if they want to.
--
-- Extends the realtime trigger so it now emits on UPDATE and DELETE too,
-- not just INSERT. Wire types:
--
--   { type: 'created',  postId, expertId, postType, visibility, title }
--   { type: 'edited',   postId, expertId, postType, visibility, title }
--   { type: 'hidden',   postId, expertId, isHidden }
--   { type: 'deleted',  postId, expertId }
--
-- All flow on the same `expert_post_events` Postgres channel; the Go
-- listener (internal/realtime/listener.go) already routes `expert_post_events`
-- to the right WS channels — we extend the wire-type switch to recognize
-- the new types.
--
-- Idempotent. Safe to re-run.
-- =============================================================================

BEGIN;

-- 1. New columns. Both default-safe so existing rows stay valid.
ALTER TABLE posts
    ADD COLUMN IF NOT EXISTS is_hidden  BOOLEAN     NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- Helpful for the "give me everything except hidden" query path.
CREATE INDEX IF NOT EXISTS posts_expert_visible_idx
    ON posts(expert_id, created_at DESC)
    WHERE target_type = 'expert' AND is_hidden = FALSE;

-- 2. Auto-bump updated_at on every UPDATE so we don't have to remember in
--    handler code.
CREATE OR REPLACE FUNCTION posts_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS posts_updated_at ON posts;
CREATE TRIGGER posts_updated_at
    BEFORE UPDATE ON posts
    FOR EACH ROW EXECUTE FUNCTION posts_set_updated_at();

-- 3. Replace the realtime trigger so it covers INSERT / UPDATE / DELETE.
--    The `created` payload is unchanged so existing clients keep working.
CREATE OR REPLACE FUNCTION notify_expert_post_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.target_type = 'expert' THEN
            payload := json_build_object(
                'type',     'deleted',
                'postId',   OLD.id,
                'expertId', OLD.expert_id
            );
            PERFORM pg_notify('expert_post_events', payload::text);
        END IF;
        RETURN OLD;
    END IF;

    IF TG_OP = 'INSERT' THEN
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
    END IF;

    -- UPDATE: differentiate "hidden flipped" from "content edited".
    IF TG_OP = 'UPDATE' AND NEW.target_type = 'expert' THEN
        IF OLD.is_hidden IS DISTINCT FROM NEW.is_hidden THEN
            payload := json_build_object(
                'type',     'hidden',
                'postId',   NEW.id,
                'expertId', NEW.expert_id,
                'isHidden', NEW.is_hidden
            );
            PERFORM pg_notify('expert_post_events', payload::text);
        ELSE
            payload := json_build_object(
                'type',       'edited',
                'postId',     NEW.id,
                'expertId',   NEW.expert_id,
                'postType',   NEW.post_type,
                'visibility', NEW.visibility,
                'title',      NEW.title
            );
            PERFORM pg_notify('expert_post_events', payload::text);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS expert_post_notify ON posts;
CREATE TRIGGER expert_post_notify
    AFTER INSERT OR UPDATE OR DELETE ON posts
    FOR EACH ROW EXECUTE FUNCTION notify_expert_post_event();

COMMIT;

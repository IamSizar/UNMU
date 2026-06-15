-- 0053_post_event_status.sql
-- Adds `status` to the expert_post_events JSON payload so the realtime
-- listener can push subscribers ONLY for posts that are actually published
-- (skip drafts + scheduled). Replaces the trigger functions from mig 0008
-- — same behaviour as before, just with the extra field.
BEGIN;

CREATE OR REPLACE FUNCTION notify_expert_post_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.target_type = 'expert' THEN
            payload := json_build_object(
                'type',       'deleted',
                'postId',     OLD.id,
                'expertId',   OLD.expert_id,
                'authorId',   OLD.author_id,
                'authorName', OLD.author_name,
                'postType',   OLD.post_type,
                'visibility', OLD.visibility,
                'status',     OLD.status,
                'title',      OLD.title
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
                'authorId',   NEW.author_id,
                'authorName', NEW.author_name,
                'postType',   NEW.post_type,
                'visibility', NEW.visibility,
                'status',     NEW.status,
                'title',      NEW.title
            );
            PERFORM pg_notify('expert_post_events', payload::text);
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' AND NEW.target_type = 'expert' THEN
        IF OLD.is_hidden IS DISTINCT FROM NEW.is_hidden THEN
            payload := json_build_object(
                'type',     'hidden',
                'postId',   NEW.id,
                'expertId', NEW.expert_id,
                'isHidden', NEW.is_hidden
            );
            PERFORM pg_notify('expert_post_events', payload::text);
            RETURN NEW;
        END IF;
        -- Scheduled-publisher promotion: status goes 'scheduled' → 'published'.
        -- Emit a 'created' event so the push fan-out fires for time-released
        -- posts too (mig 0020 added the scheduled state).
        IF OLD.status IS DISTINCT FROM NEW.status
           AND NEW.status = 'published' THEN
            payload := json_build_object(
                'type',       'created',
                'postId',     NEW.id,
                'expertId',   NEW.expert_id,
                'authorId',   NEW.author_id,
                'authorName', NEW.author_name,
                'postType',   NEW.post_type,
                'visibility', NEW.visibility,
                'status',     NEW.status,
                'title',      NEW.title
            );
            PERFORM pg_notify('expert_post_events', payload::text);
            RETURN NEW;
        END IF;
        -- Generic edit (body/title/etc).
        payload := json_build_object(
            'type',       'edited',
            'postId',     NEW.id,
            'expertId',   NEW.expert_id,
            'authorName', NEW.author_name,
            'postType',   NEW.post_type,
            'visibility', NEW.visibility,
            'status',     NEW.status,
            'title',      NEW.title
        );
        PERFORM pg_notify('expert_post_events', payload::text);
        RETURN NEW;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMIT;

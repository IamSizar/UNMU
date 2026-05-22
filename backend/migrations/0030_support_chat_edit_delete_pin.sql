-- =============================================================================
-- 0030 — Edit / soft-delete / pin for support chat messages.
--
-- Adds three capabilities on top of the chat from mig 0029:
--
--   * Edit — the user can edit their OWN message; admins can edit any
--     message. `edited_at` is set on every update so the UI can render
--     an "(edited)" suffix.
--   * Soft-delete — admin-only. We don't remove the row (would orphan
--     the chat flow + lose audit). Instead `deleted_at` is set and the
--     UI renders a "[message deleted]" placeholder bubble.
--   * Pin — admin-only. A single message per thread can be pinned at a
--     time; setting a new pin replaces the old. Stored as
--     `support_threads.pinned_message_id` with ON DELETE SET NULL so
--     deleting (or hard-cleaning) the pinned message naturally unpins.
--
-- Triggers fan three new event types on the support_message_events
-- channel: `edited`, `deleted`, `pinned`. Dispatcher in
-- internal/realtime/listener.go re-publishes them to the user channel
-- + admin channel so both clients refresh live.
-- =============================================================================

ALTER TABLE support_messages
    ADD COLUMN IF NOT EXISTS edited_at  TIMESTAMP,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP;

ALTER TABLE support_threads
    ADD COLUMN IF NOT EXISTS pinned_message_id BIGINT
        REFERENCES support_messages(id) ON DELETE SET NULL;


-- Replace the insert-only notify trigger so it also fires on UPDATE
-- (which is how we emit `edited` / `deleted` events). The original
-- AFTER INSERT trigger from 0029 still handles row-creation events.
CREATE OR REPLACE FUNCTION notify_support_message_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
    thread_user_id BIGINT;
    ev_type TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        ev_type := 'sent';
    ELSIF TG_OP = 'UPDATE' THEN
        IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
           AND NEW.deleted_at IS NOT NULL THEN
            ev_type := 'deleted';
        ELSIF NEW.edited_at IS DISTINCT FROM OLD.edited_at
              AND NEW.edited_at IS NOT NULL THEN
            ev_type := 'edited';
        ELSE
            RETURN NEW;
        END IF;
    ELSE
        RETURN NEW;
    END IF;

    SELECT user_id INTO thread_user_id
      FROM support_threads WHERE id = NEW.thread_id;

    payload := json_build_object(
        'type',         ev_type,
        'messageId',    NEW.id,
        'threadId',     NEW.thread_id,
        'threadUserId', thread_user_id,
        'senderUserId', NEW.sender_user_id,
        'senderRole',   NEW.sender_role,
        'body',         NEW.body,
        'createdAt',    NEW.created_at,
        'editedAt',     NEW.edited_at,
        'deletedAt',    NEW.deleted_at
    );
    PERFORM pg_notify('support_message_events', payload::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Bind the same function to INSERT *and* UPDATE.
DROP TRIGGER IF EXISTS support_message_notify ON support_messages;
CREATE TRIGGER support_message_notify
    AFTER INSERT OR UPDATE ON support_messages
    FOR EACH ROW EXECUTE FUNCTION notify_support_message_event();


-- Separate trigger on support_threads emits `pinned` events when
-- `pinned_message_id` changes. We send the event on a dedicated
-- support_thread_events channel; the listener also subscribes there.
CREATE OR REPLACE FUNCTION notify_support_thread_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.pinned_message_id IS DISTINCT FROM OLD.pinned_message_id THEN
            payload := json_build_object(
                'type',          CASE WHEN NEW.pinned_message_id IS NULL
                                      THEN 'unpinned'
                                      ELSE 'pinned' END,
                'threadId',      NEW.id,
                'threadUserId',  NEW.user_id,
                'pinnedMessageId', NEW.pinned_message_id
            );
            PERFORM pg_notify('support_thread_events', payload::text);
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS support_thread_notify ON support_threads;
CREATE TRIGGER support_thread_notify
    AFTER UPDATE ON support_threads
    FOR EACH ROW EXECUTE FUNCTION notify_support_thread_event();

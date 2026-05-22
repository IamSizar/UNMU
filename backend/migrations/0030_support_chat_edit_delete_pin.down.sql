-- Reverse of 0030.
DROP TRIGGER IF EXISTS support_thread_notify  ON support_threads;
DROP FUNCTION IF EXISTS notify_support_thread_event();

-- Restore the insert-only trigger function from mig 0029 so the
-- chat keeps working after rollback.
CREATE OR REPLACE FUNCTION notify_support_message_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
    thread_user_id BIGINT;
BEGIN
    SELECT user_id INTO thread_user_id
      FROM support_threads WHERE id = NEW.thread_id;

    payload := json_build_object(
        'type',         'sent',
        'messageId',    NEW.id,
        'threadId',     NEW.thread_id,
        'threadUserId', thread_user_id,
        'senderUserId', NEW.sender_user_id,
        'senderRole',   NEW.sender_role,
        'body',         NEW.body,
        'createdAt',    NEW.created_at
    );
    PERFORM pg_notify('support_message_events', payload::text);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS support_message_notify ON support_messages;
CREATE TRIGGER support_message_notify
    AFTER INSERT ON support_messages
    FOR EACH ROW EXECUTE FUNCTION notify_support_message_event();

ALTER TABLE support_threads  DROP COLUMN IF EXISTS pinned_message_id;
ALTER TABLE support_messages DROP COLUMN IF EXISTS edited_at;
ALTER TABLE support_messages DROP COLUMN IF EXISTS deleted_at;

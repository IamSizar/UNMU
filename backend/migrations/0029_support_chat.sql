-- =============================================================================
-- 0029 — Built-in user ↔ admin support chat.
--
-- Schema choices:
--   • SINGLE thread per user — `support_threads.user_id` has a UNIQUE
--     constraint so we never accidentally fork a user's conversation.
--     "Closed" threads stay around (history); the user re-opens them by
--     sending another message (handler flips status back to 'open').
--   • Messages live in `support_messages`; a partial index on
--     (thread_id, created_at DESC) keeps the chat scroll cheap.
--   • Cached unread counts on the thread row let the sidebar badge
--     render without aggregating across messages on every page load.
--   • pg_notify trigger fans out every insert on a dedicated channel
--     so the realtime hub can push to the right websocket clients.
-- =============================================================================

-- ── threads ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS support_threads (
    id                BIGSERIAL PRIMARY KEY,
    user_id           BIGINT       NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status            TEXT         NOT NULL DEFAULT 'open',  -- 'open' | 'closed'
    last_message_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    last_message_role TEXT,                                  -- 'user' | 'admin'
    last_message_body TEXT,
    -- Cached unread counts — the message INSERT trigger keeps these in
    -- sync. Admin mark-as-read zeroes unread_admin; user mark-as-read
    -- zeroes unread_user.
    unread_admin      INT          NOT NULL DEFAULT 0,
    unread_user       INT          NOT NULL DEFAULT 0,
    created_at        TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at        TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- One thread per user. CASCADE on user delete cleans up the whole tree.
CREATE UNIQUE INDEX IF NOT EXISTS support_threads_user_id_uniq
    ON support_threads(user_id);

-- Admin inbox sort key — newest activity first.
CREATE INDEX IF NOT EXISTS idx_support_threads_last_message_at
    ON support_threads(last_message_at DESC);


-- ── messages ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS support_messages (
    id              BIGSERIAL PRIMARY KEY,
    thread_id       BIGINT      NOT NULL REFERENCES support_threads(id) ON DELETE CASCADE,
    sender_user_id  BIGINT      NOT NULL REFERENCES users(id) ON DELETE SET NULL,
    sender_role     TEXT        NOT NULL CHECK (sender_role IN ('user', 'admin')),
    body            TEXT        NOT NULL,
    created_at      TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- Chat scroll — fetch the most recent N messages for a thread.
CREATE INDEX IF NOT EXISTS idx_support_messages_thread_created
    ON support_messages(thread_id, created_at DESC);


-- ── trigger: keep thread row hot whenever a message is inserted ──────
-- Updates the thread snapshot (last_message_at, last_message_body,
-- last_message_role) and bumps the unread counter on the OPPOSITE side
-- of who sent the message. Also flips status back to 'open' when a user
-- writes into a previously-closed thread.
CREATE OR REPLACE FUNCTION support_message_upsert_thread()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE support_threads
       SET last_message_at   = NEW.created_at,
           last_message_role = NEW.sender_role,
           last_message_body = LEFT(NEW.body, 200), -- snippet only
           unread_admin = CASE WHEN NEW.sender_role = 'user'
                               THEN unread_admin + 1 ELSE unread_admin END,
           unread_user  = CASE WHEN NEW.sender_role = 'admin'
                               THEN unread_user + 1 ELSE unread_user END,
           status = CASE WHEN status = 'closed' AND NEW.sender_role = 'user'
                          THEN 'open' ELSE status END,
           updated_at = NOW()
     WHERE id = NEW.thread_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS support_message_after_insert ON support_messages;
CREATE TRIGGER support_message_after_insert
    AFTER INSERT ON support_messages
    FOR EACH ROW EXECUTE FUNCTION support_message_upsert_thread();


-- ── trigger: pg_notify for the realtime hub ──────────────────────────
-- Fires on every message insert so the Go listener can fan it out to
-- the user's WS channel (admin replies) AND to the admin channel
-- (user messages). Payload mirrors the shape the realtime listener
-- already uses for other event families (see internal/realtime/listener.go).
CREATE OR REPLACE FUNCTION notify_support_message_event() RETURNS TRIGGER AS $$
DECLARE
    payload JSON;
    thread_user_id BIGINT;
BEGIN
    SELECT user_id INTO thread_user_id
      FROM support_threads WHERE id = NEW.thread_id;

    payload := json_build_object(
        'type',         'sent',  -- listener prefixes with 'support_message_'
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

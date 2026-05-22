-- Reverse of 0029 — drops the support chat tables and triggers.
DROP TRIGGER IF EXISTS support_message_notify       ON support_messages;
DROP TRIGGER IF EXISTS support_message_after_insert ON support_messages;
DROP FUNCTION IF EXISTS notify_support_message_event();
DROP FUNCTION IF EXISTS support_message_upsert_thread();
DROP TABLE IF EXISTS support_messages;
DROP TABLE IF EXISTS support_threads;

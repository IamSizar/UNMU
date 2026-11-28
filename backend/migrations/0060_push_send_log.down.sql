-- Reverts 0060_push_send_log.sql (drops the send history).
DROP TABLE IF EXISTS push_send_log;

-- Rollback migration for pipeline schema

DROP TRIGGER IF EXISTS shariah_status_change_trigger ON shariah_results;
DROP FUNCTION IF EXISTS log_shariah_status_change();

DROP TABLE IF EXISTS shariah_result_history;
DROP TABLE IF EXISTS shariah_results;
DROP TABLE IF EXISTS stock_snapshots;
DROP TABLE IF EXISTS tracked_symbols;


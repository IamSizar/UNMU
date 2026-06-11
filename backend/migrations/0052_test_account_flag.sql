-- 0052_test_account_flag.sql
-- Adds the `test_account_enabled` feature flag. Drives whether the mobile
-- login screen shows the "Test account" quick-switch button. Admins flip it
-- from the dashboard Settings page. Default true = current behaviour (shown).
INSERT INTO app_settings (key, value) VALUES
    ('test_account_enabled', 'true')
ON CONFLICT (key) DO NOTHING;

-- 0054_screening_thresholds.sql
-- Seeds the Shariah screening grading ladder into app_settings so it's
-- visible and editable from the admin dashboard instead of living only as
-- Go constants. Values match what internal/shariah/rules.go already used —
-- this migration changes nothing about existing screening results, it only
-- makes the numbers admin-configurable going forward.
--
-- SHARIAH-REVIEW: any change to these values changes what the app calls
-- "HALAL" for every user immediately. Confirm with a qualified Shariah
-- advisor before editing in production.
INSERT INTO app_settings (key, value) VALUES
    ('screening_debt_fail',  '33'),
    ('screening_debt_warn',  '30'),
    ('screening_debt_pass',  '20'),
    ('screening_debt_good',  '10'),
    ('screening_haram_fail', '10'),
    ('screening_haram_warn', '5'),
    ('screening_haram_pass', '3'),
    ('screening_haram_good', '1')
ON CONFLICT (key) DO NOTHING;

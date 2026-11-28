-- Constraint test for 0056_pulse.sql. Run against a scratch database ONLY:
--   psql -d unmu_pulse_dev -v ON_ERROR_STOP=1 -f tests/pulse_constraints_test.sql
-- Everything happens inside one transaction that is rolled back at the end, so
-- it leaves no data behind. Each block must RAISE if a bad row is ACCEPTED.
BEGIN;

INSERT INTO users (id, email, password_hash, role) VALUES
  (990001, 'pulse.author@test.invalid', 'x', 'ADMIN'),
  (990002, 'pulse.reviewer@test.invalid', 'x', 'ADMIN'),
  (990003, 'pulse.approver@test.invalid', 'x', 'ADMIN');

-- expect_fail(label, sql): the statement must raise; if it succeeds, we fail.
CREATE FUNCTION pg_temp.expect_fail(label text, stmt text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'ok   rejected: %', label;
    RETURN;
  END;
  RAISE EXCEPTION 'FAIL accepted bad row: %', label;
END;
$$ LANGUAGE plpgsql;

-- 1. A draft needs nothing; this must succeed.
INSERT INTO pulse_items (pulse_date, slot, classification, created_by)
VALUES ('2026-10-22', 'global', 'confirmed', 990001);

-- 2. Cannot go to review without both languages / source / verified_at.
SELECT pg_temp.expect_fail('in_review without translations',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, status, title_en, summary_en, source_name, verified_at)
   VALUES ('2026-10-22','gulf','confirmed','in_review','t','s','src',now())$$);

-- 3. Sharia slot must be sensitive.
SELECT pg_temp.expect_fail('sharia slot not sensitive',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, is_sensitive)
   VALUES ('2026-10-23','sharia','confirmed',false)$$);

-- 4. Approved needs an approver.
SELECT pg_temp.expect_fail('approved without approver',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, status, title_ar, title_en, summary_ar, summary_en, source_name, verified_at)
   VALUES ('2026-10-22','gulf','confirmed','approved','ع','t','ع','s','src',now())$$);

-- 5. Sensitive item needs a reviewer even with an approver.
SELECT pg_temp.expect_fail('sensitive approved without reviewer',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, is_sensitive, status, title_ar, title_en, summary_ar, summary_en, source_name, verified_at, approved_by)
   VALUES ('2026-10-24','sharia','confirmed',true,'approved','ع','t','ع','s','src',now(),990003)$$);

-- 6. Scheduled needs publish_at; published needs published_at.
SELECT pg_temp.expect_fail('scheduled without publish_at',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, status, title_ar, title_en, summary_ar, summary_en, source_name, verified_at, approved_by)
   VALUES ('2026-10-25','gulf','confirmed','scheduled','ع','t','ع','s','src',now(),990003)$$);
SELECT pg_temp.expect_fail('published without published_at',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, status, title_ar, title_en, summary_ar, summary_en, source_name, verified_at, approved_by)
   VALUES ('2026-10-25','gulf','confirmed','published','ع','t','ع','s','src',now(),990003)$$);

-- 7. Valid published sensitive item succeeds; a second published item for the
--    same day+slot is rejected.
INSERT INTO pulse_items (pulse_date, slot, classification, is_sensitive, status, title_ar, title_en, summary_ar, summary_en, source_name, verified_at, reviewed_by, approved_by, published_at)
VALUES ('2026-10-26','sharia','confirmed',true,'published','ع','t','ع','s','src',now(),990002,990003,now());
SELECT pg_temp.expect_fail('second published item same day+slot',
 $$INSERT INTO pulse_items (pulse_date, slot, classification, is_sensitive, status, title_ar, title_en, summary_ar, summary_en, source_name, verified_at, reviewed_by, approved_by, published_at)
   VALUES ('2026-10-26','sharia','confirmed',true,'published','ع','t2','ع','s2','src',now(),990002,990003,now())$$);

-- 8. Enum checks.
SELECT pg_temp.expect_fail('bad slot', $$INSERT INTO pulse_items (pulse_date, slot, classification) VALUES ('2026-10-27','weather','confirmed')$$);
SELECT pg_temp.expect_fail('bad staff role', $$INSERT INTO pulse_staff (user_id, pulse_role) VALUES (990001,'boss')$$);
SELECT pg_temp.expect_fail('bad analytics event', $$INSERT INTO pulse_events (user_id, event) VALUES (990001,'like')$$);

-- 9. Event log is append-only.
INSERT INTO pulse_item_events (item_id, action, actor_id)
  SELECT id, 'created', 990001 FROM pulse_items LIMIT 1;
SELECT pg_temp.expect_fail('rewriting a change-log row', $$UPDATE pulse_item_events SET note = 'tampered'$$);

-- 10. One save per user per item.
INSERT INTO pulse_saves (user_id, item_id) SELECT 990001, id FROM pulse_items LIMIT 1;
SELECT pg_temp.expect_fail('duplicate save', $$INSERT INTO pulse_saves (user_id, item_id) SELECT 990001, id FROM pulse_items LIMIT 1$$);

-- 11. updated_at is refreshed on update. NOW() is frozen inside one
--     transaction, so start from an old value instead of waiting.
DO $$
DECLARE after_ts timestamptz;
BEGIN
  UPDATE pulse_items SET updated_at = '2000-01-01' WHERE id = (SELECT min(id) FROM pulse_items);
  UPDATE pulse_items SET title_en = 'x' WHERE id = (SELECT min(id) FROM pulse_items);
  SELECT updated_at INTO after_ts FROM pulse_items ORDER BY id LIMIT 1;
  IF after_ts <= '2000-01-02' THEN RAISE EXCEPTION 'FAIL updated_at did not advance'; END IF;
  RAISE NOTICE 'ok   updated_at advances';
END $$;

ROLLBACK;

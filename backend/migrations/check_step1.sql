-- =============================================================================
-- Step 1 — diagnostic check.
--
-- Paste this whole file into PostgreSQL's SQL Shell (psql).app, OR run via:
--   psql -h localhost -U zaidaqrawi -d halalstocks -f check_step1.sql
--
-- It tells you:
--   1. Are you on the halalstocks DB?
--   2. Does the admin user exist?
--   3. Does the expert_applications table exist?
--   4. Are there any pending applications?
-- =============================================================================

\echo '── 1. Connected to database:'
SELECT current_database() AS db;

\echo ''
\echo '── 2. Admin account (should show admin@test.com):'
SELECT id, email, name, role
  FROM users
 WHERE role = 'ADMIN';

\echo ''
\echo '── 3. expert_applications table — row count (table must exist):'
SELECT COUNT(*) AS rows FROM expert_applications;

\echo ''
\echo '── 4. Latest applications (most recent first):'
SELECT id,
       user_id,
       full_name,
       expertise,
       status,
       submitted_at
  FROM expert_applications
 ORDER BY submitted_at DESC
 LIMIT 10;

\echo ''
\echo '── 5. Users that have applied (joined view):'
SELECT u.email,
       u.role            AS user_role,
       a.status          AS application_status,
       a.submitted_at
  FROM expert_applications a
  JOIN users u ON u.id = a.user_id
 ORDER BY a.submitted_at DESC;

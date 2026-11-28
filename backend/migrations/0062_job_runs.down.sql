-- Reverts 0062_job_runs.sql (drops the daily job run history).
DROP TABLE IF EXISTS job_runs;

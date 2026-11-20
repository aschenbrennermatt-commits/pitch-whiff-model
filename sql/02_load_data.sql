-- =============================================================================
-- 02_load_data.sql
-- Loads the CSVs written by scripts/01_download_statcast.py.
--
-- Run from the repo root (the file paths below are relative to it):
--     psql -d whiff -f sql/02_load_data.sql
--
-- \copy runs on your machine and streams the file to the server, so it works
-- without superuser rights. Everything runs in one transaction: if any file
-- fails, nothing is loaded. Safe to re-run (it empties the tables first).
--
-- If you ran the download in --test mode, only pitches_2025.csv exists:
-- comment out the 2023 and 2024 lines with -- before running.
-- =============================================================================

\set ON_ERROR_STOP on
\timing on

BEGIN;

TRUNCATE pitches, pitchers;

-- 1. Parent table first (pitches.pitcher references it)
\copy pitchers FROM 'data/raw/pitchers.csv' WITH (FORMAT csv, HEADER true)

-- 2. One file per season
\copy pitches FROM 'data/raw/pitches_2023.csv' WITH (FORMAT csv, HEADER true)
\copy pitches FROM 'data/raw/pitches_2024.csv' WITH (FORMAT csv, HEADER true)
\copy pitches FROM 'data/raw/pitches_2025.csv' WITH (FORMAT csv, HEADER true)

COMMIT;

-- Refresh the planner's statistics so the first queries run fast.
ANALYZE;

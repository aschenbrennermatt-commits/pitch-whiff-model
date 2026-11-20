-- =============================================================================
-- 07_explore_whiffs.sql
-- Exploratory checks on model_swings before modelling: do the raw numbers
-- show the patterns the model is meant to learn?
--
-- Run from the repo root:
--     psql -P pager=off -d whiff -f sql/07_explore_whiffs.sql
-- =============================================================================


-- 1. Four-seam fastball whiff rate by velocity
--    1 mph buckets; buckets with fewer than 500 swings removed.

SELECT FLOOR(velo) AS velo_mph,
	   COUNT(*) AS swings,
	   ROUND(100.0 * AVG(whiff), 1) AS whiff_pct
FROM model_swings
WHERE pitch_type = 'FF'
GROUP BY velo_mph
HAVING COUNT(*) >= 500
ORDER BY velo_mph;


-- 2. Four-seam fastball whiff rate by induced vertical break
--    2-inch buckets; buckets with fewer than 500 swings removed.

SELECT FLOOR(ivb_in / 2) * 2 AS ivb_in_bucket,
	   COUNT(*) AS swings,
	   ROUND(100.0 * AVG(whiff), 1) AS whiff_pct
FROM model_swings
WHERE pitch_type = 'FF'
GROUP BY ivb_in_bucket
HAVING COUNT(*) >= 500
ORDER BY ivb_in_bucket;


-- 3. Whiff rate by count (balls-strikes), all pitch types

SELECT balls || '-' || strikes AS ab_count,
	   COUNT(*) AS swings,
	   ROUND(100.0 * AVG(whiff), 1) AS whiff_pct
FROM model_swings
GROUP BY balls, strikes
ORDER BY balls, strikes;


-- 4. Top 10 sweepers (ST) by whiff rate, 2023-2025
--    Pitchers with at least 200 sweeper swings; grouped by pitcher id
--    so pitchers who share a name stay separate.

SELECT RANK() OVER (ORDER BY AVG(whiff) DESC) AS rank,
	   model_swings.pitcher,
	   pitchers.pitcher_name,
	   COUNT(*) AS swings,
	   ROUND(100.0 * AVG(whiff), 1) AS whiff_pct
FROM model_swings
JOIN pitchers ON pitchers.pitcher_id = model_swings.pitcher
WHERE pitch_type = 'ST'
GROUP BY model_swings.pitcher, pitchers.pitcher_name
HAVING COUNT(*) >= 200
ORDER BY rank
LIMIT 10;


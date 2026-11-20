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
-- Finding: Four-seam whiff rate rises from 11% at 86 mph to 29% at 101 mph.
--    Harder throwers may also have more ride and extension, so the model
--    tests how much of this is velocity itself.

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
-- Finding: From 4 to 14 inches, whiff rate rose only 1.4 points (4 inches was
--    slightly higher than 6), but from 16 to 22 inches it rose over 12 points.
--    Ride helps mainly once it is well above average.

SELECT FLOOR(ivb_in / 2) * 2 AS ivb_in_bucket,
	   COUNT(*) AS swings,
	   ROUND(100.0 * AVG(whiff), 1) AS whiff_pct
FROM model_swings
WHERE pitch_type = 'FF'
GROUP BY ivb_in_bucket
HAVING COUNT(*) >= 500
ORDER BY ivb_in_bucket;


-- 3. Whiff rate by count (balls-strikes), all pitch types
-- Finding: Balls move the whiff rate more than strikes. It falls from __% at 0-0
--    to __% at 3-1, while 0-2 is close to 0-0.

SELECT balls || '-' || strikes AS ab_count,
	   COUNT(*) AS swings,
	   ROUND(100.0 * AVG(whiff), 1) AS whiff_pct
FROM model_swings
GROUP BY balls, strikes
ORDER BY balls, strikes;


-- 4. Top 10 sweepers (ST) by whiff rate, 2023-2025
--    Pitchers with at least 200 sweeper swings; grouped by pitcher id
--    so pitchers who share a name stay separate.
-- Finding: Jake Cousins leads at 45.6%; 10th place (Blake Treinen) is at 41%.
--    The list mixes starters and relievers. Relievers may rank higher because
--    they throw fewer, max-effort pitches and hitters see them only once
--    (a hypothesis; this query can't separate the two). Relievers also have
--    fewer swings, so their rates are noisier and land at the extremes more
--    often; Sonny Gray's rate rests on 900+ swings and is far more reliable.

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


-- =============================================================================
-- 03_check_load.sql
-- Sanity checks after loading. Run each query and compare with the comments.
--     psql -d whiff -f sql/03_check_load.sql
-- =============================================================================

-- 1. Pitches, games and pitchers per season.
--    Expect roughly 700,000+ pitches and ~2,430 games per full season.
SELECT game_year,
       COUNT(*)                AS pitches,
       COUNT(DISTINCT game_pk) AS games,
       COUNT(DISTINCT pitcher) AS pitchers,
       MIN(game_date)          AS first_day,
       MAX(game_date)          AS last_day
FROM pitches
GROUP BY game_year
ORDER BY game_year;

-- 2. Every pitcher id in pitches has a name (expect 0).
SELECT COUNT(*) AS pitches_without_name
FROM pitches p
LEFT JOIN pitchers pr ON pr.pitcher_id = p.pitcher
WHERE pr.pitcher_id IS NULL;

-- 3. Pitch outcomes. The target will come from these values in step 2.
--    Swings = swinging_strike, swinging_strike_blocked, foul, foul_tip, hit_into_play
--    (plus the bunt values, which we will leave out).
SELECT description,
       COUNT(*) AS pitches,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM pitches
GROUP BY description
ORDER BY pitches DESC;

-- 4. Missing values in the main physics columns, as % of pitches.
--    Expect under 1% for most; arm_angle is a newer measurement and may be higher.
SELECT game_year,
       ROUND(100.0 * AVG((release_speed     IS NULL)::int), 2) AS pct_no_speed,
       ROUND(100.0 * AVG((release_spin_rate IS NULL)::int), 2) AS pct_no_spin,
       ROUND(100.0 * AVG((pfx_z             IS NULL)::int), 2) AS pct_no_movement,
       ROUND(100.0 * AVG((release_extension IS NULL)::int), 2) AS pct_no_extension,
       ROUND(100.0 * AVG((arm_angle         IS NULL)::int), 2) AS pct_no_arm_angle,
       ROUND(100.0 * AVG((pitch_type        IS NULL)::int), 2) AS pct_no_pitch_type
FROM pitches
GROUP BY game_year
ORDER BY game_year;

-- 5. Pitch mix: share of each pitch type, with average speed and spin.
--    Four-seam fastballs (FF) should be the most common, around 93-95 mph.
SELECT pitch_type,
       pitch_name,
       COUNT(*)                                            AS pitches,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)  AS pct,
       ROUND(AVG(release_speed)::numeric, 1)               AS avg_mph,
       ROUND(AVG(release_spin_rate)::numeric, 0)           AS avg_rpm
FROM pitches
GROUP BY pitch_type, pitch_name
ORDER BY pitches DESC;

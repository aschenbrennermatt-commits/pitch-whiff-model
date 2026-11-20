-- =============================================================================
-- 06_check_features.sql
-- Sanity checks on model_swings. Compare each result with the comment above it.
--     psql -P pager=off -d whiff -f sql/06_check_features.sql
-- =============================================================================

-- 1. How many swings survived the filters, and the whiff rate, by season and group.
--    Expect roughly 300k+ swings per season in total, and whiff rates around
--    17-18% for fastballs, 30-32% for breaking balls, 29-31% for off-speed.
SELECT game_year,
       pitch_group,
       COUNT(*)                         AS swings,
       ROUND(100.0 * AVG(whiff), 1)     AS whiff_pct
FROM model_swings
GROUP BY game_year, pitch_group
ORDER BY game_year, pitch_group;

-- 2. Share of all swings that survived the filters.
--    Expect over 90% with full seasons. Most of the loss is pitchers with
--    no primary fastball that season (fewer than 25 FF/SI/FC), plus bunts,
--    rare pitch types and missing tracking values.
WITH all_swings AS (
    SELECT COUNT(*) AS n
    FROM pitches
    WHERE description IN ('swinging_strike', 'swinging_strike_blocked',
                          'foul', 'foul_tip', 'hit_into_play')
)
SELECT a.n                       AS all_swings,
       (SELECT COUNT(*) FROM model_swings) AS kept,
       ROUND(100.0 * (SELECT COUNT(*) FROM model_swings) / a.n, 1) AS pct_kept
FROM all_swings a;

-- 3. Average features by pitch type. Things that should be true:
--    * FF: ~94 mph, ~16 in of ride (ivb_in), arm-side run (hb_in > 0),
--          VAA around -4.5 to -5 (flattest of all pitches)
--    * SI: less ride and more arm-side run than FF
--    * SL / ST: glove-side break (hb_in < 0); ST much more than SL
--    * CU / KC: big negative ivb_in, steepest VAA
--    * CH / FS: velo_diff around -8 to -10 mph
SELECT pitch_group,
       pitch_type,
       COUNT(*)                                AS swings,
       ROUND(100.0 * AVG(whiff), 1)            AS whiff_pct,
       ROUND(AVG(velo)::numeric, 1)            AS velo,
       ROUND(AVG(ivb_in)::numeric, 1)          AS ivb_in,
       ROUND(AVG(hb_in)::numeric, 1)           AS hb_in,
       ROUND(AVG(spin_rate)::numeric, 0)       AS spin,
       ROUND(AVG(vaa)::numeric, 2)             AS vaa,
       ROUND(AVG(velo_diff)::numeric, 1)       AS velo_diff
FROM model_swings
GROUP BY pitch_group, pitch_type
ORDER BY pitch_group, swings DESC;

-- 4. The two "direction" conventions, checked by handedness.
--    hb_in for FF should be POSITIVE for both lefties and righties (arm side),
--    and plate_x_away for sliders should be POSITIVE for same-handed batters
--    (sliders are thrown away from same-side hitters).
SELECT p_throws, stand,
       ROUND(AVG(hb_in)        FILTER (WHERE pitch_type = 'FF')::numeric, 1) AS ff_hb_in,
       ROUND(AVG(plate_x_away) FILTER (WHERE pitch_type = 'SL')::numeric, 2) AS sl_plate_x_away
FROM model_swings
GROUP BY p_throws, stand
ORDER BY p_throws, stand;

-- 5. Nothing missing (all should be 0).
SELECT COUNT(*) FILTER (WHERE vaa IS NULL)          AS null_vaa,
       COUNT(*) FILTER (WHERE velo_diff IS NULL)    AS null_velo_diff,
       COUNT(*) FILTER (WHERE plate_z_zone IS NULL) AS null_zone
FROM model_swings;

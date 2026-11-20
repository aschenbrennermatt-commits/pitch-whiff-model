-- =============================================================================
-- 04_pitcher_fastball.sql
-- One row per pitcher per season: the averages of his PRIMARY fastball.
-- Step 05 compares every pitch to this, as the stand-in for tunnelling
-- ("how different is this pitch from the fastball the hitter is expecting?").
--
-- Primary fastball = whichever of four-seam (FF), sinker (SI) or cutter (FC)
-- he threw most that season, with at least 25 of them.
--
-- Direction convention used from here on: horizontal values are flipped for
-- right-handed pitchers so that POSITIVE = ARM SIDE for everyone. Statcast
-- records them from the catcher's view, so a righty's arm-side run is negative.
--
--     psql -d whiff -f sql/04_pitcher_fastball.sql
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS pitcher_fastball;

CREATE TABLE pitcher_fastball AS
WITH fastballs AS (
    SELECT pitcher,
           game_year,
           pitch_type,
           COUNT(*)                                   AS n,
           AVG(release_speed)                         AS fb_velo,
           AVG(pfx_z * 12)                            AS fb_ivb_in,
           AVG(pfx_x * 12 * CASE WHEN p_throws = 'R' THEN -1 ELSE 1 END) AS fb_hb_in,
           AVG(release_pos_z)                         AS fb_rel_height,
           AVG(release_pos_x * CASE WHEN p_throws = 'R' THEN -1 ELSE 1 END) AS fb_rel_side
    FROM pitches
    WHERE pitch_type IN ('FF', 'SI', 'FC')
      AND release_speed IS NOT NULL
      AND pfx_x IS NOT NULL
    GROUP BY pitcher, game_year, pitch_type
    HAVING COUNT(*) >= 25
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY pitcher, game_year
                              ORDER BY n DESC, pitch_type) AS rn
    FROM fastballs
)
SELECT pitcher,
       game_year,
       pitch_type AS fb_type,
       n          AS fb_n,
       fb_velo, fb_ivb_in, fb_hb_in, fb_rel_height, fb_rel_side
FROM ranked
WHERE rn = 1;

ALTER TABLE pitcher_fastball ADD PRIMARY KEY (pitcher, game_year);

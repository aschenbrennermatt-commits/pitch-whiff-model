-- =============================================================================
-- 05_model_swings.sql
-- Builds model_swings: one row per SWING, with the target (whiff) and every
-- model feature. This is the table the notebooks read in step 3.
--
-- Run after 04_pitcher_fastball.sql:
--     psql -d whiff -f sql/05_model_swings.sql
--
-- Decisions (also logged in docs/data_notes.md):
--   * Swings only. A whiff is a swinging strike (incl. blocked); contact is a
--     foul, foul tip or ball in play. Bunts are excluded.
--   * Three pitch groups, each modelled separately in step 3.
--     Rare types (knuckleball, eephus, "Other", pitchout, screwball,
--     slow curve, unknown) and untracked pitches are dropped.
--   * Horizontal values: POSITIVE = ARM SIDE (lefties and righties on one scale).
--   * Location: plate_x_away is POSITIVE = AWAY from the batter;
--     plate_z_zone is 0 at the bottom of the batter's zone and 1 at the top.
--   * Pitches from a pitcher-season with no primary fastball (step 04) drop out.
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS model_swings;

CREATE TABLE model_swings AS
WITH swings AS (
    SELECT p.*,
           CASE WHEN p.p_throws = 'R' THEN -1 ELSE 1 END AS arm,   -- flips righties
           CASE WHEN p.stand    = 'R' THEN  1 ELSE -1 END AS away  -- flips lefty batters
    FROM pitches p
    WHERE p.description IN ('swinging_strike', 'swinging_strike_blocked',
                            'foul', 'foul_tip', 'hit_into_play')
      AND COALESCE(p.events, '') NOT IN ('sac_bunt', 'sac_bunt_double_play')
      AND p.pitch_type IN ('FF','SI','FC',  'SL','ST','CU','KC','SV',  'CH','FS','FO')
      -- every feature must be present
      AND p.release_speed IS NOT NULL AND p.release_spin_rate IS NOT NULL
      AND p.spin_axis     IS NOT NULL AND p.pfx_x IS NOT NULL AND p.pfx_z IS NOT NULL
      AND p.release_pos_x IS NOT NULL AND p.release_pos_z IS NOT NULL
      AND p.release_extension IS NOT NULL AND p.arm_angle IS NOT NULL
      AND p.vy0 IS NOT NULL AND p.vz0 IS NOT NULL AND p.ay IS NOT NULL AND p.az IS NOT NULL
      AND p.plate_x IS NOT NULL AND p.plate_z IS NOT NULL
      AND p.sz_top > p.sz_bot
),
-- Vertical approach angle: the angle the pitch is travelling at as it reaches
-- the front of home plate (y = 17/12 ft), worked out from Statcast's
-- release velocity (vy0, vz0) and acceleration (ay, az), measured at y = 50 ft.
-- Flatter (closer to 0) = harder to get on top of, especially for high fastballs.
approach AS (
    SELECT s.*,
           -SQRT(s.vy0 ^ 2 - 2 * s.ay * (50 - 17.0 / 12)) AS vy_f
    FROM swings s
),
approach2 AS (
    SELECT a.*,
           a.vz0 + a.az * ((a.vy_f - a.vy0) / a.ay) AS vz_f
    FROM approach a
)
SELECT
    -- identifiers and split
    a.game_pk, a.at_bat_number, a.pitch_number,
    a.game_year, a.game_date, a.pitcher, a.batter,
    a.pitch_type,
    CASE WHEN a.pitch_type IN ('FF','SI','FC')                THEN 'fastball'
         WHEN a.pitch_type IN ('SL','ST','CU','KC','SV')      THEN 'breaking'
         ELSE 'offspeed' END                                   AS pitch_group,

    -- target
    CASE WHEN a.description IN ('swinging_strike', 'swinging_strike_blocked')
         THEN 1 ELSE 0 END                                     AS whiff,

    -- pitch traits
    a.release_speed                                            AS velo,
    a.pfx_z * 12                                               AS ivb_in,       -- induced vertical break
    a.pfx_x * 12 * a.arm                                       AS hb_in,        -- horizontal break, + = arm side
    a.release_spin_rate                                        AS spin_rate,
    CASE WHEN a.p_throws = 'L' THEN 360 - a.spin_axis
         ELSE a.spin_axis END                                  AS spin_axis,    -- lefties mirrored to righty scale
    -DEGREES(ATAN(a.vz_f / a.vy_f))                            AS vaa,          -- vertical approach angle
    a.release_extension                                        AS extension,
    a.release_pos_z                                            AS rel_height,
    a.release_pos_x * a.arm                                    AS rel_side,     -- + = arm side
    a.arm_angle,

    -- difference from the pitcher's primary fastball (tunnelling stand-in)
    a.release_speed      - f.fb_velo                           AS velo_diff,
    a.pfx_z * 12         - f.fb_ivb_in                         AS ivb_diff,
    a.pfx_x * 12 * a.arm - f.fb_hb_in                          AS hb_diff,
    a.release_pos_z      - f.fb_rel_height                     AS rel_height_diff,
    a.release_pos_x * a.arm - f.fb_rel_side                    AS rel_side_diff,

    -- location and situation (controls)
    a.plate_x * a.away                                         AS plate_x_away,
    (a.plate_z - a.sz_bot) / (a.sz_top - a.sz_bot)             AS plate_z_zone,
    a.balls,
    a.strikes,
    CASE WHEN a.p_throws = a.stand THEN 1 ELSE 0 END           AS same_hand,
    a.p_throws,
    a.stand
FROM approach2 a
JOIN pitcher_fastball f
  ON f.pitcher = a.pitcher AND f.game_year = a.game_year;

ALTER TABLE model_swings ADD PRIMARY KEY (game_pk, at_bat_number, pitch_number);
CREATE INDEX idx_model_swings_group_year ON model_swings (pitch_group, game_year);
ANALYZE model_swings;

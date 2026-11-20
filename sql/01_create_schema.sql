-- =============================================================================
-- 01_create_schema.sql
-- Creates the two tables for the pitch whiff project.
--
-- First create the database once (in Terminal):
--     createdb whiff
-- Then, from the repo root:
--     psql -d whiff -f sql/01_create_schema.sql
--
-- Safe to re-run: it drops and recreates the tables (and any data in them).
-- =============================================================================

\set ON_ERROR_STOP on

DROP TABLE IF EXISTS pitches;
DROP TABLE IF EXISTS pitchers;

-- One row per pitcher. Statcast's MLBAM player id is the key.
CREATE TABLE pitchers (
    pitcher_id    INTEGER PRIMARY KEY,
    pitcher_name  TEXT NOT NULL            -- "Last, First"
);

-- One row per pitch, regular season only.
-- A pitch is identified by its game, the plate appearance within the game,
-- and the pitch number within that plate appearance.
CREATE TABLE pitches (
    game_pk            INTEGER  NOT NULL,
    at_bat_number      SMALLINT NOT NULL,
    pitch_number       SMALLINT NOT NULL,
    game_date          DATE     NOT NULL,
    game_year          SMALLINT NOT NULL,
    pitcher            INTEGER  NOT NULL REFERENCES pitchers (pitcher_id),
    batter             INTEGER  NOT NULL,
    p_throws           CHAR(1),            -- pitcher's hand: R / L
    stand              CHAR(1),            -- batter's side: R / L

    pitch_type         TEXT,               -- code, e.g. FF, SL, CH
    pitch_name         TEXT,               -- e.g. 4-Seam Fastball

    -- Pitch physics (units: mph, rpm, degrees, feet; pfx in feet)
    release_speed      REAL,
    release_spin_rate  REAL,
    spin_axis          REAL,
    pfx_x              REAL,               -- horizontal movement vs. a spinless pitch
    pfx_z              REAL,               -- vertical movement ("induced vertical break")
    release_pos_x      REAL,
    release_pos_y      REAL,
    release_pos_z      REAL,
    release_extension  REAL,
    arm_angle          REAL,
    vx0                REAL,               -- velocity and acceleration components,
    vy0                REAL,               -- used later to work out the pitch's
    vz0                REAL,               -- approach angle at the plate
    ax                 REAL,
    ay                 REAL,
    az                 REAL,

    -- Location and game state
    plate_x            REAL,
    plate_z            REAL,
    sz_top             REAL,
    sz_bot             REAL,
    zone               SMALLINT,
    balls              SMALLINT,
    strikes            SMALLINT,
    outs_when_up       SMALLINT,
    inning             SMALLINT,

    -- Outcome
    description        TEXT,               -- e.g. swinging_strike, foul, ball
    type               CHAR(1),            -- B / S / X (ball, strike, in play)
    events             TEXT,               -- result of the plate appearance, if it ended
    bb_type            TEXT,               -- batted-ball type, if in play
    delta_run_exp      REAL,

    PRIMARY KEY (game_pk, at_bat_number, pitch_number)
);

-- Most queries filter by season, pitcher or pitch type.
CREATE INDEX idx_pitches_year       ON pitches (game_year);
CREATE INDEX idx_pitches_pitcher    ON pitches (pitcher);
CREATE INDEX idx_pitches_pitch_type ON pitches (pitch_type);

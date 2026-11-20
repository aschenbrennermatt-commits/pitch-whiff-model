# Data notes and decisions log

## Step 1: load (2026-11-19)
- Source: MLB Statcast pitch-level data via `pybaseball` (Baseball Savant), 2023–2025.
- Regular season only (`game_type = 'R'`); spring training and postseason dropped.
- Loaded: 2023 720,684 pitches (2,430 games); 2024 711,899 (2,429 games); 2025 712,528 (2,430 games).
- Primary key `(game_pk, at_bat_number, pitch_number)`; no duplicate pitches found.
- Missing tracking values under 1.5% per column; 8,302 pitches (0.4%) have no pitch type.

## Step 2: features (2026-11-19)
**Target.** Built on swings only. Whiff = `swinging_strike` or `swinging_strike_blocked`.
Contact = `foul`, `foul_tip`, `hit_into_play`. Foul tips count as contact (the bat touched the ball).

**Excluded.**
- Bunts: `foul_bunt`, `missed_bunt`, `bunt_foul_tip`, and balls in play recorded as `sac_bunt`. Bunt singles can't be separated with the kept columns; they are a tiny share.
- Rare or non-competitive pitch types: knuckleball, eephus, "Other" (mostly position players pitching), pitchout, screwball, slow curve, unknown, and untracked pitches.
- Swings with any missing feature value.
- Pitcher-seasons with no primary fastball (fewer than 25 four-seamers, sinkers or cutters).

**Pitch groups, modelled separately** (because what a trait does depends on the pitch, e.g. spin helps a four-seamer's ride but a changeup wants less):
- Fastball: FF, SI, FC
- Breaking: SL, ST, CU, KC, SV
- Off-speed: CH, FS, FO

**Location and count are included as controls** (option A), so a pitch's traits are judged at a given location rather than getting credit for where it was thrown.

**Direction conventions.**
- Horizontal break and release side: positive = arm side, for both hands (Statcast stores them from the catcher's view, so righties were flipped).
- Spin axis: lefties mirrored (360 − axis) onto the righty scale.
- `plate_x_away`: positive = away from the batter. `plate_z_zone`: 0 = bottom of the batter's zone, 1 = top.

**Derived features.**
- `ivb_in`, `hb_in`: movement in inches (Statcast `pfx` × 12).
- `vaa`: vertical approach angle at the front of the plate (y = 17/12 ft), from release velocity and acceleration.
- `*_diff`: each pitch minus the pitcher's primary-fastball average for that season (velocity, vertical break, horizontal break, release height, release side). A stand-in for tunnelling; true tunnelling (pitch paths at the batter's decision point, by sequence) is a possible extension.

**Known limitation.** The primary-fastball averages use the whole season, including pitches after the one being scored. They describe the pitcher's arsenal, not outcomes, so they don't leak the target, but a real-time version would use only earlier pitches.

**Tested** on 10-day samples from each season: all direction conventions checked by handedness, approach angles in the expected range (four-seam about −4.7°, curveball about −9.7°), no missing values.

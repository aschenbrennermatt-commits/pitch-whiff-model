"""
01_download_statcast.py
Downloads MLB Statcast pitch data (regular season only) and writes one CSV
per season to data/raw/, ready for sql/02_load_data.sql.

Run from the repo root, with the `whiff` conda env active:
    python scripts/01_download_statcast.py            # 2023, 2024, 2025
    python scripts/01_download_statcast.py --test     # one week only, to check it works

Downloads one month at a time and saves each month to data/raw/parts/.
If the download stops partway (Wi-Fi drop, laptop sleeps), just run it again:
months already saved are skipped.

Outputs:
    data/raw/pitches_<year>.csv   one row per pitch
    data/raw/pitchers.csv         one row per pitcher (id + name)
"""

import argparse
from pathlib import Path

import pandas as pd
from pybaseball import statcast

RAW = Path("data/raw")
PARTS = RAW / "parts"

# Columns kept, in the same order as the pitches table in sql/01_create_schema.sql.
# Statcast has ~119 columns; these are the ones the project needs.
KEEP = [
    # identifiers
    "game_pk", "at_bat_number", "pitch_number", "game_date", "game_year",
    "pitcher", "batter", "p_throws", "stand",
    # pitch type
    "pitch_type", "pitch_name",
    # pitch physics (the model's features)
    "release_speed", "release_spin_rate", "spin_axis", "pfx_x", "pfx_z",
    "release_pos_x", "release_pos_y", "release_pos_z", "release_extension", "arm_angle",
    "vx0", "vy0", "vz0", "ax", "ay", "az",
    # location and count
    "plate_x", "plate_z", "sz_top", "sz_bot", "zone",
    "balls", "strikes", "outs_when_up", "inning",
    # outcome (the target comes from `description`)
    "description", "type", "events", "bb_type", "delta_run_exp",
]

# Months that can contain regular-season games (late March to early October).
MONTHS = [(3, 15, 31), (4, 1, 30), (5, 1, 31), (6, 1, 30), (7, 1, 31),
          (8, 1, 31), (9, 1, 30), (10, 1, 10)]


def download_month(year, month, first_day, last_day):
    part = PARTS / f"{year}_{month:02d}.parquet"
    if part.exists():
        print(f"  {year}-{month:02d}: already saved, skipping")
        return pd.read_parquet(part)

    start = f"{year}-{month:02d}-{first_day:02d}"
    end = f"{year}-{month:02d}-{last_day:02d}"
    print(f"  {year}-{month:02d}: downloading {start} to {end} ...")
    df = statcast(start_dt=start, end_dt=end, verbose=False, parallel=True)

    if df is None or df.empty:
        df = pd.DataFrame(columns=KEEP + ["player_name"])
    else:
        df = df[df["game_type"] == "R"]          # regular season only
        df = df[KEEP + ["player_name"]]

    df.to_parquet(part, index=False)
    print(f"  {year}-{month:02d}: {len(df):,} pitches saved")
    return df


def save_season(df, year):
    key = ["game_pk", "at_bat_number", "pitch_number"]
    before = len(df)
    df = df.drop_duplicates(subset=key)
    if len(df) < before:
        print(f"  removed {before - len(df):,} duplicate pitches")

    df = df.sort_values(["game_date"] + key)
    out = RAW / f"pitches_{year}.csv"
    df[KEEP].to_csv(out, index=False)
    print(f"{year}: {len(df):,} pitches written to {out}")


def save_pitchers(all_parts):
    # player_name in Statcast pitch data is the pitcher's name, "Last, First".
    p = (pd.concat(all_parts)[["pitcher", "player_name"]]
         .dropna()
         .drop_duplicates(subset="pitcher", keep="last")   # latest spelling wins
         .rename(columns={"pitcher": "pitcher_id", "player_name": "pitcher_name"})
         .sort_values("pitcher_id"))
    p.to_csv(RAW / "pitchers.csv", index=False)
    print(f"pitchers: {len(p):,} written to {RAW / 'pitchers.csv'}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--seasons", nargs="+", type=int, default=[2023, 2024, 2025])
    parser.add_argument("--test", action="store_true",
                        help="download one week of June 2025 only")
    args = parser.parse_args()

    PARTS.mkdir(parents=True, exist_ok=True)
    all_parts = []

    if args.test:
        print("TEST MODE: 2025-06-01 to 2025-06-07")
        df = statcast(start_dt="2025-06-01", end_dt="2025-06-07", verbose=False)
        df = df[df["game_type"] == "R"][KEEP + ["player_name"]]
        all_parts.append(df)
        save_season(df, 2025)
    else:
        for year in args.seasons:
            print(f"Season {year}")
            parts = [download_month(year, m, a, b) for m, a, b in MONTHS]
            season = pd.concat([p for p in parts if not p.empty])
            all_parts.append(season)
            save_season(season, year)

    save_pitchers(all_parts)
    print("Done. Next: run sql/01_create_schema.sql, then sql/02_load_data.sql")


if __name__ == "__main__":
    main()

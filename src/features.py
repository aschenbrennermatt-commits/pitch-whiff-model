"""Feature definitions shared by the dashboard.

Must match notebooks/01_models.ipynb, which trained the saved models.
"""

import numpy as np
import pandas as pd

SWING_COLUMNS = [
    "game_year", "pitcher", "pitch_type", "pitch_group", "whiff",
    "velo", "ivb_in", "hb_in", "spin_rate", "spin_axis", "vaa", "extension",
    "rel_height", "rel_side", "arm_angle",
    "velo_diff", "ivb_diff", "hb_diff", "rel_height_diff", "rel_side_diff",
    "plate_x_away", "plate_z_zone", "balls", "strikes", "same_hand",
]


def add_features(df: pd.DataFrame) -> pd.DataFrame:
    """Add the Python-side features used in training."""
    df = df.copy()
    rad = np.radians(df["spin_axis"])
    df["spin_axis_sin"] = np.sin(rad)
    df["spin_axis_cos"] = np.cos(rad)
    df["plate_x_sq"] = df["plate_x_away"] ** 2
    df["plate_z_sq"] = (df["plate_z_zone"] - 0.5) ** 2
    return df


def model_input(df: pd.DataFrame, features: list, pitch_types: list) -> pd.DataFrame:
    """Select model columns and give pitch_type the categories seen in training."""
    out = df[features].copy()
    out["pitch_type"] = pd.Categorical(out["pitch_type"], categories=pitch_types)
    return out

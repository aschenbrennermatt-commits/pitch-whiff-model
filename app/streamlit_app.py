"""
Pitch Whiff Model dashboard.

Run from the repo root, with the `whiff` env active and PostgreSQL running:
    streamlit run app/streamlit_app.py

Needs models/whiff_models.joblib (made by notebooks/01_models.ipynb).
"""

import os
import sys
from pathlib import Path
from urllib.parse import quote_plus

import joblib
import pandas as pd
import streamlit as st
from sqlalchemy import create_engine, text

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from src.features import SWING_COLUMNS, add_features, model_input  # noqa: E402

st.set_page_config(page_title="Pitch Whiff Model", layout="wide")

# -----------------------------------------------------------------------------
# SQL
# -----------------------------------------------------------------------------

# YOUR QUERY. Return one row per pitcher for the chosen season, with these
# three columns, sorted by pitcher_name:
#     pitcher_id, pitcher_name, swings
# Only include pitchers with at least :min_swings swings that season.
# :season and :min_swings are PARAMETERS: write them exactly like that in the
# SQL and the app fills in the values (e.g. WHERE game_year = :season).
PITCHER_LIST_SQL = """
SELECT pitchers.pitcher_id,
       pitchers.pitcher_name,
       COUNT(*) AS swings
FROM model_swings
JOIN pitchers ON pitchers.pitcher_id = model_swings.pitcher
WHERE model_swings.game_year = :season
GROUP BY pitchers.pitcher_id, pitchers.pitcher_name
HAVING COUNT(*) >= :min_swings
ORDER BY pitchers.pitcher_name;
"""

SWINGS_SQL = f"""
SELECT {", ".join(SWING_COLUMNS)}
FROM model_swings
WHERE pitcher = :pitcher AND game_year = :season;
"""

LEAGUE_SQL = """
SELECT pitch_type, AVG(whiff) AS league_whiff
FROM model_swings
WHERE game_year = :season
GROUP BY pitch_type;
"""

PITCH_NAMES = {
    "FF": "Four-seam", "SI": "Sinker", "FC": "Cutter",
    "SL": "Slider", "ST": "Sweeper", "CU": "Curveball", "KC": "Knuckle curve", "SV": "Slurve",
    "CH": "Changeup", "FS": "Splitter", "FO": "Forkball",
}

# What-if changes tested for the "best single change" chart: (feature, step, label)
CHANGES = [
    ("velo", 1.0, "+1 mph velocity"),
    ("ivb_in", 2.0, "+2 in vertical break"),
    ("ivb_in", -2.0, "-2 in vertical break"),
    ("hb_in", 2.0, "+2 in arm-side break"),
    ("hb_in", -2.0, "+2 in glove-side break"),
    ("spin_rate", 100.0, "+100 rpm spin"),
    ("extension", 0.3, "+0.3 ft extension"),
    ("vaa", 0.5, "+0.5 deg flatter approach"),
]
LINKED_DIFF = {"velo": "velo_diff", "ivb_in": "ivb_diff", "hb_in": "hb_diff"}


# -----------------------------------------------------------------------------
# Loading
# -----------------------------------------------------------------------------

@st.cache_resource
def load_models():
    return joblib.load(ROOT / "models" / "whiff_models.joblib")


@st.cache_resource
def get_engine(password: str):
    url = os.environ.get("WHIFF_DB_URL")  # optional override, e.g. for testing
    if not url:
        url = f"postgresql+psycopg://postgres:{quote_plus(password)}@localhost:5432/whiff"
    return create_engine(url)


@st.cache_data(show_spinner=False)
def run_query(_engine, sql: str, **params) -> pd.DataFrame:
    with _engine.connect() as conn:
        return pd.read_sql(text(sql), conn, params=params)


def predict(swings: pd.DataFrame, saved: dict) -> pd.Series:
    """Predicted whiff probability for each swing, using its pitch group's LightGBM model."""
    features = saved["numeric"] + saved["categorical"]
    out = pd.Series(index=swings.index, dtype=float)
    for group, part in swings.groupby("pitch_group"):
        m = saved["models"][group]
        out.loc[part.index] = m["lightgbm"].predict_proba(
            model_input(part, features, m["pitch_types"]))[:, 1]
    return out


def apply_change(swings: pd.DataFrame, feature: str, step: float) -> pd.DataFrame:
    changed = swings.copy()
    changed[feature] = changed[feature] + step
    if feature in LINKED_DIFF:
        changed[LINKED_DIFF[feature]] = changed[LINKED_DIFF[feature]] + step
    return add_features(changed)


# -----------------------------------------------------------------------------
# Page
# -----------------------------------------------------------------------------

st.title("Pitch Whiff Model")
st.caption("How likely is each of a pitcher's pitches to get a swing and miss, "
           "and which change to the pitch would help most? "
           "LightGBM models trained on 2023-2024 MLB Statcast swings, tested on 2025.")

saved = load_models()

with st.sidebar:
    if os.environ.get("WHIFF_DB_URL"):
        password = ""
    else:
        password = st.text_input("PostgreSQL password", type="password")
        if not password:
            st.info("Enter your database password to start.")
            st.stop()
    engine = get_engine(password)
    season = st.selectbox("Season", [2025, 2024, 2023])
    min_swings = st.slider("Minimum swings", 50, 1000, 200, step=50)

if "Write your query here" in PITCHER_LIST_SQL:
    st.error("Write the pitcher list query (PITCHER_LIST_SQL) in app/streamlit_app.py first.")
    st.stop()

pitchers = run_query(engine, PITCHER_LIST_SQL, season=season, min_swings=min_swings)
if pitchers.empty:
    st.warning("No pitchers match. Lower the minimum swings.")
    st.stop()

with st.sidebar:
    label = pitchers["pitcher_name"] + "  (" + pitchers["swings"].astype(str) + " swings)"
    choice = st.selectbox("Pitcher", pitchers.index, format_func=lambda i: label[i])
pitcher_id = int(pitchers.loc[choice, "pitcher_id"])
pitcher_name = pitchers.loc[choice, "pitcher_name"]

swings = add_features(run_query(engine, SWINGS_SQL, pitcher=pitcher_id, season=season))
league = run_query(engine, LEAGUE_SQL, season=season).set_index("pitch_type")["league_whiff"]
swings["expected"] = predict(swings, saved)

# --- Arsenal table -----------------------------------------------------------
st.subheader(f"{pitcher_name}, {season}")

arsenal = swings.groupby("pitch_type").agg(
    swings=("whiff", "size"),
    actual_whiff=("whiff", "mean"),
    expected_whiff=("expected", "mean"),
    velo=("velo", "mean"), ivb_in=("ivb_in", "mean"), hb_in=("hb_in", "mean"),
    spin_rate=("spin_rate", "mean"), vaa=("vaa", "mean"), extension=("extension", "mean"),
)
arsenal["whiff_plus"] = 100 * arsenal["expected_whiff"] / arsenal.index.map(league)
arsenal = arsenal.sort_values("swings", ascending=False)

table = pd.DataFrame({
    "Pitch": [PITCH_NAMES.get(p, p) for p in arsenal.index],
    "Swings": arsenal["swings"],
    "Actual whiff %": (100 * arsenal["actual_whiff"]).round(1),
    "Model whiff %": (100 * arsenal["expected_whiff"]).round(1),
    "Whiff+": arsenal["whiff_plus"].round(0).astype(int),
    "Velo (mph)": arsenal["velo"].round(1),
    "Vert. break (in)": arsenal["ivb_in"].round(1),
    "Horiz. break (in, + arm side)": arsenal["hb_in"].round(1),
    "Spin (rpm)": arsenal["spin_rate"].round(0).astype(int),
    "Approach angle (deg)": arsenal["vaa"].round(2),
    "Extension (ft)": arsenal["extension"].round(2),
}).set_index("Pitch")
st.dataframe(table)
st.caption("**Model whiff %** is the model's prediction for these exact swings (same locations and counts). "
           "**Whiff+** compares it with the league average for that pitch type: 100 = average, 120 = 20% more whiffs. "
           "A big gap between actual and model whiff % on few swings is usually luck.")

# --- What-if ---------------------------------------------------------------
st.subheader("What would help most?")
pitch = st.selectbox("Pitch", arsenal.index, format_func=lambda p: PITCH_NAMES.get(p, p))
these = swings[swings["pitch_type"] == pitch]
base = these["expected"].mean()

rows = []
for feature, step, change_label in CHANGES:
    new = predict(apply_change(these, feature, step), saved).mean()
    rows.append({"change": change_label, "whiff_points": 100 * (new - base)})
best = pd.DataFrame(rows).sort_values("whiff_points", ascending=False).set_index("change")
st.bar_chart(best, horizontal=True, y_label="", x_label="change in model whiff % (points)")
st.caption(f"Each bar applies one change to every {PITCH_NAMES.get(pitch, pitch).lower()} "
           f"{pitcher_name} threw on a swing, keeping location and count as they were, "
           f"and re-runs the model (baseline {100 * base:.1f}%).")

with st.expander("Try your own combination"):
    c1, c2, c3 = st.columns(3)
    d_velo = c1.slider("Velocity change (mph)", -3.0, 3.0, 0.0, 0.5)
    d_ivb = c2.slider("Vertical break change (in)", -4.0, 4.0, 0.0, 0.5)
    d_hb = c3.slider("Horizontal break change (in, + arm side)", -4.0, 4.0, 0.0, 0.5)
    d_spin = c1.slider("Spin change (rpm)", -300, 300, 0, 25)
    d_ext = c2.slider("Extension change (ft)", -0.5, 0.5, 0.0, 0.1)
    d_vaa = c3.slider("Approach angle change (deg, + flatter)", -1.0, 1.0, 0.0, 0.1)
    custom = these.copy()
    for feature, step in [("velo", d_velo), ("ivb_in", d_ivb), ("hb_in", d_hb),
                          ("spin_rate", d_spin), ("extension", d_ext), ("vaa", d_vaa)]:
        if step:
            custom = apply_change(custom, feature, step)
    new = predict(custom, saved).mean()
    st.metric("Model whiff %", f"{100 * new:.1f}%", f"{100 * (new - base):+.1f} points")

with st.expander("Limitations"):
    st.markdown("""
- **Predictions, not guarantees.** The model learned patterns across MLB swings; it can't promise how one pitcher's hitters will react.
- **Traits move together in real life.** More vertical break usually also flattens the approach angle; here each slider moves only its own feature.
- **Approach angle overlaps with location** (correlation about 0.78 for four-seamers), so its effect is likely overstated.
- **Changes far outside what MLB pitchers actually throw** are guesses: the model has no data there.
- **Nothing about the hitter** (skill, expectations, timing) is in the model.
""")

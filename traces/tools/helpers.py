import pandas as pd
import os, re, json
import numpy as np
import math

def _safe_div(a, b):
    return a / b if b not in (0, np.nan) else np.nan


def summarize_single_config(
    df: pd.DataFrame,
    *,
    runtime_col: str = "Runtime (s)",
    run_col: str = "database",      # identifies each workload run (e.g., Run 1..5)
    query_col: str = "query_id"     # numeric query id (e.g., 1..99)
) -> pd.DataFrame:
    """
    Returns one row of metrics:

    Mean Query Runtime Across Workloads (s)
        - Avg, Std, P50, P99 of mean runtime across workload runs

    Repeatability Across Queries
        - Std (s): Avg, P50, P99 (Bessel-corrected)
        - CV (%):  Avg, P50, P99
    """
    sub = df[pd.notna(df[runtime_col])].copy()
    if sub.empty:
        return pd.DataFrame([{
            col: np.nan for col in [
                "Mean Runtime Avg (s)", "Mean Runtime Std (s)",
                "Mean Runtime P50 (s)", "Mean Runtime P99 (s)",
                "Std Avg (s)", "Std P50 (s)", "Std P99 (s)",
                "CV Avg (%)", "CV P50 (%)", "CV P99 (%)",
                "Runs", "Queries"
            ]
        }])

    # --- Across Workloads (each run_col = one workload execution)
    per_run = (sub.groupby(run_col)[runtime_col]
                  .agg(run_mean="mean")
                  .reset_index())

    mean_runtimes = per_run["run_mean"].to_numpy()

    avg_mean_runtime_s = np.mean(mean_runtimes)
    std_mean_runtime_s = np.std(mean_runtimes, ddof=1) if len(mean_runtimes) > 1 else np.nan
    p50_mean_runtime_s = np.percentile(mean_runtimes, 50)
    p99_mean_runtime_s = np.percentile(mean_runtimes, 99)

    # --- Across Queries: each query over multiple runs
    qg = sub.groupby(query_col)[runtime_col]
    q_stats = qg.agg(
        q_mean="mean",
        q_std=lambda x: np.std(x, ddof=1) if len(x) == 5 else np.nan
    ).reset_index()
    q_stats = q_stats.dropna(subset=["q_std"]).reset_index(drop=True)

    q_stats["q_cv_percent"] = 100.0 * q_stats["q_std"] / q_stats["q_mean"]

    std_values = q_stats["q_std"].to_numpy()
    cv_values = q_stats["q_cv_percent"].to_numpy()

    avg_std_s = np.mean(std_values)
    p50_std_s = np.percentile(std_values, 50)
    p99_std_s = np.percentile(std_values, 99)

    avg_cv_pct = np.mean(cv_values)
    p50_cv_pct = np.percentile(cv_values, 50)
    p99_cv_pct = np.percentile(cv_values, 99)

    row = {
        "Mean Runtime Avg (s)": avg_mean_runtime_s,
        "Mean Runtime Std (s)": std_mean_runtime_s,
        "Mean Runtime P50 (s)": p50_mean_runtime_s,
        "Mean Runtime P99 (s)": p99_mean_runtime_s,

        "Std Avg (s)": avg_std_s,
        "Std P50 (s)": p50_std_s,
        "Std P99 (s)": p99_std_s,

        "CV Avg (%)": avg_cv_pct,
        "CV P50 (%)": p50_cv_pct,
        "CV P99 (%)": p99_cv_pct,

        "Runs": int(per_run.shape[0]),
        "Queries": int(q_stats.shape[0]),
    }

    return pd.DataFrame([row])


_RUNLOG_RE = re.compile(r"^Workload_log_BASE_(?P<run>\d+)\.ndjson$", re.IGNORECASE)
_QID_RE = re.compile(r"^q(?P<num>\d+)$", re.IGNORECASE)


def load_trino_times(
    root_dir: str,
    *,
    clamp_negative: bool = False,
) -> pd.DataFrame:
    """
    Reads Workload_log_BASE_<run>.ndjson files in `root_dir` (a CLUSTER/SF_X dir).

    Each NDJSON line should contain:
      - query_id (e.g., "q64")
      - "Runtime (s)" (seconds, float)
      - elapsed_s, execution_s, planning_s, resource_waiting_s (optional)

    Returns a DataFrame compatible with summarize_single_config().
    """
    rows = []
    files = []

    if not os.path.isdir(root_dir):
        raise FileNotFoundError(f"root_dir not found: {root_dir}")

    for fname in os.listdir(root_dir):
        m = _RUNLOG_RE.match(fname)
        if m:
            files.append((int(m.group("run")), os.path.join(root_dir, fname)))

    if not files:
        # Return empty df with expected columns
        return pd.DataFrame(columns=[
            "database", "query_id", "Runtime (s)",
            "elapsed_s", "execution_s", "planning_s", "resource_waiting_s",
        ])

    files.sort(key=lambda x: x[0])  # sort by run number

    for run_idx, fpath in files:
        df = pd.read_json(fpath, lines=True)

        df["database"] = f"Run {run_idx}"

        # Normalize query_id "q96" -> 96
        if "query_id" in df.columns:
            def _to_int_qid(x):
                if pd.isna(x):
                    return np.nan
                if isinstance(x, (int, np.integer)):
                    return int(x)
                s = str(x).strip()
                mm = _QID_RE.match(s)
                return int(mm.group("num")) if mm else np.nan

            df["query_id"] = df["query_id"].map(_to_int_qid)

        def _clean_numeric(col: str):
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce")
                df.loc[df[col] < 0, col] = np.nan

        _clean_numeric("Runtime (s)")
        _clean_numeric("elapsed_s")
        _clean_numeric("execution_s")
        _clean_numeric("planning_s")
        _clean_numeric("resource_waiting_s")

        rows.append(df)

    out = pd.concat(rows, ignore_index=True)

    # Stable sort
    if "query_id" in out.columns:
        out = out.sort_values(["database", "query_id"], kind="stable")

    return out.reset_index(drop=True)

def table_1_latex_row_from_table(
    table: pd.DataFrame,
    platform: str,
    dp: int = 3,
) -> str:
    if not isinstance(table, pd.DataFrame) or table.shape[0] != 1:
        raise ValueError("table must be a single-row pandas DataFrame")

    row = table.iloc[0]

    col_order = [
        "Mean Runtime Avg (s)", "Mean Runtime Std (s)",
        "Std Avg (s)", "Std P50 (s)", "Std P99 (s)",
        "CV Avg (%)", "CV P50 (%)", "CV P99 (%)"
    ]

    def fmt(x):
        if x is None or (isinstance(x, float) and (math.isnan(x) or np.isnan(x))):
            return "-"
        return f"{float(x):.{dp}f}"

    values = [fmt(row.get(c, np.nan)) for c in col_order]
    values[0] = "\\hspace{5pt} " + values[0]

    return f"{platform} &&& " + " & ".join(values) + " \\\\"


def compare_config_deltas(baseline_df: pd.DataFrame, compare_df: pd.DataFrame, dp: int = 3) -> pd.DataFrame:
    if not isinstance(baseline_df, pd.DataFrame) or baseline_df.shape[0] != 1:
        raise ValueError("baseline_df must be a single-row DataFrame.")
    if not isinstance(compare_df, pd.DataFrame) or compare_df.shape[0] != 1:
        raise ValueError("compare_df must be a single-row DataFrame.")

    base = baseline_df.iloc[0]
    comp = compare_df.iloc[0]

    # --- Compute deltas ---
    delta_mean_runtime = 100 * (comp["Mean Runtime Avg (s)"] - base["Mean Runtime Avg (s)"])/ base["Mean Runtime Avg (s)"]
    delta_cv_avg = 100 * (comp["CV Avg (%)"] - base["CV Avg (%)"])  / base["CV Avg (%)"]
    delta_cv_p50 = 100 *(comp["CV P50 (%)"] - base["CV P50 (%)"])  / base["CV P50 (%)"]
    delta_cv_p99 = 100 *(comp["CV P99 (%)"] - base["CV P99 (%)"])  / base["CV P99 (%)"]

    # --- Build new dataframe ---
    row = dict(comp)
    row.update({
        "Δ Mean Runtime Avg (s)": delta_mean_runtime,
        "ΔCV Avg (pp)": delta_cv_avg,
        "ΔCV P50 (pp)": delta_cv_p50,
        "ΔCV P99 (pp)": delta_cv_p99,
    })

    # --- Round all numeric values to dp ---
    for k, v in row.items():
        if isinstance(v, (int, float, np.floating)):
            if pd.notna(v):
                row[k] = round(float(v), dp)

    return pd.DataFrame([row])

def table_2_latex_row_from_table(
    table: pd.DataFrame,
    platform: str,
    *,
    isDelta: bool = False,
    factor_name: str | None = None,  # NEW: label like "External metastore"
    dp: int = 3,
) -> str:
    """
    Generate a LaTeX table row for either a BASELINE or DELTA configuration.

    Parameters
    ----------
    table : pd.DataFrame
        Single-row DataFrame (from summarize_single_config or compare_config_deltas)
    platform : str
        Name of the platform (e.g., "AWS", "Azure", etc.)
    isDelta : bool
        If True, print a Δ (delta) comparison row.
        If False, print a baseline gray header row.
    factor_name : str
        Label of the factor (e.g., "External metastore") for delta rows.
    dp : int
        Decimal places for rounding.

    Returns
    -------
    str : LaTeX-formatted table row
    """
    if not isinstance(table, pd.DataFrame) or table.shape[0] != 1:
        raise ValueError("table must be a single-row pandas DataFrame.")

    row = table.iloc[0]

    def _is_missing(x) -> bool:
        if x is None:
            return True
        try:
            return math.isnan(float(x))
        except (TypeError, ValueError):
            return False

    def fmt(x):
        """Standard formatter for non-delta columns."""
        if _is_missing(x):
            return "-"
        return f"{float(x):.{dp}f}"

    def fmt_delta(x):
        """Formatter for delta columns, e.g. $+~15.746$."""
        if _is_missing(x):
            return "-"
        x = float(x)
        if abs(x) < 10**(-dp):
            return "$0$"
        sign = "+" if x > 0 else "-"
        return f"${sign}~{abs(x):.{dp}f}$"

    # --- BASELINE ROW ---
    if not isDelta:
        latex_line = (
            "\\multicolumn{5}{c}{\\rowcolor{gray!25} (Baseline)} & "
            f"{fmt(row.get('Mean Runtime Avg (s)', np.nan))} & "
            "\\\multicolumn{1}{c}{\textbf{—}} & "
            f"{fmt(row.get('CV Avg (%)', np.nan))} & "
            f"{fmt(row.get('CV P50 (%)', np.nan))} & "
            f"{fmt(row.get('CV P99 (%)', np.nan))} & "
            "\\textbf{—} & \\textbf{—} & \\textbf{—} \\\\"
        )

    # --- DELTA ROW ---
    else:
        if factor_name is None:
            raise ValueError("factor_name must be provided for delta (isDelta=True) rows.")

        # Example desired output:
        # & \textbullet\ External metastore & 43.744 & $+~15.746$ & 21.314 & 19.069 &
        #   61.279 & $+~10.479$ & $+~10.524$ & $+~20.221$ \\
        latex_line = (
            f"& \\textbullet {factor_name} & "
            f"{fmt(row.get('Mean Runtime Avg (s)', np.nan))} & "
            f"{fmt_delta(row.get('Δ Mean Runtime Avg (s)', np.nan))} & "
            f"{fmt(row.get('CV Avg (%)', np.nan))} & "
            f"{fmt(row.get('CV P50 (%)', np.nan))} & "
            f"{fmt(row.get('CV P99 (%)', np.nan))} & "
            f"{fmt_delta(row.get('ΔCV Avg (pp)', np.nan))} & "
            f"{fmt_delta(row.get('ΔCV P50 (pp)', np.nan))} & "
            f"{fmt_delta(row.get('ΔCV P99 (pp)', np.nan))} \\\\"
        )

    return latex_line


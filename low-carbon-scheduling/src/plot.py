from typing import List, Dict, Any, Optional
from collections import defaultdict
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from matplotlib.patches import Patch
from src.experiment import ExperimentResult

# Collection of plotting functions used in Main.py

def plot_qpp_vs_oracle_co2_subplot(
    ax: plt.Axes,
    results: List[ExperimentResult],
    *,
    metric: str = "carbon_total_gco2",
    location: str = "",
    variant: str = "",
    show_legend: bool = False,
    legend_size =11,
    color_map = {},
    ticks=True,
):
    if not results:
        raise ValueError("No ExperimentResult objects provided.")

    # Collect results into a DataFrame
    rows = []
    for res in results:
        stats = res.summary()
        stats["scheduler"] = stats.get("scheduler", getattr(res, "scheduler_name", "unknown"))
        stats["label"] = getattr(res, "label", stats.get("label", None))
        rows.append(stats)

    df = pd.DataFrame(rows)

    if metric not in df.columns:
        raise ValueError(
            f"Unknown metric '{metric}'. "
            f"Available keys: {list(df.columns)}"
        )

    method_order = ["FIFO", "GNN", "RF", "Oracle"]

    schedulers_ordered = list(df["scheduler"].unique())

    def _labels_for_scheduler(sub_df, sched_name: str) -> List[str]:
        labels_here = sub_df["label"].dropna().unique().tolist()

        if "fifo" in sched_name.lower():
            if "FIFO" not in labels_here:
                labels_here = ["FIFO"]
        else:
            labels_here = [m for m in method_order if m in labels_here]

        return labels_here

    labels_per_scheduler = {}
    for sched_name in schedulers_ordered:
        sub = df[df["scheduler"] == sched_name]
        labels_per_scheduler[sched_name] = _labels_for_scheduler(sub, sched_name)

    max_n = max((len(v) for v in labels_per_scheduler.values() if v), default=1)

    width = 0.25
    gap = 0.04

    inner_gap = 0.3
    group_gap = 1.1

    scheduler_x = {}
    current_x = 0.0
    prev_is_local = None

    for sched_name in schedulers_ordered:
        is_local = "local" in sched_name.lower()
        if prev_is_local is None:
            scheduler_x[sched_name] = current_x
        else:
            if is_local == prev_is_local:
                current_x += inner_gap
            else:
                current_x += group_gap
            scheduler_x[sched_name] = current_x
        prev_is_local = is_local

    legend_done = set()
    bars_to_label = []
    bar_centers_by_scheduler = defaultdict(list)

    for sched_name in schedulers_ordered:
        sub = df[df["scheduler"] == sched_name]
        labels_here = labels_per_scheduler[sched_name]
        if not labels_here:
            continue

        n = max_n
        total_width = width * n + gap * (n - 1)
        center_x = scheduler_x[sched_name]
        start_x = center_x - total_width / 2 + width / 2

        for j, method in enumerate(labels_here):
            if method == "FIFO":
                m_sub = sub
            else:
                m_sub = sub[sub["label"] == method]

            if m_sub.empty:
                continue

            val = float(m_sub.iloc[0][metric])
            bar_x = start_x + j * (width + gap)

            legend_label = None
            if method != "FIFO" and method not in legend_done:
                legend_label = method
                legend_done.add(method)

            color = color_map.get(method, "#cccccc")
            bars = ax.bar(bar_x, val, width=width, color=color, label=legend_label)
            bars_to_label.extend(bars)
            bar_centers_by_scheduler[sched_name].append(bar_x)

    for bar in bars_to_label:
        height = bar.get_height()
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            height,
            f"{height:.2f}",
            ha="center",
            va="bottom",
            fontsize=14,
        )

    if bars_to_label:
        heights = [b.get_height() for b in bars_to_label]
        min_h, max_h = min(heights), max(heights)
        span = max_h - min_h
        pad = 0.1 * span if span > 0 else (0.1 * max_h if max_h > 0 else 1.0)
        ymin = max(0.0, min_h - pad)
        ymax = max_h + pad
        ax.set_ylim(ymin, ymax)

    xticks = []
    xtick_labels = []
    for sched_name in schedulers_ordered:
        centers = bar_centers_by_scheduler.get(sched_name)
        if not centers:
            continue
        xticks.append(float(np.mean(centers)))
        xtick_labels.append(sched_name)

    pretty_labels = []
    for lbl in xtick_labels:
        if "Local Search" in lbl:
            pretty_labels.append(lbl.replace("Local Search", "Local Search\n"))
        else:
            pretty_labels.append(lbl)

    ax.set_xticks(xticks)
    ax.set_xticklabels(pretty_labels, rotation=0, ha="center", fontsize=16)
    ax.set_ylabel("Total Carbon Emissions (gCO₂)", fontsize=17)
    ax.set_xlabel("Scheduler", fontsize=17)
    ax.tick_params(axis="y", labelsize=16)

    ax.set_title(f"{location}", fontsize=17)
 

    if show_legend:
        ax.legend(fontsize=legend_size, loc="upper right")
    if ticks == False:
            ax.set_xlabel("")
            ax.tick_params(axis="x", which="both", labelbottom=False, size=15)

    
    return ax
    

def plot_ci_over_slots(carbon_profile, max_slots=None, figsize=(10, 4)):
    """
    Plot carbon intensity (gCO2/kWh) as a function of slot index.
    """
    ci = carbon_profile.ci
    if max_slots is not None:
        ci = ci[:max_slots]

    x = np.arange(len(ci))

    plt.figure(figsize=figsize)
    plt.plot(x, ci)
    plt.xlabel("Slot index")
    plt.ylabel("CI (gCO₂/kWh)")
    plt.title("Carbon intensity over slots")
    plt.tight_layout()
    plt.show()

def plot_schedule_with_actual(
    schedule_rows: List[Dict[str, Any]],
    slot_sec: float = 1.0,
    max_queries: Optional[int] = None,
    figsize: tuple = (10, 6),
):
    """
    Visualise a schedule showing both:
      - predicted interval (planned start + pred_slots)
      - realised interval (sequential execution + actual_slots),
    where the machine is blocked for max(pred_slots, actual_slots).
    """
    if not schedule_rows:
        raise ValueError("schedule_rows is empty.")

    rows = sorted(schedule_rows, key=lambda r: r["start_slot"])

    if max_queries is not None:
        rows = rows[:max_queries]
    time_cursor = 0
    for r in rows:
        planned = int(r["start_slot"])
        pred_dur = int(r["pred_slots"])
        actual_dur = int(r["actual_slots"])

        if planned > time_cursor:
            time_cursor = planned

        realised_start = time_cursor
        realised_end = realised_start + actual_dur
        block_slots = max(pred_dur, actual_dur)
        time_cursor = realised_start + block_slots

        r["_realised_start_slot"] = realised_start
        r["_realised_end_slot"] = realised_end
        r["_pred_end_slot"] = r["start_slot"] + r["pred_slots"]

    # Build the plot
    fig, ax = plt.subplots(figsize=figsize)

    y_positions = np.arange(len(rows))

    pred_edge_color = "#377eb8"
    actual_face_color = "#f781bf"

    pred_height = 0.8
    actual_height = 0.4

    for i, r in enumerate(rows):
        start_pred = r["start_slot"] * slot_sec
        end_pred = r["_pred_end_slot"] * slot_sec
        start_real = r["_realised_start_slot"] * slot_sec
        end_real = r["_realised_end_slot"] * slot_sec

        ax.barh(
            y_positions[i],
            end_pred - start_pred,
            left=start_pred,
            height=pred_height,
            facecolor="none",
            edgecolor=pred_edge_color,
            linestyle="--",
            linewidth=1.5,
        )

        ax.barh(
            y_positions[i],
            end_real - start_real,
            left=start_real,
            height=actual_height,
            facecolor=actual_face_color,
            edgecolor="black",
            linewidth=0.5,
            alpha=0.9,
        )

    ax.set_yticks(y_positions)
    ax.set_yticklabels([r["query_id"] for r in rows])
    ax.invert_yaxis()

    ax.set_xlabel("Time (seconds)" if slot_sec != 1.0 else "Time (slots)")
    ax.set_title("Schedule: predicted vs realised execution")

    legend_handles = [
        Patch(
            facecolor="none",
            edgecolor=pred_edge_color,
            linestyle="--",
            linewidth=1.5,
            label="Predicted window",
        ),
        Patch(
            facecolor=actual_face_color,
            edgecolor="black",
            linewidth=0.5,
            label="Realised window",
        ),
    ]
    ax.legend(handles=legend_handles, loc="best")

    plt.tight_layout()
    plt.show()

def plot_overhead_vs_oracle_single_location(
    ax: plt.Axes,
    df_loc: pd.DataFrame,
    *,
    baseline_scenario: str = "Baseline",
    compare_scenario: str = "Low variance",
    schedulers=None,
    models=("GNN", "RF"),
    location_name: str = "",
    show_legend: bool = False,
    color_map = {}
):
    df = df_loc.copy()

    df = df[df["model"].isin(models)]

    if schedulers is not None:
        df = df[df["scheduler"].isin(schedulers)]

    df["overhead_pct"] = 100.0 * df["overhead_vs_oracle"]

    sched_order = list(df["scheduler"].unique())
    model_order = list(models)

    pairs = []
    for s in sched_order:
        for m in model_order:
            if not df[(df["scheduler"] == s) & (df["model"] == m)].empty:
                pairs.append((s, m))

    n_pairs = len(pairs)
    x = np.arange(n_pairs)
    width = 0.35

    baseline_heights = []
    compare_heights = []
    xtick_labels = []

    for i, (sched, model) in enumerate(pairs):
        sub = df[(df["scheduler"] == sched) & (df["model"] == model)]
        sched_parts = sched.split(" ")
        if len(sched_parts) % 2 == 0 and len(sched_parts) > 3:
            sched = f"{sched_parts[0]} {sched_parts[1].strip()}\n {sched_parts[2]} {sched_parts[3].strip()}"

        b_row = sub[sub["scenario"] == baseline_scenario]
        c_row = sub[sub["scenario"] == compare_scenario]

        b_val = float(b_row["overhead_pct"].iloc[0]) if not b_row.empty else np.nan
        c_val = float(c_row["overhead_pct"].iloc[0]) if not c_row.empty else np.nan

        baseline_heights.append(b_val)
        compare_heights.append(c_val)
        xtick_labels.append(f"{sched}\n({model})")

        if not np.isnan(b_val):
            ax.bar(
                x[i] - width / 2,
                b_val,
                width=width,
                color=color_map["baseline"],
                label=baseline_scenario if (show_legend and i == 0) else None,
            )
            ax.text(
                x[i] - width / 2,
                b_val,
                f"{b_val:.1f}%",
                ha="center",
                va="bottom",
                fontsize=14.5,
            )

        if not np.isnan(c_val):
            ax.bar(
                x[i] + width / 2,
                c_val,
                width=width,
                color=  color_map["local"],
                label=compare_scenario if (show_legend and i == 0) else None,
            )
            ax.text(
                x[i] + width / 2,
                c_val,
                f"{c_val:.1f}%",
                ha="center",
                va="bottom",
                fontsize=14.5,
            )

    all_vals = [v for v in baseline_heights + compare_heights if not np.isnan(v)]
    if all_vals:
        if min(all_vals) < 0:
            ymin = min(all_vals) - 0.5
        else:
            ymin = 0.0
        ymax = max(all_vals) * 1.15
        ax.set_ylim(ymin, ymax)

    ax.set_xticks(x)
    ax.set_xticklabels(xtick_labels, rotation=0, fontsize=15)
    ax.set_ylabel("Overhead vs Oracle (%)", fontsize=16)
    ax.tick_params(axis="y", labelsize=15)
    ax.set_xlabel("Scheduler (Model)", fontsize=16)

    if location_name:
        ax.set_title(location_name, fontsize=14)

    if show_legend:
        ax.legend(fontsize=16, loc="upper right")

def plot_overhead_vs_oracle_grid(
    overhead_df: pd.DataFrame,
    *,
    locations=None,
    baseline_scenario: str = "Higher-Variance",
    compare_scenario: str = "Lower-Variance",
    schedulers=None,
    models=("GNN", "RF"),
    figsize=(10, 10),
    color_map={}
):
    if locations is None:
        locations = list(overhead_df["location"].unique())

    if len(locations) != 4:
        raise ValueError(f"Expected exactly 4 locations for a 2x2 grid, got {len(locations)}")

    fig, axes = plt.subplots(2, 2, figsize=figsize, sharey=False)

    for idx, (ax, loc) in enumerate(zip(axes.ravel(), locations)):
        df_loc = overhead_df[overhead_df["location"] == loc]

        plot_overhead_vs_oracle_single_location(
            ax,
            df_loc,
            baseline_scenario=baseline_scenario,
            compare_scenario=compare_scenario,
            schedulers=schedulers,
            models=models,
            location_name=loc,
            show_legend=(idx == 1),
            color_map = color_map
        )
        if idx < 2:
            ax.set_xlabel("", fontsize=5)
            ax.tick_params(axis="x", which="both", labelbottom=False, size=7)

        if idx % 2 !=0:
            ax.set_ylabel("")
    plt.tight_layout(rect=[0, 0, 1, 0.90])
    fig.savefig("Overhead.pdf", dpi=300, bbox_inches="tight")
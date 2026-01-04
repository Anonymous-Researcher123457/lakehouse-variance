import pandas as pd
import numpy as np

def results_to_df(results, *, location: str, scenario_name: str) -> pd.DataFrame:
    """
    Convert a list of ExperimentResult into a DataFrame and tag with
    location and scenario.
    """
    rows = []
    for r in results:
        s = r.summary()
        s["location"] = location
        s["scenario"] = scenario_name          # "Baseline", "Low variance", etc.
        s["scheduler"] = getattr(r, "scheduler_name", "unknown")
        s["model"] = getattr(r, "label", "unknown")  # "FIFO", "GNN", "RF", "Oracle"
        rows.append(s)
    return pd.DataFrame(rows)


def add_overhead_vs_oracle(df: pd.DataFrame, metric: str = "carbon_total_gco2") -> pd.DataFrame:
    """
    For each (location, scenario, scheduler) group, compute:
      overhead_vs_oracle = (C_model - C_oracle) / C_oracle
    """
    def _group_fn(g: pd.DataFrame) -> pd.DataFrame:
        g = g.copy()
        oracle_rows = g[g["model"] == "Oracle"]
        if oracle_rows.empty:
            g["overhead_vs_oracle"] = np.nan
            return g

        c_oracle = float(oracle_rows[metric].iloc[0])
        g["overhead_vs_oracle"] = (g[metric] - c_oracle) / c_oracle
        return g

    return (
        df
        .groupby(["location", "scenario", "scheduler"], group_keys=False)
        .apply(_group_fn)
    )
    
def panel_configs_to_overhead_df(panel_configs, metric: str = "carbon_total_gco2") -> pd.DataFrame:
    """
    Take the list of (location, variant, results) from panel_configs and
    return a single DataFrame with overhead_vs_oracle computed.
    """
    dfs = []
    for location, variant, res_list in panel_configs:
        df = results_to_df(res_list, location=location, scenario_name=variant)
        dfs.append(df)

    all_df = pd.concat(dfs, ignore_index=True)
    all_df = add_overhead_vs_oracle(all_df, metric=metric)
    return all_df
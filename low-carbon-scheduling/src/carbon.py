import pandas as pd
import numpy as np

def load_carbon_timeseries(
    csv_path,
    use_lifecycle=False,
    start=None,
    end=None,
):
    """
    Load carbon intensity time series from CSV.

    Returns:
      df       : filtered DataFrame
      ci       : numpy array of carbon intensity values (gCO2/kWh)
      slot_sec : duration of each slot in seconds
      dt_hours : duration of each slot in hours
    """
    df = pd.read_csv(csv_path)
    df["Datetime (UTC)"] = pd.to_datetime(df["Datetime (UTC)"])

    if start is not None:
        start_ts = pd.to_datetime(start)
        df = df[df["Datetime (UTC)"] >= start_ts]

    if end is not None:
        end_ts = pd.to_datetime(end)
        df = df[df["Datetime (UTC)"] <= end_ts]

    df = df.sort_values("Datetime (UTC)").reset_index(drop=True)

    if len(df) < 2:
        raise ValueError("Not enough rows after filtering to infer time step")

    df = df.rename(columns={
        "Carbon intensity gCO₂eq/kWh (direct)": "ci_direct",
        "Carbon intensity gCO₂eq/kWh (Life cycle)": "ci_lifecycle",
    })

    col = "ci_lifecycle" if use_lifecycle else "ci_direct"
    ci = df[col].to_numpy(dtype=float)

    slot_sec = (df["Datetime (UTC)"].iloc[1] - df["Datetime (UTC)"].iloc[0]).total_seconds()
    dt_hours = slot_sec / 3600.0

    return df, ci, slot_sec, dt_hours


def upsample_ci(ci, old_slot_sec, new_slot_sec):
    """
    Upsample carbon intensity array from old_slot_sec to new_slot_sec
    by repeating each value.
    """
    if new_slot_sec > old_slot_sec:
        raise ValueError("new_slot_sec must be <= old_slot_sec")

    ratio = float(old_slot_sec) / float(new_slot_sec)
    factor = int(round(ratio))
    # Require that new_slot_sec divides old_slot_sec within a small tolerance
    if not np.isclose(ratio, factor, rtol=1e-9, atol=1e-9):
        raise ValueError(
            f"old_slot_sec ({old_slot_sec}) must be an integer multiple of "
            f"new_slot_sec ({new_slot_sec}); got ratio={ratio}"
        )

    ci_new = np.repeat(ci, factor)
    dt_hours_new = float(new_slot_sec) / 3600.0
    return ci_new, float(new_slot_sec), dt_hours_new

def make_ci_prefix(ci):
    """
    Prefix sum of ci so that:
    sum(ci[s:e]) = ci_prefix[e] - ci_prefix[s]
    """
    return np.concatenate([[0.0], np.cumsum(ci.astype(float))])


def carbon_emissions(
    ci,
    start_slot,
    duration_slots,
    power_kw=0.150,
    dt_hours=1.0,
    ci_prefix=None,
):
    """
    Carbon emissions over [start_slot, start_slot + duration_slots).
    """
    end = min(start_slot + duration_slots, len(ci))
    if end <= start_slot:
        return 0.0

    if ci_prefix is not None:
        window_sum = ci_prefix[end] - ci_prefix[start_slot]
    else:
        window_sum = ci[start_slot:end].sum()

    # gCO2 = (g/kWh) * (kWh)
    return float(window_sum * power_kw * dt_hours)


class CarbonProfile:
    """
    Wraps CI time series + dt_hours + prefix sums, and exposes window_carbon().
    """

    def __init__(self, ci, slot_sec, df=None):
        self.ci = np.asarray(ci, dtype=float)
        self.slot_sec = float(slot_sec)
        self.dt_hours = self.slot_sec / 3600.0
        self.df = df
        self.ci_prefix = make_ci_prefix(self.ci)

    @classmethod
    def from_csv(
        cls,
        csv_path,
        use_lifecycle=False,
        start=None,
        end=None,
        upsample_to_sec=1,
    ):
        df_ci, ci_raw, slot_sec_raw, _ = load_carbon_timeseries(
            csv_path,
            use_lifecycle=use_lifecycle,
            start=start,
            end=end,
        )
        ci, slot_sec, _ = upsample_ci(ci_raw, slot_sec_raw, upsample_to_sec)
        return cls(ci=ci, slot_sec=slot_sec, df=df_ci)

    @property
    def num_slots(self):
        return len(self.ci)

    def window_carbon(self, start_slot, duration_slots, power_kw=0.150):
        """
        Carbon emissions for a query occupying [start_slot, start_slot + duration_slots).
        """
        return carbon_emissions(
            self.ci,
            start_slot,
            duration_slots,
            power_kw=power_kw,
            dt_hours=self.dt_hours,
            ci_prefix=self.ci_prefix,
        )


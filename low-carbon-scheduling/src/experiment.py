from typing import Optional, Dict
from dataclasses import dataclass, field
import pandas as pd

from src.scheduler import Scheduler, assert_schedule_fits_sequential, realised_carbon_sequential
from src.carbon import CarbonProfile
from src.workload import Workload

@dataclass
class ExperimentResult:
    """
       Structure to hold the results of the experiment
    """
    name: str
    label: str
    scheduler_name: str
    oracle: bool
    carbon_total_gco2: float
    makespan_slots: int
    makespan_seconds: float
    num_queries: int

    schedule: Dict[str, int] = field(repr=False)
    workload: "Workload" = field(repr=False)
    carbon_profile: "CarbonProfile" = field(repr=False)
    power_kw: float = field(repr=False)

    def summary(self) -> dict:
        """Return a compact dict of key metrics."""
        carbon_per_query = (
            self.carbon_total_gco2 / self.num_queries if self.num_queries else float("nan")
        )
        carbon_per_second = (
            self.carbon_total_gco2 / self.makespan_seconds
            if self.makespan_seconds
            else float("nan")
        )

        return {
            "name": self.name,
            "label": self.label,
            "scheduler": self.scheduler_name,
            "oracle": self.oracle,
            "num_queries": self.num_queries,
            "carbon_total_gco2": self.carbon_total_gco2,
            "carbon_per_query_gco2": carbon_per_query,
            "carbon_per_second_gco2": carbon_per_second,
            "makespan_seconds": self.makespan_seconds,
            "slot_length_sec": self.carbon_profile.slot_sec,
            "power_kw": self.power_kw,
        }

    def __repr__(self) -> str:
        """ One-line summary."""
        s = self.summary()
        return (
            f"ExperimentResult<{s['name']}>("
            f"label={s['label']},"
            f"scheduler={s['scheduler']},"
            f"queries={s['num_queries']}, "
            f"carbon_total={s['carbon_total_gco2']:.2f} gCO2, "
            f"carbon/query={s['carbon_per_query_gco2']:.4f} gCO2, "
            f"makespan={s['makespan_seconds']:.1f} s)"
        )

    def get_schedule(self, order_by: str = "start", limit: Optional[int] = None):
        """
        Return the schedule as a list of dict rows:
        """
        query_by_id = {query.id: query for query in self.workload.queries}
        rows = []

        for jid, start in self.schedule.items():
            query = query_by_id[jid]
            rows.append(
                {
                    "query_id": jid,
                    "start_slot": start,
                    "start_time_s": start * self.carbon_profile.slot_sec,
                    "pred_slots": query.pred_slots,
                    "actual_slots": query.actual_slots,
                }
            )

        if order_by == "start":
            rows.sort(key=lambda r: r["start_slot"])
        elif order_by == "query_id":
            rows.sort(key=lambda r: r["query_id"])

        if limit is not None:
            rows = rows[:limit]

        return rows

    def schedule_dataframe(
        self,
        order_by: str = "start",
        limit: Optional[int] = None,
    ) -> pd.DataFrame:
        """ Return the schedule as a pandas DataFrame. """
        rows = self.get_schedule(order_by=order_by, limit=limit)
        return pd.DataFrame(rows)

class SchedulerExperiment:
    """
    Responsibilities:
      - Load carbon profile from CSV.
      - Load workload from values.csv.
      - Optionally swap to oracle view (pred = actual).
      - Run the given scheduler.
      - Compute realised carbon + basic stats.
    """

    def __init__(
        self,
        name: str,
        label: str,
        scheduler: Scheduler,
        carbon_csv_path: str,
        values_csv_path: str,
        *,
        query_limit: int = None,
        use_lifecycle_ci: bool = False,
        start_date: str = "2024-11-07",
        end_date: str = "2024-11-10",
        start_time: str = "09:00:00",
        end_time: str = None,
        upsample_to_sec: int = 1,
        power_kw: float = 0.150,
        oracle: bool = False,
        verbose: bool = False,
        add_variance: float = 1.0,
    ):
        self.name = name
        self.label = label
        self.scheduler = scheduler
        self.power_kw = float(power_kw)
        self.oracle = oracle
        self.verbose = verbose

        if end_time == None:
            end_time = start_time 
            
        # Build carbon profile
        self.carbon_profile = CarbonProfile.from_csv(
            carbon_csv_path,
            use_lifecycle=use_lifecycle_ci,
            start=f"{start_date} {start_time}",
            end=f"{end_date} {end_time}",
            upsample_to_sec=upsample_to_sec,
        )

        # Build workload
        workload = Workload.from_values_csv(
            values_csv_path,
            slot_sec=upsample_to_sec,
            limit=query_limit,
            oracle=oracle,
            add_variance=add_variance
        )
        self.workload = workload.oracle_view() if self.oracle else workload

    def _compute_makespan_slots(self, schedule) -> int:
        """
        Sequential, single-machine makespan under the same blocking semantics
        as realised_carbon_sequential.
        """
        query_by_id = {query.id: query for query in self.workload.queries}
        ordered_ids = sorted(schedule.keys(), key=lambda jid: schedule[jid])
    
        time_cursor = 0
        for jid in ordered_ids:
            q = query_by_id[jid]
            planned_start = schedule[jid]
    
            if planned_start > time_cursor:
                time_cursor = planned_start
    
            block_slots = max(q.pred_slots, q.actual_slots)
            time_cursor += block_slots
    
        return time_cursor


    def run(self) -> ExperimentResult:
        """
        Run the experiment for the issued scheduler.
        """
        cp = self.carbon_profile
        wl = self.workload

        print("================================")
        print(f"Experiment Name:        {self.name} ({self.label})")
        if self.verbose:
            print(f"Scheduler:              {self.scheduler.name}")
            print(f"# queries:                 {len(wl.queries)}")
            print(f"CI window:             ",
                cp.df["Datetime (UTC)"].iloc[0],
                "->",
                cp.df["Datetime (UTC)"].iloc[-1],
            )

        schedule = self.scheduler.build_schedule(wl, cp)

        assert_schedule_fits_sequential(
            wl,
            schedule,
            cp.num_slots,
            name=self.scheduler.name,
        )

        carbon_total = realised_carbon_sequential(
            wl,
            schedule,
            cp,
            power_kw=self.power_kw,
        )

        makespan_slots = self._compute_makespan_slots(schedule)
        makespan_seconds = makespan_slots * cp.slot_sec

        print(f"Total carbon (gCO2):   {carbon_total:.2f}")
        if self.verbose:
            print(f"Makespan (s):        {makespan_seconds:.1f}")

        return ExperimentResult(
            name=self.name,
            label=self.label,
            scheduler_name=self.scheduler.name,
            oracle=self.oracle,
            carbon_total_gco2=carbon_total,
            makespan_slots=makespan_slots,
            makespan_seconds=makespan_seconds,
            num_queries=len(wl.queries),
            schedule=schedule,
            workload=wl,
            carbon_profile=cp,
            power_kw=self.power_kw,
        )

def run_scheduler_experiment(
    name: str,
    label: str,
    scheduler: Scheduler,
    carbon_csv_path: str,
    values_csv_path: str,
    *,
    use_lifecycle_ci: bool = False,
    query_limit = None,
    power_kw: float = 0.150,
    start_date: str = "2024-01-02",
    end_date: str = "2024-01-04",
    start_time: str = "09:00:00",
    end_time: str = None,
    upsample_to_sec: int = 1,
    oracle: bool = False,
    verbose: bool = False,
    add_variance: float = 1.0,
) -> ExperimentResult:
    """
    High-level entrypoint.
    """
    exp = SchedulerExperiment(
        name=name,
        label=label,
        scheduler=scheduler,
        carbon_csv_path=carbon_csv_path,
        values_csv_path=values_csv_path,
        query_limit=query_limit,
        use_lifecycle_ci=use_lifecycle_ci,
        start_date=start_date,
        end_date=end_date,
        start_time=start_time,
        end_time=end_time,
        upsample_to_sec=upsample_to_sec,
        power_kw=power_kw,
        oracle=oracle,
        verbose=verbose,
        add_variance=add_variance,
    )
    return exp.run()

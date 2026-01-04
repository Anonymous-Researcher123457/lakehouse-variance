import random
from typing import Optional, Dict
from abc import ABC, abstractmethod
from math import ceil

try:
    from tqdm.auto import tqdm
except ImportError:  
    tqdm = None

from src.workload import Workload
from src.carbon import CarbonProfile

def realised_carbon_sequential(workload, schedule, carbon_profile, power_kw=0.150, local_search=False):
    """
    Compute realised carbon with a single machine:
    - Queries executed in order of planned start time.
    - Each query actually starts at max(planned_start, time_when_machine_free).
    - Machine is considered "blocked" for max(pred_slots, actual_slots).
      Carbon is still charged over the actual runtime.
    """
    query_by_id = {query.id: query for query in workload.queries}
    ordered_ids = sorted(schedule.keys(), key=lambda jid: schedule[jid])

    time_cursor = 0
    total = 0.0

    for jid in ordered_ids:
        q = query_by_id[jid]
        planned_start = schedule[jid]

        # Respect planned time and previous completion
        if planned_start > time_cursor:
            time_cursor = planned_start

        start = time_cursor

        # Carbon charged over actual runtime
        dur_actual = q.actual_slots
        total += carbon_profile.window_carbon(start, dur_actual, power_kw=power_kw)

        if not local_search:
            # QPP case: blocking based on predicted duration
            block_slots = q.actual_slots
        else:
            block_slots = q.pred_slots
        time_cursor = start + block_slots

    return total

class Scheduler(ABC):
    """
    Abstract scheduler: given a workload and carbon profile.
    """

    @property
    @abstractmethod
    def name(self):
        ...

    @abstractmethod
    def build_schedule(self, workload, carbon_profile):
        ...



class FIFOScheduler(Scheduler):
    """
    Simple FIFO: queries in some chosen order, back-to-back using actual_slots.
    """

    def __init__(self, name="FIFO", order_policy="arrival", random_seed: int=0):
        self._name = name
        self.order_policy = order_policy
        self.random_seed = 0

    @property
    def name(self):
        return self._name

    def build_schedule(self, workload, carbon_profile):
        schedule = {}
        slot_cursor = 0

        queries_iter = workload.ordered_queries(
            order_policy=self.order_policy,
            random_seed=0,
        )

        for query in queries_iter:
            schedule[query.id] = slot_cursor
            slot_cursor += query.actual_slots

        return schedule

class GreedyLowCarbonDeferScheduler(Scheduler):
    """
    Greedy low-carbon scheduler that chooses both:
      - which query to run next, and
      - when to start it within a deferral window.
    """

    def __init__(
        self,
        search_hours: float = 24.0,
        name: str = "LowCarbonWhoWhen",
        candidate_step_slots: int = 1,
        show_progress: bool = False,
    ):
        self.search_hours = float(search_hours)
        self._name = name
        if candidate_step_slots < 1:
            raise ValueError("candidate_step_slots must be >= 1")
        self.candidate_step_slots = int(candidate_step_slots)

        self.show_progress = show_progress

    @property
    def name(self):
        return self._name

    def build_schedule(self, workload, carbon_profile):
        remaining = {query.id for query in workload.queries}
        query_by_id = {query.id: query for query in workload.queries}
        schedule = {}
        current_slot = 0

        search_range_slots = int(ceil(self.search_hours / carbon_profile.dt_hours))
        ci_len = carbon_profile.num_slots

        pbar = None
        if self.show_progress and tqdm is not None:
            pbar = tqdm(
                total=len(remaining),
                desc=f"{self.name} (queries)",
                unit="query",
                leave=False,
            )

        while remaining:
            best_global_query = None
            best_global_start = None
            best_global_cost = float("inf")
            best_global_d_pred = None

            # For each remaining query, find its best start time within the horizon
            for jid in sorted(remaining):
                query = query_by_id[jid]
                d_pred = query.pred_slots

                if current_slot >= ci_len:
                    earliest = current_slot
                    last_possible = current_slot
                else:
                    earliest = current_slot
                    last_possible = ci_len - d_pred
                    if last_possible < earliest:
                        last_possible = earliest

                search_end = min(earliest + search_range_slots, last_possible)

                best_cost_for_query = float("inf")
                best_start_for_query = earliest
                candidate_slots = range(
                    earliest,
                    search_end + 1,
                    self.candidate_step_slots,
                )        

                for s in candidate_slots:
                    c = carbon_profile.window_carbon(s, d_pred, power_kw=0.150)
                    if c < best_cost_for_query:
                        best_cost_for_query = c
                        best_start_for_query = s

                if (best_cost_for_query < best_global_cost) or (
                        best_cost_for_query == best_global_cost and jid < best_global_query
                    ):
                    best_global_cost = best_cost_for_query
                    best_global_query = jid
                    best_global_start = best_start_for_query
                    best_global_d_pred = d_pred

            schedule[best_global_query] = best_global_start
            current_slot = best_global_start + best_global_d_pred
            remaining.remove(best_global_query)

            if pbar is not None:
                pbar.update(1)

        if pbar is not None:
            pbar.close()

        return schedule

def assert_schedule_fits_sequential(
    workload: Workload,
    schedule: Dict[str, int],
    ci_len: int,
    name: str = "schedule",
):
    """
    Check that, under the chosen blocking semantics, the schedule fits
    within the CI horizon.
    """
    query_by_id = {q.id: q for q in workload.queries}
    ordered_ids = sorted(schedule.keys(), key=lambda jid: schedule[jid])

    time_cursor = 0
    for jid in ordered_ids:
        q = query_by_id[jid]
        planned_start = schedule[jid]

        if planned_start > time_cursor:
            time_cursor = planned_start

        if not getattr(workload, "oracle", False):
            block_slots = q.pred_slots
        else:
            block_slots = max(q.pred_slots, q.actual_slots)

        time_cursor += block_slots

    assert time_cursor <= ci_len, (
        f"{name} exceeds CI window: ends at slot {time_cursor}, "
        f"but CI length is {ci_len}"
    )

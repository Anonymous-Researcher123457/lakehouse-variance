import random
from typing import Optional, Callable
from dataclasses import dataclass
from math import ceil
import pandas as pd

@dataclass(frozen=True)
class query:
    id: str
    pred_slots: int
    actual_slots: int

def runtime_to_slots(runtime_seconds, slot_sec, add_variance =1 ):
    """
    Convert a runtime in seconds to an integer number of slots.
    Ensures at least 1 slot.
    """
    return max(1, int(ceil(float(runtime_seconds) / float(slot_sec)) * add_variance))

class Workload:
    """
    Collection of queries plus helpers for loading / oracle view.
    """

    def __init__(self, queries, oracle):
        self.queries = list(queries)
        self.oracle = oracle

    @classmethod
    def from_values_csv(cls, values_csv_path, slot_sec, limit: Optional[int] = None, oracle=False, add_variance=1.0):
        """
        values.csv must have columns: 'prediction', 'label' (seconds).
        """
        df = pd.read_csv(values_csv_path)

        queries = []
        for i, row in df.iterrows():
            pred_s = float(row["prediction"])
            actual_s = float(row["label"])

            queries.append(
                query(
                    id=f"q{i}",
                    pred_slots=runtime_to_slots(pred_s, slot_sec, add_variance),
                    actual_slots=runtime_to_slots(actual_s, slot_sec),
                )
            )

        if limit is not None:
            queries = queries[:limit] 
            
        return cls(queries, oracle)

    def oracle_view(self):
        """
        Return a workload where pred_slots = actual_slots for all queries
        (perfect predictor).
        """
        oracle_queries = [
            query(id=j.id, pred_slots=j.actual_slots, actual_slots=j.actual_slots)
            for j in self.queries
        ]
        return Workload(oracle_queries, True)

    def ordered_queries(
        self,
        order_policy: Optional[Callable] | str = "arrival",
    ):
        """
        Return a list of queries ordered according to `order_policy`.
        """
        queries_list = list(self.queries)

        if callable(order_policy):
            return sorted(queries_list, key=order_policy)

        policy = "arrival" if order_policy is None else str(order_policy).lower()

        # 1) arrival order
        if policy == "arrival":
            return queries_list

        # 2) Predicted runtime-based
        if policy == "pred_longest_first":
            return sorted(queries_list, key=lambda j: j.pred_slots, reverse=True)

        if policy == "pred_shortest_first":
            return sorted(queries_list, key=lambda j: j.pred_slots)

        # 3) Actual runtime-based (oracle-style – useful for baselines)
        if policy == "actual_longest_first":
            return sorted(queries_list, key=lambda j: j.actual_slots, reverse=True)

        if policy == "actual_shortest_first":
            return sorted(queries_list, key=lambda j: j.actual_slots)

        # 4) Prediction error-based (also oracle-style)
        if policy == "high_error_first":
            return sorted(
                queries_list,
                key=lambda j: abs(j.actual_slots - j.pred_slots),
                reverse=True,
            )

        if policy == "low_error_first":
            return sorted(
                queries_list,
                key=lambda j: abs(j.actual_slots - j.pred_slots),
            )

        # 5) Random ordering (but reproducible via seed)
        if policy == "random":
            rng = random.Random(0)
            rng.shuffle(queries_list)
            return queries_list

        raise ValueError(f"Unknown order_policy '{order_policy}'")

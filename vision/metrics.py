"""Bounded timing samples. Summaries are computed only for diagnostics/reports."""
from collections import deque
import statistics

class Timings:
    def __init__(self, capacity: int = 600):
        self.values = deque(maxlen=capacity)

    def add(self, milliseconds: float) -> None:
        self.values.append(float(milliseconds))

    def summary(self) -> dict:
        values = sorted(self.values)
        if not values:
            return {"samples": 0, "mean_ms": 0, "p95_ms": 0, "max_ms": 0}
        return {"samples": len(values), "mean_ms": statistics.fmean(values),
                "p95_ms": values[min(len(values)-1, int(len(values)*.95))], "max_ms": values[-1]}

from __future__ import annotations
import math
from dataclasses import dataclass
from .config import TrackingConfig
from .detection import Observation

def angle_delta(target: float, current: float, period: float = 180) -> float:
    return (target-current+period/2) % period-period/2

@dataclass
class Track:
    pose: Observation | None = None
    anchor: Observation | None = None
    angle_anchor: float | None = None
    last_seen: float = -math.inf
    pending: Observation | None = None
    pending_time: float = -math.inf
    confirmations: int = 0

class Tracker:
    def __init__(self, settings: TrackingConfig, ids: list[int]):
        self.settings = settings
        self.tracks = {module_id: Track() for module_id in ids}

    def update(self, candidates: dict[int, list[Observation]], now: float) -> None:
        for module_id, track in self.tracks.items():
            choices = [p for p in candidates.get(module_id, []) if p.module_id == module_id
                       and all(math.isfinite(v) for v in (p.x,p.y,p.angle,p.area,p.confidence))
                       and 0 <= p.x <= 1 and 0 <= p.y <= 1]
            previous, age = track.pose, now-track.last_seen
            reacquiring = previous is None or age > self.settings.loss_tolerance
            candidate = None
            if previous is not None and age <= self.settings.loss_tolerance:
                anchor = track.anchor or previous
                gate = min(self.settings.max_jump, self.settings.jitter_allowance+self.settings.max_speed*age)
                nearby = [p for p in choices if math.hypot(p.x-anchor.x, p.y-anchor.y) <= gate]
                if nearby:
                    candidate = min(nearby, key=lambda p: math.hypot(p.x-anchor.x, p.y-anchor.y))
            elif choices:
                candidate = max(choices, key=lambda p: p.area)
            if candidate is None:
                track.pending, track.confirmations = None, 0
                continue
            if previous is None or age > self.settings.loss_tolerance:
                pending = track.pending
                coherent_angle = pending is not None and (not candidate.orientation_reliable or not pending.orientation_reliable or abs(angle_delta(candidate.angle,pending.angle,candidate.orientation_period)) <= self.settings.max_angle_jump)
                if pending is not None and coherent_angle and now-track.pending_time <= max(0.2, self.settings.loss_tolerance) and math.hypot(candidate.x-pending.x, candidate.y-pending.y) <= self.settings.reacquire_radius:
                    track.confirmations += 1
                else:
                    track.confirmations = 1
                track.pending, track.pending_time = candidate, now
                if track.confirmations < self.settings.confirmation_frames:
                    continue
            if previous is None:
                track.pose = Observation(module_id, candidate.x, candidate.y, candidate.angle, candidate.area,
                                         orientation_reliable=candidate.orientation_reliable,
                                         orientation_period=candidate.orientation_period)
                track.pose.confidence = candidate.confidence
                track.angle_anchor = candidate.angle
            else:
                dt = min(max(age, 0.001), 0.1)
                alpha = 1-math.exp(-dt/self.settings.position_tau)
                angle_alpha = 1-math.exp(-dt/self.settings.angle_tau)
                angle = previous.angle
                difference = angle_delta(candidate.angle, angle, candidate.orientation_period)
                angle_gate = min(self.settings.max_angle_jump, self.settings.angular_jitter+self.settings.angular_speed*dt)
                anchor_difference = angle_delta(candidate.angle, track.angle_anchor if track.angle_anchor is not None else angle, candidate.orientation_period)
                if candidate.orientation_reliable and (reacquiring or abs(anchor_difference) <= angle_gate):
                    angle += angle_alpha*difference
                    track.angle_anchor = candidate.angle
                track.pose = Observation(module_id, previous.x+alpha*(candidate.x-previous.x),
                                         previous.y+alpha*(candidate.y-previous.y), angle, candidate.area,
                                         orientation_reliable=candidate.orientation_reliable,
                                         orientation_period=candidate.orientation_period)
                track.pose.confidence = candidate.confidence
            track.last_seen, track.pending, track.confirmations = now, None, 0
            track.anchor = candidate

    def modules(self, now: float, force_invisible: bool = False) -> list[dict]:
        result = []
        for module_id, track in self.tracks.items():
            pose = track.pose
            if pose is None:
                continue
            result.append({"id": module_id, "x": pose.x, "y": pose.y,
                           "angle": (pose.angle+180) % 360-180,
                           "visible": not force_invisible and now-track.last_seen <= self.settings.loss_tolerance})
        return result

    def diagnostics(self, now: float) -> dict:
        return {str(module_id): {"state": "ACQUIRING" if track.pose is None else ("LOST" if now-track.last_seen > self.settings.loss_tolerance else ("HOLD" if now-track.last_seen > .06 else "LIVE")),
                                "age_ms": None if track.pose is None else max(0,now-track.last_seen)*1000,
                                "confirmations": track.confirmations,
                                "source_id": None if track.anchor is None else track.anchor.module_id,
                                "center": None if track.pose is None else [track.pose.x,track.pose.y],
                                "area": None if track.pose is None else track.pose.area,
                                "confidence": None if track.pose is None else track.pose.confidence,
                                "last_observation_monotonic": None if track.pose is None else track.last_seen}
                for module_id, track in self.tracks.items()}

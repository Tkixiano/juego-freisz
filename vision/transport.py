from __future__ import annotations
import json
import socket
import time
from collections import deque
from .config import NetworkConfig
from .metrics import Timings

class UdpSender:
    def __init__(self, config: NetworkConfig, coordinate_space: str = "CAMERA"):
        if coordinate_space not in ("CAMERA","PROJECTOR"):
            raise ValueError("Unknown coordinate space")
        self.coordinate_space = coordinate_space
        self.config = config
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setblocking(False)
        self.sequence = time.monotonic_ns()//1_000_000
        self.next_send = 0.0
        self.sent = self.errors = self.last_bytes = 0
        self.status = "UDP idle (no ACK)"
        self.send_times = deque(maxlen=600)
        self.send_cost = Timings()

    def send(self, modules: list[dict], now: float, force: bool = False, source_age_ms: float | None = None) -> bool:
        if not force and now < self.next_send:
            return False
        period = 1/self.config.hz
        self.next_send = now+period if self.next_send == 0 else max(self.next_send+period, now+period*.1)
        if self.sequence > 9_007_199_254_740_991:
            raise ValueError("Sequence exhausted")
        packet = {"version": 1, "sequence": self.sequence, "modules": modules,
                  "sent_unix_ms": time.time_ns()/1_000_000}
        packet["coordinate_space"] = self.coordinate_space
        if self.coordinate_space == "PROJECTOR":
            packet.update(version=2,projection_size=[1280,720],orientation_space="PROJECTOR_PIXELS")
        if source_age_ms is not None:
            packet["source_age_ms"] = max(0, source_age_ms)
        payload = json.dumps(packet,
                             allow_nan=False, separators=(",", ":")).encode("utf-8")
        self.sequence += 1
        if len(payload) > 4096:
            raise ValueError("UDP packet exceeds receiver limit")
        try:
            started = time.perf_counter()
            self.socket.sendto(payload, (self.config.host, self.config.port))
            self.send_cost.add((time.perf_counter()-started)*1000)
            self.sent += 1
            self.last_bytes = len(payload)
            self.send_times.append(now)
            self.status = f"UDP TX {self.sent} / {len(payload)} B (no ACK)"
            return True
        except OSError as error:
            self.errors += 1
            self.status = f"UDP ERROR: {error}"
            return False

    def close(self) -> None:
        self.socket.close()

    def diagnostics(self) -> dict:
        hz = (len(self.send_times)-1)/(self.send_times[-1]-self.send_times[0]) if len(self.send_times)>1 and self.send_times[-1]>self.send_times[0] else 0
        return {"sent":self.sent,"errors":self.errors,"measured_send_hz":hz,
                "last_bytes":self.last_bytes,"send_cost":self.send_cost.summary()}

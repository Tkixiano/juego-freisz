from __future__ import annotations
import ctypes
import multiprocessing as mp
import time
from dataclasses import dataclass
from typing import Callable
from collections import deque
import numpy as np
from .capture_worker import capture_worker
from .config import CameraConfig

@dataclass
class Frame:
    image: np.ndarray
    timestamp: float
    serial: int
    capture_ms: float = 0.0

class CameraSource:
    """One shared frame; nonblocking reads and bounded termination of native I/O."""
    def __init__(self, config: CameraConfig, factory: Callable | None = None):
        self.config, self.factory = config, factory
        self.context = mp.get_context("spawn")
        self.process = None
        self.state = "CAMERA opening"
        self.opened = False
        self.serial = 0
        self.latest = None
        self.restarts = self.forced_stops = 0
        self.last_open_ms = self.last_capture_ms = 0.0
        self.read_errors = 0
        self.captured_frames = 0
        self.capture_points = deque(maxlen=600)
        self._closed = False
        self._started_at = self._retry_at = 0.0
        self._last_progress = 0.0
        self._raw_serial = -1

    def _spawn(self):
        self.stop_event = self.context.Event()
        self.lock = self.context.Lock()
        self.pixels = self.context.RawArray(ctypes.c_ubyte, 3840*2160*3)
        self.header = self.context.RawArray(ctypes.c_double, 12)
        self.status = self.context.RawArray(ctypes.c_char, 512)
        self._started_at = time.monotonic()
        self._last_progress = self._started_at
        self._raw_serial = -1
        self.latest = None
        self.opened = False
        self.process = self.context.Process(target=capture_worker,
            args=(self.config, self.stop_event, self.lock, self.pixels, self.header, self.status, self.factory),
            name="camera-capture", daemon=True)
        self.process.start()
        self.state = "CAMERA opening"

    def start(self):
        if self.process is None and not self._closed:
            self._spawn()

    def _stop_child(self, graceful=True):
        if self.process is None:
            return
        self.stop_event.set()
        if graceful:
            self.process.join(timeout=.75)
        if self.process.is_alive():
            self.forced_stops += 1
            self.process.terminate()
            self.process.join(timeout=.35)
        if self.process.is_alive():
            self.process.kill()
            self.process.join(timeout=.35)
        if not self.process.is_alive():
            self.process.close()
            self.process = None
        self.opened = False
        self.latest = None

    def get(self) -> Frame | None:
        if self._closed:
            return None
        now = time.monotonic()
        if self.process is None:
            if now >= self._retry_at:
                self._spawn()
            return None
        # Never wait for a lock a hung/terminated native worker might hold.
        if self.lock.acquire(False):
            try:
                data = list(self.header)
                message = self.status.value.decode("utf-8", errors="replace")
                if message:
                    self.state = message
                self.opened = bool(data[6])
                self._last_progress = data[7] or self._started_at
                self.last_open_ms, self.last_capture_ms, self.read_errors = data[10], data[5], int(data[11])
                raw_serial = int(data[0])
                if raw_serial > 0 and raw_serial != self._raw_serial:
                    self.captured_frames += raw_serial-max(0,self._raw_serial)
                    self.capture_points.append((data[1],self.captured_frames))
                    width, height, channels = map(int, data[2:5])
                    size = width*height*channels
                    if 0 < size <= len(self.pixels):
                        image = np.frombuffer(self.pixels, np.uint8, count=size).reshape(height,width,channels).copy()
                        self.serial += 1
                        self.latest = Frame(image, data[1], self.serial, data[5])
                        self._raw_serial = raw_serial
            finally:
                self.lock.release()
        timeout = self.config.stall_timeout if self.latest is not None else self.config.startup_timeout
        if not self.process.is_alive() or now-self._last_progress > timeout:
            self._stop_child(graceful=False)
            self.restarts += 1
            self.state = "CAMERA stalled/disconnected; worker restarted"
            self._retry_at = now+self.config.reconnect_delay
            return None
        if self.latest is None or not self.opened or now-self.latest.timestamp > self.config.frame_timeout:
            if self.opened and self.latest is not None:
                self.state = "CAMERA frame timeout; waiting for driver/watchdog"
            return None
        return self.latest

    def diagnostics(self):
        hz = (self.capture_points[-1][1]-self.capture_points[0][1])/(self.capture_points[-1][0]-self.capture_points[0][0]) if len(self.capture_points)>1 and self.capture_points[-1][0]>self.capture_points[0][0] else 0
        return {"state":self.state,"opened":self.opened,"frames_copied":self.serial,
                "captured_frames":self.captured_frames,"measured_capture_hz":hz,
                "capture_read_ms":self.last_capture_ms,"open_ms":self.last_open_ms,
                "restarts":self.restarts,"forced_stops":self.forced_stops,"read_errors":self.read_errors,
                "child_alive":self.process is not None and self.process.is_alive()}

    def close(self) -> bool:
        self._closed = True
        self._stop_child()
        if self.forced_stops:
            self.state = "CAMERA closed; blocked native worker terminated"
        return self.process is None

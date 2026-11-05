"""Picklable fake drivers, including native-call hangs, for Windows spawn."""
from dataclasses import dataclass
import time
import numpy as np

@dataclass
class CameraFactory:
    mode: str
    released: object

    def __call__(self, *_args):
        if self.mode == "hang_open":
            time.sleep(60)
        return FakeCamera(self.mode, self.released)

class FakeCamera:
    def __init__(self, mode, released):
        self.mode, self.released = mode, released
        self.frames = 0

    def isOpened(self):
        return self.mode != "unopened"

    def set(self, *_args):
        return True

    def read(self):
        self.frames += 1
        if self.mode == "hang_read" and self.frames > 1:
            time.sleep(60)
        time.sleep(.005)
        if self.mode == "disconnect" and self.frames > 5:
            return False, None
        return True, np.zeros((480,640,3),np.uint8)

    def release(self):
        self.released.value = 1

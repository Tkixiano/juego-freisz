"""Lightweight process targets. No numpy, OpenCV, camera or device API imports."""
import time
def no_progress(config,stop,lock,pixels,header,status,factory):
    stop.wait(60)
def delayed_boot(config,stop,lock,pixels,header,status,factory):
    with lock:
        header[8]=header[7]=time.monotonic();header[9]=1
        status.value=b'FAKE importing'
    if stop.wait(2):return
    with lock:
        header[7]=time.monotonic();header[9]=2
        status.value=b'FAKE driver opening'
    stop.wait(60)

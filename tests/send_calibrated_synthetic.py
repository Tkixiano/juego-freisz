"""Finite live-loopback preparation test. Only generated images; no capture."""
import argparse
from pathlib import Path
import socket
import sys
import time
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from tests.test_calibrated_geometry import mapper
from vision.calibrated_source import CalibratedMaterialSource
from vision.material_synthetic import bgr
from vision.material_replay import labels
from vision.structure_udp import Session,fragment

def main():
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=5031);a=p.parse_args()
    with patch('cv2.VideoCapture',side_effect=AssertionError('NO HARDWARE')),socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        source=CalibratedMaterialSource(mapper());image=bgr(labels('three',True));session=Session();previous=0
        # Warm-up is synthetic and precedes measured health intervals.
        for _ in range(12):source.update(image)
        start=time.perf_counter();deadline=start
        while time.perf_counter()-start<5:
            t=time.perf_counter()-start;stage=0 if t<1.5 else 1 if t<2.2 else 2 if t<3.5 else 3
            if stage==3 and previous!=3:session=Session(started_ms=max(time.time_ns()//1000000,session.started_ms+1))
            previous=stage
            frame=source.update(image if stage in (0,3) else None,'OK' if stage in (0,3) else 'DISCONNECTED' if stage==1 else 'STALE')
            message=source.message(session,frame)
            if message is not None:
                for packet in fragment(message):sock.sendto(packet,('127.0.0.1',a.port))
            deadline=max(deadline+1/30,time.perf_counter());time.sleep(max(0,deadline-time.perf_counter()))
if __name__=='__main__':main()

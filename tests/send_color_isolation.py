"""Real OpenCV/tracking/UDP integration fixture, synthetic BGR only."""
import json
from pathlib import Path
import time
import numpy as np
from vision.config import Config
from vision.detection import ColorDetector
from vision.synthetic import draw_piece
from vision.tracking import Tracker
from vision.transport import UdpSender


def main():
    config = Config()
    detector = ColorDetector(config)
    tracker = Tracker(config.tracking,[1,2])
    sender = UdpSender(config.network)
    trace = []
    # New sequence range per stage lets the Godot observer identify checkpoints.
    base = time.monotonic_ns()//1_000_000
    try:
        for stage in range(5):
            for frame in range(60):
                start = time.monotonic()
                image = np.zeros((480,640,3),np.uint8)
                if stage in (0,2,3):
                    draw_piece(image,(180+frame,250),(120,32),frame*.2,(0,235,0))
                if stage in (1,2,3):
                    # Stage 3 green moves, blue remains exactly stationary.
                    draw_piece(image,(440 if stage==3 else 420+frame,240),(110,30),0,(255,0,0))
                batch = detector.detect(image)
                tracker.update(batch.candidates,start)
                modules = tracker.modules(start)
                if stage == 0:
                    assert not any(m["id"]==2 for m in modules)
                sender.sequence = base+stage*1000+frame
                sender.send(modules,start,force=True,source_age_ms=(time.monotonic()-start)*1000)
                trace.append({"stage":stage,"frame":frame,"sequence":sender.sequence-1,
                              "modules":modules,"detection":batch.diagnostics()})
                time.sleep(max(0,1/30-(time.monotonic()-start)))
    finally:
        sender.close()
    Path("artifacts/color_isolation_wire.json").write_text(json.dumps({"base":base,"trace":trace}),encoding="utf-8")
    print(json.dumps({"sent":len(trace),"base":base,"errors":sender.errors}))


if __name__ == "__main__":
    main()

from __future__ import annotations
import argparse
from dataclasses import asdict
import json
import math
from pathlib import Path
import time
import cv2
import numpy as np
from .camera import CameraSource
from .config import Config, load, validate
from .detection import ColorDetector, DetectionBatch
from .gui import Diagnostics
from .synthetic import make_frame
from .tracking import Tracker
from .transport import UdpSender
from .metrics import Timings
from .projection import ProjectionCalibration

def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Color modules -> Godot UDP v1; Q quits the diagnostic windows")
    parser.add_argument("--config", type=Path, default=Path(__file__).with_name("config.json"))
    parser.add_argument("--camera", type=int)
    parser.add_argument("--backend", choices=("dshow", "msmf", "auto"))
    parser.add_argument("--synthetic", action="store_true", help="Use generated BGR images, never open a camera")
    parser.add_argument("--scenario", choices=("normal","occlusion"), default="normal", help="Synthetic integration fixture only")
    parser.add_argument("--no-gui", action="store_true")
    parser.add_argument("--no-udp", action="store_true")
    parser.add_argument("--duration", type=float, default=0)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--snapshot", type=Path, help="Save one processed input frame, not a webcam stream")
    parser.add_argument("--probe-camera", action="store_true", help="Attempt one frame for at most 5 seconds; no UDP or GUI")
    parser.add_argument("--log-interval", type=float, default=2, help="Seconds between metrics; 0 disables periodic logs")
    parser.add_argument("--trace", type=Path, help="Optional JSONL candidate/track/wire audit; no images")
    parser.add_argument("--coordinates",choices=("CAMERA","PROJECTOR"),default="CAMERA")
    parser.add_argument("--calibration",type=Path,default=Path(__file__).with_name("projector_calibration.json"))
    args = parser.parse_args(argv)
    if args.synthetic and args.probe_camera:
        parser.error("--synthetic and --probe-camera are mutually exclusive")
    if args.scenario != "normal" and not args.synthetic:
        parser.error("--scenario requires --synthetic")
    if not math.isfinite(args.duration) or args.duration < 0:
        parser.error("Duration must be a finite nonnegative number")
    if not math.isfinite(args.log_interval) or args.log_interval < 0:
        parser.error("Log interval must be finite and nonnegative")
    try:
        config = load(args.config) if args.config.exists() else Config()
        if args.camera is not None:
            config.camera.index = args.camera
        if args.backend is not None:
            config.camera.backend = args.backend
        validate(config)
        calibration = ProjectionCalibration.load(args.calibration) if args.coordinates == "PROJECTOR" else None
        if calibration:
            calibration.compatible((config.camera.width,config.camera.height),config.camera.mirror,config.camera.index,config.camera.backend)
    except (OSError, ValueError) as error:
        print(f"CONFIG ERROR: {error}", flush=True)
        return 2
    if args.probe_camera:
        source = CameraSource(config.camera)
        source.start()
        deadline = time.monotonic()+5
        frame = None
        while time.monotonic() < deadline and frame is None:
            frame = source.get()
            time.sleep(.05)
        closed = source.close()
        report = {"opened_and_read_frame": frame is not None, "state": source.state,
                  "worker_closed": closed,"capture":source.diagnostics(), "size": list(frame.image.shape[:2][::-1]) if frame else None}
        print(json.dumps(report), flush=True)
        if args.report:
            args.report.parent.mkdir(parents=True, exist_ok=True)
            args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
        return 0 if frame is not None else 1
    detector = ColorDetector(config)
    tracker = Tracker(config.tracking, [c.id for c in config.colors])
    camera = None if args.synthetic else CameraSource(config.camera)
    sender = None if args.no_udp else UdpSender(config.network,args.coordinates)
    gui = None
    start = time.monotonic()
    processed = 0
    serial = -1
    fps = 0.0
    fps_frames, fps_start = 0, start
    last_batch = DetectionBatch({}, {})
    last_image = np.zeros((config.camera.height, config.camera.width, 3), np.uint8)
    snapshot_saved = False
    seen_ids: set[int] = set()
    camera_closed = True
    exit_code = 0
    processing_times, capture_times, source_ages = Timings(), Timings(), Timings()
    last_observed_at = None
    next_log = start+args.log_interval
    diagnostics_line = ""
    trace = None
    print("Synthetic BGR source" if args.synthetic else f"Camera index {config.camera.index} ({config.camera.backend})", flush=True)
    print("Q quit | S save HSV | L reload HSV. Godot: F2 -> EXTERNAL. UDP TX has no ACK.", flush=True)
    try:
        if args.trace:
            args.trace.parent.mkdir(parents=True,exist_ok=True)
            trace = args.trace.open("w",encoding="utf-8")
            trace.write(json.dumps({"event":"configuration","config":asdict(config),"coordinate_space":args.coordinates,
                                    "homography":calibration.matrix.tolist() if calibration else None})+"\n")
        # Avoid CPU oversubscription between Godot, the camera and two masks.
        cv2.setNumThreads(1)
        if camera:
            camera.start()
        if not args.no_gui:
            gui = Diagnostics(config, args.config)
        while args.duration == 0 or time.monotonic()-start < args.duration:
            tick = time.monotonic()
            if gui:
                gui.read_sliders()
            frame = camera.get() if camera else None
            if args.synthetic or (frame is not None and frame.serial != serial):
                elapsed_s = tick-start
                visible_ids = [1,2]
                if args.scenario == "occlusion":
                    if 3 <= elapsed_s < 3.08 or 4 <= elapsed_s < 5.2:
                        visible_ids.remove(1)
                    if 6.3 <= elapsed_s < 7.1:
                        visible_ids.remove(2)
                last_image = make_frame(elapsed_s, config.camera.width, config.camera.height, visible_ids) if args.synthetic else frame.image
                if calibration:
                    calibration.compatible((last_image.shape[1],last_image.shape[0]),config.camera.mirror,config.camera.index,config.camera.backend)
                observed_at = tick if args.synthetic else frame.timestamp
                serial = -1 if args.synthetic else frame.serial
                processing_started = time.perf_counter()
                last_batch = detector.detect(last_image)
                processing_times.add((time.perf_counter()-processing_started)*1000)
                if frame is not None:
                    capture_times.add(frame.capture_ms)
                source_ages.add((time.monotonic()-observed_at)*1000)
                tracker.update(last_batch.candidates, observed_at)
                if trace:
                    trace.write(json.dumps({"event":"observation","frame":processed,"time":observed_at,
                                            **last_batch.diagnostics(),"colors":[asdict(color) for color in config.colors],
                                            "tracks":tracker.diagnostics(observed_at)})+"\n")
                last_observed_at = observed_at
                processed += 1
                fps_frames += 1
                if args.snapshot and not snapshot_saved and processed >= 10:
                    args.snapshot.parent.mkdir(parents=True, exist_ok=True)
                    snapshot_saved = bool(cv2.imwrite(str(args.snapshot), last_image))
            elif camera and frame is None:
                last_batch = DetectionBatch({}, {})
            now = time.monotonic()
            if now-fps_start >= 1:
                fps = fps_frames/(now-fps_start)
                fps_frames, fps_start = 0, now
                diagnostics_line = "Read %.1f ms | OpenCV %.1f ms | age %.1f ms | TX %.1f Hz" % (capture_times.summary()["mean_ms"],processing_times.summary()["mean_ms"],source_ages.summary()["mean_ms"],sender.diagnostics()["measured_send_hz"] if sender else 0)
            modules = tracker.modules(now)
            projection_rejected = []
            if calibration:
                modules,projection_rejected = calibration.map_modules(modules)
            seen_ids.update(m["id"] for m in modules if m["visible"])
            if sender:
                sent = sender.send(modules, now, source_age_ms=None if last_observed_at is None else (now-last_observed_at)*1000)
                if sent and trace:
                    trace.write(json.dumps({"event":"udp_sent","coordinate_space":args.coordinates,"sequence":sender.sequence-1,"source_frame":processed-1,"time":now,"modules":modules})+"\n")
            if args.log_interval and now >= next_log:
                metrics = {"event":"metrics","processing_fps":fps,"opencv":processing_times.summary(),
                           "capture_read":capture_times.summary(),"source_age":source_ages.summary(),
                           "modules":tracker.diagnostics(now),"udp":sender.diagnostics() if sender else None,
                           "camera":camera.diagnostics() if camera else None}
                metrics["detection"] = last_batch.diagnostics()
                metrics["coordinate_space"] = args.coordinates
                metrics["projection_rejected"] = projection_rejected
                print(json.dumps(metrics), flush=True)
                next_log = now+args.log_interval
            camera_state = ("SYNTHETIC IMAGES - no webcam" if camera is None else camera.state)+" | "+args.coordinates
            if projection_rejected:
                camera_state += " | OUTSIDE CALIBRATION: "+",".join(str(item["id"]) for item in projection_rejected)
            if gui and not gui.show(last_image, last_batch, tracker, now, fps, camera_state, sender.status if sender else "UDP disabled", diagnostics_line):
                break
            time.sleep(max(0, 1/config.camera.fps-(time.monotonic()-tick)))
    except KeyboardInterrupt:
        pass
    except (cv2.error, OSError, ValueError) as error:
        print(f"DETECTOR ERROR: {error}", flush=True)
        exit_code = 1
    finally:
        if camera:
            camera_closed = camera.close()
        if sender:
            try:
                stopped_modules = tracker.modules(time.monotonic(), force_invisible=True)
                if calibration:
                    stopped_modules,_rejected = calibration.map_modules(stopped_modules)
                if sender.send(stopped_modules, time.monotonic(), force=True) and trace:
                    trace.write(json.dumps({"event":"udp_sent","coordinate_space":args.coordinates,"sequence":sender.sequence-1,"source_frame":processed-1,
                                            "shutdown":True,"modules":stopped_modules})+"\n")
            finally:
                sender.close()
        if gui:
            gui.close()
        elif not args.no_gui:
            cv2.destroyAllWindows()
        if trace:
            trace.close()
    elapsed = time.monotonic()-start
    if not camera_closed or (camera is not None and args.duration > 0 and processed == 0):
        exit_code = 1
    report = {"source": "synthetic_images" if args.synthetic else "webcam", "processed_frames": processed,
              "coordinate_space":args.coordinates,"calibration_errors":calibration.errors if calibration else None,
              "elapsed_seconds": elapsed, "processing_average_fps": processed/elapsed if elapsed else 0,
              "ids_seen": sorted(seen_ids), "packets_sent": sender.sent if sender else 0,
              "send_errors": sender.errors if sender else 0, "camera_closed": camera_closed,
              "snapshot_saved": snapshot_saved, "last_frame_size": list(last_image.shape[:2][::-1]) if processed else None,
              "camera_last_state": camera.state if camera else "SYNTHETIC",
              "opencv_timing":processing_times.summary(),"capture_read_timing":capture_times.summary(),
              "source_age_timing":source_ages.summary(),"capture":camera.diagnostics() if camera else None,
              "udp":sender.diagnostics() if sender else None,"modules":tracker.diagnostics(time.monotonic()),
              "processing_fps_last_window": fps, "opencv": cv2.__version__, "numpy": np.__version__, "exit_code": exit_code}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report), flush=True)
    return exit_code

if __name__ == "__main__":
    raise SystemExit(main())

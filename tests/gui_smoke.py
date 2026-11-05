"""Exercise real HighGUI windows/trackbars with synthetic images only."""
import json
from pathlib import Path
import tempfile
import time
import cv2
from vision.config import Config, load
from vision.detection import ColorDetector
from vision.gui import Diagnostics
from vision.synthetic import make_frame
from vision.tracking import Tracker

def main():
    checks = {}
    with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as directory:
        assert Path(directory).resolve().is_relative_to(Path(__file__).resolve().parent)
        config = Config()
        path = Path(directory)/"calibration.json"
        gui = None
        try:
            gui = Diagnostics(config, path)
            frame = make_frame(0)
            batch = ColorDetector(config).detect(frame)
            tracker = Tracker(config.tracking, [1, 2])
            now = time.monotonic()
            for i in range(3):
                tracker.update(batch.candidates, now+i/30)
            for _ in range(5):
                gui.show(frame, batch, tracker, now+.07, 30, "SYNTHETIC IMAGES", "UDP disabled")
                time.sleep(.03)
            checks["camera_preview_and_mask_windows_visible"] = cv2.getWindowProperty(gui.MAIN, cv2.WND_PROP_VISIBLE) >= 1 and cv2.getWindowProperty(gui.MASKS, cv2.WND_PROP_VISIBLE) >= 1
            cv2.setTrackbarPos("H min", gui.window(1), 40)
            gui.read_sliders()
            checks["slider_changes_hsv"] = config.colors[0].lower[0] == 40
            checks["s_saves_json"] = gui.handle_key(ord("s")) and load(path).colors[0].lower[0] == 40
            cv2.setTrackbarPos("H min", gui.window(1), 55)
            gui.read_sliders()
            checks["l_loads_json_and_sliders"] = gui.handle_key(ord("l")) and config.colors[0].lower[0] == 40 and cv2.getTrackbarPos("H min", gui.window(1)) == 40
            checks["color_selection"] = gui.handle_key(ord("2")) and gui.selected == 2 and gui.handle_key(ord("1")) and gui.selected == 1
            before = config.colors[0].lower[:]
            gui.mouse(cv2.EVENT_LBUTTONDOWN,185,310,0,None)
            gui.mouse(cv2.EVENT_LBUTTONUP,195,315,0,None)
            checks["roi_statistics_do_not_auto_apply"] = gui.sample is not None and config.colors[0].lower == before
            checks["explicit_apply_roi_suggestion"] = gui.handle_key(ord("a")) and config.colors[0].lower[0] == 57
            cv2.setTrackbarPos("Min area",gui.window(2),1234)
            gui.read_sliders()
            gui.handle_key(ord("s"))
            checks["independent_filter_settings_saved"] = load(path).colors[1].min_area == 1234 and load(path).colors[0].min_area == 600
            checks["details_can_be_hidden"] = gui.handle_key(ord("d")) and not gui.details
            checks["q_requests_clean_exit"] = not gui.handle_key(ord("q"))
        finally:
            if gui:
                gui.close()
    report = {"total": len(checks), "passed": sum(checks.values()), "checks": checks}
    Path("artifacts/vision_gui_results.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report))
    return 0 if all(checks.values()) else 1

if __name__ == "__main__":
    raise SystemExit(main())

"""Real HighGUI event pump; synthetic pattern image, never webcam/projector."""
import json
from pathlib import Path
import tempfile
from unittest.mock import patch
import cv2
from vision.config import Config,save
from vision.projector_calibration import main
from vision.projection import ProjectionCalibration
from vision.projection_pattern import pattern


def run():
    with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
        directory=Path(directory)
        config=Config(); config.camera.width=1280; config.camera.height=720
        save(config,directory/"config.json")
        cv2.imwrite(str(directory/"pattern.png"),pattern())
        keys=iter([32,ord("s"),ord("r"),ord("l"),ord("q")])
        original=cv2.waitKey
        def next_key(delay):
            original(40)
            return next(keys)
        with patch("cv2.waitKey",side_effect=next_key):
            code=main(["--no-launch","--image",str(directory/"pattern.png"),"--config",str(directory/"config.json"),"--output",str(directory/"calibration.json")])
        c=ProjectionCalibration.load(directory/"calibration.json")
        assert code==0 and c.errors["check_max_px"]<1
        before=(directory/"calibration.json").read_bytes()
        keys=iter([ord("m"),ord("r"),ord("q")])
        with patch("cv2.waitKey",side_effect=next_key):
            assert main(["--no-launch","--image",str(directory/"pattern.png"),"--config",str(directory/"config.json"),"--output",str(directory/"calibration.json")])==0
        assert before==(directory/"calibration.json").read_bytes()
        report={"passed":True,"checks":["real_window_with_synthetic_pattern","auto_detect_and_save","repeat_and_load","manual_mode_cancel_preserves_file"],"check_max_px":c.errors["check_max_px"]}
        Path("artifacts/projector_gui_results.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
        print(json.dumps(report))


if __name__=="__main__": run()

"""Standalone, transactional calibration UI. No combat and no UDP transmission."""
import argparse
import json
from pathlib import Path
import subprocess
import time
import cv2
import numpy as np
from .camera import CameraSource
from .config import load
from .projection import ProjectionCalibration, CENTERS, FIT_IDS, CHECK_IDS, PROJECTION_SIZE
from .projection_pattern import pattern,detect_references

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT/"vision/projector_calibration.json"


class CalibrationSession:
    """Candidate is separate from disk. Confirm is the only persistence action."""
    def __init__(self,camera,output):
        self.camera,self.output = camera,Path(output)
        self.candidate = None
        self.correspondences = {}
        self.frame_size = None
        self.message = "SPACE capture references | M manual clicks | L load | R repeat | Q cancel"
        self.manual = False
        self.order = list(FIT_IDS+CHECK_IDS)

    def build(self,found,size):
        self.candidate = None
        if set(found)!=set(CENTERS):
            raise ValueError(f"Need all eight unique references; missing {sorted(set(CENTERS)-set(found))}")
        c = self.camera
        result = ProjectionCalibration.fit([found[i] for i in FIT_IDS],[CENTERS[i] for i in FIT_IDS],
            [found[i] for i in CHECK_IDS],[CENTERS[i] for i in CHECK_IDS],size,
            mirror=c.mirror,camera_index=c.index,backend=c.backend)
        self.correspondences = dict(found)
        self.frame_size = size
        self.candidate = result
        self.message = "VALID: fit %.2f px | independent check RMS %.2f / MAX %.2f px | S confirm" % (
            result.errors["fit_rms_px"],result.errors["check_rms_px"],result.errors["check_max_px"])
        return result

    def confirm(self):
        if self.candidate is None:
            raise ValueError("No validated calibration to save")
        self.candidate.save(self.output)
        self.message = f"Saved {self.output.name}; Q exits"

    def repeat(self):
        self.candidate = None
        self.correspondences = {}
        self.message = "Previous saved calibration unchanged; SPACE capture / M manual"

    def click(self,event,x,y,flags,userdata):
        if not self.manual or event!=cv2.EVENT_LBUTTONDOWN or len(self.correspondences)>=8:
            return
        if self.frame_size is None or not (0<=x<self.frame_size[0] and 0<=y<self.frame_size[1]):
            return
        marker_id = self.order[len(self.correspondences)]
        self.correspondences[marker_id] = [float(x),float(y)]
        if len(self.correspondences)==8:
            try:
                self.build(self.correspondences,self.frame_size)
            except ValueError as error:
                self.message = str(error)+" | R then M to repeat"
        else:
            self.message = f"Click CENTER of marker ID {self.order[len(self.correspondences)]}"


def main(argv=None):
    parser = argparse.ArgumentParser(description="Projector calibration; never sends combat/platform input")
    parser.add_argument("--config",type=Path,default=ROOT/"vision/config.json")
    parser.add_argument("--output",type=Path,default=DEFAULT_OUTPUT)
    parser.add_argument("--godot",type=Path,default=Path(r"C:\godot 4.6\Godot_v4.6.3-stable_win64_console.exe"))
    parser.add_argument("--screen",type=int,default=0)
    parser.add_argument("--no-launch",action="store_true",help="Pattern already running in Godot")
    parser.add_argument("--image",type=Path,help="Offline image input instead of webcam")
    parser.add_argument("--generate-pattern",action="store_true",help="Generate pattern only, no camera/window")
    args = parser.parse_args(argv)
    pattern_path = ROOT/"juegofrei/calibration/projector_pattern.png"
    pattern_path.parent.mkdir(parents=True,exist_ok=True)
    try:
        if not cv2.imwrite(str(pattern_path),pattern()):
            raise OSError("Could not save pattern")
        if args.generate_pattern:
            print(pattern_path)
            return 0
        config = load(args.config)
        session = CalibrationSession(config.camera,args.output)
        if args.screen<0:
            raise ValueError("Screen index must be nonnegative")
    except (OSError,ValueError,RuntimeError) as error:
        print(f"CALIBRATION ERROR: {error}")
        return 2
    process,source = None,None
    title = "Camera calibration - SPACE freeze/auto | M manual | S confirm | R repeat | L load | Q cancel"
    frame = None
    frozen = False
    found = {}
    detection_info = {}
    code = 0
    try:
        if not args.no_launch:
            if not args.godot.is_file():
                raise ValueError("Godot executable not found; use --godot PATH or --no-launch")
            process = subprocess.Popen([str(args.godot),"--path",str(ROOT/"juegofrei"),
                "res://scenes/ProjectionCalibration.tscn","--",f"--projection-screen={args.screen}"])
        if args.image:
            frame = cv2.imread(str(args.image))
            if frame is None:
                raise ValueError("Could not open offline image")
            frozen = True
        else:
            source = CameraSource(config.camera)
            source.start()
        cv2.namedWindow(title,cv2.WINDOW_NORMAL)
        cv2.resizeWindow(title,800,600)
        cv2.setMouseCallback(title,session.click)
        serial = -1
        while True:
            if process is not None and process.poll() is not None:
                break
            fresh = source.get() if source and not frozen else None
            if fresh is not None and fresh.serial!=serial:
                frame = fresh.image
                serial = fresh.serial
                try:
                    found,detection_info = detect_references(frame)
                except RuntimeError as error:
                    found = {}
                    detection_info = {"error":str(error)}
            if frame is None:
                image = np.zeros((480,640,3),np.uint8)
                cv2.putText(image,source.state if source else "No image",(10,80),cv2.FONT_HERSHEY_SIMPLEX,.5,(240,240,240),1)
            else:
                session.frame_size = (frame.shape[1],frame.shape[0])
                image = frame.copy()
                refs = session.correspondences if session.manual or session.candidate else found
                for marker_id,point in refs.items():
                    x,y = map(int,point)
                    color = (0,220,0) if marker_id in FIT_IDS else (0,180,255)
                    cv2.circle(image,(x,y),5,color,2)
                    cv2.putText(image,f"{marker_id} {'FIT' if marker_id in FIT_IDS else 'CHECK'}",(x+6,y),cv2.FONT_HERSHEY_SIMPLEX,.4,color,1)
            canvas = np.full((image.shape[0]+70,image.shape[1],3),30,np.uint8)
            canvas[:image.shape[0]] = image
            cv2.putText(canvas,session.message[:125],(6,image.shape[0]+22),cv2.FONT_HERSHEY_SIMPLEX,.37,(240,240,240),1)
            cv2.putText(canvas,f"Refs {len(found)}/8 | frozen {frozen} | {detection_info}",(6,image.shape[0]+46),cv2.FONT_HERSHEY_SIMPLEX,.35,(240,240,240),1)
            cv2.imshow(title,canvas)
            key = cv2.waitKey(10)&0xff
            try:
                if key in (ord("q"),27) or cv2.getWindowProperty(title,cv2.WND_PROP_VISIBLE)<1:
                    break
                if key == ord(" ") and frame is not None:
                    frozen = True
                    session.manual = False
                    found,detection_info = detect_references(frame)
                    if detection_info.get("duplicates"):
                        raise ValueError("Duplicate marker IDs; remove ambiguous references")
                    session.build(found,(frame.shape[1],frame.shape[0]))
                elif key in (ord("m"),ord("M")) and frame is not None:
                    frozen = True
                    session.repeat()
                    session.manual = True
                    session.message = "Click CENTER of marker ID 10 (then 11,12,13,14,15,16,17)"
                elif key in (ord("r"),ord("R")):
                    session.repeat()
                    session.manual = False
                    frozen = args.image is not None
                elif key in (ord("s"),ord("S")):
                    session.confirm()
                elif key in (ord("l"),ord("L")):
                    candidate = ProjectionCalibration.load(args.output)
                    candidate.compatible(session.frame_size,config.camera.mirror,config.camera.index,config.camera.backend)
                    session.candidate = candidate
                    session.message = "Loaded valid calibration; check RMS %.2f px" % candidate.errors["check_rms_px"]
            except (OSError,ValueError,RuntimeError,cv2.error) as error:
                session.candidate = None
                session.message = str(error)+" | R repeat"
    except (OSError,ValueError,RuntimeError,cv2.error) as error:
        print(f"CALIBRATION ERROR: {error}")
        code = 1
    finally:
        if source:
            source.close()
        cv2.destroyAllWindows()
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=2)
    return code


if __name__ == "__main__":
    raise SystemExit(main())

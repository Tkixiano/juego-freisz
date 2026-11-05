from __future__ import annotations
import math
from pathlib import Path
import cv2
import numpy as np
from .config import Config, load, save
from .detection import DetectionBatch
from .tracking import Tracker
from .calibration import sample_hsv

class Diagnostics:
    MAIN = "Module detector - Q quit | S save HSV | L load HSV"
    MASKS = "Masks - ID 1 green | ID 2 blue"
    CALIBRATION = "Calibration - 1 green | 2 blue | drag ROI on camera | A apply suggestion"
    SLIDERS = ("H min", "S min", "V min", "H max", "S max", "V max")

    def __init__(self, config: Config, path: Path):
        self.config, self.path = config, path
        self.message = "S save calibration | L reload HSV | Q quit"
        self.selected = 1
        self.last_frame = None
        self.roi_start = self.roi_end = None
        self.sample = None
        self.sample_id = None
        self.details = True
        cv2.namedWindow(self.MAIN, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.MAIN, config.camera.width, config.camera.height)
        cv2.namedWindow(self.MASKS, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.MASKS, 640, 240)
        cv2.namedWindow(self.CALIBRATION, cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.CALIBRATION, 640, 480)
        cv2.setMouseCallback(self.MAIN, self.mouse)
        for color in config.colors:
            window = self.window(color.id)
            cv2.namedWindow(window, cv2.WINDOW_NORMAL)
            cv2.resizeWindow(window, 420, 540)
            for label, value, maximum in zip(self.SLIDERS, color.lower+color.upper, (179, 255, 255, 179, 255, 255)):
                cv2.createTrackbar(label, window, value, maximum, lambda _value: None)
            for label, value, maximum in self.filter_sliders(color):
                cv2.createTrackbar(label, window, value, maximum, lambda _value: None)

    @staticmethod
    def filter_sliders(color):
        return [("Min area",color.min_area,100000),("Max area %",round(color.max_area_fraction*100),95),
                ("Min dimension",round(color.min_dimension),200),("Min saturation",color.min_saturation,255),
                ("Confidence %",round(color.min_confidence*100),100)]

    def mouse(self, event, x, y, flags, userdata):
        if event == cv2.EVENT_LBUTTONDOWN:
            self.roi_start = (x,y)
            self.roi_end = None
        elif event == cv2.EVENT_LBUTTONUP and self.roi_start and self.last_frame is not None:
            self.roi_end = (x,y)
            try:
                self.sample = sample_hsv(self.last_frame,self.roi_start,self.roi_end)
                self.sample_id = self.selected
                self.message = f"ID {self.selected} ROI HSV {self.sample['median_hsv']} | A applies suggestion"
            except ValueError as error:
                self.message = str(error)

    @staticmethod
    def window(module_id: int) -> str:
        return f"HSV ID {module_id} - {'green' if module_id == 1 else 'blue'}"

    def read_sliders(self) -> None:
        for color in self.config.colors:
            values = [cv2.getTrackbarPos(label, self.window(color.id)) for label in self.SLIDERS]
            # H min > H max means hue wrap; S/V ranges stay ordered.
            for channel in (1, 2):
                values[channel] = min(values[channel], values[channel+3])
                cv2.setTrackbarPos(self.SLIDERS[channel], self.window(color.id), values[channel])
            color.lower, color.upper = values[:3], values[3:]
            window = self.window(color.id)
            color.min_area = max(10,cv2.getTrackbarPos("Min area",window))
            color.max_area_fraction = max(1,cv2.getTrackbarPos("Max area %",window))/100
            color.min_dimension = max(2,cv2.getTrackbarPos("Min dimension",window))
            color.min_saturation = cv2.getTrackbarPos("Min saturation",window)
            color.min_confidence = cv2.getTrackbarPos("Confidence %",window)/100

    def handle_key(self, key: int) -> bool:
        if key in (ord("q"), ord("Q"), 27):
            return False
        try:
            if key in (ord("1"),ord("2")):
                self.selected = int(chr(key))
            elif key in (ord("d"),ord("D")):
                self.details = not self.details
                for window in (self.MASKS,self.CALIBRATION):
                    if not self.details:
                        cv2.destroyWindow(window)
            elif key in (ord("a"),ord("A")) and self.sample is not None and self.sample_id == self.selected:
                for label,value in zip(self.SLIDERS,self.sample["suggested_lower"]+self.sample["suggested_upper"]):
                    cv2.setTrackbarPos(label,self.window(self.selected),value)
                self.read_sliders()
                self.message = "Suggestion applied; inspect masks before S to save"
            if key in (ord("s"), ord("S")):
                self.read_sliders()
                save(self.config, self.path)
                self.message = f"HSV saved: {self.path.name}"
            elif key in (ord("l"), ord("L")):
                loaded = load(self.path)
                # Runtime reload is intentionally HSV/area only; camera/network
                # changes are applied at startup to avoid hidden device changes.
                self.config.colors = loaded.colors
                for color in loaded.colors:
                    for label, value in zip(self.SLIDERS, color.lower+color.upper):
                        cv2.setTrackbarPos(label, self.window(color.id), value)
                    for label,value,_maximum in self.filter_sliders(color):
                        cv2.setTrackbarPos(label,self.window(color.id),value)
                self.message = f"HSV loaded: {self.path.name}"
        except (OSError, ValueError) as error:
            self.message = f"CONFIG ERROR: {error}"
        return True

    def show(self, frame: np.ndarray, batch: DetectionBatch, tracker: Tracker, now: float, fps: float, camera_state: str, udp_status: str, diagnostics_line: str = "") -> bool:
        image = frame.copy()
        self.last_frame = frame
        if self.roi_start and self.roi_end:
            cv2.rectangle(image,self.roi_start,self.roi_end,(0,220,255),1)
        if self.details:
            for review in batch.reviews:
                color = (50,220,50) if review.reason == "accepted" else (40,40,240)
                cv2.drawContours(image,[review.contour],-1,color,2)
                x,y = map(int,review.center)
                cv2.putText(image,f"ID{review.module_id} A{review.area:.0f} C{review.confidence:.2f} {review.reason}",(x,max(10,y)),cv2.FONT_HERSHEY_SIMPLEX,.35,color,1)
        for module_id, observations in batch.candidates.items():
            color = (0, 255, 0) if module_id == 1 else (255, 130, 40)
            for observation in observations:
                if observation.contour is not None:
                    cv2.drawContours(image, [observation.contour], -1, color, 2)
        for module in tracker.modules(now):
            x, y = int(module["x"]*(image.shape[1]-1)), int(module["y"]*(image.shape[0]-1))
            color = (0, 255, 0) if module["visible"] else (130, 130, 130)
            cv2.circle(image, (x, y), 5, color, -1)
            radians = math.radians(module["angle"])
            cv2.line(image, (x, y), (int(x+45*math.cos(radians)), int(y+45*math.sin(radians))), color, 2)
            age = now-tracker.tracks[module["id"]].last_seen
            state = "LOST" if not module["visible"] else ("HOLD" if age > .06 else "LIVE")
            cv2.putText(image, f"ID {module['id']} {module['angle']:.1f}deg {state} age {age*1000:.0f}ms", (max(0, x-65), max(90, y-15)), cv2.FONT_HERSHEY_SIMPLEX, .45, color, 1)
        for i, line in enumerate((camera_state, f"Processing FPS {fps:.1f} | {udp_status}", self.message, diagnostics_line)):
            cv2.putText(image, line[:100], (8, 20+i*22), cv2.FONT_HERSHEY_SIMPLEX, .43, (240, 240, 240), 1)
        cv2.imshow(self.MAIN, image)
        masks = [batch.masks.get(module_id, np.zeros(frame.shape[:2], np.uint8)) for module_id in (1, 2)]
        if self.details:
            cv2.imshow(self.MASKS, np.hstack(masks))
            selected = cv2.cvtColor(masks[self.selected-1],cv2.COLOR_GRAY2BGR)
            cv2.putText(selected,f"Selected ID {self.selected} | overlap pixels {batch.overlap_pixels}",(8,22),cv2.FONT_HERSHEY_SIMPLEX,.5,(0,180,255),1)
            if self.sample and self.sample_id == self.selected:
                cv2.putText(selected,f"ROI H/S/V median: {self.sample['median_hsv']}",(8,46),cv2.FONT_HERSHEY_SIMPLEX,.4,(0,180,255),1)
                cv2.putText(selected,f"Suggest {self.sample['suggested_lower']} -> {self.sample['suggested_upper']}",(8,68),cv2.FONT_HERSHEY_SIMPLEX,.4,(0,180,255),1)
            cv2.imshow(self.CALIBRATION, selected)
        try:
            if cv2.getWindowProperty(self.MAIN, cv2.WND_PROP_VISIBLE) < 1:
                return False
        except cv2.error:
            return False
        return self.handle_key(cv2.waitKey(1) & 0xff)

    def close(self) -> None:
        cv2.destroyAllWindows()

"""Synthetic IMAGE source: passes real BGR pixels through the color detector."""
import math
import cv2
import numpy as np

def draw_piece(frame: np.ndarray, center: tuple[float, float], size: tuple[float, float], angle: float, color: tuple[int, int, int], trapezoid: bool = False) -> None:
    if trapezoid:
        w, h = size
        points = np.array([[-w*.4, -h/2], [w*.4, -h/2], [w/2, h/2], [-w/2, h/2]], np.float32)
        radians = math.radians(angle)
        rotation = np.array([[math.cos(radians), -math.sin(radians)], [math.sin(radians), math.cos(radians)]])
        points = points @ rotation.T + center
    else:
        points = cv2.boxPoints((center, size, angle))
    cv2.fillConvexPoly(frame, np.round(points).astype(np.int32), color)

def make_frame(elapsed: float, width: int = 640, height: int = 480, visible_ids=(1,2)) -> np.ndarray:
    frame = np.full((height, width, 3), 25, np.uint8)
    if 1 in visible_ids:
        draw_piece(frame, (width*(.30+.10*math.sin(elapsed*.8)), height*(.65+.05*math.sin(elapsed))),
                   (width*.20, height*.07), 16*math.sin(elapsed*.6), (0, 220, 0))
    if 2 in visible_ids:
        draw_piece(frame, (width*(.72-.07*math.sin(elapsed*.65)), height*(.60+.05*math.cos(elapsed))),
                   (width*.22, height*.09), -22*math.sin(elapsed*.55), (230, 60, 20), True)
    return frame

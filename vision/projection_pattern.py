"""Eight uniquely identified projected references; four independent hold-outs."""
import cv2
import numpy as np
from .projection import CENTERS, FIT_IDS, PROJECTION_SIZE


def dictionary():
    if not hasattr(cv2,"aruco"):
        raise RuntimeError("This OpenCV build lacks aruco; use manual calibration or opencv-python >=4.10")
    return cv2.aruco.getPredefinedDictionary(cv2.aruco.DICT_4X4_50)


def pattern():
    width,height = PROJECTION_SIZE
    image = np.full((height,width,3),255,np.uint8)
    cv2.rectangle(image,(150,180),(1130,520),(130,130,130),2)
    for marker_id,(x,y) in CENTERS.items():
        # Clear a quiet zone even where the arena outline crosses a marker.
        cv2.rectangle(image,(x-60,y-60),(x+60,y+60),(255,255,255),-1)
        marker = cv2.aruco.generateImageMarker(dictionary(),marker_id,97)
        image[y-48:y+49,x-48:x+49] = cv2.cvtColor(marker,cv2.COLOR_GRAY2BGR)
        cv2.putText(image,f"{marker_id} {'FIT' if marker_id in FIT_IDS else 'CHECK'}",(x-50,y+68),cv2.FONT_HERSHEY_SIMPLEX,.45,(0,0,0),1)
    cv2.putText(image,"CAMERA -> PROJECTION | 1280 x 720 | top-left origin, Y down",(300,38),cv2.FONT_HERSHEY_SIMPLEX,.6,(0,0,0),1)
    cv2.putText(image,"Gray rectangle: allowed platform centers. Markers 14-17: independent checks.",(245,687),cv2.FONT_HERSHEY_SIMPLEX,.5,(0,0,0),1)
    return image


def detect_references(frame):
    detector = cv2.aruco.ArucoDetector(dictionary(),cv2.aruco.DetectorParameters())
    corners,ids,rejected = detector.detectMarkers(frame)
    found, duplicates = {}, set()
    if ids is not None:
        for marker,marker_id in zip(corners,ids.flatten()):
            marker_id = int(marker_id)
            if marker_id not in CENTERS:
                continue
            if marker_id in found or marker_id in duplicates:
                found.pop(marker_id,None)
                duplicates.add(marker_id)
                continue
            quad = marker.reshape(4,2).astype(np.float32)
            if not cv2.isContourConvex(quad) or cv2.contourArea(quad)<64:
                continue
            # Projective center (diagonal intersection), not mean corners.
            homography = cv2.getPerspectiveTransform(np.float32([[0,0],[1,0],[1,1],[0,1]]),quad)
            center = cv2.perspectiveTransform(np.float32([[[.5,.5]]]),homography)[0,0]
            found[marker_id] = center.tolist()
    return found,{"duplicates":sorted(duplicates),"rejected_quads":len(rejected)}

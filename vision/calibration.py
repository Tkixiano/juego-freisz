"""ROI statistics suggest HSV bounds; never silently change calibration."""
import cv2
import math
import numpy as np


def sample_hsv(frame, start, end):
    h, w = frame.shape[:2]
    x0, x1 = sorted((max(0,min(w,start[0])),max(0,min(w,end[0]))))
    y0, y1 = sorted((max(0,min(h,start[1])),max(0,min(h,end[1]))))
    if x1-x0 < 3 or y1-y0 < 3:
        raise ValueError("Select a region of at least 3 x 3 pixels")
    pixels = cv2.cvtColor(frame[y0:y1,x0:x1],cv2.COLOR_BGR2HSV).reshape(-1,3)
    # Unwrap hue around its circular mean, avoiding 0/179 boundary artifacts.
    radians = pixels[:,0]*np.pi/90
    center = np.arctan2(np.sin(radians).mean(),np.cos(radians).mean())*90/np.pi
    hue = (pixels[:,0]-center+90)%180-90+center
    low, high = np.percentile(pixels,(5,95),axis=0)
    hl, hh = np.percentile(hue,(5,95))
    lower = [math.floor(hl-3+1e-6)%180,max(0,int(low[1])-15),max(0,int(low[2])-15)]
    upper = [math.ceil(hh+3-1e-6)%180,min(255,int(high[1])+15),min(255,int(high[2])+15)]
    return {"pixels":len(pixels),"median_hsv":np.median(pixels,axis=0).tolist(),
            "p05_hsv":low.tolist(),"p95_hsv":high.tolist(),"suggested_lower":lower,"suggested_upper":upper}

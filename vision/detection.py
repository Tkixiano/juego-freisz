from __future__ import annotations
import math
from dataclasses import dataclass, field
from typing import Protocol
import cv2
import numpy as np
from .config import Config

@dataclass
class Observation:
    module_id: int
    x: float
    y: float
    angle: float
    area: float
    contour: np.ndarray | None = None
    orientation_reliable: bool = True
    orientation_period: float = 180.0
    confidence: float = 1.0

@dataclass
class CandidateReview:
    module_id: int
    contour: np.ndarray
    area: float
    center: tuple[float, float]
    confidence: float
    reason: str

@dataclass
class DetectionBatch:
    candidates: dict[int, list[Observation]]
    masks: dict[int, np.ndarray]
    reviews: list[CandidateReview] = field(default_factory=list)
    overlap_pixels: int = 0

    def diagnostics(self) -> dict:
        return {"overlap_pixels": self.overlap_pixels,
                "candidates": [{"id": r.module_id, "area": round(r.area, 1),
                                "center_px": list(r.center), "confidence": round(r.confidence, 3),
                                "decision": r.reason} for r in self.reviews]}

class Detector(Protocol):
    """Future ArUco adapter returns these observations, independent of UDP."""
    def detect(self, frame: np.ndarray) -> DetectionBatch: ...

class ColorDetector:
    def __init__(self, config: Config):
        self.config = config
        k = config.tracking.morphology_kernel
        self.kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (k, k))

    def detect(self, frame: np.ndarray) -> DetectionBatch:
        if frame is None or frame.ndim != 3 or frame.shape[2] != 3 or frame.dtype != np.uint8:
            raise ValueError("Expected a uint8 BGR image")
        height, width = frame.shape[:2]
        if width < 2 or height < 2:
            raise ValueError("Image is too small")
        hsv = cv2.cvtColor(frame, cv2.COLOR_BGR2HSV)
        candidates, masks, raw_masks, reviews = {}, {}, {}, []
        for color in self.config.colors:
            lower = color.lower[:]
            lower[1] = max(lower[1], color.min_saturation)
            low, high = np.array(lower, np.uint8), np.array(color.upper, np.uint8)
            if color.lower[0] <= color.upper[0]:
                mask = cv2.inRange(hsv, low, high)
            else:
                mask = cv2.bitwise_or(cv2.inRange(hsv, np.array([0, *lower[1:]], np.uint8), high),
                                     cv2.inRange(hsv, low, np.array([179, *color.upper[1:]], np.uint8)))
            raw_masks[color.id] = mask
        overlap = cv2.bitwise_and(raw_masks[1], raw_masks[2])
        overlap_pixels = cv2.countNonZero(overlap)
        for color in self.config.colors:
            mask = raw_masks[color.id]
            mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, self.kernel)
            mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, self.kernel)
            masks[color.id] = mask
            contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            found = []
            # Bounded diagnostic cost, largest candidates first.
            for contour in sorted(contours, key=cv2.contourArea, reverse=True)[:128]:
                area = cv2.contourArea(contour)
                rectangle = cv2.minAreaRect(contour)
                rw, rh = rectangle[1]
                fill = area/max(rw*rh, 1)
                moments = cv2.moments(contour)
                center = (moments["m10"]/moments["m00"], moments["m01"]/moments["m00"]) if moments["m00"] > 0 else rectangle[0]
                if area < color.min_area:
                    reviews.append(CandidateReview(color.id,contour,area,center,0.0,"area_min"))
                    continue
                x, y, w, h = cv2.boundingRect(contour)
                region = np.zeros((h,w), np.uint8)
                cv2.drawContours(region, [contour-np.array([[[x,y]]])], -1, 255, -1)
                population = max(cv2.countNonZero(region), 1)
                purity = cv2.countNonZero(cv2.bitwise_and(raw_masks[color.id][y:y+h,x:x+w], region))/population
                conflict = cv2.countNonZero(cv2.bitwise_and(overlap[y:y+h,x:x+w], region)) > 0
                confidence = min(1.0, fill)*purity
                reason = "accepted"
                if conflict:
                    reason = "overlapping_masks"
                elif area < color.min_area:
                    reason = "area_min"
                elif area > width*height*min(color.max_area_fraction,self.config.tracking.max_area_fraction):
                    reason = "area_max"
                elif min(rw,rh) < color.min_dimension or max(rw,rh)/max(min(rw,rh),.001) > color.max_aspect_ratio:
                    reason = "dimensions"
                elif fill < self.config.tracking.min_fill:
                    reason = "fill"
                elif confidence < color.min_confidence:
                    reason = "confidence"
                reviews.append(CandidateReview(color.id, contour, area, center, confidence, reason))
                if reason != "accepted":
                    continue
                corners = cv2.boxPoints(rectangle)
                edges = np.roll(corners, -1, axis=0)-corners
                edge = edges[np.argmax(np.sum(edges*edges, axis=1))]
                angle = (math.degrees(math.atan2(float(edge[1]), float(edge[0])))+90) % 180-90
                found.append(Observation(color.id, float(np.clip(center[0]/(width-1), 0, 1)),
                                         float(np.clip(center[1]/(height-1), 0, 1)), angle, area, contour,
                                         max(rw, rh)/min(rw, rh) >= 1.15, confidence=confidence))
            if len(found)>1:
                ordered = sorted(found,key=lambda p:p.area,reverse=True)
                if ordered[1].area/ordered[0].area >= color.ambiguity_ratio:
                    for review in reviews:
                        if review.module_id == color.id and review.reason == "accepted":
                            review.reason = "ambiguous_same_color"
                    found = []
            candidates[color.id] = sorted(found, key=lambda item: item.area, reverse=True)
        return DetectionBatch(candidates, masks, reviews, overlap_pixels)

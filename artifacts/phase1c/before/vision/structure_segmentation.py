"""Offline silhouette segmentation. No capture, transport or game dependencies.

Geometry follows pixel CELL edges, not pixel centres. Corner contacts can have
multiple exterior rings; holes are retained, never silently filled.
"""
from __future__ import annotations

from dataclasses import dataclass
import cv2
import numpy as np
from .config import ColorConfig


@dataclass(frozen=True)
class StructureSettings:
    min_area: int = 64
    max_components: int = 64
    max_pixels: int = 1280 * 720
    proximity_pixels: float = 2.0
    birth_frames: int = 3
    merge_frames: int = 3
    corner_frames: int = 5
    split_frames: int = 4
    near_split_frames: int = 8
    loss_frames: int = 5
    max_motion_pixels: float = 32.0
    geometry_difference_fraction: float = 0.015
    geometry_boundary_pixels: float = 1.5
    max_manager_vertices: int = 64
    max_members: int = 128

    def __post_init__(self):
        for name in ('min_area', 'max_components', 'max_pixels', 'birth_frames',
                     'merge_frames', 'corner_frames', 'split_frames',
                     'near_split_frames', 'loss_frames', 'max_manager_vertices', 'max_members'):
            if type(getattr(self, name)) is not int or getattr(self, name) < 1:
                raise ValueError(name)
        for name in ('proximity_pixels', 'max_motion_pixels',
                     'geometry_difference_fraction', 'geometry_boundary_pixels'):
            if not np.isfinite(getattr(self, name)) or getattr(self, name) < 0:
                raise ValueError(name)
        if self.geometry_difference_fraction > 0.1 or self.near_split_frames < self.split_frames:
            raise ValueError('unsafe hysteresis/geometry settings')


def signed_area(ring: np.ndarray) -> float:
    return float(np.sum(ring[:, 0] * np.roll(ring[:, 1], -1)
                        - ring[:, 1] * np.roll(ring[:, 0], -1)) / 2)


def cell_rings(mask: np.ndarray) -> tuple[np.ndarray, ...]:
    """Trace exposed cell edges. Right turns separate point-touching loops.

    No contour approximation, dilation, convex hull or rectangular substitution.
    Runtime is O(image pixels + boundary edges); exact collinear removal only.
    """
    p = np.pad(mask.astype(bool), 1)
    m = p[1:-1, 1:-1]
    edges = set()
    for exposed, offset, direction in (
        (m & ~p[:-2, 1:-1], (0, 0), (1, 0)),
        (m & ~p[1:-1, 2:], (1, 0), (0, 1)),
        (m & ~p[2:, 1:-1], (1, 1), (-1, 0)),
        (m & ~p[1:-1, :-2], (0, 1), (0, -1)),
    ):
        ys, xs = np.nonzero(exposed)
        for x, y in zip(xs.tolist(), ys.tolist()):
            a = (x + offset[0], y + offset[1])
            edges.add((a, (a[0] + direction[0], a[1] + direction[1])))
    outgoing = {}
    for a, b in edges:
        outgoing.setdefault(a, set()).add(b)
    codes = {(1, 0): 0, (0, 1): 1, (-1, 0): 2, (0, -1): 3}
    rank = {1: 0, 0: 1, 3: 2, 2: 3}
    rings = []
    while edges:
        a, b = min(edges)
        start = a
        ring = [a]
        while True:
            edges.remove((a, b))
            outgoing[a].remove(b)
            if b == start:
                break
            ring.append(b)
            prev = codes[(b[0] - a[0], b[1] - a[1])]
            choices = outgoing[b]
            nxt = min(choices, key=lambda c: rank[(codes[(c[0]-b[0], c[1]-b[1])] - prev) % 4])
            a, b = b, nxt
        points = np.array(ring, dtype=np.float64)
        before = points - np.roll(points, 1, axis=0)
        after = np.roll(points, -1, axis=0) - points
        cross = before[:, 0] * after[:, 1] - before[:, 1] * after[:, 0]
        rings.append(points[cross != 0])
    return tuple(sorted(rings, key=lambda r: (-abs(signed_area(r)), tuple(r[0]))))


@dataclass
class Region:
    mask: np.ndarray
    rings: tuple[np.ndarray, ...]
    center: np.ndarray
    area: int
    colors: dict[int, float]
    contact: str
    color_conflict_pixels: int
    bounds: tuple[int, int, int, int]

    @property
    def exterior_count(self):
        return sum(signed_area(r) > 0 for r in self.rings)


@dataclass
class Segmentation:
    masks: dict[int, np.ndarray]
    combined: np.ndarray
    regions: list[Region]
    proximity: list[dict]
    conflict_pixels: int
    rejected_pixels: int


class StructureSegmenter:
    def __init__(self, colors: list[ColorConfig], settings: StructureSettings | None = None):
        self.settings = settings or StructureSettings()
        if not colors or len(colors)>64 or len({c.id for c in colors}) != len(colors):
            raise ValueError('unique configured color IDs required')
        for c in colors:
            lo, hi = np.array(c.lower), np.array(c.upper)
            if (lo.shape != (3,) or hi.shape != (3,) or not np.isfinite(lo).all()
                    or not np.isfinite(hi).all() or (lo < 0).any() or (hi < 0).any()
                    or (lo > [179,255,255]).any() or (hi > [179,255,255]).any()
                    or (lo[1:] > hi[1:]).any() or not 0 <= c.min_saturation <= 255):
                raise ValueError('invalid HSV range')
        self.colors = colors

    def segment(self, image: np.ndarray) -> Segmentation:
        if image.dtype != np.uint8 or image.ndim != 3 or image.shape[2] != 3 or image.size == 0:
            raise ValueError('uint8 BGR image required')
        if image.shape[0] * image.shape[1] > self.settings.max_pixels:
            raise ValueError('image pixel limit')
        hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
        masks = {}
        for c in self.colors:
            lo = np.array(c.lower, dtype=np.uint8)
            hi = np.array(c.upper, dtype=np.uint8)
            lo[1] = max(int(lo[1]), c.min_saturation)
            if lo[0] <= hi[0]:
                raw = cv2.inRange(hsv, lo, hi)
            else:  # hue wraps, e.g. red
                a, b = lo.copy(), hi.copy()
                a[0], b[0] = 0, 179
                raw = cv2.inRange(hsv, lo, b) | cv2.inRange(hsv, a, hi)
            masks[c.id] = raw.astype(bool)
        coverage = np.zeros(image.shape[:2],dtype=np.uint8)
        for mask in masks.values():
            coverage += mask
        combined = coverage > 0
        count, labels, stats, centers = cv2.connectedComponentsWithStats(combined.astype('uint8'), connectivity=8)
        regions = []
        accepted = np.zeros_like(combined)
        for index in range(1, count):
            area = int(stats[index, cv2.CC_STAT_AREA])
            if area < self.settings.min_area:
                continue
            if len(regions) >= self.settings.max_components:
                raise ValueError('component limit: frame rejected atomically')
            mask = labels == index
            accepted |= mask
            x,y,w,h = map(int,stats[index,:4])
            crop = mask[y:y+h,x:x+w]
            n4, _, _, _ = cv2.connectedComponentsWithStats(crop.astype('uint8'), connectivity=4)
            eroded = cv2.erode(crop.astype('uint8'), np.ones((3,3),np.uint8),
                                borderType=cv2.BORDER_CONSTANT,borderValue=0)
            _, _, cores, _ = cv2.connectedComponentsWithStats(eroded, connectivity=8)
            large_cores = sum(int(s[cv2.CC_STAT_AREA]) >= self.settings.min_area for s in cores[1:])
            contact = 'CORNER' if n4 > 2 else ('AMBIGUOUS_THIN_BRIDGE' if large_cores > 1 else 'CONNECTED')
            weights = {c.id: float(np.count_nonzero(crop & masks[c.id][y:y+h,x:x+w]) / area) for c in self.colors}
            total = sum(weights.values())
            weights = {k: v/total for k,v in weights.items() if v > 0}
            rings = tuple(r+np.array([x,y]) for r in cell_rings(crop))
            regions.append(Region(mask, rings, centers[index] + .5, area,
                                  weights, contact, int(np.count_nonzero(crop & (coverage[y:y+h,x:x+w] > 1))), (x,y,w,h)))
        proximity = []
        for i, a in enumerate(regions):
            distance = None
            for j in range(i+1, len(regions)):
                ax,ay,aw,ah = a.bounds
                bx,by,bw,bh = regions[j].bounds
                dx=max(0,ax-(bx+bw),bx-(ax+aw))
                dy=max(0,ay-(by+bh),by-(ay+ah))
                if np.hypot(dx,dy) > self.settings.proximity_pixels+1:
                    continue  # bounding boxes only prune work; never replace geometry
                if distance is None:
                    distance = cv2.distanceTransform((~a.mask).astype('uint8'), cv2.DIST_L2, cv2.DIST_MASK_PRECISE)
                gap = max(0., float(distance[regions[j].mask].min()) - 1.)
                if gap <= self.settings.proximity_pixels + 1e-5:
                    proximity.append({'regions': [i,j], 'gap_pixels': gap, 'state': 'AMBIGUOUS_PROXIMITY'})
        return Segmentation(masks, accepted, regions, proximity, int(np.count_nonzero(coverage > 1)),
                            int(np.count_nonzero(combined & ~accepted)))

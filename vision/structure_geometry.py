"""Local geometry contract v1. No networking, capture or game side effects."""
from __future__ import annotations

import cv2
import numpy as np
from copy import deepcopy
from .structure_segmentation import signed_area, row_runs



def exact_rectangles(mask: np.ndarray, max_parts: int=512) -> tuple[np.ndarray,...]:
    """Partition ALL foreground cells; merge identical row runs vertically.

    Every rectangle is a convex region, not a bounding-box approximation.
    Parts have disjoint interiors and cover no background cells (including holes).
    """
    active={}
    rectangles=[]
    last_y=-1
    current=set()
    def finish_missing(keep):
        for key in list(active):
            if key not in keep:
                rectangles.append(active.pop(key))
    for y,left,right in row_runs(mask):
        if y!=last_y:
            if y!=last_y+1:
                finish_missing(set())
            else:
                finish_missing(current)
            current=set()
            last_y=y
        key=(left,right)
        if key in active and active[key][3]==y:
            active[key][3]=y+1
        else:
            if key in active: rectangles.append(active.pop(key))
            active[key]=[left,y,right,y+1]
        current.add(key)
        if len(rectangles)+len(active)>max_parts:
            raise ValueError('convex_part_limit')
    finish_missing(set())
    return tuple(np.array([[a,b],[c,b],[c,d],[a,d]],dtype=np.float64) for a,b,c,d in rectangles)


def build_contract(obj, max_parts: int=512) -> dict:
    """Export ACCEPTED geometry, not the latest unconfirmed observation.

    May raise ValueError; caller keeps previous valid geometry on rejection.
    Static geometry is cached per accepted revision/shape/pose-independent mask.
    """
    rings=obj.local_rings
    regions=[{'exterior':r.tolist(),'holes':[]} for r in rings if signed_area(r)>0]
    if not regions:
        raise ValueError('missing_exterior')
    for ring in rings:
        if len(np.unique(ring,axis=0))!=len(ring):
            raise ValueError('self_touching_ring')
        if signed_area(ring)<0:
            owners=[r for r in regions if cv2.pointPolygonTest(np.array(r['exterior'],np.float32),
                                                            tuple(map(float,ring[0])),False)>0]
            if len(owners)!=1:
                raise ValueError('ambiguous_hole_ownership')
            owners[0]['holes'].append(ring.tolist())
    # Raster partition from accepted mask, shifted to local coordinates.
    x,y,w,h=cv2.boundingRect(obj.geometry_mask.astype('uint8'))
    parts=exact_rectangles(obj.geometry_mask[y:y+h,x:x+w],max_parts)
    parts=np.asarray(parts)+np.array([x,y])-obj.position
    polygon_area=sum(signed_area(r) for r in rings)
    parts_area=float(np.sum((parts[:,2,0]-parts[:,0,0])*(parts[:,2,1]-parts[:,0,1])))
    if abs(polygon_area-parts_area)>1e-6:
        raise ValueError('accepted_rings_mask_area_mismatch')
    return {'contract_version':1,'id':obj.id,'geometry_version':obj.revision,
            'coordinate_space':'ARENA_PIXELS','source_space':'CAMERA_PIXEL_CELL_EDGES',
            'mapping':'IDENTITY_SYNTHETIC_LAB_ONLY','units':'pixels','axis':'X_RIGHT_Y_DOWN',
            'position':obj.position.tolist(),'orientation_radians':0.0,
            'regions':regions,'convex_parts':parts.tolist(),
            'tracking':{'state':'HELD' if obj.stale_frames else 'TRACKED',
                        'age_frames':obj.stale_frames},
            # Evidence score, deliberately not a calibrated probability.
            'confidence':0.0 if obj.stale_frames else max(0.,1.-obj.region.color_conflict_pixels/obj.region.area),
            'confidence_kind':'VISIBLE_NONCONFLICTING_PIXEL_FRACTION_NOT_PROBABILITY',
            'member_ids':[m.id for m in obj.members]}


class ContractExporter:
    """Bounded exact-shape cache. Consumers own the returned JSON-compatible data."""
    def __init__(self,max_parts=512):
        self.max_parts=max_parts
        self._cache={}
        self.builds=0

    def export(self,objects):
        result=[]
        keep={}
        for obj in objects:
            key=(obj.id,obj.revision,tuple(r.tobytes() for r in obj.local_rings))
            if key not in self._cache:
                self._cache[key]=build_contract(obj,self.max_parts)
                self.builds+=1
            data=deepcopy(self._cache[key])
            data['position']=obj.position.tolist()
            data['tracking']={'state':'HELD' if obj.stale_frames else 'TRACKED','age_frames':obj.stale_frames}
            data['confidence']=0.0 if obj.stale_frames else max(0.,1.-obj.region.color_conflict_pixels/obj.region.area)
            data['member_ids']=[m.id for m in obj.members]
            keep[key]=self._cache[key]
            result.append(data)
        self._cache=keep
        return result

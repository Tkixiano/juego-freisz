"""Opt-in synthetic preparation: camera CELL edges -> calibrated arena CELL edges.

No camera, window, projector, network or configuration-writing side effects.
The existing material/geometry contracts remain the only physical representation.
"""
from copy import deepcopy
from dataclasses import dataclass
import hashlib
import json
import math
import cv2
import numpy as np
from vision.projection import ProjectionCalibration,transform,resolution
from vision.material_structures import validate_material_contract
from vision.structure_segmentation import signed_area

MAPPING='CALIBRATED_CAMERA_TO_ARENA_V1'

@dataclass(frozen=True)
class ImageLayout:
    capture_size: tuple
    processed_size: tuple
    crop: tuple|None=None
    def validate(self):
        raw=resolution(self.capture_size);processed=resolution(self.processed_size)
        crop=self.crop or (0,0,*raw)
        if len(crop)!=4 or not np.isfinite(crop).all() or crop[0]<0 or crop[1]<0 or min(crop[2:])<=0 or crop[0]+crop[2]>raw[0] or crop[1]+crop[3]>raw[1]:raise ValueError('invalid_capture_crop')
        return raw,processed,tuple(crop)

class CalibratedGeometryMapper:
    def __init__(self,calibration: ProjectionCalibration,layout: ImageLayout,*,mirror=False,camera_index=0,backend='dshow',arena_size=(1280,720),arena_rect=None):
        self.calibration=deepcopy(calibration).validate()
        raw,self.processed_size,crop=layout.validate()
        self.calibration.compatible(raw,mirror,camera_index,backend)
        self.arena_size=resolution(arena_size);self.arena_rect=tuple(arena_rect or (0,0,*self.arena_size))
        x,y,w,h=self.arena_rect
        if not np.isfinite(self.arena_rect).all() or min(x,y)<0 or min(w,h)<=0 or x+w>self.arena_size[0] or y+h>self.arena_size[1]:raise ValueError('invalid_arena_rect')
        # Geometry uses edges at integers and centres at n+.5; OpenCV H uses
        # pixel centres at integers. Account for both half-pixel conventions.
        sx,sy=crop[2]/self.processed_size[0],crop[3]/self.processed_size[1]
        before=np.array([[sx,0,crop[0]-.5],[0,sy,crop[1]-.5],[0,0,1]],float)
        ax,ay=w/self.calibration.projection_size[0],h/self.calibration.projection_size[1]
        after=np.array([[ax,0,x+ax*.5],[0,ay,y+ay*.5],[0,0,1]],float)
        self.matrix=after@self.calibration.matrix@before
        self.camera_matrix=before
        self.affine=bool(np.array_equal(self.matrix[2,:2],[0,0]))
        self.fit_hull=cv2.convexHull(self.calibration.fit_camera.astype(np.float32))
        signature=dict(h=self.calibration.matrix.tolist(),capture=raw,processed=self.processed_size,crop=crop,mirror=mirror,index=camera_index,backend=backend,projection=self.calibration.projection_size,arena=self.arena_size,rect=self.arena_rect)
        self.signature=hashlib.sha256(json.dumps(signature,sort_keys=True,separators=(',',':')).encode()).hexdigest()
        self.ledger={};self.region_ledger={}

    def map_points(self,points):
        p=np.asarray(points,dtype=np.float64)
        if p.ndim!=2 or p.shape[1]!=2 or not len(p) or not np.isfinite(p).all():raise ValueError('invalid_points')
        if np.any(p<0) or np.any(p>self.processed_size):raise ValueError('outside_processed_image')
        camera=transform(self.camera_matrix,p)
        if any(cv2.pointPolygonTest(self.fit_hull,tuple(v),False)<-1e-5 for v in camera):raise ValueError('outside_calibrated_area')
        # Vertex denominators share a sign: no edge/polygon crosses infinity.
        denominator=p@self.matrix[2,:2]+self.matrix[2,2]
        if np.any(np.abs(denominator)<1e-8) or np.any(np.sign(denominator)!=np.sign(denominator[0])):raise ValueError('geometry_crosses_horizon')
        result=transform(self.matrix,p)
        x,y,w,h=self.arena_rect
        if np.any(result<[x-1e-6,y-1e-6]) or np.any(result>[x+w+1e-6,y+h+1e-6]):raise ValueError('outside_arena_rect')
        return result

    @staticmethod
    def _version(id,epoch,source_version,geometry,ledger):
        key=json.dumps(geometry,sort_keys=True,separators=(',',':'),allow_nan=False)
        old=ledger.get(id)
        if old and epoch<old['epoch']:raise ValueError('old_identity_epoch')
        if old and epoch==old['epoch'] and source_version<old['source']:raise ValueError('old_source_geometry_version')
        version=max(source_version,old['version']+int(key!=old['key'])) if old else source_version
        ledger[id]=dict(epoch=epoch,source=source_version,key=key,version=version)
        return version

    def map_frame(self,frame):
        if frame.get('spatial_mapping') or any(c.get('mapping')==MAPPING for c in frame['structures']):raise ValueError('already_calibrated_geometry')
        roots=deepcopy(self.ledger);regions=deepcopy(self.region_ledger)
        output=deepcopy(frame)
        for c in output['structures']:
            validate_material_contract(c)
            position=np.asarray(c['position'],float);angle=c['orientation_radians']
            rotation=np.array([[math.cos(angle),-math.sin(angle)],[math.sin(angle),math.cos(angle)]])
            anchor=self.map_points([position])[0]
            def ring(raw,positive=True):
                local=np.asarray(raw,float);world=local@rotation.T+position
                projected=self.map_points(world)
                # Exact affine local transform avoids pose-dependent cancellation.
                local_result=(local@rotation.T)@self.matrix[:2,:2].T/self.matrix[2,2] if self.affine else projected-anchor
                if (signed_area(local_result)>0)!=positive:local_result=local_result[::-1]
                return local_result.tolist()
            def geometry(data):
                return dict(regions=[dict(exterior=ring(r['exterior']),holes=[ring(h,False) for h in r['holes']]) for r in data['regions']],convex_parts=[ring(p) for p in data['convex_parts']])
            parent=geometry(c);material=[]
            for r in c['material_regions']:
                mapped=geometry(r);r.update(mapped)
                r['geometry_version']=self._version(r['region_id'],frame['region_identity_epochs'][r['region_id']],r['geometry_version'],dict(material=r['material'],**mapped),regions)
                material.append(r)
            c.update(parent,position=anchor.tolist(),orientation_radians=0.0,mapping=MAPPING)
            c['geometry_version']=self._version(c['id'],frame['identity_epochs'][c['id']],c['geometry_version'],dict(**parent,material_regions=material),roots)
            validate_material_contract(c)
        if len(roots)>4096 or len(regions)>4096:raise ValueError('mapping_identity_budget_new_session_required')
        output['spatial_mapping']=dict(version=1,space='GODOT_ARENA_PIXELS',arena_size=list(self.arena_size),arena_rect=list(self.arena_rect),calibration_signature=self.signature,cell_convention='PIXEL_CELL_EDGES',mapping=MAPPING)
        self.ledger,self.region_ledger=roots,regions
        return output

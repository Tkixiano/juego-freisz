"""Generate ONLY synthetic calibration/geometry fixtures and overhead measurements."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
from time import perf_counter_ns
from unittest.mock import patch
import cv2
import numpy as np
from tests.test_calibrated_geometry import calibration,frame,mapper
from tests.benchmark_states import state
from vision.calibrated_geometry import CalibratedGeometryMapper,ImageLayout
from vision.calibrated_source import CalibratedMaterialSource
from vision.projection import transform
from vision.projection_pattern import pattern,detect_references
from vision.projector_calibration import CalibrationSession
from vision.config import CameraConfig
from vision.material_replay import labels
from vision.material_synthetic import bgr

def summary(a):return {k:float(np.percentile(a,q)) for k,q in [('p50',50),('p95',95),('p99',99)]}|{'mean':float(np.mean(a)),'n':len(a)}
def main():
    p=argparse.ArgumentParser();p.add_argument('--frames',type=int,default=80);a=p.parse_args()
    if not 20<=a.frames<=600:p.error('frames 20..600')
    out=Path('artifacts/preparation');out.mkdir(exist_ok=True)
    with patch('cv2.VideoCapture',side_effect=AssertionError('NO HARDWARE')):
        fit_time=[];validation_time=[]
        for _ in range(20):
            t=perf_counter_ns();c=calibration();fit_time.append((perf_counter_ns()-t)/1e6)
            t=perf_counter_ns();deepcopy(c).validate();validation_time.append((perf_counter_ns()-t)/1e6)
        c.save(out/'SYNTHETIC_calibration.json')
        cases={}
        for name,kind,h in [('solid','solid',None),('three','three',None),('hole','hole',None),('corner','corner',None),('perspective_solid','solid',[[2,.03,0],[.01,1.3,30],[.0001,.00005,1]]),('perspective_hole','hole',[[2,.03,0],[.01,1.3,30],[.0001,.00005,1]])]:
            f=mapper(h).map_frame(frame(kind));f.update(sequence=1,logical_time=0,scene_state='SCENE_ACTIVE');cases[name]=f
        source=CalibratedMaterialSource(mapper());sequence=[]
        stages=[(bgr(labels('three',True)),'OK',12),(None,'DISCONNECTED',2),(None,'STALE',2),(bgr(labels('three',True)),'OK',4),(np.zeros((480,640,3),np.uint8),'OK',14),(bgr(labels('three',True)),'OK',12)]
        for image,health,n in stages:
            for _ in range(n):sequence.append(source.update(image,health))
        cases['health_sequence']=sequence
        timing={}
        for count in [1,4,8,16,32,64]:
            f=state(count)
            for i,s in enumerate(f['structures']):s['position']=[130+i%8*55,170+i//8*50]
            m=mapper();values=[]
            for i in range(a.frames+8):
                current=deepcopy(f)
                for s in current['structures']:s['position'][0]+=(i%10)*.1
                t=perf_counter_ns();m.map_frame(current);elapsed=(perf_counter_ns()-t)/1e6
                if i>=8:values.append(elapsed)
            timing[str(count)]=summary(values)
        # Independent ArUco checks on an OFFLINE generated image.
        target=np.float32([[0,0],[1279,0],[1279,719],[0,719]])
        warped=np.float32([[80,50],[1190,30],[1220,680],[30,650]])
        h=cv2.getPerspectiveTransform(target,warped)
        image=cv2.warpPerspective(pattern(),h,(1280,720),borderValue=(255,255,255))
        found,diagnostic=detect_references(image)
        marker_calibration=CalibrationSession(CameraConfig(width=1280,height=720),out/'NEVER_saved.json').build(found,(1280,720))
        points=np.array([[160,300],[200,300],[350,320],[460,330]],float);m=mapper()
        expected=transform(c.matrix,points-.5)+.5
        error=np.linalg.norm(m.map_points(points)-expected,axis=1)
        result=dict(synthetic_only=True,transform_ms=timing,fit_and_validation_ms=summary(fit_time),calibration_validation_ms=summary(validation_time),point_max_error_px=float(error.max()),analytic_fit_errors=c.errors,aruco_warp_errors=marker_calibration.errors,aruco_diagnostics=diagnostic,convention='pixel cell edges -> camera centres -.5 -> projector centres -> arena edges +.5',notes='Overhead only; not complete vision/UDP/physics FPS. Camera/projector never opened.')
        Path('juegofrei/validation/calibration_preparation_cases.json').write_text(json.dumps(cases,allow_nan=False),encoding='utf-8')
        (out/'metrics.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps(result))
if __name__=='__main__':main()

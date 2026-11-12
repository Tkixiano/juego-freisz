"""Finite, synthetic geometric regression corpus and pre/post mapping timings."""
from copy import deepcopy
import json
from pathlib import Path
from time import perf_counter_ns
from unittest.mock import patch
import numpy as np
from vision.calibrated_geometry import CalibratedGeometryMapper,ImageLayout
from vision.material_replay import MaterialReplayExporter
from vision.material_synthetic import bgr
from tests.test_calibrated_geometry import calibration,frame,mapper
from tests.perspective_hole_repro import H
from tests.perspective_mapper_reference import CalibratedGeometryMapper as ReferenceMapper

def from_mask(mask):
    e=MaterialReplayExporter()
    for _ in range(12):f=e.append_image(bgr(mask))
    if f['diagnostic']['status']!='TRACKING':raise ValueError(f['diagnostic'])
    return f

def masks():
    near=np.zeros((480,640),np.uint8);near[250:380,170:340]=1;near[251:379,171:339]=0
    concave=np.zeros_like(near);concave[250:390,160:360]=1;concave[250:300,300:360]=0;concave[285:350,185:250]=0
    multiple=np.zeros_like(near);multiple[250:390,140:360]=1;multiple[275:360,165:205]=0;multiple[280:340,230:280]=0;multiple[270:370,300:340]=0
    multiple[320:350,360:410]=3
    mixed=np.zeros_like(near);mixed[250:390,140:360]=1;mixed[280:360,180:320]=0;mixed[320:350,360:410]=3;mixed[250:265,200:260]=2
    blue=np.zeros_like(near);blue[250:390,140:360]=2;blue[280:360,180:320]=0;blue[320:350,360:410]=3
    return dict(near_exterior=near,concave_hole=concave,multiple_holes=multiple,mixed_materials=mixed,blue_hole=blue)

def generate():
    root=Path('artifacts/perspective_hole');root.mkdir(exist_ok=True)
    frozen=json.loads((root/'reproduction.json').read_text(encoding='utf-8'))
    original=frozen['original'];cases={}
    sources={'original':original,**{name:from_mask(mask) for name,mask in masks().items()}}
    rotated=deepcopy(original);rotated['structures'][0]['orientation_radians']=.17;sources['rotated']=rotated
    extreme=deepcopy(original)
    for c in extreme['structures']:c['position'][1]-=100
    sources['extreme']=extreme
    axis=deepcopy(original)
    for c in axis['structures']:c['position'][0]+=20
    sources['axis_rotation']=axis
    for name,f in sources.items():
        if name=='extreme':m=mapper([[3.2,.02,0],[.02,2.2,15],[.001,.0002,1]])
        elif name=='axis_rotation':
            c=calibration([[0,-1,1279],[1,0,0],[0,0,1]],(1280,1280));m=CalibratedGeometryMapper(c,ImageLayout((1280,1280),(1280,1280)))
        else:m=mapper(H)
        mapped=m.map_frame(f);mapped.update(sequence=1,logical_time=0,scene_state='SCENE_ACTIVE')
        cases[name]=mapped
    cases['unwelded_original']=frozen['transformed']
    invalid={}
    for name in ['filled_hole','touching_hole','outside_hole','duplicate_vertex','self_intersection','degenerate_part','partial_crop']:
        bad=deepcopy(cases['original']);c=bad['structures'][0]
        if name=='filled_hole':
            part=c['regions'][0]['holes'][0][::-1];c['convex_parts'].append(part);c['material_regions'][0]['convex_parts'].append(part)
        elif name=='touching_hole':c['regions'][0]['holes'][0][0]=deepcopy(c['regions'][0]['exterior'][0])
        elif name=='outside_hole':c['regions'][0]['holes'][0]=[[x+900,y] for x,y in c['regions'][0]['holes'][0]]
        elif name=='duplicate_vertex':c['regions'][0]['exterior'][1]=deepcopy(c['regions'][0]['exterior'][0])
        elif name=='self_intersection':c['regions'][0]['exterior'][1],c['regions'][0]['exterior'][3]=c['regions'][0]['exterior'][3],c['regions'][0]['exterior'][1]
        elif name=='degenerate_part':c['convex_parts'][0]=[[0,0],[1,0],[2,0]]
        elif name=='partial_crop':c['position'][0]+=1200
        invalid[name]=bad
    payload=dict(valid=cases,invalid=invalid)
    Path('juegofrei/validation/perspective_hole_cases.json').write_text(json.dumps(payload,allow_nan=False),encoding='utf-8')
    times={}
    for name,cls in [('before',ReferenceMapper),('after',CalibratedGeometryMapper)]:
        m=cls(calibration(H),ImageLayout((640,480),(640,480)));values=[]
        for i in range(110):
            t=perf_counter_ns();m.map_frame(original);elapsed=(perf_counter_ns()-t)/1e6
            if i>=10:values.append(elapsed)
        times[name]=dict(samples_ms=values,mean=float(np.mean(values)),p50=float(np.percentile(values,50)),p95=float(np.percentile(values,95)),p99=float(np.percentile(values,99)))
    (root/'mapping_performance.json').write_text(json.dumps(times,indent=2),encoding='utf-8')
    print('cases',list(cases),'parts',len(cases['original']['structures'][0]['convex_parts']))
    return payload

if __name__=='__main__':
    with patch('cv2.VideoCapture',side_effect=AssertionError('NO HARDWARE')):generate()

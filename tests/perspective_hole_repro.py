"""Isolated numerical diagnosis; no production mutation or capture."""
from decimal import Decimal,localcontext
import json
from pathlib import Path
import numpy as np
from tests.test_calibrated_geometry import frame,calibration
from tests.perspective_mapper_reference import CalibratedGeometryMapper as ReferenceMapper
from vision.calibrated_geometry import ImageLayout
from vision.structure_segmentation import signed_area

H=[[2,.03,0],[.01,1.3,30],[.0001,.00005,1]]

def clip_area(a,b):
    """Convex intersection oracle, Decimal80, strict half-planes, no tolerance."""
    with localcontext() as ctx:
        ctx.prec=80
        def points(r):return [[Decimal.from_float(float(x)),Decimal.from_float(float(y))] for x,y in r]
        a,b=points(a),points(b)
        def cross(p,q,r):return (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0])
        area=lambda r:sum(r[i][0]*r[(i+1)%len(r)][1]-r[(i+1)%len(r)][0]*r[i][1] for i in range(len(r)))/2 if r else Decimal(0)
        if area(b)<0:b.reverse()
        for i,p in enumerate(b):
            q=b[(i+1)%len(b)];result=[]
            if not a:break
            previous=a[-1];d0=cross(p,q,previous)
            for current in a:
                d1=cross(p,q,current)
                if (d0>=0)!=(d1>=0):
                    t=d0/(d0-d1);result.append([previous[k]+t*(current[k]-previous[k]) for k in range(2)])
                if d1>=0:result.append(current)
                previous,d0=current,d1
            a=result
        return float(abs(area(a))),[[float(v) for v in p] for p in a]

def main():
    output=Path('artifacts/perspective_hole');output.mkdir(exist_ok=True)
    original=frame('hole');m=ReferenceMapper(calibration(H),ImageLayout((640,480),(640,480)))
    mapped=m.map_frame(original);c=mapped['structures'][0];hole=c['regions'][0]['holes'][0]
    pairs=[]
    for index,part in enumerate(c['convex_parts']):
        double,vertices=clip_area(part,hole)
        single,vertices32=clip_area(np.asarray(part,np.float32),np.asarray(hole,np.float32))
        pairs.append(dict(index=index,float64_overlap=double,float32_exact_overlap=single,float64_intersection=vertices,float32_exact_intersection=vertices32))
    record=dict(homography=H,composed_matrix=m.matrix.tolist(),original=original,transformed=mapped,
        final_world=[dict(exterior=(np.asarray(r['exterior'])+c['position']).tolist(),holes=[(np.asarray(h)+c['position']).tolist() for h in r['holes']]) for r in c['regions']],
        original_areas=[dict(exterior=signed_area(np.asarray(r['exterior'])),holes=[signed_area(np.asarray(h)) for h in r['holes']]) for r in original['structures'][0]['regions']],
        areas=[dict(exterior=signed_area(np.asarray(r['exterior'])),holes=[signed_area(np.asarray(h)) for h in r['holes']]) for r in c['regions']],
        part_hole_pairs=pairs,notes='Decimal80 oracle computes intersections of the EXACT supplied float64 or float32 coordinates. No epsilon or camera.')
    (output/'reproduction.json').write_text(json.dumps(record,indent=2),encoding='utf-8')
    (output/'minimal_pair.json').write_text(json.dumps(dict(part=c['convex_parts'][pairs.index(max(pairs,key=lambda p:p['float32_exact_overlap']))],hole=hole)),encoding='utf-8')
    print(json.dumps(pairs,indent=2))
if __name__=='__main__':main()

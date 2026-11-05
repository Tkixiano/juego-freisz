"""Synthetic OpenCV -> complete offline snapshots. No capture or network imports."""
from __future__ import annotations
import argparse
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import numpy as np
from .config import Config
from .structure_segmentation import StructureSegmenter
from .structure_tracking import StructureTracker
from .structure_geometry import ContractExporter


def geometry_key(c):
    return hashlib.sha256(json.dumps({k:c[k] for k in ('regions','convex_parts')},
                                    sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


class ReplayExporter:
    """Full recovery state every frame; monotone versions survive ID retirement."""
    def __init__(self,hz=30,max_ids=4096):
        if type(hz) is not int or not 1<=hz<=120:raise ValueError('hz')
        self.hz=hz;self.max_ids=max_ids;self.sequence=0
        self.ledger={};self.epochs={};self.active=set()
        self.segmenter=StructureSegmenter(Config().colors)
        self.tracker=StructureTracker();self.contracts=ContractExporter()

    def append_image(self,image):
        snapshot=self.tracker.update(self.segmenter.segment(image))
        structures=self.contracts.export(self.tracker.objects.values())
        for c in structures:
            id=c['id'];key=geometry_key(c)
            if id not in self.ledger and len(self.ledger)>=self.max_ids:raise ValueError('identity_limit')
            previous=self.ledger.get(id)
            version=1 if previous is None else previous[0]+int(previous[1]!=key)
            c['geometry_version']=version;self.ledger[id]=(version,key)
            if id not in self.active:self.epochs[id]=self.epochs.get(id,0)+1
        self.active={c['id'] for c in structures}
        self.sequence+=1
        return {'sequence':self.sequence,'logical_time':(self.sequence-1)/self.hz,
                'structures':structures,'identity_epochs':{id:self.epochs[id] for id in sorted(self.active)},
                'events':[deepcopy(e) for e in snapshot['events'] if e['type'] in ('MERGE','SPLIT')],
                'diagnostic':{'tracking_status':snapshot['status'],'observed_components':snapshot['observed_components']}}


def image(rectangles):
    im=np.zeros((480,640,3),np.uint8)
    for x,y,w,h,color in rectangles:
        im[y:y+h,x:x+w]=(0,220,0) if color==1 else (220,0,0)
    return im


def export_scenarios(output:Path,long_frames=3600):
    output.mkdir(parents=True,exist_ok=True)
    a=[(120,300,100,40,1)];two=a+[(240,300,100,40,2)]
    merged=a+[(220,300,100,40,2)]
    three=a+[(220,300,100,40,2),(320,300,100,40,1)]
    three_sep=a+[(240,300,100,40,2),(360,300,100,40,1)]
    corner=[(120,300,100,40,1),(220,340,100,40,2)]
    hole=[(120,280,180,20,1),(120,300,20,100,1),(280,300,20,100,2),(120,400,180,20,2)]
    specs=[
        ('01_creation',[(a,12)]),
        ('02_movement',[(a,8)]+[([(120+i,300,100,40,1)],1) for i in range(60)]),
        ('03_rotation',[(a,12)]),
        ('04_silhouette',[(a,12), (a+[(120,340,25,40,1)],12)]),
        ('05_two',[(two,15)]),('06_merge',[(two,15),(merged,15)]),
        ('07_split',[(two,15),(merged,15),(two,15)]),
        ('08_three_merge',[(three_sep,15),(three,15)]),
        ('09_hole',[(hole,15)]),('10_corner',[(corner,15)]),
        ('11_removal',[(a,15),([],15)]),('12_reappearance',[(a,15),([],15),(a,15)]),
        ('13_duplicate',[(a,15)]),('14_out_of_order',[(a,15)]),
        ('15_invalid_geometry',[(a,15)]),
        ('16_occupied_change',[(a,45), ([(120,290,100,50,1)],15)]),
        ('17_occupied_merge',[(two,45),(merged,15)]),
        ('18_occupied_split',[(two,15),(merged,45),(two,15)]),
        ('19_simultaneous',[(two,8)]+[([(120+i,300,100,40,1),(240+i,300,100,40,2)],1) for i in range(60)]),
        ('20_long',[(two if (i//60)%2==0 else merged,1) for i in range(long_frames)])]
    manifest=[]
    for name,stages in specs:
        exporter=ReplayExporter();frames=[]
        for rects,n in stages:
            for _ in range(n):frames.append(exporter.append_image(image(rects)))
        if name=='03_rotation':
            initial=deepcopy(frames[-1]);frames=frames[:8]
            for i in range(60):
                f=deepcopy(initial);f['sequence']=len(frames)+1;f['logical_time']=(f['sequence']-1)/30
                for c in f['structures']:c['orientation_radians']=i*.002
                f['events']=[];frames.append(f)
        if name=='13_duplicate':frames.insert(10,deepcopy(frames[9]))
        if name=='14_out_of_order':frames.insert(12,deepcopy(frames[5]))
        if name=='15_invalid_geometry':
            frames[10]['structures'][0]['convex_parts'][0]=[[0,0],[1,0],[2,0]]
            frames[10]['structures'][0]['geometry_version']=2
        payload={'replay_version':1,'geometry_contract_version':1,'synthetic_only':True,
                 'tick_hz':30,'scenario':name,'frames':frames}
        path=output/(name+'.json');path.write_text(json.dumps(payload,separators=(',',':'),allow_nan=False),encoding='utf-8')
        manifest.append({'scenario':name,'file':path.name,'frames':len(frames),
                         'merge':sum(e['type']=='MERGE' for f in frames for e in f['events']),
                         'split':sum(e['type']=='SPLIT' for f in frames for e in f['events'])})
    (output/'manifest.json').write_text(json.dumps({'replay_version':1,'scenarios':manifest},indent=2))
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('juegofrei/validation/replays'))
    parser.add_argument('--long-frames',type=int,default=3600)
    args=parser.parse_args()
    if not 120<=args.long_frames<=10000:parser.error('long-frames must be 120..10000')
    result=export_scenarios(args.output,args.long_frames)
    print(json.dumps({'scenarios':len(result),'frames':sum(r['frames'] for r in result),'output':str(args.output)}))


if __name__=='__main__':main()

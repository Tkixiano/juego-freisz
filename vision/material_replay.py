"""Synthetic OpenCV multimaterial -> versioned FULL offline snapshots. No I/O devices/network."""
from __future__ import annotations
import argparse
from copy import deepcopy
import json
from pathlib import Path
import uuid
import numpy as np
from .material_structures import MaterialStructures, validate_material_contract
from .material_synthetic import bgr


class MaterialReplayExporter:
    def __init__(self, hz=30, session=None, *, config=None, settings=None):
        if type(hz) is not int or not 1 <= hz <= 60: raise ValueError('hz')
        self.hz=hz;self.session=uuid.uuid4().hex if session is None else session
        if not isinstance(self.session,str) or not 1<=len(self.session)<=64:raise ValueError('session')
        self.pipeline=MaterialStructures(config,settings);self.frames=[];self.region_epochs={};self.active=set()

    def append_image(self, image):
        s=self.pipeline.update(image)
        current={r['region_id'] for c in s['structures'] for r in c['material_regions']}
        for id in current-self.active:self.region_epochs[id]=self.region_epochs.get(id,0)+1
        self.active=current
        for c in s['structures']:validate_material_contract(c)
        frame=dict(session_id=self.session,sequence=s['sequence'],logical_time=(s['sequence']-1)/self.hz,
                   structures=s['structures'],identity_epochs=s['identity_epochs'],
                   region_identity_epochs={id:self.region_epochs[id] for id in sorted(current)},
                   events=s['events'],material_events=s['material_events'],
                   diagnostic=dict(status=s['status'],source_frame=s['source_frame'],errors=s['errors']))
        self.frames.append(frame)
        return frame

    def payload(self, name):
        return dict(replay_version=2,geometry_contract_version=1,material_contract_version=1,
                    session_id=self.session,synthetic_only=True,tick_hz=self.hz,scenario=name,frames=self.frames)


def labels(kind='solid', joined=False):
    a=np.zeros((480,640),np.uint8)
    color={'solid':1,'bounce':2,'one_way':3}.get(kind,1)
    a[300:330,160:260]=color
    if kind in ('green_orange','green_blue','blue_orange','three','two'):
        a[300:330,160:260]=2 if kind=='blue_orange' else 1
        a[300:330,260 if joined else 290:360 if joined else 390]=3 if kind in ('green_orange','blue_orange','three') else 2
        if kind=='three':a[300:330,360 if joined else 420:460 if joined else 520]=2
    if kind=='hole':
        a[:]=0;a[250:390,140:360]=1;a[280:360,180:320]=0;a[320:350,360:410]=3
    if kind=='corner':a[330:360,260:340]=3
    return a


def export_scenarios(output: Path,long_frames=600,only=None):
    if not 120<=long_frames<=10000:raise ValueError('long_frames')
    output.mkdir(parents=True,exist_ok=True)
    two=labels('two');merge=labels('two',True);empty=np.zeros((480,640),np.uint8)
    a=labels();silhouette=a.copy();silhouette[330:360,160:190]=1
    definitions=[
        ('01_solid',[(a,12)]),('02_bounce',[(labels('bounce'),12)]),('03_one_way',[(labels('one_way'),12)]),
        ('04_green_orange',[(labels('green_orange',True),12)]),('05_green_blue',[(merge,12)]),
        ('06_blue_orange',[(labels('blue_orange',True),12)]),('07_three',[(labels('three',True),12)]),
        ('08_merge',[(two,12),(merge,12)]),('09_split',[(two,12),(merge,12),(two,12)]),
        ('10_cycles',[(two if i%2==0 else merge,12) for i in range(8)]),
        ('11_hole',[(labels('hole'),12)]),('12_corner',[(labels('corner'),12)]),
        ('13_movement',[(a,12)]+[(np.roll(a,i,axis=1),1) for i in range(30)]),
        ('14_rotation',[(a,12)]),('15_silhouette',[(a,12),(silhouette,12)]),
        ('16_material',[(a,12),(labels('one_way'),12)]),
        ('17_removal',[(a,12),(empty,12)]),('18_reappearance',[(a,12),(empty,12),(a,12)]),
        ('19_supported_merge',[(two,45),(merge,20)]),('20_supported_split',[(two,12),(merge,45),(two,20)]),
        ('21_mobile_one_way',[(labels('one_way'),12)]),('22_mobile_bounce',[(labels('bounce'),12)]),
        ('23_duplicate',[(a,12)]),('24_old',[(a,12)]),('25_invalid',[(a,12)]),
        ('26_long',[(two if (i//30)%2==0 else merge,1) for i in range(long_frames)]),
        ('27_orange_merge_split',[(labels('green_orange'),12),(labels('green_orange',True),12),(labels('green_orange'),12)])]
    only=set(only or [])
    if only-{name for name,stages in definitions}:raise ValueError('unknown_scenario')
    manifest=[]
    if only and (output/'manifest.json').exists():
        manifest=[r for r in json.loads((output/'manifest.json').read_text(encoding='utf-8'))['scenarios'] if r['scenario'] not in only]
    for name,stages in definitions:
        if only and name not in only:continue
        e=MaterialReplayExporter(session='synthetic-'+name)
        # Reuse exact images' results, but STILL run segmentation/tracking per frame.
        for mask,n in stages:
            image=bgr(mask)
            for _ in range(n):e.append_image(image)
        if name in ('14_rotation','21_mobile_one_way','22_mobile_bounce'):
            initial=deepcopy(e.frames[-1])
            for i in range(1,46):
                f=deepcopy(initial);f.update(sequence=len(e.frames)+1,logical_time=len(e.frames)/30,events=[],material_events=[])
                for c in f['structures']:
                    if name=='14_rotation':c['orientation_radians']=i*.003
                    else:c['position'][0]+=i*.5;c['position'][1]-=i*.15
                e.frames.append(f)
        if name=='23_duplicate':e.frames.insert(10,deepcopy(e.frames[9]))
        if name=='24_old':e.frames.insert(11,deepcopy(e.frames[5]))
        if name=='25_invalid':
            e.frames[10]['structures'][0]['material_regions'][0]['convex_parts'][0]=[[0,0],[1,0],[2,0]]
            e.frames[10]['structures'][0]['geometry_version']+=1
        payload=e.payload(name)
        path=output/(name+'.json');path.write_text(json.dumps(payload,separators=(',',':'),allow_nan=False),encoding='utf-8')
        manifest.append(dict(scenario=name,file=path.name,frames=len(e.frames),
                             expected_rejections=int(name in ('23_duplicate','24_old','25_invalid')),
                             merges=sum(x['type']=='MERGE' for f in e.frames for x in f['events']),
                             splits=sum(x['type']=='SPLIT' for f in e.frames for x in f['events'])))
    manifest.sort(key=lambda r:r['scenario'])
    (output/'manifest.json').write_text(json.dumps(dict(replay_version=2,scenarios=manifest),indent=2),encoding='utf-8')
    return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('juegofrei/validation/material_replays'))
    parser.add_argument('--long-frames',type=int,default=600)
    parser.add_argument('--scenario',action='append',help='Export only named scenarios, retaining other manifest entries')
    args=parser.parse_args()
    result=export_scenarios(args.output,args.long_frames,args.scenario)
    print(json.dumps(dict(scenarios=len(result),frames=sum(r['frames'] for r in result),output=str(args.output))))

if __name__=='__main__':main()

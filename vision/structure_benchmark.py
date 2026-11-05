"""Repeatable synthetic CPU benchmark; no capture/render/network or Godot FPS."""
from __future__ import annotations
import argparse
import importlib
import json
from pathlib import Path
import sys
import time
import types
import cv2
import numpy as np
from .config import Config
from .structure_segmentation import StructureSegmenter
from .structure_tracking import StructureTracker
from .structure_geometry import ContractExporter


def stats(values):
    return {'mean':float(np.mean(values)),'p50':float(np.percentile(values,50)),
            'p95':float(np.percentile(values,95)),'p99':float(np.percentile(values,99)),
            'max':max(values)}


def image(index,workload,width=640,height=480):
    im=np.zeros((height,width,3),np.uint8)
    if workload=='translation':
        x=50+index%20
        im[150:230,x:x+90]=(0,220,0)
        im[150:230,300:390]=(220,0,0)
    elif workload=='topology':
        im[150:230,100:190]=(0,220,0)
        x=190 if (index//10)%2 else 215
        im[150:230,x:x+90]=(220,0,0)
    else:
        # Every frame changes a genuine silhouette; exact geometry, no cache trick.
        shape=np.zeros((height,width),np.uint8)
        shape[150:240,120:150]=1;shape[210:240,150:220]=1
        shape=cv2.warpAffine(shape,cv2.getRotationMatrix2D((170,195),(index%36)*2,1),
                             (width,height),flags=cv2.INTER_NEAREST)
        im[shape>0]=(0,220,0)
    return im


def run(label,segmenter_class,tracker_class,frames,warmup,workload):
    segmenter=segmenter_class(Config().colors);tracker=tracker_class();exporter=ContractExporter()
    all_times=[];stage_rows=[];before_export=[]
    events={'MERGE':0,'SPLIT':0};errors=[]
    for i in range(frames+warmup):
        im=image(i,workload)
        start=time.perf_counter();seg=segmenter.segment(im);mid=time.perf_counter()
        snapshot=tracker.update(seg);tracked=time.perf_counter()
        try:exporter.export(tracker.objects.values())
        except ValueError as exc:errors.append(str(exc))
        end=time.perf_counter()
        for e in snapshot['events']:
            if e['type'] in events:events[e['type']]+=1
        if i>=warmup:
            all_times.append((end-start)*1000);before_export.append((tracked-start)*1000)
            stages=dict(getattr(segmenter,'last_timings',{}))
            stages.update({'tracking':(tracked-mid)*1000,'geometry_generation':(end-tracked)*1000,
                           'segmentation_total':(mid-start)*1000})
            measured=sum(stages.get(k,0.) for k in ('segmentation','morphology','components','contours','simplification'))
            if measured:stages['segmentation_other']=(mid-start)*1000-measured
            stage_rows.append(stages)
    names=sorted(set().union(*(r.keys() for r in stage_rows)))
    return {'label':label,'workload':workload,'resolution':[640,480],'warmup':warmup,'frames':frames,
            'total_ms':stats(all_times),'without_export_ms':stats(before_export),
            'stages_ms':{k:stats([r.get(k,0.) for r in stage_rows]) for k in names},
            'contract_builds':exporter.builds,'geometry_rebuilds':tracker.geometry_rebuilds,
            'segmentation_shape_cache_hits':getattr(segmenter,'cache_hits',0),'events':events,
            'geometry_errors':errors,'samples_ms':all_times}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline',type=Path,help='saved before/vision package for paired comparison')
    p.add_argument('--frames',type=int,default=120)
    p.add_argument('--rounds',type=int,default=3)
    p.add_argument('--warmup',type=int,default=10)
    p.add_argument('--output',type=Path,default=Path('artifacts/phase1c/performance.json'))
    args=p.parse_args()
    if not 10<=args.frames<=2000 or not 1<=args.rounds<=10 or args.warmup<0:p.error('invalid measurement limits')
    implementations=[('after',StructureSegmenter,StructureTracker)]
    if args.baseline:
        package=types.ModuleType('beforevision');package.__path__=[str(args.baseline.resolve())]
        sys.modules['beforevision']=package
        s=importlib.import_module('beforevision.structure_segmentation')
        t=importlib.import_module('beforevision.structure_tracking')
        implementations.insert(0,('before',s.StructureSegmenter,t.StructureTracker))
    results=[]
    for round_index in range(args.rounds):
        # Alternate order to reduce systematic warm-up/load bias.
        order=implementations if round_index%2==0 else implementations[::-1]
        for workload in ['translation','topology','shape_changes']:
            for label,s,t in order:
                result=run(label,s,t,args.frames,args.warmup,workload)
                result['round']=round_index+1;results.append(result)
                print(json.dumps({k:result[k] for k in ('label','workload','round','total_ms','events')}),flush=True)
    aggregate=[]
    for label,_,_ in implementations:
        for workload in ['translation','topology','shape_changes']:
            rows=[r for r in results if r['label']==label and r['workload']==workload]
            samples=[x for r in rows for x in r['samples_ms']]
            aggregate.append({'label':label,'workload':workload,'frames':len(samples),'total_ms':stats(samples),
                              'round_means_ms':[r['total_ms']['mean'] for r in rows]})
    report={'synthetic_only':True,'capture_render_udp_godot_excluded':True,'opencv':cv2.__version__,
            'opencv_threads':cv2.getNumThreads(),'numpy':np.__version__,'aggregate':aggregate,'results':results}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2),encoding='utf-8')


if __name__=='__main__':main()

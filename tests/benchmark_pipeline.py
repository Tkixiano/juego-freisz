"""Reproducible, hardware-free per-stage benchmark and output equivalence corpus."""
import argparse
from collections import defaultdict
from contextlib import ExitStack
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import socket
import time
from unittest.mock import patch
import cv2
import numpy as np
from vision.material_structures import MaterialStructures
from vision.material_synthetic import bgr,scenarios
from vision.structure_udp import Session,fragment,encode

def stats(values):
    a=np.asarray(values,float)
    return dict(n=len(a),mean=float(a.mean()),p50=float(np.percentile(a,50)),p95=float(np.percentile(a,95)),p99=float(np.percentile(a,99)),max=float(a.max())) if len(a) else dict(n=0)

def image(n,i,motion_every=4,shape_change=False):
    labels=np.zeros((480,640),np.uint8)
    dx=(i//motion_every)%5 if motion_every else 0;dy=(i//(2*motion_every+1))%3 if motion_every else 0
    for k in range(n):
        x=16+(k%8)*76+dx;y=15+(k//8)*55+dy
        labels[y:y+30,x:x+40]=1+k%3
        if shape_change and i%2:labels[y:y+2,x+40:x+44]=1+k%3
        if k%3==0:labels[y+12:y+30,x+15:x+40]=0 # concavity
        if k%3==1:labels[y+8:y+20,x+10:x+28]=0 # hole
    return bgr(labels)

def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--frames',type=int,default=40);p.add_argument('--counts',default='1,4,8,16,32,64');p.add_argument('--motion-every',type=int,default=4);p.add_argument('--shape-change',action='store_true');a=p.parse_args()
    cv2.setNumThreads(1);out={'resolution':[640,480],'threads':1,'frames':a.frames,'warmup':8,'motion_every':a.motion_every,'counts':{},'synthetic_only':True}
    with patch('cv2.VideoCapture',side_effect=AssertionError('NO CAMERA')),socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        for n in map(int,a.counts.split(',')):
            pipe=MaterialStructures();samples=defaultdict(list);hashes=[];current=defaultdict(float)
            def wrap(fn,key):
                def run(*args,**kwargs):
                    t=time.perf_counter_ns()
                    try:return fn(*args,**kwargs)
                    finally:current[key]+=(time.perf_counter_ns()-t)/1e6
                return run
            with ExitStack() as stack:
                for name,key in [('cvtColor','hsv'),('inRange','masks'),('connectedComponentsWithStats','components'),('morphologyEx','morphology')]:
                    stack.enter_context(patch.object(cv2,name,wrap(getattr(cv2,name),key)))
                for obj,name,key in [(pipe.tracker,'update','tracking'),(pipe,'_candidates','material_geometry'),(pipe,'_assign_regions','region_tracking'),(pipe.contracts,'export','parent_geometry')]:
                    stack.enter_context(patch.object(obj,name,wrap(getattr(obj,name),key)))
                for i in range(a.frames+8):
                    frame=image(n,i,a.motion_every,a.shape_change);current.clear();t=time.perf_counter_ns();s=pipe.update(frame);elapsed=(time.perf_counter_ns()-t)/1e6
                    if i<8:continue
                    samples['total'].append(elapsed)
                    for k,v in current.items():samples[k].append(v)
                    for k in ['contours','simplification']:samples[k].append(pipe.segmenter.last_timings.get(k,0))
                    t=time.perf_counter_ns();payload=encode(s);samples['serialization'].append((time.perf_counter_ns()-t)/1e6)
                    hashes.append(digest(s))
                    # Benchmark full UDP wire encoding separately from the pipeline.
                    if len(s['structures'])<=32 and s['status']=='TRACKING':
                        f=dict(s,logical_time=i/30,region_identity_epochs={r['region_id']:1 for c in s['structures'] for r in c['material_regions']},diagnostic={'status':'TRACKING'})
                        t=time.perf_counter_ns();m=Session().snapshot(f,start=True);packets=fragment(m);samples['wire_preparation'].append((time.perf_counter_ns()-t)/1e6)
                        t=time.perf_counter_ns()
                        for packet in packets:sock.sendto(packet,('127.0.0.1',5099))
                        samples['udp_send'].append((time.perf_counter_ns()-t)/1e6)
            out['counts'][str(n)]=dict(stages_ms={k:stats(v) for k,v in samples.items()},hashes=hashes,errors=pipe.errors,structures=len(s['structures']),regions=sum(len(c['material_regions']) for c in s['structures']),metrics=pipe.metrics,equivalent_fps=1000/np.mean(samples['total']))
            print(n,round(out['counts'][str(n)]['stages_ms']['total']['mean'],2),'ms',flush=True)
        # Exact cross-version outputs for topology/hole/contact and disappearance cases.
        corpus={}
        for name,frames,_ in scenarios():
            pipe=MaterialStructures();corpus[name]=[digest(pipe.update(f)) for f in frames]
        out['equivalence_corpus']=corpus
    a.output.write_text(json.dumps(out,indent=2),encoding='utf-8')

if __name__=='__main__':main()

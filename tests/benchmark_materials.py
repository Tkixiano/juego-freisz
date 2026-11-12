"""Measure a fixed synthetic 640x480 workload without network or capture."""
import argparse
import json
from pathlib import Path
import time
import cv2
import numpy as np
from vision.material_structures import MaterialStructures
from vision.material_synthetic import three,bgr

def main():
    p=argparse.ArgumentParser();p.add_argument('--frames',type=int,default=120);p.add_argument('--output',type=Path,required=True);p.add_argument('--threads',type=int,default=1);a=p.parse_args()
    if not 30<=a.frames<=600:p.error('frames 30..600')
    before_threads=cv2.getNumThreads();cv2.setNumThreads(a.threads)
    image=cv2.resize(bgr(three()),(640,480),interpolation=cv2.INTER_NEAREST)
    pipeline=MaterialStructures();samples=[]
    for i in range(a.frames+10):
        start=time.perf_counter();s=pipeline.update(image)
        if i>=10:samples.append((time.perf_counter()-start)*1000)
    result=dict(resolution=[640,480],frames=a.frames,warmup=10,opencv_default_threads=before_threads,opencv_threads=cv2.getNumThreads(),mean_ms=float(np.mean(samples)),p50_ms=float(np.percentile(samples,50)),p95_ms=float(np.percentile(samples,95)),p99_ms=float(np.percentile(samples,99)),materials=len(s['structures'][0]['material_regions']),structures=len(s['structures']),errors=pipeline.errors,metrics=pipeline.metrics,notes='Fixed image benchmark; no camera/display/network; not a sustained FPS measurement',samples_ms=samples)
    a.output.write_text(json.dumps(result,indent=2),encoding='utf-8');print(json.dumps({k:v for k,v in result.items() if k!='samples_ms'}))

if __name__=='__main__':main()

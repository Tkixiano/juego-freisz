"""Synthetic/image-file material calibration and diagnostics. No capture/network."""
import argparse
import json
from pathlib import Path
import time
import cv2
import numpy as np
from .calibration import sample_hsv
from .material_config import DEFAULT_PATH,load_materials,save_materials,MATERIALS
from .material_structures import MaterialStructures
from .material_synthetic import scenarios,COLORS


class MaterialCalibration:
    CAMERA='Material source (synthetic/file) | Q quit | 1/2/3 select | S save | L load'
    SLIDERS='Material HSV | drag sample ROI | A apply suggestion'
    KEYS=('H min','S min','V min','H max','S max','V max','Min area','Min saturation')
    def __init__(self,config,path):
        self.config=config;self.path=path;self.selected=1;self.image=None;self.start=None;self.sample=None;self.sample_id=None
        self.message='Independent HSV profile; no camera or UDP'
        cv2.namedWindow(self.CAMERA,cv2.WINDOW_NORMAL);cv2.namedWindow(self.SLIDERS,cv2.WINDOW_NORMAL)
        cv2.resizeWindow(self.CAMERA,960,720);cv2.resizeWindow(self.SLIDERS,500,450)
        for key,maximum in zip(self.KEYS,(179,255,255,179,255,255,100000,255)):
            cv2.createTrackbar(key,self.SLIDERS,0,maximum,lambda _v:None)
        cv2.setMouseCallback(self.CAMERA,self.mouse);self.select(1)
    def select(self,id):
        self.selected=id;c=next(c for c in self.config.colors if c.id==id)
        for key,value in zip(self.KEYS,c.lower+c.upper+[c.min_area,c.min_saturation]):cv2.setTrackbarPos(key,self.SLIDERS,value)
    def read(self):
        values=[cv2.getTrackbarPos(k,self.SLIDERS) for k in self.KEYS]
        c=next(c for c in self.config.colors if c.id==self.selected)
        for i in (1,2):values[i]=min(values[i],values[i+3])
        c.lower=values[:3];c.upper=values[3:6];c.min_area=max(10,values[6]);c.min_saturation=values[7]
    def mouse(self,event,x,y,_flags,_data):
        if event==cv2.EVENT_LBUTTONDOWN:self.start=(x,y)
        elif event==cv2.EVENT_LBUTTONUP and self.start is not None and self.image is not None:
            try:
                self.sample=sample_hsv(self.image,self.start,(x,y));self.sample_id=self.selected
                self.message='ROI suggestion '+str(self.sample['suggested_lower'])+' -> '+str(self.sample['suggested_upper'])+'; A applies'
            except ValueError as e:self.message=str(e)
    def key(self,key):
        if key in (ord('q'),ord('Q'),27):return 'quit'
        if key in (ord('1'),ord('2'),ord('3')):self.read();self.select(int(chr(key)))
        if key in (ord('a'),ord('A')) and self.sample_id==self.selected:
            for label,v in zip(self.KEYS[:6],self.sample['suggested_lower']+self.sample['suggested_upper']):cv2.setTrackbarPos(label,self.SLIDERS,v)
            self.read()
        if key in (ord('s'),ord('S')):
            try:self.read();save_materials(self.config,self.path);self.message='Saved '+str(self.path)
            except (OSError,ValueError) as e:self.message=str(e)
        if key in (ord('l'),ord('L')):
            try:self.config=load_materials(self.path);self.select(self.selected);self.message='Loaded profile; tracking reset';return 'reload'
            except (OSError,ValueError) as e:self.message=str(e)
        return ''


def draw_snapshot(image,snapshot):
    result=image.copy()
    for c in snapshot['structures']:
        for r in c['material_regions']:
            color=COLORS[next(k for k,v in MATERIALS.items() if v==r['material'])]
            for region in r['regions']:
                for ring in [region['exterior'],*region['holes']]:
                    points=np.rint(np.asarray(ring)+c['position']).astype('int32')
                    cv2.polylines(result,[points],True,color,1)
            center=np.rint(np.asarray(r['regions'][0]['exterior']).mean(axis=0)+c['position']).astype(int)
            cv2.putText(result,r['region_id']+' / '+c['id'],tuple(center),cv2.FONT_HERSHEY_SIMPLEX,.3,(255,255,255),1)
    return result


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile',type=Path,default=DEFAULT_PATH);p.add_argument('--image',type=Path)
    p.add_argument('--scenario',default='07_three_materials');p.add_argument('--calibrate',action='store_true')
    p.add_argument('--headless',action='store_true');p.add_argument('--export',type=Path)
    p.add_argument('--threads',type=int,default=1)
    a=p.parse_args();config=load_materials(a.profile)
    if not 1<=a.threads<=16:p.error('threads 1..16')
    cv2.setNumThreads(a.threads) # same bounded OpenCV policy as vision/app.py
    if a.export and not a.headless:p.error('--export requires --headless (bounded offline frames)')
    if a.image:
        source=cv2.imread(str(a.image))
        if source is None:p.error('image file cannot be loaded')
        frames=[source]*12;name=a.image.name
    else:
        options={name:frames for name,frames,_ in scenarios()}
        if a.scenario not in options:p.error('unknown scenario: '+', '.join(options))
        frames=options[a.scenario];name=a.scenario
    pipeline=MaterialStructures(config);snapshots=[]
    if a.headless:
        for image in frames:
            s=pipeline.update(image);s['logical_time']=(s['source_frame']-1)/30;snapshots.append(s)
    else:
        ui=MaterialCalibration(config,a.profile);i=0
        try:
            while True:
                start=time.perf_counter();ui.read();image=frames[min(i,len(frames)-1)]
                snapshot=pipeline.update(image);ui.image=image
                shown=draw_snapshot(image,snapshot)
                fps=1/max(time.perf_counter()-start,1e-6)
                cv2.putText(shown,f'{snapshot["status"]} ID {ui.selected} procFPS {fps:.1f}',(5,16),cv2.FONT_HERSHEY_SIMPLEX,.36,(255,255,255),1)
                conflict=pipeline.last_segmentation.conflict_pixels if pipeline.last_segmentation is not None else 0
                count=sum(len(c['material_regions']) for c in snapshot['structures'])
                cv2.putText(shown,f'Structures {len(snapshot["structures"])} regions {count} conflict pixels {conflict}',(5,32),cv2.FONT_HERSHEY_SIMPLEX,.32,(255,255,255),1)
                cv2.putText(shown,ui.message[:54],(5,48),cv2.FONT_HERSHEY_SIMPLEX,.3,(255,255,255),1)
                cv2.imshow(ui.CAMERA,shown)
                seg=pipeline.last_segmentation
                if seg is not None:
                    cv2.imshow('Raw HSV masks: green / blue / orange',np.hstack([seg.masks[k].astype('uint8')*255 for k in (1,2,3)]))
                    cv2.imshow('Exclusive material masks (conflicts rejected)',np.hstack([seg.material_masks[k].astype('uint8')*255 for k in (1,2,3)]))
                    cv2.imshow('Selected material mask',seg.material_masks[ui.selected].astype('uint8')*255)
                key=ui.key(cv2.waitKey(1)&255)
                if key=='quit':break
                if key=='reload':pipeline=MaterialStructures(ui.config)
                i+=1;time.sleep(max(0,1/30-(time.perf_counter()-start)))
        finally:cv2.destroyAllWindows()
    if a.export:
        a.export.parent.mkdir(parents=True,exist_ok=True)
        a.export.write_text(json.dumps(dict(material_snapshot_file_version=1,geometry_contract_version=1,material_contract_version=1,synthetic_only=True,scenario=name,tick_hz=30,frames=snapshots),allow_nan=False),encoding='utf-8')
    print(json.dumps(dict(frames=len(snapshots),metrics=pipeline.metrics,errors=pipeline.errors)))


if __name__=='__main__':main()

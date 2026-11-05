"""Synthetic-only Phase 1B scenarios and reproducible report. Never opens devices."""
from __future__ import annotations

import argparse
from dataclasses import asdict
import json
from pathlib import Path
import time
import cv2
import numpy as np
from .config import ColorConfig
from .structure_segmentation import StructureSegmenter, StructureSettings, signed_area
from .structure_tracking import StructureTracker

COLORS = [ColorConfig(1,'verde',[35,80,60],[85,255,255]),
          ColorConfig(2,'azul',[95,80,60],[135,255,255]),
          ColorConfig(3,'rojo_sintetico',[170,80,60],[10,255,255])]
PALETTE = {1:(0,220,0),2:(220,0,0),3:(0,0,220)}


def frame(*rectangles):
    image = np.zeros((180,280,3),np.uint8)
    for x,y,w,h,color in rectangles:
        image[y:y+h,x:x+w] = PALETTE[color]
    return image


def fixtures():
    separated = frame((40,60,40,40,1),(100,60,40,40,1))
    joined = frame((60,60,40,40,1),(100,60,40,40,1))
    separated_colors = frame((40,60,40,40,1),(100,60,40,40,2))
    joined_colors = frame((60,60,40,40,1),(100,60,40,40,2))
    three = frame((20,60,40,40,1),(100,60,40,40,2),(180,60,40,40,3))
    three_joined = frame((60,60,40,40,1),(100,60,40,40,2),(140,60,40,40,3))
    concave_separate = frame((40,40,20,80,1),(80,100,60,20,2))
    concave_joined = frame((60,40,20,80,1),(80,100,60,20,2))
    corner_before = frame((40,40,40,40,1),(100,80,40,40,2))
    corner = frame((60,40,40,40,1),(100,80,40,40,2))
    gap1 = frame((59,60,40,40,1),(100,60,40,40,2))
    gap2 = frame((58,60,40,40,1),(100,60,40,40,2))
    noise = separated_colors.copy()
    noise[79,80:100] = PALETTE[1]
    return locals()


def scenarios():
    f = fixtures()
    # name, stages(image,frames, expected stable count), expected MERGE/SPLIT
    return [
        ('01_verdes_separados',[(f['separated'],5,2)],(0,0)),
        ('02_union_verdes',[(f['separated'],5,2),(f['joined'],5,1)],(1,0)),
        ('03_separacion_verdes',[(f['separated'],5,2),(f['joined'],5,1),(f['separated'],5,2)],(1,1)),
        ('04_union_verde_azul',[(f['separated_colors'],5,2),(f['joined_colors'],5,1)],(1,0)),
        ('05_union_tres_colores',[(f['three'],5,3),(f['three_joined'],5,1)],(1,0)),
        ('06_separacion_tres',[(f['three'],5,3),(f['three_joined'],5,1),(f['three'],5,3)],(1,1)),
        ('07_union_concava',[(f['concave_separate'],5,2),(f['concave_joined'],5,1)],(1,0)),
        ('08_contacto_esquina',[(f['corner_before'],5,2),(f['corner'],6,1)],(1,0)),
        ('09_huecos_uno_dos_pixeles',[(f['gap1'],5,2),(f['gap2'],5,2),
                                          (f['joined_colors'],5,1),(f['gap1'],9,2)],(1,1)),
        ('10_proximos_sin_contacto',[(f['separated_colors'],5,2),(f['gap2'],12,2)],(0,0)),
        ('11_contacto_por_ruido',[(f['separated_colors'],5,2),(f['noise'],1,2),
                                (f['separated_colors'],5,2),(f['noise'],10,2)],(0,0)),
        ('12_ciclos_repetidos',[(f['separated_colors'],5,2)]+[
            stage for _ in range(10) for stage in [(f['joined_colors'],5,1),(f['separated_colors'],5,2)]],(10,10))]


def run_scenario(name, stages, expected_events):
    segmenter, tracker = StructureSegmenter(COLORS), StructureTracker()
    events, snapshots, durations, stage_results = [],[],[],[]
    max_area_error = 0.
    overlap_frames = 0
    for image,n,expected in stages:
        first_frame = tracker.frame+1
        for _ in range(n):
            start = time.perf_counter()
            segmentation = segmenter.segment(image)
            snapshot = tracker.update(segmentation)
            durations.append((time.perf_counter()-start)*1000)
            for r in segmentation.regions:
                error = abs(sum(signed_area(p) for p in r.rings)-r.area)
                max_area_error = max(max_area_error,error)
            accumulated = np.zeros(image.shape[:2],np.uint8)
            for obj in tracker.objects.values():
                accumulated += obj.geometry_mask.astype('uint8')
            overlap_frames += int(np.any(accumulated>1))
            events.extend(snapshot['events'])
            snapshots.append(snapshot)
        stage_results.append({'first_frame':first_frame,'last_frame':tracker.frame,
                              'expected':expected,'actual':len(snapshot['structures'])})
    counts = tuple(sum(e['type']==kind for e in events) for kind in ('MERGE','SPLIT'))
    ok = all(s['actual']==s['expected'] for s in stage_results) and counts==expected_events and max_area_error==0 and overlap_frames==0
    return {'name':name,'pass':ok,'frames':tracker.frame,'stages':stage_results,
            'expected_merge_split':expected_events,'actual_merge_split':counts,
            'events':events,'max_polygon_area_error_pixels_squared':max_area_error,
            'overlap_frames':overlap_frames,'geometry_rebuilds':tracker.geometry_rebuilds,
            'overlap_rejections':tracker.overlap_rejections,
            'timing_ms':{'p50':float(np.percentile(durations,50)),
                         'p95':float(np.percentile(durations,95)), 'max':max(durations)},
            'final':snapshot,'trace':snapshots}


def benchmark():
    """Measured CPU pipeline only: excludes capture, rendering, UDP and Godot."""
    results=[]
    for w,h in [(640,480),(1280,720)]:
        segmenter,tracker=StructureSegmenter(COLORS),StructureTracker()
        timings=[]
        for index in range(40):
            image=np.zeros((h,w,3),np.uint8)
            for k,color in enumerate(PALETTE.values()):
                x=int(w*(.12+k*.27))+index%10
                y=int(h*.4)
                image[y:y+int(h*.15),x:x+int(w*.12)]=color
            start=time.perf_counter()
            tracker.update(segmenter.segment(image))
            elapsed=(time.perf_counter()-start)*1000
            if index>=5: timings.append(elapsed)
        results.append({'resolution':[w,h],'warmup_frames':5,'measured_frames':len(timings),
                        'pipeline_ms_p50':float(np.percentile(timings,50)),
                        'pipeline_ms_p95':float(np.percentile(timings,95)),
                        'pipeline_ms_max':max(timings),'final_structures':len(tracker.objects),
                        'scope':'segmentation+tracking+snapshot; no capture/render/network/game'})
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('artifacts/structure_phase1b'))
    parser.add_argument('--benchmark',action='store_true',help='also time synthetic 640x480 and 1280x720 processing')
    args = parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    results = [run_scenario(*s) for s in scenarios()]
    panels = []
    for result,(_,stages,_) in zip(results,scenarios()):
        panel = stages[-1][0].copy()
        cv2.putText(panel,result['name'],(5,16),cv2.FONT_HERSHEY_SIMPLEX,.38,(255,255,255),1)
        segmentation = StructureSegmenter(COLORS).segment(stages[-1][0])
        for r in segmentation.regions:
            for ring in r.rings:
                cv2.polylines(panel,[ring.astype('int32')],True,(255,255,255),1)
            cv2.circle(panel,tuple(r.center.astype(int)),3,(0,255,255),-1)
        cv2.putText(panel,f"structures={len(result['final']['structures'])} M/S={result['actual_merge_split']}",
                    (5,173),cv2.FONT_HERSHEY_SIMPLEX,.37,(255,255,255),1)
        panels.append(panel)
    montage = np.vstack([np.hstack(panels[i:i+3]) for i in range(0,12,3)])
    cv2.imwrite(str(args.output/'scenarios.png'),montage)
    # Individual masks are retained for inspection, separately from accepted union.
    f = fixtures()
    diagnostic = StructureSegmenter(COLORS).segment(f['three_joined'])
    cv2.imwrite(str(args.output/'combined.png'),diagnostic.combined.astype('uint8')*255)
    for id,mask in diagnostic.masks.items():
        cv2.imwrite(str(args.output/f'mask_color_{id}.png'),mask.astype('uint8')*255)
    report = {'synthetic_only':True,'hardware_opened':False,'settings':asdict(StructureSettings()),
              'opencv':cv2.__version__,'numpy':np.__version__,
              'passed':sum(r['pass'] for r in results),'total':len(results),
              'frames':sum(r['frames'] for r in results), 'results':results}
    if args.benchmark:
        report['benchmark']=benchmark()
    (args.output/'report.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('passed','total','frames')}))
    if report['passed']!=report['total']:
        raise SystemExit(1)


if __name__=='__main__':
    main()

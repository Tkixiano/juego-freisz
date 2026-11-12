"""Measure the unchanged capture watchdog with injected fake factories only."""
import argparse
import json
from pathlib import Path
import time


def import_probe(pipe):
    start=time.monotonic();pipe.send(('entered',start))
    import numpy
    pipe.send(('numpy',time.monotonic()))
    import cv2
    pipe.send(('opencv',time.monotonic()))
    pipe.close()


def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--runs',type=int,default=3)
    p.add_argument('--imports',action='store_true')
    p.add_argument('--startup-timeout',type=float,default=4)
    a=p.parse_args()
    import multiprocessing as mp
    if a.imports:
        parent,child=mp.get_context('spawn').Pipe(False)
        process=mp.get_context('spawn').Process(target=import_probe,args=(child,))
        start=time.monotonic();process.start();child.close();result=[]
        try:
            while time.monotonic()-start<30:
                try:ready=parent.poll(.05)
                except (BrokenPipeError,EOFError):break
                if ready:
                    try:label,t=parent.recv()
                    except EOFError:break
                    result.append(dict(stage=label,elapsed_ms=(t-start)*1000))
                if not process.is_alive() and not ready:break
        finally:
            process.join(.2)
            if process.is_alive():process.terminate();process.join(.5)
        a.output.write_text(json.dumps(dict(stages=result,exit_code=process.exitcode),indent=2),encoding='utf-8');print(json.dumps(dict(stages=result,exit_code=process.exitcode)),flush=True)
        return
    from vision.camera import CameraSource
    from vision.config import Config
    from tests.camera_fakes import CameraFactory
    result=[]
    for i in range(a.runs):
        released=mp.get_context('spawn').RawValue('i',0)
        config=Config().camera;config.startup_timeout=a.startup_timeout;config.stall_timeout=.5
        source=CameraSource(config,CameraFactory('hang_read',released))
        start=time.monotonic();source.start();spawn_ms=(time.monotonic()-start)*1000
        transitions=[];previous=None;first_frame=None
        while time.monotonic()-start<7:
            frame=source.get()
            key=(source.state,source.restarts,source.serial)
            if key!=previous:
                transitions.append(dict(elapsed_ms=(time.monotonic()-start)*1000,state=source.state,
                                        restarts=source.restarts,serial=source.serial,
                                        heartbeat=float(source.header[7]) if source.process is not None else 0))
                previous=key
            if frame is not None and first_frame is None:first_frame=(time.monotonic()-start)*1000
            if first_frame is not None and source.restarts:break
            time.sleep(.005)
        source.close()
        result.append(dict(run=i,spawn_return_ms=spawn_ms,first_frame_ms=first_frame,transitions=transitions,
                           diagnostics=source.diagnostics()))
        a.output.write_text(json.dumps(result,indent=2),encoding='utf-8')
        print(json.dumps(result[-1]),flush=True)


if __name__=='__main__':main()

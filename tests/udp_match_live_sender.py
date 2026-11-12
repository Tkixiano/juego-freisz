"""Real loopback multimaterial integration/load sender. No capture imports."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import socket
import sys
import time
import math
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from vision.structure_udp import Session,fragment,confirmed_frame

ROOT=Path(__file__).resolve().parents[1]
def frames(name):
    data=json.loads((ROOT/f'juegofrei/validation/material_replays/{name}.json').read_text(encoding='utf-8'))
    return [f for f in data['frames'] if confirmed_frame(f)]
def load_frame(count=32):
    f=deepcopy(frames('01_solid')[-1]);base=f['structures'][0];f.update(structures=[],identity_epochs={},region_identity_epochs={},events=[])
    ring=[[-20,-12],[20,-12],[20,-4],[-4,-4],[-4,12],[-20,12]]
    parts=[[[-20,-12],[20,-12],[20,-4],[-20,-4]],[[-20,-4],[-4,-4],[-4,12],[-20,12]]]
    for i in range(count):
        c=deepcopy(base);c['id']=f'load{i:02d}';c['position']=[50+i%8*70,220+i//8*50]
        c['regions']=[dict(exterior=deepcopy(ring),holes=[])];c['convex_parts']=deepcopy(parts)
        r=c['material_regions'][0];r.update(region_id=f'load_region{i:02d}',structure_id=c['id'],material=['GREEN_SOLID','BLUE_BOUNCE','ORANGE_ONE_WAY'][i%3],regions=deepcopy(c['regions']),convex_parts=deepcopy(parts))
        f['structures'].append(c);f['identity_epochs'][c['id']]=1;f['region_identity_epochs'][r['region_id']]=1
    return f
def main():
    p=argparse.ArgumentParser();p.add_argument('--port',type=int,default=5015);p.add_argument('--mode',choices=['faults','load'],default='faults');p.add_argument('--seconds',type=float,default=15);p.add_argument('--hz',type=float,default=30);p.add_argument('--stats',type=Path,required=True);p.add_argument('--regions',type=int,choices=[1,4,8,16,32,64],default=32)
    a=p.parse_args();start=time.perf_counter();sent=datagrams=errors=0;cost=[];session=Session();generation=session.started_ms;old=None
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        sock.setblocking(False)
        def send(message,packets=None):
            nonlocal sent,datagrams,errors,old
            begin=time.perf_counter()
            for packet in fragment(message) if packets is None else packets:
                try:sock.sendto(packet,('127.0.0.1',a.port));datagrams+=1
                except OSError:errors+=1
            cost.append((time.perf_counter()-begin)*1000);sent+=1
        three=frames('07_three')[-1];split=frames('09_split');empty=frames('17_removal')[-1]
        load_template=load_frame(min(a.regions,32)) if a.mode=='load' else None
        if a.mode=='load' and a.regions==64:
            from tests.benchmark_states import state
            load_template=state(64)
        prior_stage=-1;count=0;deadline=start;last=None
        while time.perf_counter()-start<a.seconds:
            t=time.perf_counter()-start
            stage=0 if a.mode=='load' else (0 if t<3 else 1 if t<5 else 2 if t<7 else 3 if t<9 else 4 if t<10 else 5 if t<11 else 6)
            if stage!=prior_stage:
                if last is not None and old is None:old=deepcopy(last)
                generation=max(time.time_ns()//1000000,generation+1);session=Session(started_ms=generation);count=0;prior_stage=stage
            if stage==2:
                deadline=max(deadline+1/a.hz,time.perf_counter());time.sleep(max(0,deadline-time.perf_counter()));continue
            f=deepcopy(load_template) if a.mode=='load' else deepcopy(split[min(count,len(split)-1)] if stage==1 else empty if stage==5 else three)
            f['logical_time']=count/a.hz
            if stage==0 and a.mode=='faults':
                for c in f['structures']:c['position'][0]+=math.sin(t)*10
            message=session.snapshot(f,start=count%10==0,error='synthetic_error' if stage==4 else None)
            send(message,list(reversed(fragment(message))) if count==0 else None)
            if stage==0 and count==10:send(message) # duplicate
            if stage==1 and count==1 and old is not None:send(old) # obsolete session
            if stage==1 and count==int(a.hz*1.85):
                missing=session.snapshot(f,start=True);send(missing,fragment(missing)[:1])
            last=message;count+=1;deadline=max(deadline+1/a.hz,time.perf_counter());time.sleep(max(0,deadline-time.perf_counter()))
    a.stats.parent.mkdir(parents=True,exist_ok=True)
    a.stats.write_text(json.dumps(dict(messages=sent,datagrams=datagrams,send_errors=errors,seconds=time.perf_counter()-start,send_cost_ms=cost),indent=2),encoding='utf-8')
if __name__=='__main__':main()

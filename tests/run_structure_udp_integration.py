"""Real localhost UDP fault/recovery or configurable load test. Synthetic only."""
import argparse
from copy import deepcopy
import json
from pathlib import Path
import socket
import time
from vision.structure_udp import Session,fragment,PORT,confirmed_frame


def load_frame(count, parts):
    from tests.structure_udp_fixtures import frame
    source=frame()['structures'][0]
    structures=[]
    for i in range(count):
        s=deepcopy(source);s['id']=f'load-{i:02d}';s['position']=[80+(i%8)*140,150+(i//8)*100]
        s['regions']=[dict(exterior=[[-40,-16],[40,-16],[40,16],[-40,16]],holes=[])]
        s['convex_parts']=[]
        for j in range(parts):
            x=-40+80*j/parts;right=-40+80*(j+1)/parts
            s['convex_parts'].append([[x,-16],[right,-16],[right,16],[x,16]])
        structures.append(s)
    return dict(sequence=1,logical_time=0,structures=structures,identity_epochs={s['id']:1 for s in structures},events=[])


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mode',choices=['faults','load'],default='faults')
    p.add_argument('--port',type=int,default=PORT)
    p.add_argument('--hz',type=float,default=30)
    p.add_argument('--seconds',type=float,default=10)
    p.add_argument('--objects',type=int,default=8)
    p.add_argument('--parts',type=int,default=16)
    p.add_argument('--stats',type=Path,required=True)
    a=p.parse_args()
    if not 1<=a.objects<=32 or not 1<=a.parts<=64 or a.objects*a.parts>512 or not 1<=a.hz<=120 or not 1<=a.seconds<=300: p.error('load limits')
    start=time.perf_counter();sent=datagrams=errors=bytes_sent=0
    send_cost=[];session=Session();old_message=None
    with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
        sock.setblocking(False)
        def send(m,packets=None):
            nonlocal sent,datagrams,errors,bytes_sent
            packets=fragment(m) if packets is None else packets
            before=time.perf_counter()
            for packet in packets:
                try:sock.sendto(packet,('127.0.0.1',a.port));datagrams+=1;bytes_sent+=len(packet)
                except OSError:errors+=1
            send_cost.append((time.perf_counter()-before)*1000);sent+=1
        if a.mode=='load':
            frame=load_frame(a.objects,a.parts);deadline=time.perf_counter()
            for i in range(int(a.hz*a.seconds)):
                frame['logical_time']=i/a.hz
                for s in frame['structures']:s['position'][0]+=.02
                send(session.snapshot(frame,start=i%30==0))
                deadline+=1/a.hz;time.sleep(max(0,deadline-time.perf_counter()))
        else:
            replay=json.loads(Path('juegofrei/validation/replays/07_split.json').read_text(encoding='utf-8'))
            for i,frame in enumerate(replay['frames']):
                if not confirmed_frame(frame):
                    time.sleep(1/30)
                    continue
                m=session.snapshot(frame,start=session.sequence==0);send(m);old_message=m
                time.sleep(1/30)
            frame=deepcopy(replay['frames'][-1]);frame['logical_time']=3
            empty=dict(sequence=1,logical_time=3,structures=[],identity_epochs={},events=[],empty_confirmed=True)
            send(session.snapshot(empty));time.sleep(.3)
            # Loss of the sender is stale, not a new empty observation.
            time.sleep(1.2)
            session=Session(started_ms=max(session.started_ms+1,time.time_ns()//1000000))
            frame['logical_time']=0
            current=session.snapshot(frame,start=True);send(current)
            send(old_message);send(current) # obsolete session + duplicate
            next_m=session.snapshot(frame);send(next_m,fragment(next_m)[::-1])
            incomplete=session.snapshot(frame);send(incomplete,fragment(incomplete)[:-1])
            time.sleep(1.2)
            recovered=session.snapshot(frame);send(recovered)
            bad=session.snapshot(frame);bad['structures'][0]['convex_parts']=[[[0,0],[1,0],[2,0]]]
            send(bad)
            send(session.snapshot(frame,error='synthetic processing error'));time.sleep(.3)
            send(session.snapshot(frame));time.sleep(.2)
    result=dict(mode=a.mode,messages_offered=sent,datagrams=datagrams,bytes=bytes_sent,send_errors=errors,
                seconds=time.perf_counter()-start,send_cost_ms=send_cost,
                hz=a.hz,objects=a.objects,parts_per_object=a.parts)
    a.stats.write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='send_cost_ms'}))


if __name__=='__main__':main()

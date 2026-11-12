"""Replay Phase 1D synthetic snapshots over the isolated structure protocol."""
import argparse
import json
from pathlib import Path
import socket
import time
from .structure_udp import Session, fragment, PORT, confirmed_frame


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--replay',type=Path,default=Path('juegofrei/validation/material_replays/26_long.json'))
    p.add_argument('--port',type=int,default=PORT)
    p.add_argument('--hz',type=float,default=30)
    p.add_argument('--loops',type=int,default=1)
    p.add_argument('--new-session-each-loop',action='store_true')
    p.add_argument('--stats',type=Path)
    a=p.parse_args()
    if not 1<=a.port<=65535 or not 1<=a.hz<=120 or not 1<=a.loops<=1000: p.error('configuration range')
    if a.replay.stat().st_size>33554432: p.error('file size')
    replay=json.loads(a.replay.read_text(encoding='utf-8'))
    if replay.get('replay_version') not in (1,2) or replay.get('geometry_contract_version')!=1 or replay.get('synthetic_only') is not True: p.error('synthetic replay v1/v2 required')
    if replay['replay_version']==2 and replay.get('material_contract_version')!=1:p.error('material contract v1 required')
    if not isinstance(replay.get('frames'),list) or not 1<=len(replay['frames'])<=10000 or type(replay.get('tick_hz')) not in (int,float) or not 1<=replay['tick_hz']<=120: p.error('frame/hz limits')
    session=Session();sent=packets=errors=skipped=0;start=time.perf_counter();deadline=start
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as sock:
            sock.setblocking(False)
            for loop in range(a.loops):
                if loop and a.new_session_each_loop:
                    # Strictly newer local session generation, even in accelerated runs.
                    session=Session(started_ms=max(time.time_ns()//1000000,session.started_ms+1))
                for frame in replay['frames']:
                    if not confirmed_frame(frame):
                        skipped+=1
                        deadline=max(deadline+1/a.hz,time.perf_counter());time.sleep(max(0,deadline-time.perf_counter()))
                        continue
                    f=dict(frame)
                    f['logical_time']=float(frame['logical_time'])+loop*len(replay['frames'])/replay['tick_hz']
                    message=session.snapshot(f,start=session.sequence%30==0)
                    for packet in fragment(message):
                        try: sock.sendto(packet,('127.0.0.1',a.port));packets+=1
                        except (BlockingIOError,OSError): errors+=1
                    sent+=1;deadline=max(deadline+1/a.hz,time.perf_counter())
                    time.sleep(max(0,deadline-time.perf_counter()))
    except KeyboardInterrupt:
        pass
    result=dict(messages=sent,datagrams=packets,send_errors=errors,unconfirmed_frames_skipped=skipped,seconds=time.perf_counter()-start,
                offered_hz=sent/(time.perf_counter()-start),delivery='UDP unacknowledged')
    print(json.dumps(result))
    if a.stats:a.stats.write_text(json.dumps(result,indent=2),encoding='utf-8')


if __name__=='__main__':main()

"""Arm the existing MCP lab, send synthetic UDP, collect its bounded metrics."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import time


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--label',required=True)
    p.add_argument('--mode',choices=['load','faults','replay'],default='load')
    p.add_argument('--replay',default='juegofrei/validation/replays/20_long.json')
    p.add_argument('--objects',type=int,default=2)
    p.add_argument('--parts',type=int,default=1)
    a=p.parse_args()
    if not a.label.replace('_','').isalnum():p.error('label')
    duration=14 if a.mode=='load' else (12 if a.mode=='faults' else 126)
    code=('var suite: RefCounted = load("res://validation/StructureUdpIntegration.gd").new()\n'
          'get_tree().current_scene.set_meta("udp_suite",suite)\n'
          f'suite.run(get_tree(),"{a.label}",{duration}.0)\nreturn "armed"')
    args=Path(f'tmp/p3_arm_{a.label}.json')
    args.write_text(json.dumps(dict(op='game_eval',params=dict(code=code))),encoding='utf-8')
    env=dict(os.environ,PYTHONIOENCODING='utf-8')
    started=time.monotonic()
    result=subprocess.run([sys.executable,'tmp/godot_mcp_client.py','call','editor_manage','--args-file',str(args)],env=env,capture_output=True,text=True,encoding='utf-8',check=True)
    armed_at=time.monotonic()
    print(result.stdout,flush=True)
    if a.mode=='replay':
        command=[sys.executable,'-m','vision.structure_udp_sender','--replay',a.replay,'--stats',f'artifacts/phase3a/{a.label}_sender.json']
    else:
        command=[sys.executable,'-m','tests.run_structure_udp_integration','--mode',a.mode,'--objects',str(a.objects),'--parts',str(a.parts),'--stats',f'artifacts/phase3a/{a.label}_sender.json']
    subprocess.run(command,env=env,check=True)
    # The MCP request itself can take seconds BEFORE the coroutine is armed.
    # Wait from its reply, then poll a fresh report instead of assuming timing.
    wait_left=max(0,duration+0.25-(time.monotonic()-armed_at))
    while wait_left>0:
        time.sleep(min(1,wait_left))
        wait_left=max(0,duration+0.25-(time.monotonic()-armed_at))
    source=Path(f'juegofrei/validation/structure_udp_{a.label}.json')
    deadline=time.monotonic()+10
    while (not source.exists() or source.stat().st_mtime<time.time()-(time.monotonic()-started)-1) and time.monotonic()<deadline:
        time.sleep(.25)
    data=json.loads(source.read_text(encoding='utf-8'))
    Path(f'artifacts/phase3a/{a.label}_receiver.json').write_text(json.dumps(data,indent=2),encoding='utf-8')
    print(json.dumps(dict(label=a.label,passed=data['passed'],total=data['total'],accepted=data['status']['metrics']['accepted'],rejected=data['status']['metrics']['rejected'],hz=data['status'].get('received_hz'),failures=data['failures'])),flush=True)
    if data['failures']:raise SystemExit(1)


if __name__=='__main__':main()

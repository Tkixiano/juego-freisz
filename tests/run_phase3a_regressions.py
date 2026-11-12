"""Sequential engine regressions; logs and exit status are kept per suite."""
import json
from pathlib import Path
import subprocess
import time


def main():
    root=Path(__file__).resolve().parents[1]
    binary=Path('C:/godot 4.6/Godot_v4.6.3-stable_win64_console.exe')
    out=root/'artifacts/phase3a';out.mkdir(exist_ok=True)
    results=[]
    for name,script in [('phase2b','Phase2BHeadless'),('phase2a','Phase2AHeadless'),('phase1a','PolygonLabHeadless'),('phase1c','CompoundGeometryHeadless'),('phase1d','OfflineReplayHeadless')]:
        start=time.perf_counter()
        with (out/(name+'.txt')).open('w',encoding='utf-8') as f:
            try:
                p=subprocess.run([str(binary),'--headless','--path',str(root/'juegofrei'),'--script','res://validation/'+script+'.gd','--log-file',str(out/(name+'_engine.log'))],stdout=f,stderr=subprocess.STDOUT,timeout=180)
                code=p.returncode
            except subprocess.TimeoutExpired:code='TIMEOUT'
        result=dict(suite=name,exit_code=code,seconds=time.perf_counter()-start)
        results.append(result);print(json.dumps(result),flush=True)
        (out/'regression_exits.json').write_text(json.dumps(results,indent=2),encoding='utf-8')


if __name__=='__main__':main()

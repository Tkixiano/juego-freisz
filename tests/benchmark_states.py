"""Same geometry corpus for pre/post Godot CPU benchmarks; no capture."""
from copy import deepcopy
import json
from pathlib import Path
from tests.udp_match_live_sender import load_frame
from vision.structure_udp import Session

def state(count):
    f=load_frame(min(count,32))
    for i,c in enumerate(f['structures']):
        c['position']=[40+i%8*70,60+i//8*55]
    if count==64:
        for c in f['structures']:
            c['regions']=[dict(exterior=[[-20,-12],[20,-12],[20,12],[-20,12]],holes=[])]
            c['convex_parts']=[[[-20,-12],[20,-12],[20,12],[-20,12]]]
            a=c['material_regions'][0];a['regions']=[dict(exterior=[[-20,-12],[0,-12],[0,12],[-20,12]],holes=[])];a['convex_parts']=[a['regions'][0]['exterior']]
            b=deepcopy(a);b['region_id']+='b';b['material']='ORANGE_ONE_WAY' if a['material']!='ORANGE_ONE_WAY' else 'GREEN_SOLID'
            b['regions']=[dict(exterior=[[0,-12],[20,-12],[20,12],[0,12]],holes=[])];b['convex_parts']=[b['regions'][0]['exterior']]
            c['material_regions'].append(b);f['region_identity_epochs'][b['region_id']]=1
    f['logical_time']=0
    return Session().snapshot(f,start=True)

def main():
    dest=Path('juegofrei/validation/performance_states.json')
    dest.write_text(json.dumps({str(n):state(n) for n in [1,4,8,16,32,64]}),encoding='utf-8')
if __name__=='__main__':main()

"""Python encoder -> Godot wire vectors. Synthetic files only, no capture."""
import base64
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
from vision.structure_udp import Session,fragment,encode,confirmed_frame

def source(name):
    return json.loads(Path(f'juegofrei/validation/material_replays/{name}.json').read_text(encoding='utf-8'))['frames']

def raw_fragment(message):
    data=encode(message);digest=hashlib.sha256(data).hexdigest()
    return [encode(dict(wire='DYNAMIC_STRUCTURES_FRAGMENT',version=1,session_id=message['session_id'],session_started_ms=message['session_started_ms'],sequence=message['sequence'],index=i,count=math.ceil(len(data)/600),total_bytes=len(data),sha256=digest,data=base64.b64encode(data[i*600:(i+1)*600]).decode())) for i in range(math.ceil(len(data)/600))]

def generate():
    series={}
    names=['01_solid','02_bounce','03_one_way','07_three','08_merge','09_split','11_hole','12_corner','13_movement','14_rotation','15_silhouette','16_material','17_removal','18_reappearance','26_long','27_orange_merge_split']
    for i,name in enumerate(names):
        session=Session(f'{i+1:032x}',1000+i)
        frames=[f for f in source(name) if confirmed_frame(f)]
        if len(frames)<8 and name not in ['08_merge','09_split']:frames=frames+[deepcopy(frames[-1]) for _ in range(8-len(frames))]
        messages=[]
        for j,f in enumerate(frames):
            f=deepcopy(f);f['logical_time']=j/30
            messages.append(session.snapshot(f,start=True))
        series[name]=messages
    a=series['01_solid'];s=Session(a[0]['session_id'],a[0]['session_started_ms']);s.sequence=len(a)
    f=deepcopy(source('01_solid')[-1]);f['logical_time']=10
    for id in f['identity_epochs']:f['identity_epochs'][id]+=1
    for id in f['region_identity_epochs']:f['region_identity_epochs'][id]+=1
    series['epoch_recovery']=[s.snapshot(f,start=True) for _ in range(5)]
    f=deepcopy(source('01_solid')[-1]);f['logical_time']=20;f['structures'][0]['position'][1]=410
    series['floor_conflict']=[s.snapshot(f,start=True) for _ in range(6)]
    f=deepcopy(source('01_solid')[-1]);f['logical_time']=30
    series['after_conflict']=[s.snapshot(f,start=True) for _ in range(6)]
    s=Session('f'*32,9000)
    series['error']=[s.snapshot(source('07_three')[-1],start=True,error='synthetic_failure')]
    result={name:[{'message':m,'packets':[base64.b64encode(p).decode() for p in fragment(m)]} for m in messages] for name,messages in series.items()}
    invalid=deepcopy(a[0]);invalid['structures'][0]['material_regions'][0]['material']='UNKNOWN'
    result['invalid']=[{'message':invalid,'packets':[base64.b64encode(p).decode() for p in raw_fragment(invalid)]}]
    out=Path('juegofrei/validation/material_udp_vectors.json');out.write_text(json.dumps(result,separators=(',',':')),encoding='utf-8')
    return result

if __name__=='__main__':print({k:len(v) for k,v in generate().items()})

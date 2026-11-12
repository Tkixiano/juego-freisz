"""Shared synthetic wire vectors: Python encoder -> actual Godot validator.

No mocks of the geometry validator; files contain complete Phase 1C contracts.
"""
import base64
from copy import deepcopy
import json
from pathlib import Path
from vision.structure_udp import Session, fragment, encode, MAX_MESSAGE, confirmed_frame


def frame():
    replay=json.loads(Path('juegofrei/validation/replays/07_split.json').read_text(encoding='utf-8'))
    return deepcopy(next(f for f in replay['frames'] if f['structures']))


def vectors():
    result=[]
    def case(name, messages, **expect):
        commands=[]
        for value in messages:
            if isinstance(value,dict) and 'protocol' in value:
                commands.append({'packets':[base64.b64encode(p).decode() for p in fragment(value)]})
            else: commands.append(value)
        result.append(dict(name=name,commands=commands,expect=expect))
    def packets(m,**kw):return [base64.b64encode(p).decode() for p in fragment(m,**kw)]
    def new():return Session('a'*32,1000)
    f=frame();s=new();a=s.snapshot(f,start=True);b=s.snapshot(f)
    c=s.snapshot(f)
    case('session_start',[a],accepted=1,sequence=1,objects=len(f['structures']),scene_state='SCENE_ACTIVE')
    ns=Session('b'*32,1001);n=ns.snapshot(f,start=True)
    case('new_session',[a,n],accepted=2,sequence=1,sessions=2,session_id='b'*32)
    case('obsolete_session',[a,n,b],accepted=2,sequence=1,reason='obsolete_session')
    case('valid_snapshot',[a,b],accepted=2,sequence=2)
    case('duplicate',[a,a],accepted=1,sequence=1,reason='duplicate_or_old_sequence')
    case('out_of_order',[a,c,b],accepted=2,sequence=3,reason='duplicate_or_old_sequence')
    case('packet_loss_full_recovery',[a,c],accepted=2,sequence=3,gaps=1)
    case('fragmentation',[a],accepted=1,sequence=1)
    wire=packets(a)
    case('reversed_fragments',[{'packets':wire[::-1]}],accepted=1,pending=0)
    case('duplicate_fragment',[{'packets':wire[:1]+wire[:1]+wire[1:]}],accepted=1,fragment_duplicates=1)
    case('incomplete',[{'packets':wire[:-1]}],accepted=0,pending=1,scene_state='SCENE_STALE')
    case('expiry',[{'packets':wire[:-1]},{'advance_ms':1100}],accepted=0,pending=0,expired=1)
    corrupt=[]
    for p in fragment(a):
        h=json.loads(p);h['sha256']='0'*64;corrupt.append(base64.b64encode(encode(h)).decode())
    case('integrity',[{'packets':corrupt}],accepted=0,reason='integrity')
    h=json.loads(fragment(a)[0]);h['total_bytes']=MAX_MESSAGE+1
    case('oversize',[{'packets':[base64.b64encode(encode(h)).decode()]}],accepted=0,reason='fragment_limits')
    case('malformed',[{'packets':[base64.b64encode(b'{invalid').decode()]}],accepted=0,reason='fragment_json')
    invalid=deepcopy(b);invalid['structures'][0]['convex_parts']=[[[0,0],[1,0],[2,0]]]
    invalid['structures'][0]['geometry_version']+=1
    case('invalid_geometry_then_recovery',[a,invalid,c],accepted=2,sequence=3,reason='geometry:invalid_convex_part')
    rep=json.loads(Path('juegofrei/validation/replays/07_split.json').read_text(encoding='utf-8'))
    s=new();msgs=[s.snapshot(fr,start=i==0) for i,fr in enumerate(fr for fr in rep['frames'] if confirmed_frame(fr))]
    case('merge_split',msgs,accepted=len(msgs),merges=1,splits=1)
    empty=dict(sequence=1,logical_time=3,structures=[],identity_epochs={},events=[],empty_confirmed=True)
    s=new();start=s.snapshot(f,start=True);e=s.snapshot(empty)
    case('confirmed_empty',[start,e],accepted=2,objects=0,scene_state='SCENE_EMPTY')
    case('timeout_not_empty',[start,{'advance_ms':1100}],accepted=1,objects=len(f['structures']),scene_state='SCENE_STALE')
    r=s.snapshot(f);r['logical_time']=4
    for obj in r['structures']:r['identity_epochs'][obj['id']]+=1
    case('recovery_after_interrupt',[start,{'advance_ms':1100},r],accepted=2,scene_state='SCENE_ACTIVE')
    case('restart_sender',[start,{'advance_ms':1100},n,b],accepted=2,sessions=2,session_id='b'*32)
    unconfirmed=deepcopy(e);unconfirmed['empty_confirmed']=False
    # Wire encoder correctly refuses unconfirmed empties; create raw integrity-valid
    # vector with a helper that does not bypass receiver validation.
    def raw_packets(message):
        import hashlib,math
        data=encode(message);out=[]
        for i in range(math.ceil(len(data)/600)):
            h=dict(wire='DYNAMIC_STRUCTURES_FRAGMENT',version=1,session_id=message['session_id'],session_started_ms=message['session_started_ms'],sequence=message['sequence'],index=i,count=math.ceil(len(data)/600),total_bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),data=base64.b64encode(data[i*600:(i+1)*600]).decode())
            out.append(base64.b64encode(encode(h)).decode())
        return {'packets':out}
    case('unconfirmed_empty',[start,raw_packets(unconfirmed)],accepted=1,scene_state='SCENE_ACTIVE',reason='unconfirmed_empty')
    pending=deepcopy(e);pending['diagnostic']={'observed_components':1,'tracking_status':'PENDING_TOPOLOGY'}
    case('pending_birth_is_not_empty',[start,raw_packets(pending)],accepted=1,scene_state='SCENE_ACTIVE',reason='unconfirmed_empty')
    s=new();version1=s.snapshot(f,start=True);older=s.snapshot(f)
    older['structures'][0]['geometry_version']=0
    case('geometry_version_invalid',[version1,raw_packets(older)],accepted=1,reason='geometry:geometry_version')
    altered=s.snapshot(f);altered['structures'][0]['convex_parts'][0][0][0]+=.5
    case('preserve_last_valid',[version1,altered],accepted=1,sequence=1)
    # Unknown color is not an identity; arbitrary stable structure IDs are legal.
    custom=deepcopy(f);custom['structures'][0]['id']='independent-of-color'
    custom['identity_epochs']={'independent-of-color':1,**{k:v for k,v in custom['identity_epochs'].items() if k!=f['structures'][0]['id']}}
    case('independent_ids',[new().snapshot(custom,start=True)],accepted=1)
    for file,name in [('09_hole','hole'),('10_corner','corner'),('03_rotation','rotation')]:
        frames=json.loads(Path('juegofrei/validation/replays/'+file+'.json').read_text(encoding='utf-8'))['frames']
        case(name,[new().snapshot(frames[-1],start=True)],accepted=1)
    mixed=deepcopy(f);obj=mixed['structures'][0]
    # Exact two-piece material partition, all in the original local coordinate system.
    ring=obj['regions'][0]['exterior'];xs=[p[0] for p in ring];ys=[p[1] for p in ring]
    x0,x1=min(xs),max(xs);y0,y1=min(ys),max(ys);mid=(x0+x1)/2
    obj['material_regions']=[]
    for left,right,mat in [(x0,mid,'GREEN_SOLID'),(mid,x1,'BLUE_BOUNCE')]:
        p=[[left,y0],[right,y0],[right,y1],[left,y1]]
        obj['material_regions'].append(dict(material=mat,regions=[dict(exterior=p,holes=[])],convex_parts=[p]))
    case('mixed_material_metadata',[new().snapshot(mixed,start=True)],accepted=1)
    bad=deepcopy(mixed);bad['structures'][0]['material_regions'][0]['material']='UNKNOWN'
    case('unknown_material',[new().snapshot(bad,start=True)],accepted=0,reason='material_id')
    orange=deepcopy(f)
    obj=orange['structures'][0]
    obj['material_regions']=[dict(material='ORANGE_ONE_WAY',regions=deepcopy(obj['regions']),convex_parts=deepcopy(obj['convex_parts']))]
    case('orange_metadata_only',[new().snapshot(orange,start=True)],accepted=1)
    overlap=deepcopy(mixed)
    overlap['structures'][0]['material_regions'][1]=deepcopy(overlap['structures'][0]['material_regions'][0])
    case('material_overlap',[new().snapshot(overlap,start=True)],accepted=0,reason='material_overlap')
    s=new();v=s.snapshot(f,start=True)
    future=Session('c'*32,2000).snapshot(f,start=True)
    future['structures'][0]['convex_parts']=[[[0,0],[1,0],[2,0]]]
    after=s.snapshot(f)
    case('invalid_future_session_cannot_poison',[v,future,after],accepted=2,session_id='a'*32,sequence=2,sessions=1)
    h=json.loads(fragment(v)[0]);h['data']='!'*len(h['data'])
    case('bad_base64',[{'packets':[base64.b64encode(encode(h)).decode()]}],accepted=0,reason='fragment_payload')
    case('invalid_utf8',[{'packets':[base64.b64encode(b'\xff\xfe').decode()]}],accepted=0,reason='utf8')
    case('oversize_datagram',[{'packets':[base64.b64encode(b'x'*1201).decode()]}],accepted=0,reason='datagram_size')
    altered_pose=deepcopy(f);altered_pose['structures'][0]['position']=[float('inf'),0]
    # Non-finite JSON cannot be emitted by the conforming Python encoder.
    # A higher identity epoch recovers a missed removal; a lower one never does.
    s=new();v=s.snapshot(f,start=True);advance=s.snapshot(f)
    for k in advance['identity_epochs']:advance['identity_epochs'][k]+=1
    rollback=s.snapshot(f)
    case('epoch_recovery_and_rollback',[v,advance,rollback],accepted=2,reason='identity_epoch_reuse')
    s=new();valid=s.snapshot(f,start=True);invalid=s.snapshot(f)
    invalid['structures'][0]['material_regions']=[]
    invalid['structures'][0]['geometry_version']+=1
    case('cache_cannot_hide_invalid_materials',[valid,invalid],accepted=1,reason='material_regions')
    s=new();valid=s.snapshot(f,start=True);invalid=s.snapshot(f)
    invalid['structures'][0]['units']='meters'
    case('cache_still_validates_metadata',[valid,invalid],accepted=1,reason='geometry:coordinate_space')
    case('unannounced_session',[b],accepted=0,reason='obsolete_or_unannounced_session')
    # Reserved memory budget: 9 partial messages, bounded to 8 and expires absolutely.
    s=new();partial=[]
    for _ in range(9):partial.append({'packets':packets(s.snapshot(f,start=True))[:1]})
    case('pending_budget',partial,accepted=0,pending=8,reason='reassembly_budget')
    case('expired_partial_then_full',[{'packets':wire[:1]},{'advance_ms':1100},{'packets':wire}],accepted=1,expired=1,pending=0)
    # Full 3600-frame Phase 1D stream, including topology changes and new IDs.
    frames=json.loads(Path('juegofrei/validation/replays/20_long.json').read_text(encoding='utf-8'))['frames']
    frames=[fr for fr in frames if confirmed_frame(fr)]
    s=new();case('prolonged',[s.snapshot(fr,start=i%30==0) for i,fr in enumerate(frames)],accepted=len(frames),merges=30,splits=29,pending=0)
    return result


def main():
    output=Path('juegofrei/validation/structure_udp_vectors.json')
    cases=vectors();output.write_text(json.dumps(dict(vector_version=1,cases=cases),separators=(',',':')),encoding='utf-8')
    print(json.dumps(dict(cases=len(cases),bytes=output.stat().st_size)))


if __name__=='__main__':main()

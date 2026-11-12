"""Dynamic structure transport v1. Independent of CAMERA/PROJECTOR transports.

Only offline JSON and synthetic arrays are consumed. No capture imports.
"""
from __future__ import annotations
import base64
from copy import deepcopy
import hashlib
import json
import math
import time
import uuid
from collections import OrderedDict

PROTOCOL = 'DYNAMIC_STRUCTURES'
WIRE = 'DYNAMIC_STRUCTURES_FRAGMENT'
PORT = 5015
MAX_DATAGRAM = 1200
CHUNK = 600
MAX_MESSAGE = 262144
MAX_FRAGMENTS = 512
STATES = ('SCENE_ACTIVE', 'SCENE_EMPTY', 'SCENE_ERROR')
_material_schema_cache = OrderedDict()


def confirmed_frame(frame):
    """An unconfirmed birth is NOT evidence that the scene is empty."""
    if 'region_identity_epochs' in frame:
        return frame.get('diagnostic',{}).get('status')=='TRACKING'
    if frame['structures']: return True
    diagnostic=frame.get('diagnostic',{})
    if diagnostic.get('observed_components',0)>0 or diagnostic.get('tracking_status')=='PENDING_TOPOLOGY': return False
    return frame.get('empty_confirmed') is True or (diagnostic.get('observed_components')==0 and diagnostic.get('tracking_status')=='TRACKING')


def encode(value):
    return json.dumps(value, separators=(',', ':'), allow_nan=False).encode('utf-8')


class Session:
    def __init__(self, session_id=None, started_ms=None):
        self.id = session_id or uuid.uuid4().hex
        self.started_ms = started_ms or time.time_ns() // 1_000_000
        self.sequence = 0

    def snapshot(self, frame, *, scene_state=None, start=False, error=None):
        if error is None and not confirmed_frame(frame): raise ValueError('unconfirmed_absence')
        self.sequence += 1
        message = deepcopy(frame)
        message.update(protocol=PROTOCOL, protocol_version=2 if 'region_identity_epochs' in frame else 1, geometry_contract_version=1,
                       session_id=self.id, session_started_ms=self.started_ms,
                       sequence=self.sequence, message_type='SESSION_START' if start else 'SNAPSHOT',
                       scene_state=scene_state or ('SCENE_ACTIVE' if frame['structures'] else 'SCENE_EMPTY'),
                       empty_confirmed=not frame['structures'], sent_unix_ms=time.time_ns()/1e6)
        if message['protocol_version']==2:message['material_contract_version']=1
        if error is not None:
            message['error'] = str(error)[:256]
            message['scene_state'] = 'SCENE_ERROR'
        validate_snapshot(message)
        # Bootstrap/schema validation can be slow. This timestamp describes
        # transmission preparation, not the start of Python's imports/validation.
        message['sent_unix_ms']=time.time_ns()/1e6
        return message


def integer(v, low=0, high=2147483647):
    return type(v) is int and low <= v <= high


def validate_snapshot(m):
    """Envelope/identity budgets. Godot additionally validates exact polygon coverage."""
    if not isinstance(m, dict) or m.get('protocol') != PROTOCOL or type(m.get('protocol_version')) is not int or m.get('protocol_version') not in (1,2) or m.get('geometry_contract_version') != 1:
        raise ValueError('protocol')
    sid=m.get('session_id', '')
    if not isinstance(sid,str) or len(sid)!=32 or any(c not in '0123456789abcdef' for c in sid): raise ValueError('session_id')
    if not integer(m.get('session_started_ms'),1,9007199254740991) or not integer(m.get('sequence'),1): raise ValueError('session_or_sequence')
    if m.get('message_type') not in ('SESSION_START','SNAPSHOT') or m.get('scene_state') not in STATES: raise ValueError('type_or_state')
    t=m.get('logical_time')
    if type(t) not in (float,int) or not math.isfinite(t) or t<0: raise ValueError('logical_time')
    structures=m.get('structures'); epochs=m.get('identity_epochs'); events=m.get('events')
    if not isinstance(structures,list) or len(structures)>32 or not isinstance(epochs,dict) or not isinstance(events,list) or len(events)>64: raise ValueError('snapshot_budget')
    ids=set()
    for s in structures:
        if not isinstance(s,dict) or not isinstance(s.get('id'),str) or not 1<=len(s['id'])<=64 or s['id'] in ids: raise ValueError('id')
        ids.add(s['id'])
        if not integer(epochs.get(s['id']),1) or not integer(s.get('geometry_version'),1): raise ValueError('identity_version')
        if s.get('contract_version')!=1 or s.get('coordinate_space')!='ARENA_PIXELS': raise ValueError('geometry_contract')
    if set(epochs)!=ids: raise ValueError('epochs')
    if m['protocol_version']==2:
        from .material_structures import validate_material_contract
        if m.get('material_contract_version')!=1 or not isinstance(m.get('region_identity_epochs'),dict):raise ValueError('material_protocol')
        regional=set()
        for s in structures:
            key=hashlib.sha256(encode({k:s.get(k) for k in ('id','contract_version','material_contract_version','material_regions')})).digest()
            if key not in _material_schema_cache:
                validate_material_contract(s)
                _material_schema_cache[key]=True
                if len(_material_schema_cache)>256:_material_schema_cache.popitem(last=False)
            else:_material_schema_cache.move_to_end(key)
            for r in s['material_regions']:
                if r['region_id'] in regional or not integer(m['region_identity_epochs'].get(r['region_id']),1):raise ValueError('regional_epoch_or_id')
                regional.add(r['region_id'])
        if set(m['region_identity_epochs'])!=regional:raise ValueError('regional_epochs')
    if m['scene_state']=='SCENE_ACTIVE' and not structures: raise ValueError('active_without_structures')
    if m['scene_state']=='SCENE_EMPTY' and (structures or m.get('empty_confirmed') is not True): raise ValueError('unconfirmed_empty')
    if m['scene_state']=='SCENE_EMPTY':
        d=m.get('diagnostic',{})
        if d.get('observed_components',0)>0 or d.get('tracking_status')=='PENDING_TOPOLOGY': raise ValueError('unconfirmed_empty')
    for e in events:
        if not isinstance(e,dict) or e.get('type') not in ('MERGE','SPLIT') or any(not isinstance(e.get(k),list) or not 1<=len(e[k])<=32 or any(not isinstance(i,str) or not 1<=len(i)<=64 for i in e[k]) for k in ('parents','children')): raise ValueError('event')


def fragment(message, chunk=CHUNK, max_message=MAX_MESSAGE):
    validate_snapshot(message)
    if chunk!=CHUNK: raise ValueError('chunk')
    data=encode(message)
    if len(data)>max_message: raise ValueError('message_size')
    count=math.ceil(len(data)/chunk)
    if count>MAX_FRAGMENTS: raise ValueError('fragment_count')
    digest=hashlib.sha256(data).hexdigest()
    packets=[]
    for index in range(count):
        p=encode(dict(wire=WIRE,version=1,session_id=message['session_id'],
                      session_started_ms=message['session_started_ms'],sequence=message['sequence'],
                      index=index,count=count,total_bytes=len(data),sha256=digest,
                      data=base64.b64encode(data[index*chunk:(index+1)*chunk]).decode('ascii')))
        if len(p)>MAX_DATAGRAM: raise ValueError('datagram_size')
        packets.append(p)
    return packets


class Reassembler:
    """Bounded reference implementation, mirrors the Godot wire checks."""
    def __init__(self, ttl=1., max_pending=8, memory=1048576):
        self.ttl=ttl;self.max_pending=max_pending;self.memory=memory
        self.pending={};self.reserved=0;self.expired=0

    def expire(self, now):
        for k,p in list(self.pending.items()):
            if now-p['at']>=self.ttl:
                self.reserved-=p['header']['total_bytes'];del self.pending[k];self.expired+=1

    def feed(self, data, now=None):
        now=time.monotonic() if now is None else now
        self.expire(now)
        if len(data)>MAX_DATAGRAM: raise ValueError('datagram_size')
        h=json.loads(data)
        if not isinstance(h,dict): raise ValueError('fragment_object')
        if h.get('wire')!=WIRE or h.get('version')!=1: raise ValueError('wire')
        if not isinstance(h.get('session_id'),str) or len(h['session_id'])!=32 or any(c not in '0123456789abcdef' for c in h['session_id']): raise ValueError('session')
        if not integer(h.get('session_started_ms'),1,9007199254740991) or not integer(h.get('sequence'),1): raise ValueError('sequence')
        if not integer(h.get('count'),1,MAX_FRAGMENTS) or not integer(h.get('index'),0,h['count']-1) or not integer(h.get('total_bytes'),1,MAX_MESSAGE): raise ValueError('limits')
        if h['count']!=math.ceil(h['total_bytes']/CHUNK): raise ValueError('fragment_layout')
        if not isinstance(h.get('sha256'),str) or len(h['sha256'])!=64 or any(c not in '0123456789abcdef' for c in h['sha256']): raise ValueError('digest')
        raw=base64.b64decode(h['data'],validate=True)
        if base64.b64encode(raw).decode('ascii')!=h['data']: raise ValueError('noncanonical_base64')
        expected=min(CHUNK,h['total_bytes']-h['index']*CHUNK)
        if len(raw)!=expected: raise ValueError('fragment_size')
        key=(h['session_id'],h['session_started_ms'],h['sequence'])
        if key not in self.pending:
            if len(self.pending)>=self.max_pending or self.reserved+h['total_bytes']>self.memory: raise ValueError('reassembly_budget')
            self.pending[key]={'header':h,'parts':{},'at':now};self.reserved+=h['total_bytes']
        p=self.pending[key]
        if any(h[k]!=p['header'][k] for k in ('count','total_bytes','sha256')): raise ValueError('conflicting_header')
        if h['index'] in p['parts'] and p['parts'][h['index']]!=raw: raise ValueError('conflicting_fragment')
        p['parts'][h['index']]=raw
        if len(p['parts'])!=h['count']: return None
        self.reserved-=h['total_bytes'];del self.pending[key]
        body=b''.join(p['parts'][i] for i in range(h['count']))
        if hashlib.sha256(body).hexdigest()!=h['sha256']: raise ValueError('integrity')
        m=json.loads(body);validate_snapshot(m)
        if (m['session_id'],m['session_started_ms'],m['sequence'])!=key: raise ValueError('envelope_mismatch')
        return m

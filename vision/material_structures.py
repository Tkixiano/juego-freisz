"""Offline multimaterial extension to the existing segmentation/tracking/contract.

No sockets or camera imports. Publishing is a full-state transaction: an invalid
or unconfirmed partition keeps the last complete silhouette + material partition.
"""
from __future__ import annotations
from copy import deepcopy
from dataclasses import replace
from collections import OrderedDict
import hashlib
import json
from time import perf_counter
import cv2
import numpy as np
from .material_config import MaterialConfig, MATERIALS
from .structure_segmentation import StructureSegmenter, StructureSettings, Region, cell_rings, signed_area
from .structure_tracking import StructureTracker, TrackedStructure
from .structure_geometry import ContractExporter, build_contract
from .offline_replay import annotate_contracts


def shape_key(data):
    return hashlib.sha256(json.dumps({k:data[k] for k in ('regions','convex_parts')},sort_keys=True,separators=(',',':'),allow_nan=False).encode()).hexdigest()


_validation_cache=OrderedDict()
def validate_material_contract(c):
    try:
        if not isinstance(c,dict):raise ValueError('material_contract_structure')
        try:
            key=json.dumps({k:c.get(k) for k in ('id','contract_version','material_contract_version','material_regions')},sort_keys=True,separators=(',',':'),allow_nan=False)
        except (TypeError,ValueError):key=None
        if key is not None and key in _validation_cache:
            _validation_cache.move_to_end(key)
            return True
        result=_validate_material_contract_schema(c)
        if key is not None:
            _validation_cache[key]=True
            if len(_validation_cache)>256:_validation_cache.popitem(last=False)
        return result
    except (TypeError,KeyError,IndexError,AttributeError) as e:
        raise ValueError('material_contract_structure: '+str(e)) from e


def _validate_material_contract_schema(c):
    """Bounded schema/ring checks; exact coverage is checked on masks at creation.

    Arbitrary imported polygon geometry additionally requires the existing Godot
    compound validator. This module produces only exact pixel-cell partitions.
    """
    if c.get('contract_version')!=1 or type(c.get('material_contract_version')) is not int or c['material_contract_version']!=1:raise ValueError('material_contract_version')
    if not isinstance(c.get('material_regions'),list) or not 1<=len(c['material_regions'])<=128:raise ValueError('material_regions')
    seen=set();total=0
    for r in c['material_regions']:
        if not isinstance(r,dict) or r.get('material') not in MATERIALS.values():raise ValueError('unknown_material')
        id=r.get('region_id')
        if not isinstance(id,str) or not 1<=len(id)<=64 or id in seen:raise ValueError('region_id')
        seen.add(id)
        if r.get('structure_id')!=c.get('id'):raise ValueError('region_owner')
        if type(r.get('geometry_version')) is not int or r['geometry_version']<1:raise ValueError('region_geometry_version')
        if not r.get('regions') or not r.get('convex_parts'):raise ValueError('empty_region')
        total+=len(r['convex_parts'])
        if total>512:raise ValueError('material_parts_budget')
        for region in r['regions']:
            for ring,positive in [(region['exterior'],True)]+[(h,False) for h in region['holes']]:
                p=np.asarray(ring,dtype=float)
                if p.ndim!=2 or p.shape[1]!=2 or not 3<=len(p)<=2048 or not np.isfinite(p).all():raise ValueError('invalid_material_ring')
                if (signed_area(p)>0)!=positive or abs(signed_area(p))<1e-6 or len(np.unique(p,axis=0))!=len(p):raise ValueError('invalid_material_ring')
    return True


class MaterialStructures:
    def __init__(self, config=None, settings=None):
        self.config=(config or MaterialConfig()).validate()
        # Pixel-exact material coverage cannot be paired with a cached different
        # silhouette. This opt-in pipeline changes no legacy tracker defaults.
        self.settings=replace(settings or StructureSettings(min_area=16),
                              geometry_difference_fraction=0,geometry_boundary_pixels=0)
        self.segmenter=StructureSegmenter(self.config.colors,self.settings,
                                         exclusive_colors=True,material_opening=self.config.opening_kernel)
        self.tracker=StructureTracker(self.settings)
        self.contracts=ContractExporter(self.config.max_parts)
        self.region_tracks={};self.serial=0;self.ledger={};self.epochs={};self.active=set()
        self.region_geometry_cache=OrderedDict()
        self.sequence=0;self.frame=0;self.last=[];self.last_epochs={}
        self.last_signature=None;self.pending_signature=None;self.pending_count=0
        self.source_events=[];self.errors=[];self.held_frames=0
        self.last_segmentation=None;self.timings=[];self.frame_timings_ms=[]
        self.metrics=dict(accepted=0,held=0,rejected=0,region_births=0,region_identity_ambiguities=0,
                          merges=0,splits=0,geometry_builds=0,material_geometry_builds=0,material_geometry_cache_hits=0)

    def _candidates(self,segmentation):
        candidates=[];occupied=np.zeros_like(segmentation.combined);parts=0
        for obj in self.tracker.objects.values():
            ox,oy,ow,oh=cv2.boundingRect(obj.geometry_mask.astype('uint8'))
            ys,xs=slice(oy,oy+oh),slice(ox,ox+ow)
            object_crop=obj.geometry_mask[ys,xs]
            covered=np.zeros_like(object_crop)
            for color_id,material in MATERIALS.items():
                mask=object_crop & segmentation.material_masks[color_id][ys,xs]
                n,labels,stats,centers=cv2.connectedComponentsWithStats(mask.astype('uint8'),connectivity=8)
                for i in range(1,n):
                    local_mask=labels==i;area=int(stats[i,cv2.CC_STAT_AREA]);center=centers[i]+[ox,oy]+.5
                    origin=np.rint(obj.position)
                    lx,ly,w,h=map(int,stats[i,:4]);crop=local_mask[ly:ly+h,lx:lx+w]
                    x,y=lx+ox,ly+oy
                    rm=np.zeros_like(obj.geometry_mask);rm[ys,xs]=local_mask
                    key=(crop.shape,hashlib.blake2b(crop.tobytes(),digest_size=16).digest())
                    cached=self.region_geometry_cache.get(key)
                    if cached is not None and np.array_equal(cached['mask'],crop):
                        geometry0=cached['geometry'];self.metrics['material_geometry_cache_hits']+=1
                        self.region_geometry_cache.move_to_end(key)
                    else:
                        rings=cell_rings(crop)
                        region=Region(crop,rings,center-[x,y],area,{color_id:1.},'CONNECTED',0,(0,0,w,h))
                        temporary=TrackedStructure('pending',region,(),np.zeros(2),rings,crop)
                        built=build_contract(temporary,self.config.max_parts)
                        geometry0={k:built[k] for k in ('regions','convex_parts')}
                        self.region_geometry_cache[key]={'mask':crop.copy(),'geometry':geometry0}
                        self.metrics['material_geometry_builds']+=1
                        while len(self.region_geometry_cache)>self.config.max_regions:self.region_geometry_cache.popitem(last=False)
                    # Rebase cached exact geometry, never approximate by its crop.
                    offset=np.array([x,y])-origin
                    geometry=dict(regions=[dict(exterior=(np.asarray(r['exterior'])+offset).tolist(),holes=[(np.asarray(hole)+offset).tolist() for hole in r['holes']]) for r in geometry0['regions']],
                                  convex_parts=[(np.asarray(part)+offset).tolist() for part in geometry0['convex_parts']])
                    parts+=len(geometry['convex_parts'])
                    if parts>self.config.max_parts:raise ValueError('material_parts_budget')
                    if np.any(covered & local_mask) or np.any(occupied[ys,xs] & local_mask):raise ValueError('material_overlap')
                    covered|=local_mask;occupied[ys,xs]|=local_mask
                    candidates.append(dict(owner=obj.id,material=material,mask=rm,center=center,geometry=geometry,bounds=(x,y,w,h),area=area))
                    if len(candidates)>self.config.max_regions:raise ValueError('material_region_limit')
            if not np.array_equal(covered,object_crop):raise ValueError('material_coverage_mismatch')
        return candidates

    def _assign_regions(self,candidates):
        old=list(self.region_tracks.values());edges=set()
        def bounds(c):return c.get('bounds') or cv2.boundingRect(c['mask'].astype('uint8'))
        old_bounds=[bounds(c) for c in old];new_bounds=[bounds(c) for c in candidates]
        old_areas=[c['area'] if 'area' in c else int(np.count_nonzero(c['mask'])) for c in old]
        new_areas=[c['area'] for c in candidates]
        for i,p in enumerate(old):
            for j,c in enumerate(candidates):
                if p['entry']['material']!=c['material']:continue
                ax,ay,aw,ah=old_bounds[i];bx,by,bw,bh=new_bounds[j]
                x,y=max(ax,bx),max(ay,by);right,bottom=min(ax+aw,bx+bw),min(ay+ah,by+bh)
                if right<=x or bottom<=y:continue
                if np.count_nonzero(p['mask'][y:bottom,x:right] & c['mask'][y:bottom,x:right])/min(old_areas[i],new_areas[j])>=.2:
                    edges.add((i,j))
        # Fallback only for mutually unique same-shape nearby movement.
        fallback=set()
        def canonical(mask):
            x,y,w,h=cv2.boundingRect(mask.astype('uint8'))
            return (w,h,mask[y:y+h,x:x+w].tobytes())
        for i,p in enumerate(old):
            if any(a==i for a,b in edges):continue
            for j,c in enumerate(candidates):
                if any(b==j for a,b in edges) or p['entry']['material']!=c['material']:continue
                if np.linalg.norm(p['center']-c['center'])<=self.settings.max_motion_pixels and canonical(p['mask'])==canonical(c['mask']):fallback.add((i,j))
        for i,j in fallback:
            if sum(a==i for a,b in fallback)==1 and sum(b==j for a,b in fallback)==1:edges.add((i,j))
        tracks={};events=[];entries={}
        for j,c in enumerate(candidates):
            matches=[i for i,b in edges if b==j]
            previous=old[matches[0]] if len(matches)==1 and sum(a==matches[0] for a,b in edges)==1 else None
            key=shape_key(c['geometry'])
            if previous:
                id=previous['entry']['region_id']
                version=previous['entry']['geometry_version']+int(key!=previous['key'])
                if previous['entry']['structure_id']!=c['owner']:
                    events.append(dict(type='REGION_REPARENT',region_id=id,previous_owner=previous['entry']['structure_id'],structure_id=c['owner']))
            else:
                self.serial+=1;id=f'r{self.serial:08d}';version=1
                events.append(dict(type='REGION_CREATE',region_id=id,structure_id=c['owner']))
                if matches:
                    events.append(dict(type='REGION_IDENTITY_AMBIGUITY',region_id=id,parents=[old[i]['entry']['region_id'] for i in matches],reason='non_unique_geometric_evidence_new_identity'))
            entry=dict(region_id=id,structure_id=c['owner'],material=c['material'],geometry_version=version,**deepcopy(c['geometry']))
            tracks[id]=dict(entry=entry,mask=c['mask'],center=c['center'],key=key,bounds=c['bounds'],area=c['area'])
            entries.setdefault(c['owner'],[]).append(entry)
        for id in self.region_tracks.keys()-tracks.keys():events.append(dict(type='REGION_REMOVE',region_id=id))
        return tracks,entries,events

    def _held(self,reason):
        self.metrics['held']+=1;self.held_frames+=1
        last=deepcopy(self.last)
        for c in last:c['tracking']=dict(state='HELD',age_frames=self.held_frames);c['confidence']=0.0
        return dict(sequence=self.sequence,source_frame=self.frame,structures=last,
                    identity_epochs=self.last_epochs.copy(),events=[],material_events=[],
                    status=reason,errors=self.errors[-1:] if reason=='REJECTED' else [])

    def update(self,image):
        self.frame+=1;self.sequence=self.frame;start=perf_counter();self.source_events=[]
        try:
            seg=self.segmenter.segment(image);self.last_segmentation=seg
            segmented=perf_counter();source=self.tracker.update(seg);tracked=perf_counter()
            if source['events']:
                self.source_events_buffer=getattr(self,'source_events_buffer',[])+deepcopy(source['events'])
                self.source_events_buffer=self.source_events_buffer[-128:]
            if source['status']!='TRACKING':return self._held(source['status'])
            candidates=self._candidates(seg)
            signature=tuple(sorted((c['owner'],c['material'],shape_key(c['geometry'])) for c in candidates))
            if signature!=self.last_signature:
                self.pending_count=self.pending_count+1 if signature==self.pending_signature else 1
                self.pending_signature=signature
                if self.pending_count<self.config.confirmation_frames:return self._held('PENDING_MATERIALS')
            # Rebase BOTH the parent and its material regions to an integer cell
            # anchor. World edges remain exact; only local coordinates change.
            # This prevents float32 centroid cancellation in Godot clipping.
            rebased=[replace(obj,position=np.rint(obj.position),
                             local_rings=tuple(np.rint(r+obj.position)-np.rint(obj.position) for r in obj.local_rings))
                     for obj in self.tracker.objects.values()]
            contracts=self.contracts.export(rebased)
            proposed,entries,material_events=self._assign_regions(candidates)
            for c in contracts:
                c.update(material_contract_version=1,material_regions=entries[c['id']])
                validate_material_contract(c)
            ledger,epochs,active=annotate_contracts(contracts,self.ledger,self.epochs,self.active)
            old=self.active;events=[]
            for e in getattr(self,'source_events_buffer',[]):
                if e['type'] in ('MERGE','SPLIT') and all(p in old for p in e['parents']) and all(c in active for c in e['children']):events.append(e)
            self.metrics['merges']+=sum(e['type']=='MERGE' for e in events)
            self.metrics['splits']+=sum(e['type']=='SPLIT' for e in events)
            self.metrics['region_births']+=sum(e['type']=='REGION_CREATE' for e in material_events)
            self.metrics['region_identity_ambiguities']+=sum(e['type']=='REGION_IDENTITY_AMBIGUITY' for e in material_events)
            self.ledger,self.epochs,self.active=ledger,epochs,active
            self.region_tracks=proposed;self.last=deepcopy(contracts)
            self.last_epochs={id:self.epochs[id] for id in sorted(active)}
            self.last_signature=signature;self.pending_count=0;self.held_frames=0
            self.source_events_buffer=[];self.metrics['accepted']+=1
            self.metrics['geometry_builds']=self.contracts.builds
            self.timings.append(dict(segmentation_ms=(segmented-start)*1000,tracking_ms=(tracked-segmented)*1000,
                                     geometry_material_ms=(perf_counter()-tracked)*1000,total_ms=(perf_counter()-start)*1000))
            self.timings=self.timings[-2048:]
            return dict(sequence=self.sequence,source_frame=self.frame,structures=deepcopy(contracts),
                        identity_epochs=self.last_epochs.copy(),events=events,material_events=material_events,
                        status='TRACKING',errors=[])
        except (ValueError,KeyError,TypeError,AttributeError,cv2.error) as e:
            self.errors.append(dict(frame=self.frame,reason=str(e)));self.errors=self.errors[-128:]
            self.metrics['rejected']+=1
            return self._held('REJECTED')
        finally:
            self.frame_timings_ms.append((perf_counter()-start)*1000)
            self.frame_timings_ms=self.frame_timings_ms[-2048:]

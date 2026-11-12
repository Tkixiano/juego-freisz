from copy import deepcopy
from dataclasses import replace
import json
from pathlib import Path
import tempfile
import unittest
import cv2
import numpy as np
from vision.config import load as load_legacy
from vision.material_config import MaterialConfig,load_materials,save_materials,MATERIALS
from vision.material_structures import MaterialStructures,validate_material_contract
from vision.material_synthetic import scenarios,three,separated,joined,bgr,blank


def raster(snapshot,shape):
    labels=np.zeros(shape,np.uint8);occupied=np.zeros(shape,np.uint8)
    for c in snapshot['structures']:
        for r in c['material_regions']:
            material=next(k for k,v in MATERIALS.items() if v==r['material'])
            for part in r['convex_parts']:
                p=np.asarray(part)+c['position']
                if np.max(np.abs(p-np.rint(p)))>1e-6:raise AssertionError('non-cell geometry')
                x0,y0=p.min(axis=0).astype(int);x1,y1=p.max(axis=0).astype(int)
                occupied[y0:y1,x0:x1]+=1;labels[y0:y1,x0:x1]=material
    return labels,occupied


def settle(pipeline,image,n=12):
    snapshots=[pipeline.update(image) for _ in range(n)]
    return snapshots[-1],snapshots


class MaterialTests(unittest.TestCase):
    def test_twenty_scenarios(self):
        results=[];fixtures=[]
        for name,frames,refs in scenarios():
            with self.subTest(name=name):
                p=MaterialStructures();snapshots=[p.update(f) for f in frames];last=snapshots[-1]
                self.assertEqual(last['status'],'TRACKING',p.errors)
                self.assertFalse(p.errors)
                labels,occupied=raster(last,refs[-1].shape)
                error=int(np.count_nonzero(labels!=refs[-1]));overlap=int(np.count_nonzero(occupied>1))
                self.assertEqual(error,0);self.assertEqual(overlap,0)
                ids=[r['region_id'] for c in last['structures'] for r in c['material_regions']]
                self.assertEqual(len(ids),len(set(ids)))
                for c in last['structures']:self.assertTrue(validate_material_contract(c))
                for color in (1,2,3):self.assertTrue(np.array_equal(p.last_segmentation.material_masks[color],refs[-1]==color))
                events=[e for s in snapshots for e in s['events']]
                if name in ('10_merge','11_split'):self.assertEqual(sum(e['type']=='MERGE' for e in events),1)
                if name=='11_split':self.assertEqual(sum(e['type']=='SPLIT' for e in events),1)
                if name=='09_three_green_regions':self.assertEqual(sum(r['material']=='GREEN_SOLID' for c in last['structures'] for r in c['material_regions']),3)
                if name=='14_corner':self.assertEqual(len(last['structures'][0]['regions']),2)
                if name=='12_holes':self.assertTrue(any(region['holes'] for c in last['structures'] for r in c['material_regions'] for region in r['regions']))
                if name=='19_brief_loss':
                    self.assertEqual([r['region_id'] for c in snapshots[9]['structures'] for r in c['material_regions']],ids)
                    self.assertEqual(snapshots[10]['status'],'PENDING_TOPOLOGY')
                if name=='20_reappearance':
                    before={r['region_id'] for c in snapshots[9]['structures'] for r in c['material_regions']}
                    self.assertFalse(before.intersection(ids))
                area=int(np.count_nonzero(refs[-1]));hist={v:int(np.count_nonzero(labels==k)) for k,v in MATERIALS.items()}
                results.append(dict(name=name,source_frames=len(frames),structures=len(last['structures']),regions=len(ids),pixel_error=error,overlap_pixels=overlap,iou=1.0 if not error else None,reference_area=area,material_area=hist,merges=sum(e['type']=='MERGE' for e in events),splits=sum(e['type']=='SPLIT' for e in events),region_identity_ambiguities=p.metrics['region_identity_ambiguities'],timings=p.timings,frame_timings_ms=p.frame_timings_ms))
                fixtures.append(dict(name=name,structures=last['structures'],identity_epochs=last['identity_epochs'],expected_area=area,material_area=hist))
        Path('artifacts/phase3b1/scenarios.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
        Path('juegofrei/validation/material_contract_fixtures.json').write_text(json.dumps(dict(material_fixture_version=1,cases=fixtures)),encoding='utf-8')

    def test_ids_survive_different_material_merge_split(self):
        p=MaterialStructures();a,_=settle(p,bgr(separated()))
        before={r['material']:r['region_id'] for c in a['structures'] for r in c['material_regions']}
        m,ms=settle(p,bgr(joined()))
        middle={r['material']:r['region_id'] for c in m['structures'] for r in c['material_regions']}
        s,ss=settle(p,bgr(separated()))
        after={r['material']:r['region_id'] for c in s['structures'] for r in c['material_regions']}
        self.assertEqual(before,middle);self.assertEqual(before,after)
        for c in s['structures']:self.assertEqual(s['identity_epochs'][c['id']],2)
        self.assertEqual((p.metrics['merges'],p.metrics['splits']),(1,1))

    def test_same_color_ambiguous_split_gets_new_region_ids(self):
        a=blank();a[60:100,20:70]=1;a[60:100,90:140]=1
        m=a.copy();m[60:100,70:90]=1
        p=MaterialStructures();s,_=settle(p,bgr(a));old={r['region_id'] for c in s['structures'] for r in c['material_regions']}
        settle(p,bgr(m));s,_=settle(p,bgr(a))
        new={r['region_id'] for c in s['structures'] for r in c['material_regions']}
        self.assertFalse(old&new);self.assertGreater(p.metrics['region_identity_ambiguities'],0)

    def test_material_change_requires_confirmation_and_version(self):
        p=MaterialStructures();a=bgr(joined(1,2));initial,_=settle(p,a)
        altered=bgr(joined(1,3));one=p.update(altered)
        self.assertEqual(one['status'],'PENDING_MATERIALS')
        self.assertEqual(one['structures'][0]['geometry_version'],initial['structures'][0]['geometry_version'])
        final,_=settle(p,altered)
        self.assertGreater(final['structures'][0]['geometry_version'],initial['structures'][0]['geometry_version'])
        self.assertIn('ORANGE_ONE_WAY',[r['material'] for r in final['structures'][0]['material_regions']])

    def test_one_frame_recolor_does_not_change_ids_or_versions(self):
        p=MaterialStructures();original=bgr(three());a,_=settle(p,original)
        p.update(bgr(joined(1,3)));b,_=settle(p,original)
        self.assertEqual(a['structures'],b['structures'])

    def test_pose_changes_do_not_change_material_geometry_version(self):
        p=MaterialStructures();labels=three();a,_=settle(p,bgr(labels))
        for dx in range(1,9):s=p.update(bgr(np.roll(labels,dx,axis=1)))
        self.assertEqual(a['structures'][0]['geometry_version'],s['structures'][0]['geometry_version'])
        self.assertEqual([r['region_id'] for r in a['structures'][0]['material_regions']],[r['region_id'] for r in s['structures'][0]['material_regions']])

    def test_conflicting_masks_have_no_double_assignment(self):
        cfg=MaterialConfig();cfg.colors[1].lower=cfg.colors[0].lower.copy();cfg.colors[1].upper=cfg.colors[0].upper.copy()
        p=MaterialStructures(cfg);s,_=settle(p,bgr(joined(1,3)))
        seg=p.last_segmentation
        self.assertGreater(seg.conflict_pixels,0)
        self.assertFalse(np.any(seg.material_masks[1]&seg.material_masks[2]))
        self.assertEqual(int(seg.material_masks[1].sum()),0)
        self.assertTrue(any(r['material']=='ORANGE_ONE_WAY' for c in s['structures'] for r in c['material_regions']))

    def test_invalid_geometry_budget_preserves_last_partition(self):
        p=MaterialStructures();initial,_=settle(p,bgr(joined(1,2)))
        p.config.max_regions=1;s=p.update(bgr(joined(1,2)))
        self.assertEqual(s['status'],'REJECTED')
        self.assertEqual([r['region_id'] for c in initial['structures'] for r in c['material_regions']],[r['region_id'] for c in s['structures'] for r in c['material_regions']])
        self.assertEqual(initial['structures'][0]['geometry_version'],s['structures'][0]['geometry_version'])

    def test_schema_rejects_bad_region_metadata(self):
        c=settle(MaterialStructures(),bgr(three()))[0]['structures'][0]
        for field,value in [('material','UNKNOWN'),('region_id',''),('structure_id','wrong'),('geometry_version',0),('regions',[])]:
            bad=deepcopy(c);bad['material_regions'][0][field]=value
            with self.assertRaises(ValueError,msg=field):validate_material_contract(bad)
        for value in (None,[],{'material_contract_version':True}):
            with self.assertRaises(ValueError):validate_material_contract(value)

    def test_returned_snapshot_does_not_mutate_tracks(self):
        p=MaterialStructures();s,_=settle(p,bgr(three()));s['structures'][0]['material_regions'][0]['material']='WRONG'
        self.assertNotIn('WRONG',[r['entry']['material'] for r in p.region_tracks.values()])

    def test_hsv_profile_independent_roundtrip(self):
        legacy=Path('vision/config.json').read_bytes()
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'materials.json';cfg=MaterialConfig();cfg.colors[2].lower[0]=7
            save_materials(cfg,p);self.assertEqual(load_materials(p).colors[2].lower[0],7)
        self.assertEqual(Path('vision/config.json').read_bytes(),legacy)
        self.assertEqual([c.id for c in load_legacy(Path('vision/config.json')).colors],[1,2])
        with self.assertRaises(ValueError):save_materials(MaterialConfig(),Path('vision/config.json'))

    def test_bad_frame_does_not_clear_previous(self):
        p=MaterialStructures();a,_=settle(p,bgr(three()))
        for invalid in (np.zeros((10,10),np.uint8),None,[]):
            b=p.update(invalid)
            self.assertEqual(b['status'],'REJECTED');self.assertEqual(len(b['structures']),len(a['structures']))

    def test_repeated_merge_split_preserves_material_identity(self):
        p=MaterialStructures();initial,_=settle(p,bgr(separated()))
        ids={r['material']:r['region_id'] for c in initial['structures'] for r in c['material_regions']}
        for _ in range(5):
            settle(p,bgr(joined()));snapshot,_=settle(p,bgr(separated()))
            self.assertEqual(ids,{r['material']:r['region_id'] for c in snapshot['structures'] for r in c['material_regions']})
        self.assertEqual((p.metrics['merges'],p.metrics['splits']),(5,5))
        self.assertEqual(sorted(snapshot['identity_epochs'].values()),[6,6])

    def test_malformed_profile_is_rejected_safely(self):
        with tempfile.TemporaryDirectory() as d:
            path=Path(d)/'profile.json'
            for value in ({},[],{'material_config_version':True},{'material_config_version':1,'colors':None}):
                path.write_text(json.dumps(value),encoding='utf-8')
                with self.assertRaises(ValueError):load_materials(path)


if __name__=='__main__':unittest.main()

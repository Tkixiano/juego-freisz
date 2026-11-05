"""Synthetic geometry contract fixtures; never capture devices or send packets."""
from __future__ import annotations
import copy
import json
import importlib
import sys
import types
from pathlib import Path
import unittest
from unittest.mock import patch
import cv2
import numpy as np
from vision.structure_segmentation import Region, cell_rings, signed_area, StructureSegmenter
from vision.structure_tracking import TrackedStructure, StructureTracker
from vision.structure_geometry import build_contract, exact_rectangles, ContractExporter
from vision.structure_synthetic import COLORS, fixtures, scenarios


def masks():
    base=np.zeros((96,128),np.uint8)
    convex=base.copy();cv2.fillPoly(convex,[np.array([[10,60],[35,10],[70,60]])],1)
    concave=base.copy();concave[10:70,10:30]=1;concave[50:70,30:80]=1
    point=base.copy();point[10:35,10:35]=1;point[35:60,35:60]=1
    edge=base.copy();edge[10:40,10:40]=1;edge[20:60,40:70]=1
    multiple=base.copy();multiple[10:30,10:30]=1;multiple[30:50,30:50]=1;multiple[50:70,50:70]=1
    hole=base.copy();hole[10:80,10:100]=1;hole[30:60,30:75]=0
    holes=hole.copy();holes[15:25,20:35]=0
    thin=base.copy();thin[20:21,10:100]=1;thin[21:65,70:71]=1
    notch=base.copy();notch[10:80,10:100]=1;notch[10:60,40:70]=0
    return {'convex':convex,'concave':concave,'point_contact':point,'edge_contact':edge,
            'multiple_regions':multiple,'hole':hole,'two_holes':holes,'thin':thin,'notch':notch}


def object_from_mask(name,mask):
    mask=mask.astype(bool);area=int(np.count_nonzero(mask))
    if not area: raise ValueError('empty_mask')
    moments=cv2.moments(mask.astype('uint8'),True)
    center=np.array([moments['m10']/area+.5,moments['m01']/area+.5])
    rings=cell_rings(mask)
    region=Region(mask,rings,center,area,{1:1.},'CONNECTED',0,cv2.boundingRect(mask.astype('uint8')))
    return TrackedStructure(name,region,(),center,tuple(r-center for r in rings),mask.copy())


def rasterized_parts(contract,shape):
    yy,xx=np.indices(shape,dtype=float);xx=xx+.5;yy=yy+.5
    position=np.array(contract['position']);acc=np.zeros(shape,np.uint16)
    # Exact exporter parts are axis-aligned rectangles, with independent pose.
    for part in contract['convex_parts']:
        p=np.array(part)+position
        acc+=((xx>p[:,0].min()) & (xx<p[:,0].max()) & (yy>p[:,1].min()) & (yy<p[:,1].max()))
    return acc


def write_fixtures(path):
    cases=[]
    for name,mask in masks().items():
        data=build_contract(object_from_mask(name,mask))
        y,x=np.nonzero(mask)
        cases.append({'name':name,'contract':data,'resolution':[mask.shape[1],mask.shape[0]],
                      'reference_position':data['position'].copy(),
                      'foreground_runs':[[row,left,right] for row,left,right in __import__('vision.structure_segmentation',fromlist=['row_runs']).row_runs(mask)],
                      'expected_area':int(mask.sum())})
    rotated=copy.deepcopy(cases[5])
    rotated.update(name='rotated_hole',validation_only=True)
    rotated['contract'].update(id='rotated_hole',position=[350,130],orientation_radians=.37)
    cases.append(rotated)
    # Invalid candidates are never accepted by Godot and must preserve old geometry.
    good=cases[5]['contract']
    invalid=[]
    for label,modify in [
        ('fills_hole',lambda c:c['convex_parts'].append([[0,0],[10,0],[10,10],[0,10]])),
        ('missing_coverage',lambda c:c['convex_parts'].pop()),
        ('duplicate_part',lambda c:c['convex_parts'].append(copy.deepcopy(c['convex_parts'][0]))),
        ('degenerate',lambda c:c['convex_parts'].__setitem__(0,[[0,0],[1,0],[2,0]])),
        ('nonfinite',lambda c:c['convex_parts'].__setitem__(0,[[0,0],[float('inf'),0],[1,1]])),
        ('wrong_winding',lambda c:c['regions'][0]['exterior'].reverse()),
        ('wrong_space',lambda c:c.__setitem__('coordinate_space','CAMERA_NORMALIZED'))]:
        c=copy.deepcopy(good);modify(c)
        # JSON cannot portably express inf: use a separate GDScript nonfinite test.
        if label=='nonfinite':continue
        invalid.append({'name':label,'contract':c})
    payload={'contract_version':1,'synthetic_only':True,'cases':cases,'invalid':invalid}
    Path(path).write_text(json.dumps(payload,indent=2),encoding='utf-8')
    return payload


class ContractTests(unittest.TestCase):
    def setUp(self):
        self.camera=patch('cv2.VideoCapture',side_effect=AssertionError('NO CAMERA'));self.camera.start()
        self.network=patch('socket.socket',side_effect=AssertionError('NO NETWORK'));self.network.start()
        self.addCleanup(self.camera.stop);self.addCleanup(self.network.stop)

    def test_exact_parts_and_area_all_fixtures(self):
        for name,mask in masks().items():
            with self.subTest(name=name):
                obj=object_from_mask(name,mask);c=build_contract(obj)
                acc=rasterized_parts(c,mask.shape)
                np.testing.assert_array_equal(acc,mask)
                self.assertAlmostEqual(sum(signed_area(np.array(p)) for p in c['convex_parts']),int(mask.sum()),places=7)

    def test_point_keeps_one_id_and_multiple_regions(self):
        c=build_contract(object_from_mask('one_id',masks()['point_contact']))
        self.assertEqual(c['id'],'one_id');self.assertEqual(len(c['regions']),2)
        self.assertEqual(len(c['convex_parts']),2)

    def test_holes_have_opposite_winding(self):
        c=build_contract(object_from_mask('hole',masks()['two_holes']))
        self.assertEqual(len(c['regions'][0]['holes']),2)
        self.assertGreater(signed_area(np.array(c['regions'][0]['exterior'])),0)
        self.assertTrue(all(signed_area(np.array(h))<0 for h in c['regions'][0]['holes']))

    def test_limits_safe_rejection(self):
        with self.assertRaises(ValueError):build_contract(object_from_mask('hole',masks()['hole']),max_parts=1)
        with self.assertRaises(ValueError):object_from_mask('empty',np.zeros((10,10),np.uint8))

    def test_random_partitions_no_filled_holes_or_overlap(self):
        rng=np.random.default_rng(193)
        for _ in range(50):
            mask=rng.random((16,20))>.5
            parts=exact_rectangles(mask)
            c={'convex_parts':[p.tolist() for p in parts],'position':[0,0]}
            np.testing.assert_array_equal(rasterized_parts(c,mask.shape),mask)

    def test_frame_edge_clipping_rebuilds_last_accepted_rings(self):
        image=np.zeros((96,128,3),np.uint8);image[20:50,5:35]=(0,220,0)
        s=StructureSegmenter(COLORS);t=StructureTracker()
        for _ in range(5):t.update(s.segment(image))
        clipped=np.zeros_like(image);clipped[20:50,0:20]=(0,220,0)
        t.update(s.segment(clipped))
        for o in t.objects.values():
            c=build_contract(o);np.testing.assert_array_equal(rasterized_parts(c,clipped.shape[:2]),o.geometry_mask)

    def test_cache_only_rebuilds_on_shape_change_and_snapshot_owned(self):
        s=StructureSegmenter(COLORS);t=StructureTracker();exporter=ContractExporter()
        for x in range(20,40):
            image=np.zeros((96,128,3),np.uint8);image[20:50,x:x+30]=(0,220,0)
            t.update(s.segment(image));data=exporter.export(t.objects.values())
        self.assertEqual(exporter.builds,1)
        data[0]['regions'][0]['exterior'][0][0]=99999
        other=exporter.export(t.objects.values())
        self.assertNotEqual(other[0]['regions'][0]['exterior'][0][0],99999)

    def test_merge_split_contract_coverage(self):
        f=fixtures();s=StructureSegmenter(COLORS);t=StructureTracker();exporter=ContractExporter()
        for key in ['separated_colors','joined_colors','separated_colors']*3:
            for _ in range(5):
                t.update(s.segment(f[key]))
                contracts=exporter.export(t.objects.values())
                acc=np.zeros(f[key].shape[:2],np.uint16)
                for c in contracts:acc+=rasterized_parts(c,acc.shape)
                expected=np.zeros_like(acc)
                for o in t.objects.values():expected+=o.geometry_mask
                np.testing.assert_array_equal(acc,expected)
                self.assertLessEqual(int(acc.max()),1)

    def test_before_after_ids_events_and_geometry_are_identical(self):
        baseline=Path('artifacts/phase1c/before/vision')
        if not baseline.exists():self.skipTest('saved Phase 1B reference not available')
        package=types.ModuleType('reference_phase1b');package.__path__=[str(baseline.resolve())]
        sys.modules['reference_phase1b']=package
        old_s=importlib.import_module('reference_phase1b.structure_segmentation').StructureSegmenter
        old_t=importlib.import_module('reference_phase1b.structure_tracking').StructureTracker
        for name,stages,_ in scenarios():
            with self.subTest(scenario=name):
                s0,t0=old_s(COLORS),old_t();s1,t1=StructureSegmenter(COLORS),StructureTracker()
                for im,count,_ in stages:
                    for _ in range(count):
                        a=t0.update(s0.segment(im));b=t1.update(s1.segment(im))
                        self.assertEqual(a['events'],b['events'])
                        self.assertEqual(list(t0.objects),list(t1.objects))
                        for id in t0.objects:
                            np.testing.assert_array_equal(t0.objects[id].geometry_mask,t1.objects[id].geometry_mask)
                            np.testing.assert_allclose(t0.objects[id].position,t1.objects[id].position,atol=1e-9)
                            self.assertEqual(t0.objects[id].revision,t1.objects[id].revision)
                            self.assertEqual([m.id for m in t0.objects[id].members],[m.id for m in t1.objects[id].members])

    def test_contour_cache_is_exact_and_bounded(self):
        s=StructureSegmenter(COLORS)
        for x in range(20,90):
            image=np.zeros((96,128,3),np.uint8);image[20:40,10:x]=(0,220,0)
            s.segment(image)
        self.assertLessEqual(len(s._cache),s.settings.max_components)


if __name__=='__main__': unittest.main()

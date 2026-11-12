from copy import deepcopy
import json
from pathlib import Path
import unittest
from unittest.mock import patch
import numpy as np
from tests.perspective_hole_repro import H,clip_area
from tests.perspective_hole_cases import masks,from_mask
from tests.test_calibrated_geometry import mapper,frame
from vision.calibrated_geometry import CalibratedGeometryMapper,ImageLayout
from vision.structure_segmentation import signed_area

class PerspectiveHoleTests(unittest.TestCase):
    def setUp(self):
        self.guard=patch('cv2.VideoCapture',side_effect=AssertionError('NO HARDWARE'));self.guard.start();self.addCleanup(self.guard.stop)
    def verify_partition(self,f):
        m=mapper(H);out=m.map_frame(f)
        for c in out['structures']:
            total=sum(signed_area(np.asarray(p)) for p in c['convex_parts'])
            expected=sum(signed_area(np.asarray(r['exterior']))+sum(signed_area(np.asarray(h)) for h in r['holes']) for r in c['regions'])
            self.assertAlmostEqual(total,expected,places=7)
            self.assertEqual(c['convex_parts'],[p for r in c['material_regions'] for p in r['convex_parts']])
            for i,p in enumerate(c['convex_parts']):
                self.assertGreater(signed_area(np.asarray(p)),0)
                for q in c['convex_parts'][:i]:self.assertLess(clip_area(p,q)[0],1e-8)
        return out
    def test_original_preserves_projected_boundary(self):
        f=frame('hole');out=self.verify_partition(f);m=mapper(H)
        for source,mapped in zip(f['structures'][0]['regions'],out['structures'][0]['regions']):
            for raw,result in [(source['exterior'],mapped['exterior']),*zip(source['holes'],mapped['holes'])]:
                expected=m.map_points(np.asarray(raw)+f['structures'][0]['position'])
                actual=np.asarray(result)+out['structures'][0]['position']
                for point in expected:self.assertLess(np.linalg.norm(actual-point,axis=1).min(),1e-9)
    def test_near_exterior(self):self.verify_partition(from_mask(masks()['near_exterior']))
    def test_concave_hole(self):self.verify_partition(from_mask(masks()['concave_hole']))
    def test_multiple_holes(self):self.verify_partition(from_mask(masks()['multiple_holes']))
    def test_blue_hole(self):self.verify_partition(from_mask(masks()['blue_hole']))
    def test_materials(self):
        out=self.verify_partition(from_mask(masks()['mixed_materials']))
        self.assertEqual({r['material'] for c in out['structures'] for r in c['material_regions']},{'GREEN_SOLID','BLUE_BOUNCE','ORANGE_ONE_WAY'})
    def test_partial_crop_is_atomic(self):
        m=mapper(H);f=frame('hole');m.map_frame(f);old=deepcopy(m.ledger)
        f['structures'][0]['position'][0]-=200
        with self.assertRaises(ValueError):m.map_frame(f)
        self.assertEqual(m.ledger,old)
    def test_degenerate_is_not_repaired(self):
        f=frame('hole');f['structures'][0]['material_regions'][0]['convex_parts'][0]=[[0,0],[1,0],[2,0]]
        with self.assertRaises(ValueError):mapper(H).map_frame(f)
    def test_rotation_partition(self):
        f=frame('hole');f['structures'][0]['orientation_radians']=.17
        out=mapper(H).map_frame(f)
        self.assertTrue(all(c['orientation_radians']==0 for c in out['structures']))
    def test_affine_rotated_pose_only_versions(self):
        m=mapper();f=frame('hole');f['structures'][0]['orientation_radians']=.17;a=m.map_frame(f)
        f['structures'][0]['position'][0]+=1;b=m.map_frame(f)
        self.assertEqual(a['structures'][0]['convex_parts'],b['structures'][0]['convex_parts'])
        self.assertEqual(a['structures'][0]['geometry_version'],b['structures'][0]['geometry_version'])
    def test_reconstructed_reference_and_precision_cause(self):
        d=json.loads(Path('artifacts/perspective_hole/reproduction.json').read_text())
        self.assertLess(max(p['float64_overlap'] for p in d['part_hole_pairs']),1e-8)
        self.assertGreater(max(p['float32_exact_overlap'] for p in d['part_hole_pairs']),.0001)

if __name__=='__main__':unittest.main()

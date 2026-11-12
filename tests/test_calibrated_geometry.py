from copy import deepcopy
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import numpy as np
from vision.calibrated_geometry import CalibratedGeometryMapper,ImageLayout,MAPPING
from vision.calibrated_source import CalibratedMaterialSource
from vision.projection import ProjectionCalibration,transform,CENTERS,FIT_IDS,CHECK_IDS
from vision.material_replay import MaterialReplayExporter,labels
from vision.material_synthetic import bgr
from vision.structure_udp import Session,fragment,Reassembler

def calibration(matrix=None,capture=(640,480),mirror=False):
    h=np.asarray(matrix if matrix is not None else [[2,0,0],[0,1.2,40],[0,0,1]],float)
    target=np.array([CENTERS[i] for i in FIT_IDS],float);checks=np.array([CENTERS[i] for i in CHECK_IDS],float)
    c=ProjectionCalibration.fit(transform(np.linalg.inv(h),target),target,transform(np.linalg.inv(h),checks),checks,capture,mirror=mirror)
    c.matrix=h.copy();return c.validate()

def frame(kind='three'):
    e=MaterialReplayExporter()
    for _ in range(12):f=e.append_image(bgr(labels(kind,True)))
    return f

def mapper(matrix=None,**kwargs):return CalibratedGeometryMapper(calibration(matrix),ImageLayout((640,480),(640,480)),**kwargs)

class CalibrationGeometryTests(unittest.TestCase):
    def setUp(self):
        self.guard=patch('cv2.VideoCapture',side_effect=AssertionError('NO HARDWARE'));self.guard.start();self.addCleanup(self.guard.stop)
    def test_reference_points_and_half_pixels(self):
        m=mapper();p=np.array([[160,300],[460,330]],float)
        expected=transform(m.calibration.matrix,p-.5)+.5
        np.testing.assert_allclose(m.map_points(p),expected,atol=1e-10)
    def test_identity_preserves_cell_edges(self):
        c=calibration(np.eye(3),(1280,720));m=CalibratedGeometryMapper(c,ImageLayout((1280,720),(1280,720)))
        np.testing.assert_allclose(m.map_points([[200,200],[900,500]]),[[200,200],[900,500]])
    def test_axis_rotation_of_whole_geometry(self):
        c=calibration([[0,-1,1279],[1,0,0],[0,0,1]],(1280,1280))
        m=CalibratedGeometryMapper(c,ImageLayout((1280,1280),(1280,1280)))
        np.testing.assert_allclose(m.map_points([[160,300],[260,330]]),[[980,160],[950,260]],atol=1e-9)
    def test_crop_resize_aspect_and_offset(self):
        c=calibration(np.eye(3),(1280,720))
        m=CalibratedGeometryMapper(c,ImageLayout((1280,720),(640,480),(200,160,800,400)),arena_rect=(100,50,1000,500))
        p=np.array([[160,200],[400,300]],float);camera=p*[800/640,400/480]+[200,160]
        expected=camera*[1000/1280,500/720]+[100,50]
        np.testing.assert_allclose(m.map_points(p),expected,atol=1e-9)
    def test_simple_and_concave_holes_all_materials(self):
        for kind in ['solid','three','hole','corner']:
            f=frame(kind);out=mapper().map_frame(f)
            self.assertEqual([r['region_id'] for c in f['structures'] for r in c['material_regions']],[r['region_id'] for c in out['structures'] for r in c['material_regions']])
            for a,b in zip(f['structures'],out['structures']):
                self.assertEqual([len(r['holes']) for r in a['regions']],[len(r['holes']) for r in b['regions']])
                self.assertEqual(a['member_ids'],b['member_ids']);self.assertEqual(b['orientation_radians'],0)
    def test_all_vertices_transformed_including_orientation(self):
        f=frame('solid');f['structures'][0]['orientation_radians']=.15;m=mapper();out=m.map_frame(f)
        c=f['structures'][0];r=np.array([[np.cos(.15),-np.sin(.15)],[np.sin(.15),np.cos(.15)]])
        expected=m.map_points(np.asarray(c['regions'][0]['exterior'])@r.T+c['position'])
        actual=np.asarray(out['structures'][0]['regions'][0]['exterior'])+out['structures'][0]['position']
        np.testing.assert_allclose(actual,expected,atol=1e-9)
    def test_perspective_maps_convex_parts_without_hole_fill(self):
        m=mapper([[2,.03,0],[.01,1.3,30],[.0001,.00005,1]])
        f=frame('hole');out=m.map_frame(f)
        # Projection may refine T-junctions. Compare the represented area rather
        # than assuming an invariant number of convex pieces.
        from vision.structure_segmentation import signed_area
        c=out['structures'][0]
        area=sum(signed_area(np.asarray(p)) for p in c['convex_parts'])
        silhouette=sum(signed_area(np.asarray(r['exterior']))+sum(signed_area(np.asarray(h)) for h in r['holes']) for r in c['regions'])
        self.assertAlmostEqual(area,silhouette,places=7)
        inverse=np.linalg.inv(m.matrix)
        original=f['structures'][0]
        for part in c['convex_parts']:
            world=np.asarray(part)+c['position']
            source=transform(inverse,world)-original['position']
            np.testing.assert_allclose(m.map_points(source+original['position']),world,atol=1e-9)
            centroid=source.mean(axis=0)
            import cv2
            self.assertTrue(any(cv2.pointPolygonTest(np.array(r['exterior'],np.float32),tuple(centroid),False)>=0 and all(cv2.pointPolygonTest(np.array(h,np.float32),tuple(centroid),False)<0 for h in r['holes']) for r in original['regions']))
    def test_affine_pose_only_keeps_versions(self):
        m=mapper();f=frame('solid');a=m.map_frame(f)
        f['structures'][0]['position'][0]+=2;b=m.map_frame(f)
        self.assertEqual(a['structures'][0]['geometry_version'],b['structures'][0]['geometry_version'])
        self.assertEqual(a['structures'][0]['convex_parts'],b['structures'][0]['convex_parts'])
    def test_perspective_motion_advances_geometry_versions(self):
        m=mapper([[2,0,0],[0,1.2,40],[.0001,0,1]]);f=frame('solid');a=m.map_frame(f)
        f['structures'][0]['position'][0]+=2;b=m.map_frame(f)
        self.assertGreater(b['structures'][0]['geometry_version'],a['structures'][0]['geometry_version'])
    def test_reflection_reverses_winding_safely(self):
        c=calibration([[-2,0,1279],[0,1.2,40],[0,0,1]],mirror=True)
        m=CalibratedGeometryMapper(c,ImageLayout((640,480),(640,480)),mirror=True);out=m.map_frame(frame('hole'))
        from vision.structure_segmentation import signed_area
        for r in out['structures'][0]['regions']:
            self.assertGreater(signed_area(np.array(r['exterior'])),0)
            for h in r['holes']:self.assertLess(signed_area(np.array(h)),0)
    def test_double_mapping_rejected(self):
        m=mapper();a=m.map_frame(frame())
        with self.assertRaisesRegex(ValueError,'already'):m.map_frame(a)
    def test_outside_rejected_atomically(self):
        m=mapper();m.map_frame(frame());before=deepcopy(m.ledger);bad=frame();bad['structures'][0]['position']=[0,0]
        with self.assertRaises(ValueError):m.map_frame(bad)
        self.assertEqual(before,m.ledger)
    def test_persistence_and_incompatibility(self):
        c=calibration()
        with tempfile.TemporaryDirectory(dir='artifacts/preparation') as d:
            path=Path(d)/'test.json';c.save(path);raw=path.read_bytes();loaded=ProjectionCalibration.load(path)
            CalibratedGeometryMapper(loaded,ImageLayout((640,480),(640,480)))
            for layout in [ImageLayout((1280,720),(640,480)),ImageLayout((640,480),(640,480),(-1,0,640,480))]:
                with self.assertRaises(ValueError):CalibratedGeometryMapper(loaded,layout)
            self.assertEqual(raw,path.read_bytes())
    def test_invalid_homography_rejected(self):
        c=calibration();c.matrix[:]=0
        with self.assertRaises(ValueError):CalibratedGeometryMapper(c,ImageLayout((640,480),(640,480)))
    def test_camera_failure_is_not_empty(self):
        source=CalibratedMaterialSource(mapper())
        for _ in range(12):active=source.update(bgr(labels('three',True)))
        self.assertEqual(active['scene_state'],'SCENE_ACTIVE')
        for health in ['DISCONNECTED','ERROR','STALE']:
            out=source.update(health=health);self.assertNotEqual(out['scene_state'],'SCENE_EMPTY');self.assertEqual(out['structures'],active['structures'])
        self.assertEqual(source.update(np.empty((0,0,3),np.uint8))['scene_state'],'SCENE_ERROR')
    def test_missing_calibration_and_resolution_errors(self):
        source=CalibratedMaterialSource();error=source.update(bgr(labels()))
        self.assertEqual(error['scene_state'],'SCENE_ERROR')
        self.assertFalse(source.message(Session(),error)['empty_confirmed'])
        self.assertEqual(CalibratedMaterialSource(mapper()).update(np.zeros((720,1280,3),np.uint8))['scene_state'],'SCENE_ERROR')
    def test_existing_hsv_profile_can_be_injected(self):
        from vision.material_config import MaterialConfig
        config=MaterialConfig();config.colors[0].lower=[70,90,55]
        source=CalibratedMaterialSource(mapper(),config=config)
        self.assertIs(source.exporter.pipeline.config,config)
        for _ in range(14):last=source.update(bgr(labels()))
        self.assertEqual(last['scene_state'],'SCENE_EMPTY')
    def test_overlapping_hsv_is_not_confirmed_empty(self):
        from vision.material_config import MaterialConfig
        config=MaterialConfig()
        source=CalibratedMaterialSource(mapper(),config=config)
        for _ in range(12):old=source.update(bgr(labels('bounce')))
        self.assertEqual(old['scene_state'],'SCENE_ACTIVE')
        config.colors[0].upper=[135,255,255]
        for _ in range(14):last=source.update(bgr(labels('bounce')))
        self.assertEqual(last['scene_state'],'SCENE_STALE')
        self.assertFalse(last['empty_confirmed'])
        self.assertEqual(last['diagnostic']['reason'],'ambiguous_color_classification')
        self.assertEqual(last['structures'],old['structures'])
    def test_empty_confirmation_and_recovery(self):
        source=CalibratedMaterialSource(mapper());image=bgr(labels('three',True))
        for _ in range(12):source.update(image)
        self.assertNotEqual(source.update(np.zeros_like(image))['scene_state'],'SCENE_EMPTY')
        for _ in range(14):empty=source.update(np.zeros_like(image))
        self.assertEqual(empty['scene_state'],'SCENE_EMPTY');self.assertTrue(empty['empty_confirmed'])
        for _ in range(12):recovery=source.update(image)
        self.assertEqual(recovery['scene_state'],'SCENE_ACTIVE')
    def test_segmentation_error_preserves_last(self):
        source=CalibratedMaterialSource(mapper());image=bgr(labels())
        for _ in range(12):old=source.update(image)
        with patch.object(source.exporter.pipeline.segmenter,'segment',side_effect=ValueError('bad segmentation')):new=source.update(image)
        self.assertEqual(new['scene_state'],'SCENE_ERROR');self.assertEqual(new['structures'],old['structures'])
    def test_opencv_mapping_error_preserves_last(self):
        import cv2
        source=CalibratedMaterialSource(mapper());image=bgr(labels())
        for _ in range(12):old=source.update(image)
        with patch.object(source.mapper,'map_frame',side_effect=cv2.error('mapping error')):new=source.update(image)
        self.assertEqual(new['scene_state'],'SCENE_ERROR');self.assertEqual(new['structures'],old['structures'])
    def test_protocol_compatible_error_stale_and_restart(self):
        source=CalibratedMaterialSource(mapper());image=bgr(labels());s=Session()
        for _ in range(12):f=source.update(image)
        message=source.message(s,f);r=Reassembler();last=None
        for p in fragment(message):last=r.feed(p)
        self.assertEqual(last['spatial_mapping'],f['spatial_mapping'])
        self.assertIsNone(source.message(s,source.update(health='STALE')))
        self.assertEqual(source.message(s,source.update(health='DISCONNECTED'))['scene_state'],'SCENE_ERROR')
        newer=Session(started_ms=s.started_ms+1)
        self.assertNotEqual(source.message(newer,f)['session_id'],message['session_id'])
    def test_merge_split_identities_and_materials_preserved(self):
        from vision.material_synthetic import scenarios
        from vision.material_structures import MaterialStructures
        # Use 1280x720 identity calibration and put images wholly inside fit hull.
        c=calibration(np.eye(3),(1280,720));m=CalibratedGeometryMapper(c,ImageLayout((1280,720),(1280,720)))
        e=MaterialReplayExporter();events=[]
        for name,images,_ in scenarios():
            if name!='11_split':continue
            for image in images:
                canvas=np.zeros((720,1280,3),np.uint8);canvas[180:420,300:620]=image
                raw=e.append_image(canvas)
                if raw['diagnostic']['status']!='TRACKING':continue
                mapped=m.map_frame(raw);self.assertEqual(mapped['events'],raw['events']);self.assertEqual(mapped['identity_epochs'],raw['identity_epochs']);events.extend(mapped['events'])
        self.assertTrue({'MERGE','SPLIT'}<={e['type'] for e in events})

if __name__=='__main__':unittest.main()

import copy
import json
from pathlib import Path
import socket
import tempfile
import time
import unittest
import cv2
import numpy as np
from vision.config import CameraConfig, NetworkConfig
from vision.projection import ProjectionCalibration, CENTERS, FIT_IDS, CHECK_IDS, transform
from vision.projection_pattern import pattern,detect_references
from vision.projector_calibration import CalibrationSession
from vision.transport import UdpSender


def fixture(matrix=None,capture_size=(1280,720),mirror=False):
    matrix = np.eye(3) if matrix is None else np.asarray(matrix,dtype=np.float64)
    targets = np.array([CENTERS[i] for i in FIT_IDS],dtype=np.float64)
    checks = np.array([CENTERS[i] for i in CHECK_IDS],dtype=np.float64)
    source = transform(np.linalg.inv(matrix),targets)
    check_source = transform(np.linalg.inv(matrix),checks)
    return ProjectionCalibration.fit(source,targets,check_source,checks,capture_size,mirror=mirror)


class ProjectionTests(unittest.TestCase):
    def test_identity(self):
        c=fixture()
        self.assertTrue(np.allclose(c.matrix,np.eye(3),atol=1e-7))
        self.assertAlmostEqual(c.map_pose(640/1279,360/719,30)[2],30,places=5)

    def test_translation(self):
        c=fixture([[1,0,20],[0,1,10],[0,0,1]])
        x,y,_=c.map_pose(620/1279,350/719,0)
        self.assertAlmostEqual(x,640/1279)
        self.assertAlmostEqual(y,360/719)

    def test_scale(self):
        c=fixture([[2,0,0],[0,1.5,0],[0,0,1]],(640,480))
        x,y,_=c.map_pose(320/639,240/479,0)
        self.assertAlmostEqual(x,640/1279)
        self.assertAlmostEqual(y,360/719)

    def test_perspective_and_orientation(self):
        h=np.array([[1.1,.05,20],[.02,1.05,10],[.00008,.00004,1]],dtype=float)
        c=fixture(h)
        center=transform(np.linalg.inv(h),[[640,360]])[0]
        x,y,angle=c.map_pose(center[0]/1279,center[1]/719,35)
        self.assertAlmostEqual(x,640/1279,places=6)
        self.assertAlmostEqual(y,360/719,places=6)
        p=transform(h,[center,center+np.array([np.cos(np.deg2rad(35)),np.sin(np.deg2rad(35))])])
        expected=np.degrees(np.arctan2(*(p[1]-p[0])[::-1]))
        self.assertAlmostEqual(angle,expected,places=5)
        self.assertGreater(abs(angle-35),.1)

    def test_axis_rotation(self):
        c=fixture([[0,-1,1279],[1,0,0],[0,0,1]],(1280,1280))
        self.assertAlmostEqual(c.map_pose(360/1279,639/1279,0)[2],90,places=5)

    def test_outside_calibrated_area_invisible_not_camera_fallback(self):
        c=fixture()
        with self.assertRaises(ValueError): c.map_pose(0,0,0)
        modules,rejected=c.map_modules([{"id":1,"x":0,"y":0,"angle":30,"visible":True}])
        self.assertFalse(modules[0]["visible"])
        self.assertEqual(modules[0]["x"],0)
        self.assertEqual(rejected[0]["id"],1)

    def test_wrong_holdout_rejected(self):
        c=fixture()
        c.check_projection[0]+=[30,20]
        with self.assertRaisesRegex(ValueError,"Reprojection"): c.validate()

    def test_wrong_fit_correspondence_rejected_by_independent_checks(self):
        c=fixture()
        source=c.fit_camera.copy()
        source[0]+=[40,30]
        with self.assertRaises(ValueError):
            ProjectionCalibration.fit(source,c.fit_projection,c.check_camera,c.check_projection,c.capture_size)

    def test_degenerate_and_collinear(self):
        c=fixture()
        for matrix in (np.zeros((3,3)),np.diag([0,1,1]),np.full((3,3),np.nan)):
            c.matrix=matrix
            with self.assertRaises(ValueError): c.validate()
        with self.assertRaises(ValueError):
            ProjectionCalibration.fit([[100,100],[200,100],[300,100],[400,100]],
                [[180,140],[1100,140],[1100,580],[180,580]],[[200,200],[400,200],[400,400],[200,400]],
                [[400,200],[800,200],[800,400],[400,400]],(1280,720))

    def test_reflection_axes_rejected(self):
        with self.assertRaisesRegex(ValueError,"axes"):
            fixture([[-1,0,1279],[0,1,0],[0,0,1]])

    def test_explicit_mirrored_capture_corrects_orientation(self):
        c=fixture([[-1,0,1279],[0,1,0],[0,0,1]],mirror=True)
        x,y,angle=c.map_pose(639/1279,360/719,0)
        self.assertAlmostEqual(x,640/1279)
        self.assertAlmostEqual(abs(angle),180)

    def test_resolution_camera_or_mirror_change_rejected(self):
        c=fixture()
        c.compatible((1280,720),False,0,"dshow")
        for size,mirror,index,backend,projection in (((640,480),False,0,"dshow",(1280,720)),
                ((1280,720),True,0,"dshow",(1280,720)),((1280,720),False,2,"dshow",(1280,720)),
                ((1280,720),False,0,"msmf",(1280,720)),((1280,720),False,0,"dshow",(1920,1080))):
            with self.assertRaises(ValueError): c.compatible(size,mirror,index,backend,projection)

    def test_save_load_revalidates_matrix_and_errors(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
            path=Path(d)/"projection.json"
            c=fixture(); c.save(path)
            loaded=ProjectionCalibration.load(path)
            self.assertTrue(np.allclose(c.matrix,loaded.matrix))
            data=json.loads(path.read_text()); data["homography"][0][2]=100
            data["errors"]={"check_max_px":0}
            path.write_text(json.dumps(data))
            with self.assertRaises(ValueError): ProjectionCalibration.load(path)

    def test_invalid_save_and_cancel_preserve_previous_file(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as d:
            path=Path(d)/"projection.json"
            c=fixture(); c.save(path); before=path.read_bytes()
            session=CalibrationSession(CameraConfig(width=1280,height=720),path)
            session.candidate=c
            session.repeat()
            with self.assertRaises(ValueError): session.confirm()
            self.assertEqual(path.read_bytes(),before)
            c.matrix[0,0]=0
            with self.assertRaises(ValueError): c.save(path)
            self.assertEqual(path.read_bytes(),before)

    def test_automatic_markers_and_manual_correspondences(self):
        image=pattern()
        refs,info=detect_references(image)
        self.assertEqual(set(refs),set(CENTERS))
        self.assertFalse(info["duplicates"])
        session=CalibrationSession(CameraConfig(width=1280,height=720),Path("not_saved.json"))
        result=session.build(refs,(1280,720))
        self.assertLess(result.errors["check_max_px"],1)
        session.repeat(); session.manual=True; session.frame_size=(1280,720)
        for i in FIT_IDS+CHECK_IDS:
            session.click(cv2.EVENT_LBUTTONDOWN,*CENTERS[i],0,None)
        self.assertIsNotNone(session.candidate)

    def test_perspective_warp_marker_detection(self):
        source=np.float32([[0,0],[1279,0],[1279,719],[0,719]])
        destination=np.float32([[80,50],[1190,30],[1220,680],[30,650]])
        h=cv2.getPerspectiveTransform(source,destination)
        image=cv2.warpPerspective(pattern(),h,(1280,720),borderValue=(255,255,255))
        refs,info=detect_references(image)
        self.assertEqual(set(refs),set(CENTERS))
        c=CalibrationSession(CameraConfig(width=1280,height=720),Path("not_saved.json")).build(refs,(1280,720))
        self.assertLess(c.errors["check_max_px"],2)

    def test_duplicate_markers_ambiguous(self):
        image=pattern()
        image[300:397,40:137]=image[92:189,132:229]
        refs,info=detect_references(image)
        self.assertIn(10,info["duplicates"])
        self.assertNotIn(10,refs)

    def test_checks_not_used_to_fit(self):
        c=fixture()
        source=c.check_camera.copy(); source[0]+=[.5,0]
        result=ProjectionCalibration.fit(c.fit_camera,c.fit_projection,source,c.check_projection,c.capture_size)
        self.assertTrue(np.allclose(result.matrix,c.matrix))
        self.assertGreater(result.errors["check_max_px"],.4)

    def test_real_udp_v2_explicit_projection_units(self):
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as receiver:
            receiver.bind(("127.0.0.1",0)); receiver.settimeout(1)
            sender=UdpSender(NetworkConfig(port=receiver.getsockname()[1]),"PROJECTOR")
            try:
                modules,_=fixture().map_modules([{"id":1,"x":640/1279,"y":360/719,"angle":25,"visible":True}])
                sender.send(modules,time.monotonic())
                packet=json.loads(receiver.recv(4096))
                self.assertEqual(packet["version"],2)
                self.assertEqual(packet["coordinate_space"],"PROJECTOR")
                self.assertEqual(packet["projection_size"],[1280,720])
                self.assertEqual(packet["orientation_space"],"PROJECTOR_PIXELS")
                self.assertAlmostEqual(packet["modules"][0]["x"]*1279,640)
            finally: sender.close()


if __name__=="__main__":
    unittest.main(verbosity=2)

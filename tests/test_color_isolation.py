import copy
import json
import socket
import unittest

import cv2
import numpy as np
from vision.calibration import sample_hsv
from vision.config import Config, NetworkConfig
from vision.detection import ColorDetector, Observation
from vision.synthetic import draw_piece, make_frame
from vision.tracking import Tracker
from vision.transport import UdpSender


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.config = Config()
        self.detector = ColorDetector(self.config)

    def test_visibility_combinations(self):
        for visible in ([],[1],[2],[1,2]):
            with self.subTest(visible=visible):
                batch = self.detector.detect(make_frame(0,visible_ids=visible))
                self.assertEqual([i for i,v in batch.candidates.items() if v],visible)

    def test_each_color_isolated_noise(self):
        for bgr in ((0,255,0),(255,0,0)):
            image = np.zeros((480,640,3),np.uint8)
            rng = np.random.default_rng(20)
            for x,y in rng.integers((0,0),(640,480),size=(600,2)):
                image[y,x] = bgr
            self.assertFalse(any(self.detector.detect(image).candidates.values()))

    def test_brightness_and_saturation(self):
        for hue,module in ((60,1),(120,2)):
            for saturation,value,expected in ((255,255,True),(150,130,True),(25,255,False),(200,30,False)):
                image = np.zeros((480,640,3),np.uint8)
                bgr = cv2.cvtColor(np.uint8([[[hue,saturation,value]]]),cv2.COLOR_HSV2BGR)[0,0].tolist()
                draw_piece(image,(250,220),(130,40),10,bgr)
                batch = self.detector.detect(image)
                self.assertEqual(bool(batch.candidates[module]),expected)
                self.assertFalse(batch.candidates[3-module])

    def test_reflection_white_hole_not_cross_id(self):
        image = make_frame(0,visible_ids=[1])
        cv2.rectangle(image,(175,300),(195,320),(255,255,255),-1)
        self.assertTrue(self.detector.detect(image).candidates[1])
        self.assertFalse(self.detector.detect(image).candidates[2])

    def test_partial_occlusion(self):
        image = make_frame(0,visible_ids=[1])
        cv2.rectangle(image,(170,0),(190,479),(0,0,0),-1)
        batch = self.detector.detect(image)
        self.assertFalse(batch.candidates[2])
        # Multiple comparable fragments are conservatively ambiguous.
        self.assertTrue(all(r.reason != "accepted" or r.module_id == 1 for r in batch.reviews))

    def test_overlap_rejects_both_instead_of_duplicate(self):
        self.config.colors[1].lower = self.config.colors[0].lower[:]
        self.config.colors[1].upper = self.config.colors[0].upper[:]
        batch = self.detector.detect(make_frame(0,visible_ids=[1]))
        self.assertGreater(batch.overlap_pixels,0)
        self.assertFalse(any(batch.candidates.values()))
        self.assertEqual({r.reason for r in batch.reviews},{"overlapping_masks"})

    def test_region_confidence_rejects_sparse_hollow_shape(self):
        image = np.zeros((480,640,3),np.uint8)
        cv2.rectangle(image,(180,160),(350,260),(0,255,0),5)
        batch = self.detector.detect(image)
        self.assertFalse(batch.candidates[1])
        self.assertIn("confidence",[r.reason for r in batch.reviews])

    def test_dimensions_and_max_area(self):
        for kind in ("size","dimension"):
            image = np.zeros((480,640,3),np.uint8)
            draw_piece(image,(250,220),(160,30),0,(0,255,0))
            if kind == "size":
                self.config.colors[0].max_area_fraction = .01
            else:
                self.config.colors[0].min_dimension = 40
                self.config.colors[0].max_area_fraction = .35
            self.assertFalse(self.detector.detect(image).candidates[1])

    def test_two_comparable_same_color_candidates_rejected(self):
        image = np.zeros((480,640,3),np.uint8)
        for x in (150,450):
            draw_piece(image,(x,220),(100,30),0,(0,255,0))
        batch = self.detector.detect(image)
        self.assertFalse(batch.candidates[1])
        self.assertEqual({r.reason for r in batch.reviews},{"ambiguous_same_color"})

    def test_tracker_rejects_wrong_observation_id_and_unknown_id(self):
        tracker = Tracker(self.config.tracking,[1,2])
        for i in range(10):
            tracker.update({2:[Observation(1,.5,.5,0,3000)],99:[Observation(99,.2,.2,0,3000)]},i/30)
        self.assertEqual(tracker.modules(.3),[])

    def test_single_frame_false_blue_never_emitted(self):
        tracker = Tracker(self.config.tracking,[1,2])
        for i in range(20):
            batch = self.detector.detect(make_frame(i/30,visible_ids=[1,2] if i==5 else [1]))
            tracker.update(batch.candidates,i/30)
            self.assertNotIn(2,[m["id"] for m in tracker.modules(i/30)])

    def test_loss_and_recovery_no_cross_assignment(self):
        tracker = Tracker(self.config.tracking,[1,2])
        for i in range(9):
            tracker.update(self.detector.detect(make_frame(0)).candidates,i/30)
        old = tracker.modules(.27)[1].copy()
        for i in range(9,24):
            tracker.update(self.detector.detect(make_frame(i/30,visible_ids=[1])).candidates,i/30)
        lost = tracker.modules(.8)[1]
        self.assertFalse(lost["visible"])
        self.assertEqual((old["x"],old["y"]),(lost["x"],lost["y"]))
        for i in range(24,27):
            tracker.update(self.detector.detect(make_frame(.0)).candidates,i/30)
        self.assertTrue(tracker.modules(26/30)[1]["visible"])

    def test_roi_suggests_but_does_not_mutate(self):
        image = make_frame(0,visible_ids=[1])
        original = copy.deepcopy(self.config)
        sample = sample_hsv(image,(185,310),(195,315))
        self.assertEqual(sample["median_hsv"][0],60)
        self.assertEqual(self.config,original)

    def test_green_only_wire_has_no_blue_transforms(self):
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as receiver:
            receiver.bind(("127.0.0.1",0)); receiver.settimeout(1)
            sender = UdpSender(NetworkConfig(port=receiver.getsockname()[1]))
            tracker = Tracker(self.config.tracking,[1,2])
            try:
                seen_green = False
                for i in range(60):
                    tracker.update(self.detector.detect(make_frame(i/30,visible_ids=[1])).candidates,i/30)
                    self.assertTrue(sender.send(tracker.modules(i/30),i/30,force=True))
                    packet = json.loads(receiver.recv(4096))
                    self.assertNotIn(2,[m["id"] for m in packet["modules"]])
                    seen_green |= any(m["id"]==1 and m["visible"] for m in packet["modules"])
                self.assertTrue(seen_green)
            finally:
                sender.close()

    def test_moving_green_keeps_static_blue_pose(self):
        tracker = Tracker(self.config.tracking,[1,2])
        baseline = None
        for i in range(40):
            image = np.zeros((480,640,3),np.uint8)
            draw_piece(image,(160+i*2,230),(110,30),0,(0,255,0))
            draw_piece(image,(480,280),(110,30),0,(255,0,0))
            tracker.update(self.detector.detect(image).candidates,i/30)
            poses = tracker.modules(i/30)
            if poses:
                blue = next(m for m in poses if m["id"]==2)
                if baseline is None: baseline = blue.copy()
                self.assertEqual(blue,baseline)


if __name__ == "__main__":
    unittest.main(verbosity=2)

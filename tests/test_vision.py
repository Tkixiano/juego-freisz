import json
from pathlib import Path
import socket
import tempfile
import time
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from vision.camera import CameraSource
from vision.config import Config, NetworkConfig, TrackingConfig, load, save, validate
from vision.detection import ColorDetector, Observation
from vision.gui import Diagnostics
from vision.synthetic import draw_piece, make_frame
from vision.tracking import Tracker, angle_delta
from vision.transport import UdpSender


class DetectionTests(unittest.TestCase):
    def setUp(self):
        self.config = Config()
        self.detector = ColorDetector(self.config)

    def test_green_blue_centers_and_different_shapes(self):
        image = np.zeros((480, 640, 3), np.uint8)
        draw_piece(image, (160, 200), (140, 35), 25, (0, 230, 0))
        draw_piece(image, (450, 280), (130, 42), -20, (255, 0, 0), True)
        result = self.detector.detect(image)
        self.assertEqual([len(result.candidates[i]) for i in (1, 2)], [1, 1])
        green, blue = result.candidates[1][0], result.candidates[2][0]
        self.assertAlmostEqual(green.x, 160/639, delta=.004)
        self.assertAlmostEqual(green.y, 200/479, delta=.004)
        self.assertAlmostEqual(blue.x, 450/639, delta=.004)
        self.assertAlmostEqual(blue.y, 280/479, delta=.015)
        self.assertAlmostEqual(angle_delta(green.angle, 25), 0, delta=2)
        self.assertAlmostEqual(angle_delta(blue.angle, -20), 0, delta=2)
        self.assertEqual(set(np.unique(result.masks[1])), {0, 255})

    def test_rotations_across_rectangle_angle_conventions(self):
        for angle in (-89, -70, -20, 0, 20, 70, 89):
            with self.subTest(angle=angle):
                image = np.zeros((480, 640, 3), np.uint8)
                draw_piece(image, (300, 240), (140, 35), angle, (0, 255, 0))
                measured = self.detector.detect(image).candidates[1][0].angle
                self.assertAlmostEqual(angle_delta(measured, angle), 0, delta=1.5)

    def test_empty_wrong_color_and_noise(self):
        image = np.zeros((480, 640, 3), np.uint8)
        draw_piece(image, (200, 200), (100, 30), 0, (0, 0, 255))
        rng = np.random.default_rng(42)
        for x, y in rng.integers((0, 0), (640, 480), size=(200, 2)):
            image[y, x] = (0, 255, 0)
        result = self.detector.detect(image)
        self.assertFalse(result.candidates[1])
        self.assertFalse(result.candidates[2])

    def test_huge_same_color_background_rejected(self):
        result = self.detector.detect(np.full((480, 640, 3), (0, 200, 0), np.uint8))
        self.assertFalse(result.candidates[1])

    def test_square_orientation_flag(self):
        image = np.zeros((480, 640, 3), np.uint8)
        draw_piece(image, (200, 200), (60, 60), 25, (0, 255, 0))
        self.assertFalse(self.detector.detect(image).candidates[1][0].orientation_reliable)

    def test_hsv_calibration_changes_detection(self):
        image = make_frame(0)
        self.config.colors[0].lower = [10, 200, 200]
        self.config.colors[0].upper = [20, 255, 255]
        self.assertFalse(self.detector.detect(image).candidates[1])

    def test_hue_wrap(self):
        self.config.colors[0].lower = [170, 70, 60]
        self.config.colors[0].upper = [10, 255, 255]
        image = np.zeros((480, 640, 3), np.uint8)
        draw_piece(image, (200, 200), (100, 30), 10, (0, 0, 255))
        self.assertEqual(len(self.detector.detect(image).candidates[1]), 1)

    def test_invalid_image(self):
        with self.assertRaises(ValueError):
            self.detector.detect(np.zeros((5, 5), np.uint8))


class TrackingTests(unittest.TestCase):
    def test_continuous_valid_rotation_does_not_freeze_from_filter_lag(self):
        tracker=Tracker(TrackingConfig(confirmation_frames=1),[1])
        tracker.update({1:[self.observation(angle=0)]},0)
        for i in range(1,9):
            tracker.update({1:[self.observation(angle=i*10)]},i/30)
        self.assertGreater(tracker.modules(8/30)[0]["angle"],50)

    def test_orientation_reacquires_after_large_rotation_while_lost(self):
        tracker=self.ready()
        for i in range(3):
            tracker.update({1:[self.observation(angle=80)]},.5+i/30)
        self.assertTrue(tracker.modules(.57)[0]["visible"])
        self.assertGreater(tracker.modules(.57)[0]["angle"],30)

    @staticmethod
    def observation(x=.3, angle=0, area=2000, reliable=True):
        return Observation(1, x, .5, angle, area, orientation_reliable=reliable)

    def ready(self):
        tracker = Tracker(TrackingConfig(), [1, 2])
        for i in range(3):
            tracker.update({1: [self.observation()]}, i/30)
        return tracker

    def test_no_position_before_confirmation(self):
        tracker = Tracker(TrackingConfig(), [1, 2])
        self.assertEqual(tracker.modules(0), [])
        tracker.update({1: [self.observation()]}, 0)
        tracker.update({1: [self.observation()]}, .03)
        self.assertEqual(tracker.modules(.03), [])
        tracker.update({1: [self.observation()]}, .06)
        self.assertEqual(tracker.modules(.06)[0]["id"], 1)

    def test_hold_no_extrapolation_and_loss(self):
        tracker = self.ready()
        initial = tracker.modules(.07)[0]
        tracker.update({}, .1)
        held = tracker.modules(.15)[0]
        self.assertTrue(held["visible"])
        self.assertEqual((initial["x"], initial["y"]), (held["x"], held["y"]))
        self.assertFalse(tracker.modules(.3)[0]["visible"])
        self.assertFalse(tracker.modules(.07, force_invisible=True)[0]["visible"])

    def test_reject_far_false_detection_without_refreshing_visibility(self):
        tracker = self.ready()
        tracker.update({1: [self.observation(.9)]}, .1)
        self.assertEqual(tracker.modules(.1)[0]["x"], .3)
        self.assertFalse(tracker.modules(.3)[0]["visible"])

    def test_nearest_same_color_not_largest_distractor(self):
        tracker = self.ready()
        tracker.update({1: [self.observation(.8, area=9000), self.observation(.32)]}, .1)
        self.assertTrue(.3 < tracker.modules(.1)[0]["x"] < .32)

    def test_smoothing_and_fast_valid_motion(self):
        tracker = self.ready()
        for i in range(1, 8):
            tracker.update({1: [self.observation(.3+i*.035)]}, (i+2)/30)
        self.assertTrue(tracker.modules(.3)[0]["visible"])
        self.assertGreater(tracker.modules(.3)[0]["x"], .45)
        self.assertLess(tracker.modules(.3)[0]["x"], .545)

    def test_reacquire_requires_consistent_frames(self):
        tracker = self.ready()
        tracker.update({1: [self.observation(.8)]}, .5)
        tracker.update({1: [self.observation(.8)]}, .53)
        self.assertFalse(tracker.modules(.53)[0]["visible"])
        tracker.update({1: [self.observation(.8)]}, .56)
        self.assertTrue(tracker.modules(.56)[0]["visible"])
        self.assertLess(tracker.modules(.56)[0]["x"], .8)

    def test_axis_wrap_square_and_angular_outlier(self):
        tracker = Tracker(TrackingConfig(confirmation_frames=1), [1])
        tracker.update({1: [self.observation(angle=88)]}, 0)
        tracker.update({1: [self.observation(angle=-88)]}, .033)
        angle = tracker.modules(.033)[0]["angle"]
        self.assertTrue(88 < angle < 92)
        tracker.update({1: [self.observation(angle=0)]}, .066)
        self.assertAlmostEqual(tracker.modules(.066)[0]["angle"], angle)
        tracker.update({1: [self.observation(angle=20, reliable=False)]}, .099)
        self.assertAlmostEqual(tracker.modules(.099)[0]["angle"], angle)


class ConfigAndTransportTests(unittest.TestCase):
    def test_send_clock_does_not_halve_rate_with_frame_jitter(self):
        with patch("vision.transport.socket.socket"):
            sender = UdpSender(NetworkConfig())
            for i in range(300):
                sender.send([], 10+i/30+(.001 if i%2==0 else -.001))
            self.assertGreaterEqual(sender.sent, 295)
            self.assertLessEqual(sender.sent, 300)
            sender.close()

    def test_json_round_trip_and_reject_invalid(self):
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as directory:
            self.assertTrue(Path(directory).resolve().is_relative_to(Path(__file__).resolve().parent))
            path = Path(directory)/"settings.json"
            save(Config(), path)
            self.assertEqual(load(path), Config())
            for mutate in (lambda c: setattr(c.camera, "index", -1),
                           lambda c: setattr(c.camera, "width", 640.0),
                           lambda c: setattr(c.network, "host", "example.com"),
                           lambda c: c.colors[0].lower.__setitem__(0, 180),
                           lambda c: setattr(c.tracking, "loss_tolerance", float("nan")),
                           lambda c: setattr(c.colors[1], "id", 1)):
                with self.subTest(mutate=mutate):
                    config = Config()
                    mutate(config)
                    with self.assertRaises(ValueError):
                        validate(config)

    def test_real_udp_wire_format_frequency_and_stop(self):
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as receiver:
            receiver.bind(("127.0.0.1", 0))
            receiver.settimeout(1)
            sender = UdpSender(NetworkConfig(port=receiver.getsockname()[1]))
            tracker = TrackingTests().ready()
            try:
                self.assertTrue(sender.send(tracker.modules(.07), 1))
                packet = receiver.recv(4096)
                data = json.loads(packet.decode("utf-8"))
                self.assertTrue({"version", "sequence", "modules", "sent_unix_ms"}.issubset(data))
                self.assertEqual(set(data["modules"][0]), {"id", "x", "y", "angle", "visible"})
                self.assertLess(len(packet), 4096)
                self.assertEqual(data["version"], 1)
                self.assertFalse(sender.send([], 1.001))
                self.assertTrue(sender.send(tracker.modules(.07, True), 1.04))
                stop = json.loads(receiver.recv(4096))
                self.assertGreater(stop["sequence"], data["sequence"])
                self.assertFalse(stop["modules"][0]["visible"])
            finally:
                sender.close()


class CameraTests(unittest.TestCase):
    def source(self, mode):
        import multiprocessing as mp
        from tests.camera_fakes import CameraFactory
        released = mp.get_context("spawn").RawValue("i",0)
        settings = Config().camera
        settings.startup_timeout = 4
        settings.stall_timeout = .5
        source = CameraSource(settings, CameraFactory(mode,released))
        source.start()
        self.addCleanup(source.close)
        return source, released

    def wait_for(self, predicate, timeout=5):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            value=predicate()
            if value:
                return value
            time.sleep(.01)
        self.fail("Camera condition timed out")

    def test_open_read_disconnect_and_release_with_fake_device(self):
        source,released=self.source("disconnect")
        self.assertIsNotNone(self.wait_for(source.get))
        self.wait_for(lambda: source.get() is None)
        self.assertTrue(source.close())
        self.assertEqual(released.value,1)

    def test_unopened_device_released(self):
        source,released=self.source("unopened")
        self.wait_for(lambda: (source.get(), "cannot open" in source.state)[1])
        self.assertTrue(source.close())
        self.assertEqual(released.value,1)

    def test_stale_frame_is_not_returned(self):
        source,_released=self.source("hang_read")
        frame=self.wait_for(source.get)
        frame.timestamp=time.monotonic()-2
        self.assertIsNone(source.get())
        self.assertIn("frame timeout",source.state)
        self.assertTrue(source.close())

    def test_hung_open_has_bounded_close(self):
        source,_released=self.source("hang_open")
        self.wait_for(lambda: (source.get(), "CAMERA 0 opening" in source.state)[1])
        started=time.monotonic()
        self.assertTrue(source.close())
        self.assertLess(time.monotonic()-started,2)
        self.assertGreater(source.forced_stops,0)
        self.assertFalse(source.diagnostics()["child_alive"])

    def test_hung_read_restarts_and_closes(self):
        source,_released=self.source("hang_read")
        self.wait_for(source.get)
        self.wait_for(lambda: (source.get(), source.restarts>0)[1])
        self.assertGreater(source.forced_stops,0)
        self.assertTrue(source.close())


if __name__ == "__main__":
    unittest.main(verbosity=2)

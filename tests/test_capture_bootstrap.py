import time
import unittest
from unittest.mock import patch
from vision.camera import CameraSource
from vision.config import Config
from tests.capture_bootstrap_fakes import no_progress,delayed_boot

class BootstrapTests(unittest.TestCase):
    def poll_until(self,source,predicate,timeout):
        until=time.monotonic()+timeout
        while time.monotonic()<until:
            source.get()
            if predicate():return
            time.sleep(.01)
        self.fail(str(source.diagnostics()))
    def test_bootstrap_does_not_consume_native_open_deadline(self):
        config=Config().camera;config.bootstrap_timeout=15;config.startup_timeout=1
        with patch('vision.camera.capture_worker',delayed_boot):
            source=CameraSource(config);source.start();self.addCleanup(source.close)
            self.poll_until(source,lambda:source.worker_phase==2,15.5)
            self.assertEqual(source.restarts,0)
            self.poll_until(source,lambda:source.restarts==1,3)
            self.assertEqual(source.last_timeout_phase,'OPEN')
            start=time.monotonic();self.assertTrue(source.close());self.assertLess(time.monotonic()-start,2)
    def test_no_bootstrap_progress_remains_bounded(self):
        config=Config().camera;config.bootstrap_timeout=1;config.startup_timeout=8
        with patch('vision.camera.capture_worker',no_progress):
            source=CameraSource(config);source.start();self.addCleanup(source.close)
            self.poll_until(source,lambda:source.restarts==1,4)
            self.assertEqual(source.last_timeout_phase,'BOOTSTRAP')
            self.assertGreater(source.forced_stops,0);self.assertTrue(source.close())

if __name__=='__main__':unittest.main()

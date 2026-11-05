"""Synthetic-only export tests. Capture and sockets are forbidden, not mocked data sources."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from vision.offline_replay import ReplayExporter, export_scenarios, image, geometry_key


class OfflineExportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.guards=[patch('cv2.VideoCapture',side_effect=AssertionError('NO CAPTURE')),
                    patch('socket.socket',side_effect=AssertionError('NO NETWORK'))]
        for guard in cls.guards:guard.start()
        cls.temp=tempfile.TemporaryDirectory(dir='tmp',prefix='offline_export_')
        cls.path=Path(cls.temp.name)
        cls.manifest=export_scenarios(cls.path,120)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()
        for guard in reversed(cls.guards):guard.stop()

    def load(self,name):return json.loads((self.path/(name+'.json')).read_text())

    def test_twenty_complete_sequences(self):
        self.assertEqual(len(self.manifest),20)
        for entry in self.manifest:
            replay=self.load(entry['scenario'])
            self.assertEqual(replay['replay_version'],1)
            self.assertEqual(replay['geometry_contract_version'],1)
            self.assertTrue(replay['synthetic_only'])
            self.assertEqual(len(replay['frames']),entry['frames'])
            for f in replay['frames']:
                self.assertEqual(set(f['identity_epochs']),{c['id'] for c in f['structures']})
                self.assertIn('logical_time',f)
                for c in f['structures']:
                    self.assertEqual(c['contract_version'],1)
                    self.assertIn('regions',c);self.assertIn('convex_parts',c)
                    self.assertIn('position',c);self.assertIn('tracking',c);self.assertIn('confidence',c)

    def test_monotonic_sequences_except_explicit_faults(self):
        for e in self.manifest:
            frames=self.load(e['scenario'])['frames']
            violations=sum(b['sequence']<=a['sequence'] for a,b in zip(frames,frames[1:]))
            self.assertEqual(violations,int(e['scenario'] in ['13_duplicate','14_out_of_order']))

    def test_geometry_versions_and_epochs_survive_split(self):
        frames=self.load('07_split')['frames']
        before=frames[13];after=frames[-1]
        self.assertEqual(set(before['identity_epochs']),set(after['identity_epochs']))
        for c in after['structures']:
            self.assertGreater(after['identity_epochs'][c['id']],before['identity_epochs'][c['id']])
            prior=next(p for p in before['structures'] if p['id']==c['id'])
            self.assertGreaterEqual(c['geometry_version'],prior['geometry_version'])

    def test_deterministic_without_wall_clock(self):
        a,b=ReplayExporter(),ReplayExporter()
        for i in range(25):
            im=image([(120+i,300,100,40,1)])
            self.assertEqual(a.append_image(im),b.append_image(im))

    def test_pose_changes_do_not_change_geometry_version(self):
        frames=self.load('03_rotation')['frames'][8:]
        self.assertGreater(frames[-1]['structures'][0]['orientation_radians'],0)
        self.assertEqual(len({f['structures'][0]['geometry_version'] for f in frames}),1)
        self.assertEqual(len({geometry_key(f['structures'][0]) for f in frames}),1)

    def test_full_snapshot_recovers_after_dropped_history(self):
        f=self.load('18_occupied_split')['frames'][-1]
        self.assertEqual(len(f['structures']),2)
        for c in f['structures']:
            self.assertGreater(len(c['convex_parts']),0)
            self.assertGreater(len(c['regions']),0)
        self.assertEqual(f['events'],[])  # No events needed to reconstruct the state.

    def test_fault_is_deliberately_invalid_then_full_valid_recovery(self):
        frames=self.load('15_invalid_geometry')['frames']
        self.assertEqual(frames[10]['structures'][0]['convex_parts'][0],[[0,0],[1,0],[2,0]])
        self.assertEqual(len(frames[11]['structures'][0]['convex_parts'][0]),4)

    def test_merge_split_events_exported(self):
        frames=self.load('20_long')['frames']
        events=[e['type'] for f in frames for e in f['events']]
        self.assertIn('MERGE',events)
        for name in ['07_split','18_occupied_split']:
            self.assertIn('SPLIT',[e['type'] for f in self.load(name)['frames'] for e in f['events']])

    def test_hz_validation(self):
        for hz in [0,121,30.0]:
            with self.assertRaises(ValueError):ReplayExporter(hz)


if __name__=='__main__':unittest.main()

from copy import deepcopy
import unittest
import tempfile
from pathlib import Path
import json
from vision.material_replay import MaterialReplayExporter, labels, export_scenarios
from vision.material_synthetic import bgr


class MaterialReplayTests(unittest.TestCase):
    def settle(self,e,mask,n=12):
        return [e.append_image(bgr(mask)) for _ in range(n)]

    def test_full_snapshots_and_identity(self):
        e=MaterialReplayExporter(session='unit')
        first=self.settle(e,labels('two'))[-1]
        merged=self.settle(e,labels('two',True))
        split=self.settle(e,labels('two'))
        self.assertEqual(e.payload('test')['replay_version'],2)
        all_frames=e.frames
        self.assertEqual([f['sequence'] for f in all_frames],list(range(1,len(all_frames)+1)))
        before={r['region_id'] for c in first['structures'] for r in c['material_regions']}
        after={r['region_id'] for c in split[-1]['structures'] for r in c['material_regions']}
        self.assertEqual(before,after)
        self.assertEqual(sum(x['type']=='MERGE' for f in merged for x in f['events']),1)
        self.assertEqual(sum(x['type']=='SPLIT' for f in split for x in f['events']),1)
        for f in all_frames:
            self.assertEqual(f['session_id'],'unit')
            self.assertEqual(set(f['region_identity_epochs']),{r['region_id'] for c in f['structures'] for r in c['material_regions']})
            self.assertTrue(all(v==1 for v in f['region_identity_epochs'].values()))

    def test_input_validation(self):
        for hz in [0,61,30.5,True]:
            with self.assertRaises(ValueError):MaterialReplayExporter(hz=hz)
        for session in [15,'','x'*65]:
            with self.assertRaises(ValueError):MaterialReplayExporter(session=session)

    def test_snapshots_independent(self):
        e=MaterialReplayExporter();f=self.settle(e,labels())[-1];old=deepcopy(f)
        self.settle(e,labels('one_way'))
        self.assertEqual(f,old)
        self.assertEqual({r['material'] for c in e.frames[-1]['structures'] for r in c['material_regions']},{'ORANGE_ONE_WAY'})

    def test_epochs_reappearance_and_holes(self):
        e=MaterialReplayExporter()
        self.settle(e,labels('hole'))
        self.assertTrue(any(r['holes'] for c in e.frames[-1]['structures'] for r in c['regions']))
        empty=labels();empty[:]=0
        self.settle(e,empty)
        self.assertEqual(e.frames[-1]['structures'],[])
        self.settle(e,labels('hole'))
        self.assertTrue(e.frames[-1]['structures'])
        self.assertTrue(all(v>=1 for v in e.frames[-1]['identity_epochs'].values()))

    def test_partial_export_retains_manifest_and_validates_names(self):
        with tempfile.TemporaryDirectory(dir='tmp') as folder:
            output=Path(folder)
            self.assertEqual(len(export_scenarios(output,120,['01_solid'])),1)
            self.assertEqual(len(export_scenarios(output,120,['03_one_way'])),2)
            before=(output/'manifest.json').read_bytes()
            with self.assertRaises(ValueError):export_scenarios(output,120,['unknown'])
            self.assertEqual(before,(output/'manifest.json').read_bytes())
            self.assertEqual(json.loads((output/'01_solid.json').read_text())['replay_version'],2)

if __name__=='__main__':unittest.main()

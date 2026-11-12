from copy import deepcopy
import json
import unittest
from unittest.mock import patch
from vision.structure_udp import Session,fragment,Reassembler,validate_snapshot,confirmed_frame
from tests.material_udp_fixtures import source

class MaterialUdpTests(unittest.TestCase):
    def test_roundtrip_all_materials_and_holes(self):
        for name in ['07_three','11_hole','12_corner']:
            f=source(name)[-1];m=Session().snapshot(f,start=True)
            self.assertEqual(m['protocol_version'],2)
            r=Reassembler();result=None
            for packet in fragment(m)[::-1]:result=r.feed(packet)
            self.assertEqual(result,m)
            self.assertTrue(all(len(packet)<=1200 for packet in fragment(m)))
    def test_requires_region_epochs(self):
        m=Session().snapshot(source('07_three')[-1],start=True)
        for bad in ['missing','extra','invalid']:
            f=deepcopy(m)
            if bad=='missing':f.pop('region_identity_epochs')
            elif bad=='extra':f['region_identity_epochs']['unknown']=1
            else:f['region_identity_epochs'][next(iter(f['region_identity_epochs']))]=0
            with self.assertRaises(ValueError):validate_snapshot(f)
    def test_material_validation(self):
        f=deepcopy(source('07_three')[-1]);f['structures'][0]['material_regions'][0]['material']='UNKNOWN'
        with self.assertRaises(ValueError):Session().snapshot(f,start=True)
    def test_no_unconfirmed_held_or_empty(self):
        f=deepcopy(source('07_three')[-1]);f['diagnostic']['status']='PENDING_TOPOLOGY'
        self.assertFalse(confirmed_frame(f))
        with self.assertRaises(ValueError):Session().snapshot(f,start=True)
        f['structures']=[]
        self.assertFalse(confirmed_frame(f))
    def test_legacy_wire_still_version_one(self):
        from tests.structure_udp_fixtures import frame
        self.assertEqual(Session().snapshot(frame(),start=True)['protocol_version'],1)
    def test_timestamp_is_after_validation(self):
        from vision import structure_udp
        original=structure_udp.validate_snapshot
        clock=[1_000_000_000]
        def slow_validation(m):
            original(m);clock[0]+=2_000_000_000
        with patch.object(structure_udp,'validate_snapshot',side_effect=slow_validation),patch.object(structure_udp.time,'time_ns',side_effect=lambda:clock[0]):
            message=Session('a'*32,1).snapshot(source('07_three')[-1],start=True)
        self.assertEqual(message['sent_unix_ms'],3000)

if __name__=='__main__':unittest.main()

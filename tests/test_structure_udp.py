import base64
from copy import deepcopy
import json
import unittest
from vision.structure_udp import Reassembler, Session, fragment, encode, MAX_MESSAGE, confirmed_frame
from tests.structure_udp_fixtures import frame


class StructureUdpTests(unittest.TestCase):
    def setUp(self):
        self.message=Session('a'*32,1000).snapshot(frame(),start=True)
        self.packets=fragment(self.message)

    def assemble(self,packets):
        r=Reassembler();m=None
        for p in packets:
            result=r.feed(p,0)
            if result is not None:m=result
        return r,m

    def test_fragment_roundtrip(self):
        r,m=self.assemble(self.packets)
        self.assertEqual(m,self.message);self.assertEqual(r.reserved,0)
        self.assertTrue(all(len(p)<=1200 for p in self.packets))

    def test_reverse(self):self.assertEqual(self.assemble(self.packets[::-1])[1],self.message)
    def test_duplicate_fragment(self):self.assertEqual(self.assemble(self.packets[:1]+self.packets)[1],self.message)
    def test_incomplete(self):self.assertIsNone(self.assemble(self.packets[:-1])[1])
    def test_expire(self):
        r,m=self.assemble(self.packets[:-1]);r.expire(1.1)
        self.assertEqual((r.expired,r.reserved,len(r.pending)),(1,0,0))

    def test_integrity(self):
        bad=[]
        for p in self.packets:
            h=json.loads(p);h['sha256']='0'*64;bad.append(encode(h))
        with self.assertRaisesRegex(ValueError,'integrity'):self.assemble(bad)

    def test_malformed(self):
        with self.assertRaises((ValueError,KeyError)):Reassembler().feed(b'not-json',0)
    def test_datagram_bound(self):
        with self.assertRaisesRegex(ValueError,'datagram_size'):Reassembler().feed(b'x'*1201,0)
    def test_message_bound(self):
        m=deepcopy(self.message);m['diagnostic']='x'*MAX_MESSAGE
        with self.assertRaisesRegex(ValueError,'message_size'):fragment(m)
    def test_count_bound(self):
        h=json.loads(self.packets[0]);h['count']=513
        with self.assertRaisesRegex(ValueError,'limits'):Reassembler().feed(encode(h),0)
    def test_memory_bound(self):
        with self.assertRaisesRegex(ValueError,'budget'):Reassembler(memory=1).feed(self.packets[0],0)
    def test_pending_bound(self):
        r=Reassembler(max_pending=1);r.feed(self.packets[0],0)
        m=deepcopy(self.message);m['sequence']=2
        with self.assertRaisesRegex(ValueError,'budget'):r.feed(fragment(m)[0],0)
    def test_changed_header(self):
        r=Reassembler();r.feed(self.packets[0],0)
        h=json.loads(self.packets[1]);h['sha256']='0'*64
        with self.assertRaisesRegex(ValueError,'conflicting'):r.feed(encode(h),0)
    def test_invalid_base64(self):
        h=json.loads(self.packets[0]);h['data']='!invalid!'
        with self.assertRaises(ValueError):Reassembler().feed(encode(h),0)
    def test_unconfirmed_empty(self):
        m=deepcopy(self.message);m.update(scene_state='SCENE_EMPTY',structures=[],identity_epochs={},empty_confirmed=False)
        with self.assertRaisesRegex(ValueError,'unconfirmed_empty'):fragment(m)
    def test_old_protocol_separate(self):
        with self.assertRaisesRegex(ValueError,'protocol'):fragment({'version':1,'modules':[]})
    def test_session_restart(self):
        a=Session();b=Session();self.assertNotEqual(a.id,b.id)
        self.assertEqual(a.snapshot(frame(),start=True)['sequence'],1)
        self.assertEqual(b.snapshot(frame(),start=True)['sequence'],1)
    def test_bad_numeric(self):
        m=deepcopy(self.message);m['logical_time']=float('nan')
        with self.assertRaises(ValueError):fragment(m)
    def test_no_capture_import(self):
        import inspect,vision.structure_udp_sender as sender
        self.assertNotIn('VideoCapture',inspect.getsource(sender))
    def test_pending_birth_cannot_emit_empty(self):
        f=dict(structures=[],identity_epochs={},events=[],logical_time=0,diagnostic=dict(observed_components=1,tracking_status='PENDING_TOPOLOGY'))
        self.assertFalse(confirmed_frame(f))
        with self.assertRaisesRegex(ValueError,'unconfirmed_absence'):Session().snapshot(f,start=True)
    def test_confirmed_empty_from_existing_tracker(self):
        f=dict(structures=[],identity_epochs={},events=[],logical_time=0,diagnostic=dict(observed_components=0,tracking_status='TRACKING'))
        self.assertEqual(Session().snapshot(f,start=True)['scene_state'],'SCENE_EMPTY')


if __name__=='__main__':unittest.main()

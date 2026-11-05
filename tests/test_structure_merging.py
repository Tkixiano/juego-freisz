"""All inputs are generated arrays. Hardware/network APIs are forbidden here."""
from dataclasses import replace
import json
import unittest
from unittest.mock import patch
import cv2
import numpy as np
from vision.structure_segmentation import (StructureSegmenter, StructureSettings,
                                            cell_rings, signed_area)
from vision.structure_tracking import StructureTracker
from vision.structure_synthetic import COLORS, PALETTE, frame, fixtures, scenarios, run_scenario


class StructureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.guards = [patch('cv2.VideoCapture',side_effect=AssertionError('NO CAMERA')),
                      patch('socket.socket',side_effect=AssertionError('NO NETWORK'))]
        for p in cls.guards:
            p.start()

    @classmethod
    def tearDownClass(cls):
        for p in reversed(cls.guards):
            p.stop()

    def setUp(self):
        self.settings = StructureSettings()
        self.segmenter = StructureSegmenter(COLORS,self.settings)
        self.tracker = StructureTracker(self.settings)
        self.f = fixtures()

    def advance(self,image,n=5):
        history=[]
        for _ in range(n):
            history.append(self.tracker.update(self.segmenter.segment(image)))
        return history

    def test_twelve_required_sequences(self):
        for name,stages,events in scenarios():
            with self.subTest(scenario=name):
                r=run_scenario(name,stages,events)
                self.assertTrue(r['pass'],{k:r[k] for k in ('name','stages','actual_merge_split')})

    def test_masks_retained_and_union(self):
        s=self.segmenter.segment(self.f['three_joined'])
        np.testing.assert_array_equal(s.combined,np.logical_or.reduce(list(s.masks.values())))
        self.assertEqual([np.count_nonzero(m) for m in s.masks.values()],[1600]*3)
        self.assertEqual(len(s.regions),1)

    def test_no_bbox_or_hull_and_exact_concavity(self):
        s=self.segmenter.segment(self.f['concave_joined'])
        r=s.regions[0]
        self.assertEqual(len(r.rings[0]),6)
        self.assertEqual(sum(signed_area(p) for p in r.rings),r.area)
        self.assertLess(cv2.pointPolygonTest(r.rings[0].astype('float32'),(110,60),False),0)
        self.assertGreater(cv2.pointPolygonTest(r.rings[0].astype('float32'),(70,70),False),0)

    def test_corner_is_one_logical_structure_multiple_simple_rings(self):
        self.advance(self.f['corner_before'])
        h=self.advance(self.f['corner'],5)
        self.assertEqual([len(x['structures']) for x in h],[2,2,2,2,1])
        obj=h[-1]['structures'][0]
        self.assertEqual(len(obj['rings']),2)
        self.assertFalse(obj['manager_candidate'])
        self.assertIn('MULTIPART_POINT_CONTACT',obj['integration_blockers'])
        self.assertEqual(obj['geometry_area'],3200)

    def test_holes_preserved_not_filled(self):
        image=frame((40,40,80,80,1))
        image[60:100,60:100]=0
        r=self.segmenter.segment(image).regions[0]
        self.assertEqual(len(r.rings),2)
        self.assertEqual(sum(signed_area(p) for p in r.rings),4800)
        obj=self.advance(image)[-1]['structures'][0]
        self.assertIn('HOLES_NOT_SUPPORTED_BY_PHASE1A',obj['integration_blockers'])

    def test_single_frame_merge_does_not_emit(self):
        self.advance(self.f['separated_colors'])
        h=self.advance(self.f['joined_colors'],1)+self.advance(self.f['separated_colors'])
        self.assertTrue(all(len(x['structures'])==2 for x in h))
        self.assertFalse(any(e['type']=='MERGE' for x in h for e in x['events']))

    def test_single_frame_split_does_not_emit(self):
        self.advance(self.f['separated_colors'])
        self.advance(self.f['joined_colors'])
        h=self.advance(self.f['separated_colors'],1)+self.advance(self.f['joined_colors'])
        self.assertTrue(all(len(x['structures'])==1 for x in h))
        self.assertFalse(any(e['type']=='SPLIT' for x in h for e in x['events']))

    def test_confirmation_is_consecutive(self):
        self.advance(self.f['separated_colors'])
        self.advance(self.f['joined_colors'],2)
        self.advance(self.f['separated_colors'],1)
        h=self.advance(self.f['joined_colors'],3)
        self.assertEqual([len(x['structures']) for x in h],[2,2,1])

    def test_identical_same_color_split_is_explicitly_ambiguous(self):
        old=self.advance(self.f['separated'])[-1]
        old_ids={m for o in old['structures'] for m in o['member_ids']}
        self.advance(self.f['joined'])
        h=self.advance(self.f['separated'])
        new_ids={m for o in h[-1]['structures'] for m in o['member_ids']}
        self.assertTrue(old_ids.isdisjoint(new_ids))
        self.assertEqual(sum(e['type']=='IDENTITY_AMBIGUITY' for x in h for e in x['events']),1)

    def test_different_colors_recover_unique_ids(self):
        old=self.advance(self.f['separated_colors'])[-1]
        self.advance(self.f['joined_colors'])
        new=self.advance(self.f['separated_colors'])[-1]
        self.assertEqual({o['id'] for o in old['structures']},{o['id'] for o in new['structures']})
        self.assertEqual({m for o in old['structures'] for m in o['member_ids']},
                         {m for o in new['structures'] for m in o['member_ids']})

    def test_birth_already_joined_does_not_invent_constituents(self):
        obj=self.advance(self.f['joined_colors'])[-1]['structures'][0]
        self.assertEqual(obj['identity_scope'],'OBSERVED_COMPONENT')
        self.assertEqual(len(obj['member_ids']),1)
        h=self.advance(self.f['separated_colors'])
        self.assertEqual(sum(e['type']=='IDENTITY_AMBIGUITY' for x in h for e in x['events']),1)

    def test_proximity_never_creates_fake_bridge(self):
        for key,gap in [('gap1',1),('gap2',2)]:
            s=self.segmenter.segment(self.f[key])
            self.assertEqual(len(s.regions),2)
            self.assertAlmostEqual(s.proximity[0]['gap_pixels'],gap,places=4)
            self.assertEqual(s.proximity[0]['state'],'AMBIGUOUS_PROXIMITY')
            self.assertFalse(s.combined[70,99])

    def test_near_split_uses_longer_confirmation(self):
        self.advance(self.f['separated_colors'])
        self.advance(self.f['joined_colors'])
        h=self.advance(self.f['gap1'],8)
        self.assertEqual([len(x['structures']) for x in h],[1]*7+[2])

    def test_thin_noise_bridge_remains_ambiguous(self):
        self.advance(self.f['separated_colors'])
        before={o.id:o.geometry_mask.copy() for o in self.tracker.objects.values()}
        h=self.advance(self.f['noise'],12)
        self.assertTrue(all(x['status']=='AMBIGUOUS_THIN_BRIDGE' for x in h))
        for id,m in before.items():
            np.testing.assert_array_equal(m,self.tracker.objects[id].geometry_mask)

    def test_overlapping_hsv_does_not_duplicate_geometry(self):
        colors=[COLORS[0],replace(COLORS[1],lower=COLORS[0].lower,upper=COLORS[0].upper)]
        s=StructureSegmenter(colors).segment(frame((40,40,40,40,1)))
        self.assertEqual(len(s.regions),1)
        self.assertEqual(s.conflict_pixels,1600)
        self.assertEqual(s.regions[0].area,1600)

    def test_translation_does_not_rebuild_geometry(self):
        self.advance(frame((40,40,40,40,1)))
        start=next(iter(self.tracker.objects.values()))
        id,revision=start.id,start.revision
        for x in range(41,61):
            self.advance(frame((x,40,40,40,1)),1)
        obj=self.tracker.objects[id]
        self.assertEqual(obj.revision,revision)
        np.testing.assert_array_equal(obj.position,start.position+[20,0])

    def test_tiny_boundary_noise_does_not_rebuild(self):
        image=frame((40,40,40,40,1))
        self.advance(image)
        id=next(iter(self.tracker.objects))
        noisy=image.copy()
        noisy[39,60]=PALETTE[1]
        self.advance(noisy)
        self.assertEqual(self.tracker.objects[id].revision,1)

    def test_real_shape_change_rebuilds_and_preserves_concavity(self):
        self.advance(frame((40,40,80,80,1)))
        id=next(iter(self.tracker.objects))
        image=frame((40,40,80,80,1));image[40:100,60:100]=0
        self.advance(image)
        self.assertEqual(self.tracker.objects[id].revision,2)
        self.assertEqual(sum(signed_area(p) for p in self.tracker.objects[id].local_rings),4000)

    def test_loss_holds_then_removes_and_reappearance_confirms(self):
        image=frame((40,40,40,40,1))
        self.advance(image)
        h=self.advance(frame(),5)
        self.assertEqual([len(x['structures']) for x in h],[1,1,1,1,0])
        h=self.advance(image,3)
        self.assertEqual([len(x['structures']) for x in h],[0,0,1])

    def test_resolution_change_rejected_without_mutation(self):
        self.advance(self.f['separated_colors'])
        ids=list(self.tracker.objects)
        with self.assertRaises(ValueError):
            self.tracker.update(self.segmenter.segment(np.zeros((100,100,3),np.uint8)))
        self.assertEqual(ids,list(self.tracker.objects))

    def test_noise_area_rejected(self):
        image=frame((40,40,4,4,1),(80,40,3,3,2))
        s=self.segmenter.segment(image)
        self.assertEqual(len(s.regions),0)
        self.assertEqual(s.rejected_pixels,25)

    def test_limits_invalid_inputs_and_configuration(self):
        for kwargs in [{'birth_frames':0},{'proximity_pixels':float('nan')},
                       {'near_split_frames':2},{'geometry_difference_fraction':.5}]:
            with self.assertRaises(ValueError): StructureSettings(**kwargs)
        with self.assertRaises(ValueError): StructureSegmenter([COLORS[0],COLORS[0]])
        with self.assertRaises(ValueError): self.segmenter.segment(np.zeros((20,20),np.uint8))
        with self.assertRaises(ValueError):
            StructureSegmenter(COLORS,replace(self.settings,max_components=1)).segment(self.f['separated'])

    def test_json_snapshot_has_no_udp_schema_or_inherited_angle(self):
        self.advance(self.f['separated_colors'])
        result=self.advance(self.f['joined_colors'])[-1]
        restored=json.loads(json.dumps(result))
        obj=restored['structures'][0]
        self.assertEqual(obj['rotation_radians'],0)
        self.assertEqual(obj['coordinate_space'],'CAMERA_PIXEL_CELL_EDGES')
        self.assertNotIn('modules',restored)
        self.assertNotIn('version',restored)

    def test_random_masks_area_conservation(self):
        rng=np.random.default_rng(704)
        for _ in range(40):
            mask=rng.random((12,12))>.5
            rings=cell_rings(mask)
            self.assertEqual(sum(signed_area(r) for r in rings),int(mask.sum()))

    def test_global_hysteresis_does_not_inherit_birth_delay(self):
        self.settings=replace(self.settings,birth_frames=7)
        self.segmenter=StructureSegmenter(COLORS,self.settings)
        self.tracker=StructureTracker(self.settings)
        self.advance(self.f['separated_colors'],7)
        h=self.advance(self.f['joined_colors'],3)
        self.assertEqual([len(x['structures']) for x in h],[2,2,1])

    def test_color_change_during_birth_resets_confirmation(self):
        self.advance(frame((40,40,40,40,1)),2)
        # A disjoint component cannot inherit two frames from an unrelated birth.
        h=self.advance(frame((180,40,40,40,2)),3)
        self.assertEqual([len(x['structures']) for x in h],[0,0,1])

    def test_no_false_merge_when_one_nearby_object_disappears(self):
        self.advance(self.f['separated_colors'])
        h=self.advance(frame((100,60,40,40,2)),8)
        self.assertFalse(any(e['type']=='MERGE' for x in h for e in x['events']))
        self.assertEqual(len(h[-1]['structures']),1)

    def test_three_colors_ids_recovered_and_no_duplicated_participants(self):
        initial=self.advance(self.f['three'])[-1]
        merged=self.advance(self.f['three_joined'])[-1]
        self.assertEqual(len(merged['structures']),1)
        members=merged['structures'][0]['member_ids']
        self.assertEqual(len(members),len(set(members)))
        self.assertEqual(len(members),3)
        final=self.advance(self.f['three'])[-1]
        self.assertEqual({o['id'] for o in initial['structures']},{o['id'] for o in final['structures']})

    def test_cache_never_emits_overlapping_shapes(self):
        image=frame((40,40,40,40,1),(82,40,40,40,2))
        self.advance(image)
        for offset in [1,0,1,0,1,0]:
            noisy=frame((40,40,40,40,1),(82,40,40,40,2))
            noisy[60,80:81+offset]=PALETTE[1]
            self.advance(noisy,1)
            count=np.zeros(image.shape[:2],np.uint8)
            for obj in self.tracker.objects.values(): count+=obj.geometry_mask.astype('uint8')
            self.assertLessEqual(int(count.max()),1)

    def test_rotation_uses_transformed_rings_not_inherited_angle(self):
        image=self.f['concave_joined']
        self.advance(image)
        transform=cv2.getRotationMatrix2D((100,80),90,1)
        rotated=cv2.warpAffine(image,transform,(280,180),flags=cv2.INTER_NEAREST)
        snapshot=self.advance(rotated)[-1]
        self.assertEqual(len(snapshot['structures']),1)
        obj=snapshot['structures'][0]
        self.assertEqual(obj['rotation_radians'],0)
        r=self.segmenter.segment(rotated).regions[0]
        world=np.array(obj['rings'][0]['vertices'])+obj['position']
        np.testing.assert_array_equal(world,r.rings[0])
        self.assertEqual(obj['geometry_area'],r.area)

    def test_two_green_ids_continue_independently_while_separated(self):
        first=self.advance(frame((40,60,40,40,1),(160,60,40,40,1)))[-1]
        ids=[o['id'] for o in sorted(first['structures'],key=lambda o:o['position'][0])]
        for x in range(41,61): self.advance(frame((x,60,40,40,1),(160,60,40,40,1)),1)
        self.assertEqual(list(self.tracker.objects),ids)
        np.testing.assert_array_equal(self.tracker.objects[ids[1]].position,[180,80])
        np.testing.assert_array_equal(self.tracker.objects[ids[0]].position,[80,80])

    def test_initial_corner_contact_also_requires_longer_confirmation(self):
        h=self.advance(self.f['corner'],5)
        self.assertEqual([len(x['structures']) for x in h],[0,0,0,0,1])


if __name__=='__main__':
    unittest.main()

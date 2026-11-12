"""Optimization regressions: exact data, cache invalidation and snapshot ownership."""
from copy import deepcopy
from itertools import permutations
import json
from pathlib import Path
import unittest
import numpy as np
from tests.benchmark_pipeline import digest
from vision.material_structures import MaterialStructures,validate_material_contract
from vision.material_synthetic import three,bgr,scenarios
from vision.structure_udp import Session,validate_snapshot

class PerformanceInvariants(unittest.TestCase):
    def test_exact_baseline_topology_corpus(self):
        baseline=json.loads(Path('artifacts/optimization/python_before.json').read_text())['equivalence_corpus']
        for name,frames,_ in scenarios():
            pipe=MaterialStructures()
            for index,f in enumerate(frames):
                value=pipe.update(f);expected=baseline[name][index]
                if digest(value)!=expected:
                    # REGION_REMOVE was already emitted from an unordered set in
                    # the baseline. Prove byte equality after ONLY permuting it.
                    self.assertTrue(any(digest(dict(value,material_events=list(p)))==expected for p in permutations(value['material_events'])),(name,index))
    def test_segmentation_cache_has_independent_outputs(self):
        pipe=MaterialStructures();image=bgr(three());a=pipe.segmenter.segment(image);a.combined[:]=False
        b=pipe.segmenter.segment(image);self.assertTrue(b.combined.any())
        b.material_masks[1][:]=False
        self.assertTrue(pipe.segmenter.segment(image).material_masks[1].any())
    def test_segmentation_cache_rechecks_dtype(self):
        seg=MaterialStructures().segmenter;image=bgr(three());seg.segment(image)
        with self.assertRaises(ValueError):seg.segment(image.astype(float))
    def test_segmentation_cache_rechecks_hsv(self):
        seg=MaterialStructures().segmenter;image=bgr(three());seg.segment(image)
        seg.colors[0].lower=[70,90,55]
        self.assertFalse(seg.segment(image).material_masks[1].any())
    def test_schema_cache_rejects_changed_material_and_owner(self):
        pipe=MaterialStructures()
        for _ in range(8):s=pipe.update(bgr(three()))
        c=s['structures'][0];validate_material_contract(c)
        for field,value in [('material','UNKNOWN'),('structure_id','wrong')]:
            bad=deepcopy(c);bad['material_regions'][0][field]=value
            with self.assertRaises(ValueError):validate_material_contract(bad)
    def test_udp_cache_cannot_hide_bad_geometry(self):
        f=json.loads(Path('juegofrei/validation/material_replays/07_three.json').read_text())['frames'][-1]
        s=Session();m=s.snapshot(f,start=True);validate_snapshot(m)
        bad=deepcopy(m);bad['structures'][0]['material_regions'][0]['regions'][0]['exterior'][1]=bad['structures'][0]['material_regions'][0]['regions'][0]['exterior'][0]
        with self.assertRaises(ValueError):validate_snapshot(bad)

if __name__=='__main__':unittest.main()

"""Conservative, bounded offline topology tracker for synthetic Phase 1B.

Snapshots replace logical geometry atomically: merged parents are never emitted
alongside their child. No UDP protocol or DynamicGeometryManager adapter here.
"""
from __future__ import annotations

from dataclasses import dataclass
import cv2
import numpy as np
from .structure_segmentation import Region, Segmentation, StructureSettings, signed_area


@dataclass
class Member:
    id: str
    origin: str
    area: int
    colors: dict[int, float]
    hu: np.ndarray


@dataclass
class TrackedStructure:
    id: str
    region: Region
    members: tuple[Member, ...]
    position: np.ndarray
    local_rings: tuple[np.ndarray, ...]
    geometry_mask: np.ndarray
    revision: int = 1
    stale_frames: int = 0
    identity_scope: str = 'OBSERVED_COMPONENT'

    def as_dict(self, settings: StructureSettings) -> dict:
        outer = sum(signed_area(r) > 0 for r in self.local_rings)
        holes = sum(signed_area(r) < 0 for r in self.local_rings)
        reasons = []
        if outer != 1:
            reasons.append('MULTIPART_POINT_CONTACT')
        if holes:
            reasons.append('HOLES_NOT_SUPPORTED_BY_PHASE1A')
        if any(len(r) > settings.max_manager_vertices for r in self.local_rings):
            reasons.append('VERTEX_LIMIT')
        # A single loop may touch itself in a pathological digital boundary.
        if any(len(np.unique(r, axis=0)) != len(r) for r in self.local_rings):
            reasons.append('SELF_TOUCHING_RING')
        return {'id': self.id, 'member_ids': [m.id for m in self.members],
                'identity_scope': self.identity_scope,
                'coordinate_space': 'CAMERA_PIXEL_CELL_EDGES',
                'position': self.position.tolist(), 'rotation_radians': 0.0,
                'orientation_policy': 'WORLD_ALIGNED_RINGS_NOT_COMPONENT_ANGLE',
                'rings': [{'kind': 'exterior' if signed_area(r)>0 else 'hole',
                           'vertices': r.tolist()} for r in self.local_rings],
                'observed_area': self.region.area,
                'geometry_area': sum(signed_area(r) for r in self.local_rings),
                'colors': self.region.colors, 'geometry_revision': self.revision,
                'stale_frames': self.stale_frames,
                'manager_candidate': not reasons, 'integration_blockers': reasons}


def hu_descriptor(region: Region) -> np.ndarray:
    x,y,w,h=region.bounds
    hu = cv2.HuMoments(cv2.moments(region.mask[y:y+h,x:x+w].astype('uint8'), binaryImage=True)).ravel()
    return np.sign(hu) * -np.log10(np.maximum(np.abs(hu), 1e-20))


class StructureTracker:
    def __init__(self, settings: StructureSettings | None = None):
        self.settings = settings or StructureSettings()
        self.objects: dict[str, TrackedStructure] = {}
        self.frame = 0
        self._serial = 0
        self._member_serial = 0
        self._pending = None
        self._pending_count = 0
        self._pending_mask = None
        self._shape = None
        self.events: list[dict] = []  # current frame only; callers may persist
        self.geometry_rebuilds = 0
        self.overlap_rejections = 0

    def _id(self):
        self._serial += 1
        return f's{self._serial:06d}'

    def _member(self, id, r):
        self._member_serial += 1
        return Member(f'o{self._member_serial:06d}', id, r.area, r.colors.copy(), hu_descriptor(r))

    def _new(self, r, members=None, id=None, scope='OBSERVED_COMPONENT'):
        id = id or self._id()
        self.geometry_rebuilds += 1
        return TrackedStructure(id, r, members if members is not None else (self._member(id,r),),
                                r.center.copy(), tuple(p-r.center for p in r.rings), r.mask.copy(),
                                identity_scope=scope)

    def _event(self, kind, parents=(), children=(), **details):
        self.events.append({'frame':self.frame, 'type':kind, 'parents':list(parents),
                            'children':list(children), **details})

    def _groups(self, regions):
        old = list(self.objects.values())
        edges = set()
        for i,o in enumerate(old):
            for j,r in enumerate(regions):
                overlap = int(np.count_nonzero(o.region.mask & r.mask))
                if overlap / min(o.region.area, r.area) >= .20:
                    edges.add((i,j))
        # Motion fallback only between unmatched observations and unmatched tracks.
        oi = [i for i in range(len(old)) if not any(a==i for a,b in edges)]
        nj = [j for j in range(len(regions)) if not any(b==j for a,b in edges)]
        candidates = {(i,j) for i in oi for j in nj
                      if np.linalg.norm(old[i].region.center-regions[j].center) <= self.settings.max_motion_pixels}
        for i,j in candidates:
            if sum(a==i for a,b in candidates)==1 and sum(b==j for a,b in candidates)==1:
                edges.add((i,j))
        # A participant can move entirely out of its old footprint while joining
        # a region that already overlaps another participant. Reciprocal-only
        # matching above cannot discover that case. Add only UNIQUE nearby
        # attachments, then require aggregate area and color conservation.
        base_edges = edges.copy()
        for i in range(len(old)):
            if any(a==i for a,b in edges):
                continue
            possible = []
            for j,r in enumerate(regions):
                d = cv2.distanceTransform((~r.mask).astype('uint8'),cv2.DIST_L2,cv2.DIST_MASK_PRECISE)
                x,y = np.floor(old[i].region.center).astype(int)
                if d[y,x] <= self.settings.max_motion_pixels and any(k in r.colors for k in old[i].region.colors):
                    possible.append(j)
            if len(possible)==1:
                edges.add((i,possible[0]))
        for j,r in enumerate(regions):
            if any(b==j for a,b in edges):
                continue
            possible = []
            for i,o in enumerate(old):
                d = cv2.distanceTransform((~o.region.mask).astype('uint8'),cv2.DIST_L2,cv2.DIST_MASK_PRECISE)
                x,y = np.floor(r.center).astype(int)
                if d[y,x] <= self.settings.max_motion_pixels and any(k in o.region.colors for k in r.colors):
                    possible.append(i)
            if len(possible)==1:
                edges.add((i,j))
        for j,r in enumerate(regions):
            parents = [old[i] for i,b in edges if b==j]
            if len(parents)>1:
                area = sum(o.region.area for o in parents)
                histogram = {k:sum(o.region.area*o.region.colors.get(k,0) for o in parents)/area
                             for k in set().union(*(o.region.colors for o in parents))}
                distance = sum(abs(histogram.get(k,0)-r.colors.get(k,0)) for k in histogram.keys()|r.colors.keys())
                if not .7 <= r.area/area <= 1.3 or distance > .35:
                    edges = {edge for edge in edges if edge[1]!=j or edge in base_edges}
        groups = []
        remaining = {('o',i) for i in range(len(old))} | {('n',j) for j in range(len(regions))}
        while remaining:
            todo = [min(remaining)]
            group = set()
            while todo:
                node = todo.pop()
                if node in group:
                    continue
                group.add(node)
                typ,k = node
                todo.extend(('n',b) for a,b in edges if typ=='o' and a==k)
                todo.extend(('o',a) for a,b in edges if typ=='n' and b==k)
            remaining -= group
            groups.append(([old[k] for typ,k in sorted(group) if typ=='o'],
                           [regions[k] for typ,k in sorted(group) if typ=='n']))
        return groups

    def _recover(self, parent, children):
        """Mutually unique color/area/Hu evidence. Position alone is not identity.

        Identical same-color pieces deliberately get NEW IDs after a merge.
        """
        possibilities = []
        for r in children:
            matches = []
            for m in parent.members:
                color_distance = sum(abs(r.colors.get(k,0)-m.colors.get(k,0)) for k in r.colors.keys()|m.colors.keys())
                ratio = max(r.area,m.area)/min(r.area,m.area)
                hu_distance = float(np.linalg.norm(hu_descriptor(r)[:2]-m.hu[:2]))
                if color_distance < .25 and ratio < 1.3 and hu_distance < .8:
                    matches.append(m)
            possibilities.append(matches)
        counts = {m.id: sum(any(c.id==m.id for c in p) for p in possibilities) for m in parent.members}
        return [p[0] if len(p)==1 and counts[p[0].id]==1 else None for p in possibilities]

    def _continued(self, old, r):
        # Geometry cache tolerates only small boundary AND area differences.
        delta = np.rint(r.center-old.position).astype(int)
        affine = np.float32([[1,0,delta[0]],[0,1,delta[1]]])
        shifted = cv2.warpAffine(old.geometry_mask.astype('uint8'), affine,
                                 (r.mask.shape[1],r.mask.shape[0]), flags=cv2.INTER_NEAREST).astype(bool)
        difference = np.count_nonzero(shifted ^ r.mask) / max(1,np.count_nonzero(shifted | r.mask))
        boundary_error = 0. if difference==0 else float('inf')
        if difference>0 and shifted.any() and r.mask.any():
            da = cv2.distanceTransform((~shifted).astype('uint8'),cv2.DIST_L2,cv2.DIST_MASK_PRECISE)
            db = cv2.distanceTransform((~r.mask).astype('uint8'),cv2.DIST_L2,cv2.DIST_MASK_PRECISE)
            boundary_error = max(float(da[r.mask].max()), float(db[shifted].max()))
        if (difference <= self.settings.geometry_difference_fraction
                and boundary_error <= self.settings.geometry_boundary_pixels
                and r.exterior_count == old.region.exterior_count
                and len(r.rings) == len(old.local_rings)):
            updated = TrackedStructure(old.id,r,old.members,old.position+delta,old.local_rings,
                                       shifted,old.revision,identity_scope=old.identity_scope)
        else:
            updated = self._new(r,old.members,old.id,old.identity_scope)
            updated.revision = old.revision+1
        if len(old.members)==1 and old.identity_scope=='OBSERVED_COMPONENT':
            m = old.members[0]
            updated.members = (Member(m.id,m.origin,r.area,r.colors.copy(),hu_descriptor(r)),)
        return updated

    def update(self, segmentation: Segmentation) -> dict:
        if self._shape is None:
            self._shape = segmentation.combined.shape
        if self._shape != segmentation.combined.shape:
            raise ValueError('resolution changed: create a fresh tracker')
        self.frame += 1
        self.events = []
        regions = segmentation.regions
        groups = self._groups(regions)
        topology = [(parents,children) for parents,children in groups if len(parents)!=1 or len(children)!=1]
        ambiguous = any(r.contact=='AMBIGUOUS_THIN_BRIDGE' for r in regions)
        signature = tuple(sorted((tuple(p.id for p in parents),len(children)) for parents,children in topology))
        required = 1
        for parents,children in topology:
            if not parents:
                required = max(required,self.settings.birth_frames)
                if any(r.contact=='CORNER' for r in children):
                    required = max(required,self.settings.corner_frames)
            elif not children:
                required = max(required,self.settings.loss_frames)
            elif len(parents)>1 and len(children)==1:
                required = max(required,self.settings.corner_frames if children[0].contact=='CORNER' else self.settings.merge_frames)
            elif len(parents)==1 and len(children)>1:
                near = any(any(regions[a] is x for x in children) and any(regions[b] is y for y in children)
                           for pair in segmentation.proximity for a,b in [pair['regions']])
                required = max(required,self.settings.near_split_frames if near else self.settings.split_frames)
        if ambiguous:
            self._pending = None
            self._pending_count = 0
            self._pending_mask = None
        elif topology:
            consistent = False
            if self._pending_mask is not None and signature==self._pending:
                union = self._pending_mask | segmentation.combined
                consistent = np.count_nonzero(self._pending_mask & segmentation.combined) / max(1,np.count_nonzero(union)) >= .5
                if not union.any():
                    consistent = True
            self._pending_count = self._pending_count+1 if consistent else 1
            self._pending = signature
            self._pending_mask = segmentation.combined.copy()
        else:
            self._pending = None
            self._pending_count = 0
            self._pending_mask = None
        commit = bool(topology) and not ambiguous and self._pending_count >= required
        proposed = {}
        for parents,children in groups:
            if len(parents)==1 and len(children)==1 and not ambiguous:
                obj = self._continued(parents[0],children[0])
                proposed[obj.id] = obj
            elif not commit:
                for old in parents:
                    # Held geometry is explicitly stale; no fabricated coordinates.
                    old.stale_frames += 1
                    proposed[old.id] = old
            elif not parents:
                for r in children:
                    obj = self._new(r)
                    proposed[obj.id] = obj
                    self._event('CREATE',children=[obj.id])
            elif not children:
                self._event('REMOVE',parents=[o.id for o in parents])
            elif len(children)==1:
                members = tuple(m for o in parents for m in o.members)
                if len(members) > self.settings.max_members:
                    obj = self._new(children[0],scope='LINEAGE_LIMIT_AMBIGUOUS')
                    self._event('IDENTITY_AMBIGUITY',parents=[o.id for o in parents],reason='lineage_limit')
                else:
                    obj = self._new(children[0],members,scope='KNOWN_OBSERVED_PARTICIPANTS')
                proposed[obj.id] = obj
                self._event('MERGE',parents=[o.id for o in parents],children=[obj.id],
                            participant_ids=[m.id for m in members],contact=children[0].contact)
            elif len(parents)==1:
                recovered = self._recover(parents[0],children)
                ids = []
                ambiguous_children = []
                for r,member in zip(children,recovered):
                    obj = self._new(r,(member,),member.origin) if member else self._new(r)
                    # Never resurrect a structure ID already active elsewhere.
                    if obj.id in proposed or obj.id in self.objects and obj.id != parents[0].id:
                        obj = self._new(r)
                        member = None
                    proposed[obj.id] = obj
                    ids.append(obj.id)
                    if member is None:
                        ambiguous_children.append(obj.id)
                self._event('SPLIT',parents=[parents[0].id],children=ids,
                            recovered_members=sum(m is not None for m in recovered))
                if ambiguous_children:
                    self._event('IDENTITY_AMBIGUITY',parents=[parents[0].id],children=ambiguous_children,
                                reason='non_unique_color_geometry_evidence')
            else:
                ids = []
                for r in children:
                    obj = self._new(r)
                    proposed[obj.id] = obj
                    ids.append(obj.id)
                self._event('IDENTITY_AMBIGUITY',parents=[o.id for o in parents],children=ids,
                            reason='many_to_many_reconfiguration')
        # Caching/independent motion must never cause overlapping emitted shapes.
        occupied = np.zeros(self._shape,dtype=bool)
        overlap = False
        for obj in proposed.values():
            if np.any(occupied & obj.geometry_mask):
                overlap = True
                break
            occupied |= obj.geometry_mask
        if overlap:
            self.overlap_rejections += 1
            self.events = []
            self._event('GEOMETRY_CONFLICT',reason='atomic_frame_held_to_prevent_duplicate_collision')
        else:
            self.objects = proposed
        if commit:
            self._pending = None
            self._pending_mask = None
            self._pending_count = 0
        return {'frame':self.frame, 'structures':[o.as_dict(self.settings) for o in self.objects.values()],
                'events':list(self.events), 'observed_components':len(regions),
                'pending_frames':self._pending_count, 'required_frames':required if topology else 0,
                'status':'AMBIGUOUS_THIN_BRIDGE' if ambiguous else ('PENDING_TOPOLOGY' if topology and not commit else 'TRACKING'),
                'proximity':segmentation.proximity, 'color_conflict_pixels':segmentation.conflict_pixels}

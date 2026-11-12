"""Hardware-free input boundary and safety state machine for future capture glue."""
from copy import deepcopy
import cv2
import numpy as np
from .material_replay import MaterialReplayExporter

class CalibratedMaterialSource:
    def __init__(self,mapper=None,hz=30,empty_confirmation=3,*,config=None,settings=None):
        if type(empty_confirmation) is not int or empty_confirmation<3:raise ValueError('empty_confirmation')
        self.mapper=mapper;self.exporter=MaterialReplayExporter(hz,config=config,settings=settings);self.hz=hz
        self.empty_confirmation=empty_confirmation;self.empty_count=0;self.sequence=0
        self.last=dict(structures=[],identity_epochs={},region_identity_epochs={},events=[],material_events=[])
    def fault(self,state,reason):
        self.empty_count=0
        frame=deepcopy(self.last)
        frame.update(sequence=self.sequence,logical_time=(self.sequence-1)/self.hz,scene_state=state,empty_confirmed=False,events=[],material_events=[],diagnostic=dict(status='ERROR' if state=='SCENE_ERROR' else 'HELD',reason=reason))
        return frame
    def update(self,image=None,health='OK'):
        self.sequence+=1
        if health in ('DISCONNECTED','ERROR'):return self.fault('SCENE_ERROR','camera_'+health.lower())
        if health=='STALE' or image is None:return self.fault('SCENE_STALE','no_fresh_frame')
        if health!='OK':return self.fault('SCENE_ERROR','unknown_source_health')
        if self.mapper is None:return self.fault('SCENE_ERROR','missing_calibration')
        if not isinstance(image,np.ndarray) or image.dtype!=np.uint8 or image.ndim!=3 or image.shape[2]!=3 or image.size==0:return self.fault('SCENE_ERROR','invalid_image')
        if (image.shape[1],image.shape[0])!=self.mapper.processed_size:return self.fault('SCENE_ERROR','incompatible_frame_resolution')
        try:
            raw=self.exporter.append_image(image)
            # Reuse exporter epochs/tracker without accumulating an offline movie
            # in a future long-running source. The caller may record explicitly.
            self.exporter.frames.clear()
            if raw['diagnostic']['status']=='REJECTED':return self.fault('SCENE_ERROR','segmentation_rejected')
            segmentation=self.exporter.pipeline.last_segmentation
            if segmentation is not None and segmentation.conflict_pixels:
                return self.fault('SCENE_STALE','ambiguous_color_classification')
            if raw['diagnostic']['status']!='TRACKING':return self.fault('SCENE_STALE','unconfirmed_tracking')
            frame=self.mapper.map_frame(raw)
            if not frame['structures']:
                self.empty_count=min(self.empty_confirmation,self.empty_count+1)
                if self.empty_count<self.empty_confirmation:return self.fault_pending_empty()
            else:self.empty_count=0
            frame.update(sequence=self.sequence,logical_time=(self.sequence-1)/self.hz,scene_state='SCENE_ACTIVE' if frame['structures'] else 'SCENE_EMPTY',empty_confirmed=not frame['structures'])
            self.last=deepcopy(frame)
            return frame
        except (ValueError,TypeError,KeyError,cv2.error) as e:return self.fault('SCENE_ERROR',str(e))
    def fault_pending_empty(self):
        # Preserve evidence count, unlike faults which break consecutiveness.
        count=self.empty_count;frame=self.fault('SCENE_STALE','confirming_empty');self.empty_count=count;return frame
    @staticmethod
    def message(session,frame):
        # STALE is a receiver timeout in wire v2, not a new wire message type.
        if frame['scene_state']=='SCENE_STALE':return None
        message=session.snapshot(frame,start=session.sequence%30==0,error=frame['diagnostic'].get('reason','processing_error') if frame['scene_state']=='SCENE_ERROR' else None)
        if frame['scene_state']=='SCENE_ERROR':message['empty_confirmed']=False
        return message

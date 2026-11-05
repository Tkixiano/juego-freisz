"""Validated planar camera-pixel -> game projection-pixel calibration.

All errors are measured in the logical 1280x720 projection canvas, not native
HDMI pixels. Hold-out markers never participate in fitting the homography.
"""
from dataclasses import dataclass
from datetime import datetime, timezone
import json
import math
from pathlib import Path
import cv2
import numpy as np

PROJECTION_SIZE = (1280,720)
FIT_IDS = (10,11,12,13)
CHECK_IDS = (14,15,16,17)
CENTERS = {10:(180,140),11:(1100,140),12:(1100,580),13:(180,580),
           14:(640,230),15:(880,360),16:(640,490),17:(400,360)}
PATTERN_ID = "arena-1280x720-aruco4x4-v1"


def points(value, size, minimum=4):
    array = np.asarray(value,dtype=np.float64)
    if array.ndim != 2 or array.shape[1] != 2 or len(array)<minimum or not np.isfinite(array).all():
        raise ValueError("Insufficient or invalid correspondences")
    if len(np.unique(array,axis=0)) != len(array):
        raise ValueError("Repeated correspondence")
    if np.any(array<0) or np.any(array>np.asarray(size)-1):
        raise ValueError("Correspondence outside image")
    return array


def resolution(value):
    if not isinstance(value,(tuple,list)) or len(value)!=2 or any(type(v) is not int or not 100<=v<=8192 for v in value):
        raise ValueError("Invalid resolution")
    return tuple(value)


def transform(matrix, pts):
    pts = np.asarray(pts,dtype=np.float64).reshape(-1,2)
    denominator = pts @ matrix[2,:2]+matrix[2,2]
    if np.any(np.abs(denominator)<1e-8):
        raise ValueError("Homography crosses infinity")
    result = cv2.perspectiveTransform(pts.reshape(-1,1,2),matrix).reshape(-1,2)
    if not np.isfinite(result).all():
        raise ValueError("Nonfinite projected point")
    return result


@dataclass
class ProjectionCalibration:
    matrix: np.ndarray
    capture_size: tuple[int,int]
    projection_size: tuple[int,int]
    fit_camera: np.ndarray
    fit_projection: np.ndarray
    check_camera: np.ndarray
    check_projection: np.ndarray
    mirror: bool
    camera_index: int
    backend: str
    created_utc: str
    errors: dict

    @classmethod
    def fit(cls, camera, projected, checks_camera, checks_projected, capture_size,
            projection_size=PROJECTION_SIZE, mirror=False, camera_index=0, backend="dshow"):
        capture_size, projection_size = resolution(capture_size), resolution(projection_size)
        source, target = points(camera,capture_size),points(projected,projection_size)
        check_source, check_target = points(checks_camera,capture_size),points(checks_projected,projection_size)
        if len(source)!=len(target) or len(check_source)!=len(check_target):
            raise ValueError("Correspondence counts differ")
        for a, b in ((source,check_source),(target,check_target)):
            if any(np.linalg.norm(p-q)<2 for p in a for q in b):
                raise ValueError("Verification points must be independent of fit points")
        matrix, inliers = cv2.findHomography(source,target,cv2.RANSAC,2.0)
        if matrix is None or inliers is None or not inliers.all():
            raise ValueError("Inconsistent fitting correspondences")
        calibration = cls(matrix,capture_size,projection_size,source,target,check_source,check_target,
                          mirror,camera_index,backend,datetime.now(timezone.utc).isoformat(),{})
        calibration.validate()
        return calibration

    def validate(self):
        self.capture_size, self.projection_size = resolution(self.capture_size),resolution(self.projection_size)
        if type(self.mirror) is not bool or type(self.camera_index) is not int or not 0<=self.camera_index<=32 or self.backend not in ("dshow","msmf","auto"):
            raise ValueError("Invalid camera identity")
        datetime.fromisoformat(self.created_utc)
        for attr,size in (("fit_camera",self.capture_size),("fit_projection",self.projection_size),
                          ("check_camera",self.capture_size),("check_projection",self.projection_size)):
            setattr(self,attr,points(getattr(self,attr),size))
        if len(self.fit_camera)!=len(self.fit_projection) or len(self.check_camera)!=len(self.check_projection):
            raise ValueError("Correspondence counts differ")
        for a,b in ((self.fit_camera,self.check_camera),(self.fit_projection,self.check_projection)):
            if any(np.linalg.norm(p-q)<2 for p in a for q in b):
                raise ValueError("Verification points are not independent")
        for values,size in ((self.fit_camera,self.capture_size),(self.fit_projection,self.projection_size)):
            hull = cv2.convexHull(values.astype(np.float32))
            if cv2.contourArea(hull)<size[0]*size[1]*.08:
                raise ValueError("Poor spatial distribution of fitting points")
        # Hold-outs must span a meaningful area and be inside the fitted region.
        for check,fit,size in ((self.check_camera,self.fit_camera,self.capture_size),
                               (self.check_projection,self.fit_projection,self.projection_size)):
            if cv2.contourArea(cv2.convexHull(check.astype(np.float32)))<size[0]*size[1]*.01:
                raise ValueError("Poor verification point distribution")
            hull = cv2.convexHull(fit.astype(np.float32))
            if any(cv2.pointPolygonTest(hull,tuple(p),False)<0 for p in check):
                raise ValueError("Verification point outside calibrated area")
        matrix = np.asarray(self.matrix,dtype=np.float64)
        if matrix.shape!=(3,3) or not np.isfinite(matrix).all() or abs(matrix[2,2])<1e-10:
            raise ValueError("Invalid homography matrix")
        matrix = matrix/matrix[2,2]
        if abs(np.linalg.det(matrix))<1e-10 or np.linalg.cond(matrix)>1e9:
            raise ValueError("Degenerate/ill-conditioned homography")
        self.matrix = matrix
        hull = cv2.convexHull(self.fit_camera.astype(np.float32)).reshape(-1,2)
        denominators = hull @ matrix[2,:2]+matrix[2,2]
        if np.any(np.abs(denominators)<1e-5) or np.any(np.sign(denominators)!=np.sign(denominators[0])):
            raise ValueError("Homography horizon crosses calibrated area")
        # Rotations are valid. Reflection requires the explicit mirrored
        # capture setting, so a swapped correspondence cannot silently flip X.
        for p in np.vstack((self.fit_camera,self.check_camera)):
            probe = transform(matrix,[p,p+[.1,0],p+[0,.1]])
            determinant = np.linalg.det(np.stack((probe[1]-probe[0],probe[2]-probe[0])))
            expected_sign = -1 if self.mirror else 1
            if determinant*expected_sign<=1e-10:
                raise ValueError("Reversed or collapsed coordinate axes")
        fit_errors = np.linalg.norm(transform(matrix,self.fit_camera)-self.fit_projection,axis=1)
        check_errors = np.linalg.norm(transform(matrix,self.check_camera)-self.check_projection,axis=1)
        self.errors = {"fit_rms_px":float(np.sqrt(np.mean(fit_errors**2))),"fit_max_px":float(fit_errors.max()),
                       "check_rms_px":float(np.sqrt(np.mean(check_errors**2))),"check_max_px":float(check_errors.max()),
                       "check_each_px":check_errors.tolist(),"units":"logical_projection_pixels"}
        if self.errors["fit_max_px"]>3 or self.errors["check_max_px"]>4 or self.errors["check_rms_px"]>3:
            raise ValueError(f"Reprojection error too high: {self.errors}")
        return self

    def compatible(self,capture_size,mirror,camera_index,backend,projection_size=PROJECTION_SIZE):
        if (resolution(capture_size),mirror,camera_index,backend,resolution(projection_size)) != (self.capture_size,self.mirror,self.camera_index,self.backend,self.projection_size):
            raise ValueError("Calibration incompatible with resolution/camera/backend/mirror; recalibrate")

    def contains(self,point):
        return cv2.pointPolygonTest(cv2.convexHull(self.fit_camera.astype(np.float32)),tuple(map(float,point)),False)>=0

    def map_pose(self,x,y,angle):
        center = np.array([x*(self.capture_size[0]-1),y*(self.capture_size[1]-1)])
        if not np.isfinite([*center,angle]).all() or not self.contains(center):
            raise ValueError("Module outside calibrated camera area")
        radians = math.radians(angle)
        direction = np.array([math.cos(radians),math.sin(radians)])
        # Local tangent via two symmetric close points; projective maps send
        # lines to lines, preserving the correct direction at this center.
        projected = transform(self.matrix,[center,center-direction*.5,center+direction*.5])
        point = projected[0]
        hull = cv2.convexHull(self.fit_projection.astype(np.float32))
        if cv2.pointPolygonTest(hull,tuple(point),False)<-1e-4 or np.any(point<0) or np.any(point>np.asarray(self.projection_size)-1):
            raise ValueError("Module outside calibrated projection area")
        axis = projected[2]-projected[1]
        if np.linalg.norm(axis)<1e-8:
            raise ValueError("Collapsed orientation")
        return float(point[0]/(self.projection_size[0]-1)),float(point[1]/(self.projection_size[1]-1)),math.degrees(math.atan2(axis[1],axis[0]))

    def map_modules(self,modules):
        result, rejected = [], []
        for module in modules:
            mapped = module.copy()
            try:
                mapped["x"],mapped["y"],mapped["angle"] = self.map_pose(module["x"],module["y"],module["angle"])
            except ValueError as error:
                # Never reuse camera coordinates in a PROJECTOR packet.
                mapped.update(x=0.0,y=0.0,angle=0.0,visible=False)
                rejected.append({"id":module["id"],"reason":str(error)})
            result.append(mapped)
        return result,rejected

    def save(self,path):
        self.validate()
        data = {"version":1,"pattern":PATTERN_ID,"capture_resolution":self.capture_size,
                "projection_resolution":self.projection_size,"homography":self.matrix.tolist(),
                "fit_camera":self.fit_camera.tolist(),"fit_projection":self.fit_projection.tolist(),
                "check_camera":self.check_camera.tolist(),"check_projection":self.check_projection.tolist(),
                "mirror":self.mirror,"camera_index":self.camera_index,"backend":self.backend,
                "created_utc":self.created_utc,"errors":self.errors}
        path = Path(path)
        path.parent.mkdir(parents=True,exist_ok=True)
        temporary = path.with_suffix(path.suffix+".tmp")
        temporary.write_text(json.dumps(data,indent=2,allow_nan=False),encoding="utf-8")
        temporary.replace(path)

    @classmethod
    def load(cls,path):
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
            if data["version"]!=1 or data["pattern"]!=PATTERN_ID:
                raise ValueError("Unknown calibration format/pattern")
            return cls(np.asarray(data["homography"],np.float64),tuple(data["capture_resolution"]),
                       tuple(data["projection_resolution"]),np.asarray(data["fit_camera"]),np.asarray(data["fit_projection"]),
                       np.asarray(data["check_camera"]),np.asarray(data["check_projection"]),data["mirror"],
                       data["camera_index"],data["backend"],data["created_utc"],{}).validate()
        except (KeyError,TypeError,cv2.error,OverflowError) as error:
            raise ValueError(f"Invalid calibration file: {error}") from error

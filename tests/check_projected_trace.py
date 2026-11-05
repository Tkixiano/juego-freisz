"""Compare actual Godot applications to sent poses and camera tracked centers."""
import json
import math
from pathlib import Path
from vision.projection import ProjectionCalibration


def main():
    events=[json.loads(line) for line in Path("artifacts/projected_vision_trace.jsonl").read_text().splitlines()]
    frames={row["frame"]:row for row in events if row["event"]=="observation"}
    packets={row["sequence"]:row for row in events if row["event"]=="udp_sent"}
    applied=json.loads(Path("juegofrei/validation/projected_vision_applications.json").read_text())
    calibration=ProjectionCalibration.load(Path("artifacts/synthetic_projection_calibration.json"))
    max_position_error=max_angle_error=0
    assert applied["coordinate_space"]=="PROJECTOR" and len(applied["trace"])>=50
    for entry in applied["trace"]:
        packet=packets[entry["sequence"]]
        assert entry["coordinate_space"]==packet["coordinate_space"]=="PROJECTOR"
        module=next(m for m in packet["modules"] if m["id"]==entry["wire_id"])
        assert module["visible"] and entry["platform"]=={1:"left",2:"right"}[module["id"]]
        camera_center=frames[packet["source_frame"]]["tracks"][str(module["id"])]["center"]
        x,y,_=calibration.map_pose(*camera_center,0)
        assert abs(x-module["x"])<1e-6 and abs(y-module["y"])<1e-6
        error=math.hypot(entry["target_x"]-module["x"]*1279,entry["target_y"]-module["y"]*719)
        angular=abs((entry["angle_degrees"]-module["angle"]+180)%360-180)
        assert error<.351 and angular<.151
        max_position_error=max(max_position_error,error)
        max_angle_error=max(max_angle_error,angular)
    report={"passed":True,"checked_applications":len(applied["trace"]),"max_position_error_px":max_position_error,
            "max_angle_error_degrees":max_angle_error,"checks":["camera_center_to_homography_once","wire_to_fixed_platform_id","projected_angle_to_godot","bounded_deadband_only"]}
    Path("artifacts/projected_trace_results.json").write_text(json.dumps(report,indent=2),encoding="utf-8")
    print(json.dumps(report))


if __name__=="__main__": main()

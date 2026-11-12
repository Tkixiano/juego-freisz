"""Real OpenCV trackbars + synthetic ROI/file roundtrip. No capture or sockets."""
import json
from pathlib import Path
import cv2
from vision.material_lab import MaterialCalibration
from vision.material_config import MaterialConfig,save_materials,load_materials
from vision.material_synthetic import three,bgr
from vision.calibration import sample_hsv

def main():
    path=Path('artifacts/phase3b1/gui_profile.json');config=MaterialConfig();save_materials(config,path)
    legacy=Path('vision/config.json').read_bytes();rows=[]
    def check(name,condition):
        rows.append(dict(name=name,passed=bool(condition)))
        if not condition:raise AssertionError(name)
    ui=MaterialCalibration(config,path)
    try:
        image=bgr(three());ui.image=image;cv2.imshow(ui.CAMERA,image);cv2.waitKey(100)
        ui.key(ord('3'));check('select_orange',ui.selected==3)
        cv2.setTrackbarPos('H min',ui.SLIDERS,8);ui.read();ui.key(ord('s'))
        saved=load_materials(path);check('orange_saved',saved.colors[2].lower[0]==8)
        check('green_preserved',saved.colors[0].lower==[35,90,55]);check('blue_preserved',saved.colors[1].lower==[95,100,55])
        ui.key(ord('1'));cv2.setTrackbarPos('H min',ui.SLIDERS,40);ui.read();ui.key(ord('s'))
        saved=load_materials(path);check('green_saved_independently',saved.colors[0].lower[0]==40)
        check('orange_preserved',saved.colors[2].lower[0]==8)
        ui.key(ord('2'));check('select_blue',ui.selected==2)
        ui.key(ord('3'));ui.sample=sample_hsv(image,(180,80),(220,110));ui.sample_id=3
        check('sample_not_auto_applied',config.colors[2].lower[0]==8)
        ui.key(ord('a'));check('explicit_sample_applied',config.colors[2].lower==ui.sample['suggested_lower'])
        ui.key(ord('s'));ui.key(ord('l'));check('load_saved_profile',ui.config.colors[2].lower==ui.sample['suggested_lower'])
        check('legacy_file_unchanged',Path('vision/config.json').read_bytes()==legacy)
        check('quit_action',ui.key(ord('q'))=='quit')
    finally:cv2.destroyAllWindows()
    Path('artifacts/phase3b1/gui_smoke.json').write_text(json.dumps(dict(passed=len(rows),total=len(rows),rows=rows),indent=2),encoding='utf-8')
    print(json.dumps(dict(passed=len(rows),total=len(rows))))

if __name__=='__main__':main()

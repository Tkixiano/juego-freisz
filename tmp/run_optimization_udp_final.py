import subprocess,json,shutil,time,sys
from pathlib import Path
r=Path(__file__).resolve().parents[1];out=r/'artifacts/optimization';binary='C:/godot 4.6/Godot_v4.6.3-stable_win64_console.exe'
for count in [1,4,8,16,32,64]:
 name='udp_regions'+str(count)
 with (out/(name+'.txt')).open('w') as f:p=subprocess.run([binary,'--headless','--path',str(r/'juegofrei'),'--script','res://validation/UdpMatchLiveHeadless.gd','--log-file',str(out/(name+'_engine.log')),'--','load','regions'+str(count)],stdout=f,stderr=subprocess.STDOUT,timeout=120)
 shutil.copyfile(r/'juegofrei/validation/udp_match_live_load.json',out/(name+'.json'))
 shutil.copyfile(r/'artifacts/phase3d/live_load_sender.json',out/(name+'_sender.json'))
 print(name,p.returncode,flush=True)

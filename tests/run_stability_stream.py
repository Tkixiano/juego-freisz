"""Two independent detector starts with real image occlusions and a stop gap."""
from pathlib import Path
import json
import subprocess
import sys
import time

def main():
    records=[]
    for index in (1,2):
        command=[sys.executable,"detector.py","--synthetic","--scenario","occlusion","--no-gui","--duration","9","--report",f"artifacts/stability_sender{index}.json"]
        with Path(f"artifacts/stability_sender{index}.log").open("w",encoding="utf-8") as log:
            result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=20)
        records.append({"start":index,"exit_code":result.returncode})
        if index==1:
            time.sleep(2)
    Path("artifacts/stability_restarts.json").write_text(json.dumps(records,indent=2),encoding="utf-8")
    return 0 if all(item["exit_code"]==0 for item in records) else 1

if __name__ == "__main__":
    raise SystemExit(main())

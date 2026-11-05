@echo off
cd /d "%~dp0"
if exist ".venv\Scripts\python.exe" (
    ".venv\Scripts\python.exe" -m vision.projector_calibration %*
) else (
    python -m vision.projector_calibration %*
)
pause

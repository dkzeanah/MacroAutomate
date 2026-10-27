@echo off
REM Harness Studio -- the unified GUI over Atlas, SideLearner, Creator Ops and OJAS.
setlocal
cd /d "%~dp0"

set PY=python
if exist ".venv\Scripts\python.exe" set PY=.venv\Scripts\python.exe

echo Starting Harness Studio...
"%PY%" -m studio.app "%CD%"
if errorlevel 1 (
  echo.
  echo Studio exited with an error. Run this to see the details:
  echo    "%PY%" -m studio.app "%CD%"
  pause
)
endlocal

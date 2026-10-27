@echo off
REM atlas -- the Context Map CLI. Pass any subcommand through, e.g.:
REM   Atlas.bat find "retry with backoff"
REM   Atlas.bat get @agent/sidelearner:utils.py#bounded_retry
REM   Atlas.bat gate my_new_thing --lines 20 --bucket agent
setlocal
cd /d "%~dp0"

set PY=python
if exist ".venv\Scripts\python.exe" set PY=.venv\Scripts\python.exe

if "%~1"=="" (
  "%PY%" -m atlas.cli --workspace "%CD%" --help
  echo.
  pause
  exit /b 0
)

"%PY%" -m atlas.cli --workspace "%CD%" %*
endlocal

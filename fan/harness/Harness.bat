@echo off
REM ===========================================================================
REM  Harness Studio - the single entry point for this workspace.
REM
REM    Harness.bat                   open the GUI (everything is reachable there)
REM    Harness.bat atlas <command>   run the Atlas CLI instead
REM    Harness.bat run "<name>"      run one absorbed tool by name
REM    Harness.bat index             re-index this workspace's own parts
REM    Harness.bat test              run the test suite
REM    Harness.bat help              list the CLI commands
REM
REM  Every other launcher this project used to have is now a tab or an entity
REM  inside the GUI. The old .bat files are kept in legacy\launchers\.
REM ===========================================================================
setlocal
cd /d "%~dp0"

set "PY=python"
if exist ".venv\Scripts\python.exe" set "PY=.venv\Scripts\python.exe"

"%PY%" -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)" 2>nul
if errorlevel 1 (
  echo.
  echo   Python 3.10 or newer is required, and "%PY%" is not it.
  echo   Install Python, or create a virtual environment here:
  echo.
  echo       python -m venv .venv
  echo.
  pause
  exit /b 1
)

set "PYTHONUTF8=1"
set "PYTHONIOENCODING=utf-8"

if "%~1"=="" goto :gui
if /i "%~1"=="gui"   goto :gui
if /i "%~1"=="help"  goto :help
if /i "%~1"=="test"  goto :test
if /i "%~1"=="index" goto :reindex
if /i "%~1"=="atlas" goto :atlas
if /i "%~1"=="run"   goto :run
goto :passthrough

:gui
echo Starting Harness Studio...
"%PY%" -m studio.app "%CD%"
if errorlevel 1 (
  echo.
  echo   Studio exited with an error. To see the details, run:
  echo       "%PY%" -m studio.app "%CD%"
  echo.
  pause
  exit /b 1
)
exit /b 0

:atlas
shift
"%PY%" -m atlas.cli --workspace "%CD%" %1 %2 %3 %4 %5 %6 %7 %8 %9
exit /b %ERRORLEVEL%

:run
shift
"%PY%" -m atlas.cli --workspace "%CD%" run %1 %2 %3 %4 %5 %6 %7 %8
exit /b %ERRORLEVEL%

:reindex
"%PY%" bootstrap_index.py
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%

:test
"%PY%" -m pytest tests/ -q
set "RC=%ERRORLEVEL%"
echo.
pause
exit /b %RC%

:help
"%PY%" -m atlas.cli --workspace "%CD%" --help
echo.
echo   Harness.bat with no arguments opens the GUI, where all of this has a tab.
echo.
pause
exit /b 0

:passthrough
REM Anything unrecognised goes straight to the Atlas CLI.
"%PY%" -m atlas.cli --workspace "%CD%" %*
exit /b %ERRORLEVEL%

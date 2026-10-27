@echo off
setlocal EnableExtensions
title SideLearner - Start
rem ===========================================================================
rem  StartSideLearner.bat
rem  Starts the hidden background daemon (perception + digital-twin learning +
rem  autonomy) and the optional web dashboard in one step.
rem
rem  Background learning is exactly what `daemon start` launches: it spawns
rem  `pythonw.exe -m sidelearner.cli run --daemon-child`, which runs the
rem  always-on watchers (screen / window / desktop audio), the observation
rem  ledger, the fact compressor, and the self-directed autonomy loop.
rem ===========================================================================
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [SideLearner] ERROR: .venv not found.
    echo               Run SideLearner.bat once to create it, then retry.
    pause
    exit /b 1
)

set "PY=.venv\Scripts\python.exe"

echo.
echo [SideLearner] Starting background learning daemon...
"%PY%" -m sidelearner.cli daemon start

echo.
echo [SideLearner] Starting web dashboard...
"%PY%" -m sidelearner.cli web start

echo.
echo [SideLearner] Current state:
"%PY%" -m sidelearner.cli daemon status
"%PY%" -m sidelearner.cli web status

echo.
echo   Dashboard: http://127.0.0.1:8080
echo   Live log:  "%PY%" -m sidelearner.cli daemon logs
echo   Learned:   "%PY%" -m sidelearner.cli twin status
echo.
echo   To stop:   StopSideLearner.bat
echo.
pause
exit /b 0

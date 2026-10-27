@echo off
setlocal EnableExtensions
title SideLearner - Stop
rem ===========================================================================
rem  StopSideLearner.bat
rem  Stops the web dashboard and the hidden background daemon in one step.
rem ===========================================================================
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo [SideLearner] ERROR: .venv not found.
    pause
    exit /b 1
)

set "PY=.venv\Scripts\python.exe"

echo.
echo [SideLearner] Stopping web dashboard...
"%PY%" -m sidelearner.cli web stop

echo.
echo [SideLearner] Stopping background learning daemon...
"%PY%" -m sidelearner.cli daemon stop

echo.
echo [SideLearner] Done.
pause
exit /b 0

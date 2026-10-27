@echo off
setlocal EnableExtensions
title SideLearner
rem ===========================================================================
rem  SideLearner launcher - self-contained.
rem   * Double-click (no arguments): operator menu.
rem   * From a terminal:  SideLearner.bat <command> [args]  (passes through)
rem   * First run: creates .venv and installs dependencies automatically.
rem ===========================================================================
cd /d "%~dp0"

rem ---- locate / bootstrap the Python environment -----------------------------
if exist ".venv\Scripts\python.exe" goto :have_py

echo [SideLearner] First run: creating virtual environment (one time only)...
where py >nul 2>nul
if %ERRORLEVEL%==0 (
    py -3.11 -m venv .venv
) else (
    python -m venv .venv
)
if errorlevel 1 (
    echo [SideLearner] ERROR: could not create .venv - install Python 3.10+ first.
    pause
    exit /b 1
)
call ".venv\Scripts\python.exe" -m pip install --quiet --upgrade pip
call ".venv\Scripts\python.exe" -m pip install --quiet -e ".[full,dev]"
if errorlevel 1 (
    echo [SideLearner] ERROR: dependency install failed - see the pip output above.
    pause
    exit /b 1
)
echo [SideLearner] Setup complete.

:have_py
set "PY=.venv\Scripts\python.exe"

rem ---- no arguments -> operator menu -----------------------------------------
if "%~1"=="" goto :menu

rem ---- pass-through ----------------------------------------------------------
"%PY%" -m sidelearner.cli %*
exit /b %ERRORLEVEL%

:menu
echo.
echo  ================== SideLearner ==================
echo   1. Start learning in the background   (daemon start)
echo   2. Daemon status                      (daemon status)
echo   3. Watch the log                      (daemon logs)
echo   4. What it has learned                (twin status)
echo   5. Open questions                     (prompts)
echo   6. First-time setup                   (onboard)
echo   7. Give it a task                     (chat)
echo   8. Open web dashboard                 (web start)
echo   0. Exit
echo  =================================================
echo.
set "choice="
set /p choice="  Choice: "
if "%choice%"=="" exit /b 0
if "%choice%"=="0" exit /b 0
if "%choice%"=="1" (
    "%PY%" -m sidelearner.cli daemon start
    goto :done
)
if "%choice%"=="2" (
    "%PY%" -m sidelearner.cli daemon status
    goto :done
)
if "%choice%"=="3" (
    "%PY%" -m sidelearner.cli daemon logs
    goto :done
)
if "%choice%"=="4" (
    "%PY%" -m sidelearner.cli twin status
    goto :done
)
if "%choice%"=="5" (
    "%PY%" -m sidelearner.cli prompts
    goto :done
)
if "%choice%"=="6" (
    "%PY%" -m sidelearner.cli onboard
    goto :done
)
if "%choice%"=="7" (
    set "task="
    set /p task="  Task: "
    if not "%task%"=="" "%PY%" -m sidelearner.cli chat "%task%"
    goto :done
)
if "%choice%"=="8" (
    "%PY%" -m sidelearner.cli web start
    echo   Dashboard: http://127.0.0.1:8080
    goto :done
)
goto :menu

:done
echo.
pause
exit /b %ERRORLEVEL%

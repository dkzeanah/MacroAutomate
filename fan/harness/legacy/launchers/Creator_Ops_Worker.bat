@echo off
setlocal
set "WORKER_FILE=%~dp0creator_ops_worker.py"
set "PYTHON="

if exist "%~dp0..\..\.venv\Scripts\python.exe" set "PYTHON=%~dp0..\..\.venv\Scripts\python.exe"
if not defined PYTHON if exist "%~dp0..\..\..\a-llm-harness-custom\.venv\Scripts\python.exe" set "PYTHON=%~dp0..\..\..\a-llm-harness-custom\.venv\Scripts\python.exe"
if not defined PYTHON for /f "delims=" %%P in ('where python.exe 2^>nul') do if not defined PYTHON set "PYTHON=%%P"
if not defined PYTHON for /d %%D in ("%LOCALAPPDATA%\Python\pythoncore-*") do if exist "%%~fD\python.exe" if not defined PYTHON set "PYTHON=%%~fD\python.exe"

if not defined PYTHON (
  echo Python 3.11 or newer was not found.
  exit /b 1
)

"%PYTHON%" -B "%WORKER_FILE%"
exit /b %errorlevel%

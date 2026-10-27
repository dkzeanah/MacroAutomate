@echo off
REM Open the separate Python toolkit under fan; Macro Automator is not required.
setlocal
cd /d "%~dp0harness"
".venv\Scripts\pythonw.exe" launch_studio.py --tab index

@echo off
REM Open the Macro Automator and its evidence-based Learning Workbench.
setlocal
set "FAN_AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%FAN_AHK%" (
  echo AutoHotkey v2 is required to run the Macro Automator.
  exit /b 1
)
start "" "%FAN_AHK%" "%~dp0MacroAutomator.ahk" --learning-workbench

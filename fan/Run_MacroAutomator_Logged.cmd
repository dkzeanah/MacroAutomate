@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK_EXE%" set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
rem The multi-file build shares the original project's data folder (see README.md).
if not exist "%SCRIPT_DIR%..\data\logs" mkdir "%SCRIPT_DIR%..\data\logs"
start "" /b "%AHK_EXE%" /ErrorStdOut=UTF-8 "%SCRIPT_DIR%MacroAutomator.ahk" >> "%SCRIPT_DIR%..\data\logs\macroautomaterv9_fan_startup.log" 2>&1
endlocal

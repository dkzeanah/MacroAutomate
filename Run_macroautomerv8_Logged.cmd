@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK_EXE%" set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
if not exist "%SCRIPT_DIR%data\logs" mkdir "%SCRIPT_DIR%data\logs"
start "" /b "%AHK_EXE%" /ErrorStdOut=UTF-8 "%SCRIPT_DIR%macroautomerv8.ahk" >> "%SCRIPT_DIR%data\logs\macroautomerv8_startup.log" 2>&1
endlocal

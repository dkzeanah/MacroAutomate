@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK_EXE%" set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
if not exist "%SCRIPT_DIR%logs" mkdir "%SCRIPT_DIR%logs"
start "" /b "%AHK_EXE%" /ErrorStdOut=UTF-8 "%SCRIPT_DIR%macroautomerv7.ahk" >> "%SCRIPT_DIR%logs\macroautomerv7_startup.log" 2>&1
endlocal

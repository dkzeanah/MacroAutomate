@echo off
setlocal
rem SUNSET REDIRECT: the old single-file v7 app was renamed to
rem macroautomerv7-sunset.ahk. The canonical build is now the /fan multi-file
rem project, so this launcher starts fan\MacroAutomator.ahk. See README.md and
rem fan\README.md. To run the sunset script directly, point AutoHotkey at it.
set "SCRIPT_DIR=%~dp0"
set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe"
if not exist "%AHK_EXE%" set "AHK_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey.exe"
if not exist "%SCRIPT_DIR%data\logs" mkdir "%SCRIPT_DIR%data\logs"
start "" /b "%AHK_EXE%" /ErrorStdOut=UTF-8 "%SCRIPT_DIR%fan\MacroAutomator.ahk" >> "%SCRIPT_DIR%data\logs\macroautomaterv9_fan_startup.log" 2>&1
endlocal

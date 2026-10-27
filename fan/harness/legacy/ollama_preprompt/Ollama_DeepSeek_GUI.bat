@echo off
setlocal
set "GUI=%~dp0ollama_preprompt_gui.pyw"
set "PYTHONW="

if exist "%~dp0..\..\.venv\Scripts\pythonw.exe" set "PYTHONW=%~dp0..\..\.venv\Scripts\pythonw.exe"
if not defined PYTHONW if exist "%~dp0..\..\..\a-llm-harness-custom\.venv\Scripts\pythonw.exe" set "PYTHONW=%~dp0..\..\..\a-llm-harness-custom\.venv\Scripts\pythonw.exe"

if not defined PYTHONW for /f "delims=" %%P in ('where pythonw.exe 2^>nul') do if not defined PYTHONW set "PYTHONW=%%P"
if not defined PYTHONW for /f "delims=" %%P in ('where pyw.exe 2^>nul') do if not defined PYTHONW set "PYTHONW=%%P"
if not defined PYTHONW for /d %%D in ("%LOCALAPPDATA%\Python\pythoncore-*") do if exist "%%~fD\pythonw.exe" if not defined PYTHONW set "PYTHONW=%%~fD\pythonw.exe"

if not defined PYTHONW (
  powershell.exe -NoProfile -WindowStyle Hidden -Command "Add-Type -AssemblyName PresentationFramework; [System.Windows.MessageBox]::Show('Python with Tkinter was not found. Install desktop Python 3.10 or newer, then open this launcher again.','Ollama to DeepSeek Harness') | Out-Null"
  exit /b 1
)

start "" "%PYTHONW%" "%GUI%"
exit /b 0

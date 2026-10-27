#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# run_fan.sh - Git Bash-safe launcher for the /fan Macro Automator build.
#
# Why this file exists: Git Bash's MSYS layer rewrites arguments that look like
# POSIX paths. "/ErrorStdOut" becomes "C:/Program Files/Git/ErrorStd..." and
# AutoHotkey then tries to load that as a script ("Script file not found").
# MSYS2_ARG_CONV_EXCL disables native argument conversion for this launch.
#
# Usage (from a Git Bash terminal):
#   sh fan/run_fan.sh
# Or from cmd/PowerShell use the .cmd instead:
#   fan\Run_MacroAutomator_Logged.cmd
#
# Each launch writes its own timestamped startup log (the running instance holds
# its log file open, so a fixed name would hit a Windows file lock).
# ═══════════════════════════════════════════════════════════════════════════════
cd "$(dirname "$0")/.." || exit 1

AHK_EXE="C:/Program Files/AutoHotkey/v2/AutoHotkey64.exe"
if [ ! -f "$AHK_EXE" ]; then
  AHK_EXE="C:/Program Files/AutoHotkey/v2/AutoHotkey.exe"
fi
if [ ! -f "$AHK_EXE" ]; then
  echo "AutoHotkey v2 was not found under C:/Program Files/AutoHotkey/v2." >&2
  exit 1
fi
AHK_SCRIPT=$(cygpath -m "$(pwd)/fan/MacroAutomator.ahk") || exit 1

# Validate through the same native argument path without launching the app.
if [ "${1:-}" = "--validate" ]; then
  MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$AHK_EXE" /ErrorStdOut=UTF-8 /validate "$AHK_SCRIPT"
  exit $?
fi

mkdir -p data/logs
LOG="data/logs/macroautomaterv9_fan_startup_$(date +%Y%m%d_%H%M%S).log"

echo "Starting: $AHK_EXE fan/MacroAutomator.ahk"
echo "Startup log: $LOG"
MSYS2_ARG_CONV_EXCL='*' MSYS_NO_PATHCONV=1 "$AHK_EXE" /ErrorStdOut=UTF-8 "$AHK_SCRIPT" >> "$LOG" 2>&1 &

; Entry lifecycle: runtime. Included by MacroAutomator.ahk.
; ===============================================================================
; GLOBALS
; ===============================================================================
#Include %A_ScriptDir%\Core\_Globals.ahk

if !DirExist(DATA_DIR)
    DirCreate(DATA_DIR)
if !DirExist(LOG_DIR)
    DirCreate(LOG_DIR)
if !DirExist(PREVIEW_DIR)
    DirCreate(PREVIEW_DIR)
if !DirExist(SCREENSHOTS_DIR)
    DirCreate(SCREENSHOTS_DIR)
; Create notes directory
if !DirExist(NOTES_DIR)
    DirCreate(NOTES_DIR)
; Create tracking output directory
if !DirExist(TRACKING_DIR)
    DirCreate(TRACKING_DIR)

if g_FanSeedPath != "" {
    FanUnified_Seed(g_FanSeedPath)
    ExitApp(0)
}


; Initialize GDI+ for screenshot capture
OnError(FanBoot_Error,0)
OnError(LogUnhandledError)
g_GdipToken := Gdip_Startup()
OnExit(ShutdownGdip)
OnExit(SaveAllOnExit)
; Flush open tracking buckets/sessions and close the tracking DB cleanly.
OnExit(TrackingOnExit)
; Persist study-assistant read-along state (it shares the tracking DB, which
; TrackingOnExit closes, so this must run before that hook - OnExit fires
; handlers last-registered-first, so register it after TrackingOnExit).
OnExit(Study_OnExit)


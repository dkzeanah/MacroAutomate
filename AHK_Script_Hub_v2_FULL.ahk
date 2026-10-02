#Requires AutoHotkey v2.0
#SingleInstance Off

; ============================================================================
; AutoHotkey v2 Script Hub
; ----------------------------------------------------------------------------
; Persistent launcher/history manager for AutoHotkey v2 scripts.
;
; Core behavior:
;   - Runs from Windows Startup.
;   - Detects AutoHotkey v2 scripts launched from Explorer, terminals, editors,
;     other scripts, Startup, etc.
;   - Persists script history and launch counts.
;   - Double-clicking this manager while it is already running opens the GUI.
;   - Double-clicking the tray icon opens the GUI.
;   - Right-clicking the tray icon exposes a live Running Scripts submenu.
;   - Consolidates every visible AutoHotkey v2 tray icon under this one Hub.
;   - Scripts using ScriptHubClient.ahk publish their REAL A_TrayMenu so custom
;     items, submenus, checks/disabled state and standard AHK items are cloned
;     into the Hub and routed back to the owning process by native command ID.
;   - Remembers which scripts were running before shutdown/logoff and restores
;     the same number of instances after the next login.
;   - Uses the current v2 interpreter (A_AhkPath) for launches.
;
; Data:
;   %AppData%\AHKScriptHub\scripts.tsv
;   %AppData%\AHKScriptHub\running_snapshot.tsv
;   %AppData%\AHKScriptHub\activity.log
; ============================================================================

Persistent()
DetectHiddenWindows true
SetTitleMatchMode 2
SetWorkingDir A_ScriptDir

; ------------------------------- CONSTANTS ----------------------------------

global APP_NAME := "AutoHotkey v2 Script Hub"
global APP_WINDOW_TITLE := "AHK Script Hub - AutoHotkey v2"
global APP_VERSION := "1.3.0"

global DATA_DIR := A_AppData "\AHKScriptHub"
global DB_FILE := DATA_DIR "\scripts.tsv"
global DB_BACKUP_FILE := DATA_DIR "\scripts.tsv.bak"
global SNAPSHOT_FILE := DATA_DIR "\running_snapshot.tsv"
global ACTIVITY_LOG := DATA_DIR "\activity.log"
global STARTUP_LINK := A_Startup "\AHK Script Hub.lnk"
global MUTEX_NAME := "Local\AHKScriptHub_v2_Manager_{2BDDD304-77F0-4C54-9C28-EA62355DC519}"

global SCITE_EXE := "C:\Program Files\AutoHotkey\SciTE\SciTE.exe"
global GLOBAL_HOTKEY := "^#a" ; Ctrl+Win+A

global HUB_ICON_FILE := DATA_DIR "\ScriptHub.ico"

; AutoHotkey's own tray icon uses 0x404 both as its notification icon ID and
; callback message. The standard tray command IDs below are stable by design.
global AHK_NOTIFYICON_MSG := 0x0404
global WM_COMMAND_MSG := 0x0111
global WM_LBUTTONDBLCLK_MSG := 0x0203
global WM_RBUTTONUP_MSG := 0x0205

; Cooperative full-tray mirroring IPC. Scripts which include ScriptHubClient.ahk
; publish their real A_TrayMenu tree to this hidden IPC window.
global HUB_IPC_TITLE := "AHK Script Hub IPC {9E10E19C-60E3-4D5A-BE43-4A11C68C76A1}"
global HUB_QUERY_MESSAGE_NAME := "AHKScriptHub.QueryState.{9E10E19C-60E3-4D5A-BE43-4A11C68C76A1}"
global WM_COPYDATA_MSG := 0x004A
global HUB_COPYDATA_MAGIC := 0x53484231 ; "SHB1"

global ID_TRAY_OPEN := 65300
global ID_TRAY_HELP := 65301
global ID_TRAY_WINDOWSPY := 65302
global ID_TRAY_RELOAD := 65303
global ID_TRAY_EDIT := 65304
global ID_TRAY_SUSPEND := 65305
global ID_TRAY_PAUSE := 65306
global ID_TRAY_EXIT := 65307


; ------------------------------- GLOBAL STATE -------------------------------

global gScripts := Map()          ; normalized path key -> record object
global gRunning := Map()          ; PID -> running instance object
global gSeenPids := Map()         ; PID -> normalized path key
global gPrecountedPids := Map()   ; PID -> expiration tick for hub-launched runs
global gBootSnapshot := []        ; array of {Path:path, Count:n} objects
global gRestoreDone := false
global gShutdownInProgress := false
global gWmi := 0
global gWmiSink := 0
global gProcessTraceActive := false
global gSavingDb := false
global gSavingSnapshot := false

; GUI globals.
global gMainGui := 0
global gSearchEdit := 0
global gFilterDDL := 0
global gList := 0
global gStatusText := 0
global gContextMenu := 0
global gContextPath := ""

; Running-script hotkey inspector globals.
global gHotkeyGui := 0
global gHotkeySearchEdit := 0
global gHotkeyList := 0
global gHotkeyStatus := 0
global gHotkeyRows := Map()
global gHotkeyScriptFilter := ""
global gHotkeyContextMenu := 0
global gHotkeyContextRow := 0
global gHotkeyScanCache := []
global gHotkeyScanSignature := ""

; Tray globals.
global gRunningMenu := 0
global gRunningMenuRows := Map()
global gRunningScriptMenus := []
global gRunningNativeMenus := []
global gHubControlMenu := 0
global gTrayConsolidationEnabled := true
global gHiddenTrayIcons := Map() ; PID -> target AHK main HWND hidden by this Hub
global gTaskbarCreatedMsg := 0

; Cooperative mirrored-tray clients.
global gTrayClients := Map()       ; PID -> {PID,Hwnd,Path,Items,LastTick}
global gMirroredMenus := []        ; keep recursively-created Menu objects alive
global gRunningHubToolMenus := []  ; keep per-script Hub management submenus alive
global gIpcGui := 0                ; hidden discoverable GUI used for WM_COPYDATA
global gHubQueryMsg := 0           ; registered message queried by client includes

; Mutex globals.
global gMutexHandle := 0
global gLaunchedFromStartup := HasArg("/startup")
global gRestartRequested := HasArg("/restart")

; ------------------------------ SINGLE INSTANCE -----------------------------
;
; #SingleInstance is intentionally Off because a second invocation is used as
; an "open the already-running hub" signal. A named Windows mutex guarantees
; only one manager owns the trackers/database.

gMutexHandle := DllCall(
    "CreateMutexW",
    "Ptr", 0,
    "Int", 0,
    "Str", MUTEX_NAME,
    "Ptr"
)
mutexError := A_LastError

if (gMutexHandle && mutexError = 183) { ; ERROR_ALREADY_EXISTS
    if gRestartRequested {
        ; A restart helper must wait until the old process releases its mutex
        ; handle. The mutex is used as a named lifetime marker (not locked), so
        ; probe for object disappearance before creating our replacement.
        DllCall("CloseHandle", "Ptr", gMutexHandle)
        gMutexHandle := 0
        Loop 120 {
            probe := DllCall(
                "OpenMutexW",
                "UInt", 0x00100000,
                "Int", 0,
                "Str", MUTEX_NAME,
                "Ptr"
            )
            if !probe
                break
            DllCall("CloseHandle", "Ptr", probe)
            Sleep 100
        }
        gMutexHandle := DllCall(
            "CreateMutexW",
            "Ptr", 0,
            "Int", 0,
            "Str", MUTEX_NAME,
            "Ptr"
        )
        if (!gMutexHandle || A_LastError = 183) {
            if gMutexHandle
                DllCall("CloseHandle", "Ptr", gMutexHandle)
            ExitApp
        }
    } else if !gLaunchedFromStartup {
        ; The first instance can still be constructing its GUI, so look for it
        ; briefly and expose it as soon as its window exists.
        Loop 30 {
            hwnd := WinExist(APP_WINDOW_TITLE " ahk_class AutoHotkeyGUI")
            if hwnd {
                try WinShow("ahk_id " hwnd)
                try WinRestore("ahk_id " hwnd)
                try WinActivate("ahk_id " hwnd)
                break
            }
            Sleep 50
        }
    }

    if !gRestartRequested {
        if gMutexHandle
            DllCall("CloseHandle", "Ptr", gMutexHandle)
        ExitApp
    }
}

; --------------------------------- START ------------------------------------

Main()

; ============================================================================
; INITIALIZATION
; ============================================================================

Main() {
    global gBootSnapshot, gLaunchedFromStartup, gTaskbarCreatedMsg

    EnsureDataDirectory()
    EnsureBridgeClientFile()
    EnsureHubIcon()
    ApplyHubTrayIdentity()
    LoadDatabase()
    gBootSnapshot := LoadRunningSnapshot()

    BuildMainGui()
    BuildContextMenu()
    BuildTrayMenu()
    InitTrayBridge()
    EnsureStartupShortcut()

    ; Ctrl+Win+A summons the hub from anywhere.
    try Hotkey(GLOBAL_HOTKEY, ShowMainGui)

    ; Save the pre-shutdown running state before other AHK scripts begin
    ; receiving shutdown messages and disappearing.
    OnMessage(0x0011, WM_QueryEndSession) ; WM_QUERYENDSESSION
    OnMessage(0x0016, WM_EndSession)      ; WM_ENDSESSION

    ; Explorer broadcasts this after its notification area is rebuilt. Peer AHK
    ; scripts recreate their icons, so the Hub reapplies consolidation shortly
    ; afterward.
    gTaskbarCreatedMsg := DllCall(
        "User32\RegisterWindowMessageW",
        "Str", "TaskbarCreated",
        "UInt"
    )
    if gTaskbarCreatedMsg
        OnMessage(gTaskbarCreatedMsg, HubTaskbarCreated)

    OnExit(AppExit)

    InitWmi()
    StartProcessTrace()

    ; Discover any scripts that were already running before this manager.
    FastWindowScan()
    FullRunningScan()

    ; Fast hidden-main-window watcher plus slower authoritative WMI sweep.
    SetTimer(FastWindowScan, 250)
    SetTimer(FullRunningScan, 1500)

    ; Give Windows Startup a moment to launch anything else, then fill in only
    ; the instances that are still missing from the previous-session snapshot.
    SetTimer(RestorePreviousSession, -1500)

    LogEvent("START", "Hub started. StartupLaunch=" . (gLaunchedFromStartup ? "1" : "0"))

    if !gLaunchedFromStartup
        ShowMainGui()
}

EnsureDataDirectory() {
    if !DirExist(DATA_DIR)
        DirCreate(DATA_DIR)
}

EnsureBridgeClientFile() {
    ; Keep the reusable include at a stable location so every script can use:
    ;   #Include "%A_AppData%\AHKScriptHub\ScriptHubClient.ahk"
    src := A_ScriptDir "\ScriptHubClient.ahk"
    dst := DATA_DIR "\ScriptHubClient.ahk"

    if !FileExist(src)
        return false

    try {
        FileCopy(src, dst, 1)
        return true
    } catch as err {
        LogEvent("ERROR", "Could not install ScriptHubClient.ahk: " err.Message)
        return false
    }
}

EnsureHubIcon() {
    global HUB_ICON_FILE

    if FileExist(HUB_ICON_FILE)
        return true

    b64 := "AAABAAUAEBAAAAAAIADiAgAAVgAAABgYAAAAACAA7QQAADgDAAAgIAAAAAAgAPAGAAAlCAAAMDAAAAAAIAA/CwAAFQ8AAEBAAAAAACAAywIAAFQaAACJUE5H"
    b64 .= "DQoaCgAAAA1JSERSAAAAEAAAABAIBgAAAB/z/2EAAAKpSURBVHicpZNLSFRxFMa//+POvfNwxiZHa0Yz07AWRlkhgQuTImHatiwhykVB5UJ30caVi0oXgUFE"
    b64 .= "bVsFDRhEJtXCyB6ELXyVlZpJjuM4dx73/v+nxThS0Cb6Fmf1nbP4vt8BimL4d7HSYAAIB7sMmUpdEEKe4BwSIChVdApRtGoNVyn3sRsK3cL4bQcAY8A13tCx"
    b64 .= "YnyZWX7ijzW1muFarNsOpOTwmQIAYOcVXFejzGcgtzKHzPyHFzvqI8emh8MOAwDZcOpyWWz/zdCulrzSSt7o2oe3M6vszvBnIgDnOnay5votdGXoPYQQbmp2"
    b64 .= "zEzPv7viTj8Y4ADAuYz7InUapCScnDjSGBSd7VEqFHLCLeTE6bbtdKghIKBygkhJX6ROcy7jAMA38yDNpeDQYIhffam3Bs1MY6xM760JaiGEfbR3lAAOQxS9"
    b64 .= "pdxlab+gNLLpArSrMP89ya/dn7D6OpuyyUyBDT2aNmcXbVYRMpBxHAilN3uTDIB2FKJhL/ovHmZLK+tOtqBdvykwF630TK0p8f31Ep1pr3aqKryi41AM3YPP"
    b64 .= "kHQUGADJGKAUIeCVaNkTxsi7PMs5eSQzLvu4kDVC27x09uTuXDm5ShrcrI4EZNAroRSBMUBqAjyWxOS3NA5eekqrKVv+TDnyeHOFGuyOrS+mU3z8zYLouTvh"
    b64 .= "i24x4fVaau1nGoYlUaBSiAR4DA5XEfyWQE2VRfd6W+zE8znZc33MOh+vz+/fGSQigtIEj8EBKmaw0QIB4JoBABFG+9uY3xTWwMMpc2opw38kc/5EXyuTvEQx"
    b64 .= "16ULEgC0dhP28qfjobLKPAkTbz9n8Gryq8grqX1eA/dGFtiB+nIFwwKYcO3lT6bWbmKjwD9RtsK1WLMdeDZQpt9QDvgM5P+C8n890x+v+Y9iAPALMQpHdO2K"
    b64 .= "PV0AAAAASUVORK5CYIKJUE5HDQoaCgAAAA1JSERSAAAAGAAAABgIBgAAAOB3PfgAAAS0SURBVHicvVZbbFRVFF37nPuYO+1M6YtCKwhtMbUtAYNSiCE1Mahg"
    b64 .= "VKJpTAyCCT4g/gA+vgwNLw0qicYYEwMfmIYYMQ1qNArRSEgQjJgCpTRYKEJpgQ6t7Uzn3rn3nrP9mBY6LQmaoOvznrPXOmfvfda+wCQ0SaBZTP5+OzSLbGwu"
    b64 .= "aPKmzRoACuauq9TSlEDmNsQ2hArU0KlPzk/kyBVobDRw6FBo169ZymGwCcpfDCGkIIAZ4FucjAjQDEBrBWn9Qoa5JdO+++AY1ziBJgnsU07dqve1ptes+FQ4"
    b64 .= "xXdDCoLrK5hSQAqC5qyMIILSjEBpOJaE0gz3+p/wh69BCN7pnv7s9TFOGruSXb9mKVR4wCm6SxdUL2EphUymQ1RX5GNg2EfSDRExs6XxAo2YY6AobqHrcgqx"
    b64 .= "qAGltBrqOkzuQI+ANB7JtO8+CDQLAXRkRQJ3uxUr4ynVS7SAksnkCBrr4jiwdRH2bJyHqBEiDDyEgYeoEWLPxnn4YWsDGuviSCZHIKDklOol2oqVMQJ3e/bg"
    b64 .= "HSSAfSq+oG82M893SmYSCWEQa/ghY35lIfIdEw01JSgvjiJQQKCA8uIoGmpKEHMszKsshB8CxBokhOGUzCRmnh9f0Dcb2KcEAHCgJYjMsQIqDRTFLHywvwuf"
    b64 .= "fndOA0jOKHUCpbNrs8qiAYDU5pYO/vibcyiMmVD6ZgOAyORASwDIJlXInCYRRGAAji3x1p526r6S5k0r6zzNDAbQ/Hy9d/hUAm9/foYcSwKcjcnBKOekB0UE"
    b64 .= "uL4CgWCbAlIIWvfR8bx7KmLh2sdmZR6dWxxUTssL3/mi0yktsGFIAo1220QNADDG97XWDD/QmFORj86eFELFMA3Cjyf65bdHeuwVK2pV56CP1iOX7QO/XZFT"
    b64 .= "YhZSXghTEu6dEUN3fwCtOef13hQgwA8Z762u5+cap9PpC0OBEOQxQAYzX7UjRsuQ4ZBtoDfxF9Yum+Xbjom0F6J2Ztx85fEqavm5Dxt2nM25yQ0BBiAFYVFN"
    b64 .= "MSxDoKwwInoHPEhJiBiE3/tcYzDuwMwwGhaWqw1PlqfHheYBsB6sLWEpiMYXNCdFzIwXdv5Kzyyeil3fX5B9g17MsSSGRwI8+9CM8KkXi/y+kMR9Xtp/+I1j"
    b64 .= "MTdkAjNsU2L5wmloPdpPzLkpulFkzYBtCfRe97BtbwfcTIiyAguOJTB7WpR3rX9g5H435fXsP6EXV0QzlRVxfbJ7WFxKuOLMpaTYtrcDPYk0bEtk/WmiAJA1"
    b64 .= "NdMglBbYkJIQaqB/KIMNT8/xDAm948uzzrutXdYfvSPGttV1bn5EsBSEvIhEaYENyxDgCa6YFdCKxouEKrvL8xXebKrhl5ZVhT+1XTW/PtprFuWb2NLSHikr"
    b64 .= "jIgtq+p4xFNgZoSKc8lHOQUAkCkUmIOxNSmAwWSAV5+oQvPKWgKQ/+FXXVE30LAMgYvX0iaA/JeXV4n1K6oxkPQhx+eCOSBTqFGBJjl8fHo3EbW5iYvMWodM"
    b64 .= "ApYBnDg/iJQb4NiZBJ08NyjybAEpGL3X0zjWmUDKDdB2fhCWQWASYK1DN3GRiaht+Pj0bqBJ/mO7TnkhbOPf2/X/MXBG8d+OzDHc+aF/C9zZ35a/ARGJejhn"
    b64 .= "u0k4AAAAAElFTkSuQmCCiVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAGt0lEQVR4nMWXa4xdVRXHf2vvfc59zJ2ZdjrT0hYrpRSk1EYsNFCL"
    b64 .= "KPIuolEnJGAKCkUNJpIG9KMRP5gIaRCNCW3kIfEDKSihlIRQMGCCMKQU22iobSlBnT5mOp07M/dxztlnLz/cmenQzlTBR9enm3PPWf//Xuu/Hls4tQkr73T/"
    b64 .= "4p1T245NHtAP+5n8R6AfwufJD3t7LVu25ACVlRu6fVJdr0KBED4cnDGIkrhC5+axHRsHT/Q9EwEBlGW9XUXKjyHm8xpC5aMHRBFjxtDw+yb12/jLlqFJjJMJ"
    b64 .= "9FrYEuJP3HK9iUq/Vp91mSim3LPEI0YFcFYICnmYPqXWCEbA59pC0CD1gf0uZCnioqGQNdal7/zmeeg10IrEBAEDBObfWS52pQPBZ+Xi7DP9rCWrrYlLYkRQ"
    b64 .= "haHRlEJs6ChF+KCTHyvgjDDSyEjSQFd7jAgEVULa0OH9r+XNY393xkX15lDcw8FN9QnMcR8/NKw8aIuN5GlVbih0npF3nXt5S/3qSb0SOcPdX17Kjr3H2Pp6"
    b64 .= "P10d8WQkrBGGRlK+eMkCVi6dzYPP7CXzgdgJSMvN0F9f8Un1kBXhuWap8FV2zM/hR0EmclI55xs9WZQfMq5gelbcoOIiIeSAEFR5ZMPFXHnhPHyu3PpAHy++"
    b64 .= "dZhKyQIw1si56tPzePyeVTgrbN95mG9ufBMj4+k2FvWZDux6ToJPQpTZM8b2PToAiJmoc1+Q9ajR8twlmY1LQu4REfKgtJeiSXBnhcsu6KaR5BgRjAiNJGfN"
    b64 .= "BXNwtpWqKy+cR3s5Ig+KiEDusXFJynOXZKhRX5D1AKy805njeqWIYBEzKQ1ViJwwOJJw6/19BFUF0nrqm9Ye1681QjMNTSA9Vku57YE+BocTItciNKl3MSBY"
    b64 .= "heLE00kCoNMWeghQKTp++9o/+NbPduRA/barzko/1l3SzAeSLHBmd0lvv2ZxOlr3zSt/8Ipu6ztIW9GeonUcxzIzvTLV8qDMnVXguTf63bbXD8Zd7YVwyxWL"
    b64 .= "0uGap5kGvv6FRWlHW5T/cuvewr7+msyqxMxQqSfZjASsEZwVRMZVqkoxtmzY/HapWsvM9286v7lmeXfeXrT63S+dm4zWvX3ipffjzjaHz1sHnOgdxszcyE4i"
    b64 .= "oOPgI/WMI8MJmVd8UDLfEuChY4n8/Nm9BQP5XWsXJzdffXZWKVr/8LZ9hUPDTWkrWqwRIisocGQ4YbSeYY1MO5FOIuCMcHQk5bqL53PfuuV0tUdaKVrtKDtt"
    b64 .= "K1idO6ugL7550O2tZvGBjy+M/WfOj57uz9p+8ey+QiMJHDqWMDiS0j+UAHDfuuVce9F8jo6kuGki8YFRa4wwWvd87er5PHL3Cpw13HHtWbkxUp9K3wg8POjK"
    b64 .= "u2q4WQ62Vl3hmuvO8+c67xNFnEA9CXz2kz2FKz41lzQ7mzse2s1Tz/wJY4QwIwGBWpKzetkcnDVkXqmUIjfWyMQYUbQVsnpADozlrjOyWFViJ9x189J0BTRO"
    b64 .= "iGqUeTVxZFm9bA5PPJnTJnxAoB8gkAdlTkfM/U/tYcm8iEvP72b9g2/xyu6BSqVoyUNLVNVqUy66/gJdfMU5cnRMWNpOeLfvML97Z6BSLFpUQRUtxjasv+5s"
    b64 .= "8+ruQe5/ag9zOmJqNQWR6QmotnpFmgVu39hHR1uBI8MJxcjIcM1jjTDa8KxZ1u2fvHlx7V2P24l3Ny1wzW3v++jHT+4ptJccYcoRf/XCAUZqCWqKiGlhTJ3B"
    b64 .= "J1eBQhwZjAjVWkal5CZL0hpBgHt7z0ucteHY3kF96Ccvu+poKmsvWZj2XrbQFyPDGbML9HTG9HTGVGsZRoQ4MlO64ikITJCA8fkfdLI0q/WMGy9d4Ncs7/aA"
    b64 .= "bNy6r/javhG7+YUDMcC3r1+SpD6QB8XnOjk7pvr8twicSMQIVGsZi3rK+tB3LqwD+nzfwfjVXQNuUU+Rx198rzA0kpjLV/RkN16ywB8eTrDm1MDTEJBpyRgD"
    b64 .= "tWbO2lXzefmnn5NKyZUGqk27YdPbJWuE2Bn+NtCQx7a/FwPlh7+30n5l9ULGmh4z4/GOY03+EGii5K050aItAplXumcVeOyeVXSWI4Do2T/2V/qPNqUUG5RW"
    b64 .= "9ZRjVwRiIyKP37uK7o4CmdcpgtfWDFJygeZxAq29HZfoZiRI/cj+KE8binWoakv59YztOw8j4/veS28fkWJsCdpau0oFyx/+PDiZ8+07DzPaGG+/qmAdedrQ"
    b64 .= "+pH9ERLEJboZgB2b/Edbyd7oZ057jP8vrWQTqTidSymc7rV8ihZP28VkIhD/36vZTHYaL6cn/v8/vp7/EwfqoDcb9rXlAAAAAElFTkSuQmCCiVBORw0KGgoA"
    b64 .= "AAANSUhEUgAAADAAAAAwCAYAAABXAvmHAAALBklEQVR4nN2aa4xd1XXHf3vv87ivuR7PjBk7xp5gHKhtyvhVwIV0CCCLRCT9EAykkUVJCVRWeTRR1aKkWFZR"
    b64 .= "aauoBdE0Bdw01KmaelJoQpQiB5K6gmIpAdu0AyGMXdvggh/jed97z2Pv1Q/nznjuvDyuIYqzpCNdnbsf///aa6+19toHznNRZ99lk3n/YUyUbvsBDCqKlZsC"
    b64 .= "1t3lfwCDN8q6u3xWbgpA5qTcs16B3GWbN+A8A+nZg5tVPNCprf33jpfPptdsBBRsVbDNzeu8vTl2wf0ujbT2wj9GGUDODe9004nFpdGfaC90gY4fGdz/1ABs"
    b64 .= "1bBNZppwJgJj74XO25tzsfy7CsudiMXVBi0i8v/aPrOKgFJK5+YZlEGiof21QF3L/qcGGvDMgYCiq8uwe3eaW3Xn4yi1WWHzLolisYkK51/oo95v8GPwhKj/"
    b64 .= "nUQZX7QfBoKpIrKj1rP9brq6PHbvtpNJTIMk8zK5lfknlCl8DlfDJjUXlhfqXNuHKbb/CkpnJiSAVirjI+Bkbmallcospt5H1aGIs4we+ym1k4eIht5zxs9p"
    b64 .= "dA6xla/XXq/elfVu9FLTq7L1U025RQuGEGclrRm/2Ebrqo0Yv0gaj1DHi9GaOLVUI4tvNKW8R2IdaoZhBcE3mpFqSmId+dAQeAbr3PiYXlDCJqP09ewiGT2J"
    b64 .= "8nIWpU3t3RNl+r47PHlM1fB70yad68ktFrx/Udpc7uIRL2haoFtXbEQZg0uTuvbBaMVINWVhS45LL2zi5GDEvoMDtDYFxKlMsTIRCDxF33DM6mXNtM0LefOd"
    b64 .= "Yd47VaOU97AuWz1xFu35iLX0vbGLePiE00EpFWdfU6Sfrq2qHaW729X5osdnWH5jQHe3FdFbdFBcL0mVsLxIt67YCMYg1o6D10pRSxzFvMc3vngFO7+0gacf"
    b64 .= "vJr1l7TQNxzje1NXwK+DX39JC08/eDU7v7SBb3zxCop5j1riMrMClM7mwhhaV2wkLC/SklTRQXG9iN5Cd7dl+Y3B2LinCQRNAls1WsWIFbEp+bYOdFhAbMJE"
    b64 .= "lVonBJ7m2W3XsGZ5M1HiaC75fPvLG+hc1sxI1aL16fZaK0aqls5lzXz7yxtoLvlEiWPN8mae3XYNgafHVyBjoRCboMMC+bYOxKYgVtAqhq06w9pAYJPh9e44"
    b64 .= "t+rAVVoHD7jqkA1bFgeF9ktxUQWlGrMH64RizrCqo0xiHaGviVNHueCzqCVPnLpJtglx6ljUkqdc8InTrE9iHas6yhRzppEAoJTBRRUK7ZcStiwOXHXIah08"
    b64 .= "kFt14Cpe747HnI1u6OXEoLSXmZfKfk4jnlEMjCTs3P02vsm0Z4wGSCuRtRO1P3EVKpG1QOplbfGNZufutxkYSfDM9Bs/w1Df4kp7OGnQpp7UWhrd7PRuUals"
    b64 .= "E9/5yE/4xx8exmglNnUWGAl9Jb5RuIl6AXyjCH0lwEillrhqZPmnHx3hzkd+gtFqltAyCY/SDaCmV/EZRCQj0FYO+L2/2YtzRJtv6IgA9bf3rK2uuGtXk1g3"
    b64 .= "vm/EOgR4/N61VUCV8v7wmi27yscHIjW/FGC0mnMMmSz6zE2mFydZICvnPB74+//Kjb2f3xS6zdctjauxw2iFVlCJHZuvWxo3l0IHsOOFQ8HxwRjf02g99wD4"
    b64 .= "vhKAbCV03Xb/YPv+/Njruz+xLB6NLKkVPKMR4PM3LovJ7EG+vutQUIud0lpxDtiBcyQAGYmcr/nLp3uDv3vuYAiwfHGTfeK+tdUw0HLkRJW7P3FRfMmSphRg"
    b64 .= "+3MHcnt7B0xLycO5c0TPHAkoMps303gXyNR6wbyAp1866vePJto5+K2PddQuai+6hc2h3PzRpTFA/3Csn3npf/3Q08yEfWyeuaaLZySgVMZgYDRhcDRzd/6k"
    b64 .= "RyloKfn86LUT5rUDA0ZnVqP+8LYVtV/vvMCuXjYvAeSVt/q9Xa8eN/OK/hS/PwZ+cDRhYDQBxZyS3lm9kFKQWkEUXNd5Aal1vLDv+Iza00rx2T/fU9z75MeH"
    b64 .= "I+Opny1cEIY3tXrfOk7xqqKN79++P9+xII91kvn9+jhZVgunRhJ+47I2PKPZ89M+lAj+GQ6xZ3CjiqFqwuP3/Rq3di0B4LHvvOWqsY20alw9EbBAs6/csGi1"
    b64 .= "9TCl+QrmB5oXhwme71NBX1+NSuKmaHZM81/49CX8xe9cDsA/736bux/9Ma25PLPJjATGBn1sy1pu7VpCnGZu8Z7f/MhY5lthhnT8K0dcU6vJ7FMEcoDyFb99"
    b64 .= "3zX21japVixqInulkdRKcPXKtsA6wTrJ5kwsv7/9jRn33qwElILEOq69fAFJmmWLWimcE6W1mq20oo57WhOfrisIkKJovbiF1e0k0xAXIEitYLRCFCRpfW7b"
    b64 .= "wwxZxuwExAn5wPDV7/XyZ5/rHH8/XE157Du9Jh/qvHNTSx/WCgdMUXVcsRSJBa1UdlABrikQz0QaiDyjPEBneZHiq9/rJR8Yolnc7YwErEAp7/HoM28Bmm2b"
    b64 .= "V1GNLZ95eA8/ePWYVwg9b3IE1VozPFhjzboPsfKjS6W/hqo6IdRwYZNy5RP9tmvbvnL7/Jyk9nRdQESUc+IKoae+du868oFh644eHn3mLRa3N1OZJVzMuomd"
    b64 .= "Exa15HnqB4f415eOIgiDownLFhYnnGVP69Ba4frVS9Jv/tGVlWKAfAvJD+S1usInXZsn2nfYeG+frOiew0NK1VdmghgQrrz3eRSKwUrCopb8GYPdGeOAc0Iu"
    b64 .= "0IxGKdXIUgg94tSRWiGpP7EVNIqjp2o8+JkVUTEwLk0tt7Xr0WTXG6k9dNICrO4oJ/d8ank8Glnayj7lgjf+zCt4lAs+1cgyGqXkAj2nSD2nSDyWfeoZssbA"
    b64 .= "KI4Pxtxxw4eTzo/MT6PYas8zsnVHT+HeR/bln/3xMR8gTqy5Y+NF0epl89ypkXRcQa7ueZwTdD0SzzVHOudcKPNWQuocN135oUSDoGBgJNa7XnnPX3pRWZ74"
    b64 .= "/oHgZ+8Me4FvXHMpcNevaU/OBuQHRkDVaztx6uTJ+9ZVb7pqUTxSSXToG7v9uYPhq70DupDTWCfqyX87GJBtW/XQ7ZfVtAJnpwa1nxuBLCZk/rq9OeS2a5fG"
    b64 .= "qXWqVPDltf8Z9He8cMRfOD9HLXaqGHrs+OGRoH84Gp/v4Tt+tTZUS1H1sX6uBJTKDvb9IzFf+Xwn//lX16tabEv1s67c9qcvF989VdNaZyukTJZd/u5jr+YB"
    b64 .= "iRNX2nxDR/jXW9ZwcijGuql1pLlKoxsVpybXuqYTkYzA9vvXc0s9RxLBAKV/eP5wMlRNVSlnxpM+TbZPokQUUDKeNtYJn72uA99ovvDEftSMDCbhEdfQsHEF"
    b64 .= "tLKIS8eqAOKmvwNIrdBc8rmlawmJzY7vSeoAzM7/eCc3Uk2nmIVzQiE0BvCszfKqxDpu6VpCc8kntdPv6AyDjIFP0aqhNlon0G1ZuSmo9Vy8x7n4YZ0vm+jU"
    b64 .= "0bhy7M2ssCWNtz5GK0Zrlp7DQ/hGEyWOwNcMVRKiOCUXmIaUW4DA07x7qspQJSHwsj6+0fQcHmK0ZqckbCIWHRaoHHuT6NTRWOfLxrn44VrPxXuyG5ysyHt6"
    b64 .= "BeJhBdscTgKUUcp4VE8ezgpbxmeizzNaEaeOT259kb29A4S+ZmAk4eaHXuaV3n4y8znd3jmhlDfsPzjAzQ+9zMBIQuhr9vYO8MmtL45nuhPQo4yPiypUTx5G"
    b64 .= "GS/bSE4C2OYyrJmc98XdX6ryel3O/wuO8/2KqeH9eXnJN+G/8/eadUb5RbvonqP8En1qcJ5+7PGLK/8HJZP/Esf2CoIAAAAASUVORK5CYIKJUE5HDQoaCgAA"
    b64 .= "AA1JSERSAAAAQAAAAEAIBgAAAKppcd4AAAKSSURBVHic7Vs7UsMwEH0wFHQuaT1DR8sxXKWgNWfICXIEzkBaah+Dli4zaSnT0UFBzBixknfXWkkhelUS6/Pe"
    b64 .= "02otOTJQUVFRcca4WNrA9d3jZwwiWny8PS/SoKqcW7QPGjMupRVKFQ/ouLEdK1k4BW40sAqFxN/cP3A5meD99cV7jWPCbAGf+NzCXfiMmDNBnAOA8sQDek5B"
    b64 .= "A6jRL1H8CIrbXO7yhsdS8ftt9/O57Qd2vRhtUNPBNxXYU0Arnvpu3YaEqyoHhOAjKhEQow0uSAPc8C953vvgcvblgugRcGqIbkAgWR0EzZBltck0BJMIIIhK"
    b64 .= "xJN1LMQDhlPgSPiAiZD9tps1wilzaPvBTDxgnAPafmgs24+B5EkwFAXutRQGmhtQehQkiQDXBCoKcow+kHEdwEmIKZDMgNCI5hp9IPNKsIQoSGqAO7LrHZrV"
    b64 .= "psN6h8ZXxhpXmkpL9/pTwaHfUnARG+DZp2cJZYqL1ASRAYH9eAOmCXMjvdp0eLpltUW2IzWhbodzE8gN0RRo+4GcBseQYyex1cb/aIsZ/sD3lPvTp2kOGDuI"
    b64 .= "8cR3pg+2mcnvAtqORkwXP9OEKBj5aFwApQFauCs/n+j9tjv8+83QiLYfmpxb5mQGUOt+yQbJCtkjYESuKEhigHT0Q/Viw9wAiYgcUZBlCgjv86ZRYGbAftuN"
    b64 .= "i5RfYufEO9cbAI3Fn6IjTAwgCGtC232QquYTQrK/xwFI7vferW5sFHMbzAXSAPc4SegoWqlwOS8+IsOFb3Mi2bTEaIMLtgGSKHCJaogvaUPCNXiI8NSOyQGy"
    b64 .= "E2LATARQFUvOB1LxgDIHlGiCllM9LM3t6KyPy09RuhHSt0bEOWDpOzqW0HA7+5emKioqKs4aX8CRKJJL4chZAAAAAElFTkSuQmCC"

    return WriteBase64File(b64, HUB_ICON_FILE)
}

WriteBase64File(base64Text, destination) {
    byteCount := 0

    if !DllCall(
        "Crypt32\CryptStringToBinaryW",
        "Str", base64Text,
        "UInt", 0,
        "UInt", 0x00000001, ; CRYPT_STRING_BASE64
        "Ptr", 0,
        "UInt*", &byteCount,
        "Ptr", 0,
        "Ptr", 0,
        "Int"
    ) {
        return false
    }

    if (byteCount <= 0)
        return false

    data := Buffer(byteCount, 0)

    if !DllCall(
        "Crypt32\CryptStringToBinaryW",
        "Str", base64Text,
        "UInt", 0,
        "UInt", 0x00000001,
        "Ptr", data.Ptr,
        "UInt*", &byteCount,
        "Ptr", 0,
        "Ptr", 0,
        "Int"
    ) {
        return false
    }

    try {
        if FileExist(destination)
            FileDelete(destination)

        file := FileOpen(destination, "w")
        if !IsObject(file)
            return false

        file.RawWrite(data, byteCount)
        file.Close()
        return true
    } catch {
        return false
    }
}

ApplyHubTrayIdentity() {
    global HUB_ICON_FILE, APP_NAME, APP_VERSION

    try {
        if FileExist(HUB_ICON_FILE)
            TraySetIcon(HUB_ICON_FILE, 1, true)
        else
            TraySetIcon("shell32.dll", 44, true)
    }

    A_IconTip := APP_NAME " v" APP_VERSION
        . "`nAll AutoHotkey v2 scripts consolidated here"
}

EnsureStartupShortcut() {
    try {
        if FileExist(STARTUP_LINK)
            FileDelete(STARTUP_LINK)

        ; /startup prevents the GUI from popping open automatically at login.
        startupArgs := Q(A_ScriptFullPath) " /startup"

        FileCreateShortcut(
            A_AhkPath,
            STARTUP_LINK,
            A_ScriptDir,
            startupArgs,
            APP_NAME
        )

        LogEvent("STARTUP", "Startup shortcut ensured: " STARTUP_LINK)
    } catch as err {
        LogEvent("ERROR", "Could not create startup shortcut: " err.Message)
    }
}

; ============================================================================
; DATA MODEL / DATABASE
; ============================================================================

NewRecord(path) {
    return {
        Path: path,
        RunCount: 0,
        FirstSeen: NowStamp(),
        LastRun: "",
        Favorite: 0,
        AlwaysStart: 0,
        Tags: "",
        Notes: ""
    }
}

EnsureRecord(path) {
    global gScripts

    path := NormalizePath(path)
    key := PathKey(path)

    if !gScripts.Has(key)
        gScripts[key] := NewRecord(path)

    return gScripts[key]
}

LoadDatabase() {
    global gScripts

    gScripts := Map()

    if !FileExist(DB_FILE)
        return

    try text := FileRead(DB_FILE, "UTF-8")
    catch as err {
        LogEvent("ERROR", "Database read failed: " err.Message)
        return
    }

    for , rawLine in StrSplit(text, "`n", "`r") {
        line := Trim(rawLine, "`r`n")
        if (line = "" || SubStr(line, 1, 1) = "#")
            continue

        fields := StrSplit(line, "`t")
        if (fields.Length < 8)
            continue

        path := DecodeField(fields[1])
        if (path = "")
            continue

        rec := {
            Path: NormalizePath(path),
            RunCount: SafeInt(DecodeField(fields[2])),
            FirstSeen: DecodeField(fields[3]),
            LastRun: DecodeField(fields[4]),
            Favorite: SafeInt(DecodeField(fields[5])) ? 1 : 0,
            AlwaysStart: SafeInt(DecodeField(fields[6])) ? 1 : 0,
            Tags: DecodeField(fields[7]),
            Notes: DecodeField(fields[8])
        }

        gScripts[PathKey(rec.Path)] := rec
    }
}

SaveDatabase() {
    global gSavingDb

    if gSavingDb
        return

    gSavingDb := true
    tempFile := DB_FILE ".tmp"

    try {
        out := "# AHK Script Hub DB v1`n"

        for key, rec in gScripts {
            out .= EncodeField(rec.Path) "`t"
                . EncodeField(rec.RunCount) "`t"
                . EncodeField(rec.FirstSeen) "`t"
                . EncodeField(rec.LastRun) "`t"
                . EncodeField(rec.Favorite) "`t"
                . EncodeField(rec.AlwaysStart) "`t"
                . EncodeField(rec.Tags) "`t"
                . EncodeField(rec.Notes) "`n"
        }

        if FileExist(tempFile)
            FileDelete(tempFile)

        FileAppend(out, tempFile, "UTF-8")

        if FileExist(DB_FILE) {
            try FileCopy(DB_FILE, DB_BACKUP_FILE, 1)
        }

        FileMove(tempFile, DB_FILE, 1)
    } catch as err {
        LogEvent("ERROR", "Database save failed: " err.Message)
        try {
            if FileExist(tempFile)
                FileDelete(tempFile)
        }
    } finally {
        gSavingDb := false
    }
}

RecordLaunch(path, reason, pid := 0) {
    rec := EnsureRecord(path)

    rec.RunCount += 1
    rec.LastRun := NowStamp()

    if (rec.FirstSeen = "")
        rec.FirstSeen := rec.LastRun

    SaveDatabase()
    LogEvent(
        "RUN",
        "reason=" reason
        . " pid=" pid
        . " count=" rec.RunCount
        . " path=" rec.Path
    )

    if IsMainGuiVisible()
        RefreshList()
    else
        UpdateStatusOnly()
}

EncodeField(value) {
    s := value ""
    s := StrReplace(s, "%", "%25")
    s := StrReplace(s, "`t", "%09")
    s := StrReplace(s, "`r", "%0D")
    s := StrReplace(s, "`n", "%0A")
    return s
}

DecodeField(value) {
    s := value ""
    s := StrReplace(s, "%0A", "`n")
    s := StrReplace(s, "%0D", "`r")
    s := StrReplace(s, "%09", "`t")
    s := StrReplace(s, "%25", "%")
    return s
}

SafeInt(value, defaultValue := 0) {
    s := Trim(value "")
    if (s = "")
        return defaultValue

    if IsNumber(s)
        return s + 0

    return defaultValue
}

; ============================================================================
; RUNNING-SESSION SNAPSHOT / RESTORE
; ============================================================================

LoadRunningSnapshot() {
    entries := []

    if !FileExist(SNAPSHOT_FILE)
        return entries

    try text := FileRead(SNAPSHOT_FILE, "UTF-8")
    catch
        return entries

    for , rawLine in StrSplit(text, "`n", "`r") {
        line := Trim(rawLine, "`r`n")
        if (line = "" || SubStr(line, 1, 1) = "#")
            continue

        fields := StrSplit(line, "`t")
        if (fields.Length < 2)
            continue

        path := NormalizePath(DecodeField(fields[1]))
        count := Max(1, SafeInt(DecodeField(fields[2]), 1))

        if (path != "" && !SamePath(path, A_ScriptFullPath))
            entries.Push({Path: path, Count: count})
    }

    return entries
}

SaveRunningSnapshot() {
    global gSavingSnapshot

    if gSavingSnapshot
        return

    gSavingSnapshot := true
    tempFile := SNAPSHOT_FILE ".tmp"

    try {
        counts := RunningCountsByPath()
        out := "# AHK Script Hub running snapshot v1`n"

        for key, info in counts {
            out .= EncodeField(info.Path) "`t" EncodeField(info.Count) "`n"
        }

        if FileExist(tempFile)
            FileDelete(tempFile)

        FileAppend(out, tempFile, "UTF-8")
        FileMove(tempFile, SNAPSHOT_FILE, 1)
    } catch as err {
        LogEvent("ERROR", "Snapshot save failed: " err.Message)
        try {
            if FileExist(tempFile)
                FileDelete(tempFile)
        }
    } finally {
        gSavingSnapshot := false
    }
}

RestorePreviousSession(*) {
    global gRestoreDone, gBootSnapshot

    ; Refresh one last time so scripts launched independently by Windows do not
    ; get duplicated by our restore pass.
    FullRunningScan()

    current := RunningCountsByPath()
    restored := 0

    for , entry in gBootSnapshot {
        path := entry.Path
        key := PathKey(path)

        if !FileExist(path) {
            LogEvent("RESTORE_SKIP", "Missing file: " path)
            continue
        }

        already := current.Has(key) ? current[key].Count : 0
        needed := Max(0, entry.Count - already)

        Loop needed {
            if RunManaged(path, "startup_restore") {
                restored += 1

                if current.Has(key)
                    current[key].Count += 1
                else
                    current[key] := {Path: path, Count: 1}

                Sleep 40
            }
        }
    }

    ; "Always Start" is separate from the shutdown snapshot and guarantees at
    ; least one instance on every manager startup.
    for key, rec in gScripts {
        if !rec.AlwaysStart
            continue

        if !FileExist(rec.Path)
            continue

        isRunning := current.Has(key) && current[key].Count > 0

        if !isRunning {
            if RunManaged(rec.Path, "always_start") {
                restored += 1
                current[key] := {Path: rec.Path, Count: 1}
            }
        }
    }

    gRestoreDone := true
    SaveRunningSnapshot()
    RebuildRunningTrayMenu()
    RefreshList()

    LogEvent("RESTORE", "Restore pass completed. Launched=" restored)
}

RunningCountsByPath() {
    global gRunning

    counts := Map()

    for pid, inst in gRunning {
        if SamePath(inst.Path, A_ScriptFullPath)
            continue

        key := PathKey(inst.Path)

        if counts.Has(key) {
            counts[key].Count += 1
        } else {
            counts[key] := {
                Path: inst.Path,
                Count: 1
            }
        }
    }

    return counts
}

RunningCount(path) {
    global gRunning

    key := PathKey(path)
    count := 0

    for pid, inst in gRunning {
        if (PathKey(inst.Path) = key)
            count += 1
    }

    return count
}

; ============================================================================
; PROCESS DISCOVERY
; ============================================================================
;
; Layer 1: AutoHotkey's hidden main windows are polled every 250ms. The normal
; v2 main-window title contains the full script path and "AutoHotkey v2".
;
; Layer 2: WMI Win32_ProcessStartTrace captures process starts and tries to
; resolve the command line immediately.
;
; Layer 3: Every 1.5s an authoritative WMI process sweep rebuilds the live set.
;
; The redundancy helps with scripts that hide tray icons, change GUI state, are
; started from unusual launchers, or happen between slower WMI sweeps.

InitWmi() {
    global gWmi

    try {
        gWmi := ComObjGet(
            "winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2"
        )
    } catch as err {
        gWmi := 0
        LogEvent("ERROR", "WMI initialization failed: " err.Message)
    }
}

StartProcessTrace() {
    global gWmi, gWmiSink, gProcessTraceActive

    if !IsObject(gWmi)
        return

    try {
        gWmiSink := ComObject("WbemScripting.SWbemSink")
        ComObjConnect(gWmiSink, "WmiSink_")

        gWmi.ExecNotificationQueryAsync(
            gWmiSink,
            "SELECT * FROM Win32_ProcessStartTrace "
            . "WHERE ProcessName LIKE 'AutoHotkey%.exe'"
        )

        gProcessTraceActive := true
        LogEvent("WATCHER", "WMI Win32_ProcessStartTrace active.")
    } catch as err {
        gWmiSink := 0
        gProcessTraceActive := false
        LogEvent("ERROR", "WMI process-start trace unavailable: " err.Message)
    }
}

WmiSink_OnObjectReady(eventObj, asyncContext := 0, *) {
    name := ""
    pid := 0

    try name := eventObj.ProcessName ""
    try pid := eventObj.ProcessID + 0

    if (!pid || !RegExMatch(name, "i)^AutoHotkey.*\.exe$"))
        return

    ; Resolve immediately so even short-lived scripts have the best chance
    ; of being captured before their interpreter process exits.
    ResolveStartedProcess(pid)
}

WmiSink_OnCompleted(hResult, errorObj := 0, asyncContext := 0, *) {
    global gProcessTraceActive
    gProcessTraceActive := false
    LogEvent("WATCHER", "WMI process-start trace completed/stopped. HRESULT=" hResult)
}

ResolveStartedProcess(pid) {
    global gWmi

    if !pid
        return

    ; Prefer AHK's hidden main window because it gives an absolute script path.
    path := ScriptPathFromMainWindow(pid, &hwnd)
    if (path != "") {
        RegisterRunningInstance(pid, path, "", "", hwnd, "wmi_event_window")
        return
    }

    if !IsObject(gWmi)
        return

    try {
        query := "SELECT ProcessId,Name,ExecutablePath,CommandLine "
            . "FROM Win32_Process WHERE ProcessId=" pid

        for proc in gWmi.ExecQuery(query) {
            AddWmiProcessToRunning(proc, gRunning, "wmi_event")
            break
        }
    }
}

FastWindowScan(*) {
    global gRunning, gRestoreDone

    changed := false

    try hwnds := WinGetList("ahk_class AutoHotkey")
    catch
        return

    for , hwnd in hwnds {
        try {
            title := WinGetTitle("ahk_id " hwnd)
            pid := WinGetPID("ahk_id " hwnd)
        } catch {
            continue
        }

        if !pid
            continue

        path := ParseV2MainWindowTitle(title)
        if (path = "" || SamePath(path, A_ScriptFullPath))
            continue

        before := gRunning.Has(pid)

        RegisterRunningInstance(
            pid,
            path,
            "",
            "",
            hwnd,
            "hidden_window"
        )

        if !before
            changed := true
    }

    ; Keep any newly discovered/recreated peer tray icons hidden under the Hub.
    ConsolidateRunningTrayIcons()

    if changed {
        RebuildRunningTrayMenu()

        if gRestoreDone
            SaveRunningSnapshot()

        if IsMainGuiVisible()
            RefreshList()
        else
            UpdateStatusOnly()
    }
}

FullRunningScan(*) {
    global gWmi, gRunning, gSeenPids, gRestoreDone

    current := Map()
    wmiSucceeded := false

    ; First collect every normal v2 script hidden main window.
    try {
        for , hwnd in WinGetList("ahk_class AutoHotkey") {
            try {
                title := WinGetTitle("ahk_id " hwnd)
                pid := WinGetPID("ahk_id " hwnd)
            } catch {
                continue
            }

            path := ParseV2MainWindowTitle(title)
            if (!pid || path = "" || SamePath(path, A_ScriptFullPath))
                continue

            RegisterRunningInstance(
                pid,
                path,
                "",
                "",
                hwnd,
                "full_window_scan",
                current
            )
        }
    }

    ; Then enrich/recover with WMI. This also finds scripts whose main-window
    ; title was deliberately changed by the script.
    if IsObject(gWmi) {
        try {
            query := "SELECT ProcessId,Name,ExecutablePath,CommandLine "
                . "FROM Win32_Process WHERE Name LIKE 'AutoHotkey%.exe'"

            for proc in gWmi.ExecQuery(query)
                AddWmiProcessToRunning(proc, current, "full_wmi_scan")

            wmiSucceeded := true
        } catch as err {
            LogEvent("ERROR", "WMI process sweep failed: " err.Message)
        }
    }

    changed := !RunningMapsEqual(gRunning, current)
    gRunning := current

    ; A full scan is authoritative, so reconcile notification-area state too.
    ConsolidateRunningTrayIcons()

    ; Forget dead PIDs so a future PID reuse is counted as a new launch.
    for pid, key in CloneMap(gSeenPids) {
        if gRunning.Has(pid)
            continue

        if wmiSucceeded {
            gSeenPids.Delete(pid)
        } else {
            try {
                if !ProcessExist(pid)
                    gSeenPids.Delete(pid)
            }
        }
    }

    CleanupPrecountedPids()

    if changed {
        RebuildRunningTrayMenu()

        if gRestoreDone
            SaveRunningSnapshot()

        if IsMainGuiVisible()
            RefreshList()
        else
            UpdateStatusOnly()
    }
}

AddWmiProcessToRunning(proc, targetMap, source) {
    pid := 0
    name := ""
    exe := ""
    cmd := ""

    try pid := proc.ProcessId + 0
    try name := proc.Name ""
    try exe := proc.ExecutablePath ""
    try cmd := proc.CommandLine ""

    if !pid
        return

    ; If a main window exists, its v2 title is the most reliable absolute path.
    path := ScriptPathFromMainWindow(pid, &hwnd)

    if (path = "") {
        ; For processes with a changed/no-normal main title, verify that the
        ; interpreter itself is v2, then parse an absolute .ahk argument.
        if !IsV2Interpreter(exe, cmd)
            return

        path := ExtractAbsoluteAhkPath(cmd)
        hwnd := 0
    }

    if (path = "" || SamePath(path, A_ScriptFullPath))
        return

    RegisterRunningInstance(pid, path, exe, cmd, hwnd, source, targetMap)
}

RegisterRunningInstance(
    pid,
    path,
    exe := "",
    cmd := "",
    hwnd := 0,
    source := "",
    targetMap := 0
) {
    global gRunning, gSeenPids, gPrecountedPids

    if !pid
        return

    path := NormalizePath(path)

    if (path = "" || SamePath(path, A_ScriptFullPath))
        return

    key := PathKey(path)

    ; One new PID is one observed script launch. Hub-launched PIDs are already
    ; counted synchronously by RunManaged(), so consume their precount marker.
    if !gSeenPids.Has(pid) {
        if gPrecountedPids.Has(pid) {
            gPrecountedPids.Delete(pid)
        } else {
            RecordLaunch(path, source = "" ? "observed" : source, pid)
        }

        gSeenPids[pid] := key
    }

    inst := {
        PID: pid,
        Path: path,
        Interpreter: exe,
        CommandLine: cmd,
        Hwnd: hwnd,
        Source: source
    }

    if IsObject(targetMap)
        targetMap[pid] := inst
    else
        gRunning[pid] := inst
}

ScriptPathFromMainWindow(pid, &outHwnd) {
    outHwnd := 0

    try hwnds := WinGetList("ahk_pid " pid " ahk_class AutoHotkey")
    catch
        return ""

    for , hwnd in hwnds {
        try title := WinGetTitle("ahk_id " hwnd)
        catch
            continue

        path := ParseV2MainWindowTitle(title)

        if (path != "") {
            outHwnd := hwnd
            return path
        }
    }

    return ""
}

ParseV2MainWindowTitle(title) {
    ; Normal uncompiled v2 title:
    ;   C:\Scripts\MyScript.ahk - AutoHotkey v2.x.x
    if RegExMatch(
        title,
        "i)^(.*\.ahk) - AutoHotkey v2(?:\.|$)",
        &match
    ) {
        return NormalizePath(match[1])
    }

    return ""
}

IsV2Interpreter(exePath, commandLine := "") {
    if (exePath != "") {
        if InStr(exePath, "\AutoHotkey\v2\", false)
            return true

        try {
            version := FileGetVersion(exePath)
            if RegExMatch(version, "^2(?:\.|$)")
                return true
        }
    }

    if InStr(commandLine, "\AutoHotkey\v2\", false)
        return true

    return false
}

ExtractAbsoluteAhkPath(commandLine) {
    if (commandLine = "")
        return ""

    args := CommandLineToArray(commandLine)

    for , arg in args {
        candidate := Trim(arg)

        if !RegExMatch(candidate, "i)\.ahk$")
            continue

        if IsAbsolutePath(candidate)
            return NormalizePath(candidate)
    }

    return ""
}

CommandLineToArray(commandLine) {
    args := []
    argc := 0

    argvPtr := DllCall(
        "Shell32\CommandLineToArgvW",
        "Str", commandLine,
        "Int*", &argc,
        "Ptr"
    )

    if !argvPtr
        return args

    try {
        Loop argc {
            itemPtr := NumGet(
                argvPtr,
                (A_Index - 1) * A_PtrSize,
                "Ptr"
            )

            args.Push(StrGet(itemPtr))
        }
    } finally {
        DllCall("LocalFree", "Ptr", argvPtr, "Ptr")
    }

    return args
}

CleanupPrecountedPids() {
    global gPrecountedPids

    nowTick := A_TickCount

    for pid, expires in CloneMap(gPrecountedPids) {
        if TickExpired(nowTick, expires)
            gPrecountedPids.Delete(pid)
    }
}

TickExpired(nowTick, expirationTick) {
    ; A_TickCount wraps roughly every 49.7 days. Signed 32-bit subtraction
    ; makes a short TTL comparison wrap-safe.
    diff := (nowTick - expirationTick) & 0xFFFFFFFF

    if (diff & 0x80000000)
        diff := -((~diff + 1) & 0xFFFFFFFF)

    return diff >= 0
}

RunningMapsEqual(a, b) {
    if (a.Count != b.Count)
        return false

    for pid, inst in b {
        if !a.Has(pid)
            return false

        if (PathKey(a[pid].Path) != PathKey(inst.Path))
            return false
    }

    return true
}

CloneMap(source) {
    copy := Map()

    for key, value in source
        copy[key] := value

    return copy
}

; ============================================================================
; SCRIPT ACTIONS
; ============================================================================

RunManaged(path, reason := "hub", asAdmin := false) {
    global gRunning, gSeenPids, gPrecountedPids, gRestoreDone

    path := NormalizePath(path)

    if !FileExist(path) {
        MsgBox(
            "The script no longer exists:`n`n" path,
            APP_NAME,
            "Icon!"
        )
        return false
    }

    SplitPath(path, &fileName, &workingDir)

    command := Q(A_AhkPath) " " Q(path)

    if asAdmin
        command := "*RunAs " command

    pid := 0

    try {
        Run(command, workingDir, , &pid)
    } catch as err {
        MsgBox(
            "Could not run:`n" path "`n`n" err.Message,
            APP_NAME,
            "Iconx"
        )
        LogEvent("ERROR", "Run failed: " path " :: " err.Message)
        return false
    }

    ; Count immediately. This guarantees hub-launched short-lived scripts count
    ; even if they exit before any watcher can observe them.
    RecordLaunch(path, reason, pid)

    if pid {
        gPrecountedPids[pid] := (A_TickCount + 10000) & 0xFFFFFFFF
        gSeenPids[pid] := PathKey(path)

        gRunning[pid] := {
            PID: pid,
            Path: path,
            Interpreter: A_AhkPath,
            CommandLine: command,
            Hwnd: 0,
            Source: reason
        }
    }

    RebuildRunningTrayMenu()
    SetTimer(ConsolidateRunningTrayIcons, -300)

    if gRestoreDone
        SaveRunningSnapshot()

    return true
}

StopPath(path, forceAfterTimeout := true) {
    global gRunning

    key := PathKey(path)
    pids := []

    for pid, inst in gRunning {
        if (PathKey(inst.Path) = key)
            pids.Push(pid)
    }

    if (pids.Length = 0)
        return true

    for , pid in pids {
        closedGracefully := false

        try {
            mainWindows := WinGetList(
                "ahk_pid " pid " ahk_class AutoHotkey"
            )

            for , hwnd in mainWindows {
                try {
                    WinClose("ahk_id " hwnd)
                    closedGracefully := true
                    break
                }
            }
        }

        ; Allow OnExit handlers in the target script to run.
        if closedGracefully {
            Loop 20 {
                if !ProcessExist(pid)
                    break
                Sleep 50
            }
        }

        if forceAfterTimeout && ProcessExist(pid) {
            try ProcessClose(pid)
        }
    }

    ; Reconcile immediately rather than waiting for the next timer.
    Sleep 50
    FullRunningScan()
    LogEvent("STOP", "path=" path " instances=" pids.Length)
    return true
}

RestartPath(path) {
    StopPath(path)
    Sleep 100
    return RunManaged(path, "restart")
}

OpenInVSCode(path) {
    if !FileExist(path)
        return MissingPathMessage(path)

    exe := FindVSCode()
    SplitPath(path, , &workingDir)

    try {
        if (exe != "")
            Run(Q(exe) " --reuse-window " Q(path), workingDir)
        else
            Run("code --reuse-window " Q(path), workingDir)
    } catch as err {
        MsgBox(
            "VS Code could not be launched.`n`n" err.Message,
            APP_NAME,
            "Iconx"
        )
    }
}

OpenInSciTE(path) {
    if !FileExist(path)
        return MissingPathMessage(path)

    if !FileExist(SCITE_EXE) {
        MsgBox(
            "SciTE4AutoHotkey was not found at:`n`n" SCITE_EXE,
            APP_NAME,
            "Icon!"
        )
        return
    }

    SplitPath(path, , &workingDir)

    try Run(Q(SCITE_EXE) " " Q(path), workingDir)
    catch as err {
        MsgBox(
            "SciTE4AutoHotkey could not be launched.`n`n" err.Message,
            APP_NAME,
            "Iconx"
        )
    }
}

FindVSCode() {
    candidates := [
        EnvGet("LocalAppData") "\Programs\Microsoft VS Code\Code.exe",
        A_ProgramFiles "\Microsoft VS Code\Code.exe"
    ]

    pf86 := EnvGet("ProgramFiles(x86)")
    if (pf86 != "")
        candidates.Push(pf86 "\Microsoft VS Code\Code.exe")

    for , candidate in candidates {
        if FileExist(candidate)
            return candidate
    }

    try {
        candidate := RegRead(
            "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe"
        )

        if FileExist(candidate)
            return candidate
    }

    try {
        candidate := RegRead(
            "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\Code.exe"
        )

        if FileExist(candidate)
            return candidate
    }

    return ""
}

OpenContainingFolder(path) {
    if FileExist(path) {
        try Run("explorer.exe /select," Q(path))
        return
    }

    SplitPath(path, , &dir)

    if DirExist(dir)
        Run(Q(dir))
    else
        MissingPathMessage(path)
}

CopyPath(path) {
    A_Clipboard := path
    ToolTip("Copied:`n" path)
    SetTimer((*) => ToolTip(), -1200)
}

ToggleFavorite(path) {
    rec := EnsureRecord(path)
    rec.Favorite := rec.Favorite ? 0 : 1
    SaveDatabase()
    RefreshList()
}

ToggleAlwaysStart(path) {
    rec := EnsureRecord(path)
    rec.AlwaysStart := rec.AlwaysStart ? 0 : 1
    SaveDatabase()
    RefreshList()
}

MissingPathMessage(path) {
    MsgBox(
        "The stored path is missing:`n`n" path
        . "`n`nUse the right-click option 'Locate moved script' to repair it.",
        APP_NAME,
        "Icon!"
    )
}

; ============================================================================
; GUI
; ============================================================================

BuildMainGui() {
    global gMainGui, gSearchEdit, gFilterDDL, gList, gStatusText

    gMainGui := Gui("+Resize MinSize900x520", APP_WINDOW_TITLE)
    gMainGui.SetFont("s9", "Segoe UI")

    gMainGui.AddText("xm ym+4", "Search:")
    gSearchEdit := gMainGui.AddEdit("x+6 yp-4 w310")

    gMainGui.AddText("x+12 yp+4", "Filter:")
    gFilterDDL := gMainGui.AddDropDownList(
        "x+6 yp-4 w155 Choose1",
        ["All scripts", "Running", "Favorites", "Always start", "Missing"]
    )

    ; Primary action row.
    btnRun := gMainGui.AddButton("xm y+12 w82", "Run")
    btnRestart := gMainGui.AddButton("x+6 w82", "Restart")
    btnStop := gMainGui.AddButton("x+6 w82", "Stop")
    btnVSCode := gMainGui.AddButton("x+6 w105", "VS Code")
    btnSciTE := gMainGui.AddButton("x+6 w105", "SciTE4AHK")
    btnFolder := gMainGui.AddButton("x+6 w100", "Open Folder")
    btnMetadata := gMainGui.AddButton("x+6 w105", "Tags / Notes")

    ; Secondary management row.
    btnAdd := gMainGui.AddButton("xm y+8 w110", "Add Script")
    btnImport := gMainGui.AddButton("x+6 w125", "Import Folder")
    btnFavorite := gMainGui.AddButton("x+6 w105", "Favorite")
    btnAlways := gMainGui.AddButton("x+6 w110", "Always Start")
    btnCopy := gMainGui.AddButton("x+6 w130", "Copy Script Path")
    btnExport := gMainGui.AddButton("x+6 w110", "Export CSV")
    btnLog := gMainGui.AddButton("x+6 w110", "Activity Log")
    btnHotkeys := gMainGui.AddButton("x+6 w115", "Hotkey Map")

    gList := gMainGui.AddListView(
        "xm y+10 w1180 h470 Grid -Multi",
        [
            "Fav",
            "Script",
            "Runs",
            "Status",
            "Last Run",
            "First Seen",
            "Always",
            "Tags",
            "Path"
        ]
    )

    gList.ModifyCol(1, 42)
    gList.ModifyCol(2, 185)
    gList.ModifyCol(3, 60)
    gList.ModifyCol(4, 100)
    gList.ModifyCol(5, 145)
    gList.ModifyCol(6, 145)
    gList.ModifyCol(7, 60)
    gList.ModifyCol(8, 130)
    gList.ModifyCol(9, 350)

    gStatusText := gMainGui.AddText(
        "xm y+8 w1180",
        "Initializing"
    )

    gSearchEdit.OnEvent("Change", (*) => RefreshList())
    gFilterDDL.OnEvent("Change", (*) => RefreshList())

    gList.OnEvent("DoubleClick", ListDoubleClick)
    gList.OnEvent("ContextMenu", ListContextMenu)

    btnRun.OnEvent("Click", RunSelected)
    btnRestart.OnEvent("Click", RestartSelected)
    btnStop.OnEvent("Click", StopSelected)
    btnVSCode.OnEvent("Click", VSCodeSelected)
    btnSciTE.OnEvent("Click", SciTESelected)
    btnFolder.OnEvent("Click", FolderSelected)
    btnMetadata.OnEvent("Click", MetadataSelected)
    btnAdd.OnEvent("Click", AddScript)
    btnImport.OnEvent("Click", ImportFolder)
    btnFavorite.OnEvent("Click", FavoriteSelected)
    btnAlways.OnEvent("Click", AlwaysStartSelected)
    btnCopy.OnEvent("Click", CopySelectedPath)
    btnExport.OnEvent("Click", ExportCsv)
    btnLog.OnEvent("Click", OpenActivityLog)
    btnHotkeys.OnEvent("Click", ShowAllRunningHotkeys)

    ; Closing the GUI keeps the manager/tracker alive in the system tray.
    gMainGui.OnEvent("Close", (*) => gMainGui.Hide())
    gMainGui.OnEvent("Escape", (*) => gMainGui.Hide())
    gMainGui.OnEvent("Size", MainGuiSize)

    RefreshList()
}

BuildContextMenu() {
    global gContextMenu

    gContextMenu := Menu()

    gContextMenu.Add("Run", ContextRun)
    gContextMenu.Add("Run as Administrator", ContextRunAdmin)
    gContextMenu.Add("Restart", ContextRestart)
    gContextMenu.Add("Stop", ContextStop)
    gContextMenu.Add()

    gContextMenu.Add("Open in VS Code", ContextVSCode)
    gContextMenu.Add("Open in SciTE4AutoHotkey", ContextSciTE)
    gContextMenu.Add("Open containing folder", ContextFolder)
    gContextMenu.Add("Copy script path", ContextCopy)
    gContextMenu.Add("Show hotkeys / mappings", ContextHotkeys)
    gContextMenu.Add()

    gContextMenu.Add("Toggle favorite", ContextFavorite)
    gContextMenu.Add("Toggle Always Start", ContextAlways)
    gContextMenu.Add("Edit tags / notes", ContextMetadata)
    gContextMenu.Add()
    gContextMenu.Add("Locate moved script", ContextRelocate)
    gContextMenu.Add("Remove from history", ContextRemove)
}

BuildTrayMenu() {
    global gRunningMenu, gHubControlMenu

    A_TrayMenu.Delete()

    A_TrayMenu.Add("Open Script Hub", ShowMainGui)
    A_TrayMenu.Default := "Open Script Hub"
    A_TrayMenu.ClickCount := 2

    A_TrayMenu.Add()

    gRunningMenu := Menu()
    A_TrayMenu.Add("Active AutoHotkey v2 Scripts", gRunningMenu)

    gHubControlMenu := Menu()
    gHubControlMenu.Add("Open Script Hub", ShowMainGui)
    gHubControlMenu.Add("Hotkey Map", ShowAllRunningHotkeys)
    gHubControlMenu.Add()
    gHubControlMenu.Add(
        "Consolidate AHK tray icons into this Hub",
        ToggleTrayConsolidation
    )
    gHubControlMenu.Add()
    gHubControlMenu.Add("Restart Script Hub", RestartHub)
    gHubControlMenu.Add("Edit Script Hub in VS Code", EditHubVSCode)
    gHubControlMenu.Add("Edit Script Hub in SciTE", EditHubSciTE)
    gHubControlMenu.Add("Open Script Hub Folder", OpenHubFolder)
    gHubControlMenu.Add("Copy Script Hub Path", CopyHubPath)
    gHubControlMenu.Add()
    gHubControlMenu.Add("Restore Last Session Now", RestorePreviousSession)
    gHubControlMenu.Add("Export History CSV", ExportCsv)
    gHubControlMenu.Add("Open Activity Log", OpenActivityLog)
    gHubControlMenu.Add("Open Data Folder", OpenHubDataFolder)
    gHubControlMenu.Add()
    gHubControlMenu.Add("Exit Script Hub", ExitHub)
    A_TrayMenu.Add("Script Hub Controls", gHubControlMenu)

    A_TrayMenu.Add("Hotkey Map (all running)", ShowAllRunningHotkeys)
    A_TrayMenu.Add()
    A_TrayMenu.Add("Exit Script Hub", ExitHub)

    RebuildRunningTrayMenu()
    RefreshTrayConsolidationMenuState()
    UpdateStatusOnly()
}

RebuildRunningTrayMenu() {
    global gRunningMenu, gRunningMenuRows, gRunningScriptMenus
    global gRunningNativeMenus, gRunningHubToolMenus, gMirroredMenus
    global gTrayClients

    if !IsObject(gRunningMenu)
        return

    CleanupTrayClients()

    gRunningMenu.Delete()
    gRunningMenuRows := Map()
    gRunningScriptMenus := []
    gRunningNativeMenus := []
    gRunningHubToolMenus := []
    gMirroredMenus := []

    pos := 0

    for pid, inst in gRunning {
        SplitPath(inst.Path, &name)

        pos += 1
        label := name "   [PID " pid "]"

        ; If this script has ScriptHubClient.ahk loaded, its actual A_TrayMenu is
        ; reconstructed here. The script's standard AHK items and any custom
        ; items/submenus therefore appear directly under its Hub submenu.
        if (gTrayClients.Has(pid) && SamePath(gTrayClients[pid].Path, inst.Path)) {
            client := gTrayClients[pid]
            scriptMenu := BuildMirroredTrayMenu(pid, client.Items)

            ; Hub-only management stays visually separate from the script's real
            ; tray menu, so the cloned menu remains recognizable and predictable.
            if (client.Items.Length > 0)
                scriptMenu.Add()

            hubTools := BuildPerScriptHubTools(pid, inst.Path)
            gRunningHubToolMenus.Push(hubTools)
            scriptMenu.Add("Script Hub Management", hubTools)
        } else {
            ; Fallback for an unmodified AHK script. Standard commands can still
            ; be sent natively; its custom menu cannot be introspected safely
            ; across process boundaries without the cooperative include.
            nativeMenu := BuildFallbackNativeMenu(pid)
            gRunningNativeMenus.Push(nativeMenu)

            scriptMenu := Menu()
            scriptMenu.Add("Native AutoHotkey Tray / Controls", nativeMenu)
            scriptMenu.Add()

            hubTools := BuildPerScriptHubTools(pid, inst.Path)
            gRunningHubToolMenus.Push(hubTools)
            scriptMenu.Add("Script Hub Management", hubTools)
            scriptMenu.Add()
            scriptMenu.Add(
                "Enable FULL tray mirroring for this script...",
                ExplainFullTrayMirroring.Bind(inst.Path)
            )
        }

        gRunningScriptMenus.Push(scriptMenu)

        try gRunningMenu.Add(label, scriptMenu)
        catch {
            ; Menu labels can collide only in unusual PID/title edge cases.
            label := name "   [PID " pid "] #" pos
            gRunningMenu.Add(label, scriptMenu)
        }

        gRunningMenuRows[pos] := {
            PID: pid,
            Path: inst.Path
        }
    }

    if (pos = 0) {
        gRunningMenu.Add("(none running)", NoOpMenu)
        gRunningMenu.Disable("(none running)")
    }
}

BuildFallbackNativeMenu(pid) {
    nativeMenu := Menu()
    nativeMenu.Add(
        "Run Script Tray Default Action",
        RunningNativeDefaultAction.Bind(pid)
    )
    nativeMenu.Add(
        "Open Original / Custom Tray Menu...",
        RunningNativeTrayMenu.Bind(pid)
    )
    nativeMenu.Add()
    nativeMenu.Add(
        "Open / Lines (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_OPEN)
    )
    nativeMenu.Add(
        "Help (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_HELP)
    )
    nativeMenu.Add(
        "Window Spy (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_WINDOWSPY)
    )
    nativeMenu.Add()
    nativeMenu.Add(
        "Reload Script (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_RELOAD)
    )
    nativeMenu.Add(
        "Edit Script (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_EDIT)
    )
    nativeMenu.Add(
        "Toggle Suspend Hotkeys (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_SUSPEND)
    )
    nativeMenu.Add(
        "Toggle Pause Script (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_PAUSE)
    )
    nativeMenu.Add()
    nativeMenu.Add(
        "Exit Script (native)",
        RunningNativeCommand.Bind(pid, ID_TRAY_EXIT)
    )
    return nativeMenu
}

BuildPerScriptHubTools(pid, path) {
    menu := Menu()
    menu.Add("Open / Select in Script Hub", RunningTrayOpen.Bind(pid, path))
    menu.Add("Run New Instance", RunningTrayRun.Bind(path))
    menu.Add("Restart Script (stop + relaunch)", RunningTrayRestart.Bind(path))
    menu.Add("Stop / Exit Script", RunningTrayStop.Bind(path))
    menu.Add()
    menu.Add("Edit in VS Code", RunningTrayVSCode.Bind(path))
    menu.Add("Edit in SciTE", RunningTraySciTE.Bind(path))
    menu.Add("Open Containing Folder", RunningTrayFolder.Bind(path))
    menu.Add("Copy Script Path", RunningTrayCopy.Bind(path))
    menu.Add("Show Hotkeys / Mappings", RunningTrayHotkeys.Bind(path))
    return menu
}

BuildMirroredTrayMenu(pid, items) {
    global gMirroredMenus

    if (items.Length = 0) {
        menu := Menu()
        menu.Add("(script tray menu is empty)", NoOpMenu)
        menu.Disable("(script tray menu is empty)")
        gMirroredMenus.Push(menu)
        return menu
    }

    index := 1
    return BuildMirroredTrayLevel(pid, items, &index, 0)
}

BuildMirroredTrayLevel(pid, items, &index, depth) {
    global gMirroredMenus

    menu := Menu()
    gMirroredMenus.Push(menu)
    usedLabels := Map()

    while (index <= items.Length) {
        item := items[index]

        if (item.Depth < depth)
            break

        ; A depth jump larger than one means a malformed snapshot. Skip only the
        ; invalid record rather than destroying the rest of the menu.
        if (item.Depth > depth) {
            index += 1
            continue
        }

        index += 1

        if (item.Kind = "S") {
            menu.Add()
            continue
        }

        visibleText := item.Text != "" ? item.Text : "(unnamed item)"
        itemLabel := UniqueMirroredMenuLabel(visibleText, usedLabels)

        if (item.Kind = "M") {
            subMenu := BuildMirroredTrayLevel(pid, items, &index, depth + 1)
            menu.Add(itemLabel, subMenu)
        } else {
            menu.Add(itemLabel, MirroredTrayCommand.Bind(pid, item.ID))
        }

        ApplyMirroredMenuState(menu, itemLabel, item.State)
    }

    return menu
}

UniqueMirroredMenuLabel(label, usedLabels) {
    ; AutoHotkey addresses Menu items by label. Two equal labels in a source
    ; Win32 menu therefore need invisible disambiguation in the cloned Menu.
    if !usedLabels.Has(label) {
        usedLabels[label] := 1
        return label
    }

    count := usedLabels[label] + 1
    usedLabels[label] := count
    suffix := ""
    Loop count - 1
        suffix .= Chr(0x200B)
    return label suffix
}

ApplyMirroredMenuState(menu, itemLabel, state) {
    ; Win32 MFS_CHECKED=0x8, MFS_DISABLED/GRAYED=0x3,
    ; MFS_DEFAULT=0x1000. These are published by ScriptHubClient.ahk.
    if (state & 0x0008)
        try menu.Check(itemLabel)

    if (state & 0x0003)
        try menu.Disable(itemLabel)

    if (state & 0x1000)
        try menu.Default := itemLabel
}

MirroredTrayCommand(pid, commandId, *) {
    if !commandId
        return

    ; AutoHotkey's tray Menu uses ordinary command IDs. Sending WM_COMMAND to
    ; the owning script's hidden main window invokes the SAME callback that the
    ; source tray menu item would have invoked.
    PostAhkNativeCommand(pid, commandId)
}

ExplainFullTrayMirroring(path, *) {
    includeLine := '#Include "%A_AppData%\AHKScriptHub\ScriptHubClient.ahk"'
    A_Clipboard := includeLine

    MsgBox(
        "This script is using fallback mode because it has not published its "
        . "A_TrayMenu to Script Hub.`n`n"
        . "Add this line near the top of the script, then reload it:`n`n"
        . includeLine
        . "`n`nThe include line has been copied to the clipboard.`n`n"
        . "Script:`n" path,
        "Enable Full Tray Mirroring",
        "Iconi"
    )
}

; ============================================================================
; COOPERATIVE FULL TRAY-MENU BRIDGE
; ============================================================================

InitTrayBridge() {
    global gIpcGui, gHubQueryMsg
    global HUB_IPC_TITLE, HUB_QUERY_MESSAGE_NAME, WM_COPYDATA_MSG

    ; Merely creating the GUI creates a hidden HWND which client includes can
    ; discover with DetectHiddenWindows. It is never shown to the user.
    gIpcGui := Gui("+ToolWindow -Caption", HUB_IPC_TITLE)
    ignoredHwnd := gIpcGui.Hwnd

    OnMessage(WM_COPYDATA_MSG, HubReceiveCopyData)

    gHubQueryMsg := DllCall(
        "User32\RegisterWindowMessageW",
        "Str", HUB_QUERY_MESSAGE_NAME,
        "UInt"
    )

    if gHubQueryMsg
        OnMessage(gHubQueryMsg, HubQueryConsolidationState)

    LogEvent("BRIDGE", "Full tray-menu IPC ready. hwnd=" ignoredHwnd)
}

HubQueryConsolidationState(wParam, lParam, msg, hwnd) {
    global gTrayConsolidationEnabled
    return gTrayConsolidationEnabled ? 1 : 0
}

HubReceiveCopyData(wParam, lParam, msg, hwnd) {
    global HUB_COPYDATA_MAGIC, gTrayClients

    if !lParam
        return 0

    magic := NumGet(lParam, 0, "UPtr")
    if (magic != HUB_COPYDATA_MAGIC)
        return 0

    byteCount := NumGet(lParam, A_PtrSize, "UInt")
    textPtr := NumGet(lParam, A_PtrSize * 2, "Ptr")

    if (!textPtr || byteCount < 4)
        return 0

    ; cbData includes the UTF-16 terminator.
    charCount := Max(0, (byteCount // 2) - 1)
    payload := StrGet(textPtr, charCount, "UTF-16")
    client := ParseTrayClientPayload(payload)

    if !IsObject(client)
        return 0

    ; Verify that the sender HWND belongs to the PID claimed in the snapshot.
    if wParam {
        senderPid := 0
        try {
            senderPid := WinGetPID("ahk_id " wParam)
        }

        if (senderPid && senderPid != client.PID)
            return 0
    }

    gTrayClients[client.PID] := client

    ; Rebuild only after WM_COPYDATA unwinds; this avoids doing significant Menu
    ; work while the client is synchronously blocked inside SendMessage.
    SetTimer(RebuildRunningTrayMenu, -1)
    return 1
}

ParseTrayClientPayload(payload) {
    lines := StrSplit(payload, "`n", "`r")
    if (lines.Length < 1)
        return 0

    header := StrSplit(lines[1], "`t")
    if (header.Length < 4 || header[1] != "AHKSH1")
        return 0

    pid := SafeInt(header[2])
    targetHwnd := SafeInt(header[3])
    path := DecodeField(header[4])

    if (!pid || !targetHwnd || path = "")
        return 0

    items := []

    Loop lines.Length - 1 {
        line := lines[A_Index + 1]
        if (line = "")
            continue

        fields := StrSplit(line, "`t")
        if (fields.Length < 6 || fields[1] != "I")
            continue

        depth := Max(0, SafeInt(fields[2]))
        kind := fields[3]
        id := SafeInt(fields[4])
        state := SafeInt(fields[5])
        text := DecodeField(fields[6])

        if !(kind = "S" || kind = "M" || kind = "C")
            continue

        items.Push({
            Depth: depth,
            Kind: kind,
            ID: id,
            State: state,
            Text: text
        })
    }

    return {
        PID: pid,
        Hwnd: targetHwnd,
        Path: NormalizePath(path),
        Items: items,
        LastTick: A_TickCount
    }
}

CleanupTrayClients() {
    global gTrayClients

    for pid, client in CloneMap(gTrayClients) {
        alive := false
        try alive := !!ProcessExist(pid)

        if !alive
            gTrayClients.Delete(pid)
    }
}

RunningNativeCommand(pid, commandId, *) {
    PostAhkNativeCommand(pid, commandId)
}

RunningNativeDefaultAction(pid, *) {
    global WM_LBUTTONDBLCLK_MSG
    PostAhkTrayMouseEvent(pid, WM_LBUTTONDBLCLK_MSG)
}

RunningNativeTrayMenu(pid, *) {
    global WM_RBUTTONUP_MSG
    PostAhkTrayMouseEvent(pid, WM_RBUTTONUP_MSG)
}

PostAhkNativeCommand(pid, commandId) {
    global WM_COMMAND_MSG

    hwnd := GetRunningAhkMainHwnd(pid)
    if !hwnd {
        ScriptControlUnavailable(pid)
        return false
    }

    result := DllCall(
        "User32\PostMessageW",
        "Ptr", hwnd,
        "UInt", WM_COMMAND_MSG,
        "UPtr", commandId,
        "Ptr", 0,
        "Int"
    )

    if !result {
        ScriptControlUnavailable(pid)
        return false
    }

    return true
}

PostAhkTrayMouseEvent(pid, mouseMessage) {
    global AHK_NOTIFYICON_MSG

    hwnd := GetRunningAhkMainHwnd(pid)
    if !hwnd {
        ScriptControlUnavailable(pid)
        return false
    }

    ; This is the same callback AutoHotkey receives when its own tray icon is
    ; clicked. WM_RBUTTONUP therefore opens the target script's real A_TrayMenu,
    ; including custom items. WM_LBUTTONDBLCLK runs its configured default item.
    result := DllCall(
        "User32\PostMessageW",
        "Ptr", hwnd,
        "UInt", AHK_NOTIFYICON_MSG,
        "UPtr", AHK_NOTIFYICON_MSG,
        "Ptr", mouseMessage,
        "Int"
    )

    if !result {
        ScriptControlUnavailable(pid)
        return false
    }

    return true
}

ScriptControlUnavailable(pid) {
    ToolTip(
        "Could not send the command to AutoHotkey PID " pid "."
        . "`nIf that script is elevated, run Script Hub elevated too."
    )
    SetTimer((*) => ToolTip(), -2200)
}

GetRunningAhkMainHwnd(pid) {
    global gRunning

    if gRunning.Has(pid) {
        inst := gRunning[pid]
        if (inst.Hwnd && DllCall("User32\IsWindow", "Ptr", inst.Hwnd, "Int"))
            return inst.Hwnd
    }

    try hwnds := WinGetList("ahk_pid " pid " ahk_class AutoHotkey")
    catch
        return 0

    for , hwnd in hwnds {
        if hwnd
            return hwnd
    }

    return 0
}

ToggleTrayConsolidation(*) {
    global gTrayConsolidationEnabled

    gTrayConsolidationEnabled := !gTrayConsolidationEnabled

    if gTrayConsolidationEnabled
        ConsolidateRunningTrayIcons(true)
    else
        RestoreIndividualTrayIcons()

    RefreshTrayConsolidationMenuState()
}

RefreshTrayConsolidationMenuState() {
    global gHubControlMenu, gTrayConsolidationEnabled

    if !IsObject(gHubControlMenu)
        return

    item := "Consolidate AHK tray icons into this Hub"

    try {
        if gTrayConsolidationEnabled
            gHubControlMenu.Check(item)
        else
            gHubControlMenu.Uncheck(item)
    }
}

ConsolidateRunningTrayIcons(force := false, *) {
    global gRunning, gHiddenTrayIcons, gTrayConsolidationEnabled, gTrayClients

    if !gTrayConsolidationEnabled
        return

    live := Map()

    for pid, inst in gRunning {
        ; Cooperative clients hide themselves with A_IconHidden after querying
        ; Hub state, which is more reliable than modifying another process icon.
        if (gTrayClients.Has(pid) && SamePath(gTrayClients[pid].Path, inst.Path))
            continue

        hwnd := GetRunningAhkMainHwnd(pid)
        if !hwnd
            continue

        live[pid] := hwnd

        alreadyHidden := gHiddenTrayIcons.Has(pid)
            && gHiddenTrayIcons[pid] = hwnd

        if (!force && alreadyHidden)
            continue

        if SetAhkTrayIconHidden(hwnd, true)
            gHiddenTrayIcons[pid] := hwnd
    }

    ; Remove stale bookkeeping without touching processes that are already gone.
    for pid, hwnd in CloneMap(gHiddenTrayIcons) {
        if !live.Has(pid)
            gHiddenTrayIcons.Delete(pid)
    }
}

RestoreIndividualTrayIcons(*) {
    global gHiddenTrayIcons

    for pid, hwnd in CloneMap(gHiddenTrayIcons) {
        if DllCall("User32\IsWindow", "Ptr", hwnd, "Int")
            SetAhkTrayIconHidden(hwnd, false)
    }

    gHiddenTrayIcons := Map()
}

SetAhkTrayIconHidden(hwnd, hidden := true) {
    global AHK_NOTIFYICON_MSG

    ; Keep the notification icon registered and modify only NIS_HIDDEN. This is
    ; preferable to NIM_DELETE: peer TrayTip/TraySetIcon/native callbacks continue
    ; to work while the duplicate green-H icon is not shown in the tray.
    static NIM_MODIFY := 0x00000001
    static NIF_STATE := 0x00000008
    static NIS_HIDDEN := 0x00000001

    if !hwnd
        return false

    if (A_PtrSize = 8) {
        structSize := 976
        hwndOffset := 8
        uidOffset := 16
        flagsOffset := 20
        stateOffset := 296
        stateMaskOffset := 300
    } else {
        structSize := 956
        hwndOffset := 4
        uidOffset := 8
        flagsOffset := 12
        stateOffset := 280
        stateMaskOffset := 284
    }

    nid := Buffer(structSize, 0)
    NumPut("UInt", structSize, nid, 0)
    NumPut("Ptr", hwnd, nid, hwndOffset)
    NumPut("UInt", AHK_NOTIFYICON_MSG, nid, uidOffset)
    NumPut("UInt", NIF_STATE, nid, flagsOffset)
    NumPut("UInt", hidden ? NIS_HIDDEN : 0, nid, stateOffset)
    NumPut("UInt", NIS_HIDDEN, nid, stateMaskOffset)

    return !!DllCall(
        "Shell32\Shell_NotifyIconW",
        "UInt", NIM_MODIFY,
        "Ptr", nid.Ptr,
        "Int"
    )
}

HubTaskbarCreated(wParam, lParam, msg, hwnd) {
    global gHiddenTrayIcons, gTrayConsolidationEnabled

    ; Explorer just rebuilt the notification area and peer scripts will re-add
    ; their icons. Clear cached hidden state and apply it again after they settle.
    gHiddenTrayIcons := Map()

    if gTrayConsolidationEnabled
        SetTimer(ReapplyTrayConsolidation, -450)
}

ReapplyTrayConsolidation(*) {
    ConsolidateRunningTrayIcons(true)
}

RunningTrayClicked(itemName, itemPos, menuObj) {
    global gRunningMenuRows

    if !gRunningMenuRows.Has(itemPos)
        return

    item := gRunningMenuRows[itemPos]
    ShowMainGui()
    SelectPathInList(item.Path)
}

RunningTrayOpen(pid, path, *) {
    ShowMainGui()
    SelectPathInList(path)
}

RunningTrayRun(path, *) {
    RunManaged(path, "tray_run")
}

RunningTrayRestart(path, *) {
    RestartPath(path)
}

RunningTrayStop(path, *) {
    StopPath(path)
}

RunningTrayVSCode(path, *) {
    OpenInVSCode(path)
}

RunningTraySciTE(path, *) {
    OpenInSciTE(path)
}

RunningTrayFolder(path, *) {
    OpenContainingFolder(path)
}

RunningTrayCopy(path, *) {
    CopyPath(path)
}

RunningTrayHotkeys(path, *) {
    ShowHotkeyInspector(path)
}

NoOpMenu(*) {
}

RestartHub(*) {
    try {
        Run(Q(A_AhkPath) " " Q(A_ScriptFullPath) " /restart", A_ScriptDir)
        ExitApp
    } catch as err {
        MsgBox("Script Hub could not restart.`n`n" err.Message, APP_NAME, "Iconx")
    }
}

EditHubVSCode(*) {
    OpenInVSCode(A_ScriptFullPath)
}

EditHubSciTE(*) {
    OpenInSciTE(A_ScriptFullPath)
}

OpenHubFolder(*) {
    OpenContainingFolder(A_ScriptFullPath)
}

CopyHubPath(*) {
    CopyPath(A_ScriptFullPath)
}

OpenHubDataFolder(*) {
    if !DirExist(DATA_DIR)
        EnsureDataDirectory()
    try Run(Q(DATA_DIR))
}

ShowMainGui(*) {
    global gMainGui

    RefreshList()
    gMainGui.Show("w1200 h650")
    try WinRestore("ahk_id " gMainGui.Hwnd)
    try WinActivate("ahk_id " gMainGui.Hwnd)
}

IsMainGuiVisible() {
    global gMainGui

    if !IsObject(gMainGui)
        return false

    try return !!DllCall("IsWindowVisible", "Ptr", gMainGui.Hwnd, "Int")
    catch
        return false
}

MainGuiSize(guiObj, minMax, width, height) {
    global gList, gStatusText

    if (minMax = -1)
        return

    try gList.Move(, , Max(500, width - 24), Max(220, height - 170))
    try gStatusText.Move(, Max(100, height - 30), Max(500, width - 24))
}

RefreshList(*) {
    global gList, gSearchEdit, gFilterDDL, gScripts

    if !IsObject(gList)
        return

    selectedPathValue := SelectedPath()
    searchText := StrLower(Trim(gSearchEdit.Value))
    filterIndex := gFilterDDL.Value

    runningCounts := RunningCountsByPath()

    gList.Opt("-Redraw")
    gList.Delete()

    ; Two passes keep favorites pinned at the top without requiring a custom
    ; sorting dependency.
    for , favoritePass in [1, 0] {
        for key, rec in gScripts {
            if (rec.Favorite != favoritePass)
                continue

            exists := !!FileExist(rec.Path)
            running := runningCounts.Has(key)
                ? runningCounts[key].Count
                : 0

            if !RecordPassesFilter(rec, filterIndex, exists, running)
                continue

            SplitPath(rec.Path, &name)

            searchable := StrLower(
                name " " rec.Path " " rec.Tags " " rec.Notes
            )

            if (searchText != "" && !InStr(searchable, searchText))
                continue

            status := exists
                ? (running ? "Running (" running ")" : "Stopped")
                : "MISSING"

            gList.Add(
                "",
                rec.Favorite ? "★" : "",
                name,
                rec.RunCount,
                status,
                rec.LastRun,
                rec.FirstSeen,
                rec.AlwaysStart ? "Yes" : "",
                rec.Tags,
                rec.Path
            )
        }
    }

    gList.Opt("+Redraw")

    if (selectedPathValue != "")
        SelectPathInList(selectedPathValue)

    UpdateStatusOnly()
}

RecordPassesFilter(rec, filterIndex, exists, runningCount) {
    switch filterIndex {
        case 2:
            return runningCount > 0
        case 3:
            return rec.Favorite
        case 4:
            return rec.AlwaysStart
        case 5:
            return !exists
        default:
            return true
    }
}

UpdateStatusOnly() {
    global gStatusText, gScripts, gRunning

    if IsObject(gStatusText) {
        totalRuns := 0
        for key, rec in gScripts
            totalRuns += rec.RunCount

        gStatusText.Text := "Tracked: " gScripts.Count
            . "    Running instances: " gRunning.Count
            . "    Recorded launches: " totalRuns
            . "    Hotkey: Ctrl+Win+A"
            . "    Data: " DATA_DIR
    }

    try {
        A_IconTip := "AHK Script Hub"
            . "`nTracked: " gScripts.Count
            . "`nRunning: " gRunning.Count
    }
}

SelectedPath() {
    global gList

    if !IsObject(gList)
        return ""

    row := gList.GetNext(0, "F")

    if !row
        row := gList.GetNext()

    if !row
        return ""

    return gList.GetText(row, 9)
}

SelectPathInList(path) {
    global gList

    if !IsObject(gList)
        return false

    key := PathKey(path)

    Loop gList.GetCount() {
        rowPath := gList.GetText(A_Index, 9)

        if (PathKey(rowPath) = key) {
            gList.Modify(A_Index, "Select Focus Vis")
            return true
        }
    }

    return false
}

ListDoubleClick(ctrl, row) {
    if (row <= 0)
        return

    path := ctrl.GetText(row, 9)

    if (path != "")
        RunManaged(path, "double_click")
}

ListContextMenu(ctrl, item, isRightClick, x, y) {
    global gContextPath, gContextMenu

    if (item <= 0)
        return

    ctrl.Modify(item, "Select Focus")
    gContextPath := ctrl.GetText(item, 9)
    gContextMenu.Show(x, y)
}

RunSelected(*) {
    path := SelectedPath()
    if (path != "")
        RunManaged(path, "gui_run")
}

RestartSelected(*) {
    path := SelectedPath()
    if (path != "")
        RestartPath(path)
}

StopSelected(*) {
    path := SelectedPath()
    if (path != "")
        StopPath(path)
}

VSCodeSelected(*) {
    path := SelectedPath()
    if (path != "")
        OpenInVSCode(path)
}

SciTESelected(*) {
    path := SelectedPath()
    if (path != "")
        OpenInSciTE(path)
}

FolderSelected(*) {
    path := SelectedPath()
    if (path != "")
        OpenContainingFolder(path)
}

FavoriteSelected(*) {
    path := SelectedPath()
    if (path != "")
        ToggleFavorite(path)
}

AlwaysStartSelected(*) {
    path := SelectedPath()
    if (path != "")
        ToggleAlwaysStart(path)
}

MetadataSelected(*) {
    path := SelectedPath()
    if (path != "")
        EditMetadata(path)
}

CopySelectedPath(*) {
    path := SelectedPath()
    if (path != "")
        CopyPath(path)
}

; ----------------------------- CONTEXT ACTIONS ------------------------------

ContextRun(*) {
    global gContextPath
    RunManaged(gContextPath, "context_run")
}

ContextRunAdmin(*) {
    global gContextPath
    RunManaged(gContextPath, "context_run_admin", true)
}

ContextRestart(*) {
    global gContextPath
    RestartPath(gContextPath)
}

ContextStop(*) {
    global gContextPath
    StopPath(gContextPath)
}

ContextVSCode(*) {
    global gContextPath
    OpenInVSCode(gContextPath)
}

ContextSciTE(*) {
    global gContextPath
    OpenInSciTE(gContextPath)
}

ContextFolder(*) {
    global gContextPath
    OpenContainingFolder(gContextPath)
}

ContextCopy(*) {
    global gContextPath
    CopyPath(gContextPath)
}

ContextHotkeys(*) {
    global gContextPath
    ShowHotkeyInspector(gContextPath)
}

ContextFavorite(*) {
    global gContextPath
    ToggleFavorite(gContextPath)
}

ContextAlways(*) {
    global gContextPath
    ToggleAlwaysStart(gContextPath)
}

ContextMetadata(*) {
    global gContextPath
    EditMetadata(gContextPath)
}

ContextRelocate(*) {
    global gContextPath
    RelocateRecord(gContextPath)
}

ContextRemove(*) {
    global gContextPath
    RemoveRecord(gContextPath)
}

; ============================================================================
; RUNNING SCRIPT HOTKEY INSPECTOR
; ============================================================================

ShowAllRunningHotkeys(*) {
    ShowHotkeyInspector("")
}

ShowHotkeyInspector(scriptPath := "", *) {
    global gHotkeyGui, gHotkeyScriptFilter

    gHotkeyScriptFilter := NormalizePath(scriptPath)
    if !IsObject(gHotkeyGui)
        BuildHotkeyInspectorGui()

    RefreshHotkeyInspector(true)
    gHotkeyGui.Show("w1320 h680")
    try WinRestore("ahk_id " gHotkeyGui.Hwnd)
    try WinActivate("ahk_id " gHotkeyGui.Hwnd)
}

BuildHotkeyInspectorGui() {
    global gHotkeyGui, gHotkeySearchEdit, gHotkeyList, gHotkeyStatus

    gHotkeyGui := Gui("+Resize MinSize920x460", "Running Script Hotkey Map - " APP_NAME)
    gHotkeyGui.SetFont("s9", "Segoe UI")

    gHotkeyGui.AddText("xm ym+4", "Filter:")
    gHotkeySearchEdit := gHotkeyGui.AddEdit("x+6 yp-4 w300")
    btnRefresh := gHotkeyGui.AddButton("x+8 yp w82", "Refresh")
    btnAll := gHotkeyGui.AddButton("x+6 w112", "All Running")
    btnCopyMap := gHotkeyGui.AddButton("x+6 w116", "Copy Mapping")
    btnCopyPath := gHotkeyGui.AddButton("x+6 w132", "Copy Script Path")
    btnOpenSource := gHotkeyGui.AddButton("x+6 w112", "Open at Line")

    gHotkeyList := gHotkeyGui.AddListView(
        "xm y+10 w1295 h560 Grid -Multi AltSubmit",
        ["Running script", "PID(s)", "Hotkey", "Maps to", "#HotIf / scope", "Source file", "Line", "Root path"]
    )
    gHotkeyList.ModifyCol(1, 170)
    gHotkeyList.ModifyCol(2, 85)
    gHotkeyList.ModifyCol(3, 190)
    gHotkeyList.ModifyCol(4, 285)
    gHotkeyList.ModifyCol(5, 220)
    gHotkeyList.ModifyCol(6, 175)
    gHotkeyList.ModifyCol(7, 55)
    gHotkeyList.ModifyCol(8, 0)

    gHotkeyStatus := gHotkeyGui.AddText(
        "xm y+8 w1295",
        "Static labels and Hotkey() registrations are resolved from every running script and its local includes."
    )

    gHotkeySearchEdit.OnEvent("Change", QueueHotkeyInspectorRefresh)
    btnRefresh.OnEvent("Click", ForceRefreshHotkeyInspector)
    btnAll.OnEvent("Click", ShowAllHotkeysInInspector)
    btnCopyMap.OnEvent("Click", CopySelectedHotkeyMapping)
    btnCopyPath.OnEvent("Click", CopySelectedHotkeyScriptPath)
    btnOpenSource.OnEvent("Click", OpenSelectedHotkeySource)
    gHotkeyList.OnEvent("DoubleClick", HotkeyListDoubleClick)
    gHotkeyList.OnEvent("ContextMenu", HotkeyListContextMenu)
    gHotkeyList.OnEvent("Click", UpdateHotkeyInspectorStatus)
    gHotkeyList.OnEvent("ItemFocus", UpdateHotkeyInspectorStatus)

    gHotkeyGui.OnEvent("Close", (*) => gHotkeyGui.Hide())
    gHotkeyGui.OnEvent("Escape", (*) => gHotkeyGui.Hide())
    gHotkeyGui.OnEvent("Size", HotkeyInspectorSize)
    BuildHotkeyInspectorContextMenu()
}

BuildHotkeyInspectorContextMenu() {
    global gHotkeyContextMenu

    gHotkeyContextMenu := Menu()
    gHotkeyContextMenu.Add("Copy hotkey + mapping", CopySelectedHotkeyMapping)
    gHotkeyContextMenu.Add("Copy running script path", CopySelectedHotkeyScriptPath)
    gHotkeyContextMenu.Add("Copy source file path", CopySelectedHotkeySourcePath)
    gHotkeyContextMenu.Add()
    gHotkeyContextMenu.Add("Open source at line", OpenSelectedHotkeySource)
    gHotkeyContextMenu.Add("Open running script in VS Code", OpenSelectedHotkeyRoot)
    gHotkeyContextMenu.Add("Open containing folder", OpenSelectedHotkeyFolder)
}

HotkeyInspectorSize(guiObj, minMax, width, height) {
    global gHotkeyList, gHotkeyStatus

    if (minMax = -1)
        return
    try gHotkeyList.Move(, , Max(700, width - 24), Max(260, height - 108))
    try gHotkeyStatus.Move(, Max(100, height - 29), Max(700, width - 24))
}

QueueHotkeyInspectorRefresh(*) {
    SetTimer(RefreshHotkeyInspector, 0)
    SetTimer(RefreshHotkeyInspector, -180)
}

ForceRefreshHotkeyInspector(*) {
    RefreshHotkeyInspector(true)
}

ShowAllHotkeysInInspector(*) {
    global gHotkeyScriptFilter
    gHotkeyScriptFilter := ""
    RefreshHotkeyInspector(true)
}

RefreshHotkeyInspector(forceScan := false, *) {
    global gHotkeyList, gHotkeySearchEdit, gHotkeyStatus, gHotkeyRows
    global gHotkeyScriptFilter, gHotkeyScanCache, gHotkeyScanSignature

    if !IsObject(gHotkeyList)
        return

    try FastWindowScan()
    signature := RunningHotkeySignature()
    if (forceScan || signature != gHotkeyScanSignature) {
        gHotkeyScanCache := ScanAllRunningHotkeys()
        gHotkeyScanSignature := signature
    }

    search := StrLower(Trim(gHotkeySearchEdit.Value))
    filterKey := gHotkeyScriptFilter = "" ? "" : PathKey(gHotkeyScriptFilter)
    selected := SelectedHotkeyData()
    selectedKey := IsObject(selected)
        ? PathKey(selected.SourcePath) "|" selected.Line "|" selected.Raw
        : ""

    gHotkeyRows := Map()
    gHotkeyList.Opt("-Redraw")
    gHotkeyList.Delete()
    visibleCount := 0
    visibleScripts := Map()

    for entry in gHotkeyScanCache {
        if (filterKey != "" && PathKey(entry.RootPath) != filterKey)
            continue

        searchable := StrLower(
            entry.ScriptName " " entry.PIDs " " entry.Display " " entry.Raw " "
            . entry.Mapping " " entry.Context " " entry.SourcePath " " entry.RootPath
        )
        if (search != "" && !InStr(searchable, search))
            continue

        SplitPath(entry.SourcePath, &sourceName)
        row := gHotkeyList.Add(
            "",
            entry.ScriptName,
            entry.PIDs,
            entry.Display,
            entry.Mapping,
            entry.Context,
            sourceName,
            entry.Line,
            entry.RootPath
        )
        gHotkeyRows[row] := entry
        visibleCount += 1
        visibleScripts[PathKey(entry.RootPath)] := true

        rowKey := PathKey(entry.SourcePath) "|" entry.Line "|" entry.Raw
        if (selectedKey != "" && rowKey = selectedKey)
            gHotkeyList.Modify(row, "Select Focus Vis")
    }

    gHotkeyList.Opt("+Redraw")
    scopeText := filterKey = "" ? "all running scripts" : "selected script"
    gHotkeyStatus.Text := visibleCount " hotkey mapping(s) across " visibleScripts.Count
        . " script(s) | " scopeText
        . " | Static source analysis; runtime-generated key names remain expressions."
}

RunningHotkeySignature() {
    groups := CollectRunningScriptGroups()
    signature := ""
    for key, info in groups {
        modified := ""
        try modified := FileGetTime(info.Path, "M")
        signature .= key "|" JoinText(info.PIDs, ",") "|" modified ";"
    }
    return signature
}

ScanAllRunningHotkeys() {
    groups := CollectRunningScriptGroups()
    allEntries := []

    for key, info in groups {
        SplitPath(info.Path, &scriptName)
        pidText := JoinText(info.PIDs, ", ")
        found := ExtractScriptHotkeys(info.Path)

        if !found.Length {
            allEntries.Push({
                RootPath: info.Path,
                SourcePath: info.Path,
                ScriptName: scriptName,
                PIDs: pidText,
                Raw: "",
                Display: "(none detected)",
                Mapping: "No static hotkey labels or Hotkey() registrations found",
                Context: "",
                Line: ""
            })
            continue
        }

        for entry in found {
            entry.ScriptName := scriptName
            entry.PIDs := pidText
            allEntries.Push(entry)
        }
    }
    return allEntries
}

CollectRunningScriptGroups() {
    global gRunning

    groups := Map()
    ownPath := NormalizePath(A_ScriptFullPath)
    ownKey := PathKey(ownPath)
    groups[ownKey] := {
        Path: ownPath,
        PIDs: [DllCall("GetCurrentProcessId", "UInt")]
    }

    for pid, instance in gRunning {
        path := NormalizePath(instance.Path)
        if (path = "")
            continue
        key := PathKey(path)
        if !groups.Has(key)
            groups[key] := {Path:path, PIDs:[]}
        if !ArrayHasValue(groups[key].PIDs, pid)
            groups[key].PIDs.Push(pid)
    }
    return groups
}

ExtractScriptHotkeys(rootPath) {
    entries := []
    visited := Map()
    ParseHotkeyFile(NormalizePath(rootPath), NormalizePath(rootPath), visited, entries, 0)
    return entries
}

ParseHotkeyFile(sourcePath, rootPath, visited, entries, depth) {
    if (depth > 30 || visited.Count >= 300 || !FileExist(sourcePath))
        return
    key := PathKey(sourcePath)
    if visited.Has(key)
        return
    visited[key] := true

    try text := FileRead(sourcePath, "UTF-8")
    catch {
        try text := FileRead(sourcePath)
        catch
            return
    }

    lines := StrSplit(text, "`n", "`r")
    symbols := Map()
    for line in lines {
        if RegExMatch(
            line,
            "^\s*(?:(?i:global)\s+)?([A-Z_][A-Z0-9_]*)\s*:=\s*\x22([^\x22]*)\x22",
            &symbolMatch
        )
            symbols[StrLower(symbolMatch[1])] := symbolMatch[2]
    }

    context := "Global"
    dynamicContext := "Global"
    for lineNumber, rawLine in lines {
        code := Trim(StripAhkComment(rawLine))
        if (code = "")
            continue

        if RegExMatch(code, "i)^#HotIf(?:\s+(.*))?$", &contextMatch) {
            context := contextMatch[1] != "" ? contextMatch[1] : "Global"
            continue
        }

        if RegExMatch(code, "i)^HotIf\((.*)\)\s*$", &dynamicContextMatch) {
            dynamicContext := Trim(dynamicContextMatch[1])
            if (dynamicContext = "")
                dynamicContext := "Global"
            continue
        }

        if RegExMatch(code, "i)^#Include(?:Again)?\s+(.+)$", &includeMatch) {
            includePath := ResolveAhkInclude(includeMatch[1], sourcePath, rootPath)
            if (includePath != "")
                ParseHotkeyFile(includePath, rootPath, visited, entries, depth + 1)
            continue
        }

        if RegExMatch(rawLine, "^\s*([^;\r\n]+?)::\s*(.*)$", &labelMatch) {
            rawHotkey := Trim(labelMatch[1])
            if IsLikelyHotkeySpec(rawHotkey) {
                mapping := Trim(StripAhkComment(labelMatch[2]))
                if (mapping = "" || mapping = "{")
                    mapping := SummarizeHotkeyBlock(lines, lineNumber + 1)
                if (mapping = "")
                    mapping := "(block handler)"
                entries.Push({
                    RootPath: rootPath,
                    SourcePath: sourcePath,
                    Raw: rawHotkey,
                    Display: DescribeAhkHotkey(rawHotkey),
                    Mapping: CleanHotkeyMapping(mapping),
                    Context: context,
                    Line: lineNumber
                })
                continue
            }
        }

        if RegExMatch(
            code,
            "i)^(?:try\s+)?Hotkey\(\s*(\x22[^\x22]*\x22|[A-Z_]\w*)\s*,\s*(.+)\)\s*$",
            &hotkeyMatch
        ) {
            rawHotkey := Trim(hotkeyMatch[1])
            if (SubStr(rawHotkey, 1, 1) = Chr(34))
                rawHotkey := SubStr(rawHotkey, 2, -1)
            else if (
                symbols.Has(StrLower(rawHotkey))
                && symbols[StrLower(rawHotkey)] != ""
            )
                rawHotkey := symbols[StrLower(rawHotkey)]

            mapping := RegExReplace(
                Trim(hotkeyMatch[2]),
                "i),\s*\x22(?:On|Off|Toggle|AltTab.*)\x22\s*$"
            )
            entries.Push({
                RootPath: rootPath,
                SourcePath: sourcePath,
                Raw: rawHotkey,
                Display: DescribeAhkHotkey(rawHotkey),
                Mapping: CleanHotkeyMapping(mapping),
                Context: dynamicContext,
                Line: lineNumber
            })
        }
    }
}

ResolveAhkInclude(includeText, sourcePath, rootPath) {
    includeText := Trim(StripAhkComment(includeText))
    includeText := RegExReplace(includeText, "i)^\*i\s+")
    if (includeText = "")
        return ""

    SplitPath(sourcePath, , &sourceDir)
    SplitPath(rootPath, , &rootDir)

    if (SubStr(includeText, 1, 1) = "<" && SubStr(includeText, -1) = ">") {
        libraryName := SubStr(includeText, 2, -1)
        if !RegExMatch(libraryName, "i)\.ahk$")
            libraryName .= ".ahk"
        candidates := [
            sourceDir "\Lib\" libraryName,
            rootDir "\Lib\" libraryName,
            A_MyDocuments "\AutoHotkey\Lib\" libraryName
        ]
        for candidate in candidates {
            if FileExist(candidate)
                return NormalizePath(candidate)
        }
        return ""
    }

    includeText := Trim(includeText, " `t" Chr(34))
    includeText := StrReplace(includeText, "%A_ScriptDir%", rootDir)
    includeText := StrReplace(includeText, "%A_LineFile%", sourcePath)
    if RegExMatch(includeText, "[\*\?]")
        return ""
    if !IsAbsolutePath(includeText)
        includeText := sourceDir "\" includeText
    includeText := NormalizePath(includeText)
    return FileExist(includeText) ? includeText : ""
}

IsLikelyHotkeySpec(spec) {
    spec := Trim(spec)
    if (spec = "" || SubStr(spec, 1, 1) = ":")
        return false
    for blockedCharacter in [Chr(34), "'", "=", "(", ")", ","] {
        if InStr(spec, blockedCharacter)
            return false
    }
    return RegExMatch(spec, "i)^[~*$<>#!^+A-Z0-9_\s&\-\.]+(?:\s+Up)?$") != 0
}

SummarizeHotkeyBlock(lines, startLine) {
    parts := []
    maxLine := Min(lines.Length, startLine + 18)
    Loop maxLine - startLine + 1 {
        index := startLine + A_Index - 1
        code := Trim(StripAhkComment(lines[index]))
        if (code = "" || code = "{" || code = "return")
            continue
        if (code = "}")
            break
        if (parts.Length && RegExMatch(code, "^\s*[^;]+::"))
            break
        parts.Push(code)
        if (parts.Length >= 3)
            break
    }
    return JoinText(parts, " `; ")
}

CleanHotkeyMapping(mapping) {
    mapping := Trim(mapping)
    mapping := RegExReplace(mapping, "\s+", " ")
    if RegExMatch(mapping, "i)ObjBindMethod\([^,]+,\s*\x22([^\x22]+)\x22", &methodMatch)
        return methodMatch[1] "() [bound method]"
    if RegExMatch(mapping, "i)^([A-Z_]\w*)$", &functionMatch)
        return functionMatch[1] "()"
    return TruncateHotkeyText(mapping, 220)
}

DescribeAhkHotkey(rawHotkey) {
    rawHotkey := Trim(rawHotkey)
    if (rawHotkey = "")
        return ""

    suffix := ""
    if RegExMatch(rawHotkey, "i)\s+Up$", &upMatch) {
        rawHotkey := RegExReplace(rawHotkey, "i)\s+Up$")
        suffix := " (release)"
    }

    modifiers := []
    position := 1
    while (position <= StrLen(rawHotkey)) {
        character := SubStr(rawHotkey, position, 1)
        if InStr("~*$", character) {
            position += 1
            continue
        }
        if ((character = "<" || character = ">") && position < StrLen(rawHotkey)) {
            side := character = "<" ? "Left " : "Right "
            nextCharacter := SubStr(rawHotkey, position + 1, 1)
            if InStr("^!+#", nextCharacter) {
                modifiers.Push(side ModifierName(nextCharacter))
                position += 2
                continue
            }
        }
        if InStr("^!+#", character) {
            modifiers.Push(ModifierName(character))
            position += 1
            continue
        }
        break
    }

    keyName := SubStr(rawHotkey, position)
    readable := modifiers.Length ? JoinText(modifiers, "+") "+" keyName : keyName
    return readable suffix "  [" rawHotkey (suffix != "" ? " Up" : "") "]"
}

ModifierName(symbol) {
    switch symbol {
        case "^": return "Ctrl"
        case "!": return "Alt"
        case "+": return "Shift"
        case "#": return "Win"
    }
    return symbol
}

StripAhkComment(text) {
    inQuote := false
    length := StrLen(text)
    Loop length {
        position := A_Index
        character := SubStr(text, position, 1)
        if (character = Chr(34)) {
            if (inQuote && position < length && SubStr(text, position + 1, 1) = Chr(34)) {
                position += 1
                continue
            }
            inQuote := !inQuote
            continue
        }
        if (!inQuote && character = ";") {
            previous := position > 1 ? SubStr(text, position - 1, 1) : " "
            if (position = 1 || previous = " " || previous = "`t")
                return RTrim(SubStr(text, 1, position - 1))
        }
    }
    return RTrim(text)
}

JoinText(values, separator := "") {
    result := ""
    for value in values
        result .= (result = "" ? "" : separator) value
    return result
}

ArrayHasValue(values, wanted) {
    for value in values {
        if (value = wanted)
            return true
    }
    return false
}

TruncateHotkeyText(text, maximum) {
    return StrLen(text) > maximum ? SubStr(text, 1, maximum - 3) "..." : text
}

SelectedHotkeyData(row := 0) {
    global gHotkeyList, gHotkeyRows
    if !IsObject(gHotkeyList)
        return 0
    if !row
        row := gHotkeyList.GetNext(0, "F")
    if !row
        row := gHotkeyList.GetNext()
    return (row && gHotkeyRows.Has(row)) ? gHotkeyRows[row] : 0
}

UpdateHotkeyInspectorStatus(ctrl, row := 0, *) {
    global gHotkeyStatus
    entry := SelectedHotkeyData(row)
    if !IsObject(entry)
        return
    gHotkeyStatus.Text := entry.Display "  ->  " entry.Mapping
        . " | " entry.SourcePath (entry.Line != "" ? ":" entry.Line : "")
}

HotkeyListDoubleClick(ctrl, row, *) {
    if row
        OpenSelectedHotkeySource(row)
}

HotkeyListContextMenu(ctrl, row, isRightClick, x, y) {
    global gHotkeyContextMenu, gHotkeyContextRow
    if !isRightClick || row <= 0
        return
    ctrl.Modify(row, "Select Focus")
    gHotkeyContextRow := row
    gHotkeyContextMenu.Show(x, y)
}

CopySelectedHotkeyMapping(*) {
    entry := SelectedHotkeyData()
    if !IsObject(entry)
        return
    A_Clipboard := entry.Display " -> " entry.Mapping
        . (entry.Context != "" ? " | Scope: " entry.Context : "")
        . " | " entry.SourcePath ":" entry.Line
    ToolTip("Hotkey mapping copied")
    SetTimer((*) => ToolTip(), -1000)
}

CopySelectedHotkeyScriptPath(*) {
    entry := SelectedHotkeyData()
    if IsObject(entry)
        CopyPath(entry.RootPath)
}

CopySelectedHotkeySourcePath(*) {
    entry := SelectedHotkeyData()
    if IsObject(entry)
        CopyPath(entry.SourcePath)
}

OpenSelectedHotkeySource(row := 0, *) {
    entry := SelectedHotkeyData(row)
    if !IsObject(entry) || !FileExist(entry.SourcePath)
        return
    OpenSourceAtLine(entry.SourcePath, entry.Line)
}

OpenSelectedHotkeyRoot(*) {
    entry := SelectedHotkeyData()
    if IsObject(entry)
        OpenInVSCode(entry.RootPath)
}

OpenSelectedHotkeyFolder(*) {
    entry := SelectedHotkeyData()
    if IsObject(entry)
        OpenContainingFolder(entry.SourcePath)
}

OpenSourceAtLine(path, lineNumber := 1) {
    exe := FindVSCode()
    SplitPath(path, , &workingDir)
    lineNumber := IsNumber(lineNumber) && lineNumber > 0 ? lineNumber : 1
    try {
        if (exe != "")
            Run(Q(exe) " --reuse-window --goto " Q(path ":" lineNumber), workingDir)
        else
            Run("code --reuse-window --goto " Q(path ":" lineNumber), workingDir)
    } catch {
        OpenInSciTE(path)
    }
}

; ============================================================================
; METADATA / IMPORT / EXPORT / HISTORY MAINTENANCE
; ============================================================================

EditMetadata(path) {
    rec := EnsureRecord(path)

    metaGui := Gui("+AlwaysOnTop", "Tags / Notes - " APP_NAME)
    metaGui.SetFont("s9", "Segoe UI")

    metaGui.AddText("xm ym", "Script:")
    metaGui.AddText("x+8 w500", rec.Path)

    metaGui.AddText("xm y+14", "Tags:")
    tagsEdit := metaGui.AddEdit("xm y+4 w560", rec.Tags)

    favoriteCheck := metaGui.AddCheckbox(
        "xm y+12",
        "Favorite / pin near top of list"
    )
    favoriteCheck.Value := rec.Favorite

    alwaysCheck := metaGui.AddCheckbox(
        "xm y+6",
        "Always start at login even if it was not running at shutdown"
    )
    alwaysCheck.Value := rec.AlwaysStart

    metaGui.AddText("xm y+12", "Notes:")
    notesEdit := metaGui.AddEdit(
        "xm y+4 w560 r10 WantTab",
        rec.Notes
    )

    saveButton := metaGui.AddButton("xm y+12 w100 Default", "Save")
    cancelButton := metaGui.AddButton("x+8 w100", "Cancel")

    saveButton.OnEvent(
        "Click",
        (*) => SaveMetadata(
            metaGui,
            path,
            tagsEdit,
            favoriteCheck,
            alwaysCheck,
            notesEdit
        )
    )

    cancelButton.OnEvent("Click", (*) => metaGui.Destroy())
    metaGui.OnEvent("Escape", (*) => metaGui.Destroy())

    metaGui.Show()
}

SaveMetadata(
    metaGui,
    path,
    tagsEdit,
    favoriteCheck,
    alwaysCheck,
    notesEdit
) {
    rec := EnsureRecord(path)

    rec.Tags := tagsEdit.Value
    rec.Favorite := favoriteCheck.Value ? 1 : 0
    rec.AlwaysStart := alwaysCheck.Value ? 1 : 0
    rec.Notes := notesEdit.Value

    SaveDatabase()
    metaGui.Destroy()
    RefreshList()
}

AddScript(*) {
    path := FileSelect(
        1,
        A_Desktop,
        "Add AutoHotkey v2 script",
        "AutoHotkey scripts (*.ahk)"
    )

    if (path = "")
        return

    path := NormalizePath(path)

    if SamePath(path, A_ScriptFullPath) {
        MsgBox(
            "The hub does not add itself to managed history.",
            APP_NAME,
            "Icon!"
        )
        return
    }

    wasKnown := gScripts.Has(PathKey(path))
    EnsureRecord(path)
    SaveDatabase()
    RefreshList()
    SelectPathInList(path)

    LogEvent(
        "ADD",
        (wasKnown ? "Already known: " : "Added: ") path
    )
}

ImportFolder(*) {
    folder := DirSelect(
        A_Desktop,
        3,
        "Choose a folder to recursively import *.ahk scripts"
    )

    if (folder = "")
        return

    added := 0
    found := 0

    Loop Files folder "\*.ahk", "FR" {
        found += 1
        path := NormalizePath(A_LoopFileFullPath)

        if SamePath(path, A_ScriptFullPath)
            continue

        key := PathKey(path)

        if !gScripts.Has(key) {
            gScripts[key] := NewRecord(path)
            added += 1
        }
    }

    SaveDatabase()
    RefreshList()

    LogEvent(
        "IMPORT",
        "folder=" folder " found=" found " added=" added
    )

    MsgBox(
        "Import complete.`n`n"
        . "AHK files found: " found "`n"
        . "New history entries: " added,
        APP_NAME,
        "Iconi"
    )
}

RelocateRecord(oldPath) {
    global gScripts

    oldKey := PathKey(oldPath)

    if !gScripts.Has(oldKey)
        return

    rec := gScripts[oldKey]

    newPath := FileSelect(
        1,
        rec.Path,
        "Locate replacement/moved AutoHotkey script",
        "AutoHotkey scripts (*.ahk)"
    )

    if (newPath = "")
        return

    newPath := NormalizePath(newPath)
    newKey := PathKey(newPath)

    if SamePath(newPath, A_ScriptFullPath) {
        MsgBox(
            "The hub cannot manage itself as a history entry.",
            APP_NAME,
            "Icon!"
        )
        return
    }

    if (newKey = oldKey) {
        rec.Path := newPath
    } else if gScripts.Has(newKey) {
        existing := gScripts[newKey]

        existing.RunCount += rec.RunCount

        if (existing.FirstSeen = ""
            || (rec.FirstSeen != "" && rec.FirstSeen < existing.FirstSeen)) {
            existing.FirstSeen := rec.FirstSeen
        }

        if (rec.LastRun > existing.LastRun)
            existing.LastRun := rec.LastRun

        existing.Favorite := existing.Favorite || rec.Favorite
        existing.AlwaysStart := existing.AlwaysStart || rec.AlwaysStart

        if (existing.Tags = "")
            existing.Tags := rec.Tags
        else if (rec.Tags != "" && !InStr(existing.Tags, rec.Tags))
            existing.Tags .= ", " rec.Tags

        if (existing.Notes = "")
            existing.Notes := rec.Notes
        else if (rec.Notes != "")
            existing.Notes .= "`r`n`r`n[Merged old record]`r`n" rec.Notes

        gScripts.Delete(oldKey)
    } else {
        gScripts.Delete(oldKey)
        rec.Path := newPath
        gScripts[newKey] := rec
    }

    SaveDatabase()
    RefreshList()
    SelectPathInList(newPath)

    LogEvent("RELOCATE", "old=" oldPath " new=" newPath)
}

RemoveRecord(path) {
    global gScripts

    key := PathKey(path)

    if !gScripts.Has(key)
        return

    if RunningCount(path) > 0 {
        MsgBox(
            "Stop this script before removing its history entry.",
            APP_NAME,
            "Icon!"
        )
        return
    }

    answer := MsgBox(
        "Remove this script from the hub history?`n`n" path
        . "`n`nThis does not delete the .ahk file.",
        APP_NAME,
        "YesNo Icon?"
    )

    if (answer != "Yes")
        return

    gScripts.Delete(key)
    SaveDatabase()
    RefreshList()
    LogEvent("REMOVE", "path=" path)
}

ExportCsv(*) {
    exportPath := A_Desktop
        . "\AHK_Script_History_"
        . FormatTime(, "yyyyMMdd_HHmmss")
        . ".csv"

    try {
        csvText := Csv("Script")
            . "," Csv("Runs")
            . "," Csv("Status")
            . "," Csv("Last Run")
            . "," Csv("First Seen")
            . "," Csv("Favorite")
            . "," Csv("Always Start")
            . "," Csv("Tags")
            . "," Csv("Notes")
            . "," Csv("Path")
            . "`r`n"

        for key, rec in gScripts {
            running := RunningCount(rec.Path)
            status := FileExist(rec.Path)
                ? (running ? "Running (" running ")" : "Stopped")
                : "MISSING"

            SplitPath(rec.Path, &name)

            csvText .= Csv(name)
                . "," Csv(rec.RunCount)
                . "," Csv(status)
                . "," Csv(rec.LastRun)
                . "," Csv(rec.FirstSeen)
                . "," Csv(rec.Favorite ? "Yes" : "No")
                . "," Csv(rec.AlwaysStart ? "Yes" : "No")
                . "," Csv(rec.Tags)
                . "," Csv(rec.Notes)
                . "," Csv(rec.Path)
                . "`r`n"
        }

        FileAppend(csvText, exportPath, "UTF-8")
        LogEvent("EXPORT", "path=" exportPath)

        try Run("explorer.exe /select," Q(exportPath))
    } catch as err {
        MsgBox(
            "Export failed.`n`n" err.Message,
            APP_NAME,
            "Iconx"
        )
    }
}

Csv(value) {
    s := value ""
    s := StrReplace(s, Chr(34), Chr(34) Chr(34))
    return Chr(34) s Chr(34)
}

OpenActivityLog(*) {
    if !FileExist(ACTIVITY_LOG)
        FileAppend("", ACTIVITY_LOG, "UTF-8")

    try Run("notepad.exe " Q(ACTIVITY_LOG))
}

; ============================================================================
; TRAY / EXIT / SHUTDOWN
; ============================================================================

ExitHub(*) {
    ExitApp
}

WM_QueryEndSession(wParam, lParam, msg, hwnd) {
    global gShutdownInProgress

    gShutdownInProgress := true

    ; Use the current in-memory live set. Do not perform a slower WMI scan here.
    ; If startup restoration has not finished yet, preserve the previous
    ; snapshot instead of replacing it with a partially initialized one.
    if gRestoreDone {
        SaveRunningSnapshot()
        LogEvent("SHUTDOWN", "WM_QUERYENDSESSION snapshot saved.")
    } else {
        LogEvent("SHUTDOWN", "Shutdown arrived before restore pass; previous snapshot preserved.")
    }

    ; TRUE: do not block Windows shutdown/logoff.
    return 1
}

WM_EndSession(wParam, lParam, msg, hwnd) {
    global gShutdownInProgress

    if !wParam {
        ; Another application/user canceled shutdown. Resume normal persistence.
        gShutdownInProgress := false
        SaveRunningSnapshot()
        LogEvent("SHUTDOWN", "Shutdown/logoff canceled.")
    }

    return 0
}

AppExit(exitReason, exitCode) {
    global gShutdownInProgress, gMutexHandle, gWmi, gWmiSink
    global gTrayConsolidationEnabled

    ; If Windows is shutting down, preserve the pre-shutdown snapshot captured
    ; in WM_QUERYENDSESSION instead of overwriting it after peer scripts exit.
    if (!gShutdownInProgress && gRestoreDone) {
        try FastWindowScan()
        try SaveRunningSnapshot()
    }

    try SaveDatabase()

    try {
        if IsObject(gWmi) && IsObject(gWmiSink)
            gWmi.CancelAsyncCall(gWmiSink)
    }

    try {
        if IsObject(gWmiSink)
            ComObjConnect(gWmiSink)
    }

    ; A normal Hub exit must give every peer script its individual icon back.
    ; Disable consolidation first so no exit-time scan can hide them again.
    if !gShutdownInProgress {
        gTrayConsolidationEnabled := false
        try RestoreIndividualTrayIcons()
    }

    if gMutexHandle {
        try DllCall("CloseHandle", "Ptr", gMutexHandle)
        gMutexHandle := 0
    }

    LogEvent("EXIT", "reason=" exitReason " code=" exitCode)
}

; ============================================================================
; UTILITIES
; ============================================================================

HasArg(wanted) {
    for , arg in A_Args {
        if (StrLower(arg) = StrLower(wanted))
            return true
    }

    return false
}

Q(value) {
    return Chr(34) value Chr(34)
}

NowStamp() {
    return FormatTime(, "yyyy-MM-dd HH:mm:ss")
}

NormalizePath(path) {
    path := Trim(path "", " `t`r`n" Chr(34))

    if (path = "")
        return ""

    path := StrReplace(path, "/", "\")

    ; Hidden AHK main-window titles and Loop Files already provide absolute
    ; paths. For manually supplied relative paths, resolve against our current
    ; working directory.
    if !IsAbsolutePath(path)
        path := A_WorkingDir "\" path

    ; Canonicalize "." and ".." without requiring the file to still exist.
    pathBuffer := Buffer(32768 * 2, 0)

    length := DllCall(
        "GetFullPathNameW",
        "Str", path,
        "UInt", 32768,
        "Ptr", pathBuffer.Ptr,
        "Ptr", 0,
        "UInt"
    )

    if (length > 0 && length < 32768)
        path := StrGet(pathBuffer.Ptr)

    ; Remove trailing slash unless this is a drive root or UNC root-like path.
    if (StrLen(path) > 3 && SubStr(path, -1) = "\")
        path := RTrim(path, "\")

    return path
}

PathKey(path) {
    return StrLower(NormalizePath(path))
}

SamePath(a, b) {
    if (a = "" || b = "")
        return false

    return PathKey(a) = PathKey(b)
}

IsAbsolutePath(path) {
    return RegExMatch(path, "i)^[A-Z]:\\")
        || (SubStr(path, 1, 2) = "\\")
}

LogEvent(kind, message) {
    try {
        clean := StrReplace(message "", "`r", " ")
        clean := StrReplace(clean, "`n", " ")
        clean := StrReplace(clean, "`t", " ")

        FileAppend(
            NowStamp() "`t" kind "`t" clean "`r`n",
            ACTIVITY_LOG,
            "UTF-8"
        )
    }
}

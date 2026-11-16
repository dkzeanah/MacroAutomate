; Entry lifecycle: hotkeys. Included by MacroAutomator.ahk.
; ===============================================================================
; GLOBAL HOTKEYS
; ===============================================================================
SetTimer(UpdateDefinitionMode, 100)

; Definition mode keys (CAPSLOCK must be ON)
#HotIf GetKeyState("CapsLock", "T")
c::DefModeClick
d::DefModeDragStart
r::DefModeRightClick
t::DefModeTripleClick
p::DefModePattern
w::DefModeWait
k::DefModeSendKeys
m::DefModeMenuSelect
Escape::DefModeCancel
#HotIf

^+g:: {
    global g_GuiVisible, MainGui
    g_GuiVisible := !g_GuiVisible
    g_GuiVisible ? MainGui.Show() : MainGui.Hide()
}

^+p:: {
    global g_IsPaused
    g_IsPaused := !g_IsPaused
    ShowTooltipTimed(g_IsPaused ? "PAUSED" : "RESUMED", 1500)
}

^+x:: {
    global g_AbortSequence
    g_AbortSequence := true
    ShowTooltipTimed("ABORTING...", 1000)
}

^+c::ClearAllNotifications()  ; Ctrl+Shift+C = Clear all notifications

^+f::FindText().Gui("Show")

^+q::QuickOCRCapture()  ; Ctrl+Shift+Q = drag a box anywhere, OCR it, copy the text

; Ctrl+Shift+A = the attention panel: which windows actually held focus,
; watch time for media, ranked by measured prominence rather than by count.
^+a::Attn_OpenPanel()

; Ctrl+Shift+1 = snip the saved region, OCR it, confirm or correct the reading.
;               The first press (no region yet) just asks you to drag one.
; Ctrl+Shift+2 = view the last snip and every representation of it.
; Ctrl+Shift+3 = redraw the region.
^+1::Snip_Hotkey()
^+2::Snip_ViewLast()
^+3::Snip_PickRegion(false)
^+4::Snip_OpenSettings()   ; capture/flash/parsing toggles and roulette timing
^+5::Qa_OpenBank()         ; every parsed question, answered or not
^+6::Qa_AskNow()           ; pull one unanswered question right now
^+7::WinModel_OpenPanel()  ; window structure map for a learned app
^+8::Study_UiReviewNow()  ; spaced review: surface the next due question card
^+9::Env_HotMapActive()   ; OCR feature map of the active window -> JSON (clipboard + file)
^+r::Scribe_Toggle()      ; Workflow Scribe: start/stop recording element interactions
; Live Portal (real-time study assistant): watch the pinned Chrome portal tab
; and answer the question on screen (observe/suggest/fill/submit per mode).
^+y::StudyLive_ToggleSession()
^+u::StudyLive_HotPin()   ; pin the browser window under the cursor
^+Esc:: {
    StudyLive_Abort()
    DeepBridge_Cancel()
}

; ═══════════════════════════════════════════════════════════════════════════════
; QUICK SCREEN OCR (Ctrl+Shift+Q)
; ═══════════════════════════════════════════════════════════════════════════════
; Press the hotkey anywhere, drag a box over any text on screen, and its text is
; recognised, copied to the clipboard and shown in a small result window.
;
; Independent of the Live OCR tab - it works with the main window hidden - but it
; reuses that tab's language/scale/grayscale settings when they are available.
; Spans every monitor (the overlay covers the virtual desktop, not just the
; primary screen).
; The Quick OCR functions themselves live in Tabs\Tab_03_LiveOCR.ahk.

; Clipboard Revolver hotkeys
^b::LoadRevolverFromSelection()   ; Copy + Parse + Load
^+b::FireAllShots()               ; Fire all shots (paste + Tab...)
; Smart Clipboard Revolver with Bins (NEW v4.1)
^!b::LoadRevolverItem(A_Clipboard)  ; Ctrl+Alt+B = Load to smart bins (shows selector)
^!+b::PasteFromBins()               ; Ctrl+Alt+Shift+B = Paste from bins (top bin first)

^!n::OpenNotepadPopup()  ; Ctrl+Alt+N = Open notepad popup
#b::ShowBinSelector("")  ; Ctrl+Alt+B = Open bin selector
^!i::ExecuteIdleMouse("0")  ; Ctrl+Alt+I = Idle mouse indefinitely

; ─── Tracking subsystem hotkeys ──────────────────────────────────────────────
^!t::Track_ToggleAllHotkey()   ; Ctrl+Alt+T = toggle all trackers on/off
^!+s::Snap_OpenViewer()        ; Ctrl+Alt+Shift+S = open the snapshot viewer
^!+c::Track_SnapNow()          ; Ctrl+Alt+Shift+C = capture a snapshot cycle now


try Snip_RestoreState()   ; resume the question roulette if it was left on
catch as err
    LogErrorToFile(err, "caught", "Snip roulette restore")


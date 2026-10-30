; ═══════════════════════════════════════════════════════════════════════════════
; StudyAutomation.ahk - Session, display/focus guard, and question perception
; ═══════════════════════════════════════════════════════════════════════════════
; The automation half of the Real-Time Study Assistant (spec sections 1 and 2).
; It complements the study-only layer (StudyDB / StudyLLM / StudyIngest):
;
;   * enumerates every monitor (negative coordinates, mixed DPI) and turns the
;     pinned window or a dragged rectangle into the capture region
;   * pins one Chrome window + tab (hwnd, title, URL origin) and RE-VERIFIES it
;     before every action - focus loss, tab change, or a closed window pauses
;     the session instead of clicking into the wrong place
;   * perceives the current question through Windows accessibility (Acc.ahk on
;     Chromium's a11y tree) fused with Windows OCR word boxes, with the
;     screenshot retained for the vision model. No DOM, no extension.
;   * classifies single/multi-select, true/false, yes/no, dropdowns, blanks,
;     short/long text, numeric, image-based, and unknown questions, and returns
;     an explicit unknown/review result instead of guessing
;   * dedupes repeated frames (pixel signature + question fingerprint) and
;     detects portal feedback ("correct"/"incorrect") after a submission
;
; Everything here is read-only: it never moves the mouse or sends keys. Input is
; StudyComposer.ahk's job.
; ═══════════════════════════════════════════════════════════════════════════════

; ─────────────────────────────────────────────────────────────────────────────
; SESSION STATE
; ─────────────────────────────────────────────────────────────────────────────
global g_StudyPin        := Map("hwnd", 0, "title", "", "url", "", "origin", "", "exe", "")
global g_StudySessOn     := false     ; the answering loop is running
global g_StudySessBusy   := false     ; a cycle is in progress (blocks re-entry)
global g_StudyPaused     := false     ; guard tripped; input is stopped
global g_StudyMode       := "suggest" ; observe | suggest | fill | submit
global g_StudyPollMs     := 1200
global g_StudyLastSig    := ""        ; Buffer of the last processed frame
global g_StudyLastQFP    := ""        ; fingerprint of the last processed question
global g_StudyLastUrlWarned := false
global g_StudyKeepFrames := false     ; keep debug PNGs instead of deleting them
global g_StudyPrevQ      := Map()     ; question awaiting feedback after submit
global g_StudyFeedbackWaitMs := 3500
global g_StudyCaptureBusy := false    ; re-entrancy guard for perception
global g_StudyOverlayGui := 0
global g_StudyOverlayText := 0
global g_StudyChromeTracking := false
global g_StudyChromeSeen := Map("hwnd", 0, "title", "", "urlTick", 0)

; Remember Chrome foreground activity even while the studier/chat has focus.
; The internal g_StudyPin is the selected learning base, not a user pin request.
StudyAuto_StartChromeTracking() {
    global g_StudyChromeTracking
    g_StudyChromeTracking := true
    StudyAuto_TrackChrome()
    if !g_StudyPin["hwnd"] {
        windows := WinGetList("ahk_exe chrome.exe") ; Windows returns z-order.
        if windows.Length
            StudyAuto_Pin(windows[1])
    }
    SetTimer(StudyAuto_TrackChrome, 250)
}

StudyAuto_IsChromeBase(observation) {
    return IsObject(observation) && observation.Get("hwnd", 0)
        && StrLower(observation.Get("exe", "")) = "chrome.exe"
}

StudyAuto_TrackChrome() {
    global g_StudyChromeSeen, g_StudyMacroCancelled
    hwnd := WinExist("A")
    if !hwnd
        return
    try {
        exe := WinGetProcessName("ahk_id " . hwnd)
        if !StudyAuto_IsChromeBase(Map("hwnd", hwnd, "exe", exe))
            return ; Keep the last Chrome base when Fan or another app activates.
        title := WinGetTitle("ahk_id " . hwnd)
        if hwnd != g_StudyPin["hwnd"] {
            if g_StudyMacroRunning
                g_StudyMacroCancelled := true
            StudyAuto_Pin(hwnd, title, exe)
            g_StudyChromeSeen := Map("hwnd", hwnd, "title", title, "urlTick", A_TickCount)
            StudyLive_LogSafe("Learning base: last activated Chrome tab · " . title)
            StudyLive_UpdatePinnedUI()
            return
        }
        if title != g_StudyChromeSeen["title"] || A_TickCount - g_StudyChromeSeen["urlTick"] > 2000 {
            url := BrowserUrl_FromWindow(hwnd, exe)["url"]
            StudyAuto_FollowTab(url, title)
            g_StudyChromeSeen := Map("hwnd", hwnd, "title", title, "urlTick", A_TickCount)
        }
    } catch as err {
        ; Browser accessibility may disappear briefly during navigation.
        StudyAuto_Debug("Chrome tracking retry: " . err.Message)
    }
}

; ─────────────────────────────────────────────────────────────────────────────
; MONITOR GEOMETRY
; ─────────────────────────────────────────────────────────────────────────────
; Enumerate every monitor at runtime. Screen coordinates are used everywhere,
; so negative origins (monitor to the left) and mixed DPI just work.
; Returns an array of Maps: index, l, t, r, b, w, h, primary, name, side
; where side is "left" | "main" | "right" relative to the primary monitor.
StudyAuto_Monitors() {
    dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    out := []
    try {
        n := MonitorGetCount()
        primary := MonitorGetPrimary()
        Loop n {
            MonitorGet(A_Index, &l, &t, &r, &b)
            name := ""
            try name := MonitorGetName(A_Index)
            side := ""
            if (A_Index = primary)
                side := "main"
            else if (r <= l) {
                ; cannot happen with MonitorGet; kept for safety
                side := "left"
            } else {
                ; primary bounds needed for side comparison
                MonitorGet(primary, &pl, &pt, &pr, &pb)
                side := (r <= pl) ? "left" : (l >= pr) ? "right" : "overlap"
            }
            out.Push(Map("index", A_Index, "l", l, "t", t, "r", r, "b", b
                       , "w", r - l, "h", b - t, "primary", A_Index = primary
                       , "name", name, "side", side))
        }
    } catch as err {
        LogErrorToFile(err, "caught", "StudyAuto_Monitors")
    }
    DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
    return out
}

; One-line-per-monitor text for the tab and overlay.
StudyAuto_MonitorText() {
    txt := ""
    for , m in StudyAuto_Monitors() {
        pos := (m["l"] < 0 ? " (left of primary)" : m["side"] = "right" ? " (right)" : m["side"] = "main" ? " (primary)" : "")
        txt .= "Monitor " . m["index"] . ": " . m["w"] . "x" . m["h"] . " at " . m["l"] . "," . m["t"] . pos . "`n"
    }
    return Trim(txt, "`n")
}

; A default spot for the status overlay: top-right of the right-hand monitor
; when one exists, else bottom-right of the primary monitor's work area.
StudyAuto_OverlayPos() {
    monitor := LearningValidation_Monitor()
    if !monitor
        return ""
    MonitorGetWorkArea(monitor, &left, &top, &right, &bottom)
    return Map("x", Max(left+8,right-340), "y", top+70)
}

; ─────────────────────────────────────────────────────────────────────────────
; CAPTURE REGION
; ─────────────────────────────────────────────────────────────────────────────
; The client area of a window, in screen coordinates.
StudyAuto_RegionFromWindow(hwnd) {
    if !hwnd
        return ""
    dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        WinGetClientPos(&x, &y, &w, &h, "ahk_id " . hwnd)
        if (w > 40 && h > 40)
            return Map("x", x, "y", y, "w", w, "h", h)
    } catch as err {
        LogErrorToFile(err, "caught", "StudyAuto_RegionFromWindow")
    } finally {
        DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
    }
    return ""
}

; The active capture region: an explicit saved rectangle wins, otherwise the
; pinned window's client area. Falls back to the primary monitor.
StudyAuto_Region() {
    global g_StudyPin
    reg := StudyAuto_RegionFromWindow(g_StudyPin["hwnd"])
    source := Study_GetSetting("portal_region_source", "window")
    if (source = "window" && IsObject(reg))
        return StudyAuto_ContentRegion(reg)
    saved := Study_GetSetting("portal_region")
    if (saved != "") {
        p := StrSplit(saved, ",")
        if (p.Length = 4 && Integer(p[3]) > 0 && Integer(p[4]) > 0)
            return Map("x", Integer(p[1]) + (IsObject(reg) ? reg["x"] : 0), "y", Integer(p[2]) + (IsObject(reg) ? reg["y"] : 0)
                     , "w", Integer(p[3]), "h", Integer(p[4]))
    }
    if IsObject(reg)
        return reg
    return Map("x", 0, "y", 0, "w", A_ScreenWidth, "h", A_ScreenHeight)
}

; Capture the rendered document, excluding address bar, tabs and bookmarks.
StudyAuto_ContentRegion(clientRegion) {
    try {
        doc := StudyAuto_Document()
        loc := doc.Location
        candidate := Map("x", loc.x, "y", loc.y, "w", loc.w, "h", loc.h)
        if (loc.w > 40 && loc.h > 40 && !(doc.State & (0x8000 | 0x10000)) && StudyMacro_InRegion(candidate, clientRegion))
            return candidate
    }
    return clientRegion
}

global g_StudyDocument := Map("hwnd", 0, "element", 0)
StudyAuto_Document() {
    global g_StudyDocument
    hwnd := g_StudyPin["hwnd"]
    if (g_StudyDocument["hwnd"] = hwnd && IsObject(g_StudyDocument["element"])) {
        try {
            node := g_StudyDocument["element"]
            loc := node.Location
            if (node.Exists && loc.w > 40 && loc.h > 40 && !(node.State & (0x8000 | 0x10000)))
                return node
        }
    }
    root := Acc.ElementFromHandle(hwnd)
    if (root.Role = 15)
        best := root
    else {
        docs := root.FindElements({Role: 15}, 4, 0, 30)
        best := "", area := 0
        for , doc in docs {
            loc := doc.Location
            if (doc.State & (0x8000 | 0x10000))
                continue
            if (loc.w * loc.h > area)
                best := doc, area := loc.w * loc.h
        }
    }
    if !IsObject(best)
        throw Error("Rendered document unavailable")
    g_StudyDocument := Map("hwnd", hwnd, "element", best)
    return best
}

StudyAuto_VisibleRegion(region) {
    ; Refuse OCR of an occluded or off-screen page. The sampler uses physical pixels.
    Loop 3 {
        iy := A_Index - 1
        Loop 3 {
            ix := A_Index - 1
            x := Round(region["x"] + 8 + ix * Max(0, region["w"] - 17) / 2)
            y := Round(region["y"] + 8 + iy * Max(0, region["h"] - 17) / 2)
            hit := DllCall("WindowFromPoint", "Int64", (y << 32) | (x & 0xFFFFFFFF), "Ptr")
            root := DllCall("GetAncestor", "Ptr", hit, "UInt", 2, "Ptr")
            if root != g_StudyPin["hwnd"] {
                StudyConsole_Log("CAPTURE", "visibility.blocked", Map("point", [x,y], "window", root,
                    "expected_window", g_StudyPin["hwnd"], "region", region), "WARN")
                return false
            }
        }
    }
    return true
}

StudyAuto_RegionSet(region, source := "manual") {
    global g_StudyLastSig, g_StudyLastQFP
    win := StudyAuto_RegionFromWindow(g_StudyPin["hwnd"])
    if (source != "window" && (!IsObject(win) || !StudyMacro_InRegion(region, win)))
        return false
    Study_SetSetting("portal_region_source", source)
    Study_SetSetting("portal_region", (region["x"] - (IsObject(win) ? win["x"] : 0)) . "," . (region["y"] - (IsObject(win) ? win["y"] : 0)) . "," . region["w"] . "," . region["h"])
    g_StudyLastSig := ""      ; force a fresh capture of the new region
    g_StudyLastQFP := ""
    return true
}

StudyAuto_MonitorSig() {
    sig := ""
    for , m in StudyAuto_Monitors()
        sig .= m["name"] . ":" . m["l"] . "," . m["t"] . "," . m["w"] . "," . m["h"] . ";"
    return sig
}

; ─────────────────────────────────────────────────────────────────────────────
; WINDOW PINNING
; ─────────────────────────────────────────────────────────────────────────────
StudyAuto_Origin(url) {
    ; scheme://host[:port] in lowercase - the identity a portal must keep.
    if !RegExMatch(url, "i)^([a-z][a-z0-9+.-]*://[^/?#]+)", &m)
        return StrLower(url)
    return StrLower(m[1])
}

; Pin the window under the mouse (hotkey) or the active window, whichever is a
; browser. Returns Map(ok, detail, title).
StudyAuto_PinFromActive() {
    win := GetWindowUnderMouse()
    if (!win["hwnd"] || !BrowserUrl_IsBrowser(win["exe"])) {
        hwnd := 0
        try hwnd := WinGetID("A")
        if hwnd {
            exe := ""
            try exe := WinGetProcessName("ahk_id " . hwnd)
            if BrowserUrl_IsBrowser(exe) {
                title := ""
                try title := WinGetTitle("ahk_id " . hwnd)
                win := Map("hwnd", hwnd, "title", title, "exe", exe)
            }
        }
    }
    if (!win["hwnd"] || !BrowserUrl_IsBrowser(win["exe"]))
        return Map("ok", false, "detail", "Hover a Chrome window (or make one active) first", "title", "")
    return StudyAuto_Pin(win["hwnd"], win["title"], win["exe"])
}

StudyAuto_Pin(hwnd, title := "", exe := "") {
    global g_StudyPin, g_StudyLastSig, g_StudyLastQFP, g_StudyDocument
    if !hwnd
        return Map("ok", false, "detail", "No window", "title", "")
    if (title = "") {
        try title := WinGetTitle("ahk_id " . hwnd)
    }
    if (exe = "") {
        try exe := WinGetProcessName("ahk_id " . hwnd)
    }
    if !BrowserUrl_IsBrowser(exe)
        return Map("ok", false, "detail", "Not a browser window (" . exe . ")", "title", title)

    url := ""
    urlInfo := Map()
    try urlInfo := BrowserUrl_FromWindow(hwnd, exe)
    if urlInfo.Has("url")
        url := urlInfo["url"]
    g_StudyPin := Map("hwnd", hwnd, "title", title, "url", url
                    , "origin", StudyAuto_Origin(url), "exe", exe, "monitors", StudyAuto_MonitorSig())
    if urlInfo.Has("element")
        g_StudyPin["urlElement"] := urlInfo["element"]
    g_StudyDocument := Map("hwnd", 0, "element", 0)
    Study_SetSetting("study_pin_title", title)
    Study_SetSetting("study_pin_origin", g_StudyPin["origin"])
    Study_SetSetting("study_pin_url", url)
    Study_SetSetting("study_pin_hwnd", String(hwnd))
    Study_SetSetting("study_pin_exe", exe)
    Study_SetSetting("study_pin_pid", String(WinGetPID("ahk_id " . hwnd)))
    g_StudyLastSig := ""
    g_StudyLastQFP := ""
    detail := "Pinned: " . title . (url != "" ? "`n" . url : "`n(URL not readable yet - accessibility may need a moment)")
    StudyConsole_Log("NAV", "pinned", Map("hwnd", hwnd, "title", title, "url", url))
    return Map("ok", true, "detail", detail, "title", title)
}

StudyAuto_Unpin() {
    global g_StudyPin
    g_StudyPin := Map("hwnd", 0, "title", "", "url", "", "origin", "", "exe", "")
    Study_SetSetting("study_pin_title", "")
    Study_SetSetting("study_pin_origin", "")
    Study_SetSetting("study_pin_hwnd", "")
}

; Restore a pin from persisted title/origin after a restart.
StudyAuto_RestorePin() {
    title := Study_GetSetting("study_pin_title")
    origin := Study_GetSetting("study_pin_origin")
    expectedUrl := Study_GetSetting("study_pin_url")
    if (title = "" && origin = "")
        return false
    hwnd := 0
    savedHwnd := Study_GetSetting("study_pin_hwnd", "0")
    if IsInteger(savedHwnd) && Integer(savedHwnd) && WinExist("ahk_id " . savedHwnd) {
        try {
            if WinGetProcessName("ahk_id " . savedHwnd) = Study_GetSetting("study_pin_exe")
                && String(WinGetPID("ahk_id " . savedHwnd)) = Study_GetSetting("study_pin_pid")
                return StudyAuto_Pin(Integer(savedHwnd))["ok"]
        }
    }
    try hwnd := WinExist(title)
    if (!hwnd && title != "") {
        for h in WinGetList() {
            t := ""
            try t := WinGetTitle(h)
            if (t != "" && InStr(t, title)) {
                hwnd := h
                break
            }
        }
    }
    if !hwnd
        return false
    res := StudyAuto_Pin(hwnd)
    return res["ok"]
}

; Follow the selected tab without replacing the browser-window pin. Cached
; controls, questions and feedback belong to the old page and must be dropped.
StudyAuto_FollowTab(url, title) {
    global g_StudyPin, g_StudyLastSig, g_StudyLastQFP, g_StudyDocument, g_StudyPrevQ, g_StudyCurrent
    global g_StudyMacroCancelled
    if url = "" || url = g_StudyPin["url"]
        return false
    previous := g_StudyPin["url"]
    g_StudyPin["url"] := url
    g_StudyPin["origin"] := StudyAuto_Origin(url)
    g_StudyPin["title"] := title
    g_StudyDocument := Map("hwnd", 0, "element", 0)
    g_StudyLastSig := "", g_StudyLastQFP := ""
    g_StudyPrevQ := Map(), g_StudyCurrent := Map()
    if g_StudyMacroRunning
        g_StudyMacroCancelled := true
    Study_SetSetting("study_pin_url", url)
    Study_SetSetting("study_pin_origin", g_StudyPin["origin"])
    Study_SetSetting("study_pin_title", title)
    StudyConsole_Log("NAV", "tab.followed", Map("previous_url", previous, "url", url, "title", title))
    try StudyLive_UpdatePinnedUI()
    return true
}

; The portal identity check run before every action and every loop tick.
; Returns Map(ok, reason, url, title). Anything but ok=true means NO input.
StudyAuto_CheckPin() {
    global g_StudyPin, g_StudyLastUrlWarned
    if g_StudyChromeTracking
        StudyAuto_TrackChrome()
    hwnd := g_StudyPin["hwnd"]
    StudyAuto_Debug("Guard started")
    if !hwnd
        return Map("ok", false, "reason", "No pinned window", "url", "", "title", "")
    if !WinExist("ahk_id " . hwnd)
        return Map("ok", false, "reason", "Pinned window is gone", "url", "", "title", "")
    mm := 0
    try mm := WinGetMinMax("ahk_id " . hwnd)
    if (mm = -1)
        return Map("ok", false, "reason", "Pinned window is minimized", "url", "", "title", "")
    title := ""
    try title := WinGetTitle("ahk_id " . hwnd)
    active := 0
    try active := WinGetID("A")
    if (active != hwnd)
        return Map("ok", false, "reason", "Focus lost - Chrome tab is not foreground", "url", "", "title", title)
    if (g_StudyPin.Has("monitors") && g_StudyPin["monitors"] != StudyAuto_MonitorSig())
        return Map("ok", false, "reason", "Monitor layout changed - re-pin the portal", "url", "", "title", title)
    if (DllCall("GetLastActivePopup", "Ptr", hwnd, "Ptr") != hwnd)
        return Map("ok", false, "reason", "A dialog is covering the portal", "url", "", "title", title)
    winRegion := StudyAuto_RegionFromWindow(hwnd)
    StudyAuto_Debug("Guard checking region")
    if (!IsObject(winRegion) || !StudyMacro_InRegion(StudyAuto_Region(), winRegion))
        return Map("ok", false, "reason", "Capture region is outside the pinned window - reset Region", "url", "", "title", title)

    ; The window is pinned; the currently selected tab may change freely.
    url := ""
    StudyAuto_Debug("Guard checking URL")
    try {
        if g_StudyPin.Has("urlElement") {
            value := Trim(g_StudyPin["urlElement"].Value)
            if BrowserUrl_LooksLikeUrl(value) {
                if (value ~= "i)^[a-z]:[/\\]")
                    value := "file:///" . StrReplace(value, "\", "/")
                else if !(value ~= "i)^[a-z][a-z0-9+.-]*://")
                    value := "https://" . value
                url := value
            }
        }
    }
    if (url = "") {
        try url := BrowserUrl_FromWindow(hwnd, g_StudyPin["exe"])["url"]
    }
    StudyAuto_Debug("Guard URL read complete")
    if (url != "") {
        if StudyAuto_FollowTab(url, title) && g_StudyMacroRunning
            return Map("ok", false, "reason", "Tab changed during entry; following the new tab automatically", "url", url, "title", title)
    }
    if ((url = "" || g_StudyPin["url"] = "") && (g_StudyMode = "fill" || g_StudyMode = "submit"))
        return Map("ok", false, "reason", "URL unreadable - use suggest mode or re-pin once accessibility is ready", "url", url, "title", title)
    if (url = "" && !g_StudyLastUrlWarned) {
        g_StudyLastUrlWarned := true
        ; Not fatal: OCR/a11y fallback still keeps us on the same window. The
        ; warning surfaces once in the log instead of spamming.
        StudyLive_LogSafe("Portal URL not readable (a11y may be warming up) - title check only")
    }
    return Map("ok", true, "reason", "", "url", url, "title", title)
}

global g_StudyControllerDebug := 0
StudyAuto_Debug(message) {
    if IsObject(g_StudyControllerDebug)
        g_StudyControllerDebug(message)
}

; Called before EVERY input action. Pauses the session when the portal is not
; safe to touch. Returns true when input may proceed.
StudyAuto_Guard() {
    global g_StudyPaused, g_StudySessOn
    if !g_StudySessOn
        return false
    chk := StudyAuto_CheckPin()
    if !chk["ok"] {
        if (!g_StudyPaused) {
            g_StudyPaused := true
            StudyLive_LogSafe("⏸ Session paused: " . chk["reason"])
            StudyAuto_OverlayPaused(true)
        }
        return false
    }
    if (g_StudyPaused) {
        g_StudyPaused := false
        StudyLive_LogSafe("▶ Session resumed - portal verified")
        StudyAuto_OverlayPaused(false)
    }
    return true
}

; ─────────────────────────────────────────────────────────────────────────────
; FRAME CHANGE DETECTION
; ─────────────────────────────────────────────────────────────────────────────
; Cheap pixel signature (reuses the engine's sampler) so OCR/Acc do not rerun
; on an unchanged frame. Returns the Buffer signature.
StudyAuto_FrameSig(region) {
    return SampleRegionPixels(region["x"], region["y"], region["w"], region["h"], 12)
}

; Did the region change enough to be worth re-perceiving? Stores the new sig.
StudyAuto_RegionChanged() {
    global g_StudyLastSig
    region := StudyAuto_Region()
    sig := StudyAuto_FrameSig(region)
    if (!IsObject(g_StudyLastSig) || g_StudyLastSig.Size != sig.Size) {
        g_StudyLastSig := sig
        return true
    }
    frac := ComparePixelSamples(g_StudyLastSig, sig)
    g_StudyLastSig := sig
    return frac >= 0.012
}

; ─────────────────────────────────────────────────────────────────────────────
; PERCEPTION - walk Chromium accessibility + OCR, fuse into a Question record
; ─────────────────────────────────────────────────────────────────────────────
StudyPercept_TempPath(tag) {
    return Photo_TempPath()
}

; Condition for one Acc walk: only interactive controls, only inside the region.
StudyPercept_IsControl(el, i?, depth?) {
    global g_StudyPin
    static roles := Map("radio button", 1, "check box", 1, "edit", 1, "editable text", 1
                      , "combo box", 1, "combobox", 1, "push button", 1
                      , "button", 1, "link", 1, "list", 1, "list item", 1, "separator", 1)
    try {
        rt := el.RoleText
        if !roles.Has(rt)
            return 0
        loc := el.Location
        if (loc.w <= 0 || loc.h <= 0)
            return 0
        ; Geometry is checked once in Walk. Re-querying the entire document
        ; inside this predicate turns one walk into a nested walk per control.
        return 1
    }
    return 0
}

; Walk the pinned window's Acc tree. Returns an array of control Maps:
;   kind, role, name, value, x, y, w, h, stateText, checked, protected
StudyPercept_Walk() {
    global g_StudyPin
    static lastLog := 0
    out := []
    if !g_StudyPin["hwnd"]
        return out
    ; If the pinned window is gone, stop chasing a dead accessibility tree —
    ; otherwise the walk throws a COM failure (0x80004005) on every poll and
    ; floods the log. Clear the pin once and bail.
    if !WinExist("ahk_id " . g_StudyPin["hwnd"]) {
        if (A_TickCount - lastLog > 60000) {
            lastLog := A_TickCount
            LogErrorToFile("Pinned window closed; clearing Live Portal pin", "caught (throttled)", "StudyPercept_Walk")
        }
        StudyAuto_Unpin()
        return out
    }
    try {
        root := StudyAuto_Document()
        els := root.FindElements(StudyPercept_IsControl, 4, 0, 30)
        region := StudyAuto_Region()
        for , el in els {
            try {
                loc := el.Location
                name := ""
                try name := Trim(el.Name)
                value := ""
                try value := el.Value
                st := 0, stText := ""
                try st := el.State
                try stText := el.StateText
                kind := StudyPercept_Kind(el.RoleText)
                if (kind = "other")
                    continue
                ; MSAA reports some static labels as read-only editable text.
                if (kind = "edit" && !(st & 0x1) && ((st & 0x40) || !(st & 0x100000)))
                    continue
                if (loc.w <= 0 || loc.h <= 0 || loc.x < region["x"] || loc.y < region["y"]
                 || loc.x + loc.w > region["x"] + region["w"] || loc.y + loc.h > region["y"] + region["h"]
                 || (st & (0x8000 | 0x10000)))
                    continue
                ; Browser chrome: the omnibox is an edit named "address and
                ; search bar" - never part of a question.
                if (kind = "edit" && name ~= "i)address and search bar|omnibox|^search")
                    continue
                out.Push(Map("kind", kind, "role", el.RoleText, "name", name
                           , "value", value, "x", loc.x, "y", loc.y
                           , "w", loc.w, "h", loc.h
                           , "checked", (st & 0x10) != 0
                           , "focused", (st & 0x4) != 0, "state", st, "element", el
                           , "enabled", !(st & 0x1)
                           , "protected", (st & 0x20000000) != 0 || InStr(StrLower(stText), "protected") != 0
                           , "stText", stText))
            }
        }
    } catch as err {
        ; Walking a live accessibility tree routinely hits elements that vanish
        ; mid-walk (COM 0x80004005). That is expected transient noise, not a
        ; fault - log at most once a minute so it cannot flood the error log.
        if (A_TickCount - lastLog > 60000) {
            lastLog := A_TickCount
            LogErrorToFile(err, "caught (throttled)", "StudyPercept_Walk")
        }
    }
    return out
}

StudyPercept_Kind(roleText) {
    switch StrLower(roleText) {
        case "radio button": return "radio"
        case "check box":    return "checkbox"
        case "edit", "editable text": return "edit"
        case "combo box", "combobox": return "dropdown"
        case "push button", "button": return "button"
        case "link":         return "link"
        case "list", "list item": return "list"
        case "separator": return "separator"
        default:             return "other"
    }
}

; OCR the capture region. Returns Map(ok, text, lines, words, err).
; words: array of Maps(text, x, y, w, h). lines: array of Maps(text, y, x, w, h).
StudyPercept_OCR(region) {
    out := Map("ok", false, "text", "", "lines", [], "words", [], "err", "")
    try {
        res := OCR.FromRect(region["x"], region["y"], region["w"], region["h"], {scale: 2})
        out["ok"] := true
        for , line in res.Lines {
            lt := Trim(line.Text)
            if (lt = "")
                continue
            br := line.BoundingRect
            out["lines"].Push(Map("text", lt, "y", br.y, "x", br.x, "w", br.w, "h", br.h))
            for , w in line.Words {
                wt := Trim(w.Text)
                if (wt = "")
                    continue
                out["words"].Push(Map("text", wt, "x", w.x, "y", w.y, "w", w.w, "h", w.h))
            }
        }
        for , ln in out["lines"]
            out["text"] .= (out["text"] = "" ? "" : "`n") . ln["text"]
    } catch as err {
        out["err"] := err.Message
    }
    return out
}

; Screenshot the region to PNG (for vision + debug). Returns path or "".
StudyPercept_SaveFrame(region) {
    path := StudyPercept_TempPath("portal")
    if Snip_SaveRegion(region, path)
        return path
    return ""
}

; Full perception pass. Returns a Map:
;   ok, region, imagePath, ocr(Map), controls(Array), question(Map or ""), err
; The question is built only when ok; classification may still yield "unknown".
StudyPercept_Capture() {
    global g_StudyCaptureBusy, g_StudyPin
    if g_StudyCaptureBusy
        return Map("ok", false, "err", "capture already running")
    g_StudyCaptureBusy := true
    StudyConsole_Log("CAPTURE", "attempt", Map("hwnd", g_StudyPin["hwnd"], "url", g_StudyPin["url"], "libraries", ["GDI+", "Windows OCR", "Acc"]))
    out := Map("ok", false, "region", Map(), "imagePath", "", "ocr", Map()
             , "controls", [], "question", Map(), "err", "")
    dpiContext := DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")
    try {
        if !g_StudyPin["hwnd"]
            return (out["err"] := "no pinned window", out)
        region := StudyAuto_Region()
        if !StudyAuto_VisibleRegion(region)
            return (out["err"] := "Portal is occluded or outside the visible desktop; bring Chrome forward", out)
        out["region"] := region
        out["imagePath"] := StudyPercept_SaveFrame(region)
        out["ocr"] := StudyPercept_OCR(region)
        out["controls"] := StudyPercept_Walk()
        for index, foundControl in out["controls"] {
            if foundControl["protected"]
                StudyConsole_Log("IDENTIFY", "protected.control.skipped", Map("kind", foundControl["kind"]))
            else
                StudyConsole_Log("IDENTIFY", "perception.control", StudyFeatures_Describe(foundControl, String(index)))
        }
        q := StudyPercept_BuildQuestion(out["ocr"], out["controls"], region, out["imagePath"])
        out["question"] := q
        StudyConsole_Log("IDENTIFY", "page.profile", q["portal"])
        out["ok"] := true
        StudyConsole_Log("CAPTURE", "gathered", Map("region", region, "image", out["imagePath"],
            "ocr_ok", out["ocr"]["ok"], "ocr_text", out["ocr"]["text"], "controls", out["controls"].Length,
            "question_type", q["qtype"], "question_text", q["text"]))
    } catch as err {
        out["err"] := err.Message
        StudyConsole_Log("ERROR", "capture.failed", err.Message, "ERROR")
        LogErrorToFile(err, "caught", "StudyPercept_Capture")
    } finally {
        g_StudyCaptureBusy := false
        DllCall("SetThreadDpiAwarenessContext", "Ptr", dpiContext, "Ptr")
    }
    ; Frame lifecycle: the engine deletes the PNG once the cycle is done (or
    ; keeps it when the debug setting is on).
    return out
}

; Delete a captured frame once the cycle that used it has finished.
StudyPercept_Dispose(path) {
    global g_StudyKeepFrames
    if path != "" && FileExist(path) {
        if g_StudyKeepFrames
            Photo_Store(path, "Study debug frame")
        try FileDelete(path)
    }
}

; ─────────────────────────────────────────────────────────────────────────────
; QUESTION MODEL
; ─────────────────────────────────────────────────────────────────────────────
; Fuse OCR + Acc into one structured Question record:
;   raw      full OCR text of the region
;   text     question stem (lines above the controls, choices stripped)
;   qtype    single | multi | yesno | tf | dropdown | fillblank | shorttext |
;            longtext | numeric | image | unknown
;   choices  [Map(tag, text, x, y, w, h, accName, checked)]   radio/checkbox options
;   blanks   [Map(name, x, y, w, h)]                          text input fields
;   dropdown Map(name, value, x, y, w, h) or ""
;   buttons  [Map(name, x, y, w, h)]                          clickable buttons
;   submit   Map(name, x, y, w, h) or ""                      submit/next control
;   hasImage bool   imagePath str   source str   conf num
StudyPercept_BuildQuestion(ocr, controls, region, imagePath) {
    q := Map("raw", ocr["text"], "text", "", "qtype", "unknown", "choices", [], "controls", controls, "region", region
           , "blanks", [], "dropdown", "", "buttons", [], "submit", ""
           , "hasImage", false, "imagePath", imagePath
           , "source", "ocr", "conf", 0.0)
    profile := StudyPortal_Profile(ocr, controls, region)
    q["portal"] := profile
    q["mathExpression"] := StudyPortal_RationalPower(ocr)

    radios := [], checks := [], edits := [], combos := [], buttons := []
    for , c in controls {
        if profile["view"] = "question_player" && (c["kind"] = "radio" || c["kind"] = "checkbox" || c["kind"] = "edit" || c["kind"] = "dropdown")
            && c["x"] < profile["questionLeft"]
            continue ; Sidebar navigation is not an answer control.
        switch c["kind"] {
            case "radio":    radios.Push(c)
            case "checkbox": checks.Push(c)
            case "edit":     edits.Push(c)
            case "dropdown": combos.Push(c)
            case "button":   buttons.Push(c)
        }
    }

    ; ── controls with OCR labels fused in ────────────────────────────────
    for , r in radios
        StudyPercept_AttachLabel(r, ocr)
    for , c in checks
        StudyPercept_AttachLabel(c, ocr)
    for , b in buttons
        StudyPercept_AttachLabel(b, ocr)

    ; ── choices from Acc ─────────────────────────────────────────────────
    n := 0
    for , r in radios {
        n++
        q["choices"].Push(Map("kind", "radio", "tag", StudyPercept_Tag(n), "text", r["name"]
                            , "x", r["x"], "y", r["y"], "w", r["w"], "h", r["h"]
                            , "accName", r["name"], "checked", r["checked"]))
    }
    if (q["choices"].Length = 0) {
        for , c in checks {
            n++
            q["choices"].Push(Map("kind", "checkbox", "tag", StudyPercept_Tag(n), "text", c["name"]
                                , "x", c["x"], "y", c["y"], "w", c["w"], "h", c["h"]
                                , "accName", c["name"], "checked", c["checked"]))
        }
    }

    ; ── blanks ───────────────────────────────────────────────────────────
    for , e in edits {
        q["blanks"].Push(Map("name", e["name"], "value", e["value"]
                           , "x", e["x"], "y", e["y"], "w", e["w"], "h", e["h"]
                           , "protected", e["protected"]))
    }
    StudyPortal_AssociateFields(q)
    for , d in combos {
        if (!IsObject(q["dropdown"]))
            q["dropdown"] := Map("name", d["name"], "value", d["value"]
                               , "x", d["x"], "y", d["y"], "w", d["w"], "h", d["h"])
    }
    for , b in buttons
        q["buttons"].Push(Map("name", b["name"], "x", b["x"], "y", b["y"], "w", b["w"], "h", b["h"]))

    ; ── question stem: OCR lines above the first QUESTION control, choices
    ;    removed. Header/nav buttons and links must not cut the stem early. ──
    firstY := 0x7FFFFFFF
    for , c in controls {
        switch c["kind"] {
            case "radio", "checkbox", "edit", "dropdown":
                firstY := Min(firstY, c["y"])
        }
    }
    stemLines := []
    for , ln in ocr["lines"] {
        if StudyPercept_IsChoiceLine(ln["text"])
            break
        if (firstY < 0x7FFFFFFF && ln["y"] >= firstY)
            break
        stemLines.Push(ln["text"])
    }
    q["text"] := StudyPercept_Join(stemLines)
    if profile["view"] = "question_player" {
        for index, line in stemLines {
            if RegExMatch(line, "i)^use radical notation|^solve\b|^simplify\b|^evaluate\b|^rewrite\b") {
                trimmedStem := []
                Loop stemLines.Length - index + 1
                    trimmedStem.Push(stemLines[index + A_Index - 1])
                q["text"] := StudyPercept_Join(trimmedStem)
                break
            }
        }
    }

    ; ── OCR-only fallback: no Acc controls found ─────────────────────────
    if (controls.Length = 0) {
        choiceLines := []
        for , ln in ocr["lines"] {
            tag := StudyPercept_ChoiceTag(ln["text"])
            if (tag != "")
                choiceLines.Push(Map("kind", "radio", "fromOcr", true, "tag", tag
                                   , "text", StudyPercept_StripTag(ln["text"])
                                   , "x", ln["x"], "y", ln["y"], "w", ln["w"], "h", ln["h"]
                                   , "accName", "", "checked", false))
        }
        ; A numbered question stem ("1. What is...") looks like a choice line;
        ; only trust the reading when several choice-shaped lines exist.
        if (choiceLines.Length >= 2) {
            q["choices"] := choiceLines
            ; stem = lines above the first choice
            stemLines := []
            for , ln in ocr["lines"] {
                if (ln["y"] >= choiceLines[1]["y"] - 4)
                    break
                stemLines.Push(ln["text"])
            }
            q["text"] := StudyPercept_Join(stemLines)
        }
        ; buttons by heuristic (Submit/Next words) - FindText-style OCR words
        for , w in ocr["words"] {
            if (w["text"] ~= "i)^(submit|next|continue|finish|save|done)$") {
                q["buttons"].Push(Map("name", w["text"], "x", w["x"], "y", w["y"]
                                    , "w", w["w"], "h", w["h"]))
            }
        }
    }

    ; ── classification ───────────────────────────────────────────────────
    StudyPercept_Classify(q, radios, checks, edits, combos, ocr)
    return q
}

StudyPercept_Join(arr) {
    out := ""
    for , s in arr
        out .= (out = "" ? "" : "`n") . s
    return out
}

StudyPercept_Tag(n) {
    static tags := ["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"]
    return n <= tags.Length ? tags[n] : String(n)
}

; Match an OCR line to a control by vertical overlap and horizontal adjacency,
; filling the control's name when accessibility left it blank.
StudyPercept_AttachLabel(ctl, ocr) {
    if (Trim(ctl["name"]) != "")
        return
    cy := ctl["y"] + ctl["h"] / 2
    best := "", bestDist := 100000
    for , ln in ocr["lines"] {
        if (cy < ln["y"] - 4 || cy > ln["y"] + ln["h"] + 4)
            continue
        ; prefer the line whose box starts just right of the control
        dist := Abs(ln["x"] - (ctl["x"] + ctl["w"]))
        if (dist < bestDist) {
            bestDist := dist
            best := ln["text"]
        }
    }
    if (best != "")
        ctl["name"] := best
}

; Does this OCR line look like a choice ("A. ...", "a) ...", "1) ...")?
StudyPercept_IsChoiceLine(s) {
    return RegExMatch(Trim(s), "i)^([A-H]|[1-9])[.):]\s+\S") > 0
}

StudyPercept_ChoiceTag(s) {
    if RegExMatch(Trim(s), "^([A-H])[.):]\s+\S", &m)
        return m[1]
    return ""
}

StudyPercept_StripTag(s) {
    return Trim(RegExReplace(Trim(s), "^([A-H]|[1-9])[.):]\s+", ""))
}

StudyPercept_BlanksInText(s) {
    n := 0
    for , part in StrSplit(s, "___", " ") {
        if (part = "" || part = s)
            continue
        n++
    }
    if (n = 0) {
        while RegExMatch(s, "_{3,}|\[blank\]|\(\s*blank\s*\)", &m)
            n++, s := StrReplace(s, m[0], "")
    }
    return n
}

; Classify the question type from controls + wording (spec section 2).
StudyPercept_Classify(q, radios, checks, edits, combos, ocr) {
    stem := StrLower(q["text"] . " " . q["raw"])
    lowText := StrLen(Trim(q["raw"])) < 24
    q["conf"] := 0.9

    ; image-based: almost no text but a real frame was captured
    if (lowText) {
        q["hasImage"] := true
        q["qtype"] := "image"
        q["conf"] := 0.6
        if (q["choices"].Length)
            q["qtype"] := "single"      ; vision can still read labels
        return
    }

    if (radios.Length > 0) {
        if edits.Length {
            q["qtype"] := "choicefill"
            return
        }
        q["qtype"] := "single"
        joined := stem
        for , c in radios
            joined .= " " . c["name"]
        jl := StrLower(joined)
        if (radios.Length = 2 && InStr(jl, "yes") && InStr(jl, "no") && !(InStr(jl, "true") || InStr(jl, "false")))
            q["qtype"] := "yesno"
        else if (radios.Length = 2 && InStr(jl, "true") && InStr(jl, "false"))
            q["qtype"] := "tf"
        return
    }
    if (checks.Length > 0) {
        q["qtype"] := "multi"
        return
    }
    if (combos.Length > 0) {
        q["qtype"] := "dropdown"
        return
    }
    if (edits.Length > 0) {
        if (InStr(stem, "explain") || InStr(stem, "describe") || InStr(stem, "essay")
         || InStr(stem, "in your own words") || StrLen(q["text"]) > 260)
            q["qtype"] := "longtext"
        else if (InStr(stem, "select all") = 0 && StudyPercept_BlanksInText(q["raw"]) > 0)
            q["qtype"] := "fillblank"
        else if (InStr(stem, "unit") || InStr(stem, "units") || InStr(stem, "nearest")
              || InStr(stem, "round to") || InStr(stem, "km") || InStr(stem, "meters")
              || InStr(stem, "percent") || InStr(stem, "decimal"))
            q["qtype"] := "numeric"
        else
            q["qtype"] := "shorttext"
        return
    }
    ; OCR-only fallback classification
    if (q["choices"].Length > 0) {
        q["qtype"] := "single"
        if (RegExMatch(stem, "i)select all|choose all|all that apply|more than one"))
            q["qtype"] := "multi"
        return
    }
    if (q["text"] != "" && InStr(q["text"], "?"))
        q["qtype"] := "shorttext"       ; text answer, but field not located -> composer abstains
    else if (!lowText)
        q["qtype"] := "unknown"         ; readable but unsupported widget (ordering/matching...)
    else {
        q["hasImage"] := true           ; nothing readable: let vision take a look
        q["qtype"] := "image"
        q["conf"] := 0.5
    }
}

; Fingerprint identifying one question (dedupe + bank dedupe share the shape).
StudyPercept_QFP(q) {
    s := q["qtype"] . "|" . q["text"]
    for , c in q["choices"]
        s .= " | " . c["tag"] . c["text"]
    return StrLower(RegExReplace(s, "\s+", " "))
}

StudyPercept_JoinTags(tags) {
    result := ""
    for , tag in tags
        result .= (result = "" ? "" : ", ") . tag
    return result
}

; Locate an OCR word near (x, y). Uses the last OCR pass. Returns Map or "".
StudyPercept_WordNear(ocr, x, y, maxDist := 160) {
    best := "", bd := 100000
    for , w in ocr["words"] {
        cx := w["x"] + w["w"] / 2, cy := w["y"] + w["h"] / 2
        d := Abs(cx - x) + Abs(cy - y)
        if (d < bd) {
            bd := d
            best := w
        }
    }
    return (bd <= maxDist) ? best : ""
}

; ─────────────────────────────────────────────────────────────────────────────
; PORTAL FEEDBACK DETECTION (after a submission)
; ─────────────────────────────────────────────────────────────────────────────
; Re-OCR the region and look for feedback markers. Returns
; Map(verdict: correct|incorrect|unknown, text: the feedback line).
StudyPercept_FeedbackCheck(region) {
    ocr := StudyPercept_OCR(region)
    return StudyPercept_FeedbackFromOCR(ocr)
}

StudyPercept_FeedbackFromOCR(ocr) {
    out := Map("verdict", "unknown", "text", "")
    if (!ocr["ok"] || ocr["text"] = "")
        return out
    posTokens := "^(?:fantastic[.!]?|correct[.!]?|your answer is correct[.!]?|that'?s right[.!]?|well done[.!]?|great job[.!]?|nice work[.!]?|correct[.!] practice answer verified[.!]?)$"
    negTokens := "^(?:incorrect[.!]?|wrong[.!]?|your answer is (?:incorrect|wrong)[.!]?|not correct[.!]?|try again[.!]?|incorrect[.!] try mitochondria[.!]?)$"
    hasPos := false, hasNeg := false, best := ""
    for , ln in ocr["lines"] {
        t := Trim(ln["text"])
        if (RegExMatch(t, "i)" . posTokens) && StrLen(t) < 90) {
            hasPos := true
            if (best = "")
                best := t
        }
        if (RegExMatch(t, "i)" . negTokens) && StrLen(t) < 90) {
            hasNeg := true
            if (best = "")
                best := t
        }
    }
    if (hasPos && !hasNeg)
        out["verdict"] := "correct"
    else if (hasNeg && !hasPos)
        out["verdict"] := "incorrect"
    out["text"] := best
    return out
}

; Crop the question area (top of region down to the last control) so the
; vision model gets a tight image. Returns a PNG path or "".
StudyPercept_CropQuestionImage(region, ocr, controls) {
    bottom := 0
    for , c in controls
        bottom := Max(bottom, c["y"] + c["h"])
    if (bottom = 0) {
        ; no controls: use OCR text extent
        for , ln in ocr["lines"]
            bottom := Max(bottom, ln["y"] + ln["h"])
    }
    if (bottom <= region["y"] + 40)
        return ""
    h := Min(bottom - region["y"] + 24, region["h"])
    crop := Map("x", region["x"], "y", region["y"], "w", region["w"], "h", h)
    path := StudyPercept_TempPath("qimg")
    if Snip_SaveRegion(crop, path)
        return path
    return ""
}

; ─────────────────────────────────────────────────────────────────────────────
; STATUS OVERLAY (non-activating, click-through; spec section 8)
; ─────────────────────────────────────────────────────────────────────────────
; A small always-on-top readout that never steals focus from the pinned tab.
StudyAuto_OverlayShow() {
    global g_StudyOverlayGui, g_StudyOverlayText
    if (g_StudyOverlayGui)
        return
    pos := StudyAuto_OverlayPos()
    if !IsObject(pos)
        return
    g_StudyOverlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000020", "StudyOverlay")
    g_StudyOverlayGui.BackColor := "101418"
    g_StudyOverlayGui.MarginX := 10, g_StudyOverlayGui.MarginY := 8
    g_StudyOverlayGui.SetFont("s9 cDDDDDD", "Consolas")
    g_StudyOverlayText := g_StudyOverlayGui.Add("Text", "w320", "Study Assistant - stopped")
    SecondaryWindows_Place(g_StudyOverlayGui, "x" . pos["x"] . " y" . pos["y"] . " NoActivate")
    WinSetTransparent(215, g_StudyOverlayGui)
}

StudyAuto_OverlayHide() {
    global g_StudyOverlayGui
    try g_StudyOverlayGui.Destroy()
    g_StudyOverlayGui := 0
}

StudyAuto_OverlayUpdate(text) {
    global g_StudyOverlayGui, g_StudyOverlayText, g_DeepActivity
    if (!g_StudyOverlayGui || !IsObject(g_StudyOverlayText))
        return
    if IsSet(g_DeepActivity) && g_DeepActivity is Map && g_DeepActivity.Get("suspended", false) {
        g_StudyOverlayGui.Hide()
        return
    }
    pos := StudyAuto_OverlayPos()
    if !IsObject(pos)
        return g_StudyOverlayGui.Hide()
    try {
        g_StudyOverlayText.Value := text
        if !SecondaryWindows_IsPinned(g_StudyOverlayGui.Hwnd)
            WinMove(pos["x"],pos["y"],,,g_StudyOverlayGui)
        SecondaryWindows_Clamp(g_StudyOverlayGui.Hwnd)
        g_StudyOverlayGui.Show("NoActivate")
    }
}

StudyAuto_OverlayPaused(paused) {
    ; The next overlay update reflects g_StudyPaused; push one immediately so
    ; the readout changes the moment the guard trips or recovers.
    StudyLive_UpdateOverlay()
}

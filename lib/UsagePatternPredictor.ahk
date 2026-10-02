; ============================================================================
; UsagePatternPredictor.ahk - Macro Automator v9 local visual usage learner
; ============================================================================
; Learns from the current machine only. It samples the complete virtual desktop
; at a coarse grid, refines regions with meaningful contrast, creates a bounded
; FindText pattern for each region, and verifies that pattern inside its source
; rectangle. Mouse clicks and dwell promote useful regions into the shared
; `element` registry. A local n-gram transition model predicts continuations of
; repeated app/click/key/type sequences. Win+Shift+CapsLock accepts a prediction
; so this learner can run alongside Vision Scout without a hotkey collision.
;
; Literal typed text is OFF by default. When enabled, credential-like windows
; are still excluded through KeyTracker's sensitive-window rules. No screen or
; usage data leaves the local tracking SQLite database.
; ============================================================================

global g_UPOn := false
global g_UPReady := false
global g_UPInputHook := ""
global g_UPControls := Map()
global g_UPCandidateRows := Map()
global g_UPTrayMenu := 0
global g_UPRecentEvents := []
global g_UPPrediction := []
global g_UPPredictionSignature := ""
global g_UPLastPredictionTick := 0
global g_UPReplaying := false
global g_UPCaptureText := false
global g_UPScanIntervalMs := 6000
global g_UPScanBusy := false
global g_UPScanCursor := 1
global g_UPLastScanTs := "Never"
global g_UPLastScanCount := 0
global g_UPLastPollTick := 0
global g_UPLastWindowHwnd := 0
global g_UPMouseDown := Map("LButton", false, "RButton", false, "MButton", false)
global g_UPHoverElementId := 0
global g_UPHoverStartedTick := 0
global g_UPLastHoverPoll := 0
global g_UPTypeBuffer := []
global g_UPTypeCount := 0
global g_UPTypeWinId := 0
global g_UPTypeAppId := 0
global g_UPTypeStartedTick := 0
global g_UPTypeLastTick := 0
global g_UPTypeLetters := 0
global g_UPTypeDigits := 0
global g_UPTypeSpaces := 0
global g_UPTypeSymbols := 0
global g_UPLastEventTick := 0
global g_UPMaxPatternsPerScan := 18
global g_UPMinSupport := 3
global g_UPMinConfidence := 0.72
global g_UPTabIndex := 16

; ---------------------------------------------------------------------------
; UI
; ---------------------------------------------------------------------------

UsagePredictor_BuildTab(guiObj) {
    global g_UPControls

    guiObj.Add("GroupBox", "x15 y48 w860 h100", "Local Visual Usage Learner")
    g_UPControls["toggle"] := guiObj.Add("Button", "x30 y72 w90 h26", "Start")
    g_UPControls["scan"] := guiObj.Add("Button", "x128 y72 w90 h26", "Scan Now")
    g_UPControls["refresh"] := guiObj.Add("Button", "x226 y72 w90 h26", "Refresh")
    g_UPControls["accept"] := guiObj.Add("Button", "x324 y72 w155 h26", "Run Prediction  Win+Shift+Caps")
    g_UPControls["text"] := guiObj.Add("CheckBox", "x490 y76 w170", "Store literal typed text")
    guiObj.Add("Text", "x665 y77 w55", "Scan:")
    g_UPControls["interval"] := guiObj.Add("DropDownList", "x720 y72 w80", ["3 sec", "6 sec", "10 sec", "20 sec", "30 sec"])
    g_UPControls["interval"].Choose(2)

    g_UPControls["status"] := guiObj.Add("Text", "x30 y107 w820 h34 cGray",
        "Stopped. Visual patterns and behavior remain local in data\\tracking.db.")

    guiObj.Add("GroupBox", "x15 y155 w860 h55", "Learning Summary")
    g_UPControls["stats"] := guiObj.Add("Text", "x30 y177 w830 h22",
        "Events: 0  |  Visual candidates: 0  |  Promoted: 0  |  Learned transitions: 0")

    guiObj.Add("Text", "x18 y219 w500", "Promoted and high-value screen elements")
    g_UPControls["elements"] := guiObj.Add("ListView", "x15 y240 w860 h235 Grid -Multi AltSubmit",
        ["Name / candidate", "App", "Clicks", "Accesses", "Dwell", "Seen", "Score", "Promoted", "Area", "Last seen"])
    for column, width in [180, 115, 55, 60, 65, 50, 58, 65, 100, 125]
        g_UPControls["elements"].ModifyCol(column, width)

    g_UPControls["show"] := guiObj.Add("Button", "x15 y482 w100 h25", "Show Area")
    g_UPControls["promote"] := guiObj.Add("Button", "x123 y482 w105 h25", "Promote Now")
    g_UPControls["copy"] := guiObj.Add("Button", "x236 y482 w110 h25", "Copy FindText")
    g_UPControls["clear"] := guiObj.Add("Button", "x735 y482 w140 h25", "Clear Learned Data")

    guiObj.Add("Text", "x18 y516 w500", "Current predicted continuation")
    g_UPControls["prediction"] := guiObj.Add("ListView", "x15 y537 w860 h155 Grid -Multi",
        ["Step", "Predicted action", "Support", "Confidence", "Replay detail"])
    g_UPControls["prediction"].ModifyCol(1, 45)
    g_UPControls["prediction"].ModifyCol(2, 245)
    g_UPControls["prediction"].ModifyCol(3, 70)
    g_UPControls["prediction"].ModifyCol(4, 85)
    g_UPControls["prediction"].ModifyCol(5, 395)

    guiObj.Add("Text", "x15 y700 w860 h34 cGray",
        "Learns app changes, physical clicks, hotkeys/navigation, and typing bursts. "
        . "Literal text is optional; password/login windows are always excluded. Press Win+Shift+CapsLock only when the suggested continuation is correct.")

    g_UPControls["toggle"].OnEvent("Click", UsagePredictor_Toggle)
    g_UPControls["scan"].OnEvent("Click", (*) => UsagePredictor_VisualScan(true))
    g_UPControls["refresh"].OnEvent("Click", UsagePredictor_RefreshUI)
    g_UPControls["accept"].OnEvent("Click", UsagePredictor_AcceptPrediction)
    g_UPControls["text"].OnEvent("Click", UsagePredictor_SetTextCapture)
    g_UPControls["interval"].OnEvent("Change", UsagePredictor_SetScanInterval)
    g_UPControls["show"].OnEvent("Click", UsagePredictor_ShowSelected)
    g_UPControls["promote"].OnEvent("Click", UsagePredictor_PromoteSelected)
    g_UPControls["copy"].OnEvent("Click", UsagePredictor_CopySelectedPattern)
    g_UPControls["clear"].OnEvent("Click", UsagePredictor_ClearData)
    g_UPControls["elements"].OnEvent("DoubleClick", UsagePredictor_ShowSelected)
}

UsagePredictor_Init() {
    global g_UPReady, g_UPCaptureText, g_UPScanIntervalMs, g_UPControls, g_UPRecentEvents

    if !TrackDB_Ready() && !TrackDB_Init() {
        UsagePredictor_SetStatus("Cannot open tracking.db: " . g_TrackDBError)
        return false
    }
    try UsagePredictor_ApplySchema()
    catch as upErr {
        UsagePredictor_SetStatus("Predictor schema failed: " . upErr.Message)
        try TrackLogError("UsagePredictor_ApplySchema", upErr)
        return false
    }

    g_UPCaptureText := TrackDB_MetaGet("usage_predictor_literal_text", "0") = "1"
    savedInterval := TrackDB_MetaGet("usage_predictor_scan_ms", "6000")
    if IsNumber(savedInterval)
        g_UPScanIntervalMs := Max(3000, Min(30000, Integer(savedInterval)))

    if g_UPControls.Has("text")
        g_UPControls["text"].Value := g_UPCaptureText ? 1 : 0
    UsagePredictor_SelectIntervalControl()
    g_UPReady := true
    ; A restart begins a fresh live prefix. Learned transitions persist, but
    ; stale pre-restart events are not joined to the user's new session.
    g_UPRecentEvents := []
    UsagePredictor_RefreshUI()

    if TrackDB_MetaGet("usage_predictor_enabled", "1") = "1"
        UsagePredictor_Start()
    return true
}

UsagePredictor_ApplySchema() {
    db := TrackDB()
    if !db
        throw Error("tracking database is unavailable")

    db.Run("CREATE TABLE IF NOT EXISTS usage_element ("
        . "id INTEGER PRIMARY KEY AUTOINCREMENT, win_id INTEGER NOT NULL, app_id INTEGER NOT NULL, "
        . "signature TEXT NOT NULL, name TEXT, role TEXT, x INTEGER, y INTEGER, w INTEGER, h INTEGER, "
        . "rel_x REAL, rel_y REAL, rel_w REAL, rel_h REAL, pattern TEXT, verified INTEGER DEFAULT 0, "
        . "seen_count INTEGER DEFAULT 0, click_count INTEGER DEFAULT 0, access_count INTEGER DEFAULT 0, "
        . "dwell_ms INTEGER DEFAULT 0, score REAL DEFAULT 0, promoted INTEGER DEFAULT 0, element_id INTEGER DEFAULT 0, "
        . "first_ts TEXT, last_ts TEXT, UNIQUE(win_id, signature))")
    db.Run("CREATE INDEX IF NOT EXISTS ix_usage_element_win ON usage_element(win_id)")
    db.Run("CREATE INDEX IF NOT EXISTS ix_usage_element_score ON usage_element(score DESC)")

    db.Run("CREATE TABLE IF NOT EXISTS usage_event ("
        . "id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT, tick INTEGER, app_id INTEGER, win_id INTEGER, "
        . "kind TEXT, token TEXT, data TEXT, automated INTEGER DEFAULT 0)")
    db.Run("CREATE INDEX IF NOT EXISTS ix_usage_event_id ON usage_event(id DESC)")
    db.Run("CREATE INDEX IF NOT EXISTS ix_usage_event_token ON usage_event(token)")

    db.Run("CREATE TABLE IF NOT EXISTS usage_transition ("
        . "id INTEGER PRIMARY KEY AUTOINCREMENT, prefix_hash TEXT NOT NULL, prefix_text TEXT NOT NULL, "
        . "prefix_len INTEGER NOT NULL, next_token TEXT NOT NULL, next_kind TEXT, next_data TEXT, "
        . "support INTEGER DEFAULT 0, accepted INTEGER DEFAULT 0, last_ts TEXT, "
        . "UNIQUE(prefix_hash, next_token))")
    db.Run("CREATE INDEX IF NOT EXISTS ix_usage_transition_prefix ON usage_transition(prefix_hash, support DESC)")
}

UsagePredictor_Start(*) {
    global g_UPOn, g_UPInputHook, g_UPScanIntervalMs

    if g_UPOn
        return true
    if !TrackDB_Ready() {
        if !UsagePredictor_Init()
            return false
        if g_UPOn
            return true
    }

    try {
        ih := InputHook("I1 V")
        ih.VisibleText := true
        ih.VisibleNonText := true
        ih.NotifyNonText := true
        ih.KeyOpt("{All}", "N")
        ih.OnChar := UsagePredictor_OnChar
        ih.OnKeyDown := UsagePredictor_OnKeyDown
        ih.Start()
        g_UPInputHook := ih
    } catch as upErr {
        g_UPInputHook := ""
        try TrackLogError("UsagePredictor_InputHook", upErr)
    }

    g_UPOn := true
    TrackDB_MetaSet("usage_predictor_enabled", "1")
    SetTimer(UsagePredictor_Poll, 45)
    SetTimer(UsagePredictor_TypeTick, 250)
    SetTimer(UsagePredictor_VisualScanTick, g_UPScanIntervalMs)
    SetTimer(UsagePredictor_RefreshUI, 2500)
    SetTimer((*) => UsagePredictor_VisualScan(false), -700)
    UsagePredictor_RecordActiveWindow(true)
    UsagePredictor_UpdateToggle()
    UsagePredictor_SetStatus("Learning is ON. Full virtual-desktop visual scan is scheduled every "
        . Round(g_UPScanIntervalMs / 1000) . " seconds.")
    return true
}

UsagePredictor_Stop(*) {
    global g_UPOn, g_UPInputHook

    if !g_UPOn
        return
    UsagePredictor_FlushTyping(true)
    UsagePredictor_CommitHover()
    g_UPOn := false
    SetTimer(UsagePredictor_Poll, 0)
    SetTimer(UsagePredictor_TypeTick, 0)
    SetTimer(UsagePredictor_VisualScanTick, 0)
    SetTimer(UsagePredictor_RefreshUI, 0)
    if IsObject(g_UPInputHook) {
        try g_UPInputHook.Stop()
    }
    g_UPInputHook := ""
    TrackDB_MetaSet("usage_predictor_enabled", "0")
    UsagePredictor_UpdateToggle()
    UsagePredictor_SetStatus("Learning is paused. Existing local patterns and sequences are preserved.")
}

UsagePredictor_Toggle(*) {
    global g_UPOn
    if g_UPOn
        UsagePredictor_Stop()
    else
        UsagePredictor_Start()
}

UsagePredictor_OnExit(*) {
    try UsagePredictor_Stop()
}

UsagePredictor_UpdateToggle() {
    global g_UPOn, g_UPControls
    if g_UPControls.Has("toggle")
        g_UPControls["toggle"].Text := g_UPOn ? "Pause" : "Start"
}

UsagePredictor_SetTextCapture(ctrl, *) {
    global g_UPCaptureText
    g_UPCaptureText := ctrl.Value = 1
    TrackDB_MetaSet("usage_predictor_literal_text", g_UPCaptureText ? "1" : "0")
    UsagePredictor_SetStatus(g_UPCaptureText
        ? "Literal text capture enabled for non-sensitive windows. Data stays in tracking.db."
        : "Literal text capture disabled. Typing shape and length are still learned.")
}

UsagePredictor_SetScanInterval(ctrl, *) {
    global g_UPScanIntervalMs, g_UPOn
    seconds := Integer(RegExReplace(ctrl.Text, "\D"))
    g_UPScanIntervalMs := Max(3000, seconds * 1000)
    TrackDB_MetaSet("usage_predictor_scan_ms", String(g_UPScanIntervalMs))
    if g_UPOn {
        SetTimer(UsagePredictor_VisualScanTick, 0)
        SetTimer(UsagePredictor_VisualScanTick, g_UPScanIntervalMs)
    }
    UsagePredictor_SetStatus("Visual scan interval: " . seconds . " seconds.")
}

UsagePredictor_SelectIntervalControl() {
    global g_UPScanIntervalMs, g_UPControls
    if !g_UPControls.Has("interval")
        return
    seconds := Round(g_UPScanIntervalMs / 1000)
    options := [3, 6, 10, 20, 30]
    bestIndex := 1, bestDelta := 99999
    for index, value in options {
        delta := Abs(seconds - value)
        if delta < bestDelta
            bestDelta := delta, bestIndex := index
    }
    g_UPControls["interval"].Choose(bestIndex)
}

UsagePredictor_SetStatus(message) {
    global g_UPControls
    if g_UPControls.Has("status")
        g_UPControls["status"].Text := message
}

; Win+Shift+CapsLock accepts only a currently displayed, confidence-qualified
; chain. Vision Scout reserves Win+CapsLock for its independently learned offer.
#+CapsLock::UsagePredictor_AcceptPrediction()

; ---------------------------------------------------------------------------
; Physical input and application-event capture
; ---------------------------------------------------------------------------

UsagePredictor_Poll(*) {
    global g_UPOn, g_UPReplaying, g_UPLastPollTick, g_UPLastHoverPoll

    if !g_UPOn || g_UPReplaying
        return
    now := A_TickCount
    if (now - g_UPLastPollTick >= 180) {
        g_UPLastPollTick := now
        UsagePredictor_RecordActiveWindow()
    }

    UsagePredictor_CheckMouseButton("LButton", "Left")
    UsagePredictor_CheckMouseButton("RButton", "Right")
    UsagePredictor_CheckMouseButton("MButton", "Middle")

    if (now - g_UPLastHoverPoll >= 750) {
        g_UPLastHoverPoll := now
        UsagePredictor_UpdateHover()
    }
}

UsagePredictor_CheckMouseButton(keyName, buttonName) {
    global g_UPMouseDown
    down := GetKeyState(keyName, "P")
    wasDown := g_UPMouseDown[keyName]
    g_UPMouseDown[keyName] := down
    if (down && !wasDown)
        UsagePredictor_OnPhysicalClick(buttonName)
}

UsagePredictor_RecordActiveWindow(force := false) {
    global g_UPLastWindowHwnd
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd || (!force && hwnd = g_UPLastWindowHwnd)
        return
    g_UPLastWindowHwnd := hwnd

    ctx := TrackCtx_Get(0)
    if !UsagePredictor_ContextUsable(ctx)
        return
    UsagePredictor_FlushTyping(true)

    SplitPath(ctx["exe"], , , , &exeBase)
    stableName := TrackEllipsis(ctx["name"], 55)
    token := "APP:" . StrLower(exeBase) . ":" . stableName
    data := Map("exe", ctx["exe"], "title", ctx["title"], "name", ctx["name"],
        "class", ctx["class"], "hwnd", ctx["hwnd"])
    UsagePredictor_RecordEvent("APP", token, data, ctx)
}

UsagePredictor_OnPhysicalClick(buttonName) {
    global g_UPReplaying
    if g_UPReplaying
        return
    UsagePredictor_FlushTyping(true)
    MouseGetPos(&mx, &my)
    ctx := TrackCtx_Get(0)
    if !UsagePredictor_ContextUsable(ctx)
        return

    element := UsagePredictor_FindElementAt(ctx, mx, my)
    if !element.Count
        element := UsagePredictor_CaptureClickRegion(ctx, mx, my)

    elementId := element.Count && element.Has("id") ? Integer(element["id"]) : 0
    if elementId {
        db := TrackDB()
        db.Run("UPDATE usage_element SET click_count=click_count+1, access_count=access_count+1, "
            . "score=score+12, last_ts=? WHERE id=?", TrackTS(), elementId)
        UsagePredictor_PromoteIfReady(elementId)
    }

    relX := ctx["w"] > 0 ? (mx - ctx["x"]) / ctx["w"] : 0
    relY := ctx["h"] > 0 ? (my - ctx["y"]) / ctx["h"] : 0
    token := elementId
        ? "CLICK:E" . elementId . ":" . SubStr(buttonName, 1, 1)
        : "CLICK:R" . Round(relX * 20) . "," . Round(relY * 20) . ":" . SubStr(buttonName, 1, 1)
    data := Map("element_id", elementId, "button", buttonName, "x", mx, "y", my,
        "rel_x", relX, "rel_y", relY, "exe", ctx["exe"], "title", ctx["title"])
    UsagePredictor_RecordEvent("CLICK", token, data, ctx)
}

UsagePredictor_OnChar(ih, char) {
    global g_UPOn, g_UPReplaying, g_UPCaptureText, g_UPTypeBuffer
    global g_UPTypeCount, g_UPTypeWinId, g_UPTypeAppId, g_UPTypeStartedTick
    global g_UPTypeLastTick, g_UPTypeLetters, g_UPTypeDigits, g_UPTypeSpaces, g_UPTypeSymbols

    if !g_UPOn || g_UPReplaying
        return
    if (GetKeyState("Control", "P") || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P") || GetKeyState("RWin", "P"))
        return
    ctx := TrackCtx_Get(0)
    if !UsagePredictor_ContextUsable(ctx) || UsagePredictor_IsSensitive(ctx)
        return

    if (g_UPTypeWinId && g_UPTypeWinId != ctx["win_id"])
        UsagePredictor_FlushTyping(true)
    now := A_TickCount
    if (g_UPTypeLastTick && now - g_UPTypeLastTick > 1200)
        UsagePredictor_FlushTyping(true)
    if !g_UPTypeCount {
        g_UPTypeStartedTick := now
        g_UPTypeWinId := ctx["win_id"]
        g_UPTypeAppId := ctx["app_id"]
    }
    g_UPTypeLastTick := now
    g_UPTypeCount += StrLen(char)
    if g_UPCaptureText
        g_UPTypeBuffer.Push(char)

    Loop Parse, char {
        c := A_LoopField
        if RegExMatch(c, "[A-Za-z]")
            g_UPTypeLetters += 1
        else if RegExMatch(c, "\d")
            g_UPTypeDigits += 1
        else if RegExMatch(c, "\s")
            g_UPTypeSpaces += 1
        else
            g_UPTypeSymbols += 1
    }
}

UsagePredictor_OnKeyDown(ih, vk, sc) {
    global g_UPOn, g_UPReplaying, g_UPCaptureText, g_UPTypeBuffer, g_UPTypeCount
    if !g_UPOn || g_UPReplaying
        return

    keyName := ""
    try keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    if (keyName = "" || UsagePredictor_ArrayHas([
        "LControl", "RControl", "LShift", "RShift", "LAlt", "RAlt",
        "LWin", "RWin", "Control", "Shift", "Alt"
    ], keyName))
        return

    ctx := TrackCtx_Get(0)
    if !UsagePredictor_ContextUsable(ctx) || UsagePredictor_IsSensitive(ctx)
        return
    ctrl := GetKeyState("Control", "P")
    alt := GetKeyState("Alt", "P")
    win := GetKeyState("LWin", "P") || GetKeyState("RWin", "P")
    shift := GetKeyState("Shift", "P")

    if !(ctrl || alt || win) {
        if (keyName = "Backspace") {
            if g_UPTypeCount > 0
                g_UPTypeCount -= 1
            if (g_UPCaptureText && g_UPTypeBuffer.Length)
                g_UPTypeBuffer.Pop()
            return
        }
        if (StrLen(keyName) = 1 || keyName = "Space")
            return
    }

    UsagePredictor_FlushTyping(true)
    sendKey := ""
    if (ctrl || alt || win) {
        sendKey := (ctrl ? "^" : "") . (alt ? "!" : "") . (shift ? "+" : "") . (win ? "#" : "")
        sendKey .= StrLen(keyName) = 1 ? StrLower(keyName) : "{" . keyName . "}"
    } else {
        sendKey := "{" . keyName . "}"
    }
    token := "KEY:" . sendKey
    data := Map("send", sendKey, "key", keyName, "exe", ctx["exe"], "title", ctx["title"])
    UsagePredictor_RecordEvent("KEY", token, data, ctx)
}

UsagePredictor_TypeTick(*) {
    global g_UPTypeLastTick, g_UPTypeCount
    if (g_UPTypeCount && A_TickCount - g_UPTypeLastTick >= 850)
        UsagePredictor_FlushTyping(true)
}

UsagePredictor_FlushTyping(force := false) {
    global g_UPTypeBuffer, g_UPTypeCount, g_UPTypeWinId, g_UPTypeAppId
    global g_UPTypeStartedTick, g_UPTypeLastTick, g_UPTypeLetters, g_UPTypeDigits
    global g_UPTypeSpaces, g_UPTypeSymbols, g_UPCaptureText

    if !g_UPTypeCount
        return
    if !force && A_TickCount - g_UPTypeLastTick < 850
        return

    count := g_UPTypeCount
    shape := UsagePredictor_TypingShape(g_UPTypeLetters, g_UPTypeDigits, g_UPTypeSpaces, g_UPTypeSymbols)
    bucket := count <= 4 ? "tiny" : count <= 16 ? "short" : count <= 60 ? "medium" : "long"
    literal := g_UPCaptureText ? UsagePredictor_Join(g_UPTypeBuffer, "") : ""
    data := Map("text", literal, "length", count, "shape", shape, "bucket", bucket,
        "duration_ms", Max(0, g_UPTypeLastTick - g_UPTypeStartedTick))
    ctx := Map("win_id", g_UPTypeWinId, "app_id", g_UPTypeAppId)

    g_UPTypeBuffer := []
    g_UPTypeCount := 0
    g_UPTypeWinId := 0
    g_UPTypeAppId := 0
    g_UPTypeStartedTick := 0
    g_UPTypeLastTick := 0
    g_UPTypeLetters := 0
    g_UPTypeDigits := 0
    g_UPTypeSpaces := 0
    g_UPTypeSymbols := 0
    UsagePredictor_RecordEvent("TYPE", "TYPE:" . shape . ":" . bucket, data, ctx)
}

UsagePredictor_TypingShape(letters, digits, spaces, symbols) {
    total := Max(1, letters + digits + spaces + symbols)
    if (symbols / total > 0.28)
        return "code"
    if (digits / total > 0.55)
        return "number"
    if (spaces > 1 && letters / total > 0.55)
        return "prose"
    if (letters > 0 && digits > 0)
        return "mixed"
    return letters > 0 ? "text" : "symbols"
}

UsagePredictor_ContextUsable(ctx) {
    return IsObject(ctx) && ctx.Has("win_id") && Integer(ctx["win_id"]) > 0
}

UsagePredictor_IsSensitive(ctx) {
    try return KeyTrack_IsExcluded(ctx["name"])
    title := ctx.Has("title") ? ctx["title"] : ""
    return RegExMatch(title, "i)(password|passphrase|credential|sign in|log ?in|bitwarden|lastpass|keepass|1password)") != 0
}

; ---------------------------------------------------------------------------
; Event persistence and local sequence model
; ---------------------------------------------------------------------------

UsagePredictor_RecordEvent(kind, token, data, ctx) {
    global g_UPRecentEvents, g_UPLastEventTick, g_UPReplaying
    if g_UPReplaying || token = "" || !TrackDB_Ready()
        return

    now := A_TickCount
    if (g_UPLastEventTick && now - g_UPLastEventTick > 120000)
        g_UPRecentEvents := []
    delayMs := g_UPLastEventTick ? Min(30000, now - g_UPLastEventTick) : 0
    g_UPLastEventTick := now
    data["delay_ms"] := delayMs

    UsagePredictor_LearnTransitions(token, kind, data)
    db := TrackDB()
    db.Run("INSERT INTO usage_event(ts,tick,app_id,win_id,kind,token,data,automated) "
        . "VALUES(?,?,?,?,?,?,?,0)", TrackTS(), now,
        ctx.Has("app_id") ? ctx["app_id"] : 0,
        ctx.Has("win_id") ? ctx["win_id"] : 0,
        kind, token, TrackJsonEncode(data))

    g_UPRecentEvents.Push(Map("kind", kind, "token", token, "data", data))
    while g_UPRecentEvents.Length > 30
        g_UPRecentEvents.RemoveAt(1)
    UsagePredictor_BuildPrediction()

    ; Keep long-running sessions bounded while preserving enough history for
    ; pattern mining and audit views.
    if (Mod(db.LastInsertId(), 1000) = 0)
        db.Run("DELETE FROM usage_event WHERE id NOT IN (SELECT id FROM usage_event ORDER BY id DESC LIMIT 50000)")
}

UsagePredictor_LearnTransitions(nextToken, nextKind, nextData) {
    global g_UPRecentEvents
    db := TrackDB()
    available := Min(5, g_UPRecentEvents.Length)
    if available < 2
        return

    Loop available - 1 {
        prefixLen := A_Index + 1
        prefixTokens := []
        start := g_UPRecentEvents.Length - prefixLen + 1
        Loop prefixLen
            prefixTokens.Push(g_UPRecentEvents[start + A_Index - 1]["token"])
        prefixText := UsagePredictor_Join(prefixTokens, " > ")
        prefixHash := TrackHash(prefixText)
        db.Run("INSERT INTO usage_transition(prefix_hash,prefix_text,prefix_len,next_token,next_kind,next_data,support,last_ts) "
            . "VALUES(?,?,?,?,?,?,1,?) ON CONFLICT(prefix_hash,next_token) DO UPDATE SET "
            . "support=usage_transition.support+1, next_kind=excluded.next_kind, "
            . "next_data=excluded.next_data, last_ts=excluded.last_ts",
            prefixHash, prefixText, prefixLen, nextToken, nextKind, TrackJsonEncode(nextData), TrackTS())
    }
}

UsagePredictor_LoadRecentEvents() {
    global g_UPRecentEvents
    g_UPRecentEvents := []
    if !TrackDB_Ready()
        return
    rows := TrackDB().Query("SELECT kind,token,data FROM usage_event WHERE automated=0 ORDER BY id DESC LIMIT 30")
    index := rows.Length
    while index >= 1 {
        row := rows[index]
        data := Map()
        try data := TrackJsonDecode(row["data"])
        g_UPRecentEvents.Push(Map("kind", row["kind"], "token", row["token"], "data", data))
        index -= 1
    }
}

UsagePredictor_BuildPrediction() {
    global g_UPRecentEvents, g_UPPrediction, g_UPPredictionSignature
    global g_UPLastPredictionTick

    if g_UPRecentEvents.Length < 2 || !TrackDB_Ready()
        return
    working := []
    for event in g_UPRecentEvents
        working.Push(event["token"])
    chain := []
    seen := Map()

    Loop 6 {
        next := UsagePredictor_BestNext(working)
        if !next.Count
            break
        loopKey := next["token"] . "|" . next["kind"]
        seen[loopKey] := seen.Has(loopKey) ? seen[loopKey] + 1 : 1
        if seen[loopKey] > 2
            break
        chain.Push(next)
        working.Push(next["token"])
        while working.Length > 30
            working.RemoveAt(1)
    }

    if chain.Length < 2 {
        g_UPPrediction := []
        UsagePredictor_RefreshPredictionUI()
        return
    }
    signatureParts := []
    for action in chain
        signatureParts.Push(action["token"])
    signature := TrackHash(UsagePredictor_Join(signatureParts, " > "))
    g_UPPrediction := chain
    UsagePredictor_RefreshPredictionUI()

    if (signature = g_UPPredictionSignature && A_TickCount - g_UPLastPredictionTick < 20000)
        return
    g_UPPredictionSignature := signature
    g_UPLastPredictionTick := A_TickCount
    UsagePredictor_ShowPredictionTip()
}

UsagePredictor_BestNext(tokens) {
    global g_UPMinSupport, g_UPMinConfidence
    db := TrackDB()
    maxPrefix := Min(5, tokens.Length)
    prefixLen := maxPrefix
    while prefixLen >= 2 {
        parts := []
        start := tokens.Length - prefixLen + 1
        Loop prefixLen
            parts.Push(tokens[start + A_Index - 1])
        prefixText := UsagePredictor_Join(parts, " > ")
        rows := db.Query("SELECT * FROM usage_transition WHERE prefix_hash=? AND prefix_text=? "
            . "ORDER BY support DESC LIMIT 20", TrackHash(prefixText), prefixText)
        if rows.Length {
            total := 0
            for row in rows
                total += Integer(row["support"])
            best := rows[1]
            confidence := total > 0 ? Integer(best["support"]) / total : 0
            if (Integer(best["support"]) >= g_UPMinSupport && confidence >= g_UPMinConfidence) {
                data := Map()
                try data := TrackJsonDecode(best["next_data"])
                return Map("transition_id", Integer(best["id"]), "token", best["next_token"],
                    "kind", best["next_kind"], "data", data, "support", Integer(best["support"]),
                    "confidence", confidence, "prefix", prefixText)
            }
        }
        prefixLen -= 1
    }
    return Map()
}

UsagePredictor_ShowPredictionTip() {
    global g_UPPrediction
    if !g_UPPrediction.Length
        return
    lines := []
    maxShow := Min(4, g_UPPrediction.Length)
    Loop maxShow
        lines.Push(A_Index . ". " . UsagePredictor_ActionLabel(g_UPPrediction[A_Index]))
    more := g_UPPrediction.Length > maxShow ? "`n+ " . (g_UPPrediction.Length - maxShow) . " more step(s)" : ""
    message := "Repeated sequence found:`n" . UsagePredictor_Join(lines, "`n") . more
        . "`n`nPress Win+Shift+CapsLock to continue automatically."
    MouseGetPos(&mx, &my)
    ToolTip(message, mx + 22, my + 22, 19)
    SetTimer(UsagePredictor_ClearTip, -9000)
    UsagePredictor_SetStatus("Sequence prediction ready: " . g_UPPrediction.Length
        . " step(s). Press Win+Shift+CapsLock to run it.")
}

UsagePredictor_ClearTip(*) {
    ToolTip(, , , 19)
}

; ---------------------------------------------------------------------------
; Full virtual-desktop visual sampling and FindText verification
; ---------------------------------------------------------------------------

UsagePredictor_VisualScanTick(*) {
    UsagePredictor_VisualScan(false)
}

UsagePredictor_VisualScan(manual := false, *) {
    global g_UPOn, g_UPReplaying, g_UPScanBusy, g_UPScanCursor
    global g_UPLastScanTs, g_UPLastScanCount, g_UPMaxPatternsPerScan

    if ((!g_UPOn && !manual) || g_UPReplaying || g_UPScanBusy)
        return
    if !TrackDB_Ready()
        return
    g_UPScanBusy := true
    started := A_TickCount
    saved := 0
    try {
        regions := UsagePredictor_DetectScreenRegions()
        if regions.Length {
            ; Half the budget always goes to the strongest regions. The other
            ; half rotates through the remainder so repeated scans eventually
            ; cover every contrast-bearing part of every monitor.
            budget := Min(g_UPMaxPatternsPerScan, regions.Length)
            strongCount := Min(Ceil(budget / 2), regions.Length)
            chosen := []
            Loop strongCount
                chosen.Push(regions[A_Index])

            remainderStart := strongCount + 1
            remainderCount := regions.Length - strongCount
            if remainderCount > 0 {
                if (g_UPScanCursor < 1 || g_UPScanCursor > remainderCount)
                    g_UPScanCursor := 1
                Loop budget - strongCount {
                    offset := Mod(g_UPScanCursor + A_Index - 2, remainderCount)
                    chosen.Push(regions[remainderStart + offset])
                }
                g_UPScanCursor := Mod(g_UPScanCursor + budget - strongCount - 1, remainderCount) + 1
            }

            for region in chosen {
                ctx := UsagePredictor_ContextAt(region["x"] + region["w"] // 2,
                    region["y"] + region["h"] // 2)
                if !UsagePredictor_ContextUsable(ctx)
                    continue
                refined := UsagePredictor_RefineRegion(region)
                patternInfo := UsagePredictor_GeneratePattern(refined)
                if patternInfo["pattern"] = ""
                    continue
                id := UsagePredictor_SaveRegion(ctx, refined, patternInfo,
                    "visual-candidate", region["visual_score"])
                if id
                    saved += 1
            }
        }
        g_UPLastScanTs := TrackTS()
        g_UPLastScanCount := saved
        UsagePredictor_SetStatus("Visual scan analyzed the complete virtual desktop: "
            . regions.Length . " relevant area(s), " . saved . " FindText pattern(s) verified/stored in "
            . (A_TickCount - started) . " ms.")
        UsagePredictor_RefreshUI()
    } catch as upErr {
        UsagePredictor_SetStatus("Visual scan failed: " . upErr.Message)
        try TrackLogError("UsagePredictor_VisualScan", upErr)
    } finally {
        g_UPScanBusy := false
    }
}

UsagePredictor_DetectScreenRegions() {
    regions := []
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    if (vw < 1 || vh < 1)
        return regions

    ft := FindText()
    ft.ScreenShot(vx, vy, vx + vw - 1, vy + vh - 1)

    tileW := 96, tileH := 64
    tileCount := Ceil(vw / tileW) * Ceil(vh / tileH)
    if tileCount > 2200 {
        factor := Sqrt(tileCount / 2200)
        tileW := Ceil(tileW * factor)
        tileH := Ceil(tileH * factor)
    }

    y := vy
    while y < vy + vh {
        h := Min(tileH, vy + vh - y)
        x := vx
        while x < vx + vw {
            w := Min(tileW, vx + vw - x)
            score := UsagePredictor_TileContrast(ft, x, y, w, h)
            if score >= 34 {
                regions.Push(Map("x", x, "y", y, "w", w, "h", h,
                    "visual_score", score))
            }
            x += tileW
        }
        y += tileH
    }
    UsagePredictor_SortRegions(regions)
    return regions
}

UsagePredictor_TileContrast(ft, x, y, w, h) {
    if (w < 8 || h < 8)
        return 0
    lumMin := 255, lumMax := 0, saturationMax := 0, edgeTotal := 0
    previous := -1
    positions := [
        [0.12, 0.15], [0.50, 0.15], [0.88, 0.15],
        [0.12, 0.50], [0.50, 0.50], [0.88, 0.50],
        [0.12, 0.85], [0.50, 0.85], [0.88, 0.85]
    ]
    for point in positions {
        sx := x + Min(w - 1, Round((w - 1) * point[1]))
        sy := y + Min(h - 1, Round((h - 1) * point[2]))
        color := ft.GetColor(sx, sy, 0)
        red := (color >> 16) & 0xFF
        green := (color >> 8) & 0xFF
        blue := color & 0xFF
        lum := (red * 38 + green * 75 + blue * 15) >> 7
        lumMin := Min(lumMin, lum), lumMax := Max(lumMax, lum)
        saturationMax := Max(saturationMax, Max(red, green, blue) - Min(red, green, blue))
        if previous >= 0
            edgeTotal += Abs(lum - previous)
        previous := lum
    }
    return (lumMax - lumMin) + Min(50, edgeTotal / 8) + Min(24, saturationMax / 4)
}

UsagePredictor_SortRegions(regions) {
    ; Small insertion sort avoids depending on an external array-sort helper.
    index := 2
    while index <= regions.Length {
        item := regions[index]
        cursor := index - 1
        while (cursor >= 1 && regions[cursor]["visual_score"] < item["visual_score"]) {
            regions[cursor + 1] := regions[cursor]
            cursor -= 1
        }
        regions[cursor + 1] := item
        index += 1
    }
}

UsagePredictor_RefineRegion(region) {
    ; Refine a coarse tile to the bounding box of pixels that differ from the
    ; tile's corner-derived background. This estimates the individual finding's
    ; area before its FindText pattern is generated.
    ft := FindText()
    x := region["x"], y := region["y"], w := region["w"], h := region["h"]
    ft.ScreenShot(x, y, x + w - 1, y + h - 1)
    corners := [ft.GetColor(x, y, 0), ft.GetColor(x + w - 1, y, 0),
        ft.GetColor(x, y + h - 1, 0), ft.GetColor(x + w - 1, y + h - 1, 0)]
    bgR := 0, bgG := 0, bgB := 0
    for color in corners {
        bgR += (color >> 16) & 0xFF
        bgG += (color >> 8) & 0xFF
        bgB += color & 0xFF
    }
    bgR //= 4, bgG //= 4, bgB //= 4
    minX := w, minY := h, maxX := -1, maxY := -1, points := 0
    step := Max(3, Floor(Min(w, h) / 18))
    sy := 0
    while sy < h {
        sx := 0
        while sx < w {
            color := ft.GetColor(x + sx, y + sy, 0)
            red := (color >> 16) & 0xFF
            green := (color >> 8) & 0xFF
            blue := color & 0xFF
            difference := Abs(red - bgR) + Abs(green - bgG) + Abs(blue - bgB)
            if difference >= 70 {
                minX := Min(minX, sx), minY := Min(minY, sy)
                maxX := Max(maxX, sx), maxY := Max(maxY, sy)
                points += 1
            }
            sx += step
        }
        sy += step
    }
    if (points < 4 || maxX < minX || maxY < minY)
        return region

    pad := 5
    rx := x + Max(0, minX - pad)
    ry := y + Max(0, minY - pad)
    right := x + Min(w - 1, maxX + pad)
    bottom := y + Min(h - 1, maxY + pad)
    return Map("x", rx, "y", ry, "w", Max(8, right - rx + 1),
        "h", Max(8, bottom - ry + 1), "visual_score", region["visual_score"])
}

UsagePredictor_GeneratePattern(region) {
    result := Map("pattern", "", "verified", 0)
    x := region["x"], y := region["y"], w := region["w"], h := region["h"]
    if (w < 8 || h < 8 || w * h > 25000)
        return result
    try {
        raw := FindText().GetTextFromScreen(x, y, x + w - 1, y + h - 1, "**50")
        if (raw = "" || StrLen(raw) < 12)
            return result
        pattern := "|<UP_" . TrackHash(raw) . ">" . raw
        found := FindText(&fx := 0, &fy := 0, x, y, x + w - 1, y + h - 1,
            0.18, 0.18, pattern)
        result["pattern"] := pattern
        result["verified"] := found && found.Length ? 1 : 0
    }
    return result
}

UsagePredictor_ContextAt(x, y) {
    empty := Map("win_id", 0, "app_id", 0, "hwnd", 0, "title", "", "name", "",
        "exe", "", "class", "", "x", 0, "y", 0, "w", 0, "h", 0)
    point := (y << 32) | (x & 0xFFFFFFFF)
    hwnd := DllCall("WindowFromPoint", "Int64", point, "Ptr")
    if !hwnd
        return empty
    root := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
    if root
        hwnd := root
    pid := 0
    try pid := WinGetPID("ahk_id " . hwnd)
    if (!pid || pid = DllCall("GetCurrentProcessId", "UInt"))
        return empty

    title := "", exe := "", windowClass := ""
    try title := WinGetTitle("ahk_id " . hwnd)
    try exe := WinGetProcessName("ahk_id " . hwnd)
    try windowClass := WinGetClass("ahk_id " . hwnd)
    if (title = "" || title = "Program Manager")
        return empty
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    catch
        return empty
    if (ww < 1 || wh < 1)
        return empty
    identity := TrackDB_ResolveWindow(title, windowClass, exe)
    return Map("win_id", identity["win_id"], "app_id", identity["app_id"], "hwnd", hwnd,
        "title", title, "name", identity["name"], "exe", exe, "class", windowClass,
        "x", wx, "y", wy, "w", ww, "h", wh)
}

UsagePredictor_SaveRegion(ctx, region, patternInfo, role, visualScore := 0) {
    db := TrackDB()
    if !db || !UsagePredictor_ContextUsable(ctx)
        return 0
    x := region["x"], y := region["y"], w := region["w"], h := region["h"]
    relX := (x - ctx["x"]) / Max(1, ctx["w"])
    relY := (y - ctx["y"]) / Max(1, ctx["h"])
    relW := w / Max(1, ctx["w"])
    relH := h / Max(1, ctx["h"])
    pattern := patternInfo["pattern"]
    signature := TrackHash(pattern != "" ? pattern : ctx["win_id"] . "|" . relX . "|" . relY)
    now := TrackTS()

    row := db.QueryRow("SELECT * FROM usage_element WHERE win_id=? AND "
        . "(signature=? OR (ABS(rel_x-?)<0.035 AND ABS(rel_y-?)<0.035 "
        . "AND ABS(rel_w-?)<0.06 AND ABS(rel_h-?)<0.06)) "
        . "ORDER BY CASE WHEN signature=? THEN 0 ELSE 1 END LIMIT 1",
        ctx["win_id"], signature, relX, relY, relW, relH, signature)
    scoreAdd := Max(0.5, Min(5.0, visualScore / 30.0)) + (patternInfo["verified"] ? 2 : 0)
    if row.Count {
        id := Integer(row["id"])
        db.Run("UPDATE usage_element SET signature=?, role=?, x=?,y=?,w=?,h=?, "
            . "rel_x=?,rel_y=?,rel_w=?,rel_h=?, pattern=CASE WHEN ?<>'' THEN ? ELSE pattern END, "
            . "verified=MAX(verified,?), seen_count=seen_count+1, score=score+?, last_ts=? WHERE id=?",
            signature, role, x, y, w, h, relX, relY, relW, relH,
            pattern, pattern, patternInfo["verified"], scoreAdd, now, id)
        return id
    }

    db.Run("INSERT INTO usage_element(win_id,app_id,signature,name,role,x,y,w,h,rel_x,rel_y,rel_w,rel_h,"
        . "pattern,verified,seen_count,score,first_ts,last_ts) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,1,?,?,?)",
        ctx["win_id"], ctx["app_id"], signature, "Candidate " . SubStr(signature, 1, 8), role,
        x, y, w, h, relX, relY, relW, relH, pattern, patternInfo["verified"], scoreAdd, now, now)
    return db.LastInsertId()
}

UsagePredictor_CaptureClickRegion(ctx, mx, my) {
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    left := Max(vx, mx - 48), top := Max(vy, my - 32)
    right := Min(vx + vw - 1, mx + 47), bottom := Min(vy + vh - 1, my + 31)
    region := Map("x", left, "y", top, "w", right - left + 1, "h", bottom - top + 1,
        "visual_score", 80)
    patternInfo := UsagePredictor_GeneratePattern(region)
    id := UsagePredictor_SaveRegion(ctx, region, patternInfo, "click-target", 80)
    return id ? TrackDB().QueryRow("SELECT * FROM usage_element WHERE id=?", id) : Map()
}

; ---------------------------------------------------------------------------
; Access/dwell scoring and promotion into MacroAutomator's element registry
; ---------------------------------------------------------------------------

UsagePredictor_FindElementAt(ctx, x, y) {
    if !UsagePredictor_ContextUsable(ctx) || ctx["w"] <= 0 || ctx["h"] <= 0
        return Map()
    relX := (x - ctx["x"]) / ctx["w"]
    relY := (y - ctx["y"]) / ctx["h"]
    return TrackDB().QueryRow("SELECT * FROM usage_element WHERE win_id=? "
        . "AND rel_x<=? AND rel_y<=? AND rel_x+rel_w>=? AND rel_y+rel_h>=? "
        . "ORDER BY promoted DESC, (rel_w*rel_h) ASC, score DESC LIMIT 1",
        ctx["win_id"], relX, relY, relX, relY)
}

UsagePredictor_UpdateHover() {
    global g_UPHoverElementId, g_UPHoverStartedTick
    MouseGetPos(&mx, &my)
    ctx := TrackCtx_Get(0)
    nextId := 0
    if UsagePredictor_ContextUsable(ctx) {
        row := UsagePredictor_FindElementAt(ctx, mx, my)
        if row.Count
            nextId := Integer(row["id"])
    }
    if (nextId = g_UPHoverElementId)
        return
    UsagePredictor_CommitHover()
    g_UPHoverElementId := nextId
    g_UPHoverStartedTick := nextId ? A_TickCount : 0
}

UsagePredictor_CommitHover() {
    global g_UPHoverElementId, g_UPHoverStartedTick
    if !g_UPHoverElementId || !g_UPHoverStartedTick
        return
    duration := A_TickCount - g_UPHoverStartedTick
    id := g_UPHoverElementId
    g_UPHoverElementId := 0
    g_UPHoverStartedTick := 0
    if duration < 350 || !TrackDB_Ready()
        return
    TrackDB().Run("UPDATE usage_element SET dwell_ms=dwell_ms+?, access_count=access_count+1, "
        . "score=score+?, last_ts=? WHERE id=?", duration, Min(8.0, duration / 900.0), TrackTS(), id)
    UsagePredictor_PromoteIfReady(id)
}

UsagePredictor_PromoteIfReady(id, force := false) {
    if !id || !TrackDB_Ready()
        return 0
    db := TrackDB()
    row := db.QueryRow("SELECT ue.*,a.exe FROM usage_element ue "
        . "LEFT JOIN app a ON a.id=ue.app_id WHERE ue.id=?", id)
    if !row.Count
        return 0
    if Integer(row["promoted"])
        return row["element_id"]

    clicks := Integer(row["click_count"])
    accesses := Integer(row["access_count"])
    dwell := Integer(row["dwell_ms"])
    if !force && clicks < 3 && !(accesses >= 8 && dwell >= 8000)
        return 0

    SplitPath(row["exe"], , , , &exeBase)
    safeApp := TrackSafeName(exeBase = "" ? "App" : exeBase)
    name := "Learned_" . safeApp . "_" . id
    el := Map("win_id", row["win_id"], "app_id", row["app_id"], "name", name,
        "description", "Auto-promoted by v9 usage learner after " . clicks . " click(s), "
            . accesses . " access(es), and " . TrackFormatMs(dwell) . " dwell.",
        "role", "learned-visual", "x", row["x"], "y", row["y"], "w", row["w"], "h", row["h"],
        "rel_x", row["rel_x"], "rel_y", row["rel_y"], "rel_w", row["rel_w"], "rel_h", row["rel_h"],
        "bin_text", row["pattern"], "ocr_text", "", "image_path", "", "b64", "")
    elementId := TrackDB_SaveElement(el)
    if elementId {
        db.Run("UPDATE usage_element SET promoted=1,element_id=?,name=?,role='promoted',last_ts=? WHERE id=?",
            elementId, name, TrackTS(), id)
        try UpdateElementActionChoices()
    }
    return elementId
}

UsagePredictor_SelectedElementId(rowNumber := 0) {
    global g_UPControls, g_UPCandidateRows
    if !g_UPControls.Has("elements")
        return 0
    list := g_UPControls["elements"]
    if !rowNumber
        rowNumber := list.GetNext(0, "F")
    if !rowNumber
        rowNumber := list.GetNext()
    return rowNumber && g_UPCandidateRows.Has(rowNumber) ? g_UPCandidateRows[rowNumber] : 0
}

UsagePredictor_ShowSelected(ctrl := 0, rowNumber := 0, *) {
    id := UsagePredictor_SelectedElementId(rowNumber)
    if !id
        return
    row := TrackDB().QueryRow("SELECT * FROM usage_element WHERE id=?", id)
    if !row.Count
        return
    try HighlightRegion(Integer(row["x"]), Integer(row["y"]), Integer(row["w"]), Integer(row["h"]),
        1800, "highlight", row["name"])
}

UsagePredictor_PromoteSelected(*) {
    id := UsagePredictor_SelectedElementId()
    if !id
        return
    elementId := UsagePredictor_PromoteIfReady(id, true)
    UsagePredictor_SetStatus(elementId
        ? "Candidate promoted into the shared element registry."
        : "Candidate could not be promoted; it may not contain a usable pattern.")
    UsagePredictor_RefreshUI()
}

UsagePredictor_CopySelectedPattern(*) {
    id := UsagePredictor_SelectedElementId()
    if !id
        return
    pattern := TrackDB().Scalar("SELECT pattern FROM usage_element WHERE id=?", id)
    if (pattern = "")
        return
    A_Clipboard := pattern
    UsagePredictor_SetStatus("Selected FindText pattern copied to the clipboard.")
}

; ---------------------------------------------------------------------------
; Prediction replay
; ---------------------------------------------------------------------------

UsagePredictor_AcceptPrediction(*) {
    global g_UPOn, g_UPPrediction, g_UPReplaying, g_UPRecentEvents
    if !g_UPOn {
        ToolTip("Usage Predictor is paused.", , , 19)
        SetTimer(UsagePredictor_ClearTip, -1500)
        return
    }
    if !g_UPPrediction.Length {
        ToolTip("No confidence-qualified continuation is ready yet.", , , 19)
        SetTimer(UsagePredictor_ClearTip, -1800)
        return
    }

    chain := g_UPPrediction.Clone()
    g_UPPrediction := []
    UsagePredictor_ClearTip()
    g_UPReplaying := true
    completed := 0
    try {
        for action in chain {
            delay := action["data"].Has("delay_ms") ? Integer(action["data"]["delay_ms"]) : 150
            Sleep(Max(80, Min(1600, delay)))
            if !UsagePredictor_ReplayAction(action)
                break
            completed += 1
            TrackDB().Run("UPDATE usage_transition SET accepted=accepted+1 WHERE id=?", action["transition_id"])
            g_UPRecentEvents.Push(Map("kind", action["kind"], "token", action["token"], "data", action["data"]))
            while g_UPRecentEvents.Length > 30
                g_UPRecentEvents.RemoveAt(1)
        }
    } catch as upErr {
        try TrackLogError("UsagePredictor_AcceptPrediction", upErr)
    } finally {
        g_UPReplaying := false
        UsagePredictor_RefreshPredictionUI()
    }
    UsagePredictor_SetStatus("Prediction replay completed " . completed . " of " . chain.Length . " step(s).")
}

UsagePredictor_ReplayAction(action) {
    kind := action["kind"], data := action["data"]
    switch kind {
        case "APP":
            return UsagePredictor_ActivateApp(data)
        case "CLICK":
            return UsagePredictor_ReplayClick(data)
        case "KEY":
            if !data.Has("send") || data["send"] = ""
                return false
            Send(data["send"])
            return true
        case "TYPE":
            if !data.Has("text") || data["text"] = "" {
                UsagePredictor_SetStatus("Prediction stopped at an uncaptured typing step. Enable literal text only if desired.")
                return false
            }
            SendText(data["text"])
            return true
    }
    return false
}

UsagePredictor_ActivateApp(data) {
    exe := data.Has("exe") ? data["exe"] : ""
    title := data.Has("title") ? data["title"] : ""
    if (title != "") {
        try {
            if hwnd := WinExist(title) {
                WinActivate("ahk_id " . hwnd)
                return WinWaitActive("ahk_id " . hwnd, , 2) != 0
            }
        }
    }
    if (exe != "") {
        try {
            if hwnd := WinExist("ahk_exe " . exe) {
                WinActivate("ahk_id " . hwnd)
                return WinWaitActive("ahk_id " . hwnd, , 2) != 0
            }
        }
    }
    return false
}

UsagePredictor_ReplayClick(data) {
    button := data.Has("button") ? data["button"] : "Left"
    elementId := data.Has("element_id") ? Integer(data["element_id"]) : 0
    if elementId {
        row := TrackDB().QueryRow("SELECT ue.*,a.exe,w.name AS win_name,w.raw_title FROM usage_element ue "
            . "LEFT JOIN app a ON a.id=ue.app_id LEFT JOIN win w ON w.id=ue.win_id WHERE ue.id=?", elementId)
        if row.Count {
            loc := UsagePredictor_LocateElement(row)
            if loc.Count {
                Click(loc["x"], loc["y"], button)
                return true
            }
        }
    }

    if data.Has("exe") && data["exe"] != ""
        UsagePredictor_ActivateApp(data)
    info := TrackGetActiveWindow()
    if info["ok"] && data.Has("rel_x") && data.Has("rel_y") {
        x := info["x"] + Round(Float(data["rel_x"]) * info["w"])
        y := info["y"] + Round(Float(data["rel_y"]) * info["h"])
        Click(x, y, button)
        return true
    }
    return false
}

UsagePredictor_LocateElement(row) {
    pattern := row["pattern"]
    if (pattern != "") {
        vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
        try {
            found := FindText(&fx := 0, &fy := 0, vx, vy, vx + vw - 1, vy + vh - 1,
                0.20, 0.20, pattern)
            if found && found.Length
                return Map("x", found[1].mx, "y", found[1].my, "method", "FindText")
        }
    }

    hwnd := 0
    if row.Has("raw_title") && row["raw_title"] != ""
        try hwnd := WinExist(row["raw_title"])
    if (!hwnd && row.Has("exe") && row["exe"] != "")
        try hwnd := WinExist("ahk_exe " . row["exe"])
    if !hwnd
        return Map()
    try WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    catch
        return Map()
    return Map("x", wx + Round((Float(row["rel_x"]) + Float(row["rel_w"]) / 2) * ww),
        "y", wy + Round((Float(row["rel_y"]) + Float(row["rel_h"]) / 2) * wh),
        "method", "relative")
}

UsagePredictor_ActionLabel(action) {
    kind := action["kind"], data := action["data"]
    switch kind {
        case "APP":
            return "Activate " . (data.Has("name") ? TrackEllipsis(data["name"], 45) : action["token"])
        case "CLICK":
            return (data.Has("button") ? data["button"] : "Left") . " click "
                . (data.Has("element_id") && data["element_id"] ? "learned element " . data["element_id"] : "relative target")
        case "KEY":
            return "Press " . (data.Has("send") ? data["send"] : action["token"])
        case "TYPE":
            return data.Has("text") && data["text"] != ""
                ? "Type " . TrackEllipsis(data["text"], 35)
                : "Manual typing (content not stored)"
    }
    return action["token"]
}

UsagePredictor_ActionDetail(action) {
    data := action["data"]
    switch action["kind"] {
        case "CLICK":
            return data.Has("element_id") && data["element_id"]
                ? "FindText element #" . data["element_id"] . " with relative fallback"
                : "Window-relative click fallback"
        case "TYPE":
            return data.Has("text") && data["text"] != "" ? "Literal text available locally" : "Stops for manual text"
        case "APP":
            return data.Has("exe") ? data["exe"] : "Window activation"
        case "KEY":
            return data.Has("send") ? data["send"] : "Key replay"
    }
    return ""
}

; ---------------------------------------------------------------------------
; Dashboard refresh and maintenance
; ---------------------------------------------------------------------------

UsagePredictor_RefreshUI(*) {
    global g_UPControls, g_UPCandidateRows, g_UPOn, g_UPLastScanTs, g_UPLastScanCount
    if !g_UPControls.Has("elements") || !TrackDB_Ready()
        return
    db := TrackDB()
    events := db.Scalar("SELECT COUNT(*) FROM usage_event")
    elements := db.Scalar("SELECT COUNT(*) FROM usage_element")
    promoted := db.Scalar("SELECT COUNT(*) FROM usage_element WHERE promoted=1")
    transitions := db.Scalar("SELECT COUNT(*) FROM usage_transition")
    g_UPControls["stats"].Text := "Events: " . events . "  |  Visual candidates: " . elements
        . "  |  Promoted: " . promoted . "  |  Learned transitions: " . transitions
        . "  |  Last scan: " . g_UPLastScanTs . " (" . g_UPLastScanCount . ")"

    list := g_UPControls["elements"]
    selectedId := UsagePredictor_SelectedElementId()
    list.Opt("-Redraw")
    list.Delete()
    g_UPCandidateRows := Map()
    rows := db.Query("SELECT ue.*,a.display AS app_display,a.exe FROM usage_element ue "
        . "LEFT JOIN app a ON a.id=ue.app_id ORDER BY ue.promoted DESC,ue.click_count DESC,ue.score DESC LIMIT 250")
    for row in rows {
        displayName := row["name"] != "" ? row["name"] : "Candidate " . row["id"]
        area := row["w"] . "x" . row["h"] . " @ " . row["x"] . "," . row["y"]
        item := list.Add("", displayName,
            row["app_display"] != "" ? row["app_display"] : row["exe"],
            row["click_count"], row["access_count"], TrackFormatMs(row["dwell_ms"]),
            row["seen_count"], Round(Float(row["score"]), 1),
            Integer(row["promoted"]) ? "YES" : "", area, row["last_ts"])
        g_UPCandidateRows[item] := Integer(row["id"])
        if (selectedId && Integer(row["id"]) = selectedId)
            list.Modify(item, "Select Focus Vis")
    }
    list.Opt("+Redraw")
    UsagePredictor_RefreshPredictionUI()
    UsagePredictor_UpdateToggle()
}

UsagePredictor_RefreshPredictionUI() {
    global g_UPControls, g_UPPrediction
    if !g_UPControls.Has("prediction")
        return
    list := g_UPControls["prediction"]
    list.Delete()
    for index, action in g_UPPrediction {
        list.Add("", index, UsagePredictor_ActionLabel(action), action["support"],
            Round(action["confidence"] * 100) . "%", UsagePredictor_ActionDetail(action))
    }
}

UsagePredictor_ClearData(*) {
    global g_UPRecentEvents, g_UPPrediction, g_UPPredictionSignature
    answer := MsgBox("Delete locally learned usage events, transition predictions, and visual candidates?`n`n"
        . "Elements already promoted into MacroAutomator's shared element registry will be preserved.",
        "Clear Usage Learner Data", "YesNo Icon! Default2")
    if answer != "Yes"
        return
    UsagePredictor_CommitHover()
    db := TrackDB()
    db.Begin()
    try {
        db.Run("DELETE FROM usage_transition")
        db.Run("DELETE FROM usage_event")
        db.Run("DELETE FROM usage_element")
        db.Commit()
    } catch as upErr {
        db.Rollback()
        UsagePredictor_SetStatus("Could not clear learner data: " . upErr.Message)
        return
    }
    g_UPRecentEvents := []
    g_UPPrediction := []
    g_UPPredictionSignature := ""
    UsagePredictor_RefreshUI()
    UsagePredictor_SetStatus("Learned usage data cleared. Promoted shared elements were preserved.")
}

UsagePredictor_AddTrayMenu() {
    global g_UPTrayMenu
    g_UPTrayMenu := Menu()
    g_UPTrayMenu.Add("Start / Pause Learning", UsagePredictor_Toggle)
    g_UPTrayMenu.Add("Scan Screen Now", (*) => UsagePredictor_VisualScan(true))
    g_UPTrayMenu.Add("Run Current Prediction (Win+Shift+CapsLock)", UsagePredictor_AcceptPrediction)
    g_UPTrayMenu.Add()
    g_UPTrayMenu.Add("Open Usage Predictor Tab", UsagePredictor_ShowTab)
    A_TrayMenu.Add("Usage Predictor", g_UPTrayMenu)
}

UsagePredictor_ShowTab(*) {
    global MainGui, TabCtrl, g_GuiVisible, g_UPTabIndex
    try TabCtrl.Choose(g_UPTabIndex)
    MainGui.Show()
    g_GuiVisible := true
    try WinActivate("ahk_id " . MainGui.Hwnd)
}

; ---------------------------------------------------------------------------
; Small helpers
; ---------------------------------------------------------------------------

UsagePredictor_Join(values, delimiter := "") {
    out := ""
    for value in values
        out .= (out = "" ? "" : delimiter) . value
    return out
}

UsagePredictor_ArrayHas(values, wanted) {
    for value in values {
        if value = wanted
            return true
    }
    return false
}

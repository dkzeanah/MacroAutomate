; ═══════════════════════════════════════════════════════════════════════════════
; AutoConfig.ahk — Self-discovery & auto-configuration engine (v2, include-safe)
; ═══════════════════════════════════════════════════════════════════════════════
; Purpose: reduce explicit input by deducing the answers DeepSeek (or a user)
; would otherwise have to type. It is a *client* of a running Fan instance: it
; never touches Fan's globals or databases directly — it calls the live Fan API
; over the loopback gateway (lib\FanBridgeClient.ahk) and combines the result
; with local machine facts it can read itself.
;
; Include ONLY this file; it pulls FanBridgeClient (and FanBridgeJson) itself:
;   #Include %A_LineFile%\..\FanBridgeClient.ahk
;
; Public surface:
;   AutoConfig_Probe()                 -> Map of local machine / bridge facts
;   AutoConfig_Deduce()                -> Map of suggested settings, each tagged
;                                         with a "source" so the caller can trust
;                                         or override it.
;   AutoConfig_Report(format:="json")  -> serialized probe + deduction
;   AutoConfig_Apply(overrides:=0)     -> push the safe subset into the running
;                                         app via fan_input_settings_set
;   AutoConfig_SelfTest()              -> Map("ok", bool, "errors", [..], ...)
;
; Everything is defensive: when Fan is not running (or a tool is unavailable),
; the corresponding deduction is omitted rather than throwing.
; ═══════════════════════════════════════════════════════════════════════════════
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\FanBridgeClient.ahk

; ───────────────────────────────────────────────────────────────────────────────
; 1. Probe: facts we can read without any app-specific API.
; ───────────────────────────────────────────────────────────────────────────────
AutoConfig_Probe() {
    facts := Map(
        "machine", A_ComputerName,
        "user", A_UserName,
        "admin", A_IsAdmin ? true : false,
        "ahk_exe", A_AhkPath,
        "ahk_version", A_AhkVersion,
        "os", A_OSVersion,
        "locale", A_Language,
        "screen", Map("w", A_ScreenWidth, "h", A_ScreenHeight)
    )
    ; Monitor geometry (physical pixels; primary first).
    monitors := []
    try {
        loop MonitorGetCount() {
            MonitorGet(A_Index, &ml, &mt, &mr, &mb)
            MonitorGetWorkArea(A_Index, &wl, &wt, &wr, &wb)
            monitors.Push(Map("index", A_Index, "left", ml, "top", mt,
                "right", mr, "bottom", mb, "w", mr - ml, "h", mb - mt,
                "work", Map("l", wl, "t", wt, "r", wr, "b", wb),
                "primary", A_Index = MonitorGetPrimary()))
        }
    }
    facts["monitors"] := monitors
    facts["full_screen_region"] := "0,0," . A_ScreenWidth . "," . A_ScreenHeight

    ; Where the DeepSeek bridge expects to live and whether its config exists.
    bridgeRoot := AutoConfig_RepoRoot() . "\fan\DeepSeekBridge"
    facts["bridge_root"] := bridgeRoot
    facts["bridge_env"] := FileExist(bridgeRoot . "\.env") ? bridgeRoot . "\.env" : ""
    facts["bridge_venv_python"] := bridgeRoot . "\.venv\Scripts\python.exe"
    facts["bridge_python_ready"] := FileExist(facts["bridge_venv_python"]) != ""

    ; Provider hints (the key itself is never read or printed — presence only).
    facts["deepseek_key_in_env"] := EnvGet("DEEPSEEK_API_KEY") != ""

    ; Foreground window (so deduction can name "the app I'm in right now").
    try {
        hwnd := WinExist("A")
        facts["foreground_title"] := WinGetTitle(hwnd)
        facts["foreground_exe"] := WinGetProcessName(hwnd)
        facts["foreground_class"] := WinGetClass(hwnd)
        facts["foreground_pid"] := WinGetPID(hwnd)
    }

    return facts
}

; ───────────────────────────────────────────────────────────────────────────────
; 2. Deduce: suggested settings, each tagged with the evidence source.
; ───────────────────────────────────────────────────────────────────────────────
AutoConfig_Deduce() {
    facts := AutoConfig_Probe()
    out := Map("facts", facts, "settings", Map(), "actions", [], "notes", [])
    settings := out["settings"]
    notes := out["notes"]

    ; (a) OCR language from the OS locale (A_Language is the 4-hex-digit LCID,
    ; e.g. "0409" = en-US). Match the exact LCID; never substring-match hex.
    locale := facts["locale"]
    ocrLang := Map(
        "0409", "en-US", "0809", "en-GB", "0c09", "en-AU", "1009", "en-CA",
        "0804", "zh-Hans", "0404", "zh-Hant",
        "040c", "fr-FR", "080c", "fr-BE", "0c0c", "fr-CA",
        "0407", "de-DE", "0807", "de-CH", "0c07", "de-AT",
        "040a", "es-ES", "080a", "es-MX", "0c0a", "es-ES",
        "0410", "it-IT", "0411", "ja-JP", "0412", "ko-KR",
        "0416", "pt-BR", "0419", "ru-RU", "041d", "sv-SE", "041f", "tr-TR")
    lang := ocrLang.Has(locale) ? ocrLang[locale] : "en-US"
    settings["ocr_language"] := Map("value", lang, "source", "A_Language=" . locale)

    ; (b) Date format — a conservative, locale-neutral default.
    settings["workflow.DateFormat"] := Map("value", "MM/dd/yyyy", "source", "default")

    ; (c) Safe workflow defaults — suggested; applied only on AutoConfig_Apply().
    settings["workflow.FindTextTolerance"] := Map("value", 0.1, "source", "default")

    ; Everything below requires the running Fan app; degrade gracefully.
    caps := AutoConfig_FanCall("Capabilities")
    if IsObject(caps) {
        if caps.Has("workflow_actions")
            facts["workflow_action_count"] := caps["workflow_actions"].Length
        if caps.Has("settings") && IsObject(caps["settings"]) {
            ws := caps["settings"].Get("workflow_settings", Map())
            facts["configured_workflow_settings"] := ws.Count
            ; Don't re-suggest keys that are already set.
            for k, v in ws
                if settings.Has("workflow." . k)
                    settings.Delete("workflow." . k)
        }
        if caps.Has("coordinate_system")
            notes.Push("coordinate_system: " . caps["coordinate_system"])
    }

    ; (d) Learned, human-certified visual targets (reusable pattern names).
    patterns := AutoConfig_FanCall("Call", "fan_pattern_list", Map())
    if IsObject(patterns) {
        list := patterns.Get("patterns", patterns.Get("items", []))
        if IsObject(list) && list.Length
            facts["saved_pattern_count"] := list.Length
    }

    ; (e) Saved workflows — reusable entry points for a daily plan.
    wf := AutoConfig_FanCall("Call", "fan_workflow_list", Map("query", ""))
    if IsObject(wf) && wf.Get("ok", false) {
        names := []
        for , w in wf.Get("workflows", [])
            names.Push(w.Get("name", ""))
        facts["saved_workflows"] := names
        facts["saved_workflow_count"] := names.Length
    }

    ; (f) Learned usage evidence → prediction & discovery signals.
    ins := AutoConfig_FanCall("Insights")
    if IsObject(ins) && ins.Get("ok", false)
        facts["learning_insights_available"] := true

    tgt := AutoConfig_FanCall("DiscoveredTargets")
    if IsObject(tgt) && tgt.Get("ok", false)
        facts["discovered_target_count"] := tgt.Get("targets", []).Length

    ; (g) Taskbar index → Win+N activation targets.
    tb := AutoConfig_FanCall("Call", "fan_taskbar_list", Map("query", ""))
    if IsObject(tb) && tb.Has("ok") {
        items := tb.Get("items", tb.Get("taskbar", []))
        if IsObject(items) && items.Length
            facts["taskbar_app_count"] := items.Length
    }

    ; (h) Live perception of the foreground window (what am I looking at now?).
    live := AutoConfig_FanCall("Inspect", 0, false)
    if IsObject(live) && live.Get("ok", false)
        facts["active_window_inspected"] := true

    return out
}

; ───────────────────────────────────────────────────────────────────────────────
; 3. Report: JSON (or "text") of probe + deduction.
; ───────────────────────────────────────────────────────────────────────────────
AutoConfig_Report(format := "json") {
    d := AutoConfig_Deduce()
    if format = "text" {
        lines := ["AutoConfig report", "================"]
        for k, v in d["facts"]
            lines.Push("fact  " . k . " = " . (IsObject(v) ? "<map/array>" : v))
        for k, v in d["settings"]
            lines.Push("set   " . k . " = " . v["value"] . "   (" . v["source"] . ")")
        for , n in d["notes"]
            lines.Push("note  " . n)
        return AutoConfig_Join(lines, "`n")
    }
    return FanBridgeJsonEncode(d)
}

; ───────────────────────────────────────────────────────────────────────────────
; 4. Apply: push the safe, well-known subset into the running app.
; ───────────────────────────────────────────────────────────────────────────────
AutoConfig_Apply(overrides := 0) {
    d := AutoConfig_Deduce()
    settings := Map()
    for k, v in d["settings"]
        settings[k] := v["value"]
    if IsObject(overrides)
        for k, v in overrides
            settings[k] := v

    ; fan_input_settings_set only accepts "workflow.*" (numeric/known) keys.
    payload := Map()
    for k, v in settings
        if SubStr(k, 1, 9) = "workflow."
            payload[k] := v
    if !payload.Count
        return Map("ok", false, "error", "No workflow.* settings to apply", "suggested", settings)

    res := AutoConfig_FanCall("Call", "fan_input_settings_set", Map("settings", payload))
    return IsObject(res) ? res : Map("ok", false, "error", "Fan app not reachable")
}

; ───────────────────────────────────────────────────────────────────────────────
; 5. Self-test: probe + deduction, with a reachability check.
; ───────────────────────────────────────────────────────────────────────────────
AutoConfig_SelfTest() {
    errors := []
    facts := AutoConfig_Probe()
    if facts["ahk_exe"] = ""
        errors.Push("AutoHotkey interpreter path unknown")
    if facts["screen"]["w"] < 1 || facts["screen"]["h"] < 1
        errors.Push("screen size unavailable")
    fanOk := false
    try {
        c := AutoConfig_FanCall("Capabilities")
        fanOk := IsObject(c) && c.Has("api_version")
    }
    if !fanOk
        errors.Push("Fan app / DeepSeek Bridge not reachable (start fan\\MacroAutomator.ahk first)")
    return Map("ok", !errors.Length, "errors", errors, "fan_reachable", fanOk, "report", AutoConfig_Report())
}

; ───────────────────────────────────────────────────────────────────────────────
; Internal helpers.
; ───────────────────────────────────────────────────────────────────────────────
AutoConfig_FanCall(method, a1 := 0, a2 := 0, a3 := 0) {
    try {
        if method = "Capabilities"
            return FanBridge.Capabilities()
        if method = "Insights"
            return FanBridge.Insights()
        if method = "DiscoveredTargets"
            return FanBridge.DiscoveredTargets()
        if method = "Inspect"
            return FanBridge.Inspect(a1, a2)
        return FanBridge.Call(a1, a2)
    }
    return ""
}

AutoConfig_RepoRoot() {
    SplitPath(A_LineFile, , &dir)          ; dir = ...\lib
    return RegExReplace(dir, "\\lib$", "") ; repo root (drops trailing \lib)
}

AutoConfig_Join(arr, delim) {
    s := ""
    for , x in arr
        s .= (s = "" ? "" : delim) . x
    return s
}

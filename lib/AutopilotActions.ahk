; ═══════════════════════════════════════════════════════════════════════════════
; AutopilotActions.ahk - workflow actions for office automation with people in the loop
; ═══════════════════════════════════════════════════════════════════════════════
;   Ask Input         ask the person running the workflow for a value ($var.name)
;   Approval Gate     a person approves before an irreversible step; "No" stops
;   Type Credential   types a portal username/password from Windows Credential
;                     Manager (Fan/Portal/<name>); never stored in a workflow/log
;   Open Page         opens an http(s) page and waits for its browser window
;   Human Check       detects CAPTCHA / MFA / verification prompts and hands the
;                     screen to a person. Fan never attempts to solve them.
;   Capture Evidence  screenshot into the current run's audit trail
;
; Unattended runs (the agent API) never prompt: Ask Input needs supplied inputs,
; Approval Gate and an on-screen verification prompt stop the run.
; ═══════════════════════════════════════════════════════════════════════════════

global g_AutopilotHumanPattern := "i)(captcha|i'?m not a robot|verify (?:that )?you(?:'re| are) (?:a )?human|are you a robot|"
    . "security check|verification code|one[- ]time (?:pass(?:code|word)|code)|enter (?:the|your) (?:\d-digit )?code|"
    . "two[- ](?:factor|step)|2-step|multi[- ]factor|authenticator app|we (?:sent|texted|emailed) (?:you )?a code|"
    . "approve (?:this |the )?sign[- ]in|press and hold|select all (?:images|squares)|unusual (?:traffic|activity))"

; ─── Portal credential store (Windows Credential Manager, DPAPI-protected) ────

AutopilotCred_ValidName(name) => RegExMatch(name, "^[A-Za-z0-9][A-Za-z0-9 _.\-]{0,59}$") != 0
AutopilotCred_Target(name) => "Fan/Portal/" . name

AutopilotCred_Write(name, user, secret) {
    if !AutopilotCred_ValidName(name)
        throw ValueError("Portal name must be 1..60 letters, numbers, spaces, _ . -")
    if user = "" || secret = ""
        throw ValueError("Both the username and the password are required")
    target := AutopilotCred_Target(name)
    tgt := Buffer(StrPut(target, "UTF-16")), StrPut(target, tgt, "UTF-16")
    usr := Buffer(StrPut(user, "UTF-16")), StrPut(user, usr, "UTF-16")
    blobSize := StrLen(secret) * 2
    blob := Buffer(blobSize + 2, 0), StrPut(secret, blob, "UTF-16")
    if A_PtrSize = 8 {
        cred := Buffer(80, 0)
        NumPut("UInt", 1, cred, 4), NumPut("Ptr", tgt.Ptr, cred, 8)          ; CRED_TYPE_GENERIC, TargetName
        NumPut("UInt", blobSize, cred, 32), NumPut("Ptr", blob.Ptr, cred, 40) ; CredentialBlobSize, CredentialBlob
        NumPut("UInt", 2, cred, 48), NumPut("Ptr", usr.Ptr, cred, 72)         ; CRED_PERSIST_LOCAL_MACHINE, UserName
    } else {
        cred := Buffer(52, 0)
        NumPut("UInt", 1, cred, 4), NumPut("Ptr", tgt.Ptr, cred, 8)
        NumPut("UInt", blobSize, cred, 24), NumPut("Ptr", blob.Ptr, cred, 28)
        NumPut("UInt", 2, cred, 32), NumPut("Ptr", usr.Ptr, cred, 48)
    }
    ok := DllCall("Advapi32\CredWriteW", "Ptr", cred.Ptr, "UInt", 0, "Int")
    DllCall("RtlZeroMemory", "Ptr", blob.Ptr, "UPtr", blob.Size)
    return ok != 0
}

; Map("user", ..., "secret", ...) or an empty Map. Callers must not keep or log it.
AutopilotCred_Read(name, withSecret := true) {
    out := Map()
    if !AutopilotCred_ValidName(name)
        return out
    pCred := 0
    if !DllCall("Advapi32\CredReadW", "Str", AutopilotCred_Target(name), "UInt", 1, "UInt", 0, "Ptr*", &pCred, "Int")
        return out
    try {
        sizeOffset := A_PtrSize = 8 ? 32 : 24, blobOffset := A_PtrSize = 8 ? 40 : 28, userOffset := A_PtrSize = 8 ? 72 : 48
        size := NumGet(pCred, sizeOffset, "UInt"), blobPtr := NumGet(pCred, blobOffset, "Ptr"), userPtr := NumGet(pCred, userOffset, "Ptr")
        out["user"] := userPtr ? StrGet(userPtr, "UTF-16") : ""
        if withSecret
            out["secret"] := size && blobPtr ? StrGet(blobPtr, size // 2, "UTF-16") : ""
    } finally DllCall("Advapi32\CredFree", "Ptr", pCred)
    return out
}

AutopilotCred_Exists(name) {
    if !AutopilotCred_ValidName(name)
        return false
    pCred := 0
    if !DllCall("Advapi32\CredReadW", "Str", AutopilotCred_Target(name), "UInt", 1, "UInt", 0, "Ptr*", &pCred, "Int")
        return false
    DllCall("Advapi32\CredFree", "Ptr", pCred)
    return true
}

AutopilotCred_User(name) {
    cred := AutopilotCred_Read(name, false)
    return cred.Count ? cred["user"] : ""
}

AutopilotCred_Delete(name) {
    if !AutopilotCred_ValidName(name)
        return false
    return DllCall("Advapi32\CredDeleteW", "Str", AutopilotCred_Target(name), "UInt", 1, "UInt", 0, "Int") != 0
}

; ─── Shared helpers ─────────────────────────────────────────────────────────────

Autopilot_Interactive() {
    global g_WorkflowExecutionOptions
    return !(g_WorkflowExecutionOptions is Map) || g_WorkflowExecutionOptions.Get("interactive", true)
}

Autopilot_Fail(message) {
    global g_LastActionError
    g_LastActionError := message
    ShowStatus(message, "fail")
    return false
}

Autopilot_Now() => FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")

; Audible cue when a person is needed (approval, verification).
Autopilot_Beep(frequency, ms) {
    try SoundBeep(frequency, ms)
}

; Second-level domain, used as the expected browser title fragment.
Autopilot_HostHint(url) {
    if !RegExMatch(url, "i)^https?://([^/:?#]+)", &m)
        return ""
    keep := []
    for , part in StrSplit(StrLower(m[1]), ".")
        if !RegExMatch(part, "^(www|login|secure|portal|my|app|auth|signin)$")
            keep.Push(part)
    return keep.Length >= 2 ? keep[keep.Length - 1] : keep.Length ? keep[1] : ""
}

Autopilot_IsBrowserExe(exe) => RegExMatch(StrLower(exe), "^(chrome|msedge|firefox|brave|opera|vivaldi|iexplore)\.exe$") != 0

Autopilot_FindBrowserWindow(text) {
    for hwnd in WinGetList() {
        exe := "", title := ""
        try exe := WinGetProcessName("ahk_id " . hwnd)
        try title := WinGetTitle("ahk_id " . hwnd)
        if title = "" || !Autopilot_IsBrowserExe(exe)
            continue
        if text = "" || InStr(title, text)
            return hwnd
    }
    return 0
}

Autopilot_RegexLiteral(text) => RegExReplace(text, "[\\.^$*+?()\[\]{}|]", "\$0")

; Capture a screen rectangle (Map x1,y1,x2,y2) to a PNG. Returns true on success.
Autopilot_CaptureRegion(region, path) {
    if !IsObject(region)
        return false
    w := region["x2"] - region["x1"], h := region["y2"] - region["y1"]
    if w < 4 || h < 4
        return false
    pBitmap := Gdip_BitmapFromScreen(region["x1"] . "|" . region["y1"] . "|" . w . "|" . h)
    if !pBitmap
        return false
    try return Gdip_SaveBitmapToFile(pBitmap, path) = 0 && FileExist(path) != ""
    finally Gdip_DisposeImage(pBitmap)
}

; ─── Actions ────────────────────────────────────────────────────────────────────

; Target = variable name. Param = "question[; default=...; mask=1]".
ExecuteAskInput(target, param) {
    global g_WorkflowVariables, g_SpoolVariables, g_WorkflowExecutionOptions, g_AbortSequence
    varName := NormalizeWorkflowVariableName(target)
    if varName = ""
        return Autopilot_Fail("Ask Input needs a variable name (letters, numbers, _)")
    prompt := Trim(param), options := Map()
    if at := InStr(param, ";") {
        prompt := Trim(SubStr(param, 1, at - 1))
        options := ParseLoopOptions(SubStr(param, at + 1))
    }
    if prompt = ""
        prompt := "Value for " . varName
    supplied := g_WorkflowExecutionOptions is Map ? g_WorkflowExecutionOptions.Get("inputs", 0) : 0
    if supplied is Map && supplied.Has(varName) {
        value := String(supplied[varName])
    } else if !Autopilot_Interactive() {
        return Autopilot_Fail("Ask Input '" . varName . "' needs a value; unattended runs must supply it in inputs")
    } else {
        prior := ""
        TryGetWorkflowVariable(varName, &prior)
        default := LoopOptStr(options, "default", prior)
        mask := LoopOptStr(options, "mask", "0") = "1"
        reply := InputBox(prompt, "Fan · workflow input", "w460 h150" . (mask ? " Password" : ""), default)
        if reply.Result != "OK" {
            g_AbortSequence := true
            return Autopilot_Fail("Stopped: no value was given for " . varName)
        }
        value := reply.Value
        if mask
            StudyConsole_Secret(value)
    }
    g_WorkflowVariables[varName] := value
    g_SpoolVariables[varName] := value
    ShowStatus("Input stored as $var." . varName, "ok")
    return true
}

ExecuteApprovalGate(param) {
    global g_AbortSequence
    message := Trim(param) != "" ? Trim(param) : "Continue with the next step?"
    if !Autopilot_Interactive()
        return Autopilot_Fail("A person must approve this step: " . message)
    try Autopilot_EvidenceCapture("window:A", "Before approval", false)
    Autopilot_Beep(660, 90)
    answer := MsgBoxTop(message . "`n`nWorkflow: " . SelfHeal_WorkflowName()
        . "`n`nYes = approve and continue`nNo = stop the workflow here", "Fan · approval needed", "YesNo Icon? Default2")
    decision := answer = "Yes" ? "approved" : "declined"
    try Autopilot_RunNote("approval", Map("decision", decision, "by", A_UserName, "at", Autopilot_Now(), "message", message))
    if decision = "approved" {
        ShowStatus("Approved: " . message, "ok")
        return true
    }
    g_AbortSequence := true
    return Autopilot_Fail("Declined at approval gate: " . message)
}

; Target = saved portal name, Param = username | password.
ExecuteTypeCredential(target, param) {
    global g_Settings
    name := Trim(target), field := StrLower(Trim(param))
    if !AutopilotCred_ValidName(name)
        return Autopilot_Fail("Type Credential needs a saved portal name")
    if field != "username" && field != "password"
        return Autopilot_Fail("Type Credential field must be username or password")
    hwnd := WinExist("A")
    if !hwnd
        return Autopilot_Fail("No active window to type the " . field . " into")
    if WinGetPID("ahk_id " . hwnd) = DllCall("GetCurrentProcessId", "UInt")
        return Autopilot_Fail("Not typing the " . field . " into Fan itself; activate the portal first")
    title := WinGetTitle("ahk_id " . hwnd)
    hint := Autopilot_PortalHint(name)
    if hint != "" && !InStr(title, hint)
        return Autopilot_Fail("Not typing the " . field . ": the active window does not look like " . name
            . " (expected '" . hint . "' in its title)")
    cred := AutopilotCred_Read(name)
    if !cred.Count
        return Autopilot_Fail("No saved credential for '" . name . "'. Add it under Autopilot > Portals.")
    value := field = "username" ? cred["user"] : cred["secret"]
    cred := ""
    if value = ""
        return Autopilot_Fail("The saved " . field . " for '" . name . "' is empty")
    if field = "password"
        StudyConsole_Secret(value)  ; redact it from every Fan log from now on
    DeepActivity_Before("text_type")
    Sleep(g_Settings["PreActionDelay"])
    SendText(value)
    value := ""
    Sleep(g_Settings["PostActionDelay"])
    ShowStatus("Typed the saved " . field . " for " . name, "ok")
    return true
}

; Param = "url=https://...; browser=chrome|edge|firefox|default; wait=title text; timeout=ms" or a bare URL.
ExecuteOpenPage(param) {
    global g_AbortSequence
    options := InStr(param, "=") && !RegExMatch(Trim(param), "i)^https?://") ? ParseLoopOptions(param) : Map("url", Trim(param))
    url := LoopOptStr(options, "url", "")
    if !RegExMatch(url, "i)^https?://[^\s`"'<>^|]+$")
        return Autopilot_Fail("Open Page needs url=https://... without spaces or quotes")
    browser := StrLower(LoopOptStr(options, "browser", "default"))
    programs := Map("chrome", "chrome.exe", "edge", "msedge.exe", "firefox", "firefox.exe")
    waitText := LoopOptStr(options, "wait", "")
    timeout := Max(1000, Min(120000, LoopOptInt(options, "timeout", 20000)))
    before := WinExist("A"), beforeTitle := ""
    try beforeTitle := WinGetTitle("ahk_id " . before)
    DeepActivity_Set(true, "Opening " . url, 10000)
    try {
        if programs.Has(browser)
            Run(programs[browser] . ' "' . url . '"')
        else
            Run(url)
    } catch as err
        return Autopilot_Fail("Could not open the page: " . err.Message)
    deadline := A_TickCount + timeout, changed := 0
    while A_TickCount < deadline {
        if g_AbortSequence
            return false
        if waitText != "" {
            if hwnd := Autopilot_FindBrowserWindow(waitText) {
                try WinActivate("ahk_id " . hwnd)
                Sleep(250)
                ShowStatus("Page open: " . WinGetTitle("ahk_id " . hwnd), "ok")
                return true
            }
        }
        active := WinExist("A"), activeTitle := "", exe := ""
        try activeTitle := WinGetTitle("ahk_id " . active)
        try exe := WinGetProcessName("ahk_id " . active)
        if Autopilot_IsBrowserExe(exe) && (active != before || activeTitle != beforeTitle)
            changed := active
        if waitText = "" && changed {
            Sleep(400)
            ShowStatus("Page open: " . activeTitle, "ok")
            return true
        }
        Sleep(250)
    }
    if changed {
        ; The browser responded, but its title never mentioned the expected text.
        ; Credential steps still refuse to type unless their own window check passes.
        ShowStatus("Page opened; its title did not mention '" . waitText . "'", "info")
        return true
    }
    return Autopilot_Fail("No browser window" . (waitText != "" ? " titled '" . waitText . "'" : "")
        . " appeared within " . Round(timeout / 1000) . "s")
}

; Target = area (default window:A). Param = "on=pause|stop; words=extra|phrases".
ExecuteHumanCheck(target, param) {
    global g_AbortSequence
    options := ParseLoopOptions(param)
    onFound := StrLower(LoopOptStr(options, "on", "pause"))
    area := Trim(target) != "" ? Trim(target) : "window:A"
    attempts := 0
    loop {
        found := Autopilot_DetectHumanStep(area, LoopOptStr(options, "words", ""))
        if found = "" {
            if attempts
                try Autopilot_RunNote("human", Map("by", A_UserName, "at", Autopilot_Now(), "detail", "verification completed by a person"))
            ShowStatus(attempts ? "Verification completed - continuing" : "No verification prompt on screen", "ok")
            return true
        }
        if onFound = "stop" || !Autopilot_Interactive()
            return Autopilot_Fail("A person must complete this verification ('" . found . "'). Fan never solves CAPTCHA or MFA prompts.")
        if ++attempts > 3
            return Autopilot_Fail("The verification prompt is still on screen ('" . found . "')")
        Autopilot_Beep(880, 120)
        answer := MsgBoxTop("The page is asking for human verification:`n`n    " . found
            . "`n`nComplete it yourself in the browser, then click OK to continue.`nClick Cancel to stop the workflow.",
            "Fan · your turn", "OKCancel Icon!")
        if answer != "OK" {
            g_AbortSequence := true
            return Autopilot_Fail("Stopped at a verification prompt")
        }
        if !WorkflowExecution_Wait(800)
            return false
    }
}

; The matched phrase, or "" when no verification prompt is visible.
Autopilot_DetectHumanStep(area, extraWords := "") {
    global g_AutopilotHumanPattern
    region := ParseRegionCoords(area)
    if !region || !IsOCRAvailable()
        return ""
    text := ""
    try text := OCR.FromRect(region["x1"], region["y1"], region["x2"] - region["x1"], region["y2"] - region["y1"], WorkflowOCR_Options()).Text
    pattern := g_AutopilotHumanPattern
    if Trim(extraWords) != "" {
        words := []
        for , word in StrSplit(extraWords, "|")
            if Trim(word) != ""
                words.Push(Autopilot_RegexLiteral(Trim(word)))
        if words.Length
            pattern := SubStr(pattern, 1, -1) . "|" . StrJoin(words, "|") . ")"
    }
    return RegExMatch(text, pattern, &m) ? m[0] : ""
}

ExecuteCaptureEvidence(target, param) {
    file := Autopilot_EvidenceCapture(Trim(target) != "" ? Trim(target) : "window:A", Trim(param) != "" ? Trim(param) : "Screenshot")
    if file = ""
        return Autopilot_Fail("Could not capture the screenshot (is the area on screen?)")
    ShowStatus("Evidence saved: " . file, "ok")
    return true
}

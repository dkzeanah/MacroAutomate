#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, OutputDebug
SetWorkingDir A_ScriptDir

/* 
[Prompt and desired functionality]

Write an auto hot key version, 2 script that can detect all key presses and combination of key presses. And all mouse movement and combination of mouse movements to determine bursts of sequences of actions and separates them by a large drop off in the frequency of
No input, meaning no credible input at the level of frequency that relates to what the burst was.

In essence, I want to perform certain tasks on my computer that involves manual input of both forms, and I want to time those chains to determine how long each process is taking me to do manually. But I want this to be auto discoverable in an intelligent way where I don't have to click a button every time I want to time.It or whatever I want it to automatically determine when the sequence starts a new one, and when the sequence ends based on the timing et cetera.


So in full, I want to walk into my workplace office and run this script on a computer.And then be able to determine out of every process that I need to do computationally, how long each one takes on an average case.

I want to identify the longest chains of action. I also want to identify ones that have a wide variance from time to time.Based on, for example, a failure point being reached in one of the chains.

Eventually, for every action or process possible in the office, I want to have an absolute minimum.Amount of clicks, mouse movements and relative app navigation via that user input.

So basically everything to find out to AT including mouse movement in inches etc.

I then want to learn machine learning type of objects or mechanisms to analyze this data, and eventually be able to simulate
Every action based on what's needed and at what time, which is always dynamic and is and can be interrupted by another process et cetera like customer service requests, boss requests, etc

Remember I want to capture this data in full thoroughness, but also provide a smart analytic engine and also a clean interface for being able to deduce actionable information from said information.

Ideally, a process would consist of the minimum actions required, and for instance, the shortest most direct mouth paths available to achieve doing so, such as the direction and amount of movement from point to point, the transfer time from mouse to hand points et cetera. Like any metric that's possibly can be gained.I want for each process, so think deep about what that looks like in terms of mouse.And keyboard inputs being used to handle a web app clunky u I interface manually et cetera

The code should work to intelligently identify things and categorize them after the fact of them, having been done or self deducing or self categorizing.

Think of it like a camera that is caching.The previous three seconds and gets added to the snapshot information only once the snapshot has been made, if that makes sense, but in a code form, I mean, it just as an analogy.But you get what i'm saying.
 */


; ADD-ON: BURST RECORDER (keyboard + mouse, automatic burst segmentation, analytics + UI)
; Paste this WHOLE section at the VERY END of your script (below RichEditHighlighter class).
; Does NOT modify your existing “core” code above—runs alongside it.
; Hotkeys:
;   F9  = Toggle Recording (on/off)
;   F10 = Show/Hide Recorder UI
;   F11 = Export JSONL + CSV summaries to /logs
; ======================================================================================================================

; ----------------------------------------------------------------------------------------------------------------------
; JSON helpers (compact, no external libs)
; ----------------------------------------------------------------------------------------------------------------------


; ======================================================================================================================
; AHK v2 "DO NOT GET THIS WRONG" QUICK REF (dense + correct)
; - v2 uses FUNCTIONS (MsgBox(), Send(), WinExist()) not legacy commands (MsgBox, Send, IfWinExist, etc.)

; - Assignment is := (and = is mostly for legacy text/INI contexts). Strings use "..."

; - Objects:
;   - Array: []         -> ordered list
;   - Map(): Map()      -> hash map, keys can be ANY type
;   - Plain object: {}  -> property bag (string keys); o.Foo := 123; o.%name% dynamic access

; - Functions are values (closures): f := (x) => x*2 ; SetTimer(() => ..., 250)

; - Methods are first-class via Bind():  btn.OnEvent("Click", ObjBindMethod(this,"Method"))

; - Errors are objects: try/catch as err, throw Error("msg")

; - No v1 command-style "If x = y" / "MsgBox, hi" in v2 scripts.
; ======================================================================================================================

; The Object prototype class has a method that allows us to define properties in objects
; By default, the String class lacks this method.
; We can copy the method from the Object Prototype into the String Prototype
String.Prototype.DefineProp := Object.Prototype.DefineProp

; Using the new DefineProp method, we can now define properties in the String class
; This means ALL strings will get access to these properties
; This will allow us to give strings a "length" property
; When the length property is used, it will call the StrLen function
; The string itself is passed in automatically as the first paramater to the StrLen
String.Prototype.DefineProp('length', {get: StrLen})

; Testing the new length property
; Make a string
greetings := 'Hello, world!'

; Does it work?
MsgBox('String contains:`n' greetings
    '`n`nString char count:`n' greetings.length)


/**
 * @description Extracts the full prototype chain of any given item
 * @param item - Any item you want to get the full prototype chain from.  
 * This is also known as an inheritance chain.  
 * @returns {String} The object's full prototype chain.
 */

get_prototype_chain(item) {
    chain := ''                                 ; String to return with full prototype chain
    loop                                        ; Loop through the item
        item := item.Base                       ;   Update the current item to the class it came from
        ,chain := item.__Class ' > ' chain      ;   Add the next class to the start of the chain
    Until item.__Class = 'Any'                  ; Stop looping when the Any class is reached
    Return SubStr(chain, 1, -3)                 ; Trim the extra ' > ' separator from the end of the string
}

    ; Give it a gui control
goo := Gui()
con := goo.AddButton(, 'Exit')

; Any > Object > Gui.Control > Gui.Button
MsgBox(get_prototype_chain(con))

; What about a string?
str := 'AutoHotkey v2!'

; Outputs: Any > Primitive > String
; While the string is a primitive, using it in this context its an object
; All the string properties and methods derive from the String class
; But the string itself is a basic, primitive data type in memory
MsgBox(get_prototype_chain(str))


WordList := "Monday`nTuesday`nWednesday`nThursday`nFriday`nSaturday`nSunday"

Suffix := ""

SacHook := InputHook("V", "{Esc}")
SacHook.OnChar := SacChar
SacHook.OnKeyDown := SacKeyDown
SacHook.KeyOpt("{Backspace}", "N")
SacHook.Start()


global BurstApp := BurstRecorderApp()
global App := CoreDemoApp()

F1::App.RunAll()
F2::App.ToggleTimer()
Esc::ExitApp
F9::BurstApp.ToggleRecording()
F10::BurstApp.ToggleUi()
F11::BurstApp.Export()


JsonStr(s) {
    s := "" s
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return '"' s '"'
}

EventToJson(ev) {
    ; whitelist minimal fields for ML pipelines
    j := "{"
    j .= '"ts":' ev["ts"]
    j .= ',"kind":' JsonStr(ev["kind"])
    if ev.Has("keyName")
        j .= ',"keyName":' JsonStr(ev["keyName"])
    if ev.Has("vk")
        j .= ',"vk":' ev["vk"]
    if ev.Has("sc")
        j .= ',"sc":' ev["sc"]
    if ev.Has("chord")
        j .= ',"chord":' JsonStr(ev["chord"])
    if ev.Has("x")
        j .= ',"x":' ev["x"]
    if ev.Has("y")
        j .= ',"y":' ev["y"]
    if ev.Has("button")
        j .= ',"button":' JsonStr(ev["button"])
    if ev.Has("wheelDelta")
        j .= ',"wheelDelta":' ev["wheelDelta"]
    if ev.Has("distPx")
        j .= ',"distPx":' Round(ev["distPx"], 4)
    if ev.Has("winExe")
        j .= ',"winExe":' JsonStr(ev["winExe"])
    if ev.Has("winTitle")
        j .= ',"winTitle":' JsonStr(ev["winTitle"])
    if ev.Has("preroll")
        j .= ',"preroll":' (ev["preroll"] ? "true" : "false")
    return j "}"
}

; ----------------------------------------------------------------------------------------------------------------------
; Range helper for loops (safe, no dependency on your existing Range class)
; ----------------------------------------------------------------------------------------------------------------------
RangeInt(a, b) {
    r := []
    i := a
    while (i <= b) {
        r.Push(i)
        i += 1
    }
    return r
}

SacChar(ih, char)  ; Called when a character is added to SacHook.Input.
{
    global Suffix := ""
    if RegExMatch(ih.Input, "`nm)\w+$", &prefix)
        && RegExMatch(WordList, "`nmi)^" prefix[0] "\K.*", &Suffix)
        Suffix := Suffix[0]
    
    if CaretGetPos(&cx, &cy)
        ToolTip Suffix, cx + 15, cy
    else
        ToolTip Suffix

    ; Intercept Tab only while we're showing a tooltip.
    ih.KeyOpt("{Tab}", Suffix = "" ? "-NS" : "+NS")
}

SacKeyDown(ih, vk, sc)
{
    if (vk = 8) ; Backspace
        SacChar(ih, "")
    else if (vk = 9) ; Tab
        Send "{Text}" Suffix
}

class BurstRecorderApp {
    __New() {
        this.cfg := Map(
            "recording", true,
            "preRollMs", 3000,
            "idleMinMs", 1200,
            "idleFactor", 6.0,
            "mouseMoveSampleMs", 12,
            "mouseMoveMinPx", 1,
            "flushMs", 40,
            "idleCheckMs", 200,
            "logDir", A_ScriptDir "\logs",

            ; --- fuzzy clustering ---
            "clusterThreshold", 0.58,         ; 0..1, higher = stricter
            "clusterExeWeight", 0.18,         ; bonus weight for matching windowExe
            "clusterTokenMinFrac", 0.35,      ; token must appear in >= frac of bursts in cluster to be a "core token"
            "clusterMaxCoreTokens", 28
        )

        DirCreate(this.cfg["logDir"])

        this._startTick := A_TickCount
        this._pressed := Map()
        this._ring := EventRingBuffer(6000)
        this._bursts := []
        this._active := 0
        this._nextBurstId := 1

        this._queue := []
        this._queueLock := false

        this._patternStats := Map()
        this._clusters := ClusterEngine(
            this.cfg["clusterThreshold"],
            this.cfg["clusterExeWeight"],
            this.cfg["clusterTokenMinFrac"],
            this.cfg["clusterMaxCoreTokens"]
        )

        this._hook := LowLevelHookMgr(
            ObjBindMethod(this, "_EnqueueEvent"),
            this.cfg["mouseMoveSampleMs"],
            this.cfg["mouseMoveMinPx"]
        )
        this._hook.Start()

        this._flushTimer := ObjBindMethod(this, "_FlushQueue")
        this._idleTimer := ObjBindMethod(this, "_IdleCheck")

        SetTimer(this._flushTimer, this.cfg["flushMs"])
        SetTimer(this._idleTimer, this.cfg["idleCheckMs"])

        OnExit(ObjBindMethod(this, "_OnExit"))

        this._BuildUi()
        this._UpdateUiStatus()
    }

    _OnExit(*) {
        try SetTimer(this._flushTimer, 0)
        try SetTimer(this._idleTimer, 0)
        try this._hook.Stop()
        try this._WriteSessionSummary()
    }

    ToggleRecording() {
        this.cfg["recording"] := !this.cfg["recording"]
        if (!this.cfg["recording"] && this._active)
            this._CloseActive("recording_off")
        this._UpdateUiStatus()
    }

    ToggleUi() {
        if this.gui.Visible
            this.gui.Hide()
        else
            this.gui.Show()
    }

    Export() {
        this._WriteSessionSummary(true)
        this._Toast("Exported", "Wrote logs to:`n" this.cfg["logDir"])
    }

    ; ------------------------- UI -------------------------

    _BuildUi() {
        this.gui := Gui("+Resize +MinSize980x600", "Burst Recorder (Auto-segmented processes)")
        this.gui.SetFont("s9", "Consolas")

        this.tabs := this.gui.Add("Tab3", "xm ym w940 h560", ["Live", "Bursts", "Stats", "Clusters", "Settings"])

        ; ---- Live ----
        this.tabs.UseTab(1)
        this.liveStatus := this.gui.Add("Text", "xm ym+30 w940 h20", "")
        this.liveMetrics := this.gui.Add("Edit", "xm y+8 w940 h480 -Wrap ReadOnly", "")

        ; ---- Bursts ----
        this.tabs.UseTab(2)
        this.burstLV := this.gui.Add("ListView", "xm ym+30 w940 h360 Grid -Multi", ["#", "Start", "Dur(ms)", "Window", "Keys", "Clicks", "Wheel", "Move(in)", "Signature", "Cluster"])
        this.burstLV.ModifyCol(1, 40)
        this.burstLV.ModifyCol(2, 120)
        this.burstLV.ModifyCol(3, 70)
        this.burstLV.ModifyCol(4, 200)
        this.burstLV.ModifyCol(5, 55)
        this.burstLV.ModifyCol(6, 55)
        this.burstLV.ModifyCol(7, 55)
        this.burstLV.ModifyCol(8, 70)
        this.burstLV.ModifyCol(9, 200)
        this.burstLV.ModifyCol(10, 60)
        this.burstLV.OnEvent("ItemSelect", ObjBindMethod(this, "_OnBurstSelect"))

        this.burstDetail := this.gui.Add("Edit", "xm y+8 w940 h120 -Wrap ReadOnly", "")

        ; ---- Stats (exact signature grouping) ----
        this.tabs.UseTab(3)
        this.statLV := this.gui.Add("ListView", "xm ym+30 w940 h420 Grid -Multi", ["Signature", "Count", "Avg(ms)", "Std(ms)", "Min(ms)", "Max(ms)", "AvgKeys", "AvgClicks", "AvgMove(in)", "Window (most common)"])
        this.statLV.ModifyCol(1, 280)
        this.statLV.ModifyCol(2, 60)
        this.statLV.ModifyCol(3, 80)
        this.statLV.ModifyCol(4, 80)
        this.statLV.ModifyCol(5, 80)
        this.statLV.ModifyCol(6, 80)
        this.statLV.ModifyCol(7, 80)
        this.statLV.ModifyCol(8, 80)
        this.statLV.ModifyCol(9, 90)
        this.statLV.ModifyCol(10, 220)

        this.btnRecalc := this.gui.Add("Button", "xm y+8 w140", "Recalc Stats")
        this.btnRecalc.OnEvent("Click", (*) => this._RecalcStats(true))

        ; ---- Clusters (fuzzy grouping) ----
        this.tabs.UseTab(4)
        this.clusterStatus := this.gui.Add("Text", "xm ym+30 w940 h20", "")
        this.clusterLV := this.gui.Add("ListView", "xm y+8 w940 h340 Grid -Multi", ["Cluster", "Count", "Avg(ms)", "Std(ms)", "Min", "Max", "AvgKeys", "AvgClicks", "AvgMove(in)", "Window (most common)", "Core Tokens"])
        this.clusterLV.ModifyCol(1, 60)
        this.clusterLV.ModifyCol(2, 60)
        this.clusterLV.ModifyCol(3, 80)
        this.clusterLV.ModifyCol(4, 80)
        this.clusterLV.ModifyCol(5, 70)
        this.clusterLV.ModifyCol(6, 70)
        this.clusterLV.ModifyCol(7, 80)
        this.clusterLV.ModifyCol(8, 80)
        this.clusterLV.ModifyCol(9, 90)
        this.clusterLV.ModifyCol(10, 230)
        this.clusterLV.ModifyCol(11, 250)
        this.clusterLV.OnEvent("ItemSelect", ObjBindMethod(this, "_OnClusterSelect"))

        this.clusterDetail := this.gui.Add("Edit", "xm y+8 w940 h120 -Wrap ReadOnly", "")

        this.btnRecluster := this.gui.Add("Button", "xm y+8 w140", "Recluster All")
        this.btnRecluster.OnEvent("Click", (*) => this._ReclusterAll())

        ; ---- Settings ----
        this.tabs.UseTab(5)
        this.gui.Add("Text", "xm ym+30 w360", "Recording:")
        this.chkRec := this.gui.Add("Checkbox", "x+10 yp-2 w200", "Enabled")
        this.chkRec.Value := this.cfg["recording"]
        this.chkRec.OnEvent("Click", (*) => (this.cfg["recording"] := !!this.chkRec.Value, this._UpdateUiStatus()))

        this.gui.Add("Text", "xm y+14 w360", "Pre-roll ms (events added before burst start):")
        this.edPre := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["preRollMs"])
        this.gui.Add("Text", "xm y+14 w360", "Idle minimum ms (minimum gap closes burst):")
        this.edIdleMin := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["idleMinMs"])
        this.gui.Add("Text", "xm y+14 w360", "Idle factor (avg gap × factor):")
        this.edIdleFactor := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["idleFactor"])
        this.gui.Add("Text", "xm y+14 w360", "Mouse move throttle (ms):")
        this.edMoveMs := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["mouseMoveSampleMs"])
        this.gui.Add("Text", "xm y+14 w360", "Mouse move min px:")
        this.edMovePx := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["mouseMoveMinPx"])

        this.gui.Add("Text", "xm y+18 w360", "Cluster threshold (0..1):")
        this.edClustTh := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["clusterThreshold"])
        this.gui.Add("Text", "xm y+14 w360", "Cluster exe weight (0..1):")
        this.edClustExeW := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["clusterExeWeight"])
        this.gui.Add("Text", "xm y+14 w360", "Core token min fraction (0..1):")
        this.edClustFrac := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["clusterTokenMinFrac"])

        this.btnApply := this.gui.Add("Button", "xm y+18 w140", "Apply Settings")
        this.btnApply.OnEvent("Click", ObjBindMethod(this, "_ApplySettings"))

        this.btnClear := this.gui.Add("Button", "x+10 yp w140", "Clear Session")
        this.btnClear.OnEvent("Click", (*) => this._ClearSession())

        this.btnExport := this.gui.Add("Button", "x+10 yp w140", "Export (F11)")
        this.btnExport.OnEvent("Click", (*) => this.Export())

        this.tabs.UseTab()

        this.gui.OnEvent("Size", ObjBindMethod(this, "_OnSize"))
        this.gui.OnEvent("Close", (*) => this.gui.Hide())

        this.gui.Show("w1020 h650")
        this._OnSize(this.gui, 0, 1020, 650)
    }

    _OnSize(guiObj, minMax, w, h) {
        pad := 12
        tabW := Max(600, w - pad*2)
        tabH := Max(320, h - pad*2)
        this.tabs.Move(pad, pad, tabW, tabH)

        cx := pad + 10
        cy := pad + 40
        cw := tabW - 20
        ch := tabH - 60

        ; Live
        this.liveStatus.Move(cx, cy - 22, cw, 20)
        this.liveMetrics.Move(cx, cy, cw, ch)

        ; Bursts
        burstTopH := Max(170, Floor(ch * 0.68))
        this.burstLV.Move(cx, cy - 6, cw, burstTopH)
        this.burstDetail.Move(cx, cy + burstTopH + 6, cw, Max(120, ch - burstTopH - 6))

        ; Stats
        this.statLV.Move(cx, cy - 6, cw, Max(220, ch - 40))
        this.btnRecalc.Move(cx, cy + Max(220, ch - 40) + 8)

        ; Clusters
        this.clusterStatus.Move(cx, cy - 22, cw, 20)
        clTopH := Max(170, Floor(ch * 0.62))
        this.clusterLV.Move(cx, cy, cw, clTopH)
        this.clusterDetail.Move(cx, cy + clTopH + 6, cw, Max(120, ch - clTopH - 44))
        this.btnRecluster.Move(cx, cy + clTopH + 6 + Max(120, ch - clTopH - 44) + 8)
    }

    _ApplySettings(*) {
        this.cfg["preRollMs"] := Integer(this.edPre.Value)
        this.cfg["idleMinMs"] := Integer(this.edIdleMin.Value)
        this.cfg["idleFactor"] := this._ToFloat(this.edIdleFactor.Value, this.cfg["idleFactor"])
        this.cfg["mouseMoveSampleMs"] := Integer(this.edMoveMs.Value)
        this.cfg["mouseMoveMinPx"] := Integer(this.edMovePx.Value)

        this.cfg["clusterThreshold"] := this._ToFloat(this.edClustTh.Value, this.cfg["clusterThreshold"])
        this.cfg["clusterExeWeight"] := this._ToFloat(this.edClustExeW.Value, this.cfg["clusterExeWeight"])
        this.cfg["clusterTokenMinFrac"] := this._ToFloat(this.edClustFrac.Value, this.cfg["clusterTokenMinFrac"])

        this._hook.SetMouseThrottle(this.cfg["mouseMoveSampleMs"], this.cfg["mouseMoveMinPx"])

        ; update cluster engine config + re-run clustering
        this._clusters.SetConfig(
            this.cfg["clusterThreshold"],
            this.cfg["clusterExeWeight"],
            this.cfg["clusterTokenMinFrac"],
            this.cfg["clusterMaxCoreTokens"]
        )
        this._ReclusterAll()

        this._UpdateUiStatus()
        this._Toast("Settings", "Applied.")
    }

    _ClearSession() {
        if this._active
            this._CloseActive("clear_session")

        this._bursts := []
        this._patternStats := Map()
        this._clusters.Clear()
        this._ring.Clear()
        this._pressed := Map()
        this._nextBurstId := 1

        this._RefreshBurstLV()
        this._RecalcStats(true)
        this._RefreshClusterLV()
        this._UpdateLive()
        this._UpdateUiStatus()
        this._Toast("Session", "Cleared.")
    }

    _UpdateUiStatus() {
        rec := this.cfg["recording"] ? "ON" : "OFF"
        this.liveStatus.Text := "Recording: " rec "    Bursts: " this._bursts.Length "    Active: " (this._active ? "YES" : "NO") "    Hotkeys: F9 toggle | F10 UI | F11 export"
        try this.chkRec.Value := this.cfg["recording"]
        this._UpdateLive()
        this._UpdateClusterStatus()
    }

    _UpdateClusterStatus() {
        this.clusterStatus.Text := "Clusters: " this._clusters.Count() "    Threshold: " this.cfg["clusterThreshold"] "    ExeWeight: " this.cfg["clusterExeWeight"] "    CoreFrac: " this.cfg["clusterTokenMinFrac"]
    }

    _UpdateLive() {
        b := this._active
        if !b {
            this.liveMetrics.Value :=
                "No active burst.`r`n`r`n" .
                "Recording: " (this.cfg["recording"] ? "ON" : "OFF") "`r`n" .
                "Bursts recorded: " this._bursts.Length "`r`n" .
                "Clusters: " this._clusters.Count() "`r`n`r`n" .
                "Tip: work normally. A burst starts on first input after idle and auto-ends after idle gap."
            return
        }

        this.liveMetrics.Value :=
            "ACTIVE BURST #" b.id "`r`n" .
            "Start: " b.startWall "`r`n" .
            "Duration(ms): " b.DurationMs() "`r`n" .
            "Window: " b.windowExe " | " b.windowTitle "`r`n" .
            "Keys: " b.keyCount "   Clicks: " b.clickCount "   Wheel: " b.wheelCount "`r`n" .
            "Mouse move: " Round(b.moveIn, 3) " in  (" Round(b.movePx) " px)" "`r`n" .
            "Signature: " b.signature "`r`n" .
            "Cluster: " (b.clusterId ? b.clusterId : "-") "`r`n`r`n" .
            "Last event: " b.lastKind "  " b.lastDetail "`r`n"
    }

    _OnBurstSelect(lv, item, selected) {
        if (!selected)
            return
        row := lv.GetNext(0, "F")
        if (!row)
            return
        id := Integer(lv.GetText(row, 1))
        b := this._FindBurstById(id)
        if !b
            return
        this.burstDetail.Value := b.Describe()
    }

    _OnClusterSelect(lv, item, selected) {
        if (!selected)
            return
        row := lv.GetNext(0, "F")
        if (!row)
            return
        cid := Integer(lv.GetText(row, 1))
        c := this._clusters.GetById(cid)
        if !c {
            this.clusterDetail.Value := ""
            return
        }

        txt := "Cluster #" cid "`r`n"
            . "Count: " c.count "`r`n"
            . "Avg(ms): " Round(c.stats.Mean(), 1) "   Std(ms): " Round(c.stats.StdDev(), 1) "`r`n"
            . "Min/Max: " c.stats.min " / " c.stats.max "`r`n"
            . "Most common window: " c.MostCommonWindow() "`r`n"
            . "Core tokens: " c.CoreTokensString() "`r`n`r`n"
            . "Top member signatures:`r`n"

        shown := 0
        for b in this._bursts {
            if (b.clusterId = cid) {
                txt .= "- #" b.id "  " b.DurationMs() "ms  " b.signature "`r`n"
                shown += 1
                if (shown >= 12)
                    break
            }
        }
        this.clusterDetail.Value := txt
    }

    _FindBurstById(id) {
        for b in this._bursts
            if (b.id = id)
                return b
        return 0
    }

    _RefreshBurstLV() {
        this.burstLV.Delete()
        for b in this._bursts {
            this.burstLV.Add(,
                b.id,
                b.startWall,
                b.DurationMs(),
                b.windowExe,
                b.keyCount,
                b.clickCount,
                b.wheelCount,
                Round(b.moveIn, 3),
                b.signature,
                (b.clusterId ? b.clusterId : "")
            )
        }
    }

    _RefreshClusterLV() {
        this.clusterLV.Delete()
        clusters := this._clusters.AllSorted("avg_desc") ; avg duration desc
        for c in clusters {
            this.clusterLV.Add(,
                c.id,
                c.count,
                Round(c.stats.Mean(), 1),
                Round(c.stats.StdDev(), 1),
                c.stats.min,
                c.stats.max,
                Round(c.avgKeys, 1),
                Round(c.avgClicks, 1),
                Round(c.avgMoveIn, 3),
                c.MostCommonWindow(),
                c.CoreTokensString()
            )
        }
        this._UpdateClusterStatus()
    }

    _ReclusterAll() {
        this._clusters.Clear()
        for b in this._bursts {
            b.clusterId := 0
            this._clusters.AddBurst(b)
        }
        this._RefreshBurstLV()
        this._RefreshClusterLV()
        this._UpdateUiStatus()
        this._Toast("Clustering", "Reclustered: " this._clusters.Count() " clusters.")
    }

    _RecalcStats(refreshUi := false) {
        this._patternStats := Map()

        for b in this._bursts {
            sig := b.signature
            if !this._patternStats.Has(sig)
                this._patternStats[sig] := PatternStat(sig)
            this._patternStats[sig].AddBurst(b)
        }

        if refreshUi {
            this.statLV.Delete()
            for sig, st in this._patternStats {
                this.statLV.Add(,
                    sig,
                    st.count,
                    Round(st.Avg(), 1),
                    Round(st.StdDev(), 1),
                    st.min,
                    st.max,
                    Round(st.avgKeys, 1),
                    Round(st.avgClicks, 1),
                    Round(st.avgMoveIn, 3),
                    st.MostCommonWindow()
                )
            }
        }

        ; Also refresh cluster LV (clusters are updated online as bursts close; but keep UI in sync)
        this._RefreshClusterLV()
    }

    _Toast(title, msg) {
        TrayTip(title, msg, 2)
    }

    ; ------------------------- HOOK PIPELINE -------------------------

    _EnqueueEvent(ev) {
        if this._queueLock
            return
        this._queue.Push(ev)
    }

    _FlushQueue() {
        if this._queueLock
            return
        this._queueLock := true
        try {
            if (this._queue.Length = 0) {
                this._queueLock := false
                return
            }
            batch := this._queue
            this._queue := []
            for ev in batch
                this._ProcessEvent(ev)
        } finally {
            this._queueLock := false
        }
    }

    _IdleCheck() {
        if !this.cfg["recording"]
            return
        if !this._active
            return

        idle := A_TickCount - this._active.lastTs
        th := this._active.DynamicIdleThreshold(this.cfg["idleMinMs"], this.cfg["idleFactor"])
        if (idle >= th)
            this._CloseActive("idle_gap")
    }

    _ProcessEvent(ev) {
        this._ring.Push(ev)

        if !this.cfg["recording"]
            return

        if !ev.Has("winExe")
            ev["winExe"] := this._SafeWinExe()
        if !ev.Has("winTitle")
            ev["winTitle"] := this._SafeWinTitle()
        if !ev.Has("dpi")
            ev["dpi"] := (A_ScreenDPI ? A_ScreenDPI : 96)

        kind := ev["kind"]

        if (kind = "keyDown") {
            vk := ev["vk"]
            this._pressed[vk] := true
            ev["mods"] := this._CurrentMods()
            ev["chord"] := this._ChordString(ev["keyName"], ev["mods"])
        } else if (kind = "keyUp") {
            vk := ev["vk"]
            if this._pressed.Has(vk)
                this._pressed.Delete(vk)
            ev["mods"] := this._CurrentMods()
        }

        if (!this._active) {
            this._StartNewBurst(ev)
        } else {
            idle := ev["ts"] - this._active.lastTs
            th := this._active.DynamicIdleThreshold(this.cfg["idleMinMs"], this.cfg["idleFactor"])
            if (idle >= th) {
                this._CloseActive("gap_before_event")
                this._StartNewBurst(ev)
            }
        }

        if (this._active)
            this._active.AddEvent(ev)

        this._UpdateUiStatus()
    }

    _StartNewBurst(firstEv) {
        b := Burst(this._nextBurstId++)
        b.startTs := firstEv["ts"]
        b.startWall := this._NowTime()
        b.windowExe := firstEv["winExe"]
        b.windowTitle := firstEv["winTitle"]

        preStart := firstEv["ts"] - this.cfg["preRollMs"]
        pre := this._ring.GetSince(preStart)
        for ev in pre {
            if (ev["ts"] < firstEv["ts"]) {
                ev2 := ev.Clone()
                ev2["preroll"] := true
                b.AddEvent(ev2)
            }
        }

        this._active := b
        this._UpdateLive()
    }

    _CloseActive(reason) {
        b := this._active
        if !b
            return

        b.endTs := A_TickCount
        b.closeReason := reason
        b.FinalizeSignature()

        ; --- fuzzy cluster assignment (online) ---
        this._clusters.AddBurst(b)

        this._bursts.Push(b)
        this._active := 0

        this._AppendBurstToJsonl(b)
        this._RefreshBurstLV()
        this._RecalcStats(true)
        this._UpdateLive()
        this._UpdateUiStatus()
    }

    _AppendBurstToJsonl(burst) {
        path := this.cfg["logDir"] "\bursts.jsonl"
        FileAppend(burst.ToJsonLine() "`r`n", path, "UTF-8")
    }

    _WriteSessionSummary(forceExport := false) {
        if (this._bursts.Length = 0 && !forceExport)
            return

        DirCreate(this.cfg["logDir"])

        bCsv := this.cfg["logDir"] "\bursts_summary.csv"
        pCsv := this.cfg["logDir"] "\patterns_summary.csv"
        cCsv := this.cfg["logDir"] "\clusters_summary.csv"

        FileDelete(bCsv)
        FileDelete(pCsv)
        FileDelete(cCsv)

        FileAppend("id,start_wall,duration_ms,window_exe,keys,clicks,wheel,move_in,signature,cluster_id,close_reason`r`n", bCsv, "UTF-8")
        for b in this._bursts {
            FileAppend(
                b.id "," this._Csv(b.startWall) "," b.DurationMs() "," this._Csv(b.windowExe) "," b.keyCount "," b.clickCount "," b.wheelCount "," Round(b.moveIn, 4) "," this._Csv(b.signature) "," (b.clusterId ? b.clusterId : "") "," this._Csv(b.closeReason) "`r`n",
                bCsv, "UTF-8"
            )
        }

        this._RecalcStats(false)
        FileAppend("signature,count,avg_ms,std_ms,min_ms,max_ms,avg_keys,avg_clicks,avg_move_in,most_common_window`r`n", pCsv, "UTF-8")
        for sig, st in this._patternStats {
            FileAppend(
                this._Csv(sig) "," st.count "," Round(st.Avg(), 2) "," Round(st.StdDev(), 2) "," st.min "," st.max "," Round(st.avgKeys, 2) "," Round(st.avgClicks, 2) "," Round(st.avgMoveIn, 4) "," this._Csv(st.MostCommonWindow()) "`r`n",
                pCsv, "UTF-8"
            )
        }

        ; clusters
        FileAppend("cluster_id,count,avg_ms,std_ms,min_ms,max_ms,avg_keys,avg_clicks,avg_move_in,most_common_window,core_tokens`r`n", cCsv, "UTF-8")
        for c in this._clusters.AllSorted("avg_desc") {
            FileAppend(
                c.id "," c.count "," Round(c.stats.Mean(), 2) "," Round(c.stats.StdDev(), 2) "," c.stats.min "," c.stats.max ","
                Round(c.avgKeys, 2) "," Round(c.avgClicks, 2) "," Round(c.avgMoveIn, 4) "," this._Csv(c.MostCommonWindow()) "," this._Csv(c.CoreTokensString()) "`r`n",
                cCsv, "UTF-8"
            )
        }
    }

    ; ------------------------- Helpers -------------------------

    _NowTime() => FormatTime(A_Now, "HH:mm:ss")

    _SafeWinTitle() {
            return WinGetTitle("A")
        
        
    }
    _SafeWinExe() {
            return WinGetProcessName("A")
    }


    _CurrentMods() {
        mods := []
        if GetKeyState("LControl","P") || GetKeyState("RControl","P")
            mods.Push("Ctrl")
        if GetKeyState("LShift","P") || GetKeyState("RShift","P")
            mods.Push("Shift")
        if GetKeyState("LAlt","P") || GetKeyState("RAlt","P")
            mods.Push("Alt")
        if GetKeyState("LWin","P") || GetKeyState("RWin","P")
            mods.Push("Win")
        return mods
    }

    _ChordString(keyName, mods) {
        base := keyName
        if (base = "LShift" || base = "RShift") 
            base := "Shift"
        else if (base = "LControl" || base = "RControl") 
            base := "Ctrl"
        else if (base = "LAlt" || base = "RAlt") 
            base := "Alt"
        else if (base = "LWin" || base = "RWin") 
            base := "Win"

        parts := []
        for m in mods
            if (m != base)
                parts.Push(m)
        parts.Push(base)

        s := ""
        for i, p in parts
            s .= (i=1 ? "" : "+") p
        return s
    }

    _Csv(s) {
        s := "" s
        if InStr(s, ",") || InStr(s, "`r") || InStr(s, "`n") || InStr(s, '"')
            return '"' StrReplace(s, '"', '""') '"'
        return s
    }

    _ToFloat(s, fallback) {
        return s + 0.0

    }
}

; ======================================================================================================================
; NEW: Fuzzy clustering engine (token-based Jaccard + windowExe bonus)
; - Burst must have .signature and .windowExe and .DurationMs() etc.
; - Writes clusterId into burst.clusterId
; ======================================================================================================================
class ClusterEngine {
    __New(threshold := 0.58, exeWeight := 0.18, tokenMinFrac := 0.35, maxCoreTokens := 28) {
        this.SetConfig(threshold, exeWeight, tokenMinFrac, maxCoreTokens)
        this._clusters := []
        this._nextId := 1
    }

    SetConfig(threshold, exeWeight, tokenMinFrac, maxCoreTokens) {
        this.threshold := this._Clamp01(threshold)
        this.exeWeight := this._Clamp01(exeWeight)
        this.tokenMinFrac := this._Clamp01(tokenMinFrac)
        this.maxCoreTokens := Max(6, Integer(maxCoreTokens))
    }

    Clear() {
        this._clusters := []
        this._nextId := 1
    }

    Count() => this._clusters.Length

    GetById(id) {
        for c in this._clusters
            if (c.id = id)
                return c
        return 0
    }

    AllSorted(mode := "avg_desc") {
        arr := []
        for c in this._clusters
            arr.Push(c)

        if (arr.Length <= 1)
            return arr

        ; simple sort without relying on advanced builtins
        ; mode: avg_desc or count_desc
        swapped := true
        while swapped {
            swapped := false
            i := 1
            while (i < arr.Length) {
                a := arr[i], b := arr[i+1]
                aKey := (mode="count_desc") ? a.count : a.stats.Mean()
                bKey := (mode="count_desc") ? b.count : b.stats.Mean()
                if (bKey > aKey) {
                    tmp := arr[i]
                    arr[i] := arr[i+1]
                    arr[i+1] := tmp
                    swapped := true
                }
                i += 1
            }
        }
        return arr
    }

    AddBurst(burst) {
        burst.clusterId := 0

        tokens := this._TokensFromBurst(burst)
        exe := (burst.windowExe != "" ? burst.windowExe : "<noexe>")

        best := 0
        bestScore := -1.0

        for c in this._clusters {
            score := this._Score(tokens, exe, c)
            if (score > bestScore) {
                bestScore := score
                best := c
            }
        }

        if (best && bestScore >= this.threshold) {
            best.AddMember(burst, tokens, exe)
            burst.clusterId := best.id
            burst.clusterScore := bestScore
        } else {
            cNew := Cluster(this._nextId++, this.tokenMinFrac, this.maxCoreTokens)
            cNew.AddMember(burst, tokens, exe)
            this._clusters.Push(cNew)
            burst.clusterId := cNew.id
            burst.clusterScore := 1.0
        }
    }

    _Score(tokens, exe, cluster) {
        ; Jaccard(set(tokens), set(coreTokens(cluster))) with exe bonus
        core := cluster.CoreTokenSet()
        if (core.Count() = 0) {
            ; fallback: compare against any tokens seen
            core := cluster.AllTokenSet()
        }
        j := this._Jaccard(tokens, core)
        exeMatch := (cluster.HasWindow(exe) ? 1.0 : 0.0)
        return (j * (1.0 - this.exeWeight)) + (exeMatch * this.exeWeight)
    }

    _Jaccard(aSet, bSet) {
        inter := 0
        union := 0

        for k, _ in aSet {
            if bSet.Has(k)
                inter += 1
            union += 1
        }
        for k, _ in bSet
            if !aSet.Has(k)
                union += 1

        if (union <= 0)
            return 0.0
        return inter / union
    }

    _TokensFromBurst(b) {
    ; Parse from signature "exe | tok tok tok"
    s := b.signature
    p := InStr(s, "|")
    tail := (p ? Trim(SubStr(s, p+1)) : Trim(s))

    ; normalize: split on spaces
    parts := StrSplit(tail, " ")
    set := Map()

    ; keep only informative tokens, strip noise
    for tok in parts {
        tok := Trim(tok)
        if (tok = "" || tok = "<no-input>")
            continue

        ; discard mouseUp tokens for clustering (usually noise) but keep mouseDown, wheel, key chords
        ; tokens in your recorder look like: K:Ctrl+S, M:LButtonDown, M:LButtonUp, W:Up
        if (SubStr(tok, 1, 2) = "M:" && InStr(tok, "Up"))
            continue

        ; reduce rare detailed stuff: if it ever includes coordinates, drop it (future-proof)
        if InStr(tok, "@") || InStr(tok, ",")
            continue

        set[tok] := true
    }
    return set
}

    _Clamp01(x) {
        try{
             x := x + 0.0
        }
        catch{
            x := 0.0
        }
        if (x < 0)
             return 0.0
        if (x > 1) 
            return 1.0
        return x
    }
    
}

class Cluster {
    __New(id, tokenMinFrac, maxCoreTokens) {
        this.id := id
        this.count := 0
        this.stats := OnlineStats()
        this._tokenFreq := Map()      ; token -> count
        this._winCounts := Map()      ; exe -> count

        this.avgKeys := 0.0
        this.avgClicks := 0.0
        this.avgMoveIn := 0.0

        this.tokenMinFrac := tokenMinFrac
        this.maxCoreTokens := maxCoreTokens
    }

    AddMember(b, tokenSet, exe) {
        this.count += 1
        this.stats.Add(b.DurationMs())

        ; update averages
        this.avgKeys += (b.keyCount - this.avgKeys) / this.count
        this.avgClicks += (b.clickCount - this.avgClicks) / this.count
        this.avgMoveIn += (b.moveIn - this.avgMoveIn) / this.count

        ; token frequencies
        for tok, _ in tokenSet {
            this._tokenFreq[tok] := (this._tokenFreq.Has(tok) ? this._tokenFreq[tok] : 0) + 1
        }

        ; window counts
        this._winCounts[exe] := (this._winCounts.Has(exe) ? this._winCounts[exe] : 0) + 1
    }

    HasWindow(exe) => this._winCounts.Has(exe)

    MostCommonWindow() {
        best := ""
        bestC := -1
        for w, c in this._winCounts
            if (c > bestC)
                bestC := c, best := w
        return best
    }

    AllTokenSet() {
        s := Map()
        for tok, _ in this._tokenFreq
            s[tok] := true
        return s
    }

    CoreTokenSet() {
        s := Map()
        if (this.count <= 0)
            return s

        minCount := Ceil(this.count * this.tokenMinFrac)
        for tok, c in this._tokenFreq
            if (c >= minCount)
                s[tok] := true

        ; limit size by taking the strongest frequencies
        if (s.Count() > this.maxCoreTokens) {
            ranked := []
            for tok, c in this._tokenFreq
                ranked.Push({t: tok, c: c})
            ; sort desc by c
            swapped := true
            while swapped {
                swapped := false
                i := 1
                while (i < ranked.Length) {
                    if (ranked[i+1].c > ranked[i].c) {
                        tmp := ranked[i]
                        ranked[i] := ranked[i+1]
                        ranked[i+1] := tmp
                        swapped := true
                    }
                    i += 1
                }
            }
            limited := Map()
            i := 1
            while (i <= ranked.Length && limited.Count() < this.maxCoreTokens) {
                tok := ranked[i].t
                if s.Has(tok)
                    limited[tok] := true
                i += 1
            }
            return limited
        }

        return s
    }

    CoreTokensString() {
        core := this.CoreTokenSet()
        if (core.Count() = 0)
            return "<none>"

        ; stable-ish output: alphabetical
        arr := []
        for tok, _ in core
            arr.Push(tok)
        ; bubble sort alpha
        swapped := true
        while swapped {
            swapped := false
            i := 1
            while (i < arr.Length) {
                if (StrLower(arr[i+1]) < StrLower(arr[i])) {
                    tmp := arr[i]
                    arr[i] := arr[i+1]
                    arr[i+1] := tmp
                    swapped := true
                }
                i += 1
            }
        }

        out := ""
        for i, tok in arr
            out .= (i=1 ? "" : " ") tok
        return out
    }
}

class OnlineStats {
    __New() {
        this.n := 0
        this._meany := 0.0
        this.m2 := 0.0
        this.min := 2147483647
        this.max := 0
    }

    Add(x) {
        this.n += 1
        if (x < this.min) this.min := x
        if (x > this.max) this.max := x

        ; Welford
        delta := x - this._meany
        this._meany += delta / this.n
        delta2 := x - this._meany
        this.m2 += delta * delta2
    }

    mean() => (this.n ? this._meany : 0.0)

    StdDev() {
        if (this.n < 2)
            return 0.0
        var := this.m2 / (this.n - 1)
        if (var < 0) var := 0
        return Sqrt(var)
    }
}

class Burst {
    __New(id) {
        this.id := id
        this.startTs := 0
        this.endTs := 0
        this.startWall := ""
        this.windowExe := ""
        this.windowTitle := ""
        this.events := []
        this.keyCount := 0
        this.clickCount := 0
        this.wheelCount := 0
        this.movePx := 0.0
        this.moveIn := 0.0
        this.lastTs := 0
        this.lastKind := ""
        this.lastDetail := ""
        this.closeReason := ""
        this._gaps := []                    ; inter-event gaps ms (for dynamic idle threshold)
        this._sigParts := []                ; build signature incrementally
        this.signature := ""
    }

    AddEvent(ev) {
        ; update timing gaps
        if (this.lastTs) {
            gap := ev["ts"] - this.lastTs
            if (gap >= 0 && gap <= 60000)
                this._gaps.Push(gap)
        }

        this.events.Push(ev)
        this.lastTs := ev["ts"]
        this.lastKind := ev["kind"]
        this.lastDetail := this._EventShort(ev)

        ; counts + movement
        k := ev["kind"]
        if (k = "keyDown") {
            this.keyCount += 1
            if ev.Has("chord")
                this._sigParts.Push("K:" ev["chord"])
        } else if (k = "mouseDown") {
            this.clickCount += 1
            this._sigParts.Push("M:" ev["button"] "Down")
        } else if (k = "mouseUp") {
            this._sigParts.Push("M:" ev["button"] "Up")
        } else if (k = "wheel") {
            this.wheelCount += 1
            this._sigParts.Push("W:" (ev["wheelDelta"] > 0 ? "Up" : "Down"))
        } else if (k = "mouseMove") {
            if ev.Has("distPx") {
                this.movePx += ev["distPx"]
                dpi := ev.Has("dpi") ? ev["dpi"] : 96
                this.moveIn += (ev["distPx"] / dpi)
            }
        }
    }

    _EventShort(ev) {
        k := ev["kind"]
        if (k = "keyDown")
            return ev.Has("chord") ? ev["chord"] : ev["keyName"]
        if (k = "keyUp")
            return ev["keyName"]
        if (k = "mouseDown" || k = "mouseUp")
            return ev["button"] " @ " ev["x"] "," ev["y"]
        if (k = "wheel")
            return "wheel " (ev["wheelDelta"] > 0 ? "up" : "down") " @ " ev["x"] "," ev["y"]
        if (k = "mouseMove")
            return ev["x"] "," ev["y"]
        return k
    }

    DurationMs() {
        if (this.endTs)
            return this.endTs - this.startTs
        if (this.lastTs)
            return this.lastTs - this.startTs
        return 0
    }

    DynamicIdleThreshold(idleMinMs, idleFactor) {
        ; If no gaps yet: use idleMinMs
        if (this._gaps.Length = 0)
            return idleMinMs

        ; Use average gap (robust enough; avoids heavy median code)
        sum := 0
        for g in this._gaps
            sum += g
        avg := sum / this._gaps.Length
        th := Max(idleMinMs, Round(avg * idleFactor))
        return th
    }

    FinalizeSignature() {
        ; Signature = windowExe + first N signature parts (normalized)
        n := Min(18, this._sigParts.Length)
        sig := this.windowExe
        if (sig = "")
            sig := "<noexe>"
        sig .= " | "

        for i, p in this._sigParts {
            if (i > n)
                break
            sig .= (i=1 ? "" : " ") p
        }
        if (n = 0)
            sig .= "<no-input>"
        this.signature := sig
    }

    Describe() {
        s :=
            "Burst #" this.id "`r`n" .
            "Start: " this.startWall "`r`n" .
            "Duration(ms): " this.DurationMs() "`r`n" .
            "Window: " this.windowExe "`r`nTitle: " this.windowTitle "`r`n" .
            "Keys: " this.keyCount "  Clicks: " this.clickCount "  Wheel: " this.wheelCount "`r`n" .
            "Move: " Round(this.moveIn, 3) " in (" Round(this.movePx) " px)`r`n" .
            "Close reason: " this.closeReason "`r`n" .
            "Signature: " this.signature "`r`n`r`n"

        ; show last ~60 events with preroll marker
        start := Max(1, this.events.Length - 60)
        for i in RangeInt(start, this.events.Length) {
            ev := this.events[i]
            tag := (ev.Has("preroll") && ev["preroll"]) ? "[pre] " : "      "
            s .= tag this._EventLine(ev) "`r`n"
        }
        return s
    }

    _EventLine(ev) {
        t := ev["ts"]
        k := ev["kind"]
        if (k = "keyDown")
            return t " keyDown " (ev.Has("chord") ? ev["chord"] : ev["keyName"])
        if (k = "keyUp")
            return t " keyUp   " ev["keyName"]
        if (k = "mouseMove")
            return t " move    " ev["x"] "," ev["y"] "  d=" (ev.Has("distPx") ? Round(ev["distPx"],2) : 0)
        if (k = "mouseDown" || k = "mouseUp")
            return t " " k " " ev["button"] " @ " ev["x"] "," ev["y"]
        if (k = "wheel")
            return t " wheel   " (ev["wheelDelta"] > 0 ? "Up" : "Down") " @ " ev["x"] "," ev["y"]
        return t " " k
    }

    ToJsonLine() {
        ; compact JSON for external ML pipelines (one line per burst)
        ; (simple manual JSON; avoids extra libs)
        j := "{"
        j .= '"id":' this.id
        j .= ',"startWall":' JsonStr(this.startWall)
        j .= ',"durationMs":' this.DurationMs()
        j .= ',"windowExe":' JsonStr(this.windowExe)
        j .= ',"windowTitle":' JsonStr(this.windowTitle)
        j .= ',"keys":' this.keyCount
        j .= ',"clicks":' this.clickCount
        j .= ',"wheel":' this.wheelCount
        j .= ',"moveIn":' Round(this.moveIn, 6)
        j .= ',"signature":' JsonStr(this.signature)
        j .= ',"closeReason":' JsonStr(this.closeReason)
        j .= ',"events":['

        maxEvents := 700
        start := Max(1, this.events.Length - maxEvents)
        first := true
        for i in RangeInt(start, this.events.Length) {
            ev := this.events[i]
            if !first
                j .= ","
            first := false
            j .= EventToJson(ev)
        }
        j .= "]}"
        return j
    }
}

class PatternStat {
    __New(sig) {
        this.sig := sig
        this.count := 0
        this.sum := 0.0
        this.sumSq := 0.0
        this.min := 2147483647
        this.max := 0
        this.avgKeys := 0.0
        this.avgClicks := 0.0
        this.avgMoveIn := 0.0
        this._winCounts := Map()   ; windowExe -> count
    }

    AddBurst(b) {
        d := b.DurationMs()
        this.count += 1
        this.sum += d
        this.sumSq += d*d
        if (d < this.min) this.min := d
        if (d > this.max) this.max := d

        ; incremental averages (stable)
        this.avgKeys += (b.keyCount - this.avgKeys) / this.count
        this.avgClicks += (b.clickCount - this.avgClicks) / this.count
        this.avgMoveIn += (b.moveIn - this.avgMoveIn) / this.count

        w := (b.windowExe != "" ? b.windowExe : "<noexe>")
        this._winCounts[w] := (this._winCounts.Has(w) ? this._winCounts[w] : 0) + 1
    }

    Avg() => (this.count ? (this.sum / this.count) : 0.0)

    StdDev() {
        if (this.count < 2)
            return 0.0
        _meany := this.sum / this.count
        var := (this.sumSq / this.count) - (_meany*_meany)
        if (var < 0)
            var := 0
        return Sqrt(var)
    }

    MostCommonWindow() {
        best := ""
        bestC := -1
        for w, c in this._winCounts
            if (c > bestC)
                bestC := c, best := w
        return best
    }
}

class EventRingBuffer {
    __New(capacity) {
        this.cap := capacity
        this.arr := []
    }
    Clear() => (this.arr := [])
    Push(ev) {
        this.arr.Push(ev)
        if (this.arr.Length > this.cap)
            this.arr.RemoveAt(1)
    }
    GetSince(tsMin) {
        out := []
        for ev in this.arr
            if (ev["ts"] >= tsMin)
                out.Push(ev)
        return out
    }
}

; ----------------------------------------------------------------------------------------------------------------------
; LOW LEVEL HOOKS (WH_KEYBOARD_LL + WH_MOUSE_LL)
; ----------------------------------------------------------------------------------------------------------------------
class LowLevelHookMgr {
    __New(onEventFunc, mouseSampleMs := 12, mouseMinPx := 1) {
        this.onEvent := onEventFunc
        this.mouseSampleMs := mouseSampleMs
        this.mouseMinPx := mouseMinPx

        this.hKey := 0
        this.hMouse := 0
        this.cbKey := 0
        this.cbMouse := 0

        this._lastMoveTs := 0
        this._lastMoveX := ""
        this._lastMoveY := ""
    }

    SetMouseThrottle(sampleMs, minPx) {
        this.mouseSampleMs := Max(1, Integer(sampleMs))
        this.mouseMinPx := Max(0, Integer(minPx))
    }

    Start() {
        if (this.hKey || this.hMouse)
            return

        this.cbKey := CallbackCreate(ObjBindMethod(this, "_KbdProc"), "Fast", 3)
        this.cbMouse := CallbackCreate(ObjBindMethod(this, "_MouseProc"), "Fast", 3)

        hMod := DllCall("GetModuleHandleW", "Ptr", 0, "Ptr")
        this.hKey := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", this.cbKey, "Ptr", hMod, "UInt", 0, "Ptr")    ; WH_KEYBOARD_LL=13
        this.hMouse := DllCall("SetWindowsHookExW", "Int", 14, "Ptr", this.cbMouse, "Ptr", hMod, "UInt", 0, "Ptr") ; WH_MOUSE_LL=14
    }

    Stop() {
        if (this.hKey) {
            DllCall("UnhookWindowsHookEx", "Ptr", this.hKey)
            this.hKey := 0
        }
        if (this.hMouse) {
            DllCall("UnhookWindowsHookEx", "Ptr", this.hMouse)
            this.hMouse := 0
        }
        if (this.cbKey) {
            CallbackFree(this.cbKey)
            this.cbKey := 0
        }
        if (this.cbMouse) {
            CallbackFree(this.cbMouse)
            this.cbMouse := 0
        }
    }

    _KbdProc(nCode, wParam, lParam) {
        if (nCode >= 0) {
            vk := NumGet(lParam, 0, "UInt")
            sc := NumGet(lParam, 4, "UInt")
            flags := NumGet(lParam, 8, "UInt")

            ; WM_KEYDOWN=0x0100 WM_SYSKEYDOWN=0x0104 WM_KEYUP=0x0101 WM_SYSKEYUP=0x0105
            kind := (wParam = 0x0100 || wParam = 0x0104) ? "keyDown"
                : (wParam = 0x0101 || wParam = 0x0105) ? "keyUp"
                : ""

            if (kind != "") {
                kn := ""
                try {
                    kn := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
                } catch {
                    kn := Format("vk{:02X}", vk)
                }

                ev := Map(
                    "ts", A_TickCount,
                    "kind", kind,
                    "vk", vk,
                    "sc", sc,
                    "flags", flags,
                    "keyName", kn
                )
                this.onEvent.Call(ev)
            }
        }

        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }

    _MouseProc(nCode, wParam, lParam) {
        if (nCode >= 0) {
            x := NumGet(lParam, 0, "Int")
            y := NumGet(lParam, 4, "Int")
            mouseData := NumGet(lParam, 8, "UInt")
            now := A_TickCount

            if (wParam = 0x0200) { ; WM_MOUSEMOVE
                if (this._lastMoveX != "") {
                    dx := x - this._lastMoveX
                    dy := y - this._lastMoveY
                    if ((now - this._lastMoveTs) < this.mouseSampleMs && (Abs(dx) + Abs(dy)) < this.mouseMinPx)
                        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
                }

                dist := 0.0
                if (this._lastMoveX != "")
                    dist := Sqrt((x - this._lastMoveX)**2 + (y - this._lastMoveY)**2)

                this._lastMoveTs := now
                this._lastMoveX := x
                this._lastMoveY := y

                ev := Map("ts", now, "kind", "mouseMove", "x", x, "y", y, "distPx", dist)
                this.onEvent.Call(ev)
            }
            else if (wParam = 0x0201 || wParam = 0x0202 || wParam = 0x0204 || wParam = 0x0205 || wParam = 0x0207 || wParam = 0x0208 || wParam = 0x020B || wParam = 0x020C) {
                button := (wParam=0x0201 || wParam=0x0202) ? "LButton"
                    : (wParam=0x0204 || wParam=0x0205) ? "RButton"
                    : (wParam=0x0207 || wParam=0x0208) ? "MButton"
                    : "XButton"

                kind := (wParam=0x0201 || wParam=0x0204 || wParam=0x0207 || wParam=0x020B) ? "mouseDown" : "mouseUp"

                if (button = "XButton") {
                    xbtn := (mouseData >> 16) & 0xFFFF
                    button := (xbtn = 1) ? "XButton1" : "XButton2"
                }

                ev := Map("ts", now, "kind", kind, "x", x, "y", y, "button", button)
                this.onEvent.Call(ev)
            }
            else if (wParam = 0x020A || wParam = 0x020E) { ; WM_MOUSEWHEEL / WM_MOUSEHWHEEL
                delta := (mouseData >> 16) & 0xFFFF
                if (delta & 0x8000)
                    delta := delta - 0x10000

                ev := Map(
                    "ts", now,
                    "kind", "wheel",
                    "x", x, "y", y,
                    "wheelDelta", delta,
                    "wheelHorizontal", (wParam = 0x020E)
                )
                this.onEvent.Call(ev)
            }
        }

        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
}
class CoreDemoApp {
    __New() {
        ; Load RichEdit (for highlighted viewer)
        try DllCall("LoadLibrary", "Str", "Msftedit.dll", "Ptr")

        this.cfg := Map("tickMs", 750, "title", "AHK v2 Core: Objects/Funcs/OOP/Event-Driven")
        this.state := { timerOn: false, ticks: 0 }
        this.tests := Map()
        this._BuildTests()

        this.gui := Gui("+Resize +MinSize860x520", this.cfg["title"])
        this.gui.SetFont("s9", "Consolas")

        ; Tabs
        this.tab := this.gui.Add("Tab3", "xm ym w820 h460 vMainTabs", ["Demo", "Code", "Reference"])

        ; ---------------------- TAB 1: Demo ----------------------
        this.tab.UseTab(1)
        this.out := this.gui.Add("Edit", "xm ym+30 w820 h360 -Wrap ReadOnly vOut")
        this.btnRun := this.gui.Add("Button", "xm y+10 w130", "Run All (F1)")
        this.btnTimer := this.gui.Add("Button", "x+10 yp w150", "Toggle Timer (F2)")
        this.btnCopy := this.gui.Add("Button", "x+10 yp w120", "Copy Output")
        this.drop := this.gui.Add("DropDownList", "x+10 yp w260 Choose1 vTestDrop", this._TestNames())
        this.btnOne := this.gui.Add("Button", "x+10 yp w130", "Run Selected")

        this.btnRun.OnEvent("Click", ObjBindMethod(this, "RunAll"))
        this.btnTimer.OnEvent("Click", ObjBindMethod(this, "ToggleTimer"))
        this.btnCopy.OnEvent("Click", (*) => (A_Clipboard := this.out.Value))
        this.btnOne.OnEvent("Click", (*) => this.RunOne(this.drop.Text))

        ; ---------------------- TAB 2: Code ----------------------
        this.tab.UseTab(2)

        this.gui.Add("Text", "xm ym+30", "Editable (left) → Highlighted Viewer (right)")

        this.codeEdit := this.gui.Add("Edit", "xm y+6 w400 h392 WantTab vCodeEdit")
        ; Custom RichEdit control to apply coloring
        this.codeView := this.gui.Add("Custom", "x+10 yp w410 h392 +0x10000000 ClassRICHEDIT50W vCodeView") ; WS_EX_CLIENTEDGE

        this.codeHighlighter := RichEditHighlighter(this.codeView.Hwnd)

        ; Seed code with this script

        seeded := FileRead(A_ScriptFullPath, "UTF-8")

        this.codeEdit.Value := seeded
        this.codeHighlighter.SetText(seeded)
        this.codeHighlighter.Highlight()

        ; Debounced highlight on edits (fast + avoids flicker)
        this._syncPending := false
        this.codeEdit.OnEvent("Change", ObjBindMethod(this, "_OnCodeEdited"))

        ; ---------------------- TAB 3: Reference ----------------------
        this.tab.UseTab(3)

        this.gui.Add("Text", "xm ym+30", "Search:")
        this.refSearch := this.gui.Add("Edit", "x+10 yp-2 w360 vRefSearch")
        this.refCount := this.gui.Add("Text", "x+10 yp+2 w220 vRefCount", "")

        this.refLV := this.gui.Add("ListView", "xm y+8 w820 h400 Grid -Multi vRefLV", ["Function", "Signature / Params", "Notes"])
        this.refLV.ModifyCol(1, 170)
        this.refLV.ModifyCol(2, 330)
        this.refLV.ModifyCol(3, 300)

        this.refData := this._BuildRefData()
        this._FillRefList("")
        this.refSearch.OnEvent("Change", ObjBindMethod(this, "_OnRefSearch"))

        ; End tab building
        this.tab.UseTab()

        this.gui.OnEvent("Size", ObjBindMethod(this, "_OnSize"))
        this.gui.OnEvent("Close", (*) => ExitApp())

        ; Initial UI state
        this.Log("Ready. F1=RunAll | F2=Timer | Esc=Exit`r`n")
        this.gui.Show("w900 h560")
        this._OnSize(this.gui, 0, 900, 560)
    }

    ; ---------------------- Resizing ----------------------
    _OnSize(guiObj, minMax, w, h) {
        ; Padding + minimums
        pad := 12
        tabW := Max(300, w - pad*2)
        tabH := Max(260, h - pad*2)

        this.tab.Move(pad, pad, tabW, tabH)

        ; Content area inside tab: approximate offsets
        cx := pad + 10
        cy := pad + 40
        cw := tabW - 20
        ch := tabH - 60

        ; --- Demo tab controls ---
        outH := Max(120, ch - 52)
        this.out.Move(cx, cy, cw, outH)

        btnY := cy + outH + 10
        this.btnRun.Move(cx, btnY)
        this.btnTimer.Move(cx + 140, btnY)
        this.btnCopy.Move(cx + 300, btnY)
        this.drop.Move(cx + 430, btnY, 260)
        this.btnOne.Move(cx + 700, btnY)

        ; --- Code tab controls ---
        ; Two columns split
        leftW := Floor((cw - 10) / 2)
        rightW := cw - 10 - leftW
        codeY := cy + 22
        codeH := Max(140, ch - 22)

        this.codeEdit.Move(cx, codeY, leftW, codeH)
        this.codeView.Move(cx + leftW + 10, codeY, rightW, codeH)

        ; --- Reference tab controls ---
        this.refSearch.Move(cx + 70, cy - 32, 360)
        this.refCount.Move(cx + 440, cy - 30, 260)

        this.refLV.Move(cx, cy, cw, ch)
    }

    ; ---------------------- Demo runner ----------------------
    Log(text) => (this.out.Value .= text . (SubStr(text, -1) = "`n" ? "" : "`r`n"))

    _BuildTests() {
        this.tests["01) Arrays + Map + plain object"] := ObjBindMethod(this, "_T01_Collections")
        this.tests["02) Classes + properties + validation"] := ObjBindMethod(this, "_T02_ClassProps")
        this.tests["03) Closures + fat arrow + higher-order"] := ObjBindMethod(this, "_T03_Closures")
        this.tests["04) __Item + dynamic prop access"] := ObjBindMethod(this, "_T04_MetaProps")
        this.tests["05) Custom iteration via __Enum"] := ObjBindMethod(this, "_T05_Enum")
        this.tests["06) try/catch/throw + finally"] := ObjBindMethod(this, "_T06_Errors")
        this.tests["07) GUI events + Bind + state"] := ObjBindMethod(this, "_T07_Events")
    }

    _TestNames() {
        names := []
        for name, _ in this.tests
            names.Push(name)
        return names
    }

    RunOne(name) {
        if !this.tests.Has(name) {
            this.Log("No such test: " name)
            return
        }
        this.Log("=== " name " ===")
        this.tests[name].Call()
        this.Log("")
    }

    RunAll() {
        this.out.Value := ""
        for name, fn in this.tests {
            this.Log("=== " name " ===")
            fn.Call()
            this.Log("")
        }
        this.Log("Done.")
    }

    ToggleTimer() {
        this.state.timerOn := !this.state.timerOn
        if this.state.timerOn {
            this.Log("Timer ON (" this.cfg["tickMs"] "ms)")
            SetTimer(ObjBindMethod(this, "_OnTick"), this.cfg["tickMs"])
        } else {
            this.Log("Timer OFF")
            SetTimer(ObjBindMethod(this, "_OnTick"), 0)
        }
    }

    _OnTick() {
        this.state.ticks += 1
        ToolTip("Ticks: " this.state.ticks "  (F2 toggles)", 10, 10)
        if (this.state.ticks >= 8) {
            ToolTip()
            this.ToggleTimer()
        }
    }

    ; ---------------------- Code tab: live highlight ----------------------
    _OnCodeEdited(*) {
        if this._syncPending
            return
        this._syncPending := true
        SetTimer(ObjBindMethod(this, "_SyncHighlight"), -120)
    }

    _SyncHighlight() {
        this._syncPending := false
        text := this.codeEdit.Value
        this.codeHighlighter.SetText(text)
        this.codeHighlighter.Highlight()
    }

    ; ---------------------- Reference tab ----------------------
    _OnRefSearch(*) {
        this._FillRefList(this.refSearch.Value)
    }

    _FillRefList(filterText) {
        f := StrLower(Trim(filterText))
        this.refLV.Delete()

        shown := 0
        for item in this.refData {
            if (f != "") {
                hay := StrLower(item.name " " item.sig " " item.note)
                if !InStr(hay, f)
                    continue
            }
            this.refLV.Add(, item.name, item.sig, item.note)
            shown += 1
        }
        this.refCount.Text := shown " items"
    }

    ; _BuildRefData() {
    ;     ; Dense, “other AIs mess this up” oriented list (v2 function style + param expectations)
    ;     d := []

    ;     d.Push({name:"MsgBox", sig:"MsgBox(Text := """", Title := """", Options := """")", note:"Function in v2 (no command syntax)."})
    ;     d.Push({name:"InputBox", sig:"InputBox(Prompt := """", Title := """", Options := """", Default := """")", note:"Returns object with .Value/.Result."})
    ;     d.Push({name:"Send", sig:"Send(Keys)", note:"Function; strings like ""^c"" etc."})
    ;     d.Push({name:"SetTimer", sig:"SetTimer(FuncOrObj, PeriodMs)", note:"Pass Func/closure/bound method; Period 0 disables; negative = one-shot."})
    ;     d.Push({name:"WinExist", sig:"WinExist(WinTitle)", note:"Returns hwnd or 0. Use ""ahk_id "" hwnd for targeting."})
    ;     d.Push({name:"WinActive", sig:"WinActive(WinTitle)", note:"Function form; don’t use v1 IfWinActive."})
    ;     d.Push({name:"ControlGetText", sig:"ControlGetText(Control, WinTitle := ""A"")", note:"Reads text; Control can be ClassNN or hwnd."})
    ;     d.Push({name:"ControlSetText", sig:"ControlSetText(Text, Control, WinTitle := ""A"")", note:"Sets text; for custom controls prefer SetWindowTextW via DllCall."})

    ;     d.Push({name:"Type", sig:"Type(Value)", note:"Returns type name: ""Array"", ""Map"", ""String"", class name, etc."})
    ;     d.Push({name:"IsObject", sig:"IsObject(Value)", note:"True for Array/Map/custom instances."})
    ;     d.Push({name:"Map", sig:"Map([k1,v1, k2,v2, ...])", note:"Keys can be ANY type (objects too). Use .Has(key)."})
    ;     d.Push({name:"Array methods", sig:"arr.Push(v), InsertAt(i,v), RemoveAt(i), Pop()", note:"Array is [] literal; 1-based indexing."})

    ;     d.Push({name:"ObjBindMethod", sig:"ObjBindMethod(obj, ""Method"", args*)", note:"Binds target + optional args; don’t re-bind obj again."})
    ;     d.Push({name:"Func.Bind", sig:"fn.Bind(args*)", note:"Binds leading args. Great for timers/events."})
    ;     d.Push({name:"try/catch/finally", sig:"try { } catch as err { } finally { }", note:"Errors are objects; err.Message, err.What, etc."})
    ;     d.Push({name:"throw", sig:"throw Error(""msg"")", note:"Throw an Error object (or any value)."})
    ;     d.Push({name:"DllCall", sig:"DllCall(""User32.dll\\MessageBoxW"", ""Ptr"",0, ""Str"",t, ""Str"",cap, ""UInt"",0)", note:"v2 requires explicit types; returns value from function."})

    ;     d.Push({name:"Gui", sig:"g := Gui(Options, Title)", note:"Object-based GUI. Use g.Add(type, options, text)."})
    ;     d.Push({name:"Gui.Add", sig:"ctrl := g.Add(""Edit"", ""w300"", ""text"")", note:"Returns control object; ctrl.Value gets/sets for built-ins."})
    ;     d.Push({name:"OnEvent", sig:"ctrl.OnEvent(""Click"", callback)", note:"callback signature depends on event; use (*)=>... to ignore params."})

    ;     d.Push({name:"Properties", sig:"Prop { get => ...  set { ... } }", note:"AHK v2 property syntax; validate in setters."})
    ;     d.Push({name:"Meta methods", sig:"__Item[key], __Enum(varCount), __Get/__Set", note:"Customize indexers, iteration, dynamic access."})

    ;     return d
    ; }

    _BuildRefData() {
        d := []

        d.Push({name:"MsgBox", sig:"MsgBox(Text := `"`", Title := `"`", Options := `"`")", note:"Function in v2 (no command syntax)."})
        d.Push({name:"InputBox", sig:"InputBox(Prompt := `"`", Title := `"`", Options := `"`", Default := `"`")", note:"Returns object with .Value/.Result."})
        d.Push({name:"Send", sig:"Send(Keys)", note:"Function; strings like `"`^c`"` etc."})
        d.Push({name:"SetTimer", sig:"SetTimer(FuncOrObj, PeriodMs)", note:"Pass Func/closure/bound method; Period 0 disables; negative = one-shot."})
        d.Push({name:"WinExist", sig:"WinExist(WinTitle)", note:"Returns hwnd or 0. Use `"`ahk_id `"` hwnd for targeting."})
        d.Push({name:"WinActive", sig:"WinActive(WinTitle)", note:"Function form; don’t use v1 IfWinActive."})
        d.Push({name:"ControlGetText", sig:"ControlGetText(Control, WinTitle := `"`A`"`)", note:"Reads text; Control can be ClassNN or hwnd."})
        d.Push({name:"ControlSetText", sig:"ControlSetText(Text, Control, WinTitle := `"`A`"`)", note:"Sets text; for custom controls prefer SetWindowTextW via DllCall."})

        d.Push({name:"Type", sig:"Type(Value)", note:"Returns type name: `"`Array`"`, `"`Map`"`, `"`String`"`, class name, etc."})
        d.Push({name:"IsObject", sig:"IsObject(Value)", note:"True for Array/Map/custom instances."})
        d.Push({name:"Map", sig:"Map([k1,v1, k2,v2, ...])", note:"Keys can be ANY type (objects too). Use .Has(key)."})
        d.Push({name:"Array methods", sig:"arr.Push(v), InsertAt(i,v), RemoveAt(i), Pop()", note:"Array is [] literal; 1-based indexing."})

        d.Push({name:"ObjBindMethod", sig:"ObjBindMethod(obj, `"`Method`"`, args*)", note:"Binds target + optional args; don’t re-bind obj again."})
        d.Push({name:"Func.Bind", sig:"fn.Bind(args*)", note:"Binds leading args. Great for timers/events."})
        d.Push({name:"try/catch/finally", sig:"try { } catch as err { } finally { }", note:"Errors are objects; err.Message, err.What, etc."})
        d.Push({name:"throw", sig:"throw Error(`"msg`")", note:"Throw an Error object (or any value)."})
        d.Push({name:"DllCall", sig:"DllCall(`"User32.dll\MessageBoxW`", `"Ptr`",0, `"Str`",t, `"Str`",cap, `"UInt`",0)", note:"v2 requires explicit types; returns function return value."})

        d.Push({name:"Gui", sig:"g := Gui(Options, Title)", note:"Object-based GUI. Use g.Add(type, options, text)."})
        d.Push({name:"Gui.Add", sig:"ctrl := g.Add(`"Edit`", `"w300`", `"text`")", note:"Returns control object; ctrl.Value gets/sets for built-ins."})
        d.Push({name:"OnEvent", sig:"ctrl.OnEvent(`"Click`", callback)", note:"callback signature depends on event; use (*)=>... to ignore params."})

        d.Push({name:"Properties", sig:"Prop { get => ...  set { ... } }", note:"AHK v2 property syntax; validate in setters."})
        d.Push({name:"Meta methods", sig:"__Item[key], __Enum(varCount), __Get/__Set", note:"Customize indexers, iteration, dynamic access."})

        return d
    }




    ; ---------------------- TESTS ----------------------
    _T01_Collections() {
        arr := ["alpha", "beta"]
        arr.Push("gamma")
        arr.InsertAt(2, "BETA")
        arr.RemoveAt(1)

        m := Map("pi", 3.14159, 42, "answer")
        m[arr] := "arrays can be keys too"
        o := { Name: "Don", Role: "Builder" }

        s := "arr=" this._Fmt(arr) "`r`n"
          . "map(pi)=" m["pi"] ", map(42)=" m[42] ", map(arrKey)=" m[arr] "`r`n"
          . "obj.Name=" o.Name ", obj.Role=" o.Role
        this.Log(s)
    }

    _T02_ClassProps() {
        p := Person("Alex", 29)
        p.Age := 30
        this.Log("Person.ToString(): " p.ToString())
        p.Rename("Alexandra")
        this.Log("Renamed -> " p.Name)
        this.Log("Factory -> " Person.FromCsv("Sam,41").ToString())
    }

    _T03_Closures() {
        makeAdder := (n) => ((x) => x + n)
        add10 := makeAdder(10)
        nums := [1,2,3,4]
        doubled := this._Map(nums, (x) => x*2)
        this.Log("add10(5)=" add10(5))
        this.Log("Map x2 -> " this._Fmt(doubled))
    }

    _T04_MetaProps() {
        cfg := Settings()
        cfg.TimeoutMs := 1200
        cfg["Mode"] := "Debug"
        propName := "TimeoutMs"
        this.Log("Dynamic cfg.%propName% => " cfg.%propName%)
        this.Log("Indexer cfg['Mode'] => " cfg["Mode"])
    }

    _T05_Enum() {
        r := Range(3, 9, 2)
        parts := []
        for v in r
            parts.Push(v)
        this.Log("Range(3..9 step2) => " this._Fmt(parts))
    }

    _T06_Errors() {
        try {
            _ := Person("BadAge", -1)
        } catch as err {
            this.Log("Caught: " Type(err) " | " err.Message)
        } finally {
            this.Log("finally always runs.")
        }
    }

    _T07_Events() {
        clicker := { count: 0 }

        ; Objects are reference types in v2: NO & ByRef needed to mutate object properties
        bump := (obj) => (++obj.count)
        bump(clicker), bump(clicker)
        this.Log("Closure mutated count=" clicker.count)

        ; Correct binding: ObjBindMethod already binds `this`
        f := ObjBindMethod(this, "Log").Bind("Bound method called via Bind() OK")
        f.Call()
    }

    ; ---------------------- UTIL ----------------------
    _Map(arr, fn) {
        out := []
        for v in arr
            out.Push(fn.Call(v))
        return out
    }

    _Fmt(x) {
        t := Type(x)
        if (t = "Array") {
            s := "["
            for i, v in x
                s .= (i=1 ? "" : ", ") . (IsObject(v) ? "<obj>" : v)
            return s "]"
        }
        if (t = "Map") {
            s := "Map{"
            first := true
            for k, v in x {
                s .= (first ? "" : ", "), first := false
                s .= (IsObject(k) ? "<objKey>" : k) ":" (IsObject(v) ? "<obj>" : v)
            }
            return s "}"
        }
        if IsObject(x)
            return "<" t ">"
        return x
    }
}

class Person {
    static MinAge := 0

    __New(name, age) {
        this.Name := name
        this.Age := age
    }

    Name {
        get => this._name
        set => this._name := value
    }

    Age {
        get => this._age
        set {
            if (value < Person.MinAge)
                throw Error("Age must be >= " Person.MinAge)
            this._age := value
        }
    }

    Rename(newName) => (this.Name := newName)
    ToString() => Format("Person(Name={1}, Age={2})", this.Name, this.Age)

    static FromCsv(line) {
        parts := StrSplit(line, ",")
        return Person(Trim(parts[1]), Integer(Trim(parts[2])))
    }
}

class Settings {
    __New() => (this._m := Map())

    __Item[key] {
        get => this._m.Has(key) ? this._m[key] : ""
        set => this._m[key] := value
    }

    TimeoutMs {
        get => this._m.Has("TimeoutMs") ? this._m["TimeoutMs"] : 500
        set {
            if (value < 50)
                throw Error("TimeoutMs too small")
            this._m["TimeoutMs"] := Integer(value)
        }
    }
}

class Range {
    __New(start, stop, step := 1) {
        if (step = 0)
            throw Error("step cannot be 0")
        this.start := start, this.stop := stop, this.step := step
    }

    __Enum(varCount) {
        i := this.start - this.step
        if (varCount != 1)
            throw Error("Range supports single-var enumeration only")
        return (&outVal) => ((i += this.step) <= this.stop ? (outVal := i, true) : false)
    }
}

; ======================================================================================================================
; RichEditHighlighter: minimal AHK v2 syntax highlighting for a RICHEDIT50W control (no external DLLs beyond Msftedit.dll)
; Highlights:
;   - Comments: ; to end of line
;   - Strings: "..." (handles doubled quotes "")
;   - Keywords: core v2 language words + common directives
; ======================================================================================================================
class RichEditHighlighter {
    static WM_SETREDRAW := 0x000B
    static EM_SETSEL := 0x00B1
    static EM_EXSETSEL := 0x0437
    static EM_SETCHARFORMAT := 0x0444
    static SCF_SELECTION := 0x0001
    static SCF_ALL := 0x0004

    __New(hwnd) {
        this.hwnd := hwnd

        ; default font to Consolas (RichEdit needs explicit font assignment)
        this._SetDefaultFont("Consolas", 9)

        ; Keywords tuned for v2 correctness
        this.keywords := [
            "class","extends","global","local","static","if","else","for","while","loop","until",
            "break","continue","return","try","catch","finally","throw","switch","case","default",
            "and","or","not","in","is","as","true","false","unset","this","super"
        ]
    }

    SetText(text) {
        ; Set window text directly (works reliably for custom RichEdit control)
        DllCall("SetWindowTextW", "Ptr", this.hwnd, "Str", text)
    }

    Highlight() {
        ; Freeze redraw
        SendMessage(RichEditHighlighter.WM_SETREDRAW, 0, 0, this.hwnd)

        text := this._GetText()
        if (text = "") {
            SendMessage(RichEditHighlighter.WM_SETREDRAW, 1, 0, this.hwnd)
            DllCall("RedrawWindow", "Ptr", this.hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0001|0x0004)
            return
        }

        ; Reset all formatting to default (black)
        this._SelectAll()
        this._SetSelectionFormat(0x000000, false, false)

        ; Apply strings (light red-ish) and comments (green-ish) and keywords (blue-ish)
        ; NOTE: Windows RichEdit uses BGR COLORREF
        this._ApplyStrings(text, 0x0000A0, false, false)   ; BGR: 0x00GGRR -> red-ish
        this._ApplyComments(text, 0x008000, false, false)  ; green
        this._ApplyKeywords(text, 0xA00000, true, false)   ; blue-ish + bold

        ; Unfreeze redraw
        SendMessage(RichEditHighlighter.WM_SETREDRAW, 1, 0, this.hwnd)
        DllCall("RedrawWindow", "Ptr", this.hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x0001|0x0004)
    }

    ; -------------------- Internals --------------------
    _GetText() {
        ; Use GetWindowTextLength/GetWindowText for speed
        len := DllCall("GetWindowTextLengthW", "Ptr", this.hwnd, "Int")
        if (len <= 0)
            return ""
        buf := Buffer((len + 1) * 2, 0)
        DllCall("GetWindowTextW", "Ptr", this.hwnd, "Ptr", buf, "Int", len + 1)
        return StrGet(buf)
    }

    _SelectAll() {
        SendMessage(RichEditHighlighter.EM_SETSEL, 0, -1, this.hwnd)
    }

    _SetDefaultFont(face, sizePt) {
        ; Apply as default to entire control once
        this._SelectAll()
        this._SetSelectionFormat(0x000000, false, false, face, sizePt)
        ; Move caret to start
        SendMessage(RichEditHighlighter.EM_SETSEL, 0, 0, this.hwnd)
    }

    _SetSelectionFormat(colorBGR, bold := false, italic := false, face := "", sizePt := "") {
        ; CHARFORMAT2W
        ; https://learn.microsoft.com/en-us/windows/win32/api/richedit/ns-richedit-charformat2w
        CF := Buffer(116, 0)
        NumPut("UInt", 116, CF, 0) ; cbSize

        mask := 0x40000000 ; CFM_COLOR
        effects := 0

        if (bold != "")
            mask |= 0x00000001 ; CFM_BOLD
        if (italic != "")
            mask |= 0x00000002 ; CFM_ITALIC

        if (bold)
            effects |= 0x00000001 ; CFE_BOLD
        if (italic)
            effects |= 0x00000002 ; CFE_ITALIC

        if (face != "")
            mask |= 0x20000000 ; CFM_FACE
        if (sizePt != "")
            mask |= 0x80000000 ; CFM_SIZE

        NumPut("UInt", mask, CF, 4)       ; dwMask
        NumPut("UInt", effects, CF, 8)    ; dwEffects
        NumPut("UInt", colorBGR, CF, 20)  ; crTextColor

        if (sizePt != "")
            NumPut("Int", sizePt * 20, CF, 12) ; yHeight in twips (1 pt = 20 twips)

        if (face != "") {
            ; szFaceName is WCHAR[32] at offset 26 in CHARFORMAT2W
            StrPut(face, CF.Ptr + 26, 32, "UTF-16")
        }

        SendMessage(RichEditHighlighter.EM_SETCHARFORMAT, RichEditHighlighter.SCF_SELECTION, CF.Ptr, this.hwnd)
    }

    _SetSelRange(startChar, endChar) {
        ; EM_SETSEL expects character positions
        SendMessage(RichEditHighlighter.EM_SETSEL, startChar, endChar, this.hwnd)
    }

    _ApplyComments(text, colorBGR, bold := false, italic := false) {
        ; Simple rule: ';' to end-of-line
        ; (Not perfect around strings, but pragmatic + dense for demo usage.)
        pos := 1
        while (pos := InStr(text, ";", false, pos)) {
            lineEnd := InStr(text, "`n", false, pos)
            if (!lineEnd)
                lineEnd := StrLen(text) + 1
            ; Convert 1-based to 0-based char indices
            s0 := pos - 1
            e0 := lineEnd - 1
            this._SetSelRange(s0, e0)
            this._SetSelectionFormat(colorBGR, bold, italic)
            pos := lineEnd
        }
        this._SetSelRange(0, 0)
    }

    _ApplyStrings(text, colorBGR, bold := false, italic := false) {
        i := 1
        n := StrLen(text)
        while (i <= n) {
            ch := SubStr(text, i, 1)
            if (ch = '"') {
                start := i
                i += 1
                while (i <= n) {
                    ch2 := SubStr(text, i, 1)
                    if (ch2 = '"') {
                        ; doubled quote "" stays inside string
                        if (i < n && SubStr(text, i+1, 1) = '"') {
                            i += 2
                            continue
                        }
                        i += 1
                        break
                    }
                    i += 1
                }
                ; Apply [start..i)
                s0 := start - 1
                e0 := i - 1
                this._SetSelRange(s0, e0)
                this._SetSelectionFormat(colorBGR, bold, italic)
            } else {
                i += 1
            }
        }
        this._SetSelRange(0, 0)
    }

    _ApplyKeywords(text, colorBGR, bold := true, italic := false) {
        ; Word-boundary-ish scan (ASCII letters/_ + digits after first)
        n := StrLen(text)
        i := 1
        while (i <= n) {
            ch := SubStr(text, i, 1)
            if this._IsWordStart(ch) {
                start := i
                i += 1
                while (i <= n && this._IsWordMid(SubStr(text, i, 1)))
                    i += 1

                word := SubStr(text, start, i - start)
                if this._IsKeyword(word) {
                    s0 := start - 1
                    e0 := i - 1
                    this._SetSelRange(s0, e0)
                    this._SetSelectionFormat(colorBGR, bold, italic)
                }
            } else {
                i += 1
            }
        }
        this._SetSelRange(0, 0)
    }

    _IsKeyword(word) {
        lw := StrLower(word)
        for k in this.keywords
            if (lw = k)
                return true
        return false
    }

    _IsWordStart(ch) {
        c := Ord(ch)
        return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (ch = "_")
    }

    _IsWordMid(ch) {
        c := Ord(ch)
        return this._IsWordStart(ch) || (c >= 48 && c <= 57)
    }
}

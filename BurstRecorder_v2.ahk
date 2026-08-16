#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, OutputDebug
SetWorkingDir(A_ScriptDir)

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; BURST RECORDER v2 - Enhanced Process Timing, Pattern Matching & Replay
; ══════════════════════════════════════════════════════════════════════════════════════════════════
;
; NEW FEATURES IN v2:
;   - Pattern Fingerprinting: Detects duplicate/similar action sequences
;   - Burst Labeling: Name, describe, and categorize bursts after capture
;   - Replay Visualization: "Ghost" playback showing what happened without clicking
;   - Calibration Mode: Record slow, deliberate workflows where timing is ignored
;   - Reference Patterns: Define "gold standard" workflows to match against
;
; HOTKEYS:
;   F9  = Toggle Recording (normal mode)
;   F10 = Show/Hide Recorder UI
;   F11 = Export data to logs folder
;   F12 = Toggle Calibration Mode (timing-independent recording)
;   Esc = Exit application
;
; ══════════════════════════════════════════════════════════════════════════════════════════════════

global BurstApp := BurstRecorderApp()

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; HOTKEYS
; ══════════════════════════════════════════════════════════════════════════════════════════════════

F9::BurstApp.ToggleRecording()
F10::BurstApp.ToggleUi()
F11::BurstApp.Export()
F12::BurstApp.ToggleCalibrationMode()
Escape::ExitApp()

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; MAIN APPLICATION CLASS
; ══════════════════════════════════════════════════════════════════════════════════════════════════

class BurstRecorderApp {
    
    __New() {
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; CONFIGURATION
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.cfg := Map(
            ; Core recording
            "recording", true,
            "preRollMs", 3000,
            "idleMinMs", 1200,
            "idleFactor", 6.0,
            "mouseMoveSampleMs", 12,
            "mouseMoveMinPx", 1,
            "flushMs", 40,
            "idleCheckMs", 200,
            "logDir", A_ScriptDir "\logs",
            
            ; Clustering
            "clusterThreshold", 0.58,
            "clusterExeWeight", 0.18,
            "clusterTokenMinFrac", 0.35,
            "clusterMaxCoreTokens", 28,
            
            ; Pattern matching
            "fingerprintMinSimilarity", 0.70,    ; Min similarity to suggest as duplicate
            "fingerprintMaxTokens", 50,           ; Max tokens in fingerprint
            
            ; Calibration mode
            "calibrationMode", false,             ; When true, timing is ignored
            "calibrationIdleMs", 30000            ; 30 second idle before auto-close in calibration
        )
        
        try DirCreate(this.cfg["logDir"])
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; STATE
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this._startTick := A_TickCount
        this._pressed := Map()
        this._ring := EventRingBuffer(6000)
        this._bursts := []
        this._active := 0
        this._nextBurstId := 1
        
        this._queue := []
        this._queueLock := false
        
        ; Analytics
        this._patternStats := Map()
        this._clusters := ClusterEngine(
            this.cfg["clusterThreshold"],
            this.cfg["clusterExeWeight"],
            this.cfg["clusterTokenMinFrac"],
            this.cfg["clusterMaxCoreTokens"]
        )
        
        ; Pattern library (named reference patterns)
        this._referencePatterns := Map()    ; name -> Burst
        this._patternFingerprints := Map()  ; fingerprint -> [burst ids]
        
        ; Replay system
        this._replayOverlay := 0
        this._replayTimer := 0
        this._replayEvents := []
        this._replayIndex := 0
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; HOOKS & TIMERS
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
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
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; GUI
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this._BuildUi()
        this._UpdateUiStatus()
    }
    
    _OnExit(*) {
        try SetTimer(this._flushTimer, 0)
        try SetTimer(this._idleTimer, 0)
        try this._hook.Stop()
        try this._StopReplay()
        try this._WriteSessionSummary()
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; PUBLIC METHODS
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    ToggleRecording() {
        this.cfg["recording"] := !this.cfg["recording"]
        
        if (!this.cfg["recording"] && this._active) {
            this._CloseActive("recording_off")
        }
        
        this._UpdateUiStatus()
    }
    
    ToggleCalibrationMode() {
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; CALIBRATION MODE
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; In calibration mode:
        ;   - Timing between actions is IGNORED for burst detection
        ;   - User performs actions slowly and deliberately
        ;   - Burst only closes after very long idle (30s) or manual close
        ;   - Creates "reference patterns" - the ideal sequence of actions
        ;   - These patterns can then be used to match against normal recordings
        
        this.cfg["calibrationMode"] := !this.cfg["calibrationMode"]
        
        if (this.cfg["calibrationMode"]) {
            ; Starting calibration - close any existing burst first
            if (this._active) {
                this._CloseActive("calibration_start")
            }
            this._Toast("Calibration Mode ON", "Perform your workflow slowly.`nTiming is now ignored.`nPress F12 again when done.")
        } else {
            ; Ending calibration
            if (this._active) {
                this._active.isReference := true
                this._CloseActive("calibration_end")
            }
            this._Toast("Calibration Mode OFF", "Reference pattern saved.`nNormal recording resumed.")
        }
        
        this._UpdateUiStatus()
    }
    
    ToggleUi() {
        if this.gui.Visible {
            this.gui.Hide()
        } else {
            this.gui.Show()
        }
    }
    
    Export() {
        this._WriteSessionSummary(true)
        this._Toast("Exported", "Wrote logs to:`n" this.cfg["logDir"])
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; GUI BUILDING
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _BuildUi() {
        this.gui := Gui("+Resize +MinSize1100x700", "Burst Recorder v2 (Pattern Matching + Replay)")
        this.gui.SetFont("s9", "Consolas")
        
        this.tabs := this.gui.Add("Tab3", "xm ym w1060 h640", 
            ["Live", "Bursts", "Patterns", "Clusters", "Replay", "Settings"])
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; TAB 1: LIVE VIEW
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab(1)
        this.liveStatus := this.gui.Add("Text", "xm ym+30 w1060 h20", "")
        this.liveMetrics := this.gui.Add("Edit", "xm y+8 w1060 h550 -Wrap ReadOnly", "")
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; TAB 2: BURSTS LIST WITH LABELING
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab(2)
        
        this.burstLV := this.gui.Add("ListView", "xm ym+30 w1060 h300 Grid -Multi", 
            ["#", "Name", "Start", "Dur(ms)", "Window", "Keys", "Clicks", "Move(in)", 
             "Fingerprint", "Similar To", "Ref?"])
        
        this.burstLV.ModifyCol(1, 40)
        this.burstLV.ModifyCol(2, 120)
        this.burstLV.ModifyCol(3, 80)
        this.burstLV.ModifyCol(4, 60)
        this.burstLV.ModifyCol(5, 150)
        this.burstLV.ModifyCol(6, 50)
        this.burstLV.ModifyCol(7, 50)
        this.burstLV.ModifyCol(8, 70)
        this.burstLV.ModifyCol(9, 180)
        this.burstLV.ModifyCol(10, 100)
        this.burstLV.ModifyCol(11, 40)
        
        this.burstLV.OnEvent("ItemSelect", ObjBindMethod(this, "_OnBurstSelect"))
        this.burstLV.OnEvent("DoubleClick", ObjBindMethod(this, "_OnBurstDoubleClick"))
        
        ; Burst detail and labeling panel
        this.gui.Add("GroupBox", "xm y+10 w1060 h230", "Burst Details && Labeling")
        
        this.gui.Add("Text", "xm+15 yp+25 w80", "Name:")
        this.edBurstName := this.gui.Add("Edit", "x+5 yp-2 w250", "")
        
        this.gui.Add("Text", "x+20 yp+2 w80", "Category:")
        this.edBurstCategory := this.gui.Add("ComboBox", "x+5 yp-2 w150", 
            ["", "Data Entry", "Navigation", "Copy/Paste", "Form Fill", "Search", "Report", "Custom"])
        
        this.chkIsReference := this.gui.Add("Checkbox", "x+20 yp+2", "Reference Pattern")
        
        this.gui.Add("Text", "xm+15 y+10 w80", "Description:")
        this.edBurstDesc := this.gui.Add("Edit", "x+5 yp-2 w600 h60", "")
        
        this.gui.Add("Text", "xm+15 y+10 w80", "Tags:")
        this.edBurstTags := this.gui.Add("Edit", "x+5 yp-2 w400", "")
        this.gui.Add("Text", "x+10 yp+2 w200 cGray", "(comma-separated)")
        
        this.btnSaveLabel := this.gui.Add("Button", "xm+15 y+15 w120", "Save Labels")
        this.btnSaveLabel.OnEvent("Click", ObjBindMethod(this, "_OnSaveBurstLabel"))
        
        this.btnReplayBurst := this.gui.Add("Button", "x+10 yp w120", "Replay (Ghost)")
        this.btnReplayBurst.OnEvent("Click", ObjBindMethod(this, "_OnReplaySelectedBurst"))
        
        this.btnSetAsRef := this.gui.Add("Button", "x+10 yp w150", "Set as Reference")
        this.btnSetAsRef.OnEvent("Click", ObjBindMethod(this, "_OnSetAsReference"))
        
        this.btnFindSimilar := this.gui.Add("Button", "x+10 yp w150", "Find Similar Bursts")
        this.btnFindSimilar.OnEvent("Click", ObjBindMethod(this, "_OnFindSimilar"))
        
        this.burstDetail := this.gui.Add("Edit", "x+20 ym+360 w350 h180 -Wrap ReadOnly", "")
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; TAB 3: PATTERN LIBRARY (Named Reference Patterns)
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab(3)
        
        this.gui.Add("Text", "xm ym+30 w1060", 
            "Reference Patterns - Define ideal workflows to match against. Double-click to replay.")
        
        this.patternLV := this.gui.Add("ListView", "xm y+10 w1060 h350 Grid -Multi",
            ["Name", "Category", "Fingerprint", "Keys", "Clicks", "Move(in)", "Matches", "Avg Match %"])
        
        this.patternLV.ModifyCol(1, 180)
        this.patternLV.ModifyCol(2, 120)
        this.patternLV.ModifyCol(3, 250)
        this.patternLV.ModifyCol(4, 60)
        this.patternLV.ModifyCol(5, 60)
        this.patternLV.ModifyCol(6, 80)
        this.patternLV.ModifyCol(7, 70)
        this.patternLV.ModifyCol(8, 100)
        
        this.patternLV.OnEvent("DoubleClick", ObjBindMethod(this, "_OnPatternDoubleClick"))
        
        this.btnDeletePattern := this.gui.Add("Button", "xm y+10 w140", "Delete Pattern")
        this.btnDeletePattern.OnEvent("Click", ObjBindMethod(this, "_OnDeletePattern"))
        
        this.btnAnalyzePatterns := this.gui.Add("Button", "x+10 yp w180", "Analyze All Patterns")
        this.btnAnalyzePatterns.OnEvent("Click", ObjBindMethod(this, "_OnAnalyzePatterns"))
        
        this.patternAnalysis := this.gui.Add("Edit", "xm y+10 w1060 h140 -Wrap ReadOnly", "")
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; TAB 4: CLUSTERS (Fuzzy grouping)
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab(4)
        this.clusterStatus := this.gui.Add("Text", "xm ym+30 w1060 h20", "")
        
        this.clusterLV := this.gui.Add("ListView", "xm y+8 w1060 h340 Grid -Multi", 
            ["Cluster", "Count", "Avg(ms)", "Std(ms)", "Min", "Max", 
             "AvgKeys", "AvgClicks", "AvgMove(in)", "Window", "Core Tokens"])
        
        this.clusterLV.ModifyCol(1, 60)
        this.clusterLV.ModifyCol(2, 50)
        this.clusterLV.ModifyCol(3, 70)
        this.clusterLV.ModifyCol(4, 70)
        this.clusterLV.ModifyCol(5, 60)
        this.clusterLV.ModifyCol(6, 60)
        this.clusterLV.ModifyCol(7, 70)
        this.clusterLV.ModifyCol(8, 70)
        this.clusterLV.ModifyCol(9, 80)
        this.clusterLV.ModifyCol(10, 200)
        this.clusterLV.ModifyCol(11, 250)
        
        this.clusterLV.OnEvent("ItemSelect", ObjBindMethod(this, "_OnClusterSelect"))
        this.clusterDetail := this.gui.Add("Edit", "xm y+8 w1060 h140 -Wrap ReadOnly", "")
        
        this.btnRecluster := this.gui.Add("Button", "xm y+8 w140", "Recluster All")
        this.btnRecluster.OnEvent("Click", (*) => this._ReclusterAll())
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; TAB 5: REPLAY CONTROLS
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab(5)
        
        this.gui.Add("Text", "xm ym+30 w1060 h40", 
            "Replay Visualization - Watch a 'ghost' playback of any burst WITHOUT actually clicking.`n"
            . "Shows cursor movement, click locations, and key presses as visual overlays.")
        
        this.gui.Add("Text", "xm y+20 w150", "Replay Speed:")
        this.sliderSpeed := this.gui.Add("Slider", "x+10 yp-5 w300 Range1-10", 5)
        this.lblSpeed := this.gui.Add("Text", "x+10 yp+5 w80", "1.0x")
        this.sliderSpeed.OnEvent("Change", (*) => (
            this.lblSpeed.Text := Round(this.sliderSpeed.Value / 5, 1) . "x"
        ))
        
        this.gui.Add("Text", "xm y+20 w150", "Select Burst to Replay:")
        this.ddReplayBurst := this.gui.Add("DropDownList", "x+10 yp-2 w400", ["(none)"])
        
        this.btnStartReplay := this.gui.Add("Button", "xm y+20 w120", "▶ Start Replay")
        this.btnStartReplay.OnEvent("Click", ObjBindMethod(this, "_OnStartReplay"))
        
        this.btnStopReplay := this.gui.Add("Button", "x+10 yp w120", "■ Stop Replay")
        this.btnStopReplay.OnEvent("Click", (*) => this._StopReplay())
        
        this.chkShowPath := this.gui.Add("Checkbox", "x+30 yp+3 Checked", "Show Mouse Path")
        this.chkShowClicks := this.gui.Add("Checkbox", "x+20 yp Checked", "Show Click Markers")
        this.chkShowKeys := this.gui.Add("Checkbox", "x+20 yp Checked", "Show Key Presses")
        
        this.replayLog := this.gui.Add("Edit", "xm y+30 w1060 h350 -Wrap ReadOnly", 
            "Replay log will appear here...")
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; TAB 6: SETTINGS
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab(6)
        
        ; Recording settings
        this.gui.Add("Text", "xm ym+30 w400 cBlue", "Recording Settings")
        
        this.gui.Add("Text", "xm y+14 w360", "Recording:")
        this.chkRec := this.gui.Add("Checkbox", "x+10 yp-2 w200", "Enabled")
        this.chkRec.Value := this.cfg["recording"]
        this.chkRec.OnEvent("Click", (*) => (
            this.cfg["recording"] := !!this.chkRec.Value, 
            this._UpdateUiStatus()
        ))
        
        this.gui.Add("Text", "xm y+14 w360", "Pre-roll ms:")
        this.edPre := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["preRollMs"])
        
        this.gui.Add("Text", "xm y+14 w360", "Idle minimum ms:")
        this.edIdleMin := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["idleMinMs"])
        
        this.gui.Add("Text", "xm y+14 w360", "Idle factor:")
        this.edIdleFactor := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["idleFactor"])
        
        ; Pattern matching settings
        this.gui.Add("Text", "xm y+30 w400 cBlue", "Pattern Matching Settings")
        
        this.gui.Add("Text", "xm y+14 w360", "Fingerprint min similarity (0-1):")
        this.edFpSimilarity := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["fingerprintMinSimilarity"])
        
        this.gui.Add("Text", "xm y+14 w360", "Cluster threshold (0-1):")
        this.edClustTh := this.gui.Add("Edit", "x+10 yp-2 w120", this.cfg["clusterThreshold"])
        
        ; Calibration settings
        this.gui.Add("Text", "xm y+30 w400 cBlue", "Calibration Mode Settings")
        
        this.gui.Add("Text", "xm y+14 w360", "Calibration idle timeout (ms):")
        this.edCalibIdle := this.gui.Add("Edit", "x+10 yp-2 w120 Number", this.cfg["calibrationIdleMs"])
        
        ; Buttons
        this.btnApply := this.gui.Add("Button", "xm y+30 w140", "Apply Settings")
        this.btnApply.OnEvent("Click", ObjBindMethod(this, "_ApplySettings"))
        
        this.btnClear := this.gui.Add("Button", "x+10 yp w140", "Clear Session")
        this.btnClear.OnEvent("Click", (*) => this._ClearSession())
        
        this.btnExport := this.gui.Add("Button", "x+10 yp w140", "Export (F11)")
        this.btnExport.OnEvent("Click", (*) => this.Export())
        
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; FINALIZE
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        
        this.tabs.UseTab()
        
        this.gui.OnEvent("Size", ObjBindMethod(this, "_OnSize"))
        this.gui.OnEvent("Close", (*) => this.gui.Hide())
        
        this.gui.Show("w1140 h720")
    }
    
    _OnSize(guiObj, minMax, w, h) {
        if (minMax = -1) {
            return
        }
        ; Basic resize - tabs fill window
        pad := 12
        tabW := Max(600, w - pad * 2)
        tabH := Max(400, h - pad * 2)
        this.tabs.Move(pad, pad, tabW, tabH)
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; SETTINGS
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _ApplySettings(*) {
        this.cfg["preRollMs"] := Integer(this.edPre.Value)
        this.cfg["idleMinMs"] := Integer(this.edIdleMin.Value)
        this.cfg["idleFactor"] := this._ToFloat(this.edIdleFactor.Value, this.cfg["idleFactor"])
        this.cfg["fingerprintMinSimilarity"] := this._ToFloat(this.edFpSimilarity.Value, 0.70)
        this.cfg["clusterThreshold"] := this._ToFloat(this.edClustTh.Value, 0.58)
        this.cfg["calibrationIdleMs"] := Integer(this.edCalibIdle.Value)
        
        this._clusters.SetConfig(
            this.cfg["clusterThreshold"],
            this.cfg["clusterExeWeight"],
            this.cfg["clusterTokenMinFrac"],
            this.cfg["clusterMaxCoreTokens"]
        )
        
        this._Toast("Settings", "Applied.")
        this._UpdateUiStatus()
    }
    
    _ClearSession() {
        if this._active {
            this._CloseActive("clear_session")
        }
        
        this._bursts := []
        this._patternStats := Map()
        this._clusters.Clear()
        this._ring.Clear()
        this._pressed := Map()
        this._nextBurstId := 1
        this._patternFingerprints := Map()
        
        this._RefreshBurstLV()
        this._RefreshPatternLV()
        this._RefreshClusterLV()
        this._RefreshReplayDropdown()
        this._UpdateLive()
        this._UpdateUiStatus()
        this._Toast("Session", "Cleared.")
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; UI UPDATE METHODS
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _UpdateUiStatus() {
        if !this.HasOwnProp("liveStatus") {
            return
        }
        
        rec := this.cfg["recording"] ? "ON" : "OFF"
        mode := this.cfg["calibrationMode"] ? " [CALIBRATION MODE]" : ""
        
        this.liveStatus.Text := "Recording: " rec . mode
            . "    Bursts: " this._bursts.Length 
            . "    Patterns: " this._referencePatterns.Count
            . "    Active: " (this._active ? "YES" : "NO") 
            . "    | F9=rec F10=UI F11=export F12=calibrate"
        
        try this.chkRec.Value := this.cfg["recording"]
        
        this._UpdateLive()
        this._UpdateClusterStatus()
    }
    
    _UpdateClusterStatus() {
        if !this.HasOwnProp("clusterStatus") {
            return
        }
        
        this.clusterStatus.Text := "Clusters: " this._clusters.Count() 
            . "    Threshold: " this.cfg["clusterThreshold"]
    }
    
    _UpdateLive() {
        if !this.HasOwnProp("liveMetrics") {
            return
        }
        
        b := this._active
        mode := this.cfg["calibrationMode"] ? "`r`n*** CALIBRATION MODE - Timing Ignored ***`r`n" : ""
        
        if !b {
            this.liveMetrics.Value := mode . "No active burst.`r`n`r`n"
                . "Recording: " (this.cfg["recording"] ? "ON" : "OFF") "`r`n"
                . "Bursts recorded: " this._bursts.Length "`r`n"
                . "Reference patterns: " this._referencePatterns.Count "`r`n"
                . "Clusters: " this._clusters.Count() "`r`n`r`n"
                . "Tip: Work normally - bursts auto-detect based on idle gaps.`r`n"
                . "Use F12 for Calibration Mode (timing-independent recording)."
            return
        }
        
        this.liveMetrics.Value := mode . "ACTIVE BURST #" b.id "`r`n"
            . "Name: " (b.name != "" ? b.name : "(unnamed)") "`r`n"
            . "Start: " b.startWall "`r`n"
            . "Duration(ms): " b.DurationMs() "`r`n"
            . "Window: " b.windowExe " | " b.windowTitle "`r`n"
            . "Keys: " b.keyCount "   Clicks: " b.clickCount "   Wheel: " b.wheelCount "`r`n"
            . "Mouse move: " Round(b.moveIn, 3) " in  (" Round(b.movePx) " px)`r`n"
            . "Fingerprint: " b.GetFingerprint() "`r`n"
            . "Last event: " b.lastKind "  " b.lastDetail "`r`n"
    }
    
    _Toast(title, msg) {
        TrayTip(title, msg, 2)
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; BURST SELECTION & LABELING
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _selectedBurstId := 0
    
    _OnBurstSelect(lv, item, selected) {
        if (!selected) {
            return
        }
        
        row := lv.GetNext(0, "F")
        if (!row) {
            return
        }
        
        id := Integer(lv.GetText(row, 1))
        b := this._FindBurstById(id)
        
        if !b {
            return
        }
        
        this._selectedBurstId := id
        
        ; Fill in labeling fields
        this.edBurstName.Value := b.name
        this.edBurstCategory.Text := b.category
        this.edBurstDesc.Value := b.description
        this.edBurstTags.Value := b.GetTagsString()
        this.chkIsReference.Value := b.isReference
        
        ; Show details
        this.burstDetail.Value := b.Describe()
    }
    
    _OnBurstDoubleClick(lv, row) {
        ; Double-click to replay
        if (!row) {
            return
        }
        
        id := Integer(lv.GetText(row, 1))
        b := this._FindBurstById(id)
        
        if b {
            this._StartReplayForBurst(b)
        }
    }
    
    _OnSaveBurstLabel(*) {
        if (this._selectedBurstId = 0) {
            this._Toast("Error", "No burst selected.")
            return
        }
        
        b := this._FindBurstById(this._selectedBurstId)
        if !b {
            return
        }
        
        ; Save labels
        b.name := this.edBurstName.Value
        b.category := this.edBurstCategory.Text
        b.description := this.edBurstDesc.Value
        b.SetTagsFromString(this.edBurstTags.Value)
        b.isReference := this.chkIsReference.Value
        
        ; If marked as reference, add to pattern library
        if (b.isReference && b.name != "") {
            this._referencePatterns[b.name] := b
        }
        
        this._RefreshBurstLV()
        this._RefreshPatternLV()
        this._Toast("Saved", "Labels saved for burst #" b.id)
    }
    
    _OnReplaySelectedBurst(*) {
        if (this._selectedBurstId = 0) {
            this._Toast("Error", "No burst selected.")
            return
        }
        
        b := this._FindBurstById(this._selectedBurstId)
        if b {
            this._StartReplayForBurst(b)
        }
    }
    
    _OnSetAsReference(*) {
        if (this._selectedBurstId = 0) {
            this._Toast("Error", "No burst selected.")
            return
        }
        
        b := this._FindBurstById(this._selectedBurstId)
        if !b {
            return
        }
        
        ; Prompt for name if not set
        if (b.name = "") {
            b.name := "Pattern_" b.id
            this.edBurstName.Value := b.name
        }
        
        b.isReference := true
        this.chkIsReference.Value := true
        this._referencePatterns[b.name] := b
        
        this._RefreshBurstLV()
        this._RefreshPatternLV()
        this._Toast("Reference Set", "Burst #" b.id " is now a reference pattern.")
    }
    
    _OnFindSimilar(*) {
        if (this._selectedBurstId = 0) {
            this._Toast("Error", "No burst selected.")
            return
        }
        
        b := this._FindBurstById(this._selectedBurstId)
        if !b {
            return
        }
        
        ; Find similar bursts
        similar := this._FindSimilarBursts(b, this.cfg["fingerprintMinSimilarity"])
        
        if (similar.Length = 0) {
            this._Toast("No Matches", "No similar bursts found above " 
                . Round(this.cfg["fingerprintMinSimilarity"] * 100) . "% similarity.")
            return
        }
        
        ; Build report
        report := "Similar bursts to #" b.id " (" b.name "):`r`n`r`n"
        
        for match in similar {
            report .= "  #" match.burst.id 
                . " - " (match.burst.name != "" ? match.burst.name : "(unnamed)")
                . " - " Round(match.similarity * 100, 1) "% similar"
                . " - " match.burst.DurationMs() "ms`r`n"
        }
        
        this.burstDetail.Value := report
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; PATTERN LIBRARY
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _OnPatternDoubleClick(lv, row) {
        if (!row) {
            return
        }
        
        name := lv.GetText(row, 1)
        if this._referencePatterns.Has(name) {
            b := this._referencePatterns[name]
            this._StartReplayForBurst(b)
        }
    }
    
    _OnDeletePattern(*) {
        row := this.patternLV.GetNext(0, "F")
        if (!row) {
            return
        }
        
        name := this.patternLV.GetText(row, 1)
        if this._referencePatterns.Has(name) {
            b := this._referencePatterns[name]
            b.isReference := false
            this._referencePatterns.Delete(name)
            this._RefreshPatternLV()
            this._RefreshBurstLV()
            this._Toast("Deleted", "Pattern '" name "' removed from library.")
        }
    }
    
    _OnAnalyzePatterns(*) {
        ; Analyze all patterns - find which bursts match which patterns
        report := "Pattern Analysis Report`r`n"
            . "═══════════════════════════════════════════════════════`r`n`r`n"
        
        if (this._referencePatterns.Count = 0) {
            report .= "No reference patterns defined.`r`n"
            report .= "Select a burst and click 'Set as Reference' to create patterns."
            this.patternAnalysis.Value := report
            return
        }
        
        for name, refBurst in this._referencePatterns {
            report .= "Pattern: " name "`r`n"
            report .= "  Fingerprint: " refBurst.GetFingerprint() "`r`n"
            
            ; Find matches
            matches := this._FindSimilarBursts(refBurst, this.cfg["fingerprintMinSimilarity"])
            report .= "  Matches: " matches.Length " bursts`r`n"
            
            if (matches.Length > 0) {
                ; Calculate average duration
                totalDur := 0
                for m in matches {
                    totalDur += m.burst.DurationMs()
                }
                avgDur := totalDur / matches.Length
                
                report .= "  Avg Duration: " Round(avgDur) "ms`r`n"
                report .= "  Best Match: " Round(matches[1].similarity * 100, 1) "%`r`n"
            }
            
            report .= "`r`n"
        }
        
        this.patternAnalysis.Value := report
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; CLUSTER SELECTION
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _OnClusterSelect(lv, item, selected) {
        if (!selected) {
            return
        }
        
        row := lv.GetNext(0, "F")
        if (!row) {
            return
        }
        
        cid := Integer(lv.GetText(row, 1))
        c := this._clusters.GetById(cid)
        
        if !c {
            this.clusterDetail.Value := ""
            return
        }
        
        txt := "Cluster #" cid "`r`n"
            . "Count: " c.count "`r`n"
            . "Avg(ms): " Round(c.stats.Mean(), 1) "   Std(ms): " Round(c.stats.StdDev(), 1) "`r`n"
            . "Core tokens: " c.CoreTokensString() "`r`n`r`n"
            . "Member bursts:`r`n"
        
        shown := 0
        for b in this._bursts {
            if (b.clusterId = cid) {
                txt .= "- #" b.id "  " (b.name != "" ? b.name : "(unnamed)") 
                    . "  " b.DurationMs() "ms`r`n"
                shown += 1
                if (shown >= 15) {
                    break
                }
            }
        }
        
        this.clusterDetail.Value := txt
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; REPLAY SYSTEM
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _OnStartReplay(*) {
        ; Get selected burst from dropdown
        idx := this.ddReplayBurst.Value
        if (idx <= 1) {
            this._Toast("Error", "Select a burst to replay.")
            return
        }
        
        ; Parse burst ID from dropdown text
        text := this.ddReplayBurst.Text
        if !RegExMatch(text, "^#(\d+)", &m) {
            return
        }
        
        id := Integer(m[1])
        b := this._FindBurstById(id)
        
        if b {
            this._StartReplayForBurst(b)
        }
    }
    
    _StartReplayForBurst(b) {
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; GHOST REPLAY
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; Shows what the burst did WITHOUT actually clicking or typing.
        ; Creates an overlay window that displays:
        ;   - Mouse cursor path as a trail
        ;   - Click locations as colored circles
        ;   - Key presses as floating text
        
        this._StopReplay()
        
        if (b.events.Length = 0) {
            this._Toast("Error", "No events to replay.")
            return
        }
        
        this._replayEvents := b.events
        this._replayIndex := 1
        this._replayBurst := b
        
        ; Create overlay window (transparent, click-through)
        this._replayOverlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        this._replayOverlay.BackColor := "000000"
        WinSetTransColor("000000 200", this._replayOverlay)
        
        ; Make it full screen
        this._replayOverlay.Show("x0 y0 w" A_ScreenWidth " h" A_ScreenHeight " NoActivate")
        
        ; Get speed multiplier
        speedMult := this.sliderSpeed.Value / 5.0
        if (speedMult <= 0) {
            speedMult := 1.0
        }
        
        ; Log
        this.replayLog.Value := "Starting replay of burst #" b.id "`r`n"
            . "Name: " (b.name != "" ? b.name : "(unnamed)") "`r`n"
            . "Events: " b.events.Length "`r`n"
            . "Speed: " Round(speedMult, 1) "x`r`n`r`n"
        
        ; Start replay timer
        this._replaySpeedMult := speedMult
        this._replayLastTs := 0
        this._replayTimer := ObjBindMethod(this, "_ReplayTick")
        SetTimer(this._replayTimer, 16)  ; ~60fps
    }
    
    _ReplayTick() {
        if (this._replayIndex > this._replayEvents.Length) {
            this._StopReplay()
            this.replayLog.Value .= "`r`n=== Replay Complete ==="
            return
        }
        
        ev := this._replayEvents[this._replayIndex]
        
        ; Check timing (simulate delays between events)
        if (this._replayLastTs > 0) {
            originalDelay := ev["ts"] - this._replayLastTs
            scaledDelay := originalDelay / this._replaySpeedMult
            
            ; For calibration mode bursts, use fixed small delay
            if (this._replayBurst.isReference || this.cfg["calibrationMode"]) {
                scaledDelay := 50  ; Fixed 50ms between events
            }
            
            ; Skip if not enough time passed (accumulate)
            static accumulated := 0
            accumulated += 16
            if (accumulated < scaledDelay) {
                return
            }
            accumulated := 0
        }
        
        this._replayLastTs := ev["ts"]
        
        ; Process event visually
        k := ev["kind"]
        
        if (k = "mouseMove" && this.chkShowPath.Value) {
            this._DrawReplayMarker(ev["x"], ev["y"], "path")
        }
        else if ((k = "mouseDown" || k = "mouseUp") && this.chkShowClicks.Value) {
            this._DrawReplayMarker(ev["x"], ev["y"], k = "mouseDown" ? "clickDown" : "clickUp")
            this.replayLog.Value .= ev["ts"] . " " . k . " " . ev["button"] . " @ " . ev["x"] . "," . ev["y"] . "`r`n"
        }
        else if (k = "keyDown" && this.chkShowKeys.Value) {
            keyName := ev.Has("chord") ? ev["chord"] : ev["keyName"]
            this._DrawReplayKey(ev["x"], ev["y"], keyName)
            this.replayLog.Value .= ev["ts"] . " keyDown " . keyName . "`r`n"
        }
        
        this._replayIndex += 1
    }
    
    _DrawReplayMarker(x, y, markerType) {
        ; Draw a visual marker at x,y on the overlay
        if !this._replayOverlay {
            return
        }
        
        ; Create a small GUI element at the position
        size := 8
        color := "FFFF00"  ; Yellow for path
        
        if (markerType = "clickDown") {
            size := 20
            color := "FF0000"  ; Red for click down
        } else if (markerType = "clickUp") {
            size := 16
            color := "00FF00"  ; Green for click up
        }
        
        ; Add a text control as a marker (simple but works)
        try {
            marker := this._replayOverlay.Add("Text", 
                "x" (x - size/2) " y" (y - size/2) " w" size " h" size " Background" color, "")
            
            ; Auto-remove after delay
            SetTimer(() => (
                try marker.Visible := false
            ), -500)
        }
    }
    
    _DrawReplayKey(x, y, keyName) {
        ; Show key press as floating text
        if !this._replayOverlay {
            return
        }
        
        try {
            ; Position near bottom center of screen for visibility
            keyLabel := this._replayOverlay.Add("Text", 
                "x" (A_ScreenWidth/2 - 100) " y" (A_ScreenHeight - 100) 
                " w200 h30 Center BackgroundYellow", keyName)
            
            ; Auto-remove after delay
            SetTimer(() => (
                try keyLabel.Visible := false
            ), -800)
        }
    }
    
    _StopReplay() {
        if this._replayTimer {
            SetTimer(this._replayTimer, 0)
            this._replayTimer := 0
        }
        
        if this._replayOverlay {
            this._replayOverlay.Destroy()
            this._replayOverlay := 0
        }
        
        this._replayEvents := []
        this._replayIndex := 0
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; LIST VIEW REFRESH
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _RefreshBurstLV() {
        if !this.HasOwnProp("burstLV") {
            return
        }
        
        this.burstLV.Delete()
        
        for b in this._bursts {
            ; Find similar pattern
            similarTo := ""
            if (b.similarTo != "" && b.similarScore > 0) {
                similarTo := b.similarTo . " (" . Round(b.similarScore * 100) . "%)"
            }
            
            this.burstLV.Add(,
                b.id,
                b.name,
                b.startWall,
                b.DurationMs(),
                b.windowExe,
                b.keyCount,
                b.clickCount,
                Round(b.moveIn, 2),
                b.GetFingerprint(),
                similarTo,
                b.isReference ? "✓" : ""
            )
        }
        
        this._RefreshReplayDropdown()
    }
    
    _RefreshPatternLV() {
        if !this.HasOwnProp("patternLV") {
            return
        }
        
        this.patternLV.Delete()
        
        for name, b in this._referencePatterns {
            ; Count matches
            matches := this._FindSimilarBursts(b, this.cfg["fingerprintMinSimilarity"])
            avgMatch := 0
            if (matches.Length > 0) {
                total := 0
                for m in matches {
                    total += m.similarity
                }
                avgMatch := total / matches.Length
            }
            
            this.patternLV.Add(,
                name,
                b.category,
                b.GetFingerprint(),
                b.keyCount,
                b.clickCount,
                Round(b.moveIn, 2),
                matches.Length,
                Round(avgMatch * 100, 1) . "%"
            )
        }
    }
    
    _RefreshClusterLV() {
        if !this.HasOwnProp("clusterLV") {
            return
        }
        
        this.clusterLV.Delete()
        
        clusters := this._clusters.AllSorted("avg_desc")
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
    
    _RefreshReplayDropdown() {
        if !this.HasOwnProp("ddReplayBurst") {
            return
        }
        
        items := ["(none)"]
        for b in this._bursts {
            label := "#" b.id " - " (b.name != "" ? b.name : b.windowExe) 
                . " (" b.DurationMs() "ms)"
            items.Push(label)
        }
        
        this.ddReplayBurst.Delete()
        this.ddReplayBurst.Add(items)
        this.ddReplayBurst.Choose(1)
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
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; PATTERN MATCHING
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _FindSimilarBursts(targetBurst, minSimilarity) {
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; FINGERPRINT-BASED SIMILARITY
        ; ─────────────────────────────────────────────────────────────────────────────────────────
        ; Compares bursts by their ACTION SEQUENCE (ignoring timing).
        ; This allows matching a slow calibration recording to fast real-world actions.
        
        targetFp := targetBurst.GetFingerprintTokens()
        results := []
        
        for b in this._bursts {
            if (b.id = targetBurst.id) {
                continue
            }
            
            otherFp := b.GetFingerprintTokens()
            similarity := this._CalculateSimilarity(targetFp, otherFp)
            
            if (similarity >= minSimilarity) {
                results.Push({burst: b, similarity: similarity})
            }
        }
        
        ; Sort by similarity descending
        this._SortBySimilarity(results)
        
        return results
    }
    
    _CalculateSimilarity(tokens1, tokens2) {
        ; Jaccard similarity on token sets
        if (tokens1.Length = 0 && tokens2.Length = 0) {
            return 1.0
        }
        if (tokens1.Length = 0 || tokens2.Length = 0) {
            return 0.0
        }
        
        ; Convert to sets
        set1 := Map()
        for t in tokens1 {
            set1[t] := true
        }
        
        set2 := Map()
        for t in tokens2 {
            set2[t] := true
        }
        
        ; Calculate intersection and union
        inter := 0
        union := 0
        
        for k, _ in set1 {
            if set2.Has(k) {
                inter += 1
            }
            union += 1
        }
        
        for k, _ in set2 {
            if !set1.Has(k) {
                union += 1
            }
        }
        
        if (union = 0) {
            return 0.0
        }
        
        return inter / union
    }
    
    _SortBySimilarity(arr) {
        ; Bubble sort by similarity descending
        if (arr.Length <= 1) {
            return
        }
        
        swapped := true
        while swapped {
            swapped := false
            i := 1
            while (i < arr.Length) {
                if (arr[i + 1].similarity > arr[i].similarity) {
                    tmp := arr[i]
                    arr[i] := arr[i + 1]
                    arr[i + 1] := tmp
                    swapped := true
                }
                i += 1
            }
        }
    }
    
    _MatchAgainstPatterns(burst) {
        ; Find the best matching reference pattern for this burst
        bestMatch := ""
        bestScore := 0.0
        
        burstFp := burst.GetFingerprintTokens()
        
        for name, refBurst in this._referencePatterns {
            refFp := refBurst.GetFingerprintTokens()
            similarity := this._CalculateSimilarity(burstFp, refFp)
            
            if (similarity > bestScore) {
                bestScore := similarity
                bestMatch := name
            }
        }
        
        if (bestScore >= this.cfg["fingerprintMinSimilarity"]) {
            burst.similarTo := bestMatch
            burst.similarScore := bestScore
        }
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; EVENT PROCESSING
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _EnqueueEvent(ev) {
        if this._queueLock {
            return
        }
        this._queue.Push(ev)
    }
    
    _FlushQueue() {
        if this._queueLock {
            return
        }
        
        this._queueLock := true
        
        try {
            if (this._queue.Length = 0) {
                this._queueLock := false
                return
            }
            
            batch := this._queue
            this._queue := []
            
            for ev in batch {
                this._ProcessEvent(ev)
            }
        } finally {
            this._queueLock := false
        }
    }
    
    _IdleCheck() {
        if !this.cfg["recording"] {
            return
        }
        
        if !this._active {
            return
        }
        
        idle := A_TickCount - this._active.lastTs
        
        ; In calibration mode, use longer idle threshold
        if (this.cfg["calibrationMode"]) {
            if (idle >= this.cfg["calibrationIdleMs"]) {
                this._active.isReference := true
                this._CloseActive("calibration_idle")
            }
        } else {
            th := this._active.DynamicIdleThreshold(this.cfg["idleMinMs"], this.cfg["idleFactor"])
            if (idle >= th) {
                this._CloseActive("idle_gap")
            }
        }
    }
    
    _ProcessEvent(ev) {
        this._ring.Push(ev)
        
        if !this.cfg["recording"] {
            return
        }
        
        ; Add window info
        if !ev.Has("winExe") {
            ev["winExe"] := this._SafeWinExe()
        }
        if !ev.Has("winTitle") {
            ev["winTitle"] := this._SafeWinTitle()
        }
        if !ev.Has("dpi") {
            ev["dpi"] := (A_ScreenDPI ? A_ScreenDPI : 96)
        }
        
        kind := ev["kind"]
        
        ; Track key states
        if (kind = "keyDown") {
            vk := ev["vk"]
            this._pressed[vk] := true
            ev["mods"] := this._CurrentMods()
            ev["chord"] := this._ChordString(ev["keyName"], ev["mods"])
        } else if (kind = "keyUp") {
            vk := ev["vk"]
            if this._pressed.Has(vk) {
                this._pressed.Delete(vk)
            }
            ev["mods"] := this._CurrentMods()
        }
        
        ; Handle burst lifecycle
        if (!this._active) {
            this._StartNewBurst(ev)
        } else if (!this.cfg["calibrationMode"]) {
            ; In normal mode, check for idle gap
            idle := ev["ts"] - this._active.lastTs
            th := this._active.DynamicIdleThreshold(this.cfg["idleMinMs"], this.cfg["idleFactor"])
            
            if (idle >= th) {
                this._CloseActive("gap_before_event")
                this._StartNewBurst(ev)
            }
        }
        ; In calibration mode, we don't auto-close based on timing
        
        if (this._active) {
            this._active.AddEvent(ev)
        }
        
        this._UpdateUiStatus()
    }
    
    _StartNewBurst(firstEv) {
        b := Burst(this._nextBurstId++)
        b.startTs := firstEv["ts"]
        b.startWall := this._NowTime()
        b.windowExe := firstEv["winExe"]
        b.windowTitle := firstEv["winTitle"]
        b.isReference := this.cfg["calibrationMode"]
        
        ; Include pre-roll
        if (!this.cfg["calibrationMode"]) {
            preStart := firstEv["ts"] - this.cfg["preRollMs"]
            pre := this._ring.GetSince(preStart)
            
            for ev in pre {
                if (ev["ts"] < firstEv["ts"]) {
                    ev2 := ev.Clone()
                    ev2["preroll"] := true
                    b.AddEvent(ev2)
                }
            }
        }
        
        this._active := b
        this._UpdateLive()
    }
    
    _CloseActive(reason) {
        b := this._active
        if !b {
            return
        }
        
        b.endTs := A_TickCount
        b.closeReason := reason
        b.FinalizeSignature()
        
        ; Match against reference patterns
        this._MatchAgainstPatterns(b)
        
        ; Assign to cluster
        this._clusters.AddBurst(b)
        
        ; If this is a reference pattern from calibration, add to library
        if (b.isReference) {
            if (b.name = "") {
                b.name := "Calibration_" b.id
            }
            this._referencePatterns[b.name] := b
        }
        
        this._bursts.Push(b)
        this._active := 0
        
        this._AppendBurstToJsonl(b)
        this._RefreshBurstLV()
        this._RefreshPatternLV()
        this._RefreshClusterLV()
        this._UpdateLive()
        this._UpdateUiStatus()
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; FILE OUTPUT
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _AppendBurstToJsonl(burst) {
        path := this.cfg["logDir"] "\bursts.jsonl"
        try {
            FileAppend(burst.ToJsonLine() "`r`n", path, "UTF-8")
        }
    }
    
    _WriteSessionSummary(forceExport := false) {
        if (this._bursts.Length = 0 && !forceExport) {
            return
        }
        
        try DirCreate(this.cfg["logDir"])
        
        ; Export patterns
        pPath := this.cfg["logDir"] "\patterns.csv"
        try FileDelete(pPath)
        
        FileAppend("name,category,fingerprint,keys,clicks,move_in,description,tags`r`n", pPath, "UTF-8")
        for name, b in this._referencePatterns {
            FileAppend(
                this._Csv(name) "," 
                . this._Csv(b.category) ","
                . this._Csv(b.GetFingerprint()) ","
                . b.keyCount ","
                . b.clickCount ","
                . Round(b.moveIn, 4) ","
                . this._Csv(b.description) ","
                . this._Csv(b.GetTagsString()) "`r`n",
                pPath, "UTF-8"
            )
        }
        
        ; Export bursts with labels
        bPath := this.cfg["logDir"] "\bursts_labeled.csv"
        try FileDelete(bPath)
        
        FileAppend("id,name,category,start_wall,duration_ms,window_exe,keys,clicks,move_in,fingerprint,similar_to,similar_score,is_reference,tags`r`n", bPath, "UTF-8")
        for b in this._bursts {
            FileAppend(
                b.id ","
                . this._Csv(b.name) ","
                . this._Csv(b.category) ","
                . this._Csv(b.startWall) ","
                . b.DurationMs() ","
                . this._Csv(b.windowExe) ","
                . b.keyCount ","
                . b.clickCount ","
                . Round(b.moveIn, 4) ","
                . this._Csv(b.GetFingerprint()) ","
                . this._Csv(b.similarTo) ","
                . Round(b.similarScore, 3) ","
                . (b.isReference ? "1" : "0") ","
                . this._Csv(b.GetTagsString()) "`r`n",
                bPath, "UTF-8"
            )
        }
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; HELPERS
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    _FindBurstById(id) {
        for b in this._bursts {
            if (b.id = id) {
                return b
            }
        }
        return 0
    }
    
    _NowTime() {
        return FormatTime(, "HH:mm:ss")
    }
    
    _SafeWinTitle() {
        try {
            return WinGetTitle("A")
        } catch {
            return ""
        }
    }
    
    _SafeWinExe() {
        try {
            return WinGetProcessName("A")
        } catch {
            return ""
        }
    }
    
    _CurrentMods() {
        mods := []
        if GetKeyState("LControl", "P") || GetKeyState("RControl", "P") {
            mods.Push("Ctrl")
        }
        if GetKeyState("LShift", "P") || GetKeyState("RShift", "P") {
            mods.Push("Shift")
        }
        if GetKeyState("LAlt", "P") || GetKeyState("RAlt", "P") {
            mods.Push("Alt")
        }
        if GetKeyState("LWin", "P") || GetKeyState("RWin", "P") {
            mods.Push("Win")
        }
        return mods
    }
    
    _ChordString(keyName, mods) {
        base := keyName
        
        if (base = "LShift" || base = "RShift") {
            base := "Shift"
        } else if (base = "LControl" || base = "RControl") {
            base := "Ctrl"
        } else if (base = "LAlt" || base = "RAlt") {
            base := "Alt"
        } else if (base = "LWin" || base = "RWin") {
            base := "Win"
        }
        
        parts := []
        for m in mods {
            if (m != base) {
                parts.Push(m)
            }
        }
        parts.Push(base)
        
        s := ""
        for i, p in parts {
            s .= (i = 1 ? "" : "+") . p
        }
        return s
    }
    
    _Csv(s) {
        s := "" . s
        if InStr(s, ",") || InStr(s, "`r") || InStr(s, "`n") || InStr(s, '"') {
            return '"' . StrReplace(s, '"', '""') . '"'
        }
        return s
    }
    
    _ToFloat(s, fallback) {
        try {
            return s + 0.0
        } catch {
            return fallback
        }
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; BURST CLASS - Enhanced with labeling and fingerprinting
; ══════════════════════════════════════════════════════════════════════════════════════════════════

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
        this.clusterId := 0
        this.clusterScore := 0.0
        this._gaps := []
        this._sigParts := []
        this.signature := ""
        
        ; NEW: Labeling properties
        this.name := ""
        this.category := ""
        this.description := ""
        this._tags := []
        this.isReference := false
        
        ; NEW: Pattern matching
        this.similarTo := ""
        this.similarScore := 0.0
        this._fingerprintCache := ""
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; LABELING METHODS
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    GetTagsString() {
        if (this._tags.Length = 0) {
            return ""
        }
        
        s := ""
        for i, t in this._tags {
            s .= (i = 1 ? "" : ", ") . t
        }
        return s
    }
    
    SetTagsFromString(tagStr) {
        this._tags := []
        
        if (tagStr = "") {
            return
        }
        
        parts := StrSplit(tagStr, ",")
        for p in parts {
            p := Trim(p)
            if (p != "") {
                this._tags.Push(p)
            }
        }
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; FINGERPRINTING
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; A fingerprint captures the SEQUENCE of actions, ignoring timing.
    ; This allows matching slow calibration recordings to fast real-world usage.
    
    GetFingerprint() {
        if (this._fingerprintCache != "") {
            return this._fingerprintCache
        }
        
        tokens := this.GetFingerprintTokens()
        
        if (tokens.Length = 0) {
            this._fingerprintCache := "<empty>"
            return this._fingerprintCache
        }
        
        ; Take first N tokens for display
        maxShow := 8
        fp := ""
        i := 1
        while (i <= tokens.Length && i <= maxShow) {
            fp .= (i = 1 ? "" : " ") . tokens[i]
            i += 1
        }
        
        if (tokens.Length > maxShow) {
            fp .= " +" . (tokens.Length - maxShow) . "more"
        }
        
        this._fingerprintCache := fp
        return this._fingerprintCache
    }
    
    GetFingerprintTokens() {
        ; Extract action tokens (ignoring timing, mouse movements)
        tokens := []
        
        for ev in this.events {
            if ev.Has("preroll") && ev["preroll"] {
                continue  ; Skip pre-roll events
            }
            
            k := ev["kind"]
            
            if (k = "keyDown") {
                ; Include key chords
                tok := "K:" . (ev.Has("chord") ? ev["chord"] : ev["keyName"])
                tokens.Push(tok)
            }
            else if (k = "mouseDown") {
                ; Include button clicks
                tokens.Push("C:" . ev["button"])
            }
            else if (k = "wheel") {
                tokens.Push("W:" . (ev["wheelDelta"] > 0 ? "Up" : "Down"))
            }
            ; Mouse moves and key ups are ignored for fingerprinting
        }
        
        return tokens
    }
    
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    ; EXISTING METHODS (from v1)
    ; ─────────────────────────────────────────────────────────────────────────────────────────────
    
    AddEvent(ev) {
        if (this.lastTs) {
            gap := ev["ts"] - this.lastTs
            if (gap >= 0 && gap <= 60000) {
                this._gaps.Push(gap)
            }
        }
        
        this.events.Push(ev)
        this.lastTs := ev["ts"]
        this.lastKind := ev["kind"]
        this.lastDetail := this._EventShort(ev)
        
        ; Clear fingerprint cache when events change
        this._fingerprintCache := ""
        
        k := ev["kind"]
        
        if (k = "keyDown") {
            this.keyCount += 1
            if ev.Has("chord") {
                this._sigParts.Push("K:" . ev["chord"])
            }
        } else if (k = "mouseDown") {
            this.clickCount += 1
            this._sigParts.Push("M:" . ev["button"] . "Down")
        } else if (k = "mouseUp") {
            this._sigParts.Push("M:" . ev["button"] . "Up")
        } else if (k = "wheel") {
            this.wheelCount += 1
            this._sigParts.Push("W:" . (ev["wheelDelta"] > 0 ? "Up" : "Down"))
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
        
        if (k = "keyDown") {
            return ev.Has("chord") ? ev["chord"] : ev["keyName"]
        }
        if (k = "keyUp") {
            return ev["keyName"]
        }
        if (k = "mouseDown" || k = "mouseUp") {
            return ev["button"] . " @ " . ev["x"] . "," . ev["y"]
        }
        if (k = "wheel") {
            return "wheel " . (ev["wheelDelta"] > 0 ? "up" : "down")
        }
        if (k = "mouseMove") {
            return ev["x"] . "," . ev["y"]
        }
        return k
    }
    
    DurationMs() {
        if (this.endTs) {
            return this.endTs - this.startTs
        }
        if (this.lastTs) {
            return this.lastTs - this.startTs
        }
        return 0
    }
    
    DynamicIdleThreshold(idleMinMs, idleFactor) {
        if (this._gaps.Length = 0) {
            return idleMinMs
        }
        
        sum := 0
        for g in this._gaps {
            sum += g
        }
        
        avg := sum / this._gaps.Length
        th := Max(idleMinMs, Round(avg * idleFactor))
        return th
    }
    
    FinalizeSignature() {
        n := Min(18, this._sigParts.Length)
        sig := this.windowExe
        
        if (sig = "") {
            sig := "<noexe>"
        }
        
        sig .= " | "
        
        for i, p in this._sigParts {
            if (i > n) {
                break
            }
            sig .= (i = 1 ? "" : " ") . p
        }
        
        if (n = 0) {
            sig .= "<no-input>"
        }
        
        this.signature := sig
    }
    
    Describe() {
        s := "Burst #" . this.id . "`r`n"
            . "Name: " . (this.name != "" ? this.name : "(unnamed)") . "`r`n"
            . "Category: " . (this.category != "" ? this.category : "(none)") . "`r`n"
            . "Reference: " . (this.isReference ? "YES" : "no") . "`r`n"
            . "─────────────────────────────────`r`n"
            . "Start: " . this.startWall . "`r`n"
            . "Duration: " . this.DurationMs() . "ms`r`n"
            . "Window: " . this.windowExe . "`r`n"
            . "Keys: " . this.keyCount . "  Clicks: " . this.clickCount . "  Wheel: " . this.wheelCount . "`r`n"
            . "Move: " . Round(this.moveIn, 3) . " in`r`n"
            . "Fingerprint: " . this.GetFingerprint() . "`r`n"
        
        if (this.similarTo != "") {
            s .= "Similar to: " . this.similarTo . " (" . Round(this.similarScore * 100) . "%)`r`n"
        }
        
        if (this.description != "") {
            s .= "`r`nDescription: " . this.description . "`r`n"
        }
        
        return s
    }
    
    ToJsonLine() {
        j := "{"
        j .= '"id":' . this.id
        j .= ',"name":' . JsonStr(this.name)
        j .= ',"category":' . JsonStr(this.category)
        j .= ',"isReference":' . (this.isReference ? "true" : "false")
        j .= ',"startWall":' . JsonStr(this.startWall)
        j .= ',"durationMs":' . this.DurationMs()
        j .= ',"windowExe":' . JsonStr(this.windowExe)
        j .= ',"keys":' . this.keyCount
        j .= ',"clicks":' . this.clickCount
        j .= ',"wheel":' . this.wheelCount
        j .= ',"moveIn":' . Round(this.moveIn, 6)
        j .= ',"fingerprint":' . JsonStr(this.GetFingerprint())
        j .= ',"similarTo":' . JsonStr(this.similarTo)
        j .= ',"similarScore":' . Round(this.similarScore, 3)
        j .= ',"tags":' . JsonStr(this.GetTagsString())
        j .= ',"events":['
        
        maxEvents := 500
        start := Max(1, this.events.Length - maxEvents)
        first := true
        
        i := start
        while (i <= this.events.Length) {
            ev := this.events[i]
            if !first {
                j .= ","
            }
            first := false
            j .= EventToJson(ev)
            i += 1
        }
        
        j .= "]}"
        return j
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; CLUSTER ENGINE (unchanged from v1)
; ══════════════════════════════════════════════════════════════════════════════════════════════════

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
        for c in this._clusters {
            if (c.id = id) {
                return c
            }
        }
        return 0
    }
    
    AllSorted(mode := "avg_desc") {
        arr := []
        for c in this._clusters {
            arr.Push(c)
        }
        
        if (arr.Length <= 1) {
            return arr
        }
        
        swapped := true
        while swapped {
            swapped := false
            i := 1
            while (i < arr.Length) {
                a := arr[i]
                b := arr[i + 1]
                aKey := (mode = "count_desc") ? a.count : a.stats.Mean()
                bKey := (mode = "count_desc") ? b.count : b.stats.Mean()
                
                if (bKey > aKey) {
                    tmp := arr[i]
                    arr[i] := arr[i + 1]
                    arr[i + 1] := tmp
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
        core := cluster.CoreTokenSet()
        
        if (core.Count = 0) {
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
            if bSet.Has(k) {
                inter += 1
            }
            union += 1
        }
        
        for k, _ in bSet {
            if !aSet.Has(k) {
                union += 1
            }
        }
        
        if (union <= 0) {
            return 0.0
        }
        
        return inter / union
    }
    
    _TokensFromBurst(b) {
        s := b.signature
        p := InStr(s, "|")
        tail := (p ? Trim(SubStr(s, p + 1)) : Trim(s))
        
        parts := StrSplit(tail, " ")
        set := Map()
        
        for tok in parts {
            tok := Trim(tok)
            
            if (tok = "" || tok = "<no-input>") {
                continue
            }
            
            if (SubStr(tok, 1, 2) = "M:" && InStr(tok, "Up")) {
                continue
            }
            
            if InStr(tok, "@") || InStr(tok, ",") {
                continue
            }
            
            set[tok] := true
        }
        
        return set
    }
    
    _Clamp01(x) {
        try {
            x := x + 0.0
        } catch {
            x := 0.0
        }
        
        if (x < 0) {
            return 0.0
        }
        if (x > 1) {
            return 1.0
        }
        
        return x
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; CLUSTER CLASS
; ══════════════════════════════════════════════════════════════════════════════════════════════════

class Cluster {
    __New(id, tokenMinFrac, maxCoreTokens) {
        this.id := id
        this.count := 0
        this.stats := OnlineStats()
        this._tokenFreq := Map()
        this._winCounts := Map()
        
        this.avgKeys := 0.0
        this.avgClicks := 0.0
        this.avgMoveIn := 0.0
        
        this.tokenMinFrac := tokenMinFrac
        this.maxCoreTokens := maxCoreTokens
    }
    
    AddMember(b, tokenSet, exe) {
        this.count += 1
        this.stats.Add(b.DurationMs())
        
        this.avgKeys += (b.keyCount - this.avgKeys) / this.count
        this.avgClicks += (b.clickCount - this.avgClicks) / this.count
        this.avgMoveIn += (b.moveIn - this.avgMoveIn) / this.count
        
        for tok, _ in tokenSet {
            this._tokenFreq[tok] := (this._tokenFreq.Has(tok) ? this._tokenFreq[tok] : 0) + 1
        }
        
        this._winCounts[exe] := (this._winCounts.Has(exe) ? this._winCounts[exe] : 0) + 1
    }
    
    HasWindow(exe) => this._winCounts.Has(exe)
    
    MostCommonWindow() {
        best := ""
        bestC := -1
        
        for w, c in this._winCounts {
            if (c > bestC) {
                bestC := c
                best := w
            }
        }
        
        return best
    }
    
    AllTokenSet() {
        s := Map()
        for tok, _ in this._tokenFreq {
            s[tok] := true
        }
        return s
    }
    
    CoreTokenSet() {
        s := Map()
        
        if (this.count <= 0) {
            return s
        }
        
        minCount := Ceil(this.count * this.tokenMinFrac)
        
        for tok, c in this._tokenFreq {
            if (c >= minCount) {
                s[tok] := true
            }
        }
        
        if (s.Count > this.maxCoreTokens) {
            ranked := []
            for tok, c in this._tokenFreq {
                ranked.Push({t: tok, c: c})
            }
            
            swapped := true
            while swapped {
                swapped := false
                i := 1
                while (i < ranked.Length) {
                    if (ranked[i + 1].c > ranked[i].c) {
                        tmp := ranked[i]
                        ranked[i] := ranked[i + 1]
                        ranked[i + 1] := tmp
                        swapped := true
                    }
                    i += 1
                }
            }
            
            limited := Map()
            i := 1
            while (i <= ranked.Length && limited.Count < this.maxCoreTokens) {
                tok := ranked[i].t
                if s.Has(tok) {
                    limited[tok] := true
                }
                i += 1
            }
            
            return limited
        }
        
        return s
    }
    
    CoreTokensString() {
        core := this.CoreTokenSet()
        
        if (core.Count = 0) {
            return "<none>"
        }
        
        arr := []
        for tok, _ in core {
            arr.Push(tok)
        }
        
        ; Sort using StrCompare
        swapped := true
        while swapped {
            swapped := false
            i := 1
            while (i < arr.Length) {
                if (StrCompare(arr[i + 1], arr[i], true) < 0) {
                    tmp := arr[i]
                    arr[i] := arr[i + 1]
                    arr[i + 1] := tmp
                    swapped := true
                }
                i += 1
            }
        }
        
        out := ""
        for i, tok in arr {
            out .= (i = 1 ? "" : " ") . tok
        }
        
        return out
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; ONLINE STATS CLASS
; ══════════════════════════════════════════════════════════════════════════════════════════════════

class OnlineStats {
    __New() {
        this.n := 0
        this._meanVal := 0.0
        this.m2 := 0.0
        this.min := 2147483647
        this.max := 0
    }
    
    Add(x) {
        this.n += 1
        
        if (x < this.min) {
            this.min := x
        }
        if (x > this.max) {
            this.max := x
        }
        
        delta := x - this._meanVal
        this._meanVal += delta / this.n
        delta2 := x - this._meanVal
        this.m2 += delta * delta2
    }
    
    Mean() {
        return (this.n ? this._meanVal : 0.0)
    }
    
    StdDev() {
        if (this.n < 2) {
            return 0.0
        }
        
        variance := this.m2 / (this.n - 1)
        if (variance < 0) {
            variance := 0
        }
        
        return Sqrt(variance)
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; EVENT RING BUFFER
; ══════════════════════════════════════════════════════════════════════════════════════════════════

class EventRingBuffer {
    __New(capacity) {
        this.cap := capacity
        this.arr := []
    }
    
    Clear() {
        this.arr := []
    }
    
    Push(ev) {
        this.arr.Push(ev)
        
        if (this.arr.Length > this.cap) {
            this.arr.RemoveAt(1)
        }
    }
    
    GetSince(tsMin) {
        out := []
        
        for ev in this.arr {
            if (ev["ts"] >= tsMin) {
                out.Push(ev)
            }
        }
        
        return out
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; LOW LEVEL HOOK MANAGER
; ══════════════════════════════════════════════════════════════════════════════════════════════════

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
        if (this.hKey || this.hMouse) {
            return
        }
        
        this.cbKey := CallbackCreate(ObjBindMethod(this, "_KbdProc"), "Fast", 3)
        this.cbMouse := CallbackCreate(ObjBindMethod(this, "_MouseProc"), "Fast", 3)
        
        hMod := DllCall("GetModuleHandleW", "Ptr", 0, "Ptr")
        
        this.hKey := DllCall("SetWindowsHookExW", "Int", 13, "Ptr", this.cbKey, "Ptr", hMod, "UInt", 0, "Ptr")
        this.hMouse := DllCall("SetWindowsHookExW", "Int", 14, "Ptr", this.cbMouse, "Ptr", hMod, "UInt", 0, "Ptr")
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
            
            kind := ""
            if (wParam = 0x0100 || wParam = 0x0104) {
                kind := "keyDown"
            } else if (wParam = 0x0101 || wParam = 0x0105) {
                kind := "keyUp"
            }
            
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
            
            if (wParam = 0x0200) {
                if (this._lastMoveX != "") {
                    dx := x - this._lastMoveX
                    dy := y - this._lastMoveY
                    
                    if ((now - this._lastMoveTs) < this.mouseSampleMs && (Abs(dx) + Abs(dy)) < this.mouseMinPx) {
                        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
                    }
                }
                
                dist := 0.0
                if (this._lastMoveX != "") {
                    dist := Sqrt((x - this._lastMoveX) ** 2 + (y - this._lastMoveY) ** 2)
                }
                
                this._lastMoveTs := now
                this._lastMoveX := x
                this._lastMoveY := y
                
                ev := Map("ts", now, "kind", "mouseMove", "x", x, "y", y, "distPx", dist)
                this.onEvent.Call(ev)
                
            } else if (wParam = 0x0201 || wParam = 0x0202 || wParam = 0x0204 || wParam = 0x0205 
                    || wParam = 0x0207 || wParam = 0x0208 || wParam = 0x020B || wParam = 0x020C) {
                button := ""
                if (wParam = 0x0201 || wParam = 0x0202) {
                    button := "LButton"
                } else if (wParam = 0x0204 || wParam = 0x0205) {
                    button := "RButton"
                } else if (wParam = 0x0207 || wParam = 0x0208) {
                    button := "MButton"
                } else {
                    button := "XButton"
                }
                
                kind := ""
                if (wParam = 0x0201 || wParam = 0x0204 || wParam = 0x0207 || wParam = 0x020B) {
                    kind := "mouseDown"
                } else {
                    kind := "mouseUp"
                }
                
                if (button = "XButton") {
                    xbtn := (mouseData >> 16) & 0xFFFF
                    button := (xbtn = 1) ? "XButton1" : "XButton2"
                }
                
                ev := Map("ts", now, "kind", kind, "x", x, "y", y, "button", button)
                this.onEvent.Call(ev)
                
            } else if (wParam = 0x020A || wParam = 0x020E) {
                delta := (mouseData >> 16) & 0xFFFF
                
                if (delta & 0x8000) {
                    delta := delta - 0x10000
                }
                
                ev := Map(
                    "ts", now,
                    "kind", "wheel",
                    "x", x, 
                    "y", y,
                    "wheelDelta", delta,
                    "wheelHorizontal", (wParam = 0x020E)
                )
                
                this.onEvent.Call(ev)
            }
        }
        
        return DllCall("CallNextHookEx", "Ptr", 0, "Int", nCode, "Ptr", wParam, "Ptr", lParam, "Ptr")
    }
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; JSON HELPERS
; ══════════════════════════════════════════════════════════════════════════════════════════════════

JsonStr(s) {
    s := "" . s
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    return '"' . s . '"'
}

EventToJson(ev) {
    j := "{"
    j .= '"ts":' . ev["ts"]
    j .= ',"kind":' . JsonStr(ev["kind"])
    
    if ev.Has("keyName") {
        j .= ',"keyName":' . JsonStr(ev["keyName"])
    }
    if ev.Has("vk") {
        j .= ',"vk":' . ev["vk"]
    }
    if ev.Has("chord") {
        j .= ',"chord":' . JsonStr(ev["chord"])
    }
    if ev.Has("x") {
        j .= ',"x":' . ev["x"]
    }
    if ev.Has("y") {
        j .= ',"y":' . ev["y"]
    }
    if ev.Has("button") {
        j .= ',"button":' . JsonStr(ev["button"])
    }
    if ev.Has("wheelDelta") {
        j .= ',"wheelDelta":' . ev["wheelDelta"]
    }
    if ev.Has("distPx") {
        j .= ',"distPx":' . Round(ev["distPx"], 4)
    }
    if ev.Has("winExe") {
        j .= ',"winExe":' . JsonStr(ev["winExe"])
    }
    if ev.Has("preroll") {
        j .= ',"preroll":' . (ev["preroll"] ? "true" : "false")
    }
    
    return j . "}"
}

; ══════════════════════════════════════════════════════════════════════════════════════════════════
; END OF SCRIPT
; ══════════════════════════════════════════════════════════════════════════════════════════════════

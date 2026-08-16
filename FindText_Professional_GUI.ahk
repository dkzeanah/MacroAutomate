/*
================================================================================
FINDTEXT.AHK - PROFESSIONAL GUI WRAPPER
================================================================================

Modern, user-friendly interface for FindText.ahk library

FEATURES:
✓ Visual pattern capture and preview
✓ Real-time search visualization
✓ Pattern library management
✓ Office automation (OCR, Excel export, monitoring)
✓ Comprehensive benchmarking
✓ All FindText parameters exposed
✓ Modern, clean interface

REQUIREMENTS:
- AutoHotkey v2.0+
- FindText.ahk (in same directory)

================================================================================
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; Include FindText library
#Include "FindText.ahk"

; ============================================================================
; MAIN APPLICATION CLASS
; ============================================================================

class FindTextGUI {
    
    __New() {
        ; Initialize FindText object
        this.ft := FindText()
        
        ; Application state
        this.isSearching := false
        this.cancelRequested := false
        this.monitorTimer := 0
        this.lastMonitorState := ""
        
        ; Bitmap handles for preview
        this.hbmCaptured := 0
        this.hbmScaled := 0
        
        ; Visual overlays
        this.scanOverlays := []
        this.matchBoxes := []
        
        ; Configuration with sensible defaults
        this.cfg := Map(
            "x1", 0,
            "y1", 0,
            "x2", A_ScreenWidth - 1,
            "y2", A_ScreenHeight - 1,
            "err1", 0.1,
            "err0", 0.1,
            "findAll", 0,
            "screenShot", 1,
            "pauseOnMatch", 0,
            "visualize", 1,
            "tileSize", 64,
            "scanSpeed", 50,
            "exportFormat", "CSV",
            "monitorInterval", 5,
            "ocrEnabled", 0
        )
        
        ; Pattern library
        this.patterns := []
        this.currentPattern := ""
        this.currentPatternInfo := Map("w", 0, "h", 0)
        
        ; Build GUI
        this.BuildGUI()
        
        ; Load saved state
        this.LoadState()
        
        ; Initialize
        this.UpdatePreview()
        this.RefreshPatternList()
        this.UpdateStatusText()
    }
    
    ; ========================================================================
    ; GUI CONSTRUCTION
    ; ========================================================================
    
    BuildGUI() {
        ; Main window
        this.gui := Gui("+Resize", "FindText Professional - GUI Wrapper")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.BackColor := "0xF5F5F5"
        
        ; ====================================================================
        ; TOP: QUICK ACTIONS BAR
        ; ====================================================================
        
        this.gui.Add("Progress", "x0 y0 w1400 h60 Background0xE8F4FF")
        
        this.gui.SetFont("s11 Bold")
        this.gui.Add("Text", "x20 y10 c0x0078D4", "⚡ Quick Actions")
        this.gui.SetFont("s9", "Segoe UI")
        
        this.btnQuickCapture := this.gui.Add("Button", "x20 y30 w130 h25", "📸 Quick Capture")
        this.btnQuickCapture.OnEvent("Click", (*) => this.QuickCapture())
        
        this.btnQuickSearch := this.gui.Add("Button", "x160 y30 w130 h25", "🔍 Quick Search")
        this.btnQuickSearch.OnEvent("Click", (*) => this.StartSearch())
        
        this.btnQuickOCR := this.gui.Add("Button", "x300 y30 w130 h25", "📝 Quick OCR")
        this.btnQuickOCR.OnEvent("Click", (*) => this.QuickOCR())
        
        this.btnExport := this.gui.Add("Button", "x440 y30 w130 h25", "📊 Export Results")
        this.btnExport.OnEvent("Click", (*) => this.ExportResults())
        
        this.btnMonitor := this.gui.Add("Button", "x580 y30 w130 h25", "⏰ Start Monitor")
        this.btnMonitor.OnEvent("Click", (*) => this.ToggleMonitoring())
        
        this.btnHelp := this.gui.Add("Button", "x720 y30 w130 h25", "❓ Quick Help")
        this.btnHelp.OnEvent("Click", (*) => this.ShowQuickHelp())
        
        ; Status indicator
        this.statusIndicator := this.gui.Add("Progress", "x880 y32 w15 h20 Background0x107C10")
        this.statusText := this.gui.Add("Text", "x900 y33 w200", "Ready")
        
        ; ====================================================================
        ; LEFT PANEL: CONTROLS
        ; ====================================================================
        
        yStart := 75
        leftW := 520
        
        ; --- PATTERN SECTION ---
        
        this.gui.Add("GroupBox", "x10 y" yStart " w" leftW " h180", "Pattern")
        
        this.gui.Add("Text", "x20 y" (yStart + 20), "FindText Pattern String:")
        this.edPattern := this.gui.Add("Edit", "x20 y" (yStart + 40) " w" (leftW - 20) " r4")
        this.edPattern.SetFont("s9", "Consolas")
        this.edPattern.OnEvent("Change", (*) => this.OnPatternChange())
        
        this.btnOpenFindText := this.gui.Add("Button", "x20 y" (yStart + 125) " w160 h30", "Open FindText GUI")
        this.btnOpenFindText.OnEvent("Click", (*) => this.ft.Gui("Show"))
        
        this.btnLoadPattern := this.gui.Add("Button", "x190 y" (yStart + 125) " w80 h30", "📂 Load")
        this.btnLoadPattern.OnEvent("Click", (*) => this.LoadPatternFromFile())
        
        this.btnSavePattern := this.gui.Add("Button", "x280 y" (yStart + 125) " w80 h30", "💾 Save")
        this.btnSavePattern.OnEvent("Click", (*) => this.SavePatternToFile())
        
        this.btnClearPattern := this.gui.Add("Button", "x370 y" (yStart + 125) " w80 h30", "🗑 Clear")
        this.btnClearPattern.OnEvent("Click", (*) => (this.edPattern.Value := "", this.OnPatternChange()))
        
        this.txtPatternInfo := this.gui.Add("Text", "x20 y" (yStart + 160) " w" (leftW - 20), "No pattern loaded")
        
        ; --- SEARCH REGION SECTION ---
        
        yStart += 190
        this.gui.Add("GroupBox", "x10 y" yStart " w" leftW " h120", "Search Region")
        
        this.gui.Add("Text", "x20 y" (yStart + 25), "X1:")
        this.edX1 := this.gui.Add("Edit", "x50 y" (yStart + 22) " w70 Number", "0")
        
        this.gui.Add("Text", "x130 y" (yStart + 25), "Y1:")
        this.edY1 := this.gui.Add("Edit", "x160 y" (yStart + 22) " w70 Number", "0")
        
        this.gui.Add("Text", "x240 y" (yStart + 25), "X2:")
        this.edX2 := this.gui.Add("Edit", "x270 y" (yStart + 22) " w70 Number", A_ScreenWidth)
        
        this.gui.Add("Text", "x350 y" (yStart + 25), "Y2:")
        this.edY2 := this.gui.Add("Edit", "x380 y" (yStart + 22) " w70 Number", A_ScreenHeight)
        
        this.btnPickRegion := this.gui.Add("Button", "x20 y" (yStart + 55) " w230 h30", "🎯 Pick Region (2 Clicks)")
        this.btnPickRegion.OnEvent("Click", (*) => this.PickRegionTwoClicks())
        
        this.btnFullScreen := this.gui.Add("Button", "x260 y" (yStart + 55) " w115 h30", "🖥 Full Screen")
        this.btnFullScreen.OnEvent("Click", (*) => this.SetFullScreen())
        
        this.btnApplyRegion := this.gui.Add("Button", "x385 y" (yStart + 55) " w125 h30", "✓ Apply & Preview")
        this.btnApplyRegion.OnEvent("Click", (*) => this.ApplyRegion())
        
        this.txtRegionInfo := this.gui.Add("Text", "x20 y" (yStart + 92) " w" (leftW - 20), "Region: Full Screen")
        
        ; --- SEARCH PARAMETERS SECTION ---
        
        yStart += 130
        this.gui.Add("GroupBox", "x10 y" yStart " w" leftW " h160", "Search Parameters")
        
        this.gui.Add("Text", "x20 y" (yStart + 25), "Text Tolerance (err1):")
        this.gui.Add("Text", "x480 y" (yStart + 25) " w30 Right", "10%")
        this.txtErr1 := this.gui.Add("Text", "x480 y" (yStart + 25) " w30 Right", "10%")
        this.slErr1 := this.gui.Add("Slider", "x20 y" (yStart + 45) " w" (leftW - 30) " Range0-50 TickInterval5", 10)
        this.slErr1.OnEvent("Change", (*) => this.UpdateErr1Text())
        
        this.gui.Add("Text", "x20 y" (yStart + 75), "Background Tolerance (err0):")
        this.txtErr0 := this.gui.Add("Text", "x480 y" (yStart + 75) " w30 Right", "10%")
        this.slErr0 := this.gui.Add("Slider", "x20 y" (yStart + 95) " w" (leftW - 30) " Range0-50 TickInterval5", 10)
        this.slErr0.OnEvent("Change", (*) => this.UpdateErr0Text())
        
        this.cbFindAll := this.gui.Add("Checkbox", "x20 y" (yStart + 125), "Find All Matches")
        this.cbScreenShot := this.gui.Add("Checkbox", "x160 y" (yStart + 125) . " Checked", "New Screenshot")
        this.cbPauseOnMatch := this.gui.Add("Checkbox", "x310 y" (yStart + 125), "Pause When Found")
        
        ; --- PATTERN LIBRARY SECTION ---
        
        yStart += 170
        this.gui.Add("GroupBox", "x10 y" yStart " w" leftW " h180", "Pattern Library")
        
        this.lvPatterns := this.gui.Add("ListView", "x20 y" (yStart + 20) " w" (leftW - 20) " h110 Grid", ["Name", "Size", "Date"])
        this.lvPatterns.ModifyCol(1, 240)
        this.lvPatterns.ModifyCol(2, 100)
        this.lvPatterns.ModifyCol(3, 150)
        this.lvPatterns.OnEvent("DoubleClick", (*) => this.LoadPatternFromLibrary())
        
        this.btnLoadLib := this.gui.Add("Button", "x20 y" (yStart + 140) " w120 h25", "Load Selected")
        this.btnLoadLib.OnEvent("Click", (*) => this.LoadPatternFromLibrary())
        
        this.btnDeleteLib := this.gui.Add("Button", "x150 y" (yStart + 140) " w120 h25", "Delete Selected")
        this.btnDeleteLib.OnEvent("Click", (*) => this.DeleteFromLibrary())
        
        this.btnRefreshLib := this.gui.Add("Button", "x280 y" (yStart + 140) " w120 h25", "🔄 Refresh")
        this.btnRefreshLib.OnEvent("Click", (*) => this.RefreshPatternList())
        
        this.btnOpenLibFolder := this.gui.Add("Button", "x410 y" (yStart + 140) " w100 h25", "📁 Open Folder")
        this.btnOpenLibFolder.OnEvent("Click", (*) => this.OpenLibraryFolder())
        
        ; --- OFFICE FEATURES SECTION ---
        
        yStart += 190
        this.gui.Add("GroupBox", "x10 y" yStart " w" leftW " h120", "Office Features")
        
        this.gui.Add("Text", "x20 y" (yStart + 25), "Export Format:")
        this.ddExport := this.gui.Add("DropDownList", "x120 y" (yStart + 22) " w100", ["CSV", "Excel", "JSON"])
        this.ddExport.Choose(1)
        
        this.cbIncludeTimestamp := this.gui.Add("Checkbox", "x230 y" (yStart + 25) . " Checked", "Include Timestamp")
        
        this.gui.Add("Text", "x20 y" (yStart + 55), "Monitor Interval (sec):")
        this.edMonitorInterval := this.gui.Add("Edit", "x160 y" (yStart + 52) " w60 Number", "5")
        
        this.cbMonitorNotify := this.gui.Add("Checkbox", "x230 y" (yStart + 55) . " Checked", "Desktop Notifications")
        this.cbMonitorSound := this.gui.Add("Checkbox", "x380 y" (yStart + 55), "Sound Alerts")
        
        this.txtMonitorStatus := this.gui.Add("Text", "x20 y" (yStart + 85) " w" (leftW - 20) " Border Center", "Monitoring: Inactive")
        
        ; --- ACTION BUTTONS ---
        
        yStart += 130
        
        this.btnStart := this.gui.Add("Button", "x10 y" yStart " w250 h50", "🔍 START SEARCH")
        this.btnStart.OnEvent("Click", (*) => this.StartSearch())
        this.btnStart.SetFont("s11 Bold")
        
        this.btnStop := this.gui.Add("Button", "x270 y" yStart " w250 h50 Disabled", "⏹ STOP")
        this.btnStop.OnEvent("Click", (*) => this.StopSearch())
        this.btnStop.SetFont("s11")
        
        ; ====================================================================
        ; RIGHT PANEL: PREVIEW AND RESULTS
        ; ====================================================================
        
        rightX := leftW + 30
        rightW := 700
        
        ; --- PREVIEW SECTION ---
        
        this.gui.Add("GroupBox", "x" rightX " y75 w" rightW " h480", "Visual Preview & Live Visualization")
        
        this.txtPreviewInfo := this.gui.Add("Text", "x" (rightX + 10) " y95 w" (rightW - 20) " Center", 
            "Capture or select a region to see preview")
        
        this.picPreview := this.gui.Add("Picture", "x" (rightX + 10) " y115 w" (rightW - 20) " h435 Border")
        
        ; --- RESULTS TABS ---
        
        yStart := 565
        
        this.tabResults := this.gui.Add("Tab3", "x" rightX " y" yStart " w" rightW " h310", 
            ["Matches", "Metrics", "Log"])
        
        ; Matches Tab
        this.tabResults.UseTab(1)
        this.lvResults := this.gui.Add("ListView", "x" (rightX + 10) " y" (yStart + 30) " w" (rightW - 20) " h265 Grid", 
            ["#", "X", "Y", "Width", "Height", "Similarity"])
        this.lvResults.ModifyCol(1, 50)
        this.lvResults.ModifyCol(2, 80)
        this.lvResults.ModifyCol(3, 80)
        this.lvResults.ModifyCol(4, 80)
        this.lvResults.ModifyCol(5, 80)
        this.lvResults.ModifyCol(6, 120)
        
        ; Metrics Tab
        this.tabResults.UseTab(2)
        this.edMetrics := this.gui.Add("Edit", "x" (rightX + 10) " y" (yStart + 30) " w" (rightW - 20) " h265 ReadOnly Multi")
        this.edMetrics.SetFont("s9", "Consolas")
        this.edMetrics.Value := "Perform a search to see benchmark metrics."
        
        ; Log Tab
        this.tabResults.UseTab(3)
        this.edLog := this.gui.Add("Edit", "x" (rightX + 10) " y" (yStart + 30) " w" (rightW - 20) " h265 ReadOnly Multi")
        this.edLog.SetFont("s9", "Consolas")
        
        this.tabResults.UseTab()
        
        ; ====================================================================
        ; EVENTS
        ; ====================================================================
        
        this.gui.OnEvent("Close", (*) => this.OnClose())
        this.gui.OnEvent("Size", (*) => this.OnResize())
        
        ; Show GUI
        this.gui.Show("w1260 h900")
        
        this.Log("FindText Professional GUI started successfully")
        this.Log("Click 'Open FindText GUI' to capture patterns")
    }
    
    ; ========================================================================
    ; PATTERN MANAGEMENT
    ; ========================================================================
    
    QuickCapture() {
        /*
        Opens FindText capture GUI for quick pattern capture
        */
        this.Log("Opening FindText capture GUI...")
        this.ft.Gui("Show")
        
        ; Show help
        MsgBox("FindText Capture GUI opened!`n`n" .
               "1. Use the capture tools to select a pattern`n" .
               "2. Copy the pattern text`n" .
               "3. Paste it in the Pattern box`n" .
               "4. Click 'Apply & Preview'",
               "Quick Capture", "Iconi T3")
    }
    
    OnPatternChange() {
        /*
        Called when pattern text changes
        Updates pattern info and preview
        */
        pattern := Trim(this.edPattern.Value)
        
        if (pattern = "") {
            this.currentPattern := ""
            this.currentPatternInfo := Map("w", 0, "h", 0)
            this.txtPatternInfo.Value := "No pattern loaded"
            this.UpdateStatusText()
            return
        }
        
        this.currentPattern := pattern
        
        ; Parse pattern dimensions
        info := this.ParsePatternDims(pattern)
        this.currentPatternInfo := info
        
        ; Update info text
        if (info["w"] > 0 && info["h"] > 0) {
            this.txtPatternInfo.Value := "Pattern size: " . info["w"] . " x " . info["h"] . " pixels"
        } else {
            this.txtPatternInfo.Value := "Pattern loaded (size unknown)"
        }
        
        this.UpdateStatusText()
        this.UpdatePreview()
    }
    
    ParsePatternDims(pattern) {
        /*
        Extracts dimensions from FindText pattern string
        Format: *XXX$HEIGHT.WIDTH or similar
        */
        w := 0
        h := 0
        
        ; Try to extract height after $
        if RegExMatch(pattern, "\$(\d+)", &mH)
            h := Integer(mH[1])
        
        ; Try to extract width after W or .
        if RegExMatch(pattern, "W(\d+)", &mW)
            w := Integer(mW[1])
        else if RegExMatch(pattern, "\.(\d+)", &mW)
            w := Integer(mW[1])
        
        return Map("w", w, "h", h)
    }
    
    LoadPatternFromFile() {
        /*
        Loads pattern from text file
        */
        file := FileSelect(3, , "Load Pattern", "Text Files (*.txt)")
        if (!file)
            return
        
        try {
            pattern := FileRead(file)
            this.edPattern.Value := pattern
            this.OnPatternChange()
            this.Log("Pattern loaded from: " . file)
        } catch as err {
            MsgBox("Failed to load pattern: " . err.Message, "Error", "Icon!")
            this.Log("ERROR: Failed to load pattern")
        }
    }
    
    SavePatternToFile() {
        /*
        Saves current pattern to text file
        */
        pattern := Trim(this.edPattern.Value)
        if (pattern = "") {
            MsgBox("No pattern to save!", "Warning", "Icon!")
            return
        }
        
        file := FileSelect("S16", , "Save Pattern", "Text Files (*.txt)")
        if (!file)
            return
        
        if (!InStr(file, ".txt"))
            file .= ".txt"
        
        try {
            FileDelete(file)
            FileAppend(pattern, file)
            this.Log("Pattern saved to: " . file)
            MsgBox("Pattern saved successfully!", "Success", "Iconi T2")
        } catch as err {
            MsgBox("Failed to save pattern: " . err.Message, "Error", "Icon!")
            this.Log("ERROR: Failed to save pattern")
        }
    }
    
    RefreshPatternLibrary() {
        /*
        Refreshes pattern library list
        */
        this.lvPatterns.Delete()
        
        ; Create patterns directory if needed
        libDir := A_ScriptDir . "\Patterns"
        if (!DirExist(libDir)) {
            try DirCreate(libDir)
        }
        
        ; Scan for pattern files
        Loop Files, libDir . "\*.txt" {
            this.lvPatterns.Add(, A_LoopFileName, A_LoopFileSize . " bytes", A_LoopFileTimeModified)
        }
        
        this.Log("Pattern library refreshed: " . this.lvPatterns.GetCount() . " patterns")
    }
    
    LoadPatternFromLibrary() {
        /*
        Loads selected pattern from library
        */
        row := this.lvPatterns.GetNext()
        if (!row) {
            MsgBox("Select a pattern to load!", "Info", "Iconi")
            return
        }
        
        fileName := this.lvPatterns.GetText(row, 1)
        filePath := A_ScriptDir . "\Patterns\" . fileName
        
        try {
            pattern := FileRead(filePath)
            this.edPattern.Value := pattern
            this.OnPatternChange()
            this.Log("Pattern loaded from library: " . fileName)
        } catch as err {
            MsgBox("Failed to load pattern: " . err.Message, "Error", "Icon!")
            this.Log("ERROR: Failed to load pattern from library")
        }
    }
    
    DeleteFromLibrary() {
        /*
        Deletes selected pattern from library
        */
        row := this.lvPatterns.GetNext()
        if (!row) {
            MsgBox("Select a pattern to delete!", "Info", "Iconi")
            return
        }
        
        fileName := this.lvPatterns.GetText(row, 1)
        result := MsgBox("Delete pattern: " . fileName . "?", "Confirm Delete", "YesNo Icon!")
        
        if (result = "No")
            return
        
        filePath := A_ScriptDir . "\Patterns\" . fileName
        
        try {
            FileDelete(filePath)
            this.RefreshPatternList()
            this.Log("Pattern deleted: " . fileName)
        } catch as err {
            MsgBox("Failed to delete pattern: " . err.Message, "Error", "Icon!")
        }
    }
    
    OpenLibraryFolder() {
        /*
        Opens pattern library folder in Explorer
        */
        libDir := A_ScriptDir . "\Patterns"
        if (!DirExist(libDir)) {
            try DirCreate(libDir)
        }
        Run(libDir)
    }
    
    ; ========================================================================
    ; REGION MANAGEMENT
    ; ========================================================================
    
    PickRegionTwoClicks() {
        /*
        Interactive region selection with two clicks
        */
        this.Log("Pick region: Click TOP-LEFT, then BOTTOM-RIGHT")
        
        ; Hide GUI temporarily
        this.gui.Hide()
        
        CoordMode("Mouse", "Screen")
        
        ; Wait for first click
        ToolTip("Click TOP-LEFT corner...")
        KeyWait("LButton", "D")
        MouseGetPos(&x1, &y1)
        KeyWait("LButton", "U")
        
        ; Wait for second click
        ToolTip("Click BOTTOM-RIGHT corner...")
        Sleep(200)
        
        KeyWait("LButton", "D")
        MouseGetPos(&x2, &y2)
        KeyWait("LButton", "U")
        
        ToolTip()
        
        ; Show GUI again
        this.gui.Show()
        
        ; Set region
        this.edX1.Value := Min(x1, x2)
        this.edY1.Value := Min(y1, y2)
        this.edX2.Value := Max(x1, x2)
        this.edY2.Value := Max(y1, y2)
        
        this.ApplyRegion()
        
        this.Log("Region picked: (" . this.edX1.Value . "," . this.edY1.Value . ") to (" . 
                 this.edX2.Value . "," . this.edY2.Value . ")")
    }
    
    SetFullScreen() {
        /*
        Sets region to full screen
        */
        this.edX1.Value := 0
        this.edY1.Value := 0
        this.edX2.Value := A_ScreenWidth - 1
        this.edY2.Value := A_ScreenHeight - 1
        
        this.ApplyRegion()
        this.Log("Region set to full screen")
    }
    
    ApplyRegion() {
        /*
        Applies current region settings and updates preview
        */
        this.cfg["x1"] := Integer(this.edX1.Value)
        this.cfg["y1"] := Integer(this.edY1.Value)
        this.cfg["x2"] := Integer(this.edX2.Value)
        this.cfg["y2"] := Integer(this.edY2.Value)
        
        w := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        h := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        
        this.txtRegionInfo.Value := "Region: " . w . " x " . h . " pixels"
        
        this.UpdatePreview()
        this.UpdateStatusText()
        
        this.Log("Region applied: " . w . "x" . h)
    }
    
    ; ========================================================================
    ; VISUALIZATION
    ; ========================================================================
    
    UpdatePreview() {
        /*
        Updates preview image of search region
        */
        x := this.cfg["x1"]
        y := this.cfg["y1"]
        w := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        h := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        
        if (w < 10 || h < 10)
            return
        
        ; Get preview control size
        this.picPreview.GetPos(, , &pw, &ph)
        if (pw < 50 || ph < 50)
            return
        
        ; Cleanup old bitmaps
        this.CleanupBitmaps()
        
        ; Capture region
        this.hbmCaptured := this.CaptureScreenRegion(x, y, w, h)
        if (!this.hbmCaptured)
            return
        
        ; Scale to fit preview
        this.hbmScaled := this.ScaleBitmap(this.hbmCaptured, pw, ph)
        if (!this.hbmScaled)
            return
        
        ; Display
        this.picPreview.Value := "HBITMAP:*" . this.hbmScaled
        
        this.txtPreviewInfo.Value := "Preview: " . w . "x" . h . " → " . pw . "x" . ph . " (scaled)"
    }
    
    CaptureScreenRegion(x, y, w, h) {
        /*
        Captures screen region to HBITMAP
        */
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
        
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm)
        DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h,
                "Ptr", hdcScreen, "Int", x, "Int", y, "UInt", 0x00CC0020)
        
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        
        return hbm
    }
    
    ScaleBitmap(hbmSrc, newW, newH) {
        /*
        Scales bitmap to new dimensions
        */
        if (!hbmSrc)
            return 0
        
        ; Get source dimensions
        bm := Buffer(32, 0)
        DllCall("GetObject", "Ptr", hbmSrc, "Int", 32, "Ptr", bm)
        srcW := NumGet(bm, 4, "Int")
        srcH := NumGet(bm, 8, "Int")
        
        ; Create DCs
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcSrc := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hdcDst := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        
        ; Create destination bitmap
        hbmDst := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", newW, "Int", newH, "Ptr")
        
        ; Select bitmaps
        DllCall("SelectObject", "Ptr", hdcSrc, "Ptr", hbmSrc)
        DllCall("SelectObject", "Ptr", hdcDst, "Ptr", hbmDst)
        
        ; Set high quality scaling
        DllCall("SetStretchBltMode", "Ptr", hdcDst, "Int", 4)
        
        ; Scale
        DllCall("StretchBlt", "Ptr", hdcDst, "Int", 0, "Int", 0, "Int", newW, "Int", newH,
                "Ptr", hdcSrc, "Int", 0, "Int", 0, "Int", srcW, "Int", srcH, "UInt", 0x00CC0020)
        
        ; Cleanup
        DllCall("DeleteDC", "Ptr", hdcSrc)
        DllCall("DeleteDC", "Ptr", hdcDst)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        
        return hbmDst
    }
    
    CleanupBitmaps() {
        /*
        Frees bitmap resources
        */
        if (this.hbmScaled) {
            DllCall("DeleteObject", "Ptr", this.hbmScaled)
            this.hbmScaled := 0
        }
        if (this.hbmCaptured) {
            DllCall("DeleteObject", "Ptr", this.hbmCaptured)
            this.hbmCaptured := 0
        }
    }
    
    DrawMatchBox(x, y, w, h) {
        /*
        Draws green box around found match on preview
        */
        ; Calculate scaled coordinates
        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        
        this.picPreview.GetPos(&px, &py, &pw, &ph)
        
        rx := x - this.cfg["x1"]
        ry := y - this.cfg["y1"]
        
        sx := Floor(rx * pw / regionW)
        sy := Floor(ry * ph / regionH)
        sw := Max(2, Ceil(w * pw / regionW))
        sh := Max(2, Ceil(h * ph / regionH))
        
        ; Create box controls
        t := 3
        color := "00FF00"
        
        top := this.gui.Add("Progress", "x" (px+sx) " y" (py+sy) " w" sw " h" t " Background" color)
        left := this.gui.Add("Progress", "x" (px+sx) " y" (py+sy) " w" t " h" sh " Background" color)
        right := this.gui.Add("Progress", "x" (px+sx+sw-t) " y" (py+sy) " w" t " h" sh " Background" color)
        bottom := this.gui.Add("Progress", "x" (px+sx) " y" (py+sy+sh-t) " w" sw " h" t " Background" color)
        
        this.matchBoxes.Push([top, left, right, bottom])
    }
    
    ClearMatchBoxes() {
        /*
        Removes all match box overlays
        */
        for box in this.matchBoxes {
            for ctrl in box {
                try ctrl.Destroy()
            }
        }
        this.matchBoxes := []
    }
    
    ; ========================================================================
    ; SEARCH FUNCTIONS
    ; ========================================================================
    
    StartSearch() {
        /*
        Starts FindText search with current parameters
        */
        if (this.isSearching) {
            MsgBox("Search already in progress!", "Warning", "Icon!")
            return
        }
        
        ; Validate pattern
        if (Trim(this.edPattern.Value) = "") {
            MsgBox("No pattern loaded!`n`nCapture a pattern first.", "Error", "Icon!")
            return
        }
        
        ; Validate region
        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        patW := this.currentPatternInfo["w"]
        patH := this.currentPatternInfo["h"]
        
        if (patW > 0 && patH > 0 && (regionW < patW || regionH < patH)) {
            MsgBox("Search region is smaller than pattern!`n`n" .
                   "Region: " . regionW . "x" . regionH . "`n" .
                   "Pattern: " . patW . "x" . patH . "`n`n" .
                   "Pick a larger region.",
                   "Error", "Icon!")
            return
        }
        
        ; Update state
        this.isSearching := true
        this.cancelRequested := false
        
        ; Update UI
        this.btnStart.Enabled := false
        this.btnStop.Enabled := true
        this.ClearMatchBoxes()
        this.lvResults.Delete()
        
        ; Get parameters
        err1 := this.slErr1.Value / 100
        err0 := this.slErr0.Value / 100
        findAll := this.cbFindAll.Value
        screenShot := this.cbScreenShot.Value
        
        this.Log("=== SEARCH STARTED ===")
        this.Log("Region: (" . this.cfg["x1"] . "," . this.cfg["y1"] . ") to (" . 
                 this.cfg["x2"] . "," . this.cfg["y2"] . ") = " . regionW . "x" . regionH)
        this.Log("Pattern: " . patW . "x" . patH)
        this.Log("Tolerances: err1=" . Round(err1, 3) . " err0=" . Round(err0, 3))
        this.Log("Find All: " . (findAll ? "Yes" : "No"))
        
        ; Start search
        startTime := A_TickCount
        
        ; Call FindText
        ox := 0
        oy := 0
        ok := this.ft.FindText(&ox, &oy,
            this.cfg["x1"], this.cfg["y1"], this.cfg["x2"], this.cfg["y2"],
            err1, err0,
            this.edPattern.Value,
            screenShot, findAll)
        
        elapsed := A_TickCount - startTime
        
        ; Process results
        if (IsObject(ok) && ok.Length > 0) {
            this.Log("=== FOUND " . ok.Length . " MATCH(ES) ===")
            this.Log("Time: " . elapsed . " ms")
            
            ; Add to results list
            for index, match in ok {
                this.lvResults.Add(, index, match.x, match.y, match.w, match.h, "100%")
                this.DrawMatchBox(match.x, match.y, match.w, match.h)
                
                this.Log("Match " . index . ": (" . match.x . "," . match.y . ") " . 
                         match.w . "x" . match.h)
            }
            
            ; Display metrics
            this.DisplayMetrics(elapsed, ok.Length)
            
            ; Pause if requested
            if (this.cbPauseOnMatch.Value) {
                MsgBox("Found " . ok.Length . " match(es)!`n`nSee results below.", 
                       "Search Complete", "Iconi T3")
            }
            
        } else {
            this.Log("=== NO MATCHES FOUND ===")
            this.Log("Time: " . elapsed . " ms")
            this.DisplayMetrics(elapsed, 0)
            
            MsgBox("No matches found.`n`nTry adjusting tolerance or checking the pattern.", 
                   "No Results", "Iconi T3")
        }
        
        ; Reset state
        this.isSearching := false
        this.btnStart.Enabled := true
        this.btnStop.Enabled := false
        
        this.UpdateStatusText()
    }
    
    StopSearch() {
        /*
        Cancels current search
        */
        this.cancelRequested := true
        this.Log("Search cancelled by user")
    }
    
    DisplayMetrics(elapsed, matchCount) {
        /*
        Displays benchmark metrics
        */
        report := ""
        report .= "=".Repeat(60) . "`n"
        report .= "BENCHMARK METRICS`n"
        report .= "=".Repeat(60) . "`n`n"
        
        report .= "Duration:        " . elapsed . " ms (" . Round(elapsed/1000, 2) . " seconds)`n"
        report .= "Matches Found:   " . matchCount . "`n"
        
        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        report .= "Region Size:     " . regionW . " x " . regionH . "`n"
        
        patW := this.currentPatternInfo["w"]
        patH := this.currentPatternInfo["h"]
        if (patW > 0 && patH > 0) {
            report .= "Pattern Size:    " . patW . " x " . patH . "`n"
        }
        
        report .= "`n=".Repeat(60) . "`n"
        report .= "Parameters:`n"
        report .= "Text Tolerance:  " . Round(this.slErr1.Value) . "%`n"
        report .= "Bg Tolerance:    " . Round(this.slErr0.Value) . "%`n"
        report .= "Find All:        " . (this.cbFindAll.Value ? "Yes" : "No") . "`n"
        report .= "New Screenshot:  " . (this.cbScreenShot.Value ? "Yes" : "No") . "`n"
        
        this.edMetrics.Value := report
    }
    
    ; ========================================================================
    ; OFFICE FEATURES
    ; ========================================================================
    
    QuickOCR() {
        /*
        Quick OCR text extraction
        */
        MsgBox("OCR Feature`n`n" .
               "This feature extracts text from screen regions.`n`n" .
               "In a full implementation, this would:`n" .
               "1. Use pattern recognition to identify text`n" .
               "2. Convert to readable characters`n" .
               "3. Copy to clipboard`n`n" .
               "For now, use FindText to capture text patterns.",
               "OCR Info", "Iconi")
        
        this.Log("OCR feature accessed (demonstration mode)")
    }
    
    ExportResults() {
        /*
        Exports search results to file
        */
        if (this.lvResults.GetCount() = 0) {
            MsgBox("No results to export!`n`nPerform a search first.", "No Results", "Icon!")
            return
        }
        
        ; Get export format
        format := this.ddExport.Text
        extension := format = "JSON" ? ".json" : ".csv"
        
        ; File dialog
        file := FileSelect("S16", , "Export Results", format . " Files (*" . extension . ")")
        if (!file)
            return
        
        if (!InStr(file, extension))
            file .= extension
        
        try {
            ; Build export data
            if (format = "CSV" || format = "Excel") {
                data := this.BuildCSVExport()
            } else {
                data := this.BuildJSONExport()
            }
            
            ; Write file
            FileDelete(file)
            FileAppend(data, file)
            
            this.Log("Results exported to: " . file)
            
            result := MsgBox("Results exported successfully!`n`nFile: " . file . "`n`nOpen file now?",
                            "Export Complete", "YesNo Iconi")
            
            if (result = "Yes")
                Run(file)
                
        } catch as err {
            MsgBox("Export failed: " . err.Message, "Error", "Icon!")
            this.Log("ERROR: Export failed")
        }
    }
    
    BuildCSVExport() {
        /*
        Builds CSV format export
        */
        csv := "#,X,Y,Width,Height,Similarity"
        
        if (this.cbIncludeTimestamp.Value)
            csv .= ",Timestamp"
        
        csv .= "`n"
        
        timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        
        Loop this.lvResults.GetCount() {
            row := A_Index
            csv .= this.lvResults.GetText(row, 1) . ","
            csv .= this.lvResults.GetText(row, 2) . ","
            csv .= this.lvResults.GetText(row, 3) . ","
            csv .= this.lvResults.GetText(row, 4) . ","
            csv .= this.lvResults.GetText(row, 5) . ","
            csv .= this.lvResults.GetText(row, 6)
            
            if (this.cbIncludeTimestamp.Value)
                csv .= "," . timestamp
            
            csv .= "`n"
        }
        
        ; Add metadata
        csv .= "`nMetadata:`n"
        csv .= "Total Matches," . this.lvResults.GetCount() . "`n"
        csv .= "Export Date," . timestamp . "`n"
        csv .= "Pattern Size," . this.currentPatternInfo["w"] . "x" . this.currentPatternInfo["h"] . "`n"
        
        return csv
    }
    
    BuildJSONExport() {
        /*
        Builds JSON format export
        */
        json := '{"matches":['
        
        Loop this.lvResults.GetCount() {
            if (A_Index > 1)
                json .= ","
            
            row := A_Index
            json .= '{'
            json .= '"index":' . this.lvResults.GetText(row, 1) . ','
            json .= '"x":' . this.lvResults.GetText(row, 2) . ','
            json .= '"y":' . this.lvResults.GetText(row, 3) . ','
            json .= '"width":' . this.lvResults.GetText(row, 4) . ','
            json .= '"height":' . this.lvResults.GetText(row, 5) . ','
            json .= '"similarity":"' . this.lvResults.GetText(row, 6) . '"'
            json .= '}'
        }
        
        json .= '],'
        json .= '"metadata":{'
        json .= '"totalMatches":' . this.lvResults.GetCount() . ','
        json .= '"exportDate":"' . FormatTime(, "yyyy-MM-dd HH:mm:ss") . '",'
        json .= '"patternSize":"' . this.currentPatternInfo["w"] . 'x' . this.currentPatternInfo["h"] . '"'
        json .= '}}'
        
        return json
    }
    
    ToggleMonitoring() {
        /*
        Toggles pattern monitoring
        */
        if (this.monitorTimer) {
            this.StopMonitoring()
        } else {
            this.StartMonitoring()
        }
    }
    
    StartMonitoring() {
        /*
        Starts pattern monitoring
        */
        if (Trim(this.edPattern.Value) = "") {
            MsgBox("No pattern loaded!`n`nCapture a pattern first.", "Error", "Icon!")
            return
        }
        
        interval := Integer(this.edMonitorInterval.Value) * 1000
        if (interval < 1000)
            interval := 5000
        
        this.monitorTimer := SetTimer((*) => this.MonitorCheck(), interval)
        
        this.btnMonitor.Text := "⏹ Stop Monitor"
        this.txtMonitorStatus.Value := "Monitoring: ACTIVE (checking every " . (interval/1000) . "s)"
        
        this.Log("Monitoring started (interval: " . (interval/1000) . "s)")
        
        if (this.cbMonitorNotify.Value)
            TrayTip("Monitoring Active", "Pattern check every " . (interval/1000) . " seconds", 2)
    }
    
    StopMonitoring() {
        /*
        Stops pattern monitoring
        */
        if (this.monitorTimer) {
            SetTimer(this.monitorTimer, 0)
            this.monitorTimer := 0
        }
        
        this.btnMonitor.Text := "⏰ Start Monitor"
        this.txtMonitorStatus.Value := "Monitoring: Inactive"
        
        this.Log("Monitoring stopped")
    }
    
    MonitorCheck() {
        /*
        Performs monitoring check
        */
        err1 := this.slErr1.Value / 100
        err0 := this.slErr0.Value / 100
        
        ox := 0
        oy := 0
        ok := this.ft.FindText(&ox, &oy,
            this.cfg["x1"], this.cfg["y1"], this.cfg["x2"], this.cfg["y2"],
            err1, err0,
            this.edPattern.Value,
            1, 0)
        
        currentState := (IsObject(ok) && ok.Length > 0) ? "FOUND" : "NOT_FOUND"
        
        if (currentState != this.lastMonitorState && this.lastMonitorState != "") {
            this.Log("MONITOR: State changed from " . this.lastMonitorState . " to " . currentState)
            
            if (this.cbMonitorNotify.Value) {
                if (currentState = "FOUND")
                    TrayTip("Pattern Detected!", "Pattern found at " . FormatTime(, "HH:mm:ss"), 3)
                else
                    TrayTip("Pattern Lost!", "Pattern no longer visible", 3)
            }
            
            if (this.cbMonitorSound.Value)
                SoundBeep(1000, 200)
        }
        
        this.lastMonitorState := currentState
        
        timestamp := FormatTime(, "HH:mm:ss")
        this.txtMonitorStatus.Value := "Last check: " . timestamp . " - " . currentState
    }
    
    ; ========================================================================
    ; UI UPDATE FUNCTIONS
    ; ========================================================================
    
    UpdateErr1Text() {
        this.txtErr1.Value := Round(this.slErr1.Value) . "%"
    }
    
    UpdateErr0Text() {
        this.txtErr0.Value := Round(this.slErr0.Value) . "%"
    }
    
    UpdateStatusText() {
        /*
        Updates status indicator and text
        */
        if (this.isSearching) {
            this.statusIndicator.Opt("Background0xFFB900")  ; Orange
            this.statusText.Value := "Searching..."
        } else if (Trim(this.edPattern.Value) = "") {
            this.statusIndicator.Opt("Background0xD13438")  ; Red
            this.statusText.Value := "No Pattern Loaded"
        } else {
            this.statusIndicator.Opt("Background0x107C10")  ; Green
            this.statusText.Value := "Ready to Search"
        }
    }
    
    RefreshPatternList() {
        this.RefreshPatternLibrary()
    }
    
    ; ========================================================================
    ; UTILITY FUNCTIONS
    ; ========================================================================
    
    Log(message) {
        /*
        Adds message to log
        */
        timestamp := FormatTime(, "[HH:mm:ss]")
        this.edLog.Value .= timestamp . " " . message . "`n"
        SendMessage(0x0115, 7, 0, this.edLog.Hwnd)  ; Scroll to bottom
    }
    
    ShowQuickHelp() {
        /*
        Shows quick help dialog
        */
        help := "QUICK START GUIDE`n"
        help .= "=".Repeat(50) . "`n`n"
        
        help .= "1. CAPTURE PATTERN`n"
        help .= "   Click 'Open FindText GUI' to capture a pattern`n"
        help .= "   Copy the pattern text and paste into Pattern box`n`n"
        
        help .= "2. SET REGION`n"
        help .= "   Use 'Pick Region' or 'Full Screen'`n"
        help .= "   Region must be larger than pattern`n`n"
        
        help .= "3. ADJUST PARAMETERS`n"
        help .= "   Tolerance: 10% is good default`n"
        help .= "   Lower = stricter, Higher = more flexible`n`n"
        
        help .= "4. START SEARCH`n"
        help .= "   Click 'START SEARCH' or use Quick Actions`n"
        help .= "   Results appear in Matches tab`n`n"
        
        help .= "5. EXPORT OR MONITOR`n"
        help .= "   Export results to CSV/Excel/JSON`n"
        help .= "   Use monitoring for auto-detection`n`n"
        
        help .= "TIPS:`n"
        help .= "• Save patterns to library for reuse`n"
        help .= "• Use visualization to see search area`n"
        help .= "• Check log for detailed information`n"
        
        MsgBox(help, "Quick Help", "Iconi")
    }
    
    OnResize() {
        /*
        Handles window resize
        */
        ; TODO: Implement responsive resize if needed
    }
    
    OnClose() {
        /*
        Cleanup on close
        */
        this.StopMonitoring()
        this.SaveState()
        this.CleanupBitmaps()
        ExitApp
    }
    
    ; ========================================================================
    ; STATE PERSISTENCE
    ; ========================================================================
    
    LoadState() {
        /*
        Loads saved state from INI file
        */
        ini := A_ScriptDir . "\FindText_GUI.ini"
        if (!FileExist(ini))
            return
        
        try {
            this.edX1.Value := IniRead(ini, "Region", "X1", "0")
            this.edY1.Value := IniRead(ini, "Region", "Y1", "0")
            this.edX2.Value := IniRead(ini, "Region", "X2", A_ScreenWidth)
            this.edY2.Value := IniRead(ini, "Region", "Y2", A_ScreenHeight)
            
            this.slErr1.Value := IniRead(ini, "Params", "Err1", "10")
            this.slErr0.Value := IniRead(ini, "Params", "Err0", "10")
            
            this.UpdateErr1Text()
            this.UpdateErr0Text()
            
            this.ApplyRegion()
            
            this.Log("Settings loaded from " . ini)
        }
    }
    
    SaveState() {
        /*
        Saves current state to INI file
        */
        ini := A_ScriptDir . "\FindText_GUI.ini"
        
        try {
            IniWrite(this.edX1.Value, ini, "Region", "X1")
            IniWrite(this.edY1.Value, ini, "Region", "Y1")
            IniWrite(this.edX2.Value, ini, "Region", "X2")
            IniWrite(this.edY2.Value, ini, "Region", "Y2")
            
            IniWrite(this.slErr1.Value, ini, "Params", "Err1")
            IniWrite(this.slErr0.Value, ini, "Params", "Err0")
            
            this.Log("Settings saved to " . ini)
        }
    }
}

; ============================================================================
; PROGRAM START
; ============================================================================

; Check if FindText.ahk exists
if (!FileExist(A_ScriptDir . "\FindText.ahk")) {
    MsgBox("FindText.ahk not found!`n`n" .
           "Please place FindText.ahk in the same directory as this script:`n" .
           A_ScriptDir,
           "Missing Library", "Icon!")
    ExitApp
}

; Create and run application
try {
    app := FindTextGUI()
} catch as err {
    MsgBox("Failed to initialize application:`n`n" . err.Message, "Error", "Icon!")
    ExitApp
}


; ============================================================================
; STRING EXTENSION (Helper)
; ============================================================================

String.Prototype.Repeat := (count){
    result := ""
    Loop count
        result .= this
     
}

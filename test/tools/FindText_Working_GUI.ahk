/*
================================================================================
FINDTEXT PROFESSIONAL GUI - WORKING VERSION
================================================================================
AutoHotkey v2.0+ GUI Wrapper for FindText.ahk

REQUIREMENTS:
- AutoHotkey v2.0+
- FindText.ahk in same directory

================================================================================
*/

#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

; Check for FindText.ahk first
if (!FileExist(A_ScriptDir . "\FindText.ahk")) {
    MsgBox("FindText.ahk not found!`n`nPlease place FindText.ahk in:`n" . A_ScriptDir, "Missing Library", "Icon!")
    ExitApp
}

; Include FindText library
#Include "FindText.ahk"

; ============================================================================
; HELPER FUNCTIONS
; ============================================================================

StrRepeat(str, count) {
    result := ""
    Loop count
        result .= str
    return result
}

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
        
        ; Bitmap handles
        this.hbmCaptured := 0
        this.hbmScaled := 0
        
        ; Visual overlays
        this.matchBoxes := []
        
        ; Configuration
        this.cfg := Map(
            "x1", 0,
            "y1", 0,
            "x2", A_ScreenWidth - 1,
            "y2", A_ScreenHeight - 1,
            "err1", 0.1,
            "err0", 0.1,
            "findAll", 0,
            "screenShot", 1
        )
        
        ; Pattern data
        this.currentPattern := ""
        this.currentPatternInfo := Map("w", 0, "h", 0)
        
        ; Build GUI
        this.BuildGUI()
        
        ; Initialize
        this.LoadState()
        this.RefreshPatternList()
        this.UpdatePreview()
    }
    
    ; ========================================================================
    ; GUI CONSTRUCTION
    ; ========================================================================
    
    BuildGUI() {
        ; Create main window
        this.gui := Gui("+Resize", "FindText Professional GUI")
        this.gui.SetFont("s9", "Segoe UI")
        this.gui.BackColor := "0xF5F5F5"
        
        ; ====================================================================
        ; TOP BAR
        ; ====================================================================
        
        this.gui.Add("Progress", "x0 y0 w1400 h60 Background0xE8F4FF")
        
        this.gui.SetFont("s11 Bold")
        this.gui.Add("Text", "x20 y10 c0x0078D4", "FindText Professional GUI")
        this.gui.SetFont("s9", "Segoe UI")
        
        this.btnQuickCapture := this.gui.Add("Button", "x20 y30 w140 h25", "📸 Quick Capture")
        this.btnQuickCapture.OnEvent("Click", (*) => this.QuickCapture())
        
        this.btnQuickSearch := this.gui.Add("Button", "x170 y30 w140 h25", "🔍 Quick Search")
        this.btnQuickSearch.OnEvent("Click", (*) => this.StartSearch())
        
        this.btnExport := this.gui.Add("Button", "x320 y30 w140 h25", "📊 Export Results")
        this.btnExport.OnEvent("Click", (*) => this.ExportResults())
        
        this.btnHelp := this.gui.Add("Button", "x470 y30 w100 h25", "❓ Help")
        this.btnHelp.OnEvent("Click", (*) => this.ShowHelp())
        
        this.statusText := this.gui.Add("Text", "x600 y33 w300", "Status: Ready")
        
        ; ====================================================================
        ; LEFT PANEL
        ; ====================================================================
        
        yPos := 75
        leftW := 520
        
        ; Pattern Section
        this.gui.Add("GroupBox", "x10 y" . yPos . " w" . leftW . " h180", "Pattern")
        
        this.gui.Add("Text", "x20 y" . (yPos + 20), "FindText Pattern String:")
        this.edPattern := this.gui.Add("Edit", "x20 y" . (yPos + 40) . " w" . (leftW - 20) . " r4")
        this.edPattern.SetFont("s9", "Consolas")
        this.edPattern.OnEvent("Change", (*) => this.OnPatternChange())
        
        this.btnOpenFindText := this.gui.Add("Button", "x20 y" . (yPos + 125) . " w160 h30", "Open FindText GUI")
        this.btnOpenFindText.OnEvent("Click", (*) => this.ft.Gui("Show"))
        
        this.btnLoadPattern := this.gui.Add("Button", "x190 y" . (yPos + 125) . " w80 h30", "📂 Load")
        this.btnLoadPattern.OnEvent("Click", (*) => this.LoadPatternFromFile())
        
        this.btnSavePattern := this.gui.Add("Button", "x280 y" . (yPos + 125) . " w80 h30", "💾 Save")
        this.btnSavePattern.OnEvent("Click", (*) => this.SavePatternToFile())
        
        this.btnClearPattern := this.gui.Add("Button", "x370 y" . (yPos + 125) . " w80 h30", "🗑 Clear")
        this.btnClearPattern.OnEvent("Click", (*) => this.ClearPattern())
        
        this.txtPatternInfo := this.gui.Add("Text", "x20 y" . (yPos + 160) . " w" . (leftW - 20), "No pattern loaded")
        
        ; Region Section
        yPos += 190
        this.gui.Add("GroupBox", "x10 y" . yPos . " w" . leftW . " h130", "Search Region")
        
        this.gui.Add("Text", "x20 y" . (yPos + 25), "X1:")
        this.edX1 := this.gui.Add("Edit", "x50 y" . (yPos + 22) . " w70 Number", "0")
        
        this.gui.Add("Text", "x130 y" . (yPos + 25), "Y1:")
        this.edY1 := this.gui.Add("Edit", "x160 y" . (yPos + 22) . " w70 Number", "0")
        
        this.gui.Add("Text", "x240 y" . (yPos + 25), "X2:")
        this.edX2 := this.gui.Add("Edit", "x270 y" . (yPos + 22) . " w70 Number", A_ScreenWidth)
        
        this.gui.Add("Text", "x350 y" . (yPos + 25), "Y2:")
        this.edY2 := this.gui.Add("Edit", "x380 y" . (yPos + 22) . " w70 Number", A_ScreenHeight)
        
        this.btnPickRegion := this.gui.Add("Button", "x20 y" . (yPos + 55) . " w230 h30", "🎯 Pick Region (2 Clicks)")
        this.btnPickRegion.OnEvent("Click", (*) => this.PickRegion())
        
        this.btnFullScreen := this.gui.Add("Button", "x260 y" . (yPos + 55) . " w120 h30", "🖥 Full Screen")
        this.btnFullScreen.OnEvent("Click", (*) => this.SetFullScreen())
        
        this.btnApply := this.gui.Add("Button", "x390 y" . (yPos + 55) . " w120 h30", "✓ Apply")
        this.btnApply.OnEvent("Click", (*) => this.ApplyRegion())
        
        this.txtRegionInfo := this.gui.Add("Text", "x20 y" . (yPos + 95) . " w" . (leftW - 20), "Region: Full Screen")
        
        ; Parameters Section
        yPos += 140
        this.gui.Add("GroupBox", "x10 y" . yPos . " w" . leftW . " h140", "Search Parameters")
        
        this.gui.Add("Text", "x20 y" . (yPos + 25), "Text Tolerance (err1):")
        this.txtErr1 := this.gui.Add("Text", "x480 y" . (yPos + 25) . " w30 Right", "10%")
        this.slErr1 := this.gui.Add("Slider", "x20 y" . (yPos + 45) . " w" . (leftW - 30) . " Range0-50 TickInterval5", 10)
        this.slErr1.OnEvent("Change", (*) => this.UpdateErr1())
        
        this.gui.Add("Text", "x20 y" . (yPos + 75), "Background Tolerance (err0):")
        this.txtErr0 := this.gui.Add("Text", "x480 y" . (yPos + 75) . " w30 Right", "10%")
        this.slErr0 := this.gui.Add("Slider", "x20 y" . (yPos + 95) . " w" . (leftW - 30) . " Range0-50 TickInterval5", 10)
        this.slErr0.OnEvent("Change", (*) => this.UpdateErr0())
        
        this.cbFindAll := this.gui.Add("Checkbox", "x20 y" . (yPos + 120), "Find All Matches")
        this.cbScreenShot := this.gui.Add("Checkbox", "x160 y" . (yPos + 120) . " Checked", "New Screenshot")
        
        ; Pattern Library
        yPos += 150
        this.gui.Add("GroupBox", "x10 y" . yPos . " w" . leftW . " h200", "Pattern Library")
        
        this.lvPatterns := this.gui.Add("ListView", "x20 y" . (yPos + 20) . " w" . (leftW - 20) . " h130 Grid", ["Name", "Size", "Date"])
        this.lvPatterns.ModifyCol(1, 240)
        this.lvPatterns.ModifyCol(2, 100)
        this.lvPatterns.ModifyCol(3, 150)
        this.lvPatterns.OnEvent("DoubleClick", (*) => this.LoadFromLibrary())
        
        this.btnLoadLib := this.gui.Add("Button", "x20 y" . (yPos + 160) . " w160 h30", "Load Selected")
        this.btnLoadLib.OnEvent("Click", (*) => this.LoadFromLibrary())
        
        this.btnDeleteLib := this.gui.Add("Button", "x190 y" . (yPos + 160) . " w160 h30", "Delete Selected")
        this.btnDeleteLib.OnEvent("Click", (*) => this.DeleteFromLibrary())
        
        this.btnRefresh := this.gui.Add("Button", "x360 y" . (yPos + 160) . " w150 h30", "🔄 Refresh")
        this.btnRefresh.OnEvent("Click", (*) => this.RefreshPatternList())
        
        ; Action Buttons
        yPos += 210
        this.btnStart := this.gui.Add("Button", "x10 y" . yPos . " w250 h50", "🔍 START SEARCH")
        this.btnStart.OnEvent("Click", (*) => this.StartSearch())
        this.btnStart.SetFont("s11 Bold")
        
        this.btnStop := this.gui.Add("Button", "x270 y" . yPos . " w250 h50 Disabled", "⏹ STOP")
        this.btnStop.OnEvent("Click", (*) => this.StopSearch())
        
        ; ====================================================================
        ; RIGHT PANEL
        ; ====================================================================
        
        rightX := 550
        rightW := 700
        
        ; Preview
        this.gui.Add("GroupBox", "x" . rightX . " y75 w" . rightW . " h480", "Visual Preview")
        
        this.txtPreviewInfo := this.gui.Add("Text", "x" . (rightX + 10) . " y95 w" . (rightW - 20) . " Center", "Select region to see preview")
        
        this.picPreview := this.gui.Add("Picture", "x" . (rightX + 10) . " y115 w" . (rightW - 20) . " h435 Border")
        
        ; Results Tabs
        yPos := 565
        this.tabResults := this.gui.Add("Tab3", "x" . rightX . " y" . yPos . " w" . rightW . " h310", ["Matches", "Metrics", "Log"])
        
        ; Matches Tab
        this.tabResults.UseTab(1)
        this.lvResults := this.gui.Add("ListView", "x" . (rightX + 10) . " y" . (yPos + 30) . " w" . (rightW - 20) . " h265 Grid", ["#", "X", "Y", "Width", "Height", "Similarity"])
        this.lvResults.ModifyCol(1, 50)
        this.lvResults.ModifyCol(2, 80)
        this.lvResults.ModifyCol(3, 80)
        this.lvResults.ModifyCol(4, 80)
        this.lvResults.ModifyCol(5, 80)
        this.lvResults.ModifyCol(6, 120)
        
        ; Metrics Tab
        this.tabResults.UseTab(2)
        this.edMetrics := this.gui.Add("Edit", "x" . (rightX + 10) . " y" . (yPos + 30) . " w" . (rightW - 20) . " h265 ReadOnly Multi")
        this.edMetrics.SetFont("s9", "Consolas")
        this.edMetrics.Value := "Perform a search to see metrics."
        
        ; Log Tab
        this.tabResults.UseTab(3)
        this.edLog := this.gui.Add("Edit", "x" . (rightX + 10) . " y" . (yPos + 30) . " w" . (rightW - 20) . " h265 ReadOnly Multi")
        this.edLog.SetFont("s9", "Consolas")
        
        this.tabResults.UseTab()
        
        ; Events
        this.gui.OnEvent("Close", (*) => this.OnClose())
        
        ; Show GUI
        this.gui.Show("w1270 h900")
        
        this.Log("FindText Professional GUI started")
    }
    
    ; ========================================================================
    ; PATTERN MANAGEMENT
    ; ========================================================================
    
    QuickCapture() {
        this.Log("Opening FindText capture GUI...")
        this.ft.Gui("Show")
        MsgBox("FindText GUI opened!`n`n1. Use Alt+1 to capture pattern`n2. Copy pattern text`n3. Paste in Pattern box", "Quick Capture", "Iconi T3")
    }
    
    OnPatternChange() {
        pattern := Trim(this.edPattern.Value)
        
        if (pattern = "") {
            this.currentPattern := ""
            this.currentPatternInfo := Map("w", 0, "h", 0)
            this.txtPatternInfo.Value := "No pattern loaded"
            return
        }
        
        this.currentPattern := pattern
        info := this.ParsePatternDims(pattern)
        this.currentPatternInfo := info
        
        if (info["w"] > 0 && info["h"] > 0) {
            this.txtPatternInfo.Value := "Pattern size: " . info["w"] . " x " . info["h"] . " pixels"
        } else {
            this.txtPatternInfo.Value := "Pattern loaded"
        }
        
        this.UpdatePreview()
    }
    
    ParsePatternDims(pattern) {
        w := 0
        h := 0
        
        if RegExMatch(pattern, "\$(\d+)", &mH)
            h := Integer(mH[1])
        
        if RegExMatch(pattern, "\.(\d+)", &mW)
            w := Integer(mW[1])
        
        return Map("w", w, "h", h)
    }
    
    LoadPatternFromFile() {
        file := FileSelect(3, , "Load Pattern", "Text Files (*.txt)")
        if (!file)
            return
        
        try {
            pattern := FileRead(file)
            this.edPattern.Value := pattern
            this.OnPatternChange()
            this.Log("Pattern loaded from file")
        } catch as err {
            MsgBox("Failed to load: " . err.Message, "Error", "Icon!")
        }
    }
    
    SavePatternToFile() {
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
            if FileExist(file)
                FileDelete(file)
            FileAppend(pattern, file)
            this.Log("Pattern saved to file")
            MsgBox("Pattern saved!", "Success", "Iconi T2")
        } catch as err {
            MsgBox("Failed to save: " . err.Message, "Error", "Icon!")
        }
    }
    
    ClearPattern() {
        this.edPattern.Value := ""
        this.OnPatternChange()
    }
    
    RefreshPatternList() {
        this.lvPatterns.Delete()
        
        libDir := A_ScriptDir . "\Patterns"
        if (!DirExist(libDir)) {
            try DirCreate(libDir)
        }
        
        Loop Files, libDir . "\*.txt" {
            this.lvPatterns.Add(, A_LoopFileName, A_LoopFileSize . " bytes", A_LoopFileTimeModified)
        }
        
        this.Log("Pattern library refreshed")
    }
    
    LoadFromLibrary() {
        row := this.lvPatterns.GetNext()
        if (!row) {
            MsgBox("Select a pattern first!", "Info", "Iconi")
            return
        }
        
        fileName := this.lvPatterns.GetText(row, 1)
        filePath := A_ScriptDir . "\Patterns\" . fileName
        
        try {
            pattern := FileRead(filePath)
            this.edPattern.Value := pattern
            this.OnPatternChange()
            this.Log("Loaded from library: " . fileName)
        } catch as err {
            MsgBox("Failed to load: " . err.Message, "Error", "Icon!")
        }
    }
    
    DeleteFromLibrary() {
        row := this.lvPatterns.GetNext()
        if (!row) {
            MsgBox("Select a pattern first!", "Info", "Iconi")
            return
        }
        
        fileName := this.lvPatterns.GetText(row, 1)
        result := MsgBox("Delete: " . fileName . "?", "Confirm", "YesNo Icon!")
        
        if (result = "No")
            return
        
        filePath := A_ScriptDir . "\Patterns\" . fileName
        
        try {
            FileDelete(filePath)
            this.RefreshPatternList()
            this.Log("Deleted: " . fileName)
        } catch as err {
            MsgBox("Failed to delete: " . err.Message, "Error", "Icon!")
        }
    }
    
    ; ========================================================================
    ; REGION MANAGEMENT
    ; ========================================================================
    
    PickRegion() {
        this.Log("Pick region: Click TOP-LEFT then BOTTOM-RIGHT")
        this.gui.Hide()
        
        CoordMode("Mouse", "Screen")
        
        ToolTip("Click TOP-LEFT corner...")
        KeyWait("LButton", "D")
        MouseGetPos(&x1, &y1)
        KeyWait("LButton", "U")
        
        ToolTip("Click BOTTOM-RIGHT corner...")
        Sleep(200)
        
        KeyWait("LButton", "D")
        MouseGetPos(&x2, &y2)
        KeyWait("LButton", "U")
        
        ToolTip()
        this.gui.Show()
        
        this.edX1.Value := Min(x1, x2)
        this.edY1.Value := Min(y1, y2)
        this.edX2.Value := Max(x1, x2)
        this.edY2.Value := Max(y1, y2)
        
        this.ApplyRegion()
        this.Log("Region picked")
    }
    
    SetFullScreen() {
        this.edX1.Value := 0
        this.edY1.Value := 0
        this.edX2.Value := A_ScreenWidth - 1
        this.edY2.Value := A_ScreenHeight - 1
        this.ApplyRegion()
        this.Log("Region set to full screen")
    }
    
    ApplyRegion() {
        this.cfg["x1"] := Integer(this.edX1.Value)
        this.cfg["y1"] := Integer(this.edY1.Value)
        this.cfg["x2"] := Integer(this.edX2.Value)
        this.cfg["y2"] := Integer(this.edY2.Value)
        
        w := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        h := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        
        this.txtRegionInfo.Value := "Region: " . w . " x " . h . " pixels"
        this.UpdatePreview()
        this.Log("Region applied: " . w . "x" . h)
    }
    
    ; ========================================================================
    ; VISUALIZATION
    ; ========================================================================
    
    UpdatePreview() {
        x := this.cfg["x1"]
        y := this.cfg["y1"]
        w := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        h := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        
        if (w < 10 || h < 10)
            return
        
        this.picPreview.GetPos(, , &pw, &ph)
        if (pw < 50 || ph < 50)
            return
        
        this.CleanupBitmaps()
        
        this.hbmCaptured := this.CaptureScreen(x, y, w, h)
        if (!this.hbmCaptured)
            return
        
        this.hbmScaled := this.ScaleBitmap(this.hbmCaptured, pw, ph)
        if (!this.hbmScaled)
            return
        
        this.picPreview.Value := "HBITMAP:*" . this.hbmScaled
        this.txtPreviewInfo.Value := "Preview: " . w . "x" . h . " scaled to " . pw . "x" . ph
    }
    
    CaptureScreen(x, y, w, h) {
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcMem := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hbm := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", w, "Int", h, "Ptr")
        
        DllCall("SelectObject", "Ptr", hdcMem, "Ptr", hbm)
        DllCall("BitBlt", "Ptr", hdcMem, "Int", 0, "Int", 0, "Int", w, "Int", h, "Ptr", hdcScreen, "Int", x, "Int", y, "UInt", 0x00CC0020)
        
        DllCall("DeleteDC", "Ptr", hdcMem)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        
        return hbm
    }
    
    ScaleBitmap(hbmSrc, newW, newH) {
        if (!hbmSrc)
            return 0
        
        bm := Buffer(32, 0)
        DllCall("GetObject", "Ptr", hbmSrc, "Int", 32, "Ptr", bm)
        srcW := NumGet(bm, 4, "Int")
        srcH := NumGet(bm, 8, "Int")
        
        hdcScreen := DllCall("GetDC", "Ptr", 0, "Ptr")
        hdcSrc := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        hdcDst := DllCall("CreateCompatibleDC", "Ptr", hdcScreen, "Ptr")
        
        hbmDst := DllCall("CreateCompatibleBitmap", "Ptr", hdcScreen, "Int", newW, "Int", newH, "Ptr")
        
        DllCall("SelectObject", "Ptr", hdcSrc, "Ptr", hbmSrc)
        DllCall("SelectObject", "Ptr", hdcDst, "Ptr", hbmDst)
        DllCall("SetStretchBltMode", "Ptr", hdcDst, "Int", 4)
        
        DllCall("StretchBlt", "Ptr", hdcDst, "Int", 0, "Int", 0, "Int", newW, "Int", newH, "Ptr", hdcSrc, "Int", 0, "Int", 0, "Int", srcW, "Int", srcH, "UInt", 0x00CC0020)
        
        DllCall("DeleteDC", "Ptr", hdcSrc)
        DllCall("DeleteDC", "Ptr", hdcDst)
        DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdcScreen)
        
        return hbmDst
    }
    
    CleanupBitmaps() {
        if (this.hbmScaled) {
            DllCall("DeleteObject", "Ptr", this.hbmScaled)
            this.hbmScaled := 0
        }
        if (this.hbmCaptured) {
            DllCall("DeleteObject", "Ptr", this.hbmCaptured)
            this.hbmCaptured := 0
        }
    }
    
    ; ========================================================================
    ; SEARCH
    ; ========================================================================
    
    StartSearch() {
        if (this.isSearching) {
            MsgBox("Search already running!", "Warning", "Icon!")
            return
        }
        
        if (Trim(this.edPattern.Value) = "") {
            MsgBox("No pattern loaded!", "Error", "Icon!")
            return
        }
        
        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        patW := this.currentPatternInfo["w"]
        patH := this.currentPatternInfo["h"]
        
        if (patW > 0 && patH > 0 && (regionW < patW || regionH < patH)) {
            MsgBox("Region smaller than pattern!`n`nRegion: " . regionW . "x" . regionH . "`nPattern: " . patW . "x" . patH, "Error", "Icon!")
            return
        }
        
        this.isSearching := true
        this.btnStart.Enabled := false
        this.btnStop.Enabled := true
        this.lvResults.Delete()
        this.ClearMatchBoxes()
        
        err1 := this.slErr1.Value / 100
        err0 := this.slErr0.Value / 100
        findAll := this.cbFindAll.Value
        screenShot := this.cbScreenShot.Value
        
        this.Log("=== SEARCH STARTED ===")
        this.Log("Region: " . regionW . "x" . regionH)
        this.Log("Pattern: " . patW . "x" . patH)
        this.Log("Tolerances: " . Round(err1, 3) . " / " . Round(err0, 3))
        
        startTime := A_TickCount
        
        ox := 0
        oy := 0
        ok := this.ft.FindText(&ox, &oy, this.cfg["x1"], this.cfg["y1"], this.cfg["x2"], this.cfg["y2"], err1, err0, this.edPattern.Value, screenShot, findAll)
        
        elapsed := A_TickCount - startTime
        
        if (IsObject(ok) && ok.Length > 0) {
            this.Log("=== FOUND " . ok.Length . " MATCH(ES) ===")
            this.Log("Time: " . elapsed . " ms")
            
            for index, match in ok {
                this.lvResults.Add(, index, match.x, match.y, match.w, match.h, "100%")
                this.Log("Match " . index . ": (" . match.x . "," . match.y . ")")
            }
            
            this.DisplayMetrics(elapsed, ok.Length)
            MsgBox("Found " . ok.Length . " match(es)!", "Success", "Iconi T2")
        } else {
            this.Log("=== NO MATCHES ===")
            this.Log("Time: " . elapsed . " ms")
            this.DisplayMetrics(elapsed, 0)
            MsgBox("No matches found.", "No Results", "Iconi T2")
        }
        
        this.isSearching := false
        this.btnStart.Enabled := true
        this.btnStop.Enabled := false
    }
    
    StopSearch() {
        this.cancelRequested := true
        this.Log("Search cancelled")
    }
    
    DisplayMetrics(elapsed, matchCount) {
        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        
        report := StrRepeat("=", 60) . "`n"
        report .= "BENCHMARK METRICS`n"
        report .= StrRepeat("=", 60) . "`n`n"
        report .= "Duration:      " . elapsed . " ms`n"
        report .= "Matches Found: " . matchCount . "`n"
        report .= "Region Size:   " . regionW . " x " . regionH . "`n"
        report .= "Pattern Size:  " . this.currentPatternInfo["w"] . " x " . this.currentPatternInfo["h"] . "`n"
        report .= "`n" . StrRepeat("=", 60) . "`n"
        report .= "Parameters:`n"
        report .= "Text Tol:  " . Round(this.slErr1.Value) . "%`n"
        report .= "Bg Tol:    " . Round(this.slErr0.Value) . "%`n"
        report .= "Find All:  " . (this.cbFindAll.Value ? "Yes" : "No") . "`n"
        
        this.edMetrics.Value := report
    }
    
    ClearMatchBoxes() {
        for box in this.matchBoxes {
            for ctrl in box {
                try ctrl.Destroy()
            }
        }
        this.matchBoxes := []
    }
    
    ; ========================================================================
    ; EXPORT
    ; ========================================================================
    
    ExportResults() {
        if (this.lvResults.GetCount() = 0) {
            MsgBox("No results to export!", "No Results", "Icon!")
            return
        }
        
        file := FileSelect("S16", , "Export Results", "CSV Files (*.csv)")
        if (!file)
            return
        
        if (!InStr(file, ".csv"))
            file .= ".csv"
        
        try {
            csv := "#,X,Y,Width,Height,Similarity,Timestamp`n"
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            
            Loop this.lvResults.GetCount() {
                row := A_Index
                csv .= this.lvResults.GetText(row, 1) . ","
                csv .= this.lvResults.GetText(row, 2) . ","
                csv .= this.lvResults.GetText(row, 3) . ","
                csv .= this.lvResults.GetText(row, 4) . ","
                csv .= this.lvResults.GetText(row, 5) . ","
                csv .= this.lvResults.GetText(row, 6) . ","
                csv .= timestamp . "`n"
            }
            
            if FileExist(file)
                FileDelete(file)
            FileAppend(csv, file)
            
            this.Log("Exported to: " . file)
            
            result := MsgBox("Export successful!`n`nOpen file?", "Export Complete", "YesNo Iconi")
            if (result = "Yes")
                Run(file)
                
        } catch as err {
            MsgBox("Export failed: " . err.Message, "Error", "Icon!")
        }
    }
    
    ; ========================================================================
    ; UTILITIES
    ; ========================================================================
    
    UpdateErr1() {
        this.txtErr1.Value := Round(this.slErr1.Value) . "%"
    }
    
    UpdateErr0() {
        this.txtErr0.Value := Round(this.slErr0.Value) . "%"
    }
    
    Log(message) {
        timestamp := FormatTime(, "[HH:mm:ss]")
        this.edLog.Value .= timestamp . " " . message . "`n"
        SendMessage(0x0115, 7, 0, this.edLog.Hwnd)
    }
    
    ShowHelp() {
        help := "QUICK START:`n`n"
        help .= "1. Click 'Open FindText GUI'`n"
        help .= "2. Use Alt+1 to capture pattern`n"
        help .= "3. Copy pattern text and paste`n"
        help .= "4. Pick region or use full screen`n"
        help .= "5. Click START SEARCH`n"
        help .= "`nResults appear in Matches tab!"
        
        MsgBox(help, "Quick Help", "Iconi")
    }
    
    OnClose() {
        this.SaveState()
        this.CleanupBitmaps()
        ExitApp
    }
    
    LoadState() {
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
            this.UpdateErr1()
            this.UpdateErr0()
            this.ApplyRegion()
        }
    }
    
    SaveState() {
        ini := A_ScriptDir . "\FindText_GUI.ini"
        
        try {
            IniWrite(this.edX1.Value, ini, "Region", "X1")
            IniWrite(this.edY1.Value, ini, "Region", "Y1")
            IniWrite(this.edX2.Value, ini, "Region", "X2")
            IniWrite(this.edY2.Value, ini, "Region", "Y2")
            IniWrite(this.slErr1.Value, ini, "Params", "Err1")
            IniWrite(this.slErr0.Value, ini, "Params", "Err0")
        }
    }
}

; ============================================================================
; START APPLICATION
; ============================================================================

try {
    app := FindTextGUI()
} catch as err {
    MsgBox("Error: " . err.Message, "Startup Error", "Icon!")
    ExitApp
}

return

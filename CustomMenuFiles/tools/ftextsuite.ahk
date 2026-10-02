#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir A_ScriptDir

#Include "FindText.ahk"

; ======================================================================================
; Hover tooltips (compact UX)
; ======================================================================================
class ToolTipMgr {
    static tips := Map()
    static enabled := true
    static lastHwnd := 0

    static Enable(on := true) {
        ToolTipMgr.enabled := !!on
        if (!ToolTipMgr.enabled)
            ToolTip
    }

    static Set(ctrlOrHwnd, text) {
        hwnd := IsObject(ctrlOrHwnd) ? ctrlOrHwnd.Hwnd : ctrlOrHwnd
        if (hwnd)
            ToolTipMgr.tips[hwnd] := text
    }

    static Attach(guiObj) {
        OnMessage(0x200, ToolTipMgr._OnMouseMove) ; WM_MOUSEMOVE
        guiObj.OnEvent("Close", (*) => (ToolTipMgr.lastHwnd := 0, ToolTip))
        guiObj.OnEvent("Escape", (*) => (ToolTipMgr.lastHwnd := 0, ToolTip))
    }

    static _OnMouseMove(wParam, lParam, msg, hwnd) {
        if (!ToolTipMgr.enabled)
            return

        pt := Buffer(8, 0)
        DllCall("GetCursorPos", "ptr", pt)
        x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
        hCtrl := DllCall("WindowFromPoint", "int", x, "int", y, "ptr")

        if (!hCtrl || !ToolTipMgr.tips.Has(hCtrl)) {
            if (ToolTipMgr.lastHwnd) {
                ToolTipMgr.lastHwnd := 0
                ToolTip
            }
            return
        }

        if (hCtrl = ToolTipMgr.lastHwnd)
            return

        ToolTipMgr.lastHwnd := hCtrl
        ToolTip ToolTipMgr.tips[hCtrl]
    }
}

; ======================================================================================
; App
; ======================================================================================
class FindTextTestSuiteApp {
    __New() {
        this.findTextObj := FindText()

        this.hbmCaptured := 0
        this.hbmScaled := 0

        this.tileOverlays := []
        this.matchOverlay := 0
        this.isRunning := false
        this.cancelRequested := false

        this.cfg := Map(
            "x1", 0, "y1", 0, "x2", A_ScreenWidth-1, "y2", A_ScreenHeight-1,
            "tileW", 64, "tileH", 48,
            "err1", 0.05, "err0", 0.05,
            "findAll", 0,
            "screenShot", 1,
            "pauseOnFound", 1,
            "scanDir", "LR_TB",
            "scanMode", "FullRegion (recommended)",
            "autoTileToPattern", 1,
            "useToleranceSweep", 1,
            "sweepSteps", 8,
            "sweepEndErr1", 0.25,
            "sweepEndErr0", 0.25,
            "tooltips", 1
        )

        this.savedPatterns := []

        this.BuildGui()
        this.LoadState()
        this.RefreshPatternList()
        this.UpdateRegionEditsFromCfg()
        this.UpdatePreview()
        this.UpdateInstructions()
        this.Log("Ready.")
    }

    ; ------------------------------------------------------------------------------
    ; HARD FIX: -DPIScale prevents Windows scaling from overlapping controls
    ; Layout: Tabs (top) + Preview (middle) + Log (bottom)
    ; Entire UI fits in 800x800.
    ; ------------------------------------------------------------------------------
    BuildGui() {
        ; -DPIScale is the make-or-break fix for overlap on scaled displays.
        this.gui := Gui("-DPIScale +MinSize800x800", "FindText Test Suite (800x800)")
        this.gui.SetFont("s9", "Segoe UI")
        ToolTipMgr.Attach(this.gui)

        ; ====== geometry ======
        M := 10
        W := 800
        H := 800
        InnerW := W - M*2

        TabsH := 280
        PreviewH := 360
        LogH := H - (M + TabsH + M + PreviewH + M + M)  ; remaining

        TabsX := M, TabsY := M
        PreviewX := M, PreviewY := TabsY + TabsH + M
        LogX := M, LogY := PreviewY + PreviewH + M

        ; ====== Tabs ======
        this.tabs := this.gui.Add("Tab3", "x" TabsX " y" TabsY " w" InnerW " h" TabsH, ["Pattern", "Region", "Scan", "Sweep", "Help"])
        ToolTipMgr.Set(this.tabs, "Use tabs to keep the UI compact. Nothing should overlap now.")

        ; Common layout helpers inside tabs
        RowStart(x, y, w) {
            return {x:x, y:y, w:w, h:24, gap:8}
        }
        AddLabel(guiObj, text, x, y, w := 120, h := 18) {
            return guiObj.Add("Text", "x" x " y" y " w" w " h" h, text)
        }
        AddEdit(guiObj, opts, value := "") {
            return guiObj.Add("Edit", opts, value)
        }

        ; ----------------------------------------------------------------------
        ; TAB: Pattern
        ; ----------------------------------------------------------------------
        this.gui.Tab := 1
        baseX := TabsX + 10
        baseY := TabsY + 35
        usableW := InnerW - 20

        AddLabel(this.gui, "Pattern (FindText text string)", baseX, baseY, usableW, 18)
        this.edPattern := this.gui.Add("Edit", "x" baseX " y" (baseY+20) " w" usableW " h80 vPattern")
        this.edPattern.SetFont("s9", "Consolas")
        this.edPattern.OnEvent("Change", (*) => (this.UpdateInstructions(), this.UpdatePreview()))
        ToolTipMgr.Set(this.edPattern, "Paste FindText pattern string here.")

        AddLabel(this.gui, "Saved patterns", baseX, baseY+110, usableW, 18)
        this.lv := this.gui.Add("ListView", "x" baseX " y" (baseY+130) " w" usableW " h90 Grid -Multi", ["Name"])
        this.lv.OnEvent("ItemSelect", (*) => this.OnPatternSelect())
        ToolTipMgr.Set(this.lv, "Select a saved pattern to load it.")

        btnY := baseY + 225
        btnW := Floor((usableW - 20) / 3)
        this.btnSavePattern := this.gui.Add("Button", "x" baseX " y" btnY " w" btnW " h28", "Save Pattern As...")
        this.btnSavePattern.OnEvent("Click", (*) => this.SavePatternPrompt())
        ToolTipMgr.Set(this.btnSavePattern, "Save current pattern under a name.")

        this.btnDeletePattern := this.gui.Add("Button", "x" (baseX+btnW+10) " y" btnY " w" btnW " h28", "Delete Selected")
        this.btnDeletePattern.OnEvent("Click", (*) => this.DeleteSelectedPattern())
        ToolTipMgr.Set(this.btnDeletePattern, "Delete selected saved pattern.")

        this.btnOpenFindTextGui := this.gui.Add("Button", "x" (baseX+(btnW+10)*2) " y" btnY " w" btnW " h28", "Open Capture GUI")
        this.btnOpenFindTextGui.OnEvent("Click", (*) => this.findTextObj.Gui("Show"))
        ToolTipMgr.Set(this.btnOpenFindTextGui, "Open FindText capture GUI to create patterns.")

        ; ----------------------------------------------------------------------
        ; TAB: Region
        ; ----------------------------------------------------------------------
        this.gui.Tab := 2
        baseX := TabsX + 10
        baseY := TabsY + 35
        usableW := InnerW - 20

        gb := this.gui.Add("GroupBox", "x" baseX " y" baseY " w" usableW " h150", "Search Region (screen coords)")
        y1 := baseY + 30

        AddLabel(this.gui, "X1", baseX+15, y1)
        this.edX1 := this.gui.Add("Edit", "x" (baseX+45) " y" (y1-2) " w90 h22 vX1", "")
        AddLabel(this.gui, "Y1", baseX+155, y1)
        this.edY1 := this.gui.Add("Edit", "x" (baseX+185) " y" (y1-2) " w90 h22 vY1", "")

        y2 := y1 + 35
        AddLabel(this.gui, "X2", baseX+15, y2)
        this.edX2 := this.gui.Add("Edit", "x" (baseX+45) " y" (y2-2) " w90 h22 vX2", "")
        AddLabel(this.gui, "Y2", baseX+155, y2)
        this.edY2 := this.gui.Add("Edit", "x" (baseX+185) " y" (y2-2) " w90 h22 vY2", "")

        ToolTipMgr.Set(this.edX1, "Region left (screen coord).")
        ToolTipMgr.Set(this.edY1, "Region top (screen coord).")
        ToolTipMgr.Set(this.edX2, "Region right (screen coord).")
        ToolTipMgr.Set(this.edY2, "Region bottom (screen coord).")

        this.btnUseMouseRegion := this.gui.Add("Button", "x" (baseX+320) " y" (y1-2) " w" 200 " h30", "Pick Region (2 clicks)")
        this.btnUseMouseRegion.OnEvent("Click", (*) => this.PickRegionTwoClicks())
        ToolTipMgr.Set(this.btnUseMouseRegion, "Click TOP-LEFT then BOTTOM-RIGHT.")

        this.btnApplyRegion := this.gui.Add("Button", "x" (baseX+530) " y" (y1-2) " w" 200 " h30", "Apply + Refresh")
        this.btnApplyRegion.OnEvent("Click", (*) => (this.ReadCfgFromEdits(), this.UpdatePreview(), this.UpdateInstructions()))
        ToolTipMgr.Set(this.btnApplyRegion, "Apply region values and refresh preview.")

        this.chkTooltips := this.gui.Add("CheckBox", "x" (baseX+320) " y" (y2-2) " w" 200 " h22 vTooltips", "Enable tooltips")
        this.chkTooltips.Value := this.cfg["tooltips"] ? 1 : 0
        this.chkTooltips.OnEvent("Click", (*) => (this.cfg["tooltips"] := this.chkTooltips.Value ? 1 : 0, ToolTipMgr.Enable(this.cfg["tooltips"])))
        ToolTipMgr.Set(this.chkTooltips, "Toggle hover-tooltips.")

        this.lblRegionTip := this.gui.Add("Text", "x" baseX " y" (baseY+165) " w" usableW " h70"
            , "Tip: Region must be bigger than the pattern footprint, or matching is impossible.`nPreview below shows what you are scanning.")

        ; ----------------------------------------------------------------------
        ; TAB: Scan
        ; ----------------------------------------------------------------------
        this.gui.Tab := 3
        baseX := TabsX + 10
        baseY := TabsY + 35
        usableW := InnerW - 20

        this.gui.Add("GroupBox", "x" baseX " y" baseY " w" usableW " h190", "Scan Settings")
        y := baseY + 30

        AddLabel(this.gui, "Mode", baseX+15, y)
        this.ddMode := this.gui.Add("DropDownList", "x" (baseX+60) " y" (y-3) " w260 vScanMode"
            , ["FullRegion (recommended)", "TiledSweep (visual demo)"])
        this.ddMode.Value := 1
        this.ddMode.OnEvent("Change", (*) => (this.ReadCfgFromEdits(), this.UpdateInstructions()))
        ToolTipMgr.Set(this.ddMode, "FullRegion is recommended; TiledSweep is a visual tile-based scan.")

        AddLabel(this.gui, "Dir", baseX+350, y)
        this.ddDir := this.gui.Add("DropDownList", "x" (baseX+385) " y" (y-3) " w170 vScanDir"
            , ["LR_TB","RL_TB","LR_BT","RL_BT","TB_LR","BT_LR","TB_RL","BT_RL"])
        this.ddDir.Value := 1
        this.ddDir.OnEvent("Change", (*) => (this.ReadCfgFromEdits(), this.UpdateInstructions()))
        ToolTipMgr.Set(this.ddDir, "Tile traversal direction (mainly for TiledSweep).")

        y += 35
        AddLabel(this.gui, "Err1", baseX+15, y)
        this.edErr1 := this.gui.Add("Edit", "x" (baseX+60) " y" (y-2) " w90 h22 vErr1", this.cfg["err1"])
        AddLabel(this.gui, "Err0", baseX+165, y)
        this.edErr0 := this.gui.Add("Edit", "x" (baseX+210) " y" (y-2) " w90 h22 vErr0", this.cfg["err0"])
        ToolTipMgr.Set(this.edErr1, "Tolerance Err1.")
        ToolTipMgr.Set(this.edErr0, "Tolerance Err0.")

        y += 32
        this.cbFindAll := this.gui.Add("CheckBox", "x" (baseX+15) " y" y " w140 vFindAll", "FindAll (slower)")
        this.cbScreenShot := this.gui.Add("CheckBox", "x" (baseX+170) " y" y " w210 vScreenShot", "New screenshot each call")
        this.cbPauseOnFound := this.gui.Add("CheckBox", "x" (baseX+390) " y" y " w160 vPauseOnFound", "Pause on found")

        this.cbFindAll.Value := this.cfg["findAll"] ? 1 : 0
        this.cbScreenShot.Value := this.cfg["screenShot"] ? 1 : 0
        this.cbPauseOnFound.Value := this.cfg["pauseOnFound"] ? 1 : 0

        y += 32
        AddLabel(this.gui, "Tile W", baseX+15, y)
        this.edTileW := this.gui.Add("Edit", "x" (baseX+60) " y" (y-2) " w90 h22 vTileW", this.cfg["tileW"])
        AddLabel(this.gui, "Tile H", baseX+165, y)
        this.edTileH := this.gui.Add("Edit", "x" (baseX+210) " y" (y-2) " w90 h22 vTileH", this.cfg["tileH"])
        this.cbAutoTile := this.gui.Add("CheckBox", "x" (baseX+320) " y" y " w260 vAutoTileToPattern", "Auto tile >= pattern size")
        this.cbAutoTile.Value := this.cfg["autoTileToPattern"] ? 1 : 0
        this.cbAutoTile.OnEvent("Click", (*) => (this.ReadCfgFromEdits(), this.UpdateInstructions()))
        ToolTipMgr.Set(this.cbAutoTile, "Prevents tile smaller than pattern (a common miss).")

        y += 40
        this.btnRun := this.gui.Add("Button", "x" (baseX+15) " y" y " w220 h34", "Run Scan")
        this.btnRun.OnEvent("Click", (*) => this.RunScan())
        this.btnCancel := this.gui.Add("Button", "x" (baseX+245) " y" y " w220 h34", "Cancel")
        this.btnCancel.OnEvent("Click", (*) => this.CancelScan())
        this.btnCancel.Enabled := false

        ; ----------------------------------------------------------------------
        ; TAB: Sweep
        ; ----------------------------------------------------------------------
        this.gui.Tab := 4
        baseX := TabsX + 10
        baseY := TabsY + 35
        usableW := InnerW - 20

        this.gui.Add("GroupBox", "x" baseX " y" baseY " w" usableW " h170", "Tolerance Sweep")
        y := baseY + 30
        this.cbSweep := this.gui.Add("CheckBox", "x" (baseX+15) " y" y " w420 vUseToleranceSweep", "Use sweep: strict -> loose until found")
        this.cbSweep.Value := this.cfg["useToleranceSweep"] ? 1 : 0
        this.cbSweep.OnEvent("Click", (*) => (this.ReadCfgFromEdits(), this.UpdateInstructions()))

        y += 35
        AddLabel(this.gui, "Steps", baseX+15, y)
        this.edSweepSteps := this.gui.Add("Edit", "x" (baseX+60) " y" (y-2) " w90 h22 vSweepSteps", this.cfg["sweepSteps"])
        AddLabel(this.gui, "End Err1", baseX+170, y)
        this.edSweepEndErr1 := this.gui.Add("Edit", "x" (baseX+230) " y" (y-2) " w90 h22 vSweepEndErr1", this.cfg["sweepEndErr1"])
        AddLabel(this.gui, "End Err0", baseX+340, y)
        this.edSweepEndErr0 := this.gui.Add("Edit", "x" (baseX+400) " y" (y-2) " w90 h22 vSweepEndErr0", this.cfg["sweepEndErr0"])

        this.gui.Add("Text", "x" (baseX+15) " y" (y+35) " w" usableW-30 " h60"
            , "Sweep tries multiple tolerance pairs. Useful for robustness and benchmarking.`nIf strict fails, looser passes may succeed.")

        ; ----------------------------------------------------------------------
        ; TAB: Help
        ; ----------------------------------------------------------------------
        this.gui.Tab := 5
        baseX := TabsX + 10
        baseY := TabsY + 35
        usableW := InnerW - 20
        this.edHelp := this.gui.Add("Edit", "x" baseX " y" baseY " w" usableW " h220 ReadOnly -Wrap")
        this.edHelp.Value :=
            "Workflow:`r`n" .
            "1) Pattern tab: open Capture GUI, capture a pattern, paste it.`r`n" .
            "2) Region tab: pick a region larger than the pattern footprint.`r`n" .
            "3) Scan tab: set tolerances and run.`r`n" .
            "Preview area shows region + overlays; green box = match.`r`n"

        ; end tabs
        this.gui.Tab := 0

        ; ====== Preview area ======
        this.gui.Add("Text", "x" PreviewX " y" (PreviewY-20) " w" InnerW " h18", "Preview (scaled) + scan overlay")
        this.previewHolder := this.gui.Add("Text", "x" PreviewX " y" PreviewY " w" InnerW " h" PreviewH " 0x200", "")
        this.pic := this.gui.Add("Picture", "x" PreviewX " y" PreviewY " w" InnerW " h" PreviewH " 0xE vPreviewPic", "")

        ; ====== Bottom log + instructions (non-overlapping fixed area) ======
        this.edHow := this.gui.Add("Edit", "x" LogX " y" LogY " w" InnerW " h" Floor(LogH/2)-5 " ReadOnly -Wrap")
        this.edHow.SetFont("s9", "Consolas")

        this.edLog := this.gui.Add("Edit", "x" LogX " y" (LogY + Floor(LogH/2)) " w" InnerW " h" Floor(LogH/2)-5 " ReadOnly -Wrap")
        this.edLog.SetFont("s9", "Consolas")

        ToolTipMgr.Set(this.pic, "Scaled region preview. Overlays show scan progress; green box = match.")
        ToolTipMgr.Enable(this.cfg["tooltips"])

        this.gui.OnEvent("Close", (*) => this.OnClose())

        ; Show fixed 800x800. No resizing means no drift.
        this.gui.Show("w800 h800")
    }

    OnClose() {
        this.SaveState()
        this.CleanupBitmaps()
        ExitApp
    }

    UpdateInstructions() {
        this.ReadCfgFromEdits()
        dims := this.ParsePatternDims(Trim(this.edPattern.Value))
        patW := dims.w, patH := dims.h

        rxW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        rxH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1

        msg := ""
        msg .= "Pattern W/H: " patW " x " patH "`r`n"
        msg .= "Region  W/H: " rxW " x " rxH "`r`n"

        if (patW > 0 && patH > 0 && (rxW < patW || rxH < patH)) {
            msg .= "`r`n!!! INVALID: region smaller than pattern. Pick a larger region.`r`n"
        } else {
            msg .= "`r`nUse: Capture pattern -> Pick region -> Run scan.`r`n"
        }

        msg .= "`r`nRecommended: FullRegion + (New screenshot ON if UI changes).`r`n"
        msg .= "Sweep ON for robustness/benchmarking.`r`n"
        this.edHow.Value := msg
    }

    RefreshPatternList() {
        this.lv.Delete()
        for _, item in this.savedPatterns
            this.lv.Add(, item.name)
    }

    OnPatternSelect() {
        row := this.lv.GetNext(0, "F")
        if (!row)
            return
        name := this.lv.GetText(row, 1)
        for _, item in this.savedPatterns {
            if (item.name = name) {
                this.edPattern.Value := item.text
                this.UpdateInstructions()
                this.UpdatePreview()
                break
            }
        }
    }

    SavePatternPrompt() {
        txt := Trim(this.edPattern.Value)
        if (txt = "") {
            this.Log("No pattern text to save.")
            return
        }
        ib := InputBox("Name this pattern:", "Save Pattern", "w380 h140")
        if (ib.Result != "OK")
            return
        name := Trim(ib.Value)
        if (name = "")
            return

        for idx, item in this.savedPatterns {
            if (item.name = name) {
                this.savedPatterns[idx].text := txt
                this.RefreshPatternList()
                this.Log("Saved (overwritten) pattern: " name)
                return
            }
        }
        this.savedPatterns.Push({name:name, text:txt})
        this.RefreshPatternList()
        this.Log("Saved pattern: " name)
    }

    DeleteSelectedPattern() {
        row := this.lv.GetNext(0, "F")
        if (!row)
            return
        name := this.lv.GetText(row, 1)
        for idx, item in this.savedPatterns {
            if (item.name = name) {
                this.savedPatterns.RemoveAt(idx)
                this.RefreshPatternList()
                this.Log("Deleted pattern: " name)
                return
            }
        }
    }

    UpdateRegionEditsFromCfg() {
        this.edX1.Value := this.cfg["x1"]
        this.edY1.Value := this.cfg["y1"]
        this.edX2.Value := this.cfg["x2"]
        this.edY2.Value := this.cfg["y2"]
        this.edTileW.Value := this.cfg["tileW"]
        this.edTileH.Value := this.cfg["tileH"]
        this.edErr1.Value := this.cfg["err1"]
        this.edErr0.Value := this.cfg["err0"]
        this.cbFindAll.Value := this.cfg["findAll"] ? 1 : 0
        this.cbScreenShot.Value := this.cfg["screenShot"] ? 1 : 0
        this.cbPauseOnFound.Value := this.cfg["pauseOnFound"] ? 1 : 0
        this.cbAutoTile.Value := this.cfg["autoTileToPattern"] ? 1 : 0
        this.cbSweep.Value := this.cfg["useToleranceSweep"] ? 1 : 0
        this.edSweepSteps.Value := this.cfg["sweepSteps"]
        this.edSweepEndErr1.Value := this.cfg["sweepEndErr1"]
        this.edSweepEndErr0.Value := this.cfg["sweepEndErr0"]

        try {
            this.ddMode.Text := this.cfg["scanMode"]
            this.ddDir.Text := this.cfg["scanDir"]
        }
        if (this.chkTooltips) {
            this.chkTooltips.Value := this.cfg["tooltips"] ? 1 : 0
            ToolTipMgr.Enable(this.cfg["tooltips"])
        }
    }

    ReadCfgFromEdits() {
        try {
            this.cfg["x1"] := Integer(this.edX1.Value)
            this.cfg["y1"] := Integer(this.edY1.Value)
            this.cfg["x2"] := Integer(this.edX2.Value)
            this.cfg["y2"] := Integer(this.edY2.Value)

            this.cfg["tileW"] := Max(1, Integer(this.edTileW.Value))
            this.cfg["tileH"] := Max(1, Integer(this.edTileH.Value))

            this.cfg["err1"] := Max(0, Min(0.99, Number(this.edErr1.Value)))
            this.cfg["err0"] := Max(0, Min(0.99, Number(this.edErr0.Value)))

            this.cfg["findAll"] := this.cbFindAll.Value ? 1 : 0
            this.cfg["screenShot"] := this.cbScreenShot.Value ? 1 : 0
            this.cfg["pauseOnFound"] := this.cbPauseOnFound.Value ? 1 : 0

            this.cfg["scanMode"] := this.ddMode.Text
            this.cfg["scanDir"] := this.ddDir.Text
            this.cfg["autoTileToPattern"] := this.cbAutoTile.Value ? 1 : 0

            this.cfg["useToleranceSweep"] := this.cbSweep.Value ? 1 : 0
            this.cfg["sweepSteps"] := Max(1, Integer(this.edSweepSteps.Value))
            this.cfg["sweepEndErr1"] := Max(0, Min(0.99, Number(this.edSweepEndErr1.Value)))
            this.cfg["sweepEndErr0"] := Max(0, Min(0.99, Number(this.edSweepEndErr0.Value)))

            if (this.chkTooltips)
                this.cfg["tooltips"] := this.chkTooltips.Value ? 1 : 0
        } catch as e {
            this.Log("Config parse error: " e.Message)
        }
    }

    PickRegionTwoClicks() {
        this.Log("Region pick: click TOP-LEFT, then BOTTOM-RIGHT.")
        CoordMode "Mouse", "Screen"

        ToolTip "Click TOP-LEFT..."
        KeyWait "LButton", "D"
        MouseGetPos &x1, &y1
        KeyWait "LButton", "U"

        ToolTip "Click BOTTOM-RIGHT..."
        Sleep 150
        KeyWait "LButton", "D"
        MouseGetPos &x2, &y2
        KeyWait "LButton", "U"
        ToolTip

        this.cfg["x1"] := Min(x1, x2)
        this.cfg["y1"] := Min(y1, y2)
        this.cfg["x2"] := Max(x1, x2)
        this.cfg["y2"] := Max(y1, y2)

        this.UpdateRegionEditsFromCfg()
        this.UpdatePreview()
        this.UpdateInstructions()
        this.Log("Picked region: (" this.cfg["x1"] "," this.cfg["y1"] ") -> (" this.cfg["x2"] "," this.cfg["y2"] ")")
    }

    UpdatePreview(rebuildOverlays := false) {
        this.ReadCfgFromEdits()

        x := this.cfg["x1"], y := this.cfg["y1"]
        w := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        h := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        if (w < 2 || h < 2)
            return

        this.pic.GetPos(&px, &py, &pw, &ph)
        if (pw < 50 || ph < 50)
            return

        this.CleanupBitmaps()
        this.hbmCaptured := this.CaptureScreenRegionToHBITMAP(x, y, w, h)
        if (!this.hbmCaptured)
            return

        this.hbmScaled := this.ScaleHBITMAP(this.hbmCaptured, pw, ph)
        if (!this.hbmScaled)
            return

        this.pic.Value := "HBITMAP:*" this.hbmScaled
        this.BuildTileOverlays(pw, ph)
        this.HideMatchOverlay()
    }

    BuildTileOverlays(picW, picH) {
        for _, ctrl in this.tileOverlays {
            try ctrl.Destroy()
        }
        this.tileOverlays := []
        this.HideMatchOverlay()

        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1

        tileW := Max(16, this.cfg["tileW"])
        tileH := Max(16, this.cfg["tileH"])
        tilesX := Ceil(regionW / tileW)
        tilesY := Ceil(regionH / tileH)

        this.pic.GetPos(&px, &py, , )

        Loop tilesY {
            ty := A_Index - 1
            Loop tilesX {
                tx := A_Index - 1
                sx := Floor((tx * tileW) * picW / regionW)
                sy := Floor((ty * tileH) * picH / regionH)
                sw := Max(2, Ceil(tileW * picW / regionW))
                sh := Max(2, Ceil(tileH * picH / regionH))

                if (sx + sw > picW)
                    sw := picW - sx
                if (sy + sh > picH)
                    sh := picH - sy
                if (sw < 2 || sh < 2)
                    continue

                ctrl := this.gui.Add("Progress", "x" (px+sx) " y" (py+sy) " w" sw " h" sh " -E0x20000 Background000000 c000000")
                ctrl.Value := 0
                ctrl.Visible := false
                this.tileOverlays.Push(ctrl)
            }
        }
    }

    ResetTileOverlayVisuals() {
        for _, ctrl in this.tileOverlays {
            ctrl.Value := 0
            ctrl.Opt("Background000000 c000000")
            ctrl.Visible := false
        }
    }

    ShowTile(idx, intensity := 30) {
        if (idx < 1 || idx > this.tileOverlays.Length)
            return
        ctrl := this.tileOverlays[idx]
        ctrl.Visible := true
        ctrl.Value := Max(0, Min(100, intensity))
        ctrl.Opt("Background000000 c" this.RampColor(intensity))
    }

    RampColor(intensity) {
        intensity := Max(0, Min(100, intensity))
        r := 0x22 + Floor((0xFF - 0x22) * (intensity / 100))
        return Format("{:02X}{:02X}{:02X}", r, 0x00, 0x00)
    }

    DrawMatchBox(foundX, foundY, foundW, foundH) {
        this.HideMatchOverlay()

        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1

        this.pic.GetPos(&px, &py, &pw, &ph)

        rx := foundX - this.cfg["x1"]
        ry := foundY - this.cfg["y1"]

        sx := Floor(rx * pw / regionW)
        sy := Floor(ry * ph / regionH)
        sw := Max(2, Ceil(foundW * pw / regionW))
        sh := Max(2, Ceil(foundH * ph / regionH))

        t := 2
        green := "00FF00"

        top := this.gui.Add("Text", "x" (px+sx) " y" (py+sy) " w" sw " h" t " Background" green)
        left := this.gui.Add("Text", "x" (px+sx) " y" (py+sy) " w" t " h" sh " Background" green)
        right := this.gui.Add("Text", "x" (px+sx+sw-t) " y" (py+sy) " w" t " h" sh " Background" green)
        bottom := this.gui.Add("Text", "x" (px+sx) " y" (py+sy+sh-t) " w" sw " h" t " Background" green)

        this.matchOverlay := [top, left, right, bottom]
    }

    HideMatchOverlay() {
        if (this.matchOverlay) {
            for _, c in this.matchOverlay {
                try c.Destroy()
            }
            this.matchOverlay := 0
        }
    }

    RunScan() {
        if (this.isRunning)
            return

        txt := Trim(this.edPattern.Value)
        if (txt = "") {
            this.Log("No pattern text. Paste a FindText pattern string first.")
            return
        }

        this.ReadCfgFromEdits()
        this.UpdatePreview()

        dims := this.ParsePatternDims(txt)
        patW := dims.w, patH := dims.h

        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1

        if (patW > 0 && patH > 0 && (regionW < patW || regionH < patH)) {
            this.Log("IMPOSSIBLE: region is smaller than pattern. Region=" regionW "x" regionH " Pattern=" patW "x" patH)
            MsgBox "Your region is smaller than the pattern footprint.`n`nRegion: " regionW "x" regionH "`nPattern: " patW "x" patH "`n`nPick a larger region.", "FindText Test Suite", "Icon!"
            return
        }

        this.isRunning := true
        this.cancelRequested := false
        this.btnRun.Enabled := false
        this.btnCancel.Enabled := true

        this.ResetTileOverlayVisuals()
        this.HideMatchOverlay()

        startTick := A_TickCount
        this.Log("---- RUN START ----")
        this.Log("Mode: " this.cfg["scanMode"])
        this.Log("Region: (" this.cfg["x1"] "," this.cfg["y1"] ") -> (" this.cfg["x2"] "," this.cfg["y2"] ")  (" regionW "x" regionH ")")
        this.Log("Pattern W/H: " patW " x " patH)
        this.Log("Err1/Err0 base: " this.cfg["err1"] " / " this.cfg["err0"])
        this.Log("Sweep: " this.cfg["useToleranceSweep"] " | steps=" this.cfg["sweepSteps"] " end=" this.cfg["sweepEndErr1"] "/" this.cfg["sweepEndErr0"])
        this.Log("FindAll: " this.cfg["findAll"] " | NewShotEachCall: " this.cfg["screenShot"])
        this.Log("")

        if (this.cfg["scanMode"] = "FullRegion (recommended)") {
            this.RunFullRegion(txt, patW, patH, startTick)
        } else {
            this.RunTiledSweep(txt, patW, patH, startTick)
        }

        this.isRunning := false
        this.btnRun.Enabled := true
        this.btnCancel.Enabled := false
    }

    RunFullRegion(patternText, patW, patH, startTick) {
        tilesCount := this.tileOverlays.Length
        sweep := this.BuildToleranceSweep()
        stepIndex := 0
        found := false
        foundInfo := 0

        for _, step in sweep {
            if (this.cancelRequested)
                break

            stepIndex++
            intensity := Min(100, 10 + Floor(90 * (stepIndex / sweep.Length)))
            Loop tilesCount
                this.ShowTile(A_Index, intensity)

            ox := 0, oy := 0
            ok := this.findTextObj.FindText(&ox, &oy
                , this.cfg["x1"], this.cfg["y1"], this.cfg["x2"], this.cfg["y2"]
                , step.err1, step.err0
                , patternText
                , this.cfg["screenShot"] ? 1 : 0
                , this.cfg["findAll"] ? 1 : 0
            )

            this.Log("Pass " stepIndex "/" sweep.Length "  err1/err0=" step.err1 "/" step.err0 " -> " (IsObject(ok) && ok.Length ? "FOUND" : "no"))

            if (IsObject(ok) && ok.Length) {
                found := true
                foundInfo := ok[1]
                break
            }
            Sleep 25
        }

        elapsed := A_TickCount - startTick
        if (this.cancelRequested) {
            this.Log("---- CANCELED ---- (" elapsed " ms)")
            return
        }

        if (found) {
            this.DrawMatchBox(foundInfo.x, foundInfo.y, foundInfo.w, foundInfo.h)
            this.Log("---- FOUND ----")
            this.Log("Elapsed: " elapsed " ms")
            this.Log("Found X/Y: " foundInfo.x ", " foundInfo.y)
            this.Log("Found W/H: " foundInfo.w " x " foundInfo.h)
            this.Log("")
            if (this.cfg["pauseOnFound"]) {
                this.Log("Paused. Press OK to end run.")
                MsgBox "Found match. Benchmark captured. (See log)", "FindText Test Suite", "OK"
            }
        } else {
            this.Log("---- NOT FOUND ----")
            this.Log("Elapsed: " elapsed " ms")
            this.Log("")
        }
    }

    RunTiledSweep(patternText, patW, patH, startTick) {
        tileW := this.cfg["tileW"]
        tileH := this.cfg["tileH"]

        if (this.cfg["autoTileToPattern"] && patW > 0 && patH > 0) {
            tileW := Max(tileW, patW)
            tileH := Max(tileH, patH)
        }

        tileW := Max(16, tileW)
        tileH := Max(16, tileH)

        regionW := Abs(this.cfg["x2"] - this.cfg["x1"]) + 1
        regionH := Abs(this.cfg["y2"] - this.cfg["y1"]) + 1
        tilesX := Ceil(regionW / tileW)
        tilesY := Ceil(regionH / tileH)

        tiles := this.BuildTileSweepWithSize(tileW, tileH, tilesX, tilesY)
        sweep := this.BuildToleranceSweep()

        found := false
        foundInfo := 0
        tilesScanned := 0
        passUsed := 0

        for _, tile in tiles {
            if (this.cancelRequested)
                break

            tilesScanned++
            intensity := Min(100, 10 + Floor(90 * (tilesScanned / tiles.Length)))
            this.ShowTile(tile.overlayIndex, intensity)

            for passIdx, step in sweep {
                if (this.cancelRequested)
                    break

                ox := 0, oy := 0
                ok := this.findTextObj.FindText(&ox, &oy
                    , tile.x1, tile.y1, tile.x2, tile.y2
                    , step.err1, step.err0
                    , patternText
                    , this.cfg["screenShot"] ? 1 : 0
                    , this.cfg["findAll"] ? 1 : 0
                )

                if (IsObject(ok) && ok.Length) {
                    found := true
                    foundInfo := ok[1]
                    passUsed := passIdx
                    break
                }
            }

            if (found)
                break

            Sleep 10
        }

        elapsed := A_TickCount - startTick
        if (this.cancelRequested) {
            this.Log("---- CANCELED ---- (" elapsed " ms, tiles scanned: " tilesScanned ")")
            return
        }

        if (found) {
            this.DrawMatchBox(foundInfo.x, foundInfo.y, foundInfo.w, foundInfo.h)
            this.Log("---- FOUND ----")
            this.Log("Elapsed: " elapsed " ms")
            this.Log("Tiles scanned: " tilesScanned " / " tiles.Length)
            this.Log("Pass used: " passUsed " / " sweep.Length)
            this.Log("Found X/Y: " foundInfo.x ", " foundInfo.y)
            this.Log("Found W/H: " foundInfo.w " x " foundInfo.h)
            this.Log("")
            if (this.cfg["pauseOnFound"]) {
                this.Log("Paused. Press OK to end run.")
                MsgBox "Found match. Benchmark captured. (See log)", "FindText Test Suite", "OK"
            }
        } else {
            this.Log("---- NOT FOUND ----")
            this.Log("Elapsed: " elapsed " ms")
            this.Log("Tiles scanned: " tilesScanned " / " tiles.Length)
            this.Log("")
        }
    }

    BuildToleranceSweep() {
        sweep := []
        if (!this.cfg["useToleranceSweep"]) {
            sweep.Push({err1:this.cfg["err1"], err0:this.cfg["err0"]})
            return sweep
        }

        steps := this.cfg["sweepSteps"]
        startE1 := this.cfg["err1"], startE0 := this.cfg["err0"]
        endE1 := this.cfg["sweepEndErr1"], endE0 := this.cfg["sweepEndErr0"]

        if (steps = 1) {
            sweep.Push({err1:startE1, err0:startE0})
            return sweep
        }

        Loop steps {
            i := A_Index - 1
            t := i / (steps - 1)
            e1 := startE1 + (endE1 - startE1) * t
            e0 := startE0 + (endE0 - startE0) * t
            sweep.Push({err1:Round(e1, 3), err0:Round(e0, 3)})
        }
        return sweep
    }

    BuildTileSweepWithSize(tileW, tileH, tilesX, tilesY) {
        x1 := this.cfg["x1"], y1 := this.cfg["y1"]
        x2 := this.cfg["x2"], y2 := this.cfg["y2"]

        tiles := []
        dir := this.cfg["scanDir"]

        pushTile := (tx, ty) => (
            tx1 := x1 + tx*tileW,
            ty1 := y1 + ty*tileH,
            tx2 := Min(x2, tx1 + tileW - 1),
            ty2 := Min(y2, ty1 + tileH - 1),
            overlayIndex := this.MapOverlayIndex(tx, ty, tilesX),
            tiles.Push({x1:tx1, y1:ty1, x2:tx2, y2:ty2, overlayIndex:overlayIndex})
        )

        if (dir = "LR_TB") {
            Loop tilesY {
                ty := A_Index - 1
                Loop tilesX {
                    tx := A_Index - 1
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "RL_TB") {
            Loop tilesY {
                ty := A_Index - 1
                Loop tilesX {
                    tx := tilesX - A_Index
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "LR_BT") {
            Loop tilesY {
                ty := tilesY - A_Index
                Loop tilesX {
                    tx := A_Index - 1
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "RL_BT") {
            Loop tilesY {
                ty := tilesY - A_Index
                Loop tilesX {
                    tx := tilesX - A_Index
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "TB_LR") {
            Loop tilesX {
                tx := A_Index - 1
                Loop tilesY {
                    ty := A_Index - 1
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "BT_LR") {
            Loop tilesX {
                tx := A_Index - 1
                Loop tilesY {
                    ty := tilesY - A_Index
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "TB_RL") {
            Loop tilesX {
                tx := tilesX - A_Index
                Loop tilesY {
                    ty := A_Index - 1
                    pushTile(tx, ty)
                }
            }
        } else if (dir = "BT_RL") {
            Loop tilesX {
                tx := tilesX - A_Index
                Loop tilesY {
                    ty := tilesY - A_Index
                    pushTile(tx, ty)
                }
            }
        } else {
            Loop tilesY {
                ty := A_Index - 1
                Loop tilesX {
                    tx := A_Index - 1
                    pushTile(tx, ty)
                }
            }
        }

        return tiles
    }

    MapOverlayIndex(tx, ty, tilesX) => (ty*tilesX + tx + 1)

    ParsePatternDims(patternText) {
        w := 0, h := 0
        if RegExMatch(patternText, "\$(\d+)", &mH)
            h := Integer(mH[1])
        if RegExMatch(patternText, "W(\d+)", &mW)
            w := Integer(mW[1])
        return {w:w, h:h}
    }

    CancelScan() {
        if (!this.isRunning)
            return
        this.cancelRequested := true
        this.Log("Cancel requested...")
    }

    Log(msg) {
        t := FormatTime(A_Now, "HH:mm:ss")
        this.edLog.Value .= "[" t "] " msg "`r`n"
        SendMessage 0x115, 7, 0, this.edLog.Hwnd
    }

    LoadState() {
        ini := A_ScriptDir "\FindText_TestSuite.ini"
        if !FileExist(ini)
            return

        this.cfg["x1"] := IniRead(ini, "region", "x1", this.cfg["x1"])
        this.cfg["y1"] := IniRead(ini, "region", "y1", this.cfg["y1"])
        this.cfg["x2"] := IniRead(ini, "region", "x2", this.cfg["x2"])
        this.cfg["y2"] := IniRead(ini, "region", "y2", this.cfg["y2"])

        this.cfg["tileW"] := IniRead(ini, "scan", "tileW", this.cfg["tileW"])
        this.cfg["tileH"] := IniRead(ini, "scan", "tileH", this.cfg["tileH"])
        this.cfg["err1"] := IniRead(ini, "scan", "err1", this.cfg["err1"])
        this.cfg["err0"] := IniRead(ini, "scan", "err0", this.cfg["err0"])
        this.cfg["findAll"] := IniRead(ini, "scan", "findAll", this.cfg["findAll"])
        this.cfg["screenShot"] := IniRead(ini, "scan", "screenShot", this.cfg["screenShot"])
        this.cfg["pauseOnFound"] := IniRead(ini, "scan", "pauseOnFound", this.cfg["pauseOnFound"])
        this.cfg["scanDir"] := IniRead(ini, "scan", "scanDir", this.cfg["scanDir"])
        this.cfg["scanMode"] := IniRead(ini, "scan", "scanMode", this.cfg["scanMode"])
        this.cfg["autoTileToPattern"] := IniRead(ini, "scan", "autoTileToPattern", this.cfg["autoTileToPattern"])

        this.cfg["useToleranceSweep"] := IniRead(ini, "sweep", "useToleranceSweep", this.cfg["useToleranceSweep"])
        this.cfg["sweepSteps"] := IniRead(ini, "sweep", "sweepSteps", this.cfg["sweepSteps"])
        this.cfg["sweepEndErr1"] := IniRead(ini, "sweep", "sweepEndErr1", this.cfg["sweepEndErr1"])
        this.cfg["sweepEndErr0"] := IniRead(ini, "sweep", "sweepEndErr0", this.cfg["sweepEndErr0"])
        this.cfg["tooltips"] := IniRead(ini, "ui", "tooltips", this.cfg["tooltips"])

        pCount := IniRead(ini, "patterns", "count", 0)
        Loop pCount {
            i := A_Index
            nm := IniRead(ini, "patterns", "name" i, "")
            tx := IniRead(ini, "patterns", "text" i, "")
            if (nm != "" && tx != "")
                this.savedPatterns.Push({name:nm, text:tx})
        }
        ToolTipMgr.Enable(this.cfg["tooltips"])
    }

    SaveState() {
        ini := A_ScriptDir "\FindText_TestSuite.ini"
        this.ReadCfgFromEdits()

        IniWrite this.cfg["x1"], ini, "region", "x1"
        IniWrite this.cfg["y1"], ini, "region", "y1"
        IniWrite this.cfg["x2"], ini, "region", "x2"
        IniWrite this.cfg["y2"], ini, "region", "y2"

        IniWrite this.cfg["tileW"], ini, "scan", "tileW"
        IniWrite this.cfg["tileH"], ini, "scan", "tileH"
        IniWrite this.cfg["err1"], ini, "scan", "err1"
        IniWrite this.cfg["err0"], ini, "scan", "err0"
        IniWrite this.cfg["findAll"], ini, "scan", "findAll"
        IniWrite this.cfg["screenShot"], ini, "scan", "screenShot"
        IniWrite this.cfg["pauseOnFound"], ini, "scan", "pauseOnFound"
        IniWrite this.cfg["scanDir"], ini, "scan", "scanDir"
        IniWrite this.cfg["scanMode"], ini, "scan", "scanMode"
        IniWrite this.cfg["autoTileToPattern"], ini, "scan", "autoTileToPattern"

        IniWrite this.cfg["useToleranceSweep"], ini, "sweep", "useToleranceSweep"
        IniWrite this.cfg["sweepSteps"], ini, "sweep", "sweepSteps"
        IniWrite this.cfg["sweepEndErr1"], ini, "sweep", "sweepEndErr1"
        IniWrite this.cfg["sweepEndErr0"], ini, "sweep", "sweepEndErr0"
        IniWrite this.cfg["tooltips"], ini, "ui", "tooltips"

        IniWrite this.savedPatterns.Length, ini, "patterns", "count"
        i := 0
        for _, item in this.savedPatterns {
            i++
            IniWrite item.name, ini, "patterns", "name" i
            IniWrite item.text, ini, "patterns", "text" i
        }
    }

    CleanupBitmaps() {
        if (this.hbmScaled) {
            DllCall("DeleteObject", "ptr", this.hbmScaled)
            this.hbmScaled := 0
        }
        if (this.hbmCaptured) {
            DllCall("DeleteObject", "ptr", this.hbmCaptured)
            this.hbmCaptured := 0
        }
    }

    CaptureScreenRegionToHBITMAP(x, y, w, h) {
        hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        hdcMem := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        hbm := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", w, "int", h, "ptr")
        obm := DllCall("SelectObject", "ptr", hdcMem, "ptr", hbm, "ptr")

        ok := DllCall("BitBlt"
            , "ptr", hdcMem, "int", 0, "int", 0, "int", w, "int", h
            , "ptr", hdcScreen, "int", x, "int", y
            , "uint", 0x00CC0020
        )

        DllCall("SelectObject", "ptr", hdcMem, "ptr", obm)
        DllCall("DeleteDC", "ptr", hdcMem)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)

        if (!ok) {
            DllCall("DeleteObject", "ptr", hbm)
            return 0
        }
        return hbm
    }

    ScaleHBITMAP(hbmSrc, newW, newH) {
        if (!hbmSrc)
            return 0

        hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
        hdcSrc := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
        hdcDst := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")

        bm := Buffer(32, 0)
        DllCall("GetObject", "ptr", hbmSrc, "int", 32, "ptr", bm)
        srcW := NumGet(bm, 4, "int")
        srcH := NumGet(bm, 8, "int")

        hbmDst := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", newW, "int", newH, "ptr")
        obmSrc := DllCall("SelectObject", "ptr", hdcSrc, "ptr", hbmSrc, "ptr")
        obmDst := DllCall("SelectObject", "ptr", hdcDst, "ptr", hbmDst, "ptr")

        DllCall("SetStretchBltMode", "ptr", hdcDst, "int", 4)

        ok := DllCall("StretchBlt"
            , "ptr", hdcDst, "int", 0, "int", 0, "int", newW, "int", newH
            , "ptr", hdcSrc, "int", 0, "int", 0, "int", srcW, "int", srcH
            , "uint", 0x00CC0020
        )

        DllCall("SelectObject", "ptr", hdcSrc, "ptr", obmSrc)
        DllCall("SelectObject", "ptr", hdcDst, "ptr", obmDst)

        DllCall("DeleteDC", "ptr", hdcSrc)
        DllCall("DeleteDC", "ptr", hdcDst)
        DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)

        if (!ok) {
            DllCall("DeleteObject", "ptr", hbmDst)
            return 0
        }
        return hbmDst
    }
}

app := FindTextTestSuiteApp()
return

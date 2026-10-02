; FindText GUI Manager for AHK v2
; Simplifies using the FindText OCR functionality

class FindTextManager {
    static GuiObj := ""
    static Results := []
    static LastSearch := ""
    static FT := ""
    
    __New() {
        ; Initialize the FindText instance
        this.FT := FindText()
    }
    
    Show() {
        this.CreateGUI()
        this.GuiObj.Show("Center")
    }
    
    CreateGUI() {
        ; Destroy existing GUI if it exists
        if (this.GuiObj) {
            try this.GuiObj.Destroy()
        }
        
        ; Create main GUI
        this.GuiObj := Gui("+Resize +MinSize", "FindText GUI Manager")
        this.GuiObj.OnEvent("Close", (*) => this.GuiObj.Destroy())
        this.GuiObj.OnEvent("Size", (*) => this.AutoResize())
        
        ; Create menu bar
        this.CreateMenu()
        
        ; Create main tabs
        this.TabControl := this.GuiObj.Add("Tab3", "x10 y10 w780 h540", ["Capture", "Search", "Manage", "Settings"])
        
        ; Capture tab
        this.TabControl.UseTab(1)
        this.CreateCaptureTab()
        
        ; Search tab
        this.TabControl.UseTab(2)
        this.CreateSearchTab()
        
        ; Manage tab
        this.TabControl.UseTab(3)
        this.CreateManageTab()
        
        ; Settings tab
        this.TabControl.UseTab(4)
        this.CreateSettingsTab()
        
        this.TabControl.UseTab() ; End tabs
        
        ; Status bar
        this.StatusBar := this.GuiObj.Add("StatusBar",, "Ready")
        
        this.AutoResize()
    }
    
    CreateMenu() {
        MenuBar := Menu()
        
        ; File menu
        FileMenu := Menu()
        FileMenu.Add("Load Library", (*) => this.LoadLibrary())
        FileMenu.Add("Save Library", (*) => this.SaveLibrary())
        FileMenu.Add("Export Code", (*) => this.ExportCode())
        FileMenu.AddSeparator()
        FileMenu.Add("Exit", (*) => this.GuiObj.Destroy())
        MenuBar.Add("File", FileMenu)
        
        ; Tools menu
        ToolsMenu := Menu()
        ToolsMenu.Add("Capture Screen Region", (*) => this.CaptureRegion())
        ToolsMenu.Add("Test Current Pattern", (*) => this.TestPattern())
        ToolsMenu.Add("Clear Results", (*) => this.ClearResults())
        MenuBar.Add("Tools", ToolsMenu)
        
        ; Help menu
        HelpMenu := Menu()
        HelpMenu.Add("About", (*) => this.ShowAbout())
        MenuBar.Add("Help", HelpMenu)
        
        this.GuiObj.Menu := MenuBar
    }
    
    CreateCaptureTab() {
        this.GuiObj.Add("GroupBox", "x20 y40 w760 h200", "Screen Capture")
        this.CaptureAreaBtn := this.GuiObj.Add("Button", "x40 y70 w120 h30", "Capture Area")
        this.CaptureAreaBtn.OnEvent("Click", (*) => this.CaptureArea())
        
        this.CaptureWindowBtn := this.GuiObj.Add("Button", "x180 y70 w120 h30", "Capture Window")
        this.CaptureWindowBtn.OnEvent("Click", (*) => this.CaptureWindow())
        
        this.CaptureFileBtn := this.GuiObj.Add("Button", "x320 y70 w120 h30", "From File")
        this.CaptureFileBtn.OnEvent("Click", (*) => this.CaptureFromFile())
        
        this.GuiObj.Add("Text", "x40 y120 w100 h20", "Tolerance:")
        this.ToleranceEdit := this.GuiObj.Add("Edit", "x150 y120 w60 h20", "0.05")
        this.GuiObj.Add("Text", "x230 y120 w100 h20", "Background Tol:")
        this.BgToleranceEdit := this.GuiObj.Add("Edit", "x340 y120 w60 h20", "0.05")
        
        this.GenerateCodeBtn := this.GuiObj.Add("Button", "x40 y160 w120 h30", "Generate Code")
        this.GenerateCodeBtn.OnEvent("Click", (*) => this.GenerateCode())
        
        this.TestCaptureBtn := this.GuiObj.Add("Button", "x180 y160 w120 h30", "Test Capture")
        this.TestCaptureBtn.OnEvent("Click", (*) => this.TestCapture())
        
        this.CapturePreview := this.GuiObj.Add("Picture", "x450 y70 w300 h150", "")
        this.CapturePreview.Value := "HICON:*" ; Placeholder
        
        this.GuiObj.Add("GroupBox", "x20 y260 w760 h200", "Generated Code")
        this.CodeEdit := this.GuiObj.Add("Edit", "x40 y290 w720 h150", ";; Generated code will appear here")
    }
    
    CreateSearchTab() {
        this.GuiObj.Add("GroupBox", "x20 y40 w760 h200", "Search Settings")
        this.GuiObj.Add("Text", "x40 y70 w100 h20", "Search Area:")
        this.SearchX1 := this.GuiObj.Add("Edit", "x150 y70 w50 h20", "0")
        this.GuiObj.Add("Text", "x210 y70 w20 h20", ",")
        this.SearchY1 := this.GuiObj.Add("Edit", "x230 y70 w50 h20", "0")
        this.GuiObj.Add("Text", "x290 y70 w20 h20", "to")
        this.SearchX2 := this.GuiObj.Add("Edit", "x310 y70 w50 h20", A_ScreenWidth)
        this.GuiObj.Add("Text", "x370 y70 w20 h20", ",")
        this.SearchY2 := this.GuiObj.Add("Edit", "x390 y70 w50 h20", A_ScreenHeight)
        
        this.FindAllCheck := this.GuiObj.Add("CheckBox", "x40 y110 w150 h20", "Find All Occurrences")
        this.WaitModeCheck := this.GuiObj.Add("CheckBox", "x200 y110 w150 h20", "Wait for Appearance")
        
        this.SearchNowBtn := this.GuiObj.Add("Button", "x40 y150 w120 h30", "Search Now")
        this.SearchNowBtn.OnEvent("Click", (*) => this.SearchNow())
        
        this.LoadPatternBtn := this.GuiObj.Add("Button", "x180 y150 w120 h30", "Load Pattern")
        this.LoadPatternBtn.OnEvent("Click", (*) => this.LoadPattern())
        
        this.GuiObj.Add("GroupBox", "x20 y260 w760 h200", "Search Results")
        this.ResultsList := this.GuiObj.Add("ListView", "x40 y290 w720 h150", ["X", "Y", "Width", "Height", "ID"])
        this.ResultsList.OnEvent("DoubleClick", (*) => this.ResultDoubleClick())
        
        this.ClickResultBtn := this.GuiObj.Add("Button", "x40 y450 w120 h30", "Click Result")
        this.ClickResultBtn.OnEvent("Click", (*) => this.ClickResult())
        
        this.CopyCoordsBtn := this.GuiObj.Add("Button", "x180 y450 w120 h30", "Copy Coordinates")
        this.CopyCoordsBtn.OnEvent("Click", (*) => this.CopyCoordinates())
    }
    
    CreateManageTab() {
        this.GuiObj.Add("GroupBox", "x20 y40 w760 h200", "Pattern Library")
        this.PatternList := this.GuiObj.Add("ListView", "x40 y70 w720 h150", ["Name", "Pattern", "Date"])
        
        this.AddPatternBtn := this.GuiObj.Add("Button", "x40 y230 w120 h30", "Add Pattern")
        this.AddPatternBtn.OnEvent("Click", (*) => this.AddPattern())
        
        this.RemovePatternBtn := this.GuiObj.Add("Button", "x180 y230 w120 h30", "Remove Pattern")
        this.RemovePatternBtn.OnEvent("Click", (*) => this.RemovePattern())
        
        this.EditPatternBtn := this.GuiObj.Add("Button", "x320 y230 w120 h30", "Edit Pattern")
        this.EditPatternBtn.OnEvent("Click", (*) => this.EditPattern())
        
        this.GuiObj.Add("GroupBox", "x20 y280 w760 h200", "Pattern Details")
        this.PatternEdit := this.GuiObj.Add("Edit", "x40 y310 w720 h150", ";; Select a pattern to view details")
    }
    
    CreateSettingsTab() {
        this.GuiObj.Add("GroupBox", "x20 y40 w760 h200", "General Settings")
        this.BindWindowCheck := this.GuiObj.Add("CheckBox", "x40 y70 w200 h20", "Bind Window for Search")
        this.ShowAreaCheck := this.GuiObj.Add("CheckBox", "x40 y100 w200 h20", "Show Search Area")
        this.AutoCopyCheck := this.GuiObj.Add("CheckBox", "x40 y130 w200 h20", "Auto-copy Coordinates")
        
        this.GuiObj.Add("Text", "x40 y170 w100 h20", "Default Wait Time:")
        this.WaitTimeEdit := this.GuiObj.Add("Edit", "x150 y170 w60 h20", "5")
        this.GuiObj.Add("Text", "x220 y170 w80 h20", "seconds")
        
        this.GuiObj.Add("GroupBox", "x20 y260 w760 h200", "Advanced Settings")
        this.ResetSettingsBtn := this.GuiObj.Add("Button", "x40 y290 w120 h30", "Reset Settings")
        this.ResetSettingsBtn.OnEvent("Click", (*) => this.ResetSettings())
        
        this.ShowFTGUIBtn := this.GuiObj.Add("Button", "x180 y290 w120 h30", "Show FT GUI")
        this.ShowFTGUIBtn.OnEvent("Click", (*) => this.ShowFTGUI())
    }
    
    AutoResize() {
        ; Basic auto-resize logic
        if (this.GuiObj) {
            WinGetPos(,, &Width, &Height, this.GuiObj.Hwnd)
            this.TabControl.Move(, , Width - 20, Height - 60)
            if (this.StatusBar) {
                this.StatusBar.Move(, , Width)
            }
        }
    }
    
    ; Core functionality methods
    CaptureArea() {
        this.StatusBar.Text := "Capturing area... Right-click to cancel"
        ; Use FindText's built-in capture functionality
        FindText().Gui("Show")
        this.StatusBar.Text := "Area captured - use FindText's interface to complete capture"
    }
    
    CaptureWindow() {
        this.StatusBar.Text := "Select a window to capture"
        ; Simple window selection
        MsgBox("Window capture feature - select a window in the next dialog", "FindText Manager", "OK")
        ; You would implement window selection logic here
        this.StatusBar.Text := "Window capture ready"
    }
    
    SearchNow() {
        pattern := this.GetCurrentPattern()
        if (pattern = "") {
            MsgBox("Please load or capture a pattern first", "FindText Manager", "OK")
            return
        }
        
        ; Get search area coordinates
        x1 := this.SearchX1.Value = "A_ScreenWidth" ? A_ScreenWidth : Integer(this.SearchX1.Value)
        y1 := this.SearchY1.Value = "A_ScreenHeight" ? A_ScreenHeight : Integer(this.SearchY1.Value)
        x2 := this.SearchX2.Value = "A_ScreenWidth" ? A_ScreenWidth : Integer(this.SearchX2.Value)
        y2 := this.SearchY2.Value = "A_ScreenHeight" ? A_ScreenHeight : Integer(this.SearchY2.Value)
        
        ; Get tolerances
        err1 := this.ToleranceEdit.Value
        err0 := this.BgToleranceEdit.Value
        findAll := this.FindAllCheck.Value
        
        this.StatusBar.Text := "Searching..."
        
        try {
            if (findAll) {
                ; Find all occurrences
                results := this.FT.FindText(,, x1, y1, x2, y2, err1, err0, pattern, 1, 1)
            } else {
                ; Find first occurrence
                results := this.FT.FindText(&outX, &outY, x1, y1, x2, y2, err1, err0, pattern)
            }
            
            this.DisplayResults(results)
            this.StatusBar.Text := "Search completed: " . results.Length . " results found"
        } catch Error as e {
            MsgBox("Search error: " . e.Message, "FindText Manager", "OK")
            this.StatusBar.Text := "Search failed"
        }
    }
    
    DisplayResults(results) {
        this.Results := results
        this.ResultsList.Delete()
        
        for i, result in results {
            this.ResultsList.Add("", result.x, result.y, result.w, result.h, result.id)
        }
        
        if (results.Length > 0) {
            this.LastSearch := results
        }
    }
    
    ClickResult() {
        if (this.Results.Length = 0) {
            MsgBox("No results to click", "FindText Manager", "OK")
            return
        }
        
        row := this.ResultsList.GetNext()
        if (row = 0) {
            row := 1
        }
        
        result := this.Results[row]
        this.FT.Click(result.mx, result.my)
        this.StatusBar.Text := "Clicked at " . result.mx . ", " . result.my
    }
    
    GetCurrentPattern() {
        ; For demonstration, return a simple pattern
        ; In a real implementation, this would get the pattern from the UI
        return ""
    }
    
    ; Placeholder methods for other functionality
    CaptureFromFile() {
        ; File selection dialog would go here
        MsgBox("File capture feature - select an image file", "FindText Manager", "OK")
    }
    
    GenerateCode() {
        ; Generate FindText code from current pattern
        code := "
        (
        ; FindText generated code
        Text := ""Your pattern here""
        if (ok := FindText(&X, &Y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0.05, 0.05, Text)) {
            ; Found the text
            FindText().Click(X, Y)
        }
        )"
        this.CodeEdit.Value := code
        this.StatusBar.Text := "Code generated"
    }
    
    TestCapture() {
        ; Test the current capture
        MsgBox("Testing current capture pattern", "FindText Manager", "OK")
    }
    
    LoadPattern() {
        ; Load a pattern from storage
        MsgBox("Load pattern from library", "FindText Manager", "OK")
    }
    
    AddPattern() {
        ; Add current pattern to library
        MsgBox("Add pattern to library", "FindText Manager", "OK")
    }
    
    RemovePattern() {
        ; Remove pattern from library
        MsgBox("Remove pattern from library", "FindText Manager", "OK")
    }
    
    EditPattern() {
        ; Edit selected pattern
        MsgBox("Edit pattern details", "FindText Manager", "OK")
    }
    
    LoadLibrary() {
        ; Load pattern library
        MsgBox("Load pattern library from file", "FindText Manager", "OK")
    }
    
    SaveLibrary() {
        ; Save pattern library
        MsgBox("Save pattern library to file", "FindText Manager", "OK")
    }
    
    ExportCode() {
        ; Export code to file
        MsgBox("Export generated code to file", "FindText Manager", "OK")
    }
    
    ShowAbout() {
        MsgBox("FindText Manager v1.0`n`nA simplified interface for the FindText OCR functionality`n`nBased on FindText by FeiYue", "About FindText Manager", "OK")
    }
    
    ResultDoubleClick() {
        this.ClickResult()
    }
    
    CopyCoordinates() {
        if (this.Results.Length > 0) {
            row := this.ResultsList.GetNext()
            if (row = 0) row := 1
            result := this.Results[row]
            A_Clipboard := result.mx . ", " . result.my
            this.StatusBar.Text := "Coordinates copied to clipboard"
        }
    }
    
    ClearResults() {
        this.Results := []
        this.ResultsList.Delete()
        this.StatusBar.Text := "Results cleared"
    }
    
    TestPattern() {
        ; Test the current pattern
        this.SearchNow()
    }
    
    CaptureRegion() {
        this.CaptureArea()
    }
    
    ResetSettings() {
        ; Reset to default settings
        this.ToleranceEdit.Value := "0.05"
        this.BgToleranceEdit.Value := "0.05"
        this.WaitTimeEdit.Value := "5"
        this.StatusBar.Text := "Settings reset to defaults"
    }
    
    ShowFTGUI() {
        ; Show the original FindText GUI
        FindText().Gui("Show")
    }
}

; Global function to easily access the manager (renamed to avoid conflict)
GetFindTextManager() {
    static FTMgr := FindTextManager()
    return FTMgr
}

; Example usage:
 F1::GetFindTextManager().Show()  ; Show GUI when F1 is pressed
 F2::GetFindTextManager().SearchNow()  ; Quick search with current settings

; Uncomment the following line to show the GUI when the script runs
 GetFindTextManager().Show()

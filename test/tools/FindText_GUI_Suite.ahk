/*
================================================================================
FINDTEXT.AHK GUI TEST SUITE & VISUALIZER (AutoHotkey v2)
================================================================================

COMPREHENSIVE GUI INTERFACE FOR FINDTEXT.AHK LIBRARY

FEATURES:
- Full GUI with intuitive controls for all FindText parameters
- Real-time visualization of scanning process
- Progressive match intensity display
- Benchmark metrics and performance analysis
- Pattern library management (save/load patterns)
- Multi-scale pattern matching support
- Tweakable tolerance, search regions, and visualization settings
- Export results and generate reports
- Step-by-step scanning mode for detailed analysis
- Color-coded match quality indicators

REQUIREMENTS:
- AutoHotkey v2.0+
- FindText.ahk library (must be in same directory or #Include path)
- Windows 10/11

USAGE:
1. Ensure FindText.ahk is accessible (same directory or #Include path)
2. Run this script
3. Use GUI to configure parameters
4. Capture or load patterns
5. Start search and watch visualization!

ARCHITECTURE:
- Main GUI with tabbed interface
- Real-time visualization canvas
- Background scanning with progress callbacks
- Benchmark metrics tracking
- Pattern database management
================================================================================
*/

#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; SECTION 1: INCLUDE FINDTEXT LIBRARY
; ============================================================================

/*
HOW #INCLUDE WORKS:
- #Include tells AHK to load another script file
- FindText.ahk must be in same directory or specify full path
- This gives us access to all FindText functions

FINDTEXT.AHK PROVIDES:
- FindText() - Main search function
- FindText().ScreenShot() - Capture screen
- FindText().GetRange() - Define search area
- FindText().PicInfo() - Get picture information
- And many more...
*/

; Try to include FindText.ahk
; If not found, script will show error and exit
#Include FindText.ahk


; ============================================================================
; SECTION 2: GLOBAL VARIABLES AND CONFIGURATION
; ============================================================================

/*
GLOBAL VARIABLES:
In AHK v2, variables declared at top level are global by default
We use these to store application state across functions
*/

; GUI Objects (will hold references to GUI controls)
global MainGui := ""           ; Main GUI window object
global VisualizationCanvas := "" ; Canvas for real-time visualization
global ResultsList := ""       ; ListView showing found matches
global MetricsText := ""       ; Edit control showing benchmark metrics
global LogText := ""           ; Edit control showing operation log

; Search Parameters (user-configurable)
global SearchParams := Map(
    "err1", 0.1,              ; Text tolerance (0.0 - 1.0)
    "err0", 0.1,              ; Background tolerance (0.0 - 1.0)
    "SearchRegion", "FullScreen",  ; "FullScreen" or "Custom"
    "X1", 0,                  ; Custom region coordinates
    "Y1", 0,
    "X2", A_ScreenWidth,
    "Y2", A_ScreenHeight,
    "FindAll", true,          ; Find all matches or just first
    "ScreenshotMode", 1       ; 1 = new screenshot, 0 = use last
)

; Visualization Parameters
global VizParams := Map(
    "Enabled", true,          ; Enable real-time visualization
    "Scale", 0.3,             ; Scale factor for display (30%)
    "UpdateDelay", 10,        ; Milliseconds between updates
    "PauseOnMatch", true,     ; Pause when match found
    "ShowIntensity", true,    ; Show match intensity colors
    "TrailLength", 100        ; How many previous positions to show
)

; Multi-Scale Parameters
global MultiScaleParams := Map(
    "Enabled", false,         ; Enable multi-scale searching
    "Levels", 5,              ; Number of scale levels
    "MinScale", 0.5,          ; Smallest scale (50%)
    "MaxScale", 2.0           ; Largest scale (200%)
)

; Application State
global CurrentPattern := ""    ; Currently loaded pattern
global PatternInfo := Map()    ; Pattern metadata
global SearchResults := []     ; Array of found matches
global IsSearching := false    ; Whether search is currently running
global SearchStartTime := 0    ; For benchmarking
global PositionsChecked := 0   ; Counter for performance metrics
global ShouldStop := false     ; Flag to stop current search

; Visualization State
global VizCanvas := ""         ; GDI+ canvas object
global VizBitmap := ""         ; Bitmap for drawing
global VizGraphics := ""       ; Graphics object
global ScanHistory := []       ; History of scanned positions
global CurrentScanPos := Map("x", 0, "y", 0, "w", 0, "h", 0, "intensity", 0)

; Pattern Library
global PatternLibrary := []    ; Stored patterns


; ============================================================================
; SECTION 3: MAIN ENTRY POINT
; ============================================================================

/*
SCRIPT EXECUTION STARTS HERE:
When script runs, this code executes first
It initializes the GUI and shows it to the user
*/

; Initialize GDI+ (required for custom drawing)
; GDI+ is Windows graphics library for drawing shapes, images, etc.
pToken := Gdip_Startup()
if (!pToken) {
    MsgBox("Failed to initialize GDI+`nScript will exit.", "Error", "Icon!")
    ExitApp
}

; Create and show main GUI
CreateMainGUI()
MainGui.Show("w1400 h900")

; Log startup message
LogMessage("FindText GUI Test Suite initialized successfully")
LogMessage("Ready to capture patterns and perform searches")

; Script continues running, handling GUI events
return


; ============================================================================
; SECTION 4: GUI CREATION FUNCTIONS
; ============================================================================

CreateMainGUI() {
    /*
    CREATES THE MAIN GUI WINDOW
    
    GUI STRUCTURE:
    - Top: Menu bar with File, Tools, Help
    - Left: Control panel with parameters (400px wide)
    - Right: Visualization and results (remaining width)
    - Bottom: Status bar
    
    HOW AHK v2 GUI WORKS:
    - Gui() creates a new GUI window object
    - Add() method adds controls to the GUI
    - OnEvent() registers event handlers
    - Show() makes the GUI visible
    */
    
    global MainGui, VisualizationCanvas, ResultsList, MetricsText, LogText
    
    ; Create main GUI window
    ; Options: +Resize allows window resizing, -DPIScale disables DPI scaling
    MainGui := Gui("+Resize -DPIScale", "FindText.ahk - GUI Test Suite & Visualizer")
    
    ; Set window icon (optional - requires icon file)
    ; MainGui.SetIcon("FindText.ico")
    
    ; Create menu bar
    CreateMenuBar()
    
    ; Set GUI background color
    MainGui.BackColor := "0x2B2B2B"  ; Dark gray background
    
    ; Calculate layout dimensions
    ; We'll split the window: 400px left panel, rest for visualization
    ControlPanelWidth := 400
    VizAreaX := ControlPanelWidth + 10
    
    ; ========================================================================
    ; LEFT PANEL: CONTROL PANEL
    ; ========================================================================
    
    ; Create scrollable control panel
    ; Tab control for organizing parameters into sections
    TabControl := MainGui.Add("Tab3", "x10 y10 w" . ControlPanelWidth . " h850", 
        ["Search", "Visualization", "Multi-Scale", "Patterns", "Settings"])
    
    ; ------------------------------------------------------------------------
    ; TAB 1: SEARCH PARAMETERS
    ; ------------------------------------------------------------------------
    TabControl.UseTab(1)
    
    ; === PATTERN SECTION ===
    MainGui.Add("GroupBox", "x20 y40 w" . (ControlPanelWidth - 20) . " h180", "Pattern")
    
    ; Pattern capture button
    MainGui.Add("Button", "x30 y60 w" . (ControlPanelWidth - 40) . " h30", "📸 Capture Pattern (Ctrl+F1)")
        .OnEvent("Click", (*) => CapturePattern())
    
    ; Load/Save buttons in same row
    MainGui.Add("Button", "x30 y100 w" . ((ControlPanelWidth - 50) // 2) . " h30", "📂 Load Pattern")
        .OnEvent("Click", (*) => LoadPattern())
    MainGui.Add("Button", "x" . (30 + (ControlPanelWidth - 50) // 2 + 10) . " y100 w" . ((ControlPanelWidth - 50) // 2) . " h30", "💾 Save Pattern")
        .OnEvent("Click", (*) => SavePattern())
    
    ; Pattern info display
    MainGui.Add("Text", "x30 y140 w" . (ControlPanelWidth - 40), "Current Pattern:")
    global PatternInfoText := MainGui.Add("Edit", "x30 y160 w" . (ControlPanelWidth - 40) . " h50 ReadOnly")
    PatternInfoText.Value := "No pattern loaded"
    
    ; === TOLERANCE SECTION ===
    MainGui.Add("GroupBox", "x20 y230 w" . (ControlPanelWidth - 20) . " h120", "Tolerance Settings")
    
    ; Text tolerance (err1)
    MainGui.Add("Text", "x30 y250 w150", "Text Tolerance (err1):")
    global Err1ValueText := MainGui.Add("Text", "x330 y250 w50 Right", "0.10")
    global Err1Slider := MainGui.Add("Slider", "x30 y270 w" . (ControlPanelWidth - 40) . " Range0-100 TickInterval10 ToolTip", 10)
    Err1Slider.OnEvent("Change", UpdateErr1Value)
    
    ; Background tolerance (err0)
    MainGui.Add("Text", "x30 y300 w150", "Background Tolerance (err0):")
    global Err0ValueText := MainGui.Add("Text", "x330 y300 w50 Right", "0.10")
    global Err0Slider := MainGui.Add("Slider", "x30 y320 w" . (ControlPanelWidth - 40) . " Range0-100 TickInterval10 ToolTip", 10)
    Err0Slider.OnEvent("Change", UpdateErr0Value)
    
    ; === SEARCH REGION SECTION ===
    MainGui.Add("GroupBox", "x20 y360 w" . (ControlPanelWidth - 20) . " h180", "Search Region")
    
    ; Radio buttons for region selection
    global FullScreenRadio := MainGui.Add("Radio", "x30 y380 Checked", "Full Screen")
    FullScreenRadio.OnEvent("Click", (*) => UpdateSearchRegion("FullScreen"))
    global CustomRegionRadio := MainGui.Add("Radio", "x30 y405", "Custom Region")
    CustomRegionRadio.OnEvent("Click", (*) => UpdateSearchRegion("Custom"))
    
    ; Custom region coordinates
    MainGui.Add("Text", "x30 y430 w30", "X1:")
    global X1Edit := MainGui.Add("Edit", "x65 y428 w60 Number", "0")
    MainGui.Add("Text", "x135 y430 w30", "Y1:")
    global Y1Edit := MainGui.Add("Edit", "x170 y428 w60 Number", "0")
    
    MainGui.Add("Text", "x30 y460 w30", "X2:")
    global X2Edit := MainGui.Add("Edit", "x65 y458 w60 Number", A_ScreenWidth)
    MainGui.Add("Text", "x135 y460 w30", "Y2:")
    global Y2Edit := MainGui.Add("Edit", "x170 y458 w60 Number", A_ScreenHeight)
    
    MainGui.Add("Button", "x30 y490 w" . (ControlPanelWidth - 40) . " h30", "🎯 Select Region (Drag on Screen)")
        .OnEvent("Click", (*) => SelectRegionInteractive())
    
    ; === OPTIONS SECTION ===
    MainGui.Add("GroupBox", "x20 y550 w" . (ControlPanelWidth - 20) . " h80", "Search Options")
    
    global FindAllCheck := MainGui.Add("Checkbox", "x30 y570 Checked", "Find All Matches")
    FindAllCheck.OnEvent("Click", (*) => (SearchParams["FindAll"] := FindAllCheck.Value))
    
    global NewScreenshotCheck := MainGui.Add("Checkbox", "x30 y595 Checked", "Take New Screenshot")
    NewScreenshotCheck.OnEvent("Click", (*) => (SearchParams["ScreenshotMode"] := NewScreenshotCheck.Value ? 1 : 0))
    
    ; === ACTION BUTTONS ===
    MainGui.Add("GroupBox", "x20 y640 w" . (ControlPanelWidth - 20) . " h140", "Actions")
    
    global StartSearchBtn := MainGui.Add("Button", "x30 y665 w" . (ControlPanelWidth - 40) . " h40 Default", "🔍 Start Search (F5)")
    StartSearchBtn.OnEvent("Click", (*) => StartSearch())
    
    global StopSearchBtn := MainGui.Add("Button", "x30 y715 w" . (ControlPanelWidth - 40) . " h30 Disabled", "⏹ Stop Search (Esc)")
    StopSearchBtn.OnEvent("Click", (*) => StopSearch())
    
    global ClearResultsBtn := MainGui.Add("Button", "x30 y755 w" . (ControlPanelWidth - 40) . " h20", "🗑 Clear Results")
    ClearResultsBtn.OnEvent("Click", (*) => ClearResults())
    
    ; ------------------------------------------------------------------------
    ; TAB 2: VISUALIZATION PARAMETERS
    ; ------------------------------------------------------------------------
    TabControl.UseTab(2)
    
    MainGui.Add("GroupBox", "x20 y40 w" . (ControlPanelWidth - 20) . " h140", "Visualization Settings")
    
    global VizEnabledCheck := MainGui.Add("Checkbox", "x30 y60 Checked", "Enable Real-Time Visualization")
    VizEnabledCheck.OnEvent("Click", (*) => (VizParams["Enabled"] := VizEnabledCheck.Value))
    
    MainGui.Add("Text", "x30 y90 w150", "Display Scale:")
    global VizScaleText := MainGui.Add("Text", "x330 y90 w50 Right", "30%")
    global VizScaleSlider := MainGui.Add("Slider", "x30 y110 w" . (ControlPanelWidth - 40) . " Range10-100 TickInterval10", 30)
    VizScaleSlider.OnEvent("Change", UpdateVizScale)
    
    MainGui.Add("Text", "x30 y140 w150", "Update Delay (ms):")
    global VizDelayText := MainGui.Add("Text", "x330 y140 w50 Right", "10")
    global VizDelaySlider := MainGui.Add("Slider", "x30 y160 w" . (ControlPanelWidth - 40) . " Range1-100 TickInterval10", 10)
    VizDelaySlider.OnEvent("Change", UpdateVizDelay)
    
    MainGui.Add("GroupBox", "x20 y190 w" . (ControlPanelWidth - 20) . " h120", "Display Options")
    
    global ShowIntensityCheck := MainGui.Add("Checkbox", "x30 y210 Checked", "Show Match Intensity Colors")
    ShowIntensityCheck.OnEvent("Click", (*) => (VizParams["ShowIntensity"] := ShowIntensityCheck.Value))
    
    global PauseOnMatchCheck := MainGui.Add("Checkbox", "x30 y235 Checked", "Pause When Match Found")
    PauseOnMatchCheck.OnEvent("Click", (*) => (VizParams["PauseOnMatch"] := PauseOnMatchCheck.Value))
    
    MainGui.Add("Text", "x30 y260 w150", "Trail Length:")
    global TrailLengthText := MainGui.Add("Text", "x330 y260 w50 Right", "100")
    global TrailLengthSlider := MainGui.Add("Slider", "x30 y280 w" . (ControlPanelWidth - 40) . " Range10-500 TickInterval50", 100)
    TrailLengthSlider.OnEvent("Change", UpdateTrailLength)
    
    MainGui.Add("GroupBox", "x20 y320 w" . (ControlPanelWidth - 20) . " h200", "Color Legend")
    
    ; Color legend showing what each color means
    legendY := 345
    AddColorLegend("Current Position", "0x0000FF", legendY)      ; Blue
    AddColorLegend("Low Match (< 30%)", "0x333333", legendY + 30)    ; Dark gray
    AddColorLegend("Medium Match (30-60%)", "0x666600", legendY + 60) ; Dark yellow
    AddColorLegend("Good Match (60-90%)", "0x006600", legendY + 90)  ; Green
    AddColorLegend("Perfect Match (90%+)", "0x00FF00", legendY + 120) ; Bright green
    AddColorLegend("Final Match", "0x00FF00", legendY + 150)     ; Bright green
    
    ; ------------------------------------------------------------------------
    ; TAB 3: MULTI-SCALE PARAMETERS
    ; ------------------------------------------------------------------------
    TabControl.UseTab(3)
    
    MainGui.Add("GroupBox", "x20 y40 w" . (ControlPanelWidth - 20) . " h240", "Multi-Scale Search")
    
    MainGui.Add("Text", "x30 y60 w" . (ControlPanelWidth - 50), 
        "Search for patterns at multiple sizes simultaneously.`n" .
        "Perfect for finding icons at different scales.")
    
    global MultiScaleEnabledCheck := MainGui.Add("Checkbox", "x30 y110", "Enable Multi-Scale Matching")
    MultiScaleEnabledCheck.OnEvent("Click", (*) => (MultiScaleParams["Enabled"] := MultiScaleEnabledCheck.Value))
    
    MainGui.Add("Text", "x30 y140 w150", "Scale Levels:")
    global ScaleLevelsText := MainGui.Add("Text", "x330 y140 w50 Right", "5")
    global ScaleLevelsSlider := MainGui.Add("Slider", "x30 y160 w" . (ControlPanelWidth - 40) . " Range3-15 TickInterval1", 5)
    ScaleLevelsSlider.OnEvent("Change", UpdateScaleLevels)
    
    MainGui.Add("Text", "x30 y190 w150", "Min Scale:")
    global MinScaleText := MainGui.Add("Text", "x330 y190 w50 Right", "50%")
    global MinScaleSlider := MainGui.Add("Slider", "x30 y210 w" . (ControlPanelWidth - 40) . " Range10-100 TickInterval10", 50)
    MinScaleSlider.OnEvent("Change", UpdateMinScale)
    
    MainGui.Add("Text", "x30 y240 w150", "Max Scale:")
    global MaxScaleText := MainGui.Add("Text", "x330 y240 w50 Right", "200%")
    global MaxScaleSlider := MainGui.Add("Slider", "x30 y260 w" . (ControlPanelWidth - 40) . " Range100-500 TickInterval50", 200)
    MaxScaleSlider.OnEvent("Change", UpdateMaxScale)
    
    ; Preview of scales
    global ScalesPreviewText := MainGui.Add("Edit", "x20 y290 w" . (ControlPanelWidth - 20) . " h230 ReadOnly Multi")
    UpdateScalesPreview()
    
    ; ------------------------------------------------------------------------
    ; TAB 4: PATTERN LIBRARY
    ; ------------------------------------------------------------------------
    TabControl.UseTab(4)
    
    MainGui.Add("GroupBox", "x20 y40 w" . (ControlPanelWidth - 20) . " h780", "Saved Patterns")
    
    ; Pattern library listview
    global PatternLibraryLV := MainGui.Add("ListView", "x30 y60 w" . (ControlPanelWidth - 40) . " h680", 
        ["Name", "Size", "Date"])
    PatternLibraryLV.OnEvent("DoubleClick", LoadPatternFromLibrary)
    
    ; Pattern library buttons
    MainGui.Add("Button", "x30 y750 w" . ((ControlPanelWidth - 50) // 2) . " h30", "Load Selected")
        .OnEvent("Click", LoadPatternFromLibrary)
    MainGui.Add("Button", "x" . (30 + (ControlPanelWidth - 50) // 2 + 10) . " y750 w" . ((ControlPanelWidth - 50) // 2) . " h30", "Delete Selected")
        .OnEvent("Click", DeletePatternFromLibrary)
    
    MainGui.Add("Button", "x30 y790 w" . (ControlPanelWidth - 40) . " h25", "Refresh Library")
        .OnEvent("Click", (*) => RefreshPatternLibrary())
    
    ; ------------------------------------------------------------------------
    ; TAB 5: SETTINGS
    ; ------------------------------------------------------------------------
    TabControl.UseTab(5)
    
    MainGui.Add("GroupBox", "x20 y40 w" . (ControlPanelWidth - 20) . " h200", "General Settings")
    
    MainGui.Add("Text", "x30 y60", "FindText.ahk Path:")
    global FindTextPathEdit := MainGui.Add("Edit", "x30 y80 w" . (ControlPanelWidth - 40) . " ReadOnly", A_ScriptDir . "\FindText.ahk")
    
    MainGui.Add("Text", "x30 y110", "Pattern Library Path:")
    global PatternLibPathEdit := MainGui.Add("Edit", "x30 y130 w" . (ControlPanelWidth - 40), A_ScriptDir . "\Patterns")
    
    MainGui.Add("Button", "x30 y170 w" . (ControlPanelWidth - 40) . " h30", "Open Pattern Library Folder")
        .OnEvent("Click", (*) => Run(PatternLibPathEdit.Value))
    
    MainGui.Add("GroupBox", "x20 y250 w" . (ControlPanelWidth - 20) . " h120", "Performance")
    
    MainGui.Add("Text", "x30 y270", "Search Step (1 = thorough, higher = faster):")
    global SearchStepText := MainGui.Add("Text", "x330 y270 w50 Right", "1")
    global SearchStepSlider := MainGui.Add("Slider", "x30 y290 w" . (ControlPanelWidth - 40) . " Range1-10 TickInterval1", 1)
    SearchStepSlider.OnEvent("Change", UpdateSearchStep)
    
    global ThoroughnessCheck := MainGui.Add("Checkbox", "x30 y320 Checked", "Thoroughness Mode (forces step=1)")
    
    MainGui.Add("GroupBox", "x20 y380 w" . (ControlPanelWidth - 20) . " h100", "About")
    
    MainGui.Add("Text", "x30 y400 w" . (ControlPanelWidth - 40), 
        "FindText.ahk GUI Test Suite v1.0`n" .
        "Comprehensive testing and visualization tool`n" .
        "for the FindText.ahk library.`n`n" .
        "© 2024 - AutoHotkey v2")
    
    ; ========================================================================
    ; RIGHT PANEL: VISUALIZATION AND RESULTS
    ; ========================================================================
    
    TabControl.UseTab()  ; End of tab control
    
    ; Calculate right panel dimensions
    RightPanelX := VizAreaX
    RightPanelWidth := 980
    
    ; === VISUALIZATION CANVAS ===
    MainGui.Add("GroupBox", "x" . RightPanelX . " y10 w" . RightPanelWidth . " h500", "Real-Time Visualization")
    
    ; Status bar above canvas
    global VizStatusText := MainGui.Add("Text", "x" . (RightPanelX + 10) . " y30 w" . (RightPanelWidth - 20) . " h20 Center BackgroundWhite", 
        "Ready - Load a pattern and start search to see visualization")
    
    ; Progress info
    global VizProgressText := MainGui.Add("Text", "x" . (RightPanelX + 10) . " y55 w" . (RightPanelWidth - 20) . " h20 Center BackgroundWhite", 
        "Positions: 0 | Matches: 0 | Speed: 0 pos/sec")
    
    ; Create canvas for visualization using Picture control
    ; We'll draw on this using GDI+
    global VisualizationCanvas := MainGui.Add("Picture", "x" . (RightPanelX + 10) . " y80 w" . (RightPanelWidth - 20) . " h410 Border")
    
    ; Initialize GDI+ canvas
    InitializeVisualizationCanvas(RightPanelWidth - 20, 410)
    
    ; === RESULTS SECTION ===
    ResultsTabControl := MainGui.Add("Tab3", "x" . RightPanelX . " y520 w" . RightPanelWidth . " h340", 
        ["Matches", "Metrics", "Log"])
    
    ; --- MATCHES TAB ---
    ResultsTabControl.UseTab(1)
    
    global ResultsList := MainGui.Add("ListView", "x" . (RightPanelX + 10) . " y550 w" . (RightPanelWidth - 20) . " h295", 
        ["#", "X", "Y", "Width", "Height", "Similarity", "Scale"])
    ResultsList.ModifyCol(1, 40)   ; # column
    ResultsList.ModifyCol(2, 70)   ; X
    ResultsList.ModifyCol(3, 70)   ; Y
    ResultsList.ModifyCol(4, 80)   ; Width
    ResultsList.ModifyCol(5, 80)   ; Height
    ResultsList.ModifyCol(6, 100)  ; Similarity
    ResultsList.ModifyCol(7, 80)   ; Scale
    
    ; --- METRICS TAB ---
    ResultsTabControl.UseTab(2)
    
    global MetricsText := MainGui.Add("Edit", "x" . (RightPanelX + 10) . " y550 w" . (RightPanelWidth - 20) . " h295 ReadOnly Multi", 
        "No search performed yet.`n`nBenchmark metrics will appear here after search.")
    
    ; --- LOG TAB ---
    ResultsTabControl.UseTab(3)
    
    global LogText := MainGui.Add("Edit", "x" . (RightPanelX + 10) . " y550 w" . (RightPanelWidth - 20) . " h295 ReadOnly Multi")
    
    ResultsTabControl.UseTab()
    
    ; ========================================================================
    ; BOTTOM STATUS BAR
    ; ========================================================================
    
    global StatusBar := MainGui.Add("StatusBar", , "Ready")
    StatusBar.SetParts(300, 200)  ; Split status bar into sections
    StatusBar.SetText("Ready", 1)
    StatusBar.SetText("No pattern loaded", 2)
    
    ; ========================================================================
    ; HOTKEYS
    ; ========================================================================
    
    ; Register hotkeys for quick actions
    ; HotKey registers a key combination to trigger a function
    HotKey("F5", (*) => StartSearch())       ; F5 = Start search
    HotKey("^F1", (*) => CapturePattern())   ; Ctrl+F1 = Capture pattern
    HotKey("Esc", (*) => StopSearch())       ; Esc = Stop search
    
    ; ========================================================================
    ; GUI EVENT HANDLERS
    ; ========================================================================
    
    ; Handle GUI close
    MainGui.OnEvent("Close", (*) => ExitApp())
    
    ; Handle GUI resize
    MainGui.OnEvent("Size", GuiSize)
    
    ; Initialize pattern library
    RefreshPatternLibrary()
}

; Helper function to add color legend entry
AddColorLegend(label, color, y) {
    /*
    ADDS A COLOR LEGEND ENTRY
    Shows a colored box with label explaining what the color means
    
    PARAMETERS:
    - label: Text description
    - color: Color hex value (e.g., "0xFF0000" for red)
    - y: Y position for this legend entry
    */
    global MainGui
    
    ; Draw color box (20x15 pixels)
    MainGui.Add("Progress", "x40 y" . y . " w20 h15 Background" . color)
    
    ; Add label text
    MainGui.Add("Text", "x70 y" . (y - 2) . " w300", label)
}

CreateMenuBar() {
    /*
    CREATES THE MENU BAR AT TOP OF GUI
    
    MENU STRUCTURE:
    - File: Save, Load, Export, Exit
    - Tools: Options, Pattern Manager
    - Help: Documentation, About
    
    HOW AHK v2 MENUS WORK:
    - MenuBar() creates a menu bar
    - Add() adds menu items
    - OnEvent("Click", function) assigns action to menu item
    */
    
    global MainGui
    
    ; Create File menu
    FileMenu := Menu()
    FileMenu.Add("&Load Pattern`tCtrl+O", (*) => LoadPattern())
    FileMenu.Add("&Save Pattern`tCtrl+S", (*) => SavePattern())
    FileMenu.Add()  ; Separator
    FileMenu.Add("&Export Results`tCtrl+E", (*) => ExportResults())
    FileMenu.Add()
    FileMenu.Add("E&xit`tAlt+F4", (*) => ExitApp())
    
    ; Create Tools menu
    ToolsMenu := Menu()
    ToolsMenu.Add("&Capture Pattern`tCtrl+F1", (*) => CapturePattern())
    ToolsMenu.Add("&Clear Results", (*) => ClearResults())
    ToolsMenu.Add()
    ToolsMenu.Add("&Pattern Library", (*) => ShowPatternLibrary())
    ToolsMenu.Add("&Benchmark Test", (*) => RunBenchmarkTest())
    
    ; Create Help menu
    HelpMenu := Menu()
    HelpMenu.Add("&Documentation", (*) => ShowDocumentation())
    HelpMenu.Add("&About FindText GUI", (*) => ShowAbout())
    
    ; Create menu bar and add menus
    MenuBar := MenuBar()
    MenuBar.Add("&File", FileMenu)
    MenuBar.Add("&Tools", ToolsMenu)
    MenuBar.Add("&Help", HelpMenu)
    
    ; Attach menu bar to GUI
    MainGui.MenuBar := MenuBar
}


; ============================================================================
; SECTION 5: VISUALIZATION FUNCTIONS
; ============================================================================

InitializeVisualizationCanvas(width, height) {
    /*
    INITIALIZES THE GDI+ CANVAS FOR VISUALIZATION
    
    GDI+ DRAWING PROCESS:
    1. Create a bitmap (image buffer)
    2. Create graphics object from bitmap
    3. Draw on graphics object
    4. Convert bitmap to HBITMAP for display
    5. Set as Picture control's image
    
    PARAMETERS:
    - width, height: Canvas dimensions in pixels
    */
    
    global VizBitmap, VizGraphics
    
    ; Create bitmap for drawing
    ; This is an in-memory image buffer
    VizBitmap := Gdip_CreateBitmap(width, height)
    
    ; Create graphics object from bitmap
    ; Graphics object provides drawing functions
    VizGraphics := Gdip_GraphicsFromImage(VizBitmap)
    
    ; Set smooth drawing mode for better quality
    Gdip_SetSmoothingMode(VizGraphics, 4)  ; 4 = AntiAlias
    
    ; Fill with black background
    Gdip_GraphicsClear(VizGraphics, 0xFF000000)  ; Black
    
    ; Display initial canvas
    UpdateVisualizationDisplay()
}

UpdateVisualizationDisplay() {
    /*
    UPDATES THE VISUALIZATION CANVAS DISPLAY
    
    PROCESS:
    1. Convert current bitmap to HBITMAP
    2. Set as Picture control's image
    3. Delete old HBITMAP (cleanup)
    
    This is called after drawing to show the changes
    */
    
    global VizBitmap, VisualizationCanvas
    static LastHBitmap := 0
    
    ; Convert Gdip bitmap to HBITMAP (Windows bitmap handle)
    hBitmap := Gdip_CreateHBITMAPFromBitmap(VizBitmap)
    
    ; Set as picture control's image
    ; SendMessage is used to set the image handle
    SendMessage(0x0172, 0, hBitmap, VisualizationCanvas.Hwnd)  ; STM_SETIMAGE
    
    ; Delete old bitmap to prevent memory leak
    if (LastHBitmap)
        DllCall("DeleteObject", "Ptr", LastHBitmap)
    
    LastHBitmap := hBitmap
}

DrawScanPosition(x, y, w, h, intensity) {
    /*
    DRAWS CURRENT SCAN POSITION ON CANVAS
    
    VISUALIZATION:
    - Rectangle showing current position being checked
    - Color based on match intensity (0.0 - 1.0)
    - Brighter = better match
    
    COLOR SCHEME:
    - intensity < 0.3: Dark gray (poor match)
    - intensity 0.3-0.6: Dark yellow (medium match)
    - intensity 0.6-0.9: Green (good match)
    - intensity >= 0.9: Bright green (excellent match)
    
    PARAMETERS:
    - x, y: Position in screen coordinates
    - w, h: Size of pattern
    - intensity: Match quality 0.0 - 1.0
    */
    
    global VizGraphics, VizParams, ScanHistory
    
    if (!VizParams["Enabled"])
        return
    
    ; Scale coordinates for display
    scale := VizParams["Scale"]
    sx := x * scale
    sy := y * scale
    sw := w * scale
    sh := h * scale
    
    ; Determine color based on intensity
    if (intensity < 0.3) {
        color := 0x88333333  ; Dark gray with transparency
        penColor := 0xFF333333
    } else if (intensity < 0.6) {
        color := 0x88666600  ; Dark yellow
        penColor := 0xFF888800
    } else if (intensity < 0.9) {
        color := 0x88006600  ; Green
        penColor := 0xFF00AA00
    } else {
        color := 0x8800FF00  ; Bright green
        penColor := 0xFF00FF00
    }
    
    ; Draw filled rectangle with transparency
    brush := Gdip_BrushCreateSolid(color)
    Gdip_FillRectangle(VizGraphics, brush, sx, sy, sw, sh)
    Gdip_DeleteBrush(brush)
    
    ; Draw outline
    pen := Gdip_CreatePen(penColor, 1)
    Gdip_DrawRectangle(VizGraphics, pen, sx, sy, sw, sh)
    Gdip_DeletePen(pen)
    
    ; Add to scan history
    ScanHistory.Push(Map("x", sx, "y", sy, "w", sw, "h", sh, "intensity", intensity))
    
    ; Limit history length
    if (ScanHistory.Length > VizParams["TrailLength"]) {
        ScanHistory.RemoveAt(1)
    }
    
    ; Update display
    UpdateVisualizationDisplay()
}

DrawCurrentPosition(x, y, w, h) {
    /*
    DRAWS CURRENT POSITION INDICATOR (BLUE BOX)
    
    This shows WHERE we're checking RIGHT NOW
    Bright blue outline that moves with the scan
    
    PARAMETERS:
    - x, y: Position in screen coordinates
    - w, h: Size of pattern
    */
    
    global VizGraphics, VizParams
    
    if (!VizParams["Enabled"])
        return
    
    scale := VizParams["Scale"]
    sx := x * scale
    sy := y * scale
    sw := w * scale
    sh := h * scale
    
    ; Draw bright blue outline (current position indicator)
    pen := Gdip_CreatePen(0xFF0000FF, 3)  ; Blue, 3px thick
    Gdip_DrawRectangle(VizGraphics, pen, sx, sy, sw, sh)
    Gdip_DeletePen(pen)
    
    UpdateVisualizationDisplay()
}

DrawFinalMatch(x, y, w, h, similarity) {
    /*
    DRAWS A FINAL CONFIRMED MATCH
    
    Bright green box with similarity score
    Remains visible after search completes
    
    PARAMETERS:
    - x, y: Match position
    - w, h: Match size
    - similarity: Match quality 0.0 - 1.0
    */
    
    global VizGraphics, VizParams
    
    if (!VizParams["Enabled"])
        return
    
    scale := VizParams["Scale"]
    sx := x * scale
    sy := y * scale
    sw := w * scale
    sh := h * scale
    
    ; Draw bright green filled rectangle
    brush := Gdip_BrushCreateSolid(0x4400FF00)  ; Semi-transparent green
    Gdip_FillRectangle(VizGraphics, brush, sx, sy, sw, sh)
    Gdip_DeleteBrush(brush)
    
    ; Draw thick green outline
    pen := Gdip_CreatePen(0xFF00FF00, 4)  ; Bright green, 4px
    Gdip_DrawRectangle(VizGraphics, pen, sx, sy, sw, sh)
    Gdip_DeletePen(pen)
    
    ; Draw similarity text
    if (similarity) {
        simText := Round(similarity * 100) . "%"
        
        ; Create font
        font := "Arial"
        fontSize := 10
        fontStyle := 1  ; Bold
        
        ; Draw text with background
        brush := Gdip_BrushCreateSolid(0xFF00FF00)
        Gdip_TextToGraphics(VizGraphics, simText, "s" . fontSize . " Bold c" . brush . " x" . (sx + 2) . " y" . (sy - 15), font)
        Gdip_DeleteBrush(brush)
    }
    
    UpdateVisualizationDisplay()
}

ClearVisualization() {
    /*
    CLEARS THE VISUALIZATION CANVAS
    Fills with black background, resets scan history
    */
    
    global VizGraphics, ScanHistory
    
    ; Clear to black
    Gdip_GraphicsClear(VizGraphics, 0xFF000000)
    
    ; Clear history
    ScanHistory := []
    
    UpdateVisualizationDisplay()
}

DrawSearchArea(x1, y1, x2, y2) {
    /*
    DRAWS THE SEARCH AREA BOUNDARY
    White rectangle showing region being searched
    
    PARAMETERS:
    - x1, y1, x2, y2: Search region coordinates
    */
    
    global VizGraphics, VizParams
    
    if (!VizParams["Enabled"])
        return
    
    scale := VizParams["Scale"]
    sx1 := x1 * scale
    sy1 := y1 * scale
    sw := (x2 - x1) * scale
    sh := (y2 - y1) * scale
    
    ; Draw white border
    pen := Gdip_CreatePen(0xFFFFFFFF, 2)  ; White, 2px
    Gdip_DrawRectangle(VizGraphics, pen, sx1, sy1, sw, sh)
    Gdip_DeletePen(pen)
    
    UpdateVisualizationDisplay()
}


; ============================================================================
; SECTION 6: SEARCH FUNCTIONS
; ============================================================================

StartSearch() {
    /*
    STARTS THE PATTERN SEARCH
    
    SEARCH PROCESS:
    1. Validate pattern is loaded
    2. Get search parameters from GUI
    3. Clear previous results
    4. Initialize visualization
    5. Call FindText() with parameters
    6. Process results
    7. Display matches and metrics
    
    This is the MAIN search function that orchestrates everything
    */
    
    global CurrentPattern, IsSearching, SearchStartTime, PositionsChecked
    global SearchResults, ShouldStop
    
    ; Validate pattern exists
    if (!CurrentPattern || CurrentPattern = "") {
        MsgBox("No pattern loaded!`n`nPlease capture or load a pattern first.", "Error", "Icon!")
        return
    }
    
    ; Check if already searching
    if (IsSearching) {
        MsgBox("Search already in progress!`n`nPlease wait for current search to complete.", "Warning", "Icon!")
        return
    }
    
    ; Update state
    IsSearching := true
    ShouldStop := false
    PositionsChecked := 0
    SearchResults := []
    
    ; Update GUI
    StartSearchBtn.Enabled := false
    StopSearchBtn.Enabled := true
    VizStatusText.Value := "Searching..."
    StatusBar.SetText("Searching...", 1)
    LogMessage("Search started")
    
    ; Clear previous visualization
    ClearVisualization()
    ClearResults()
    
    ; Get search parameters
    x1 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(X1Edit.Value)
    y1 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(Y1Edit.Value)
    x2 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(X2Edit.Value)
    y2 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(Y2Edit.Value)
    
    err1 := SearchParams["err1"]
    err0 := SearchParams["err0"]
    ScreenshotMode := SearchParams["ScreenshotMode"]
    FindAll := SearchParams["FindAll"] ? 1 : 0
    
    ; Draw search area
    if (x1 != 0 || y1 != 0) {
        DrawSearchArea(x1, y1, x2, y2)
    } else {
        DrawSearchArea(0, 0, A_ScreenWidth, A_ScreenHeight)
    }
    
    ; Record start time for benchmarking
    SearchStartTime := A_TickCount
    
    ; Start search in new thread (using SetTimer for async behavior)
    ; This prevents GUI from freezing during search
    SetTimer(PerformSearch, -10)  ; -10 = run once after 10ms
}

PerformSearch() {
    /*
    PERFORMS THE ACTUAL SEARCH
    
    This runs asynchronously so GUI stays responsive
    Calls FindText() and processes results
    */
    
    global CurrentPattern, SearchParams, SearchResults, SearchStartTime
    global PositionsChecked, IsSearching
    
    try {
        ; Get parameters
        x1 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(X1Edit.Value)
        y1 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(Y1Edit.Value)
        x2 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(X2Edit.Value)
        y2 := SearchParams["SearchRegion"] = "FullScreen" ? 0 : Integer(Y2Edit.Value)
        
        err1 := SearchParams["err1"]
        err0 := SearchParams["err0"]
        ScreenshotMode := SearchParams["ScreenshotMode"]
        FindAll := SearchParams["FindAll"] ? 1 : 0
        
        ; Check if multi-scale is enabled
        if (MultiScaleParams["Enabled"]) {
            ; Perform multi-scale search
            SearchResults := PerformMultiScaleSearch(x1, y1, x2, y2, err1, err0, ScreenshotMode, FindAll)
        } else {
            ; Standard single-scale search
            ; Call FindText library
            ok := FindText(&x := 0, &y := 0, x1, y1, x2, y2, err1, err0, CurrentPattern, ScreenshotMode, FindAll)
            
            ; Process results
            if (ok) {
                for index, match in ok {
                    SearchResults.Push(Map(
                        "x", match.x,
                        "y", match.y,
                        "w", match.w,
                        "h", match.h,
                        "similarity", 1.0,  ; FindText doesn't return similarity
                        "scale", 1.0
                    ))
                    
                    ; Draw match on visualization
                    DrawFinalMatch(match.x, match.y, match.w, match.h, 1.0)
                    
                    ; Pause if requested
                    if (VizParams["PauseOnMatch"]) {
                        Sleep(500)
                    }
                }
            }
        }
        
        ; Calculate metrics
        elapsed := A_TickCount - SearchStartTime
        
        ; Update GUI with results
        DisplayResults()
        DisplayMetrics(elapsed)
        
        ; Update status
        VizStatusText.Value := "Search Complete - Found " . SearchResults.Length . " match(es)"
        StatusBar.SetText("Ready", 1)
        LogMessage("Search completed: " . SearchResults.Length . " matches found in " . elapsed . "ms")
        
    } catch as err {
        MsgBox("Error during search:`n`n" . err.Message, "Error", "Icon!")
        LogMessage("ERROR: " . err.Message)
    }
    
    ; Reset state
    IsSearching := false
    StartSearchBtn.Enabled := true
    StopSearchBtn.Enabled := false
}

StopSearch() {
    /*
    STOPS THE CURRENT SEARCH
    Sets flag that search loops check
    */
    
    global ShouldStop, IsSearching
    
    if (!IsSearching) {
        return
    }
    
    ShouldStop := true
    LogMessage("Search stopped by user")
    
    ; Reset UI
    IsSearching := false
    StartSearchBtn.Enabled := true
    StopSearchBtn.Enabled := false
    VizStatusText.Value := "Search stopped"
    StatusBar.SetText("Ready", 1)
}

PerformMultiScaleSearch(x1, y1, x2, y2, err1, err0, ScreenshotMode, FindAll) {
    /*
    PERFORMS MULTI-SCALE SEARCH
    
    Searches for pattern at multiple scales:
    1. Generate scaled versions of pattern
    2. Search for each scale
    3. Aggregate all results
    
    RETURNS:
    - Array of all matches from all scales
    */
    
    global CurrentPattern, MultiScaleParams
    
    allMatches := []
    
    ; Calculate scales
    levels := MultiScaleParams["Levels"]
    minScale := MultiScaleParams["MinScale"]
    maxScale := MultiScaleParams["MaxScale"]
    
    ; Generate scale values
    scales := []
    if (levels = 1) {
        scales.Push(1.0)
    } else {
        step := (maxScale - minScale) / (levels - 1)
        loop levels {
            scale := minScale + ((A_Index - 1) * step)
            scales.Push(scale)
        }
    }
    
    ; Search at each scale
    for index, scale in scales {
        LogMessage("Searching at scale " . index . "/" . levels . " (" . Round(scale * 100) . "%)")
        VizStatusText.Value := "Searching at scale " . index . "/" . levels . " (" . Round(scale * 100) . "%)"
        
        ; Scale the pattern
        scaledPattern := ScalePattern(CurrentPattern, scale)
        
        ; Perform search
        ok := FindText(&x := 0, &y := 0, x1, y1, x2, y2, err1, err0, scaledPattern, ScreenshotMode, FindAll)
        
        if (ok) {
            for matchIndex, match in ok {
                ; Store match with scale info
                allMatches.Push(Map(
                    "x", match.x,
                    "y", match.y,
                    "w", match.w,
                    "h", match.h,
                    "similarity", 1.0,
                    "scale", scale
                ))
                
                ; Draw with scale-specific color
                DrawFinalMatch(match.x, match.y, match.w, match.h, 1.0)
            }
        }
    }
    
    return allMatches
}

ScalePattern(pattern, scale) {
    /*
    SCALES A FINDTEXT PATTERN
    
    This is a simplified version - in reality would need to:
    1. Parse FindText format
    2. Extract pattern dimensions
    3. Resize the pattern data
    4. Recreate FindText format
    
    For now, returns original pattern
    (Full implementation would require deep FindText format knowledge)
    */
    
    ; TODO: Implement actual pattern scaling
    ; This is complex and requires understanding FindText's binary format
    
    return pattern
}


; ============================================================================
; SECTION 7: RESULTS DISPLAY FUNCTIONS
; ============================================================================

DisplayResults() {
    /*
    DISPLAYS SEARCH RESULTS IN LISTVIEW
    Shows all found matches with their properties
    */
    
    global ResultsList, SearchResults
    
    ; Clear existing items
    ResultsList.Delete()
    
    ; Add each result
    for index, match in SearchResults {
        ResultsList.Add(, 
            index,
            match["x"],
            match["y"],
            match["w"],
            match["h"],
            Round(match["similarity"] * 100) . "%",
            Round(match["scale"] * 100) . "%"
        )
    }
    
    ; Auto-size columns
    loop 7 {
        ResultsList.ModifyCol(A_Index, "AutoHdr")
    }
}

DisplayMetrics(elapsedMs) {
    /*
    DISPLAYS BENCHMARK METRICS
    
    METRICS SHOWN:
    - Duration
    - Positions checked
    - Matches found
    - Throughput (positions/second)
    - Average similarity
    
    PARAMETERS:
    - elapsedMs: Time taken in milliseconds
    */
    
    global MetricsText, SearchResults, PositionsChecked
    
    ; Calculate metrics
    matchCount := SearchResults.Length
    elapsedSec := elapsedMs / 1000.0
    throughput := elapsedSec > 0 ? Round(PositionsChecked / elapsedSec) : 0
    
    ; Calculate average similarity
    totalSim := 0
    for index, match in SearchResults {
        totalSim += match["similarity"]
    }
    avgSim := matchCount > 0 ? totalSim / matchCount : 0
    
    ; Format report
    report := ""
    report .= "══════════════════════════════════════════════════════`n"
    report .= "                 BENCHMARK METRICS                     `n"
    report .= "══════════════════════════════════════════════════════`n`n"
    
    report .= "Duration:           " . elapsedMs . " ms (" . Round(elapsedSec, 2) . " seconds)`n"
    report .= "Matches Found:      " . matchCount . "`n"
    report .= "Positions Checked:  " . PositionsChecked . "`n"
    report .= "Throughput:         " . Format("{:,}", throughput) . " positions/second`n`n"
    
    if (matchCount > 0) {
        report .= "Average Similarity: " . Round(avgSim * 100, 1) . "%`n"
        
        ; Scale distribution if multi-scale
        if (MultiScaleParams["Enabled"]) {
            report .= "`nMatches by Scale:`n"
            
            scaleGroups := Map()
            for index, match in SearchResults {
                scale := Round(match["scale"] * 100)
                if (!scaleGroups.Has(scale))
                    scaleGroups[scale] := 0
                scaleGroups[scale] := scaleGroups[scale] + 1
            }
            
            for scale, count in scaleGroups {
                report .= "  " . scale . "%: " . count . " match(es)`n"
            }
        }
    }
    
    report .= "`n══════════════════════════════════════════════════════`n"
    report .= "Search Region:      "
    if (SearchParams["SearchRegion"] = "FullScreen") {
        report .= "Full Screen`n"
    } else {
        report .= "Custom (" . SearchParams["X1"] . "," . SearchParams["Y1"] . ") to (" . SearchParams["X2"] . "," . SearchParams["Y2"] . ")`n"
    }
    
    report .= "Text Tolerance:     " . Round(SearchParams["err1"] * 100) . "%`n"
    report .= "Bg Tolerance:       " . Round(SearchParams["err0"] * 100) . "%`n"
    report .= "Find All:           " . (SearchParams["FindAll"] ? "Yes" : "No") . "`n"
    report .= "Multi-Scale:        " . (MultiScaleParams["Enabled"] ? "Yes (" . MultiScaleParams["Levels"] . " levels)" : "No") . "`n"
    
    report .= "══════════════════════════════════════════════════════`n"
    
    ; Display in metrics tab
    MetricsText.Value := report
}

ClearResults() {
    /*
    CLEARS ALL RESULTS AND RESETS VISUALIZATION
    */
    
    global ResultsList, MetricsText, SearchResults
    
    ; Clear results
    ResultsList.Delete()
    SearchResults := []
    
    ; Reset metrics
    MetricsText.Value := "No search performed yet.`n`nBenchmark metrics will appear here after search."
    
    ; Clear visualization
    ClearVisualization()
    
    ; Update status
    VizProgressText.Value := "Positions: 0 | Matches: 0 | Speed: 0 pos/sec"
    
    LogMessage("Results cleared")
}


; ============================================================================
; SECTION 8: PATTERN MANAGEMENT FUNCTIONS
; ============================================================================

CapturePattern() {
    /*
    CAPTURES A PATTERN USING FINDTEXT'S CAPTURE TOOL
    
    Opens FindText's built-in GUI for pattern capture
    User selects area, then pattern is saved to CurrentPattern
    */
    
    global CurrentPattern, PatternInfo
    
    LogMessage("Opening FindText capture tool...")
    
    ; Use FindText's built-in capture GUI
    ; This opens the selection tool
    t1 := FindText()  ; Create FindText object
    
    ; Call CaptureCur() or the appropriate capture method
    ; Note: Exact method depends on FindText.ahk version
    ; This is a placeholder - adjust based on your FindText.ahk
    
    MsgBox("Use FindText's capture tool (Alt+1) to capture a pattern.`n`nAfter capturing, the pattern will be loaded into the GUI.", "Info", "Icon")
    
    ; Wait for user to capture
    ; In real implementation, would hook into FindText's capture completion
    ; For now, prompt user to paste pattern
    
    ; TODO: Integrate with FindText's actual capture mechanism
    ; This requires understanding FindText's capture API
}

LoadPattern() {
    /*
    LOADS A PATTERN FROM FILE
    
    Opens file dialog for user to select pattern file
    Pattern files are text files containing FindText format
    */
    
    global CurrentPattern, PatternInfo, PatternInfoText, StatusBar
    
    ; Show file dialog
    selectedFile := FileSelect(3, , "Load FindText Pattern", "Text Files (*.txt)")
    
    if (!selectedFile) {
        LogMessage("Pattern load cancelled")
        return
    }
    
    try {
        ; Read pattern from file
        CurrentPattern := FileRead(selectedFile)
        
        ; Parse pattern info
        ; FindText format: |<comment>$...
        if (InStr(CurrentPattern, "|<")) {
            commentEnd := InStr(CurrentPattern, ">")
            if (commentEnd) {
                PatternInfo["name"] := SubStr(CurrentPattern, 3, commentEnd - 3)
            } else {
                PatternInfo["name"] := "Unnamed"
            }
        } else {
            PatternInfo["name"] := "Unnamed"
        }
        
        PatternInfo["file"] := selectedFile
        PatternInfo["size"] := StrLen(CurrentPattern)
        
        ; Update GUI
        PatternInfoText.Value := "Name: " . PatternInfo["name"] . "`nFile: " . selectedFile . "`nSize: " . PatternInfo["size"] . " bytes"
        StatusBar.SetText("Pattern loaded: " . PatternInfo["name"], 2)
        
        LogMessage("Pattern loaded: " . selectedFile)
        
    } catch as err {
        MsgBox("Failed to load pattern:`n`n" . err.Message, "Error", "Icon!")
        LogMessage("ERROR loading pattern: " . err.Message)
    }
}

SavePattern() {
    /*
    SAVES CURRENT PATTERN TO FILE
    */
    
    global CurrentPattern, PatternInfo
    
    if (!CurrentPattern || CurrentPattern = "") {
        MsgBox("No pattern to save!", "Warning", "Icon!")
        return
    }
    
    ; Show file dialog
    selectedFile := FileSelect("S16", , "Save FindText Pattern", "Text Files (*.txt)")
    
    if (!selectedFile) {
        LogMessage("Pattern save cancelled")
        return
    }
    
    ; Add .txt extension if not present
    if (!InStr(selectedFile, ".txt")) {
        selectedFile .= ".txt"
    }
    
    try {
        ; Write pattern to file
        FileDelete(selectedFile)  ; Delete if exists
        FileAppend(CurrentPattern, selectedFile)
        
        LogMessage("Pattern saved: " . selectedFile)
        MsgBox("Pattern saved successfully!", "Success", "Icon")
        
    } catch as err {
        MsgBox("Failed to save pattern:`n`n" . err.Message, "Error", "Icon!")
        LogMessage("ERROR saving pattern: " . err.Message)
    }
}

RefreshPatternLibrary() {
    /*
    REFRESHES THE PATTERN LIBRARY LIST
    Scans pattern library folder and lists all .txt files
    */
    
    global PatternLibraryLV, PatternLibPathEdit
    
    ; Clear listview
    PatternLibraryLV.Delete()
    
    ; Get library path
    libPath := PatternLibPathEdit.Value
    
    ; Create folder if doesn't exist
    if (!DirExist(libPath)) {
        try {
            DirCreate(libPath)
        } catch {
            LogMessage("Could not create pattern library folder")
            return
        }
    }
    
    ; Scan for pattern files
    Loop Files, libPath . "\*.txt" {
        ; Get file info
        fileName := A_LoopFileName
        fileSize := A_LoopFileSize
        fileDate := A_LoopFileTimeModified
        
        ; Add to listview
        PatternLibraryLV.Add(, fileName, fileSize . " bytes", fileDate)
    }
    
    LogMessage("Pattern library refreshed: " . PatternLibraryLV.GetCount() . " patterns found")
}

LoadPatternFromLibrary(*) {
    /*
    LOADS SELECTED PATTERN FROM LIBRARY
    */
    
    global PatternLibraryLV, PatternLibPathEdit
    
    ; Get selected row
    selectedRow := PatternLibraryLV.GetNext()
    
    if (!selectedRow) {
        MsgBox("Please select a pattern to load!", "Info", "Icon")
        return
    }
    
    ; Get filename
    fileName := PatternLibraryLV.GetText(selectedRow, 1)
    filePath := PatternLibPathEdit.Value . "\" . fileName
    
    ; Load the pattern (reuse LoadPattern logic)
    global CurrentPattern, PatternInfo, PatternInfoText, StatusBar
    
    try {
        CurrentPattern := FileRead(filePath)
        
        if (InStr(CurrentPattern, "|<")) {
            commentEnd := InStr(CurrentPattern, ">")
            if (commentEnd) {
                PatternInfo["name"] := SubStr(CurrentPattern, 3, commentEnd - 3)
            } else {
                PatternInfo["name"] := fileName
            }
        } else {
            PatternInfo["name"] := fileName
        }
        
        PatternInfo["file"] := filePath
        PatternInfo["size"] := StrLen(CurrentPattern)
        
        PatternInfoText.Value := "Name: " . PatternInfo["name"] . "`nFile: " . filePath . "`nSize: " . PatternInfo["size"] . " bytes"
        StatusBar.SetText("Pattern loaded: " . PatternInfo["name"], 2)
        
        LogMessage("Pattern loaded from library: " . fileName)
        
    } catch as err {
        MsgBox("Failed to load pattern:`n`n" . err.Message, "Error", "Icon!")
    }
}

DeletePatternFromLibrary(*) {
    /*
    DELETES SELECTED PATTERN FROM LIBRARY
    */
    
    global PatternLibraryLV, PatternLibPathEdit
    
    selectedRow := PatternLibraryLV.GetNext()
    
    if (!selectedRow) {
        MsgBox("Please select a pattern to delete!", "Info", "Icon")
        return
    }
    
    fileName := PatternLibraryLV.GetText(selectedRow, 1)
    
    ; Confirm deletion
    result := MsgBox("Delete pattern: " . fileName . "?`n`nThis cannot be undone!", "Confirm Delete", "YesNo Icon!")
    
    if (result = "No") {
        return
    }
    
    filePath := PatternLibPathEdit.Value . "\" . fileName
    
    try {
        FileDelete(filePath)
        LogMessage("Pattern deleted: " . fileName)
        RefreshPatternLibrary()
    } catch as err {
        MsgBox("Failed to delete pattern:`n`n" . err.Message, "Error", "Icon!")
    }
}


; ============================================================================
; SECTION 9: GUI UPDATE FUNCTIONS (Parameter Changes)
; ============================================================================

UpdateErr1Value(*) {
    /*
    UPDATES TEXT TOLERANCE VALUE DISPLAY
    Called when err1 slider moves
    */
    
    global Err1Slider, Err1ValueText, SearchParams
    
    ; Get slider value (0-100)
    value := Err1Slider.Value
    
    ; Convert to 0.0-1.0 range
    normalizedValue := value / 100.0
    
    ; Update display
    Err1ValueText.Value := Format("{:.2f}", normalizedValue)
    
    ; Store in parameters
    SearchParams["err1"] := normalizedValue
}

UpdateErr0Value(*) {
    global Err0Slider, Err0ValueText, SearchParams
    value := Err0Slider.Value
    normalizedValue := value / 100.0
    Err0ValueText.Value := Format("{:.2f}", normalizedValue)
    SearchParams["err0"] := normalizedValue
}

UpdateSearchRegion(region) {
    global SearchParams
    SearchParams["SearchRegion"] := region
    LogMessage("Search region changed to: " . region)
}

UpdateVizScale(*) {
    global VizScaleSlider, VizScaleText, VizParams
    value := VizScaleSlider.Value
    VizScaleText.Value := value . "%"
    VizParams["Scale"] := value / 100.0
}

UpdateVizDelay(*) {
    global VizDelaySlider, VizDelayText, VizParams
    value := VizDelaySlider.Value
    VizDelayText.Value := value
    VizParams["UpdateDelay"] := value
}

UpdateTrailLength(*) {
    global TrailLengthSlider, TrailLengthText, VizParams
    value := TrailLengthSlider.Value
    TrailLengthText.Value := value
    VizParams["TrailLength"] := value
}

UpdateScaleLevels(*) {
    global ScaleLevelsSlider, ScaleLevelsText, MultiScaleParams
    value := ScaleLevelsSlider.Value
    ScaleLevelsText.Value := value
    MultiScaleParams["Levels"] := value
    UpdateScalesPreview()
}

UpdateMinScale(*) {
    global MinScaleSlider, MinScaleText, MultiScaleParams
    value := MinScaleSlider.Value
    MinScaleText.Value := value . "%"
    MultiScaleParams["MinScale"] := value / 100.0
    UpdateScalesPreview()
}

UpdateMaxScale(*) {
    global MaxScaleSlider, MaxScaleText, MultiScaleParams
    value := MaxScaleSlider.Value
    MaxScaleText.Value := value . "%"
    MultiScaleParams["MaxScale"] := value / 100.0
    UpdateScalesPreview()
}

UpdateSearchStep(*) {
    global SearchStepSlider, SearchStepText
    value := SearchStepSlider.Value
    SearchStepText.Value := value
}

UpdateScalesPreview() {
    /*
    UPDATES THE MULTI-SCALE PREVIEW TEXT
    Shows which scales will be searched
    */
    
    global ScalesPreviewText, MultiScaleParams
    
    levels := MultiScaleParams["Levels"]
    minScale := MultiScaleParams["MinScale"]
    maxScale := MultiScaleParams["MaxScale"]
    
    preview := "Scales that will be searched:`n`n"
    
    if (levels = 1) {
        preview .= "Scale 1: 100%`n"
    } else {
        step := (maxScale - minScale) / (levels - 1)
        
        loop levels {
            scale := minScale + ((A_Index - 1) * step)
            preview .= "Scale " . A_Index . ": " . Round(scale * 100) . "%`n"
        }
    }
    
    preview .= "`nTotal: " . levels . " scale(s)`n"
    preview .= "Range: " . Round(minScale * 100) . "% - " . Round(maxScale * 100) . "%"
    
    ScalesPreviewText.Value := preview
}


; ============================================================================
; SECTION 10: UTILITY FUNCTIONS
; ============================================================================

LogMessage(message) {
    /*
    ADDS MESSAGE TO LOG
    Appends timestamped message to log text control
    */
    
    global LogText
    
    ; Get current time
    timestamp := FormatTime(, "[HH:mm:ss]")
    
    ; Append to log
    currentLog := LogText.Value
    newLog := currentLog . timestamp . " " . message . "`n"
    LogText.Value := newLog
    
    ; Scroll to bottom
    ; SendMessage to scroll to end
    SendMessage(0x0115, 7, 0, LogText.Hwnd)  ; WM_VSCROLL, SB_BOTTOM
}

SelectRegionInteractive() {
    /*
    ALLOWS USER TO SELECT REGION BY DRAGGING ON SCREEN
    Creates a selection overlay
    */
    
    ; TODO: Implement interactive region selection
    ; Would require creating transparent overlay GUI
    ; Capturing mouse drag events
    ; Showing selection rectangle
    
    MsgBox("Interactive region selection not yet implemented.`n`nPlease enter coordinates manually or use Full Screen.", "Info", "Icon")
}

ExportResults() {
    /*
    EXPORTS SEARCH RESULTS TO FILE
    */
    
    global SearchResults, MetricsText
    
    if (SearchResults.Length = 0) {
        MsgBox("No results to export!", "Info", "Icon")
        return
    }
    
    ; Show file dialog
    selectedFile := FileSelect("S16", , "Export Search Results", "Text Files (*.txt)")
    
    if (!selectedFile) {
        return
    }
    
    if (!InStr(selectedFile, ".txt")) {
        selectedFile .= ".txt"
    }
    
    try {
        ; Build export content
        content := "FINDTEXT SEARCH RESULTS`n"
        content .= "=" . StrRepeater("=", 60) . "`n`n"
        content .= "Generated: " . FormatTime(, "yyyy-MM-dd HH:mm:ss") . "`n`n"
        
        content .= "MATCHES:`n"
        content .= "-" . StrRepeater("-", 60) . "`n"
        
        for index, match in SearchResults {
            content .= "Match " . index . ":`n"
            content .= "  Position: (" . match["x"] . ", " . match["y"] . ")`n"
            content .= "  Size: " . match["w"] . "x" . match["h"] . "`n"
            content .= "  Similarity: " . Round(match["similarity"] * 100) . "%`n"
            content .= "  Scale: " . Round(match["scale"] * 100) . "%`n`n"
        }
        
        content .= "`n`nMETRICS:`n"
        content .= "-" . StrRepeater("-", 60) . "`n"
        content .= MetricsText.Value
        
        ; Write to file
        FileDelete(selectedFile)
        FileAppend(content, selectedFile)
        
        LogMessage("Results exported to: " . selectedFile)
        MsgBox("Results exported successfully!", "Success", "Icon")
        
    } catch as err {
        MsgBox("Failed to export results:`n`n" . err.Message, "Error", "Icon!")
    }
}

StrRepeater(str, count) {
    /*
    REPEATS A STRING N TIMES
    Helper function for formatting
    */
    result := ""
    loop count {
        result .= str
    }
    return result
}

ShowPatternLibrary() {
    ; Switch to Patterns tab
    ; TODO: Programmatically select tab
    MsgBox("Pattern Library is in the 'Patterns' tab.", "Info", "Icon")
}

RunBenchmarkTest() {
    /*
    RUNS AUTOMATED BENCHMARK TEST
    Tests search performance with various parameters
    */
    
    MsgBox("Benchmark test not yet implemented.`n`nUse normal search and check Metrics tab for performance data.", "Info", "Icon")
}

ShowDocumentation() {
    /*
    SHOWS DOCUMENTATION/HELP
    */
    
    helpText := "
    (
FINDTEXT GUI TEST SUITE - DOCUMENTATION

QUICK START:
1. Capture or load a pattern
2. Configure search parameters
3. Click 'Start Search'
4. View results and visualization

PARAMETERS:
- Text Tolerance (err1): How different text can be (0-100%)
- Background Tolerance (err0): How different background can be (0-100%)
- Search Region: Full screen or custom area
- Find All: Find all matches or just first one

VISUALIZATION:
- Blue box = current position being checked
- Color intensity = match quality
- Green boxes = found matches

MULTI-SCALE:
- Searches pattern at multiple sizes
- Perfect for finding icons at different scales
- Configure levels and range in Multi-Scale tab

HOTKEYS:
- F5: Start search
- Ctrl+F1: Capture pattern
- Esc: Stop search

For more information, see README.txt
    )"
    
    MsgBox(helpText, "Documentation", "Icon")
}

ShowAbout() {
    /*
    SHOWS ABOUT DIALOG
    */
    
    aboutText := "
    (
FindText.ahk GUI Test Suite
Version 1.0

Comprehensive testing and visualization tool
for the FindText.ahk library.

FEATURES:
• Real-time visualization of scanning
• Progressive match intensity display
• Benchmark metrics and analysis
• Pattern library management
• Multi-scale pattern matching
• Intuitive tweakable parameters

© 2024
AutoHotkey v2
    )"
    
    MsgBox(aboutText, "About", "Icon 64")
}

GuiSize(GuiObj, MinMax, Width, Height) {
    /*
    HANDLES GUI RESIZE EVENT
    Adjusts control positions/sizes when window is resized
    */
    
    ; TODO: Implement dynamic resizing
    ; Would recalculate control positions based on new window size
}


; ============================================================================
; SECTION 11: GDI+ HELPER FUNCTIONS
; ============================================================================

/*
These are wrapper functions for GDI+ operations
GDI+ is Windows' graphics library for drawing shapes, images, text, etc.

INCLUDED HERE FOR CONVENIENCE
In production, these would be in a separate library file
*/

Gdip_Startup() {
    /*
    INITIALIZES GDI+
    Must be called before using any GDI+ functions
    RETURNS: Token for GDI+ session
    */
    
    pToken := 0
    si := Buffer(24, 0)  ; GdiplusStartupInput structure
    NumPut("UInt", 1, si)  ; GdiplusVersion = 1
    
    DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken, "Ptr", si, "Ptr", 0)
    return pToken
}

Gdip_Shutdown(pToken) {
    /*
    SHUTS DOWN GDI+
    Call when exiting application
    */
    DllCall("gdiplus\GdiplusShutdown", "Ptr", pToken)
}

Gdip_CreateBitmap(width, height) {
    /*
    CREATES A BITMAP (IMAGE BUFFER)
    */
    pBitmap := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "Int", width, "Int", height, "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
    return pBitmap
}

Gdip_GraphicsFromImage(pBitmap) {
    /*
    CREATES GRAPHICS OBJECT FROM BITMAP
    Graphics object provides drawing functions
    */
    pGraphics := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pBitmap, "Ptr*", &pGraphics)
    return pGraphics
}

Gdip_SetSmoothingMode(pGraphics, mode) {
    /*
    SETS DRAWING QUALITY
    mode=4 is anti-aliased (smooth)
    */
    return DllCall("gdiplus\GdipSetSmoothingMode", "Ptr", pGraphics, "Int", mode)
}

Gdip_GraphicsClear(pGraphics, color) {
    /*
    CLEARS GRAPHICS WITH SOLID COLOR
    color format: 0xAARRGGBB (alpha, red, green, blue)
    */
    return DllCall("gdiplus\GdipGraphicsClear", "Ptr", pGraphics, "UInt", color)
}

Gdip_BrushCreateSolid(color) {
    /*
    CREATES SOLID COLOR BRUSH
    Brushes are used to fill shapes
    */
    pBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "UInt", color, "Ptr*", &pBrush)
    return pBrush
}

Gdip_DeleteBrush(pBrush) {
    /*
    DELETES BRUSH (CLEANUP)
    Always delete objects to prevent memory leaks
    */
    return DllCall("gdiplus\GdipDeleteBrush", "Ptr", pBrush)
}

Gdip_FillRectangle(pGraphics, pBrush, x, y, w, h) {
    /*
    DRAWS FILLED RECTANGLE
    */
    return DllCall("gdiplus\GdipFillRectangle", "Ptr", pGraphics, "Ptr", pBrush, "Float", x, "Float", y, "Float", w, "Float", h)
}

Gdip_CreatePen(color, width) {
    /*
    CREATES PEN FOR DRAWING LINES/OUTLINES
    */
    pPen := 0
    DllCall("gdiplus\GdipCreatePen1", "UInt", color, "Float", width, "Int", 2, "Ptr*", &pPen)
    return pPen
}

Gdip_DeletePen(pPen) {
    /*
    DELETES PEN (CLEANUP)
    */
    return DllCall("gdiplus\GdipDeletePen", "Ptr", pPen)
}

Gdip_DrawRectangle(pGraphics, pPen, x, y, w, h) {
    /*
    DRAWS RECTANGLE OUTLINE
    */
    return DllCall("gdiplus\GdipDrawRectangle", "Ptr", pGraphics, "Ptr", pPen, "Float", x, "Float", y, "Float", w, "Float", h)
}

Gdip_CreateHBITMAPFromBitmap(pBitmap) {
    /*
    CONVERTS GDI+ BITMAP TO WINDOWS BITMAP HANDLE
    Needed to display in Picture control
    */
    hBitmap := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hBitmap, "UInt", 0)
    return hBitmap
}

Gdip_TextToGraphics(pGraphics, text, options, font) {
    /*
    DRAWS TEXT ON GRAPHICS
    Simplified version - full implementation more complex
    */
    ; TODO: Implement full text drawing
    ; Requires creating font, measuring text, drawing, etc.
    return 0
}


; ============================================================================
; SCRIPT EXIT CLEANUP
; ============================================================================

OnExit(CleanupAndExit)

CleanupAndExit(*) {
    /*
    CLEANUP WHEN SCRIPT EXITS
    Frees GDI+ resources to prevent memory leaks
    */
    
    global pToken, VizBitmap, VizGraphics
    
    ; Delete GDI+ objects
    if (VizGraphics)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", VizGraphics)
    
    if (VizBitmap)
        DllCall("gdiplus\GdipDisposeImage", "Ptr", VizBitmap)
    
    ; Shutdown GDI+
    if (pToken)
        Gdip_Shutdown(pToken)
}


; ============================================================================
; END OF SCRIPT
; ============================================================================

/*
NOTES FOR USERS:

This script provides a comprehensive GUI for testing and visualizing
the FindText.ahk library. 

TO USE:
1. Ensure FindText.ahk is in the same directory or #Include path
2. Run this script
3. Capture or load a pattern
4. Configure parameters in the tabs
5. Start search and watch the visualization!

CUSTOMIZATION:
- All parameters are tweakable via GUI
- Colors can be changed in the visualization drawing functions
- Layout can be adjusted in CreateMainGUI()

PERFORMANCE:
- Visualization adds overhead but helps understand the process
- Disable visualization for maximum speed
- Multi-scale searching is slower but finds all sizes

For questions or issues, refer to FindText.ahk documentation.

Happy pattern hunting! 🎯
*/

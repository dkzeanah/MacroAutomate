
; proj creator options to open in vscode / not work - create button should destroy the window. 
;default directory should be root of script / data / projs.
;






; =====================================================================================
; GLOBALCODER ENHANCED - Comprehensive Menu & Automation System
; AutoHotkey v2.0 - Teaching Edition with Custom Menu Navigation
; =====================================================================================
; 
; WHAT THIS SCRIPT DOES:
; This script creates a powerful menu system that can be triggered via hotkeys or
; hotstrings. When the menu is visible, you can navigate it using speed keys.
;
; NEW FEATURES IN THIS VERSION:
; 1. Custom GUI-based menu with speed key navigation (j, f, g, h, s, m, i)
; 2. Hotstring manager (jjj = menu, ggg = google/GPT with logging)
; 3. Arrow key navigation when menu is visible
; 4. Fixed InitializeActionsFile() function (was commented out)
; 5. Query logging to file database
;
; SPEED KEYS (only when menu is visible):
; j = move down (like arrow down)
; k = move up (like arrow up)  
; f = go up menu tree (back/parent)
; g = jump to admin menu
; h = select item (like Enter)
; s = jump to snips section
; m = jump to messages section
; i = jump to instructions
;
; HOTSTRINGS:
; jjj = show the global menu
; ggg = google/GPT search with logging
;
; =====================================================================================
#Requires AutoHotkey v2.0
#SingleInstance Force
#ErrorStdOut

; =====================================================================================
; SECTION 1: GLOBAL VARIABLES & PATHS
; =====================================================================================
; These are script-wide variables accessible from any function.
; The 'global' keyword declares them at the top level of the script.

global mainMenu := ""              ; Stores the main menu object
global TotalWords := 0             ; Counter for word statistics
global items := 0                  ; Counter for menu items
global callingWindowTitle := ""    ; Stores the title of window that was active when menu opened
global callingWindowItem := ""     ; Menu item text showing calling window info

; --- Custom Menu System Variables ---
; These track the state of our custom GUI-based menu
global customMenuGui := ""         ; The GUI object for our custom menu
global menuIsVisible := false      ; Boolean flag: is the menu currently showing?
global currentMenuItems := []      ; Array of items in the current menu view
global currentMenuIndex := 1       ; Which item is currently highlighted (1-based)
global menuStack := []             ; Stack of previous menus for "back" navigation
global menuListView := ""          ; Reference to the ListView control in the menu

; --- Hotstring Query Logging ---
; File where we log all google/GPT queries triggered by 'ggg' hotstring
global QueryLogFile := ""          ; Path to the query log file

; --- Path definitions ---
; These paths define where the script stores its data files
global CustomMenuPath := A_ScriptDir "\CustomMenuFiles"    ; Main data folder
global LogsPath := CustomMenuPath "\logs"                   ; Log files
global NotesPath := CustomMenuPath "\notes"                 ; Note files
global ClassesPath := NotesPath "\classes"                  ; Class definition files
global SnipsPath := CustomMenuPath "\0_snips"               ; Code snippets
global ProjectsPath := CustomMenuPath "\1_projects"         ; Project files
global SettingsFile := CustomMenuPath "\settings.ini"       ; User settings
global ActionsFile := CustomMenuPath "\actions.ini"         ; Action definitions
global StepFilesPath := CustomMenuPath "\step_definitions"  ; Tutorial step files
global HotstringsFile := CustomMenuPath "\hotstrings.ini"   ; Custom hotstring definitions

; --- Project management paths ---
global DefaultProjectRoot := CustomMenuPath "\data\projects"
global VSCodePath := "code"
global SublimePath := "C:\Program Files\Sublime Text\sublime_text.exe"
global GitBashPath := "C:\Program Files\Git\git-bash.exe"
global TemplatesPath := CustomMenuPath "\templates"

; --- GUT-Display defaults ---
; GUT = Global Universal Transparent display (non-focus-stealing popup)
global GUT_DefaultTimeout := 5000          ; 5 seconds auto-hide
global GUT_DefaultTransparency := 180      ; 0=invisible, 255=opaque
global GUT_DefaultWidth := 500
global GUT_DefaultHeight := 300

; --- Active StepCanvas reference for hotkey handling ---
global activeStepCanvas := ""

; =====================================================================================
; SECTION 2: INITIALIZATION
; =====================================================================================
; This section runs when the script first starts.
; It sets up folders, loads settings, and prepares the menu.

InitializeSettings()           ; Load or create settings file
InitializeFolderStructure()    ; Create required directories
InitializeHotstrings()         ; Set up hotstring triggers
SetupTrayMenu()                ; Configure system tray icon menu

; Build the menu structure from the CustomMenuPath folder
mainMenu := PrepareMenu(CustomMenuPath)

; Set up error handling - logs errors to a file instead of crashing
OnError(LogError)

; The 'Return' here ends the auto-execute section
; Everything below will only run when called by hotkeys/functions
Return

; =====================================================================================
; SECTION 3: HOTSTRING MANAGER
; =====================================================================================
; Hotstrings trigger actions when you type specific text sequences.
; Unlike hotkeys (which use modifier keys), hotstrings activate on typed text.
;
; HOW HOTSTRINGS WORK:
; When you type "jjj" and press space/enter/tab, AHK detects the pattern
; and runs the associated function. The asterisk (*) means "trigger immediately"
; without waiting for an ending character.

InitializeHotstrings() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Register all hotstring triggers for the application
    ; 
    ; SYNTAX EXPLANATION:
    ; Hotstring("::trigger", callback)  - Standard hotstring, triggers on ending char
    ; Hotstring(":*:trigger", callback) - Immediate trigger, no ending char needed
    ; Hotstring(":?:trigger", callback) - Triggers even inside other words
    ; Hotstring(":B0:trigger", callback)- Don't backspace the trigger text
    ; ---------------------------------------------------------------------------------
    global QueryLogFile, CustomMenuPath
    
    ; Initialize the query log file path
    ; This file stores all google/GPT queries in a line-by-line format
    QueryLogFile := CustomMenuPath "\query_log.txt"
    
    ; --- JJJ Hotstring: Show the global menu ---
    ; The :*: prefix means trigger immediately (no space/enter needed)
    ; The :?: means trigger even if typed inside another word
    ; The :B0: means don't backspace (erase) the trigger characters
    ; We combine: :*?B0: for immediate trigger, anywhere, keeping the text
    ; Actually, we want to erase 'jjj', so we use :*: only
    Hotstring(":*:jjj", ShowCustomMenu)
    
    ; --- GGG Hotstring: Google/GPT search with logging ---
    ; This triggers a search dialog and logs the query to a file
    Hotstring(":*:ggg", GoogleSearchWithLogging)
    
    ; --- Load custom hotstrings from file ---
    ; Users can define their own hotstrings in hotstrings.ini
    LoadCustomHotstrings()
}

LoadCustomHotstrings() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Load user-defined hotstrings from the hotstrings.ini file
    ; 
    ; FILE FORMAT (hotstrings.ini):
    ; [Hotstrings]
    ; myhs=This text will be inserted
    ; sig=Best regards, John Doe
    ; ---------------------------------------------------------------------------------
    global HotstringsFile
    
    ; Check if the hotstrings file exists
    if (!FileExist(HotstringsFile)) {
        ; Create a default hotstrings file with examples
        ; The parentheses syntax is a "continuation section" - allows multi-line strings
        defaultContent := "
(
; =====================================================================================
; CUSTOM HOTSTRINGS FILE
; =====================================================================================
; Format: trigger=replacement text
; Lines starting with ; are comments
;
; Example:
; myemail=john.doe@example.com
; sig=Best regards,`nJohn Doe
;
; Note: Use `n for newlines in replacement text
; =====================================================================================

[Hotstrings]
; Add your custom hotstrings below:
; btw=by the way
; omw=on my way

[Expansions]
; Longer text expansions:
; lorem=Lorem ipsum dolor sit amet, consectetur adipiscing elit.
)"
        FileAppend(defaultContent, HotstringsFile)
        return
    }
    
    ; Read and parse the hotstrings file
    try {
        fileContent := FileRead(HotstringsFile)
    } catch {
        return  ; Silent fail if file can't be read
    }
    
    ; Track which section we're in
    currentSection := ""
    
    ; Loop through each line of the file
    ; StrSplit splits the content by newline, and we also trim carriage returns
    for lineText in StrSplit(fileContent, "`n", "`r") {
        lineText := Trim(lineText)  ; Remove leading/trailing whitespace
        
        ; Skip empty lines and comments (lines starting with ;)
        if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
            continue
        }
        
        ; Check for section headers like [Hotstrings]
        if (SubStr(lineText, 1, 1) = "[" && SubStr(lineText, -1) = "]") {
            ; Extract section name (remove the brackets)
            currentSection := SubStr(lineText, 2, StrLen(lineText) - 2)
            continue
        }
        
        ; Parse hotstring definitions (trigger=replacement)
        if (InStr(lineText, "=") && (currentSection = "Hotstrings" || currentSection = "Expansions")) {
            ; Split on first = sign only (in case replacement contains =)
            parts := StrSplit(lineText, "=", , 2)
            if (parts.Length >= 2) {
                trigger := Trim(parts[1])
                replacement := Trim(parts[2])
                
                ; Convert escape sequences like `n to actual newlines
                replacement := StrReplace(replacement, "``n", "`n")
                replacement := StrReplace(replacement, "``t", "`t")
                
                ; Register the hotstring
                ; We use :*: for immediate trigger (no ending character needed)
                try {
                    Hotstring(":*:" . trigger, (*) => SendText(replacement))
                }
            }
        }
    }
}

GoogleSearchWithLogging(*) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Show a search dialog, perform Google search, and log the query
    ; 
    ; HOW IT WORKS:
    ; 1. Shows an InputBox asking for the search query
    ; 2. Logs the query with timestamp to query_log.txt
    ; 3. Opens Google search in the default browser
    ;
    ; The asterisk (*) in the parameter list captures any arguments passed
    ; (hotstring callbacks receive some info we don't need here)
    ; ---------------------------------------------------------------------------------
    global QueryLogFile
    
    ; Show input dialog for search query
    ; InputBox returns an object with .Result (OK/Cancel) and .Value (the text)
    result := InputBox("Enter search query (will be logged):", "Google/GPT Search", "w350 h120")
    
    ; Check if user cancelled or entered nothing
    if (result.Result = "Cancel" || result.Value = "") {
        return
    }
    
    query := result.Value
    
    ; --- Log the query to file ---
    ; Format: timestamp | query
    ; This creates a line-delineated database of all searches
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    logEntry := timestamp . " | " . query . "`n"
    
    ; Append to the log file (creates file if it doesn't exist)
    try {
        FileAppend(logEntry, QueryLogFile)
    } catch as err {
        ; Show error but continue with the search
        ToolTip("Log error: " . err.Message)
        SetTimer((*) => ToolTip(), -2000)
    }
    
    ; --- Perform the Google search ---
    ; UrlEncode converts spaces and special characters to URL-safe format
    encodedQuery := UrlEncode(query)
    
    ; as_qdr=y1 limits results to the past year
    url := "https://www.google.com/search?q=" . encodedQuery . "&as_qdr=y1"
    
    ; Open the URL in the default browser
    Run(url)
    
    ; Show confirmation
    GUT_Display("Search Logged", "Query: " . query . "`n`nLogged to: query_log.txt", 2000)
}

ShowQueryLog(*) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Display the query log in a GUT-Display window
    ; ---------------------------------------------------------------------------------
    global QueryLogFile
    
    if (!FileExist(QueryLogFile)) {
        GUT_Display("Query Log", "No queries logged yet.`n`nUse 'ggg' hotstring to search and log.", 3000)
        return
    }
    
    content := FileRead(QueryLogFile)
    
    ; Count the number of queries (non-empty lines)
    lineCount := 0
    for line in StrSplit(content, "`n", "`r") {
        if (Trim(line) != "") {
            lineCount++
        }
    }
    
    options := Map()
    options["width"] := 600
    options["height"] := 400
    
    GUT_Display("Query Log (" . lineCount . " queries)", content, -1, options)
}

; =====================================================================================
; SECTION 4: CUSTOM MENU SYSTEM WITH SPEED KEY NAVIGATION
; =====================================================================================
; This replaces the native Windows menu with a custom GUI that supports:
; - Arrow key navigation
; - Speed keys (j, k, f, g, h, s, m, i)
; - Visual highlighting of selected items

ShowCustomMenu(*) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Display the custom navigable menu GUI
    ;
    ; WHY A CUSTOM MENU?
    ; Native Windows menus (Menu class) don't support custom key bindings.
    ; By using a GUI with a ListView, we can intercept any keypress and
    ; implement our own navigation logic.
    ; ---------------------------------------------------------------------------------
    global customMenuGui, menuIsVisible, currentMenuItems, currentMenuIndex
    global menuStack, menuListView, callingWindowTitle, CustomMenuPath
    
    ; Store the currently active window so we can return to it
    callingWindowTitle := WinGetTitle("A")
    
    ; If menu is already visible, close it (toggle behavior)
    if (menuIsVisible && IsObject(customMenuGui)) {
        CloseCustomMenu()
        return
    }
    
    ; Reset the menu stack (navigation history)
    menuStack := []
    
    ; Build the main menu items from the folder structure
    currentMenuItems := BuildMenuItems(CustomMenuPath)
    currentMenuIndex := 1
    
    ; Create and show the menu GUI
    CreateMenuGui("GlobalCoder Menu")
}

BuildMenuItems(path, isSubmenu := false) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Scan a folder and build an array of menu items
    ;
    ; PARAMETERS:
    ; path      - The folder path to scan
    ; isSubmenu - Whether this is a submenu (affects whether we add "Back" item)
    ;
    ; RETURNS: Array of Maps, each containing:
    ;   name     - Display name
    ;   path     - Full path to file/folder
    ;   type     - "folder", "file", "action", or "back"
    ;   icon     - Emoji icon for visual identification
    ; ---------------------------------------------------------------------------------
    items := []
    
    ; Add "Back" option for submenus
    if (isSubmenu) {
        items.Push(Map(
            "name", "⬅️ Back",
            "path", "",
            "type", "back",
            "icon", "⬅️"
        ))
    }
    
    ; Add standard menu items at the top
    if (!isSubmenu) {
        items.Push(Map("name", "📝 Add Class Note", "path", "action:AddClassNote", "type", "action", "icon", "📝"))
        items.Push(Map("name", "📚 Show Classes", "path", "action:ShowClasses", "type", "action", "icon", "📚"))
        items.Push(Map("name", "🔍 Google Search", "path", "action:GoogleSearch", "type", "action", "icon", "🔍"))
        items.Push(Map("name", "📂 Find in Files", "path", "action:FindInFiles", "type", "action", "icon", "📂"))
        items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
        items.Push(Map("name", "🚀 Project Management", "path", "submenu:ProjectManagement", "type", "submenu", "icon", "🚀"))
        items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
    }
    
    ; Scan the folder for files and subfolders
    try {
        Loop Files, path "\*", "DF" {
            itemIcon := ""
            itemType := ""
            
            if (A_LoopFileAttrib ~= "D") {
                ; It's a directory/folder
                itemType := "folder"
                itemIcon := "📁"
            } else {
                ; It's a file - determine icon by extension
                itemType := "file"
                SplitPath(A_LoopFilePath, , , &ext)
                
                ; Assign icons based on file extension
                switch StrLower(ext) {
                    case "txt": itemIcon := "📄"
                    case "ahk": itemIcon := "🔧"
                    case "py":  itemIcon := "🐍"
                    case "js":  itemIcon := "📜"
                    case "json": itemIcon := "📋"
                    case "md":  itemIcon := "📝"
                    case "html", "htm": itemIcon := "🌐"
                    case "css": itemIcon := "🎨"
                    case "exe": itemIcon := "⚡"
                    case "steps": itemIcon := "📋"
                    default: itemIcon := "📄"
                }
            }
            
            items.Push(Map(
                "name", itemIcon . " " . A_LoopFileName,
                "path", A_LoopFilePath,
                "type", itemType,
                "icon", itemIcon
            ))
        }
    }
    
    ; Add special menu sections at the bottom
    if (!isSubmenu) {
        items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
        items.Push(Map("name", "📁 Actions", "path", "submenu:Actions", "type", "submenu", "icon", "📁"))
        items.Push(Map("name", "⚙️ Admin", "path", "submenu:Admin", "type", "submenu", "icon", "⚙️"))
        items.Push(Map("name", "🪟 Calling Window: " . SubStr(callingWindowTitle, 1, 25), "path", "action:FocusCallingWindow", "type", "action", "icon", "🪟"))
    }
    
    return items
}

BuildSpecialSubmenu(submenuName) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Build items for special submenus (Admin, Actions, ProjectManagement)
    ;
    ; PARAMETER:
    ; submenuName - Which special submenu to build ("Admin", "Actions", etc.)
    ;
    ; RETURNS: Array of menu item Maps
    ; ---------------------------------------------------------------------------------
    items := []
    
    ; Always add back button for submenus
    items.Push(Map("name", "⬅️ Back", "path", "", "type", "back", "icon", "⬅️"))
    
    switch submenuName {
        case "Admin":
            items.Push(Map("name", "⚙️ Settings", "path", "action:ShowSettingsGUI", "type", "action", "icon", "⚙️"))
            items.Push(Map("name", "➕ Add Action Item", "path", "action:ShowAddActionGUI", "type", "action", "icon", "➕"))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "🔄 Reload Menu", "path", "action:RebuildMenu", "type", "action", "icon", "🔄"))
            items.Push(Map("name", "🔃 Reload Script", "path", "action:Reload", "type", "action", "icon", "🔃"))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "📂 Open Script Folder", "path", "action:OpenScriptFolder", "type", "action", "icon", "📂"))
            items.Push(Map("name", "📂 Open Menu Folder", "path", "action:OpenMenuFolder", "type", "action", "icon", "📂"))
            items.Push(Map("name", "📜 View Query Log", "path", "action:ShowQueryLog", "type", "action", "icon", "📜"))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "❌ Exit", "path", "action:ExitApp", "type", "action", "icon", "❌"))
            
        case "Actions":
            items.Push(Map("name", "📋 Dump Clipboard", "path", "action:Action_DumpClipboard", "type", "action", "icon", "📋"))
            items.Push(Map("name", "📁 New Folder", "path", "action:Action_NewFolder", "type", "action", "icon", "📁"))
            items.Push(Map("name", "📄 New File", "path", "action:Action_NewFile", "type", "action", "icon", "📄"))
            items.Push(Map("name", "📂 Open in Explorer", "path", "action:Action_OpenFolder", "type", "action", "icon", "📂"))
            items.Push(Map("name", "🌳 Capture Structure", "path", "action:Action_CaptureStructure", "type", "action", "icon", "🌳"))
            
        case "ProjectManagement":
            items.Push(Map("name", "🆕 Create New Project", "path", "action:ShowNewProjectWizard", "type", "action", "icon", "🆕"))
            items.Push(Map("name", "📋 Recent Projects", "path", "action:ShowRecentProjects", "type", "action", "icon", "📋"))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "📚 Learning Center", "path", "action:ShowLearningCenter", "type", "action", "icon", "📚"))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "⚙️ Project Settings", "path", "action:ShowProjectSettings", "type", "action", "icon", "⚙️"))
            
        case "Snips":
            ; Build menu from snips folder
            global SnipsPath
            if (DirExist(SnipsPath)) {
                try {
                    Loop Files, SnipsPath "\*", "DF" {
                        itemIcon := (A_LoopFileAttrib ~= "D") ? "📁" : "📄"
                        items.Push(Map(
                            "name", itemIcon . " " . A_LoopFileName,
                            "path", A_LoopFilePath,
                            "type", (A_LoopFileAttrib ~= "D") ? "folder" : "file",
                            "icon", itemIcon
                        ))
                    }
                }
            }
            if (items.Length = 1) {  ; Only has "Back" button
                items.Push(Map("name", "(No snips found)", "path", "", "type", "info", "icon", "ℹ️"))
            }
            
        case "Messages":
            ; Build menu from messages folder
            global SnipsPath
            messagesPath := SnipsPath "\messages"
            if (DirExist(messagesPath)) {
                try {
                    Loop Files, messagesPath "\*", "F" {
                        items.Push(Map(
                            "name", "💬 " . A_LoopFileName,
                            "path", A_LoopFilePath,
                            "type", "file",
                            "icon", "💬"
                        ))
                    }
                }
            }
            if (items.Length = 1) {
                items.Push(Map("name", "(No messages found)", "path", "", "type", "info", "icon", "ℹ️"))
            }
            
        case "Instructions":
            ; Show a help/instructions submenu
            items.Push(Map("name", "📖 Speed Key Navigation", "path", "", "type", "info", "icon", "📖"))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "j / ↓ = Move down", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "k / ↑ = Move up", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "h / Enter = Select", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "f / Backspace = Go back", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "g = Jump to Admin", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "s = Jump to Snips", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "m = Jump to Messages", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "i = This help screen", "path", "", "type", "info", "icon", ""))
            items.Push(Map("name", "───────────────", "path", "", "type", "separator", "icon", ""))
            items.Push(Map("name", "Esc = Close menu", "path", "", "type", "info", "icon", ""))
    }
    
    return items
}

CreateMenuGui(title) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Create and display the custom menu GUI
    ;
    ; GUI STRUCTURE:
    ; - Title bar showing current menu location
    ; - ListView showing menu items (supports keyboard selection)
    ; - Status bar showing speed key hints
    ;
    ; The GUI is set to +AlwaysOnTop so it stays visible above other windows.
    ; ---------------------------------------------------------------------------------
    global customMenuGui, menuIsVisible, currentMenuItems, currentMenuIndex, menuListView
    
    ; Destroy any existing menu GUI first
    if (IsObject(customMenuGui)) {
        try {
            customMenuGui.Destroy()
        }
    }
    
    ; Create new GUI with dark theme
    ; +AlwaysOnTop keeps it above other windows
    ; -Caption removes the title bar (we'll make our own)
    ; +ToolWindow prevents it from appearing in taskbar
    customMenuGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "GlobalMenu")
    customMenuGui.BackColor := "1E1E1E"
    
    ; --- Custom title bar ---
    titleText := customMenuGui.Add("Text", "x0 y0 w400 h30 +0x200 Background2D2D30 c00AAFF Center", "  " . title)
    titleText.SetFont("s11 bold")
    
    ; --- Speed key hint bar ---
    hintText := "j↓ k↑ h=select f=back | g=admin s=snips m=msgs i=help | Esc=close"
    customMenuGui.Add("Text", "x0 y30 w400 h20 Background252526 c888888 Center", hintText)
    
    ; --- Menu ListView ---
    ; The ListView control displays our menu items and handles keyboard navigation
    ; -Hdr hides the column header
    ; +AltSubmit sends notifications for all events (not just double-click)
    ; +Grid adds gridlines between items
    menuListView := customMenuGui.Add("ListView", 
        "x5 y55 w390 h350 -Hdr +Grid Background252526 cD4D4D4 vMenuList", 
        ["Item"])
    
    ; Populate the ListView with menu items
    PopulateMenuListView()
    
    ; Set up event handlers
    ; DoubleClick triggers item selection
    menuListView.OnEvent("DoubleClick", (ctrl, row) => SelectMenuItem(row))
    
    ; --- Bottom status bar ---
    customMenuGui.Add("Text", "x0 y410 w400 h25 Background2D2D30 c666666 Center", 
        "Items: " . currentMenuItems.Length . " | Use arrow keys or speed keys")
    
    ; --- Position the GUI ---
    ; Center it on the primary monitor
    MonitorGet(MonitorGetPrimary(), &left, &top, &right, &bottom)
    posX := (right - left - 400) // 2
    posY := (bottom - top - 440) // 2
    
    ; Show the GUI
    customMenuGui.Show("x" . posX . " y" . posY . " w400 h435 NoActivate")
    menuIsVisible := true
    
    ; Activate the GUI and set focus to the ListView
    WinActivate("ahk_id " . customMenuGui.Hwnd)
    menuListView.Focus()
    
    ; Select the first item
    if (currentMenuItems.Length > 0) {
        menuListView.Modify(1, "+Select +Focus")
        currentMenuIndex := 1
    }
    
    ; Register keyboard handlers for this window
    RegisterMenuHotkeys()
}

PopulateMenuListView() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Fill the ListView with the current menu items
    ; 
    ; This clears the existing items and adds all items from currentMenuItems array.
    ; Separator items are displayed but not selectable.
    ; ---------------------------------------------------------------------------------
    global menuListView, currentMenuItems
    
    menuListView.Delete()  ; Clear existing items
    
    for index, item in currentMenuItems {
        menuListView.Add(, item["name"])
    }
    
    ; Auto-size the column to fit content
    menuListView.ModifyCol(1, "AutoHdr")
}

RegisterMenuHotkeys() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Set up keyboard bindings for menu navigation
    ;
    ; SPEED KEYS:
    ; j = down, k = up, h = select, f = back
    ; g = admin, s = snips, m = messages, i = instructions
    ;
    ; STANDARD KEYS:
    ; Up/Down arrows, Enter, Escape, Backspace
    ;
    ; HotIfWinExist conditionally enables hotkeys only when our menu is visible
    ; ---------------------------------------------------------------------------------
    global customMenuGui
    
    ; Only enable these hotkeys when our menu window exists
    HotIfWinExist("ahk_id " . customMenuGui.Hwnd)
    
    ; --- Arrow key navigation ---
    Hotkey("Up", (*) => MenuMoveUp(), "On")
    Hotkey("Down", (*) => MenuMoveDown(), "On")
    Hotkey("Enter", (*) => MenuSelect(), "On")
    Hotkey("Escape", (*) => CloseCustomMenu(), "On")
    Hotkey("Backspace", (*) => MenuGoBack(), "On")
    
    ; --- Speed keys ---
    Hotkey("j", (*) => MenuMoveDown(), "On")      ; j = down (vim-style)
    Hotkey("k", (*) => MenuMoveUp(), "On")        ; k = up (vim-style)
    Hotkey("h", (*) => MenuSelect(), "On")        ; h = select (enter)
    Hotkey("f", (*) => MenuGoBack(), "On")        ; f = go back/up tree
    Hotkey("g", (*) => JumpToSubmenu("Admin"), "On")        ; g = admin menu
    Hotkey("s", (*) => JumpToSubmenu("Snips"), "On")        ; s = snips section
    Hotkey("m", (*) => JumpToSubmenu("Messages"), "On")     ; m = messages section
    Hotkey("i", (*) => JumpToSubmenu("Instructions"), "On") ; i = instructions/help
}

UnregisterMenuHotkeys() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Disable the menu-specific hotkeys when menu closes
    ; ---------------------------------------------------------------------------------
    global customMenuGui
    
    try {
        HotIfWinExist("ahk_id " . customMenuGui.Hwnd)
        Hotkey("Up", "Off")
        Hotkey("Down", "Off")
        Hotkey("Enter", "Off")
        Hotkey("Escape", "Off")
        Hotkey("Backspace", "Off")
        Hotkey("j", "Off")
        Hotkey("k", "Off")
        Hotkey("h", "Off")
        Hotkey("f", "Off")
        Hotkey("g", "Off")
        Hotkey("s", "Off")
        Hotkey("m", "Off")
        Hotkey("i", "Off")
    }
}

MenuMoveUp() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Move selection up in the menu
    ; Skips over separator items (they're not selectable)
    ; ---------------------------------------------------------------------------------
    global menuListView, currentMenuItems, currentMenuIndex
    
    if (currentMenuIndex <= 1) {
        return  ; Already at top
    }
    
    ; Find the next valid (non-separator) item above current position
    newIndex := currentMenuIndex - 1
    while (newIndex >= 1) {
        item := currentMenuItems[newIndex]
        if (item["type"] != "separator") {
            break
        }
        newIndex--
    }
    
    if (newIndex >= 1) {
        currentMenuIndex := newIndex
        menuListView.Modify(0, "-Select -Focus")  ; Deselect all
        menuListView.Modify(currentMenuIndex, "+Select +Focus")
    }
}

MenuMoveDown() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Move selection down in the menu
    ; Skips over separator items
    ; ---------------------------------------------------------------------------------
    global menuListView, currentMenuItems, currentMenuIndex
    
    if (currentMenuIndex >= currentMenuItems.Length) {
        return  ; Already at bottom
    }
    
    ; Find the next valid item below current position
    newIndex := currentMenuIndex + 1
    while (newIndex <= currentMenuItems.Length) {
        item := currentMenuItems[newIndex]
        if (item["type"] != "separator") {
            break
        }
        newIndex++
    }
    
    if (newIndex <= currentMenuItems.Length) {
        currentMenuIndex := newIndex
        menuListView.Modify(0, "-Select -Focus")
        menuListView.Modify(currentMenuIndex, "+Select +Focus")
    }
}

MenuSelect() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Activate the currently selected menu item
    ; Calls SelectMenuItem with the current index
    ; ---------------------------------------------------------------------------------
    global currentMenuIndex
    SelectMenuItem(currentMenuIndex)
}

SelectMenuItem(rowIndex) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Handle selection of a menu item
    ;
    ; BEHAVIOR BY ITEM TYPE:
    ; - folder: Push current menu to stack, show folder contents
    ; - submenu: Push current menu to stack, show special submenu
    ; - file: Close menu and handle the file
    ; - action: Close menu and execute the action
    ; - back: Pop from menu stack, show previous menu
    ; - separator/info: Do nothing (not selectable)
    ; ---------------------------------------------------------------------------------
    global currentMenuItems, menuStack, currentMenuIndex, CustomMenuPath
    
    if (rowIndex < 1 || rowIndex > currentMenuItems.Length) {
        return
    }
    
    item := currentMenuItems[rowIndex]
    itemType := item["type"]
    itemPath := item["path"]
    
    switch itemType {
        case "separator", "info":
            ; These items are informational only, not selectable
            return
            
        case "back":
            MenuGoBack()
            return
            
        case "folder":
            ; Navigate into the folder
            ; Save current menu state to stack for "back" navigation
            menuStack.Push(Map(
                "items", currentMenuItems,
                "index", currentMenuIndex,
                "title", "Previous Menu"
            ))
            
            ; Build new menu from folder contents
            SplitPath(itemPath, &folderName)
            currentMenuItems := BuildMenuItems(itemPath, true)
            currentMenuIndex := 1
            
            ; Refresh the display
            RefreshMenuDisplay("📁 " . folderName)
            return
            
        case "submenu":
            ; Handle special submenus (Admin, Actions, ProjectManagement)
            submenuName := StrReplace(itemPath, "submenu:", "")
            
            ; Save current menu state
            menuStack.Push(Map(
                "items", currentMenuItems,
                "index", currentMenuIndex,
                "title", "Main Menu"
            ))
            
            ; Build the special submenu
            currentMenuItems := BuildSpecialSubmenu(submenuName)
            currentMenuIndex := 1
            
            RefreshMenuDisplay(item["icon"] . " " . submenuName)
            return
            
        case "file":
            ; Close menu and handle the file
            CloseCustomMenu()
            MenuEventHandler(itemPath)
            return
            
        case "action":
            ; Close menu and execute the action
            CloseCustomMenu()
            actionName := StrReplace(itemPath, "action:", "")
            ExecuteMenuAction(actionName)
            return
    }
}

MenuGoBack() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Navigate back to the previous menu level
    ; Pops the last menu state from the stack and restores it
    ; ---------------------------------------------------------------------------------
    global menuStack, currentMenuItems, currentMenuIndex
    
    if (menuStack.Length = 0) {
        ; No previous menu, close the entire menu system
        CloseCustomMenu()
        return
    }
    
    ; Pop the previous menu state
    previousState := menuStack.Pop()
    currentMenuItems := previousState["items"]
    currentMenuIndex := previousState["index"]
    
    RefreshMenuDisplay("GlobalCoder Menu")
}

JumpToSubmenu(submenuName) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Directly jump to a specific submenu (for speed keys g, s, m, i)
    ;
    ; PARAMETER:
    ; submenuName - Which submenu to jump to ("Admin", "Snips", "Messages", "Instructions")
    ; ---------------------------------------------------------------------------------
    global menuStack, currentMenuItems, currentMenuIndex
    
    ; Save current menu state (allow going back)
    menuStack.Push(Map(
        "items", currentMenuItems,
        "index", currentMenuIndex,
        "title", "Previous Menu"
    ))
    
    ; Build and display the target submenu
    currentMenuItems := BuildSpecialSubmenu(submenuName)
    currentMenuIndex := 1
    
    ; Determine icon for the submenu
    iconMap := Map(
        "Admin", "⚙️",
        "Snips", "✂️",
        "Messages", "💬",
        "Instructions", "📖"
    )
    icon := iconMap.Has(submenuName) ? iconMap[submenuName] : "📁"
    
    RefreshMenuDisplay(icon . " " . submenuName)
}

RefreshMenuDisplay(title) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Update the menu GUI with new content
    ; Called when navigating between menu levels
    ; ---------------------------------------------------------------------------------
    global customMenuGui, menuListView, currentMenuItems, currentMenuIndex
    
    ; Repopulate the ListView
    PopulateMenuListView()
    
    ; Select the appropriate item
    if (currentMenuItems.Length > 0) {
        ; Make sure index is valid
        if (currentMenuIndex > currentMenuItems.Length) {
            currentMenuIndex := 1
        }
        
        ; Skip separator if it's the current index
        while (currentMenuIndex <= currentMenuItems.Length && 
               currentMenuItems[currentMenuIndex]["type"] = "separator") {
            currentMenuIndex++
        }
        if (currentMenuIndex > currentMenuItems.Length) {
            currentMenuIndex := 1
        }
        
        menuListView.Modify(0, "-Select -Focus")
        menuListView.Modify(currentMenuIndex, "+Select +Focus")
    }
}

ExecuteMenuAction(actionName) {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Execute a menu action by name
    ; Maps action names to actual function calls
    ; ---------------------------------------------------------------------------------
    global CustomMenuPath, A_ScriptDir
    
    switch actionName {
        case "AddClassNote":
            AddClassNote()
        case "ShowClasses":
            ShowClasses()
        case "GoogleSearch":
            GoogleSearch()
        case "FindInFiles":
            FindInFiles()
        case "ShowSettingsGUI":
            ShowSettingsGUI()
        case "ShowAddActionGUI":
            ShowAddActionGUI()
        case "RebuildMenu":
            RebuildMenu()
        case "Reload":
            Reload()
        case "OpenScriptFolder":
            Run("explorer.exe " . A_ScriptDir)
        case "OpenMenuFolder":
            Run("explorer.exe " . CustomMenuPath)
        case "ShowQueryLog":
            ShowQueryLog()
        case "ExitApp":
            ExitApp()
        case "ShowNewProjectWizard":
            ShowNewProjectWizard()
        case "ShowRecentProjects":
            ShowRecentProjects()
        case "ShowLearningCenter":
            ShowLearningCenter()
        case "ShowProjectSettings":
            ShowProjectSettings()
        case "FocusCallingWindow":
            FocusCallingWindow()
        case "Action_DumpClipboard":
            Action_DumpClipboard(CustomMenuPath)
        case "Action_NewFolder":
            Action_NewFolder(CustomMenuPath)
        case "Action_NewFile":
            Action_NewFile(CustomMenuPath)
        case "Action_OpenFolder":
            Action_OpenFolder(CustomMenuPath)
        case "Action_CaptureStructure":
            Action_CaptureStructure(CustomMenuPath)
        default:
            GUT_Display("Unknown Action", "Action not implemented: " . actionName, 3000)
    }
}

CloseCustomMenu() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Close the custom menu GUI and clean up
    ; ---------------------------------------------------------------------------------
    global customMenuGui, menuIsVisible
    
    ; Disable the menu hotkeys
    UnregisterMenuHotkeys()
    
    ; Destroy the GUI
    if (IsObject(customMenuGui)) {
        try {
            customMenuGui.Destroy()
        }
    }
    
    menuIsVisible := false
    customMenuGui := ""
}

; =====================================================================================
; SECTION 5: INITIALIZATION FUNCTIONS
; =====================================================================================

InitializeSettings() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Load settings from INI file, or create defaults if file doesn't exist
    ;
    ; INI FILE STRUCTURE:
    ; INI files are simple text files with [Section] headers and Key=Value pairs.
    ; IniRead(file, section, key, default) reads a value
    ; IniWrite(value, file, section, key) writes a value
    ; ---------------------------------------------------------------------------------
    global SettingsFile, GUT_DefaultTimeout, GUT_DefaultTransparency
    global GUT_DefaultWidth, GUT_DefaultHeight, CustomMenuPath
    global DefaultProjectRoot, VSCodePath, SublimePath, GitBashPath
    
    ; Create the main folder if it doesn't exist
    if (!DirExist(CustomMenuPath)) {
        DirCreate(CustomMenuPath)
    }
    
    ; If settings file doesn't exist, create it with defaults
    if (!FileExist(SettingsFile)) {
        ; Write GUT Display settings
        IniWrite(5000, SettingsFile, "GUT_Display", "Timeout")
        IniWrite(180, SettingsFile, "GUT_Display", "Transparency")
        IniWrite(500, SettingsFile, "GUT_Display", "DefaultWidth")
        IniWrite(300, SettingsFile, "GUT_Display", "DefaultHeight")
        IniWrite("TopRight", SettingsFile, "GUT_Display", "Position")
        
        ; Write General settings
        IniWrite(1, SettingsFile, "General", "ShowTooltips")
        IniWrite(2000, SettingsFile, "General", "TooltipDuration")
        IniWrite(1, SettingsFile, "General", "LogUsage")
        
        ; Write Project settings
        IniWrite("D:\code", SettingsFile, "Projects", "DefaultRoot")
        IniWrite("code", SettingsFile, "Projects", "VSCodePath")
        IniWrite("C:\Program Files\Sublime Text\sublime_text.exe", SettingsFile, "Projects", "SublimePath")
        IniWrite("C:\Program Files\Git\git-bash.exe", SettingsFile, "Projects", "GitBashPath")
    }
    
    ; Load settings into global variables
    ; Integer() converts string to number, IniRead returns strings
    GUT_DefaultTimeout := Integer(IniRead(SettingsFile, "GUT_Display", "Timeout", 5000))
    GUT_DefaultTransparency := Integer(IniRead(SettingsFile, "GUT_Display", "Transparency", 180))
    GUT_DefaultWidth := Integer(IniRead(SettingsFile, "GUT_Display", "DefaultWidth", 500))
    GUT_DefaultHeight := Integer(IniRead(SettingsFile, "GUT_Display", "DefaultHeight", 300))
    
    DefaultProjectRoot := IniRead(SettingsFile, "Projects", "DefaultRoot", "D:\code")
    VSCodePath := IniRead(SettingsFile, "Projects", "VSCodePath", "code")
    SublimePath := IniRead(SettingsFile, "Projects", "SublimePath", "C:\Program Files\Sublime Text\sublime_text.exe")
    GitBashPath := IniRead(SettingsFile, "Projects", "GitBashPath", "C:\Program Files\Git\git-bash.exe")
}

InitializeFolderStructure() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Create all required directories for the application
    ;
    ; DIRECTORY STRUCTURE:
    ; CustomMenuFiles/
    ; ├── logs/           - Log files
    ; ├── notes/          - Note files
    ; │   └── classes/    - C# class templates
    ; ├── 0_snips/        - Code snippets
    ; │   └── messages/   - Message templates
    ; ├── 1_projects/     - Project files
    ; ├── templates/      - Project templates
    ; │   └── .vscode/    - VS Code configuration
    ; └── step_definitions/ - Tutorial step files
    ;     └── typescript/
    ; ---------------------------------------------------------------------------------
    global CustomMenuPath, LogsPath, NotesPath, ClassesPath, SnipsPath
    global ProjectsPath, TemplatesPath, StepFilesPath
    
    ; Array of all directories that need to exist
    requiredDirs := [
        CustomMenuPath,
        LogsPath,
        NotesPath,
        ClassesPath,
        SnipsPath,
        SnipsPath "\messages",
        ProjectsPath,
        TemplatesPath,
        TemplatesPath "\.vscode",
        StepFilesPath,
        StepFilesPath "\typescript",
        StepFilesPath "\javascript",
        StepFilesPath "\python",
        StepFilesPath "\csharp"
    ]
    
    ; Loop through and create each directory if it doesn't exist
    for index, dirPath in requiredDirs {
        if (!DirExist(dirPath)) {
            DirCreate(dirPath)
        }
    }
    
    ; Create step definition files if they don't exist
    CreateStepDefinitionFiles()
    
    ; Create VSCode templates
    CreateVSCodeTemplates()
    
    ; Initialize actions file (FIXED - was commented out before)
    InitializeActionsFile()
}

InitializeActionsFile() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Create the actions.ini file with default action definitions
    ;
    ; FIX: This function was previously inside a comment block, causing warnings:
    ;   "Warning: This line will never execute, due to Return preceding it"
    ;   "Warning: This local variable appears to never be assigned a value"
    ;
    ; The function is now properly defined outside of any comment blocks.
    ; ---------------------------------------------------------------------------------
    global ActionsFile
    
    ; Only create if file doesn't exist (don't overwrite user customizations)
    if (!FileExist(ActionsFile)) {
        actionsContent := "
(
[Actions]
Dump Clipboard=Action_DumpClipboard
New Folder=Action_NewFolder
New File=Action_NewFile
Open in Explorer=Action_OpenFolder
Capture Structure=Action_CaptureStructure

[ActionDescriptions]
Dump Clipboard=Append clipboard contents with timestamp to a dump file
New Folder=Create a new subfolder in this location
New File=Create a new file, optionally with clipboard content
Open in Explorer=Open this folder in Windows Explorer
Capture Structure=Generate a text representation of the folder tree
)"
        FileAppend(actionsContent, ActionsFile)
    }
}

CreateStepDefinitionFiles() {
    ; ---------------------------------------------------------------------------------
    ; Purpose: Create the step definition files for each language
    ; These are external files that can be edited to add more project types
    ; ---------------------------------------------------------------------------------
    global StepFilesPath
    
    ; JavaScript steps
    jsStepsFile := StepFilesPath "\javascript\projects.steps"
    if (!FileExist(jsStepsFile)) {
        CreateJavaScriptStepsFile(jsStepsFile)
    }
    
    ; Python steps
    pyStepsFile := StepFilesPath "\python\projects.steps"
    if (!FileExist(pyStepsFile)) {
        CreatePythonStepsFile(pyStepsFile)
    }
    
    ; C# steps
    csStepsFile := StepFilesPath "\csharp\projects.steps"
    if (!FileExist(csStepsFile)) {
        CreateCSharpStepsFile(csStepsFile)
    }
    
    ; TypeScript steps
    tsStepsFile := StepFilesPath "\typescript\projects.steps"
    if (!FileExist(tsStepsFile)) {
        CreateTypeScriptStepsFile(tsStepsFile)
    }
}

CreateJavaScriptStepsFile(filePath) {
    content := "
(
; =====================================================================================
; JAVASCRIPT PROJECT SETUP STEPS
; =====================================================================================
; Format: step|command|directions|input_needed|explanation
; Lines starting with ; are comments
; [ProjectType] starts a new project type section
; =====================================================================================

[Vanilla JS Static Site]
1|mkdir VanillaStatic && cd VanillaStatic|Create project folder|Folder name|Creates and enters your project directory
2|New-Item index.html -ItemType File|Create HTML file (PowerShell)|None|PowerShell command to create empty file
3|New-Item main.js -ItemType File|Create JS file (PowerShell)|None|Creates your main JavaScript file
4|code .|Open in VS Code|None|Opens folder in Visual Studio Code
5|npx serve .|Start local server|None|Uses npx to run serve without installing globally

[Node + Express API]
1|mkdir NodeApi && cd NodeApi|Create project folder|Project name|Creates your API project directory
2|npm init -y|Initialize package.json|None|Creates default package.json with project metadata
3|npm install express|Install Express framework|None|Adds Express.js web framework to your project
4|New-Item index.js -ItemType File|Create entry point|None|Creates the main server file
5|code .|Open in VS Code|None|Opens folder to add server code

[React with Vite]
1|npm create vite@latest my-react-app -- --template react|Create React project|App name|Vite scaffolds a complete React application
2|cd my-react-app|Enter project directory|None|Navigate into the created project folder
3|npm install|Install dependencies|None|Downloads all required packages
4|npm run dev|Start development server|None|Launches Vite dev server with hot reload
)"
    FileAppend(content, filePath)
}

CreatePythonStepsFile(filePath) {
    content := "
(
; =====================================================================================
; PYTHON PROJECT SETUP STEPS
; =====================================================================================

[Python venv (Standard)]
1|mkdir MyPythonProject && cd MyPythonProject|Create project folder|Project name|Creates your project directory
2|python -m venv venv|Create virtual environment|None|Creates isolated Python environment
3|venv\Scripts\activate|Activate environment (Windows)|None|Activates venv
4|pip install --upgrade pip|Upgrade pip|None|Ensures latest pip version
5|pip freeze > requirements.txt|Save dependencies|None|Creates requirements.txt

[Anaconda/Miniconda]
1|conda create -n myenv python=3.11|Create conda environment|Env name|Creates isolated conda environment
2|conda activate myenv|Activate environment|None|Activates the conda environment
3|conda install numpy pandas matplotlib|Install data science packages|Package names|Conda handles dependencies
)"
    FileAppend(content, filePath)
}

CreateCSharpStepsFile(filePath) {
    content := "
(
; =====================================================================================
; C# / .NET PROJECT SETUP STEPS
; =====================================================================================

[.NET Console App]
1|dotnet new console -n MyConsoleApp|Create console project|Project name|Scaffolds a C# console application
2|cd MyConsoleApp|Enter project directory|None|Navigate into the created project
3|dotnet build|Build the project|None|Compiles the application
4|dotnet run|Run the application|None|Executes the compiled application

[.NET Web API]
1|dotnet new webapi -n MyApi|Create Web API project|API name|Scaffolds ASP.NET Core Web API
2|cd MyApi|Enter project directory|None|Navigate into the created project
3|dotnet run|Start the API|None|Launches on https://localhost:5001
)"
    FileAppend(content, filePath)
}

CreateTypeScriptStepsFile(filePath) {
    content := "
(
; =====================================================================================
; TYPESCRIPT PROJECT SETUP STEPS
; =====================================================================================

[TypeScript Node Project]
1|mkdir ts-node-project && cd ts-node-project|Create project folder|Folder name|Creates your project directory
2|npm init -y|Initialize package.json|None|Creates default package.json
3|npm install typescript --save-dev|Install TypeScript|None|Adds TypeScript compiler
4|npx tsc --init|Create tsconfig.json|None|Initializes TypeScript configuration
5|mkdir src|Create source folder|None|Sets up source directory
)"
    FileAppend(content, filePath)
}

CreateVSCodeTemplates() {
    global TemplatesPath
    vscodeDir := TemplatesPath "\.vscode"
    if (!DirExist(vscodeDir)) {
        DirCreate(vscodeDir)
    }
    
    ; launch.json template
    launchJson := '
(
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": ".NET Core Launch (console)",
            "type": "coreclr",
            "request": "launch",
            "preLaunchTask": "build",
            "program": "${workspaceFolder}/bin/Debug/net8.0/${workspaceFolderBasename}.dll",
            "args": [],
            "cwd": "${workspaceFolder}",
            "console": "internalConsole"
        }
    ]
}
)'
    if (!FileExist(vscodeDir "\launch.json")) {
        FileAppend(launchJson, vscodeDir "\launch.json")
    }
    
    ; tasks.json template
    tasksJson := '
(
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build",
            "command": "dotnet",
            "type": "process",
            "args": ["build", "${workspaceFolder}"],
            "problemMatcher": "$msCompile"
        }
    ]
}
)'
    if (!FileExist(vscodeDir "\tasks.json")) {
        FileAppend(tasksJson, vscodeDir "\tasks.json")
    }
}

; =====================================================================================
; SECTION 6: STEP FILE LOADER CLASS
; =====================================================================================
; This class parses .steps files into structured data for the tutorial system

class StepFileLoader {
    static LoadFile(filePath) {
        ; ---------------------------------------------------------------------------------
        ; Purpose: Load and parse a .steps file into structured data
        ; Returns: Map where key=project type name, value=array of step Maps
        ; ---------------------------------------------------------------------------------
        projectTypes := Map()
        
        if (!FileExist(filePath)) {
            return projectTypes
        }
        
        try {
            fileContent := FileRead(filePath)
        } catch {
            return projectTypes
        }
        
        currentType := ""
        currentSteps := []
        
        for lineText in StrSplit(fileContent, "`n", "`r") {
            lineText := Trim(lineText)
            
            ; Skip empty lines and comments
            if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
                continue
            }
            
            ; Check for project type header [ProjectType]
            if (SubStr(lineText, 1, 1) = "[" && SubStr(lineText, -1) = "]") {
                ; Save previous project type if exists
                if (currentType != "" && currentSteps.Length > 0) {
                    projectTypes[currentType] := currentSteps
                }
                currentType := SubStr(lineText, 2, StrLen(lineText) - 2)
                currentSteps := []
                continue
            }
            
            ; Parse step line (pipe-delimited)
            if (InStr(lineText, "|")) {
                parts := StrSplit(lineText, "|")
                if (parts.Length >= 5) {
                    stepData := Map(
                        "step", Trim(parts[1]),
                        "command", Trim(parts[2]),
                        "directions", Trim(parts[3]),
                        "input", Trim(parts[4]),
                        "explanation", Trim(parts[5])
                    )
                    currentSteps.Push(stepData)
                }
            }
        }
        
        ; Save last project type
        if (currentType != "" && currentSteps.Length > 0) {
            projectTypes[currentType] := currentSteps
        }
        
        return projectTypes
    }
    
    static GetProjectTypeNames(filePath) {
        projectTypes := this.LoadFile(filePath)
        names := []
        for typeName, steps in projectTypes {
            names.Push(typeName)
        }
        return names
    }
    
    static GetStepsForType(filePath, typeName) {
        projectTypes := this.LoadFile(filePath)
        if (projectTypes.Has(typeName)) {
            return projectTypes[typeName]
        }
        return []
    }
}

; =====================================================================================
; SECTION 7: TRAY MENU SETUP
; =====================================================================================

SetupTrayMenu() {
    A_TrayMenu.Delete()
    A_TrayMenu.Add("&Settings", (*) => ShowSettingsGUI())
    A_TrayMenu.Add("&Add Action Item", (*) => ShowAddActionGUI())
    A_TrayMenu.Add()
    
    ; Project Management submenu
    projectSubMenu := Menu()
    projectSubMenu.Add("Create New Project", (*) => ShowNewProjectWizard())
    projectSubMenu.Add("Open Recent Projects", (*) => ShowRecentProjects())
    projectSubMenu.Add()
    projectSubMenu.Add("📚 Learning Center", (*) => ShowLearningCenter())
    projectSubMenu.Add()
    projectSubMenu.Add("Project Settings", (*) => ShowProjectSettings())
    A_TrayMenu.Add("&Project Management", projectSubMenu)
    A_TrayMenu.Add()
    
    ; Demos submenu
    demoSubMenu := Menu()
    demoSubMenu.Add("GUT-Display Demo", (*) => DemoGUTDisplay())
    demoSubMenu.Add("Step Canvas Demo", (*) => DemoStepCanvas())
    demoSubMenu.Add("Project Steps Browser", (*) => ShowProjectStepsBrowser())
    A_TrayMenu.Add("&Demos && Showcases", demoSubMenu)
    A_TrayMenu.Add()
    
    ; Hotstring/Query management
    hotstringSubMenu := Menu()
    hotstringSubMenu.Add("View Query Log", (*) => ShowQueryLog())
    hotstringSubMenu.Add("Edit Hotstrings", (*) => Run("notepad.exe " . HotstringsFile))
    hotstringSubMenu.Add("Reload Hotstrings", (*) => (LoadCustomHotstrings(), GUT_Display("Hotstrings", "Hotstrings reloaded!", 2000)))
    A_TrayMenu.Add("&Hotstrings", hotstringSubMenu)
    A_TrayMenu.Add()
    
    A_TrayMenu.Add("Open &Script Folder", (*) => Run("explorer.exe " . A_ScriptDir))
    A_TrayMenu.Add("Open &Menu Folder", (*) => Run("explorer.exe " . CustomMenuPath))
    A_TrayMenu.Add()
    
    ; Original AHK tray menu
    originalTraySubMenu := Menu()
    originalTraySubMenu.Add("&Pause Script", (*) => Pause(-1))
    originalTraySubMenu.Add("&Suspend Hotkeys", (*) => Suspend(-1))
    originalTraySubMenu.Add()
    originalTraySubMenu.Add("&Open Script in Editor", (*) => Edit())
    originalTraySubMenu.Add("&Help", (*) => Run("https://www.autohotkey.com/docs/v2/"))
    A_TrayMenu.Add("&Original AHK Menu", originalTraySubMenu)
    A_TrayMenu.Add()
    
    A_TrayMenu.Add("&Reload Script", (*) => Reload())
    A_TrayMenu.Add("E&xit", (*) => ExitApp())
    A_TrayMenu.Default := "&Settings"
    
    A_IconTip := "GlobalCoder - Type 'jjj' for menu, 'ggg' for search"
    OnMessage(0x404, TrayIconCallback)
}

TrayIconCallback(wParam, lParam, msg, hwnd) {
    if (lParam = 0x203) {  ; Double-click
        ShowMainFeaturesGUI()
        return 0
    }
}

; =====================================================================================
; SECTION 8: GUT-DISPLAY (Global Universal Transparent Display)
; =====================================================================================
; A non-focus-stealing popup window for notifications and information display

GUT_Display(title := "Information", content := "", timeout := 0, options := Map()) {
    global GUT_DefaultTimeout, GUT_DefaultTransparency, GUT_DefaultWidth, GUT_DefaultHeight
    
    actualTimeout := (timeout = 0) ? GUT_DefaultTimeout : timeout
    width := options.Has("width") ? options["width"] : GUT_DefaultWidth
    height := options.Has("height") ? options["height"] : GUT_DefaultHeight
    transparency := options.Has("transparency") ? options["transparency"] : GUT_DefaultTransparency
    position := options.Has("position") ? options["position"] : "TopRight"
    
    gutGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "GUT_" . A_TickCount)
    gutGui.Opt("+E0x08000000")  ; WS_EX_NOACTIVATE - prevents stealing focus
    gutGui.BackColor := "1E1E1E"
    
    ; Store content for copy functionality
    if (Type(content) = "Array") {
        contentStr := ""
        for idx, item in content {
            if (Type(item) = "Map") {
                contentStr .= (idx > 1 ? "`n" : "") . (item.Has("text") ? item["text"] : "")
            } else {
                contentStr .= (idx > 1 ? "`n" : "") . String(item)
            }
        }
        gutGui.originalContent := contentStr
    } else {
        gutGui.originalContent := String(content)
    }
    
    gutGui.isAlwaysOnTop := true
    
    ; Title bar
    titleText := gutGui.Add("Text", "x5 y5 w" . (width - 10) . " h20 c00AAFF", "📋 " . title)
    titleText.SetFont("s10 bold")
    gutGui.Add("Text", "x5 y28 w" . (width - 10) . " h1 Background444444")
    
    contentHeight := height - 85
    
    if (options.Has("itemized") && options["itemized"] && Type(content) = "Array") {
        DisplayItemizedContent(gutGui, content, width, contentHeight, options)
    } else if (options.Has("tree") && options["tree"]) {
        DisplayTreeContent(gutGui, content, width, contentHeight)
    } else {
        editCtrl := gutGui.Add("Edit", "x5 y32 w" . (width - 10) . " h" . contentHeight
            . " +ReadOnly -E0x200 Background252526 cD4D4D4 +VScroll", gutGui.originalContent)
        editCtrl.SetFont("s9", "Consolas")
    }
    
    ; Bottom toolbar
    toolbarY := height - 45
    gutGui.Add("Text", "x5 y" . (toolbarY - 5) . " w" . (width - 10) . " h1 Background444444")
    
    btnCopy := gutGui.Add("Button", "x10 y" . toolbarY . " w70 h30", "📋 Copy")
    btnCopy.OnEvent("Click", (*) => CopyGUTContent(gutGui))
    
    btnX := 90
    if (options.Has("actions") && Type(options["actions"]) = "Array") {
        for index, action in options["actions"] {
            if (btnX + 80 < width - 170) {
                if (Type(action) = "Map" && action.Has("text") && action.Has("callback")) {
                    btn := gutGui.Add("Button", "x" . btnX . " y" . toolbarY . " w70 h30", action["text"])
                    btn.OnEvent("Click", action["callback"])
                    btnX += 80
                }
            }
        }
    }
    
    btnPin := gutGui.Add("Button", "x" . (width - 160) . " y" . toolbarY . " w70 h30 vPinBtn", "📌 Pin")
    btnPin.OnEvent("Click", (*) => ToggleGUTAlwaysOnTop(gutGui))
    
    btnClose := gutGui.Add("Button", "x" . (width - 80) . " y" . toolbarY . " w70 h30", "✖ Close")
    btnClose.OnEvent("Click", (*) => SafeDestroyGui(gutGui))
    
    if (actualTimeout > 0) {
        timeoutSecs := Round(actualTimeout / 1000)
        gutGui.Add("Text", "x" . (width - 90) . " y" . (toolbarY - 18) . " w80 h15 c666666 Right", "Auto: " . timeoutSecs . "s")
    }
    
    ; Position calculation
    MonitorGet(MonitorGetPrimary(), &left, &top, &right, &bottom)
    switch position {
        case "TopRight":
            posX := right - width - 10
            posY := top + 10
        case "TopLeft":
            posX := left + 10
            posY := top + 10
        case "BottomRight":
            posX := right - width - 10
            posY := bottom - height - 50
        case "BottomLeft":
            posX := left + 10
            posY := bottom - height - 50
        case "Center":
            posX := (right - left - width) // 2
            posY := (bottom - top - height) // 2
        default:
            posX := right - width - 10
            posY := top + 10
    }
    
    gutGui.Show("x" . posX . " y" . posY . " w" . width . " h" . height . " NoActivate")
    WinSetTransparent(transparency, "ahk_id " . gutGui.Hwnd)
    
    if (actualTimeout > 0) {
        SetTimer((*) => SafeDestroyGui(gutGui), -actualTimeout)
    }
    
    gutGui.timeout := actualTimeout
    return gutGui
}

ToggleGUTAlwaysOnTop(guiObj) {
    try {
        if (guiObj.isAlwaysOnTop) {
            guiObj.Opt("-AlwaysOnTop")
            guiObj.isAlwaysOnTop := false
            guiObj["PinBtn"].Text := "📍 Unpin"
            ToolTip("Window unpinned")
        } else {
            guiObj.Opt("+AlwaysOnTop")
            guiObj.isAlwaysOnTop := true
            guiObj["PinBtn"].Text := "📌 Pin"
            ToolTip("Window pinned")
        }
        SetTimer((*) => ToolTip(), -1500)
    }
}

SafeDestroyGui(guiObj) {
    try {
        if (IsObject(guiObj) && guiObj.HasProp("Hwnd")) {
            hwnd := guiObj.Hwnd
            if (WinExist("ahk_id " . hwnd)) {
                guiObj.Destroy()
            }
        }
    }
}

CopyGUTContent(guiObj) {
    try {
        if (guiObj.HasProp("originalContent")) {
            A_Clipboard := guiObj.originalContent
            ToolTip("📋 Copied to clipboard!")
            SetTimer((*) => ToolTip(), -1500)
        }
    }
}

DisplayItemizedContent(guiObj, items, width, height, options) {
    lv := guiObj.Add("ListView", "x5 y32 w" . (width - 10) . " h" . height
        . " -Hdr +Grid Background252526 cD4D4D4 vItemList", ["Item", "Action"])
    guiObj.itemsData := items
    
    for index, item in items {
        if (Type(item) = "Map") {
            itemText := item.Has("text") ? item["text"] : ""
            actionText := item.Has("actionText") ? item["actionText"] : ""
            lv.Add(, itemText, actionText)
        } else {
            lv.Add(, String(item), "")
        }
    }
    
    lv.ModifyCol(1, "AutoHdr")
    lv.OnEvent("DoubleClick", (ctrl, row) => OnItemizedDoubleClick(guiObj, row))
}

OnItemizedDoubleClick(guiObj, row) {
    try {
        if (!guiObj.HasProp("itemsData")) {
            return
        }
        items := guiObj.itemsData
        if (row > 0 && row <= items.Length) {
            item := items[row]
            if (Type(item) = "Map") {
                if (item.Has("callback")) {
                    item["callback"].Call()
                } else if (item.Has("copyCommand")) {
                    A_Clipboard := item["copyCommand"]
                    ToolTip("Command copied: " . item["copyCommand"])
                    SetTimer((*) => ToolTip(), -2000)
                }
            }
        }
    }
}

DisplayTreeContent(guiObj, folderPath, width, height) {
    treeText := GenerateFolderTree(String(folderPath), "", true)
    guiObj.originalContent := treeText
    editCtrl := guiObj.Add("Edit", "x5 y32 w" . (width - 10) . " h" . height
        . " +ReadOnly -E0x200 Background252526 cD4D4D4 -Wrap +HScroll +VScroll", treeText)
    editCtrl.SetFont("s9", "Consolas")
}

GenerateFolderTree(path, indent := "", isLast := true) {
    result := ""
    SplitPath(path, &folderName)
    connector := isLast ? "└── " : "├── "
    result := indent . connector . folderName . "`n"
    childIndent := indent . (isLast ? "    " : "│   ")
    
    folders := []
    files := []
    
    try {
        Loop Files, path "\*", "DF" {
            if (A_LoopFileAttrib ~= "D") {
                folders.Push(A_LoopFilePath)
            } else {
                files.Push(A_LoopFileName)
            }
        }
    }
    
    for index, folderPath in folders {
        isLastChild := (index = folders.Length && files.Length = 0)
        result .= GenerateFolderTree(folderPath, childIndent, isLastChild)
    }
    
    for index, fileName in files {
        isLastChild := (index = files.Length)
        fileConnector := isLastChild ? "└── " : "├── "
        result .= childIndent . fileConnector . fileName . "`n"
    }
    
    return result
}

; =====================================================================================
; SECTION 9: STEP CANVAS CLASS
; =====================================================================================
; Interactive tutorial display with arrow key navigation

class StepCanvas {
    source := ""
    GuiObj := ""
    Steps := []
    CurrentStep := 1
    isAlwaysOnTop := true
    projectTypeName := ""
    stepTextControl := ""
    codeDisplay := ""
    directionsText := ""
    auxInputText := ""
    explanationText := ""
    
    __New(stepsData, projectTypeName := "Project Steps") {
        global activeStepCanvas
        
        if (Type(stepsData) = "String") {
            this.source := stepsData
            if (!this.LoadStepsFromFile(stepsData)) {
                MsgBox("Error: Could not load steps from " . stepsData, "StepCanvas Error", 16)
                return
            }
        } else if (Type(stepsData) = "Array") {
            this.Steps := stepsData
            this.source := "Provided Data"
        } else {
            MsgBox("Error: Invalid steps data type", "StepCanvas Error", 16)
            return
        }
        
        this.projectTypeName := projectTypeName
        
        if (this.Steps.Length = 0) {
            MsgBox("Error: No valid steps found", "StepCanvas Error", 16)
            return
        }
        
        this.GuiObj := Gui("+AlwaysOnTop +Resize", "📚 " . projectTypeName)
        this.GuiObj.OnEvent("Close", (*) => this.OnClose())
        this.GuiObj.BackColor := "1E1E1E"
        
        ; Step indicator
        this.stepTextControl := this.GuiObj.Add("Text", "x10 y10 w480 h25 c00AAFF", "Step 1 of " . this.Steps.Length)
        this.stepTextControl.SetFont("s12 bold")
        
        this.GuiObj.Add("Text", "x10 y35 w480 h15 c666666", "Use ← → arrow keys or buttons to navigate • Esc to close")
        
        ; Code display
        this.GuiObj.Add("Text", "x10 y55 w80 h20 c888888", "Command:")
        this.codeDisplay := this.GuiObj.Add("Edit", "x10 y75 w480 h80 +ReadOnly Background252526 c00FF00 -Wrap +HScroll", "")
        this.codeDisplay.SetFont("s11", "Consolas")
        
        btnCopyCmd := this.GuiObj.Add("Button", "x395 y160 w95 h25", "📋 Copy Cmd")
        btnCopyCmd.OnEvent("Click", (*) => this.CopyCurrentCommand())
        
        ; Info section
        this.GuiObj.Add("Text", "x10 y165 w80 h20 c888888", "Directions:")
        this.directionsText := this.GuiObj.Add("Text", "x90 y165 w300 h20 cD4D4D4", "")
        
        this.GuiObj.Add("Text", "x10 y190 w80 h20 c888888", "Input:")
        this.auxInputText := this.GuiObj.Add("Text", "x90 y190 w400 h20 cFFAA00", "")
        
        this.GuiObj.Add("Text", "x10 y215 w80 h20 c888888", "Explanation:")
        this.explanationText := this.GuiObj.Add("Edit", "x10 y235 w480 h70 +ReadOnly Background252526 cD4D4D4", "")
        this.explanationText.SetFont("s9")
        
        ; Bottom toolbar
        this.GuiObj.Add("Text", "x5 y310 w490 h1 Background444444")
        this.GuiObj.Add("Button", "x10 y320 w90 h30", "◀ Previous").OnEvent("Click", (*) => this.PrevStep())
        this.GuiObj.Add("Button", "x110 y320 w90 h30", "Next ▶").OnEvent("Click", (*) => this.NextStep())
        
        stepList := []
        for idx, step in this.Steps {
            stepList.Push("Step " . idx)
        }
        this.GuiObj.Add("Text", "x210 y325 w40 h20 cD4D4D4", "Jump:")
        this.GuiObj.Add("DropDownList", "x250 y320 w80 vStepJump Choose1", stepList).OnEvent("Change", (ctrl, *) => this.JumpToStep(ctrl))
        
        pinBtn := this.GuiObj.Add("Button", "x340 y320 w70 h30 vPinBtn", "📌 Pin")
        pinBtn.OnEvent("Click", (*) => this.ToggleAlwaysOnTop())
        
        this.GuiObj.Add("Button", "x420 y320 w70 h30", "✖ Close").OnEvent("Click", (*) => this.OnClose())
        
        this.UpdateGui()
        this.GuiObj.Show("w500 h360")
        
        activeStepCanvas := this
        this.SetupHotkeys()
    }
    
    SetupHotkeys() {
        HotIfWinExist("ahk_id " . this.GuiObj.Hwnd)
        Hotkey("Left", (*) => this.PrevStep(), "On")
        Hotkey("Right", (*) => this.NextStep(), "On")
        Hotkey("Escape", (*) => this.OnClose(), "On")
    }
    
    DisableHotkeys() {
        try {
            HotIfWinExist("ahk_id " . this.GuiObj.Hwnd)
            Hotkey("Left", "Off")
            Hotkey("Right", "Off")
            Hotkey("Escape", "Off")
        }
    }
    
    OnClose() {
        global activeStepCanvas
        this.DisableHotkeys()
        activeStepCanvas := ""
        this.GuiObj.Destroy()
    }
    
    LoadStepsFromFile(textFile) {
        if (!FileExist(textFile)) {
            return false
        }
        
        try {
            fileContent := FileRead(textFile)
        } catch {
            return false
        }
        
        lines := StrSplit(fileContent, "`n", "`r")
        for index, lineText in lines {
            lineText := Trim(lineText)
            if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
                continue
            }
            
            parts := StrSplit(lineText, "|")
            if (parts.Length >= 5) {
                this.Steps.Push(Map(
                    "step", Trim(parts[1]),
                    "command", Trim(parts[2]),
                    "directions", Trim(parts[3]),
                    "input", Trim(parts[4]),
                    "explanation", Trim(parts[5])
                ))
            }
        }
        
        return (this.Steps.Length > 0)
    }
    
    PrevStep() {
        if (this.CurrentStep > 1) {
            this.CurrentStep--
            this.UpdateGui()
        }
    }
    
    NextStep() {
        if (this.CurrentStep < this.Steps.Length) {
            this.CurrentStep++
            this.UpdateGui()
        }
    }
    
    JumpToStep(ctrl) {
        this.CurrentStep := ctrl.Value
        this.UpdateGui()
    }
    
    UpdateGui() {
        if (this.CurrentStep < 1 || this.CurrentStep > this.Steps.Length) {
            return
        }
        
        step := this.Steps[this.CurrentStep]
        this.stepTextControl.Text := "Step " . this.CurrentStep . " of " . this.Steps.Length
        
        if (step.Has("command")) {
            this.codeDisplay.Value := step["command"]
        } else if (step.Has("code")) {
            this.codeDisplay.Value := step["code"]
        }
        
        this.directionsText.Text := step["directions"]
        
        if (step.Has("input")) {
            this.auxInputText.Text := step["input"]
        } else if (step.Has("auxInput")) {
            this.auxInputText.Text := step["auxInput"]
        }
        
        this.explanationText.Value := step["explanation"]
        
        try {
            this.GuiObj["StepJump"].Value := this.CurrentStep
        }
    }
    
    CopyCurrentCommand() {
        if (this.CurrentStep >= 1 && this.CurrentStep <= this.Steps.Length) {
            step := this.Steps[this.CurrentStep]
            cmd := step.Has("command") ? step["command"] : (step.Has("code") ? step["code"] : "")
            A_Clipboard := cmd
            ToolTip("Command copied to clipboard!")
            SetTimer((*) => ToolTip(), -2000)
        }
    }
    
    ToggleAlwaysOnTop() {
        if (this.isAlwaysOnTop) {
            this.GuiObj.Opt("-AlwaysOnTop")
            this.isAlwaysOnTop := false
            this.GuiObj["PinBtn"].Text := "📍 Unpin"
        } else {
            this.GuiObj.Opt("+AlwaysOnTop")
            this.isAlwaysOnTop := true
            this.GuiObj["PinBtn"].Text := "📌 Pin"
        }
    }
}

; =====================================================================================
; SECTION 10: LEARNING CENTER
; =====================================================================================

ShowLearningCenter() {
    global StepFilesPath
    
    lcGui := Gui("+AlwaysOnTop", "📚 GlobalCoder Learning Center")
    lcGui.BackColor := "1E1E1E"
    lcGui.isAlwaysOnTop := true
    
    titleText := lcGui.Add("Text", "x10 y10 w580 h30 c00AAFF Center", "🎓 Project Setup Learning Center")
    titleText.SetFont("s14 bold")
    
    lcGui.Add("Text", "x10 y45 w580 h20 c888888 Center", "Select a language, then choose a project type to view step-by-step instructions")
    
    lcGui.Add("Text", "x10 y75 w150 h20 cD4D4D4", "Select Language:")
    languages := ["JavaScript", "Python", "C# / .NET", "TypeScript"]
    langDropdown := lcGui.Add("DropDownList", "x10 y95 w200 vLanguage Choose1", languages)
    langDropdown.OnEvent("Change", (ctrl, *) => UpdateProjectTypes(lcGui, ctrl.Text))
    
    lcGui.Add("Text", "x10 y130 w150 h20 cD4D4D4", "Select Project Type:")
    projectDropdown := lcGui.Add("DropDownList", "x10 y150 w350 vProjectType", [])
    
    lcGui.Add("Text", "x10 y185 w150 h20 cD4D4D4", "Description:")
    descEdit := lcGui.Add("Edit", "x10 y205 w580 h100 +ReadOnly Background252526 cD4D4D4 vDescription", "Select a project type to see its description and steps.")
    
    lcGui.Add("Text", "x5 y315 w590 h1 Background444444")
    
    btnLaunch := lcGui.Add("Button", "x10 y325 w120 h35 Default", "🚀 Launch Tutorial")
    btnLaunch.OnEvent("Click", (*) => LaunchTutorial(lcGui))
    
    btnBrowseFiles := lcGui.Add("Button", "x140 y325 w120 h35", "📂 Edit Steps")
    btnBrowseFiles.OnEvent("Click", (*) => Run("explorer.exe " . StepFilesPath))
    
    btnReload := lcGui.Add("Button", "x270 y325 w100 h35", "🔄 Reload")
    btnReload.OnEvent("Click", (*) => (lcGui.Destroy(), ShowLearningCenter()))
    
    btnPin := lcGui.Add("Button", "x510 y325 w80 h35 vPinBtn", "📌 Pin")
    btnPin.OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(lcGui))
    
    UpdateProjectTypes(lcGui, "JavaScript")
    lcGui.Show("w600 h370")
}

UpdateProjectTypes(guiObj, language) {
    global StepFilesPath
    
    langMap := Map(
        "JavaScript", StepFilesPath "\javascript\projects.steps",
        "Python", StepFilesPath "\python\projects.steps",
        "C# / .NET", StepFilesPath "\csharp\projects.steps",
        "TypeScript", StepFilesPath "\typescript\projects.steps"
    )
    
    if (!langMap.Has(language)) {
        return
    }
    
    filePath := langMap[language]
    projectTypes := StepFileLoader.GetProjectTypeNames(filePath)
    
    projectDropdown := guiObj["ProjectType"]
    projectDropdown.Delete()
    
    if (projectTypes.Length > 0) {
        projectDropdown.Add(projectTypes)
        projectDropdown.Value := 1
        steps := StepFileLoader.GetStepsForType(filePath, projectTypes[1])
        UpdateProjectDescription(guiObj, projectTypes[1], steps)
    } else {
        projectDropdown.Add(["No project types found"])
        projectDropdown.Value := 1
        guiObj["Description"].Value := "No step definitions found for " . language
    }
    
    projectDropdown.OnEvent("Change", (ctrl, *) => OnProjectTypeChange(guiObj, language, ctrl.Text))
}

OnProjectTypeChange(guiObj, language, projectType) {
    global StepFilesPath
    
    langMap := Map(
        "JavaScript", StepFilesPath "\javascript\projects.steps",
        "Python", StepFilesPath "\python\projects.steps",
        "C# / .NET", StepFilesPath "\csharp\projects.steps",
        "TypeScript", StepFilesPath "\typescript\projects.steps"
    )
    
    if (!langMap.Has(language)) {
        return
    }
    
    steps := StepFileLoader.GetStepsForType(langMap[language], projectType)
    UpdateProjectDescription(guiObj, projectType, steps)
}

UpdateProjectDescription(guiObj, projectType, steps) {
    desc := "📋 " . projectType . "`n"
    desc .= "─────────────────────────────────────`n"
    desc .= "Steps: " . steps.Length . "`n`n"
    
    if (steps.Length > 0) {
        desc .= "Quick Overview:`n"
        for idx, step in steps {
            if (idx <= 4) {
                cmd := step.Has("command") ? step["command"] : ""
                desc .= "  " . idx . ". " . SubStr(cmd, 1, 50) . (StrLen(cmd) > 50 ? "..." : "") . "`n"
            }
        }
        if (steps.Length > 4) {
            desc .= "  ... and " . (steps.Length - 4) . " more steps"
        }
    }
    
    guiObj["Description"].Value := desc
}

LaunchTutorial(guiObj) {
    global StepFilesPath
    
    language := guiObj["Language"].Text
    projectType := guiObj["ProjectType"].Text
    
    if (projectType = "" || projectType = "No project types found") {
        MsgBox("Please select a valid project type.", "Error", 48)
        return
    }
    
    langMap := Map(
        "JavaScript", StepFilesPath "\javascript\projects.steps",
        "Python", StepFilesPath "\python\projects.steps",
        "C# / .NET", StepFilesPath "\csharp\projects.steps",
        "TypeScript", StepFilesPath "\typescript\projects.steps"
    )
    
    steps := StepFileLoader.GetStepsForType(langMap[language], projectType)
    
    if (steps.Length > 0) {
        guiObj.Destroy()
        StepCanvas(steps, projectType)
    } else {
        MsgBox("No steps found for " . projectType, "Error", 48)
    }
}

ShowProjectStepsBrowser() {
    ShowLearningCenter()
}

; =====================================================================================
; SECTION 11: PROJECT MANAGEMENT SYSTEM
; =====================================================================================

class ProjectManager {
    static projectsRegistry := ""
    static recentProjects := []
    
    static Init() {
        global ProjectsPath
        this.projectsRegistry := ProjectsPath "\projects.ini"
        this.LoadRecentProjects()
    }
    
    static LoadRecentProjects() {
        this.recentProjects := []
        try {
            recentStr := IniRead(this.projectsRegistry, "RecentProjects", "List", "")
            if (recentStr != "") {
                this.recentProjects := StrSplit(recentStr, "|")
            }
        }
    }
    
    static SaveRecentProjects() {
        recentStr := ""
        for idx, proj in this.recentProjects {
            if (idx <= 10) {
                recentStr .= (idx > 1 ? "|" : "") . proj
            }
        }
        IniWrite(recentStr, this.projectsRegistry, "RecentProjects", "List")
    }
    
    static AddToRecent(projectPath) {
        newRecent := []
        for idx, proj in this.recentProjects {
            if (proj != projectPath) {
                newRecent.Push(proj)
            }
        }
        newRecent.InsertAt(1, projectPath)
        this.recentProjects := newRecent
        this.SaveRecentProjects()
    }
    
    static OpenWithVSCode(projectPath) {
        global VSCodePath
        this.AddToRecent(projectPath)
        Run(VSCodePath . ' "' . projectPath . '"')
    }
    
    static OpenWithSublime(projectPath) {
        global SublimePath
        this.AddToRecent(projectPath)
        if (FileExist(SublimePath)) {
            Run('"' . SublimePath . '" "' . projectPath . '"')
        } else {
            MsgBox("Sublime Text not found at:`n" . SublimePath, "Error", 48)
        }
    }
    
    static OpenInTerminal(projectPath) {
        global GitBashPath
        this.AddToRecent(projectPath)
        if (FileExist(GitBashPath)) {
            Run('"' . GitBashPath . '" --cd="' . projectPath . '"')
        } else {
            Run('cmd.exe /K cd /d "' . projectPath . '"')
        }
    }
    
    static OpenInExplorer(projectPath) {
        this.AddToRecent(projectPath)
        Run('explorer.exe "' . projectPath . '"')
    }
}

ProjectManager.Init()

ShowNewProjectWizard() {
    global DefaultProjectRoot
    
    wizardGui := Gui("+AlwaysOnTop", "🆕 Create New Project")
    wizardGui.BackColor := "1E1E1E"
    wizardGui.isAlwaysOnTop := true
    
    wizardGui.Add("Text", "x10 y10 w150 cD4D4D4", "Project Name:")
    wizardGui.Add("Edit", "x10 y30 w380 h25 Background252526 cD4D4D4 vProjectName", "MyProject")
    
    wizardGui.Add("Text", "x10 y65 w150 cD4D4D4", "Location:")
    wizardGui.Add("Edit", "x10 y85 w310 h25 Background252526 cD4D4D4 vProjectPath", DefaultProjectRoot)
    btnBrowse := wizardGui.Add("Button", "x330 y85 w60 h25", "Browse")
    btnBrowse.OnEvent("Click", (*) => BrowseProjectPath(wizardGui))
    
    wizardGui.Add("Text", "x10 y120 w150 cD4D4D4", "Project Type:")
    projectTypes := wizardGui.Add("DropDownList", "x10 y140 w200 vProjectType Choose1 Background252526",
        [".NET Console App", ".NET Solution + Console + Library", ".NET Web API",
         "Node.js Express", "Python Virtual Env", "Empty Folder"])
    
    wizardGui.Add("GroupBox", "x10 y175 w380 h100 cD4D4D4", "Options")
    wizardGui.Add("Checkbox", "x20 y195 cD4D4D4 vOpenVSCode Checked", "Open in VS Code after creation")
    wizardGui.Add("Checkbox", "x20 y220 cD4D4D4 vCopyVSCodeConfig Checked", "Copy .vscode config templates")
    wizardGui.Add("Checkbox", "x20 y245 cD4D4D4 vInitGit", "Initialize Git repository")
    
    wizardGui.Add("Text", "x5 y280 w390 h1 Background444444")
    
    btnCreate := wizardGui.Add("Button", "x10 y290 w100 h30 Default", "🚀 Create")
    btnTutorial := wizardGui.Add("Button", "x120 y290 w100 h30", "📚 Tutorial")
    btnCancel := wizardGui.Add("Button", "x230 y290 w80 h30", "Cancel")
    btnPin := wizardGui.Add("Button", "x310 y290 w80 h30 vPinBtn", "📌 Pin")
    
    btnCreate.OnEvent("Click", (*) => CreateProject(wizardGui))
    btnTutorial.OnEvent("Click", (*) => (wizardGui.Destroy(), ShowLearningCenter()))
    btnCancel.OnEvent("Click", (*) => wizardGui.Destroy())
    btnPin.OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(wizardGui))
    
    wizardGui.Show("w400 h330")
}

BrowseProjectPath(guiObj) {
    selectedFolder := FileSelect("D", guiObj["ProjectPath"].Value, "Select project location")
    if (selectedFolder != "") {
        guiObj["ProjectPath"].Value := selectedFolder
    }
}

CreateProject(guiObj) {
    global TemplatesPath
    
    savedVals := guiObj.Submit(false)
    projectName := Trim(savedVals.ProjectName)
    projectPath := Trim(savedVals.ProjectPath)
    projectType := savedVals.ProjectType
    openVSCode := savedVals.OpenVSCode
    copyConfig := savedVals.CopyVSCodeConfig
    initGit := savedVals.InitGit
    
    if (projectName = "") {
        MsgBox("Please enter a project name.", "Error", 48)
        return
    }
    
    fullPath := projectPath . "\" . projectName
    
    if (DirExist(fullPath)) {
        result := MsgBox("Folder already exists. Continue anyway?", "Warning", 52)
        if (result = "No") {
            return
        }
    } else {
        DirCreate(fullPath)
    }
    
    GUT_Display("Creating Project", "Setting up " . projectName . "...`n`nType: " . projectType, 2000)
    
    switch projectType {
        case ".NET Console App":
            SetupDotNetConsole(fullPath, projectName)
        case ".NET Solution + Console + Library":
            SetupDotNetFullSolution(fullPath, projectName)
        case ".NET Web API":
            SetupDotNetWebAPI(fullPath, projectName)
        case "Node.js Express":
            SetupNodeExpress(fullPath, projectName)
        case "Python Virtual Env":
            SetupPythonVenv(fullPath, projectName)
    }
    
    if (copyConfig) {
        vscodeSource := TemplatesPath "\.vscode"
        vscodeDest := fullPath "\.vscode"
        if (DirExist(vscodeSource) && !DirExist(vscodeDest)) {
            DirCopy(vscodeSource, vscodeDest)
        }
    }
    
    if (initGit) {
        RunWait('git init', fullPath, "Hide")
    }
    
    ProjectManager.AddToRecent(fullPath)
    guiObj.Destroy()
    
    if (openVSCode) {
        ProjectManager.OpenWithVSCode(fullPath)
    }
    
    GUT_Display("Project Created! ✅",
        "Project: " . projectName . "`n"
        . "Location: " . fullPath . "`n`n"
        . "Type: " . projectType, 4000)
    
    RebuildMenu()
}

SetupDotNetConsole(path, name) {
    RunWait('dotnet new console -n "' . name . '"', path, "Hide")
}

SetupDotNetWebAPI(path, name) {
    RunWait('dotnet new webapi -n "' . name . '"', path, "Hide")
}

SetupDotNetFullSolution(path, name) {
    consoleName := name . "_Console"
    libraryName := name . "_Library"
    slnName := name
    
    RunWait('dotnet new sln -n "' . slnName . '"', path, "Hide")
    RunWait('dotnet new console -n "' . consoleName . '"', path, "Hide")
    RunWait('dotnet new classlib -n "' . libraryName . '"', path, "Hide")
    RunWait('dotnet sln "' . slnName . '.sln" add **/*.csproj', path, "Hide")
    
    consoleProj := path . "\" . consoleName . "\" . consoleName . ".csproj"
    libraryProj := path . "\" . libraryName . "\" . libraryName . ".csproj"
    RunWait('dotnet add "' . consoleProj . '" reference "' . libraryProj . '"', path, "Hide")
}

SetupNodeExpress(path, name) {
    RunWait('npm init -y', path, "Hide")
    RunWait('npm install express', path, "Hide")
    
    indexContent := "
(
// index.js - Express Server
const express = require('express');
const path = require('path');
const app = express();
const PORT = 3000;

app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

app.get('/api/hello', (req, res) => {
    res.json({ message: 'Hello from " . name . "!' });
});

app.listen(PORT, () => {
    console.log(`Server running at http://localhost:${PORT}`);
});
)"
    FileAppend(indexContent, path "\index.js")
    
    DirCreate(path "\public")
    
    htmlContent := "
(
<!DOCTYPE html>
<html>
<head>
    <meta charset=""utf-8"" />
    <title>" . name . "</title>
</head>
<body>
    <h1>Hello from " . name . "!</h1>
    <script src=""main.js""></script>
</body>
</html>
)"
    FileAppend(htmlContent, path "\public\index.html")
    
    jsContent := "
(
console.log('Main JS loaded');
fetch('/api/hello')
    .then(response => response.json())
    .then(data => console.log('API says:', data))
    .catch(console.error);
)"
    FileAppend(jsContent, path "\public\main.js")
}

SetupPythonVenv(path, name) {
    RunWait('python -m venv venv', path, "Hide")
    
    mainContent := "
(
#!/usr/bin/env python3
" . Chr(34) . Chr(34) . Chr(34) . "
" . name . " - Main entry point
" . Chr(34) . Chr(34) . Chr(34) . "

def main():
    print('Hello from " . name . "!')

if __name__ == '__main__':
    main()
)"
    FileAppend(mainContent, path "\main.py")
    FileAppend("# Add your dependencies here`n", path "\requirements.txt")
}

ShowRecentProjects() {
    if (ProjectManager.recentProjects.Length = 0) {
        GUT_Display("Recent Projects", "No recent projects found`n`nCreate a new project to get started!", 3000)
        return
    }
    
    items := []
    for idx, projPath in ProjectManager.recentProjects {
        SplitPath(projPath, &projName)
        items.Push(Map(
            "text", projName . " - " . projPath,
            "copyCommand", projPath,
            "actionText", "Open"
        ))
    }
    
    options := Map()
    options["itemized"] := true
    options["width"] := 700
    options["height"] := 400
    
    GUT_Display("Recent Projects (double-click to copy path)", items, -1, options)
}

ShowProjectSettings() {
    global SettingsFile, DefaultProjectRoot, VSCodePath, SublimePath, GitBashPath
    
    settingsGui := Gui("+AlwaysOnTop", "Project Settings")
    settingsGui.BackColor := "1E1E1E"
    settingsGui.isAlwaysOnTop := true
    
    settingsGui.Add("Text", "x10 y10 w150 cD4D4D4", "Default Project Root:")
    settingsGui.Add("Edit", "x10 y30 w310 h25 Background252526 cD4D4D4 vDefaultRoot", DefaultProjectRoot)
    settingsGui.Add("Button", "x330 y30 w60 h25", "Browse").OnEvent("Click", (*) => BrowseAndSet(settingsGui, "DefaultRoot"))
    
    settingsGui.Add("Text", "x10 y65 w150 cD4D4D4", "VS Code Command/Path:")
    settingsGui.Add("Edit", "x10 y85 w380 h25 Background252526 cD4D4D4 vVSCodePath", VSCodePath)
    
    settingsGui.Add("Text", "x10 y120 w150 cD4D4D4", "Sublime Text Path:")
    settingsGui.Add("Edit", "x10 y140 w310 h25 Background252526 cD4D4D4 vSublimePath", SublimePath)
    settingsGui.Add("Button", "x330 y140 w60 h25", "Browse").OnEvent("Click", (*) => BrowseFileAndSet(settingsGui, "SublimePath"))
    
    settingsGui.Add("Text", "x10 y175 w150 cD4D4D4", "Git Bash Path:")
    settingsGui.Add("Edit", "x10 y195 w310 h25 Background252526 cD4D4D4 vGitBashPath", GitBashPath)
    settingsGui.Add("Button", "x330 y195 w60 h25", "Browse").OnEvent("Click", (*) => BrowseFileAndSet(settingsGui, "GitBashPath"))
    
    settingsGui.Add("Text", "x5 y235 w390 h1 Background444444")
    
    settingsGui.Add("Button", "x10 y245 w80 h30", "Save").OnEvent("Click", (*) => SaveProjectSettings(settingsGui))
    settingsGui.Add("Button", "x100 y245 w80 h30", "Cancel").OnEvent("Click", (*) => settingsGui.Destroy())
    settingsGui.Add("Button", "x310 y245 w80 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(settingsGui))
    
    settingsGui.Show("w400 h285")
}

BrowseAndSet(guiObj, controlName) {
    currentVal := guiObj[controlName].Value
    selectedFolder := FileSelect("D", currentVal, "Select folder")
    if (selectedFolder != "") {
        guiObj[controlName].Value := selectedFolder
    }
}

BrowseFileAndSet(guiObj, controlName) {
    currentVal := guiObj[controlName].Value
    selectedFile := FileSelect(3, currentVal, "Select executable", "Executables (*.exe)")
    if (selectedFile != "") {
        guiObj[controlName].Value := selectedFile
    }
}

SaveProjectSettings(guiObj) {
    global SettingsFile, DefaultProjectRoot, VSCodePath, SublimePath, GitBashPath
    
    savedVals := guiObj.Submit(false)
    
    DefaultProjectRoot := savedVals.DefaultRoot
    VSCodePath := savedVals.VSCodePath
    SublimePath := savedVals.SublimePath
    GitBashPath := savedVals.GitBashPath
    
    IniWrite(DefaultProjectRoot, SettingsFile, "Projects", "DefaultRoot")
    IniWrite(VSCodePath, SettingsFile, "Projects", "VSCodePath")
    IniWrite(SublimePath, SettingsFile, "Projects", "SublimePath")
    IniWrite(GitBashPath, SettingsFile, "Projects", "GitBashPath")
    
    guiObj.Destroy()
    GUT_Display("Settings Saved", "Project settings have been updated.", 2000)
}

; =====================================================================================
; SECTION 12: MAIN MENU PREPARATION (Traditional Menu for Ctrl+RShift)
; =====================================================================================

PrepareMenu(PATH) {
    global callingWindowItem, ActionsFile
    
    popupMenu := Menu()
    popupMenu.Add("Add Class Note", (*) => AddClassNote())
    popupMenu.Add("Show Classes", (*) => ShowClasses())
    popupMenu.Add("Google Search", (*) => GoogleSearch())
    popupMenu.Add("Find in Files", (*) => FindInFiles())
    popupMenu.Add()
    
    projectSubMenu := Menu()
    projectSubMenu.Add("🆕 Create New Project", (*) => ShowNewProjectWizard())
    projectSubMenu.Add("📋 Recent Projects", (*) => ShowRecentProjects())
    projectSubMenu.Add()
    projectSubMenu.Add("📚 Learning Center", (*) => ShowLearningCenter())
    projectSubMenu.Add()
    projectSubMenu.Add("⚙️ Project Settings", (*) => ShowProjectSettings())
    popupMenu.Add("🚀 Project Management", projectSubMenu)
    popupMenu.Add()
    
    LoopOverFolder(PATH, popupMenu)
    
    actionsSubMenu := BuildActionsMenu(PATH)
    if (IsObject(actionsSubMenu)) {
        popupMenu.Add()
        popupMenu.Add("📁 Actions", actionsSubMenu)
    }
    
    adminSubMenu := Menu()
    adminSubMenu.Add("Settings", (*) => ShowSettingsGUI())
    adminSubMenu.Add("Add Action Item", (*) => ShowAddActionGUI())
    adminSubMenu.Add()
    adminSubMenu.Add("Reload Menu", (*) => RebuildMenu())
    adminSubMenu.Add("Reload Script", (*) => Reload())
    adminSubMenu.Add()
    adminSubMenu.Add("Open Script Folder", (*) => Run("explorer.exe " . A_ScriptDir))
    adminSubMenu.Add("Open Menu Folder", (*) => Run("explorer.exe " . CustomMenuPath))
    adminSubMenu.Add()
    adminSubMenu.Add("Exit", (*) => ExitApp())
    popupMenu.Add()
    popupMenu.Add("⚙️ Admin", adminSubMenu)
    
    callingWindowItem := "Calling Window: "
    popupMenu.Add(callingWindowItem, (*) => FocusCallingWindow())
    
    return popupMenu
}

LoopOverFolder(PATH, parentMenu) {
    try {
        Loop Files, PATH "\*", "DF" {
            if (A_LoopFileAttrib ~= "D") {
                subMenu := Menu()
                LoopOverFolder(A_LoopFilePath, subMenu)
                
                if (FileExist(A_LoopFilePath "\steps.txt")) {
                    subMenu.Add()
                    subMenu.Add("📋 View Project Steps", ViewProjectSteps.Bind(A_LoopFilePath))
                }
                parentMenu.Add(A_LoopFileName, subMenu)
            } else {
                parentMenu.Add(A_LoopFileName, MenuEventHandler.Bind(A_LoopFilePath))
            }
        }
    }
}

ViewProjectSteps(folderPath, *) {
    stepsFile := folderPath "\steps.txt"
    if (FileExist(stepsFile)) {
        StepCanvas(stepsFile, "Project Steps")
    } else {
        MsgBox("Steps file not found: " . stepsFile, "Error", 16)
    }
}

BuildActionsMenu(contextPath) {
    global ActionsFile
    
    if (!FileExist(ActionsFile)) {
        return ""
    }
    
    actionsSubMenu := Menu()
    actionCount := 0
    
    try {
        fileContent := FileRead(ActionsFile)
    } catch {
        return ""
    }
    
    inActionsSection := false
    
    for lineText in StrSplit(fileContent, "`n", "`r") {
        lineText := Trim(lineText)
        
        if (lineText = "" || SubStr(lineText, 1, 1) = ";") {
            continue
        }
        
        if (SubStr(lineText, 1, 1) = "[") {
            inActionsSection := (lineText = "[Actions]")
            continue
        }
        
        if (inActionsSection && InStr(lineText, "=")) {
            parts := StrSplit(lineText, "=", , 2)
            actionName := Trim(parts[1])
            functionName := Trim(parts[2])
            actionsSubMenu.Add(actionName, (*) => ExecuteAction(functionName, contextPath))
            actionCount++
        }
    }
    
    if (actionCount = 0) {
        return ""
    }
    
    return actionsSubMenu
}

ExecuteAction(functionName, contextPath) {
    switch functionName {
        case "Action_DumpClipboard":
            Action_DumpClipboard(contextPath)
        case "Action_NewFolder":
            Action_NewFolder(contextPath)
        case "Action_NewFile":
            Action_NewFile(contextPath)
        case "Action_OpenFolder":
            Action_OpenFolder(contextPath)
        case "Action_CaptureStructure":
            Action_CaptureStructure(contextPath)
        default:
            MsgBox("Unknown action: " . functionName, "Error", 16)
    }
}

; =====================================================================================
; SECTION 13: ACTION FUNCTIONS
; =====================================================================================

Action_DumpClipboard(folderPath) {
    dumpFile := folderPath "\dump.txt"
    clipContent := A_Clipboard
    
    if (clipContent = "") {
        GUT_Display("Dump Clipboard", "Clipboard is empty. Nothing to dump.", 3000)
        return
    }
    
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    activeWindow := WinGetTitle("A")
    
    entry := "`n`n"
        . "═══════════════════════════════════════════════════════════`n"
        . "📅 " . timestamp . " | 🪟 " . activeWindow . "`n"
        . "═══════════════════════════════════════════════════════════`n"
        . clipContent
    
    FileAppend(entry, dumpFile)
    GUT_Display("Dump Clipboard", "Content appended to`n" . dumpFile . "`n`nCharacters: " . StrLen(clipContent), 3000)
}

Action_NewFolder(folderPath) {
    result := InputBox("Enter the name for the new folder:", "Create New Folder", "w300 h120")
    
    if (result.Result = "Cancel" || result.Value = "") {
        return
    }
    
    newFolderPath := folderPath "\" . result.Value
    
    if (DirExist(newFolderPath)) {
        GUT_Display("Folder Exists", "A folder with this name already exists:`n" . newFolderPath, 4000)
        return
    }
    
    DirCreate(newFolderPath)
    RebuildMenu()
    GUT_Display("Folder Created", "Successfully created:`n" . newFolderPath, 3000)
}

Action_NewFile(folderPath) {
    fileGui := Gui("+AlwaysOnTop", "Create New File")
    fileGui.BackColor := "1E1E1E"
    fileGui.targetFolder := folderPath
    fileGui.isAlwaysOnTop := true
    
    fileGui.Add("Text", "x10 y10 w280 cD4D4D4", "Enter filename (with extension):")
    editName := fileGui.Add("Edit", "x10 y30 w280 h25 Background252526 cD4D4D4 vFileName", "")
    editName.Focus()
    
    fileGui.Add("Checkbox", "x10 y65 cD4D4D4 vUseClipboard", "Paste clipboard content into file")
    
    fileGui.Add("Text", "x5 y95 w290 h1 Background444444")
    
    fileGui.Add("Button", "x10 y105 w70 h30 Default", "Create").OnEvent("Click", (*) => CreateFileFromGUI(fileGui))
    fileGui.Add("Button", "x90 y105 w70 h30", "Cancel").OnEvent("Click", (*) => fileGui.Destroy())
    fileGui.Add("Button", "x220 y105 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(fileGui))
    
    fileGui.Show("w300 h145")
}

CreateFileFromGUI(guiObj) {
    savedVals := guiObj.Submit(false)
    fileName := savedVals.FileName
    useClipboard := savedVals.UseClipboard
    folderPath := guiObj.targetFolder
    
    if (fileName = "") {
        MsgBox("Please enter a filename.", "Error", 48)
        return
    }
    
    newFilePath := folderPath "\" . fileName
    
    if (FileExist(newFilePath)) {
        MsgBox("A file with this name already exists.", "Error", 48)
        return
    }
    
    content := useClipboard ? A_Clipboard : ""
    FileAppend(content, newFilePath)
    
    guiObj.Destroy()
    RebuildMenu()
    GUT_Display("File Created", "Successfully created:`n" . newFilePath, 3000)
}

Action_OpenFolder(folderPath) {
    Run("explorer.exe " . folderPath)
}

Action_CaptureStructure(folderPath) {
    treeText := String(folderPath) . "`n" . GenerateFolderTree(String(folderPath), "", true)
    
    options := Map()
    options["tree"] := true
    options["width"] := 600
    options["height"] := 500
    
    GUT_Display("Folder Structure", folderPath, -1, options)
}

; =====================================================================================
; SECTION 14: FILE HANDLERS
; =====================================================================================

MenuEventHandler(FilePath, *) {
    if (FilePath = "") {
        return
    }
    
    SplitPath(FilePath, &name, &dir, &ext, &nameNoExt)
    
    switch StrLower(ext) {
        case "txt":
            Handler_txt(FilePath)
        case "rtf":
            Handler_RTF(FilePath)
        case "dump":
            Handler_dump(FilePath)
        case "action":
            Handler_Action(FilePath)
        case "note":
            Handler_note(FilePath)
        case "ahk":
            Handler_Ahk(FilePath)
        case "json":
            Handler_json(FilePath)
        case "html", "htm":
            Handler_html(FilePath)
        case "exe", "bat", "cmd":
            Handler_LaunchProgram(FilePath)
        case "steps":
            Handler_steps(FilePath)
        default:
            Handler_default(FilePath)
    }
}

Handler_txt(PATH) {
    content := FileRead(PATH)
    A_Clipboard := content
    Send("^v")
}

Handler_steps(FilePath) {
    projectTypes := StepFileLoader.LoadFile(FilePath)
    
    if (projectTypes.Count = 0) {
        GUT_Display("No Steps Found", "No valid project types found in this file.", 3000)
        return
    }
    
    if (projectTypes.Count = 1) {
        for typeName, steps in projectTypes {
            StepCanvas(steps, typeName)
            return
        }
    }
    
    items := []
    for typeName, steps in projectTypes {
        items.Push(Map(
            "text", typeName . " (" . steps.Length . " steps)",
            "callback", (*) => StepCanvas(steps, typeName)
        ))
    }
    
    options := Map()
    options["itemized"] := true
    options["width"] := 500
    options["height"] := 400
    
    GUT_Display("Select Project Type", items, -1, options)
}

Handler_default(PATH) {
    if (!FileExist(PATH)) {
        GUT_Display("Error", "File not found:`n" . PATH, 4000)
        return
    }
    
    fileContent := FileRead(PATH)
    
    editGui := Gui("+AlwaysOnTop -Caption +ToolWindow +Border", "Text Viewer: " . PATH)
    editGui.Opt("+E0x08000000")
    editGui.BackColor := "1E1E1E"
    editGui.filePath := PATH
    editGui.isEditMode := false
    editGui.isAlwaysOnTop := true
    editGui.OnEvent("Size", EditGuiResize)
    
    SplitPath(PATH, &fileName)
    editGui.Add("Text", "x0 y0 w620 h25 +0x200 Background2D2D30 c00AAFF", "  📄 " . fileName)
    
    editCtrl := editGui.Add("Edit", "vFileContent x5 y30 w610 h390 +ReadOnly Background252526 cD4D4D4 -E0x200 +VScroll", fileContent)
    
    wordCount := CountWords(fileContent)
    editGui.Add("Text", "x5 y425 w400 h20 c888888", "Words: " . wordCount . " | Chars: " . StrLen(fileContent))
    
    editGui.Add("Text", "x5 y448 w610 h1 Background444444")
    
    editGui.Add("Button", "x10 y455 w70 h30", "📋 Copy").OnEvent("Click", (*) => CopyContent(editCtrl))
    editGui.Add("Button", "x90 y455 w70 h30 vEditBtn", "✏️ Edit").OnEvent("Click", (*) => ToggleEdit(editGui, editCtrl, editGui["EditBtn"]))
    editGui.Add("Button", "x450 y455 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(editGui))
    editGui.Add("Button", "x530 y455 w80 h30", "✖️ Close").OnEvent("Click", (*) => editGui.Destroy())
    
    MonitorGet(MonitorGetPrimary(), &left, &top, &right, &bottom)
    posX := right - 630
    posY := top + 10
    
    editGui.Show("x" . posX . " y" . posY . " w620 h495 NoActivate")
    WinSetTransparent(180, "ahk_id " . editGui.Hwnd)
}

ToggleGuiAlwaysOnTop(guiObj) {
    try {
        if (guiObj.isAlwaysOnTop) {
            guiObj.Opt("-AlwaysOnTop")
            guiObj.isAlwaysOnTop := false
            try {
                guiObj["PinBtn"].Text := "📍 Unpin"
            }
            ToolTip("Window unpinned")
        } else {
            guiObj.Opt("+AlwaysOnTop")
            guiObj.isAlwaysOnTop := true
            try {
                guiObj["PinBtn"].Text := "📌 Pin"
            }
            ToolTip("Window pinned")
        }
        SetTimer((*) => ToolTip(), -1500)
    }
}

Handler_RTF(FilePath) {
    A_Clipboard := ""
    Sleep(200)
    try {
        wordApp := ComObject("Word.Application")
        oDoc := wordApp.Documents.Open(FilePath)
        Sleep(250)
        oDoc.Range.FormattedText.Copy()
        Sleep(250)
        if (!ClipWait(2)) {
            oDoc.Close(0)
            return
        }
        oDoc.Close(0)
        Sleep(250)
        Send("^v")
    } catch as err {
        MsgBox("Error opening RTF file:`n" . err.Message, "Error", 48)
    }
}

Handler_dump(PATH) {
    fileContent := A_Clipboard
    if (fileContent = "") {
        GUT_Display("Dump", "Clipboard is empty - nothing to dump.", 3000)
        return
    }
    
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    activeWindowTitle := WinGetTitle("A")
    
    newContent := "`n`n#═══════════════════════════════════════`n"
        . "# " . timestamp . " | " . activeWindowTitle . "`n"
        . "#═══════════════════════════════════════`n"
        . fileContent
    
    FileAppend(newContent, PATH)
    GUT_Display("Dump Updated", "Content added to:`n" . PATH, 3000)
}

Handler_Action(FilePath) {
    SplitPath(FilePath, &name, &actionDir, &ext, &nameNoExt)
    SplitPath(actionDir, , &languageFolder)
    languageFolder := StrReplace(languageFolder, "\(Action)")
    languageFolder := StrReplace(languageFolder, "\Action")
    
    switch nameNoExt {
        case "Dump":
            Action_DumpClipboard(languageFolder)
        case "NewFolder":
            Action_NewFolder(languageFolder)
        case "NewFile":
            Action_NewFile(languageFolder)
        case "OpenFolder":
            Action_OpenFolder(languageFolder)
        case "CaptureStructure":
            Action_CaptureStructure(languageFolder)
        default:
            MsgBox("Unknown action: " . nameNoExt, "Action Handler", 48)
    }
}

Handler_note(PATH) {
    fileContent := FileRead(PATH)
    lines := StrSplit(fileContent, "`n", "`r")
    
    if (lines.Length < 2) {
        MsgBox("Note file must have at least 2 lines.", "Invalid Note", 48)
        return
    }
    
    content := ""
    for index, lineText in lines {
        if (index > 1) {
            content .= (index > 2 ? "`n" : "") . lineText
        }
    }
    
    A_Clipboard := content
    Sleep(50)
    Send("^v")
}

Handler_Ahk(filepath) {
    optionsMenu := Menu()
    optionsMenu.Add("View in GUT", (*) => ViewAhkInGUT(filepath))
    optionsMenu.Add("Edit in Notepad", (*) => Run("notepad.exe " . filepath))
    optionsMenu.Add("Run Script", (*) => Run(filepath))
    optionsMenu.Add()
    optionsMenu.Add("Open Containing Folder", (*) => Run("explorer.exe /select," . filepath))
    optionsMenu.Show()
}

ViewAhkInGUT(filepath) {
    content := FileRead(filepath)
    options := Map()
    options["width"] := 700
    options["height"] := 500
    
    actions := []
    actions.Push(Map("text", "Edit", "callback", (*) => Run("notepad.exe " . filepath)))
    actions.Push(Map("text", "Run", "callback", (*) => Run(filepath)))
    options["actions"] := actions
    
    GUT_Display("AHK Script: " . filepath, content, -1, options)
}

Handler_json(filepath) {
    content := FileRead(filepath)
    options := Map()
    options["width"] := 600
    options["height"] := 500
    GUT_Display("JSON: " . filepath, content, -1, options)
}

Handler_html(filepath) {
    optionsMenu := Menu()
    optionsMenu.Add("Open in Browser", (*) => Run(filepath))
    optionsMenu.Add("View Source", (*) => Handler_txt(filepath))
    optionsMenu.Show()
}

Handler_LaunchProgram(FilePath) {
    Run(FilePath)
}

; =====================================================================================
; SECTION 15: GUI HELPER FUNCTIONS
; =====================================================================================

CopyContent(editCtrl) {
    A_Clipboard := editCtrl.Value
    ToolTip("📋 Content copied to clipboard!")
    SetTimer((*) => ToolTip(), -2000)
}

ToggleEdit(guiObj, editCtrl, btnEdit) {
    if (!guiObj.isEditMode) {
        editCtrl.Opt("-ReadOnly")
        btnEdit.Text := "💾 Save"
        ToolTip("✏️ Edit mode enabled")
        WinSetTransparent(255, "ahk_id " . guiObj.Hwnd)
        guiObj.Opt("-E0x08000000 +Caption +Resize")
        guiObj.isEditMode := true
    } else {
        editCtrl.Opt("+ReadOnly")
        btnEdit.Text := "✏️ Edit"
        if (guiObj.HasProp("filePath") && guiObj.filePath != "") {
            try {
                FileDelete(guiObj.filePath)
                FileAppend(editCtrl.Value, guiObj.filePath)
                ToolTip("💾 Changes saved")
            } catch as err {
                MsgBox("Error saving file: " . err.Message, "Save Error", 48)
            }
        } else {
            ToolTip("✏️ Edit mode disabled")
        }
        WinSetTransparent(180, "ahk_id " . guiObj.Hwnd)
        guiObj.Opt("+E0x08000000 -Caption -Resize")
        guiObj.isEditMode := false
    }
    SetTimer((*) => ToolTip(), -2000)
}

EditGuiResize(guiObj, minMax, width, height) {
    if (minMax = -1) {
        return
    }
    try {
        editCtrl := guiObj["FileContent"]
        if (editCtrl) {
            editCtrl.Move(, , width - 10, height - 105)
        }
    }
}

; =====================================================================================
; SECTION 16: SETTINGS & CONFIGURATION GUIs
; =====================================================================================

ShowSettingsGUI() {
    global SettingsFile, GUT_DefaultTimeout, GUT_DefaultTransparency, CustomMenuPath
    
    settingsGui := Gui("+AlwaysOnTop", "GlobalCoder Settings")
    settingsGui.BackColor := "1E1E1E"
    settingsGui.isAlwaysOnTop := true
    
    settingsGui.Add("GroupBox", "x10 y10 w380 h150 cD4D4D4", "GUT Display Settings")
    
    settingsGui.Add("Text", "x20 y35 w120 cD4D4D4", "Auto-hide timeout (ms):")
    settingsGui.Add("Edit", "x150 y32 w100 Background252526 cD4D4D4 vTimeout", GUT_DefaultTimeout)
    
    settingsGui.Add("Text", "x20 y65 w120 cD4D4D4", "Transparency (0-255):")
    settingsGui.Add("Edit", "x150 y62 w100 Background252526 cD4D4D4 vTransparency", GUT_DefaultTransparency)
    
    settingsGui.Add("Text", "x20 y95 w120 cD4D4D4", "Default Width:")
    settingsGui.Add("Edit", "x150 y92 w100 Background252526 cD4D4D4 vDefWidth",
        IniRead(SettingsFile, "GUT_Display", "DefaultWidth", 500))
    
    settingsGui.Add("Text", "x20 y125 w120 cD4D4D4", "Default Height:")
    settingsGui.Add("Edit", "x150 y122 w100 Background252526 cD4D4D4 vDefHeight",
        IniRead(SettingsFile, "GUT_Display", "DefaultHeight", 300))
    
    settingsGui.Add("GroupBox", "x10 y170 w380 h80 cD4D4D4", "Paths")
    settingsGui.Add("Text", "x20 y195 w350 c888888", "Menu Folder: " . CustomMenuPath)
    settingsGui.Add("Text", "x20 y215 w350 c888888", "Settings File: " . SettingsFile)
    
    settingsGui.Add("Text", "x5 y255 w390 h1 Background444444")
    
    settingsGui.Add("Button", "x10 y265 w70 h30", "Save").OnEvent("Click", (*) => SaveSettings(settingsGui))
    settingsGui.Add("Button", "x90 y265 w70 h30", "Cancel").OnEvent("Click", (*) => settingsGui.Destroy())
    settingsGui.Add("Button", "x170 y265 w90 h30", "Open Folder").OnEvent("Click", (*) => Run("explorer.exe " . CustomMenuPath))
    settingsGui.Add("Button", "x320 y265 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(settingsGui))
    
    settingsGui.Show("w400 h305")
}

SaveSettings(guiObj) {
    global SettingsFile, GUT_DefaultTimeout, GUT_DefaultTransparency, GUT_DefaultWidth, GUT_DefaultHeight
    
    savedVals := guiObj.Submit(false)
    
    timeout := Integer(savedVals.Timeout)
    transparency := Integer(savedVals.Transparency)
    width := Integer(savedVals.DefWidth)
    height := Integer(savedVals.DefHeight)
    
    transparency := Max(0, Min(255, transparency))
    
    IniWrite(timeout, SettingsFile, "GUT_Display", "Timeout")
    IniWrite(transparency, SettingsFile, "GUT_Display", "Transparency")
    IniWrite(width, SettingsFile, "GUT_Display", "DefaultWidth")
    IniWrite(height, SettingsFile, "GUT_Display", "DefaultHeight")
    
    GUT_DefaultTimeout := timeout
    GUT_DefaultTransparency := transparency
    GUT_DefaultWidth := width
    GUT_DefaultHeight := height
    
    guiObj.Destroy()
    GUT_Display("Settings Saved", "Your settings have been saved.", 2000)
}

ShowAddActionGUI() {
    global ActionsFile
    
    addGui := Gui("+AlwaysOnTop", "Add Action Item")
    addGui.BackColor := "1E1E1E"
    addGui.isAlwaysOnTop := true
    
    addGui.Add("Text", "x10 y10 w280 cD4D4D4", "Action Display Name:")
    addGui.Add("Edit", "x10 y30 w280 Background252526 cD4D4D4 vActionName", "")
    
    addGui.Add("Text", "x10 y60 w280 cD4D4D4", "Function Name:")
    addGui.Add("Edit", "x10 y80 w280 Background252526 cD4D4D4 vFuncName", "Action_")
    
    addGui.Add("Text", "x5 y115 w290 h1 Background444444")
    
    addGui.Add("Button", "x10 y125 w70 h30", "Add").OnEvent("Click", (*) => AddActionItem(addGui))
    addGui.Add("Button", "x90 y125 w70 h30", "Cancel").OnEvent("Click", (*) => addGui.Destroy())
    addGui.Add("Button", "x220 y125 w70 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(addGui))
    
    addGui.Show("w300 h165")
}

AddActionItem(guiObj) {
    global ActionsFile
    
    savedVals := guiObj.Submit(false)
    name := Trim(savedVals.ActionName)
    func := Trim(savedVals.FuncName)
    
    if (name = "" || func = "") {
        MsgBox("Please enter both a name and function.", "Error", 48)
        return
    }
    
    content := FileExist(ActionsFile) ? FileRead(ActionsFile) : "[Actions]`n`n[ActionDescriptions]`n"
    content := StrReplace(content, "[Actions]", "[Actions]`n" . name . "=" . func)
    
    try {
        FileDelete(ActionsFile)
    }
    FileAppend(content, ActionsFile)
    
    guiObj.Destroy()
    RebuildMenu()
    GUT_Display("Action Added", "New action '" . name . "' added.", 3000)
}

ShowMainFeaturesGUI() {
    global mainMenu
    
    mainGui := Gui("+AlwaysOnTop", "GlobalCoder Features")
    mainGui.BackColor := "1E1E1E"
    mainGui.isAlwaysOnTop := true
    
    titleText := mainGui.Add("Text", "x10 y10 w280 h30 c00AAFF Center", "🌐 GlobalCoder")
    titleText.SetFont("s14 bold")
    
    btnY := 50
    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "📋 Show Custom Menu (jjj)").OnEvent("Click", (*) => (mainGui.Destroy(), ShowCustomMenu()))
    btnY += 45
    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "📚 Learning Center").OnEvent("Click", (*) => (mainGui.Destroy(), ShowLearningCenter()))
    btnY += 45
    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "🆕 Create New Project").OnEvent("Click", (*) => (mainGui.Destroy(), ShowNewProjectWizard()))
    btnY += 45
    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "🔍 Google Search (ggg)").OnEvent("Click", (*) => (mainGui.Destroy(), GoogleSearchWithLogging()))
    btnY += 45
    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "📜 View Query Log").OnEvent("Click", (*) => (mainGui.Destroy(), ShowQueryLog()))
    btnY += 45
    mainGui.Add("Button", "x10 y" . btnY . " w280 h35", "⚙️ Settings").OnEvent("Click", (*) => (mainGui.Destroy(), ShowSettingsGUI()))
    btnY += 55
    
    mainGui.Add("Text", "x5 y" . (btnY - 10) . " w290 h1 Background444444")
    
    mainGui.Add("Button", "x10 y" . btnY . " w130 h30", "✖ Close").OnEvent("Click", (*) => mainGui.Destroy())
    mainGui.Add("Button", "x160 y" . btnY . " w130 h30 vPinBtn", "📌 Pin").OnEvent("Click", (*) => ToggleGuiAlwaysOnTop(mainGui))
    
    mainGui.Show("w300 h" . (btnY + 40))
}

ShowMainMenu() {
    global mainMenu
    if (IsObject(mainMenu)) {
        mainMenu.Show()
    } else {
        mainMenu := PrepareMenu(CustomMenuPath)
        mainMenu.Show()
    }
}

; =====================================================================================
; SECTION 17: DEMO FUNCTIONS
; =====================================================================================

DemoGUTDisplay() {
    GUT_Display("Demo: GUT-Display",
        "This is the GUT-Display - a transparent, non-focusable popup`n`n"
        . "Features:`n"
        . "• Doesn't steal focus from your work`n"
        . "• Auto-hides after timeout`n"
        . "• Customizable transparency`n"
        . "• COPY, PIN, and CLOSE buttons!", 5000)
}

DemoStepCanvas() {
    global StepFilesPath
    jsStepsFile := StepFilesPath "\javascript\projects.steps"
    
    if (FileExist(jsStepsFile)) {
        projectTypes := StepFileLoader.LoadFile(jsStepsFile)
        for typeName, steps in projectTypes {
            StepCanvas(steps, typeName)
            return
        }
    } else {
        GUT_Display("Demo Not Available", "Steps file not found. Run the script once to generate files.", 4000)
    }
}

; =====================================================================================
; SECTION 18: UTILITY FUNCTIONS
; =====================================================================================

FindInFiles() {
    global CustomMenuPath
    
    result := InputBox("Enter search string:", "Find in Files", "w300 h120")
    if (result.Result = "Cancel" || result.Value = "") {
        return
    }
    
    searchStr := result.Value
    results := []
    
    try {
        Loop Files, CustomMenuPath "\*.*", "RF" {
            ext := StrLower(SubStr(A_LoopFileName, -3))
            if (ext = ".exe" || ext = ".dll" || ext = ".zip") {
                continue
            }
            
            try {
                content := FileRead(A_LoopFilePath)
                if (InStr(content, searchStr)) {
                    relPath := StrReplace(A_LoopFilePath, CustomMenuPath . "\", "")
                    results.Push(Map("text", relPath, "copyCommand", A_LoopFilePath))
                }
            }
        }
    }
    
    if (results.Length > 0) {
        options := Map()
        options["itemized"] := true
        options["width"] := 600
        options["height"] := 400
        GUT_Display("Search: '" . searchStr . "' (" . results.Length . " found)", results, -1, options)
    } else {
        GUT_Display("No Results", "No matches found for: " . searchStr, 3000)
    }
}

GoogleSearch() {
    result := InputBox("Enter search query:", "Google Search", "w300 h120")
    if (result.Result = "Cancel" || result.Value = "") {
        return
    }
    
    query := UrlEncode(result.Value)
    url := "https://www.google.com/search?q=" . query . "&as_qdr=y1"
    Run(url)
}

UrlEncode(str) {
    result := ""
    Loop Parse, str {
        charCode := Ord(A_LoopField)
        if (A_LoopField = " ") {
            result .= "+"
        } else if ((charCode >= 48 && charCode <= 57)
                || (charCode >= 65 && charCode <= 90)
                || (charCode >= 97 && charCode <= 122)
                || A_LoopField = "-" || A_LoopField = "_" || A_LoopField = "." || A_LoopField = "~") {
            result .= A_LoopField
        } else {
            result .= "%" . Format("{:02X}", charCode)
        }
    }
    return result
}

AddClassNote() {
    global ClassesPath
    
    result := InputBox("Enter class name:", "Add Class Note", "w250 h120")
    if (result.Result = "Cancel" || result.Value = "") {
        return
    }
    
    className := result.Value
    filePath := ClassesPath "\" . className . ".cs"
    template := "using System;`n`nnamespace MyNamespace`n{`n    public class " . className . "`n    {`n        public " . className . "()`n        {`n        }`n    }`n}"
    
    if (!DirExist(ClassesPath)) {
        DirCreate(ClassesPath)
    }
    
    FileAppend(template, filePath)
    Run(filePath)
    RebuildMenu()
}

ShowClasses() {
    global ClassesPath
    
    classList := []
    try {
        Loop Files, ClassesPath "\*.cs" {
            classList.Push(Map("text", A_LoopFileName, "copyCommand", A_LoopFilePath))
        }
    }
    
    if (classList.Length > 0) {
        options := Map()
        options["itemized"] := true
        options["width"] := 400
        options["height"] := 300
        GUT_Display("C# Classes", classList, -1, options)
    } else {
        GUT_Display("No Classes", "No C# class files found.", 3000)
    }
}

CountWords(text) {
    count := 0
    Loop Parse, text, " `t`n`r" {
        if (A_LoopField != "") {
            count++
        }
    }
    return count
}

RebuildMenu() {
    global mainMenu, CustomMenuPath
    mainMenu := PrepareMenu(CustomMenuPath)
    GUT_Display("Menu Rebuilt", "Menu refreshed with current folder contents.", 2000)
}

UpdateCallingWindowInfo(menuObj) {
    global callingWindowTitle, callingWindowItem
    callingWindowTitle := WinGetTitle("A")
    try {
        if (IsObject(menuObj)) {
            menuObj.Rename(callingWindowItem, "Calling Window: " . SubStr(callingWindowTitle, 1, 30))
        }
    }
}

FocusCallingWindow() {
    global callingWindowTitle
    if (callingWindowTitle != "" && WinExist(callingWindowTitle)) {
        WinActivate(callingWindowTitle)
    }
}

LogError(exception, mode) {
    global CustomMenuPath
    errorLog := CustomMenuPath "\errorlog.txt"
    timestamp := FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss")
    errorText := timestamp . " | Line " . exception.Line . ": " . exception.Message . "`n"
    FileAppend(errorText, errorLog)
    OutputDebug("Error: " . exception.Message)
    return true
}

; =====================================================================================
; SECTION 19: HOTKEY DEFINITIONS
; =====================================================================================
; These are the keyboard shortcuts that trigger various actions.
; The syntax is: modifier+key:: { code }
; Modifiers: ^ = Ctrl, ! = Alt, + = Shift, # = Win

; Ctrl + Right Shift: Show traditional popup menu
^RShift:: {
    global mainMenu, callingWindowTitle
    callingWindowTitle := WinGetTitle("A")
    UpdateCallingWindowInfo(mainMenu)
    ShowMainMenu()
}

; Alt + Right Shift: Also show menu (alternative)
!RShift:: {
    global mainMenu
    UpdateCallingWindowInfo(mainMenu)
    ShowMainMenu()
}

; Ctrl + Space: Quick Google search
^Space:: GoogleSearch()

; Ctrl + Alt + N: New project wizard
^!n:: ShowNewProjectWizard()

; Ctrl + Alt + L: Learning center
^!l:: ShowLearningCenter()

; Ctrl + Alt + R: Rebuild menu
^!r:: RebuildMenu()

; Ctrl + Alt + Right Shift: Also rebuild menu
^!RShift:: RebuildMenu()

; Ctrl + Alt + M: Show custom navigable menu (alternative to jjj hotstring)
^!m:: ShowCustomMenu()

; =====================================================================================
; END OF SCRIPT
; =====================================================================================

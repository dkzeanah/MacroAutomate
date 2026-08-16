#Requires AutoHotkey v2.0
#SingleInstance Force

; ============================================================================
; Global Console Command Menu
; AutoHotkey v2
;
; Global hotkeys:
;   Ctrl+Alt+Space        Show the command menu using the current send mode.
;   Ctrl+Alt+Shift+Space  Show the menu in Copy Only mode.
;   Ctrl+AppsKey          Alternate context-menu hotkey.
;   Ctrl+Alt+R            Paste clipboard into the target console and press Enter.
;   Ctrl+Alt+V            Paste clipboard into the target console without Enter.
;   Ctrl+Alt+T            Pin the currently active window as the command target.
;   Ctrl+Alt+U            Unpin the command target.
;
; Every selected command is copied to the clipboard first. Depending on the
; selected send mode, the command is then pasted or pasted and executed in the
; console window that invoked the menu, the pinned target, or the last console.
; ============================================================================

SendMode("Input")
SetWorkingDir(A_ScriptDir)

class ConsoleCommandMenu {
    __New() {
        ; Store persistent settings next to the script.
        this.ConfigPath := A_ScriptDir "\GlobalConsoleCommandMenu.ini"

        ; Runtime state.
        this.Mode := "Run"
        this.InvocationHwnd := 0
        this.LastConsoleHwnd := 0
        this.PinnedTargetHwnd := 0
        this.MaxHistory := 30
        this.History := []
        this.CustomCommands := []

        ; Known native console processes.
        this.ConsoleProcesses := Map(
            "windowsterminal.exe", true,
            "powershell.exe", true,
            "pwsh.exe", true,
            "cmd.exe", true,
            "conemu.exe", true,
            "conemu64.exe", true,
            "mintty.exe", true,
            "git-bash.exe", true,
            "bash.exe", true,
            "wsl.exe", true,
            "ubuntu.exe", true,
            "ubuntu2004.exe", true,
            "ubuntu2204.exe", true,
            "ubuntu2404.exe", true,
            "debian.exe", true,
            "kali.exe", true,
            "opensuse.exe", true,
            "alacritty.exe", true,
            "wezterm-gui.exe", true
        )

        this.LoadState()
        this.CommandGroups := this.CreateCommandGroups()

        ; Register global hotkeys.
        Hotkey("^!Space", ObjBindMethod(this, "ShowMenu", ""))
        Hotkey("^!+Space", ObjBindMethod(this, "ShowMenu", "Copy"))
        Hotkey("^AppsKey", ObjBindMethod(this, "ShowMenu", ""))
        Hotkey("^!r", ObjBindMethod(this, "SendClipboardToTarget", true))
        Hotkey("^!v", ObjBindMethod(this, "SendClipboardToTarget", false))
        Hotkey("^!t", ObjBindMethod(this, "PinCurrentWindow"))
        Hotkey("^!u", ObjBindMethod(this, "UnpinTarget"))

        ; Continuously remember the last native console window used.
        SetTimer(ObjBindMethod(this, "TrackActiveWindow"), 250)
        OnExit(ObjBindMethod(this, "SaveState"))

        this.Notify("Console command menu loaded. Ctrl+Alt+Space opens it.")
    }

    ; ------------------------------------------------------------------------
    ; Menu construction
    ; ------------------------------------------------------------------------

    ShowMenu(modeOverride := "", *) {
        ; Capture the window that was active before the popup menu appeared.
        this.InvocationHwnd := WinExist("A")
        this.RememberConsoleWindow(this.InvocationHwnd)

        previousMode := this.Mode
        if (modeOverride = "Run" || modeOverride = "Paste" || modeOverride = "Copy")
            this.Mode := modeOverride

        ; Rebuild before every display so history, target details, and custom
        ; commands are always current. A hotkey-supplied mode is temporary and
        ; is restored after the menu command finishes.
        this.BuildMainMenu()
        this.MainMenu.Show()
        this.Mode := previousMode
    }

    BuildMainMenu() {
        this.MainMenu := Menu()

        targetText := "Target: " this.GetTargetDescription()
        this.MainMenu.Add(this.MenuSafe(targetText), ObjBindMethod(this, "ShowTargetInformation"))

        this.MainMenu.Add("Send mode", this.BuildModeMenu())
        this.MainMenu.Add()

        for group in this.CommandGroups {
            groupMenu := Menu()
            for item in group.Items {
                menuLabel := this.MenuSafe(item.Label)
                groupMenu.Add(menuLabel, ObjBindMethod(this, "HandleCommand", item))
            }
            this.MainMenu.Add(this.MenuSafe(group.Name), groupMenu)
        }

        this.MainMenu.Add("Command history", this.BuildHistoryMenu())
        this.MainMenu.Add("Custom commands", this.BuildCustomMenu())
        this.MainMenu.Add()

        targetMenu := Menu()
        targetMenu.Add("Pin current active window", ObjBindMethod(this, "PinCurrentWindow"))
        targetMenu.Add("Unpin target window", ObjBindMethod(this, "UnpinTarget"))
        targetMenu.Add("Show target details", ObjBindMethod(this, "ShowTargetInformation"))
        this.MainMenu.Add("Target management", targetMenu)

        launchMenu := Menu()
        launchMenu.Add("Windows Terminal", ObjBindMethod(this, "LaunchApplication", "wt.exe"))
        launchMenu.Add("PowerShell 7", ObjBindMethod(this, "LaunchApplication", "pwsh.exe"))
        launchMenu.Add("Windows PowerShell", ObjBindMethod(this, "LaunchApplication", "powershell.exe"))
        launchMenu.Add("Command Prompt", ObjBindMethod(this, "LaunchApplication", "cmd.exe"))
        launchMenu.Add("WSL default distribution", ObjBindMethod(this, "LaunchApplication", "wsl.exe"))
        this.MainMenu.Add("Open console", launchMenu)

        this.MainMenu.Add("Explorer workspace manager", OpenExplorerWorkspaceManager)
        this.MainMenu.Add("Hotkey reference", ObjBindMethod(this, "ShowHotkeyReference"))
        this.MainMenu.Add("Exit command menu", (*) => ExitApp())
    }

    BuildModeMenu() {
        modeMenu := Menu()
        modeMenu.Add("Paste + Enter", ObjBindMethod(this, "SetMode", "Run", true))
        modeMenu.Add("Paste only", ObjBindMethod(this, "SetMode", "Paste", true))
        modeMenu.Add("Copy only", ObjBindMethod(this, "SetMode", "Copy", true))

        switch this.Mode {
            case "Run":
                modeMenu.Check("Paste + Enter")
            case "Paste":
                modeMenu.Check("Paste only")
            case "Copy":
                modeMenu.Check("Copy only")
        }

        return modeMenu
    }

    BuildHistoryMenu() {
        historyMenu := Menu()

        if (this.History.Length = 0) {
            historyMenu.Add("(No command history)", (*) => 0)
            historyMenu.Disable("(No command history)")
            return historyMenu
        }

        for index, command in this.History {
            display := index ". " this.Truncate(command, 90)
            historyMenu.Add(this.MenuSafe(display), ObjBindMethod(this, "ExecuteCommand", command))
        }

        historyMenu.Add()
        historyMenu.Add("Clear history", ObjBindMethod(this, "ClearHistory"))
        return historyMenu
    }

    BuildCustomMenu() {
        customMenu := Menu()
        customMenu.Add("Add custom command...", ObjBindMethod(this, "AddCustomCommand"))

        if (this.CustomCommands.Length > 0) {
            customMenu.Add()

            runMenu := Menu()
            editMenu := Menu()
            deleteMenu := Menu()

            for index, item in this.CustomCommands {
                numberedLabel := index ". " item.Label
                safeLabel := this.MenuSafe(numberedLabel)
                runMenu.Add(safeLabel, ObjBindMethod(this, "ExecuteCommand", item.Command))
                editMenu.Add(safeLabel, ObjBindMethod(this, "EditCustomCommand", index))
                deleteMenu.Add(safeLabel, ObjBindMethod(this, "DeleteCustomCommand", index))
            }

            customMenu.Add("Run custom command", runMenu)
            customMenu.Add("Edit custom command", editMenu)
            customMenu.Add("Delete custom command", deleteMenu)
        }

        return customMenu
    }

    ; ------------------------------------------------------------------------
    ; Command execution and target selection
    ; ------------------------------------------------------------------------

    HandleCommand(item, *) {
        command := ""

        if item.HasOwnProp("Builder")
            command := item.Builder.Call()
        else if item.HasOwnProp("Command")
            command := item.Command

        if (command = "")
            return

        this.ExecuteCommand(command)
    }

    ExecuteCommand(command, *) {
        command := Trim(command)
        if (command = "")
            return

        ; The clipboard always receives the selected command, regardless of mode.
        A_Clipboard := command
        ClipWait(0.75)
        this.AddHistory(command)

        if (this.Mode = "Copy") {
            this.Notify("Copied: " this.Truncate(command, 100))
            return
        }

        targetHwnd := this.ResolveTargetWindow()
        if !targetHwnd
            targetHwnd := this.OpenDefaultConsole()

        if !targetHwnd {
            MsgBox(
                "The command was copied, but no console target could be found or opened.`n`n"
                command,
                "Console Command Menu",
                "Icon!"
            )
            return
        }

        if !this.ActivateTarget(targetHwnd) {
            MsgBox(
                "The command was copied, but AutoHotkey could not activate the target window.`n`n"
                "This commonly occurs when the console is elevated and the script is not.",
                "Console Command Menu",
                "Icon!"
            )
            return
        }

        Send("^v")
        if (this.Mode = "Run") {
            Sleep(60)
            Send("{Enter}")
        }
    }

    SendClipboardToTarget(pressEnter, *) {
        if (A_Clipboard = "") {
            this.Notify("Clipboard is empty.")
            return
        }

        this.InvocationHwnd := WinExist("A")
        this.RememberConsoleWindow(this.InvocationHwnd)

        targetHwnd := this.ResolveTargetWindow()
        if !targetHwnd
            targetHwnd := this.OpenDefaultConsole()

        if !targetHwnd || !this.ActivateTarget(targetHwnd) {
            this.Notify("No usable command target was found.")
            return
        }

        Send("^v")
        if pressEnter {
            Sleep(60)
            Send("{Enter}")
        }
    }

    ResolveTargetWindow() {
        ; A manually pinned target always wins.
        if this.IsUsableWindow(this.PinnedTargetHwnd)
            return this.PinnedTargetHwnd

        ; Prefer the exact native console that invoked the menu.
        if this.IsUsableWindow(this.InvocationHwnd) && this.IsInvocationTarget(this.InvocationHwnd)
            return this.InvocationHwnd

        ; Otherwise use the most recently active native console.
        if this.IsUsableWindow(this.LastConsoleHwnd)
            return this.LastConsoleHwnd

        return 0
    }

    ActivateTarget(hwnd) {
        if !this.IsUsableWindow(hwnd)
            return false

        try {
            WinActivate("ahk_id " hwnd)
            if !WinWaitActive("ahk_id " hwnd, , 2)
                return false
            Sleep(100)
            return true
        } catch {
            return false
        }
    }

    OpenDefaultConsole() {
        ; Prefer Windows Terminal. Fall back to Windows PowerShell.
        try {
            Run("wt.exe")
            if WinWaitActive("ahk_exe WindowsTerminal.exe", , 3) {
                hwnd := WinExist("A")
                this.LastConsoleHwnd := hwnd
                return hwnd
            }
        } catch {
            ; Continue to the fallback below.
        }

        try {
            Run("powershell.exe", , , &pid)
            if WinWaitActive("ahk_pid " pid, , 3) {
                hwnd := WinExist("A")
                this.LastConsoleHwnd := hwnd
                return hwnd
            }
        } catch {
            return 0
        }

        return 0
    }

    TrackActiveWindow(*) {
        hwnd := WinExist("A")
        this.RememberConsoleWindow(hwnd)
    }

    RememberConsoleWindow(hwnd) {
        if !this.IsUsableWindow(hwnd)
            return

        if this.IsNativeConsole(hwnd)
            this.LastConsoleHwnd := hwnd
    }

    IsNativeConsole(hwnd) {
        if !this.IsUsableWindow(hwnd)
            return false

        try {
            processName := StrLower(WinGetProcessName("ahk_id " hwnd))
            windowClass := StrLower(WinGetClass("ahk_id " hwnd))
        } catch {
            return false
        }

        if this.ConsoleProcesses.Has(processName)
            return true

        return (
            windowClass = "consolewindowclass"
            || windowClass = "cascadia_hosting_window_class"
            || InStr(windowClass, "mintty")
            || InStr(windowClass, "virtualconsole")
        )
    }

    IsInvocationTarget(hwnd) {
        return this.IsNativeConsole(hwnd)
    }

    IsUsableWindow(hwnd) {
        return hwnd && WinExist("ahk_id " hwnd)
    }

    PinCurrentWindow(*) {
        hwnd := WinExist("A")
        if !this.IsUsableWindow(hwnd) {
            this.Notify("No active window could be pinned.")
            return
        }

        this.PinnedTargetHwnd := hwnd
        this.SaveState()
        this.Notify("Pinned target: " this.DescribeWindow(hwnd))
    }

    UnpinTarget(*) {
        this.PinnedTargetHwnd := 0
        this.SaveState()
        this.Notify("Pinned target cleared.")
    }

    GetTargetDescription() {
        target := this.ResolveTargetWindow()
        if !target
            return "none; a new terminal will open"

        if (target = this.PinnedTargetHwnd)
            return "PINNED - " this.DescribeWindow(target)

        if (target = this.InvocationHwnd)
            return "calling window - " this.DescribeWindow(target)

        return "last console - " this.DescribeWindow(target)
    }

    DescribeWindow(hwnd) {
        if !this.IsUsableWindow(hwnd)
            return "unavailable"

        try {
            title := WinGetTitle("ahk_id " hwnd)
            processName := WinGetProcessName("ahk_id " hwnd)
            if (title = "")
                title := "Untitled"
            return processName " | " this.Truncate(title, 70)
        } catch {
            return "unavailable"
        }
    }

    ShowTargetInformation(*) {
        target := this.ResolveTargetWindow()
        pinned := (
            this.IsUsableWindow(this.PinnedTargetHwnd)
            ? this.DescribeWindow(this.PinnedTargetHwnd)
            : "None"
        )
        lastConsole := (
            this.IsUsableWindow(this.LastConsoleHwnd)
            ? this.DescribeWindow(this.LastConsoleHwnd)
            : "None"
        )
        invocation := (
            this.IsUsableWindow(this.InvocationHwnd)
            ? this.DescribeWindow(this.InvocationHwnd)
            : "None"
        )
        resolved := target ? this.DescribeWindow(target) : "A new terminal will be opened"

        MsgBox(
            "Resolved target:`n" resolved "`n`n"
            "Pinned target:`n" pinned "`n`n"
            "Calling window:`n" invocation "`n`n"
            "Last native console:`n" lastConsole,
            "Console Target Information"
        )
    }

    ; ------------------------------------------------------------------------
    ; Mode, history, custom commands, and persistence
    ; ------------------------------------------------------------------------

    SetMode(mode, save := true, *) {
        if !(mode = "Run" || mode = "Paste" || mode = "Copy")
            return

        this.Mode := mode
        if save
            this.SaveState()

        modeText := mode = "Run" ? "Paste + Enter" : mode = "Paste" ? "Paste only" : "Copy only"
        this.Notify("Send mode: " modeText)
    }

    AddHistory(command) {
        ; Remove an older duplicate so the newest use appears first.
        duplicateIndex := 0
        for index, oldCommand in this.History {
            if (oldCommand = command) {
                duplicateIndex := index
                break
            }
        }

        if duplicateIndex
            this.History.RemoveAt(duplicateIndex)

        this.History.InsertAt(1, command)

        while (this.History.Length > this.MaxHistory)
            this.History.Pop()

        this.SaveHistory()
    }

    ClearHistory(*) {
        this.History := []
        this.SaveHistory()
        this.Notify("Command history cleared.")
    }

    AddCustomCommand(*) {
        labelResult := InputBox(
            "Enter the menu label for the new command.",
            "Add Custom Command",
            "w520 h150"
        )
        if (labelResult.Result != "OK" || Trim(labelResult.Value) = "")
            return

        commandResult := InputBox(
            "Enter the exact command to copy, paste, or run.",
            "Add Custom Command",
            "w700 h180"
        )
        if (commandResult.Result != "OK" || Trim(commandResult.Value) = "")
            return

        this.CustomCommands.Push({
            Label: Trim(labelResult.Value),
            Command: Trim(commandResult.Value)
        })
        this.SaveCustomCommands()
        this.Notify("Custom command added.")
    }

    EditCustomCommand(index, *) {
        if (index < 1 || index > this.CustomCommands.Length)
            return

        item := this.CustomCommands[index]

        labelResult := InputBox(
            "Edit the menu label.",
            "Edit Custom Command",
            "w520 h150",
            item.Label
        )
        if (labelResult.Result != "OK" || Trim(labelResult.Value) = "")
            return

        commandResult := InputBox(
            "Edit the exact command.",
            "Edit Custom Command",
            "w700 h180",
            item.Command
        )
        if (commandResult.Result != "OK" || Trim(commandResult.Value) = "")
            return

        this.CustomCommands[index] := {
            Label: Trim(labelResult.Value),
            Command: Trim(commandResult.Value)
        }
        this.SaveCustomCommands()
        this.Notify("Custom command updated.")
    }

    DeleteCustomCommand(index, *) {
        if (index < 1 || index > this.CustomCommands.Length)
            return

        item := this.CustomCommands[index]
        answer := MsgBox(
            "Delete this custom command?`n`n" item.Label "`n" item.Command,
            "Delete Custom Command",
            "YesNo Icon?"
        )
        if (answer != "Yes")
            return

        this.CustomCommands.RemoveAt(index)
        this.SaveCustomCommands()
        this.Notify("Custom command deleted.")
    }

    LoadState() {
        this.Mode := IniRead(this.ConfigPath, "Settings", "Mode", "Run")
        if !(this.Mode = "Run" || this.Mode = "Paste" || this.Mode = "Copy")
            this.Mode := "Run"

        ; A window handle is only reusable while the same window still exists.
        savedPinned := IniRead(this.ConfigPath, "Settings", "PinnedTargetHwnd", "0") + 0
        this.PinnedTargetHwnd := WinExist("ahk_id " savedPinned) ? savedPinned : 0

        this.LoadHistory()
        this.LoadCustomCommands()
    }

    SaveState(*) {
        IniWrite(this.Mode, this.ConfigPath, "Settings", "Mode")
        IniWrite(this.PinnedTargetHwnd, this.ConfigPath, "Settings", "PinnedTargetHwnd")
        this.SaveHistory()
        this.SaveCustomCommands()
    }

    LoadHistory() {
        this.History := []
        count := IniRead(this.ConfigPath, "History", "Count", "0") + 0

        Loop Min(count, this.MaxHistory) {
            command := IniRead(this.ConfigPath, "History", "Command" A_Index, "")
            if (command != "")
                this.History.Push(command)
        }
    }

    SaveHistory() {
        try IniDelete(this.ConfigPath, "History")
        catch {
            ; The section may not exist yet.
        }

        IniWrite(this.History.Length, this.ConfigPath, "History", "Count")
        for index, command in this.History
            IniWrite(command, this.ConfigPath, "History", "Command" index)
    }

    LoadCustomCommands() {
        this.CustomCommands := []
        count := IniRead(this.ConfigPath, "Custom", "Count", "0") + 0

        Loop count {
            label := IniRead(this.ConfigPath, "Custom", "Label" A_Index, "")
            command := IniRead(this.ConfigPath, "Custom", "Command" A_Index, "")
            if (label != "" && command != "")
                this.CustomCommands.Push({Label: label, Command: command})
        }
    }

    SaveCustomCommands() {
        try IniDelete(this.ConfigPath, "Custom")
        catch {
            ; The section may not exist yet.
        }

        IniWrite(this.CustomCommands.Length, this.ConfigPath, "Custom", "Count")
        for index, item in this.CustomCommands {
            IniWrite(item.Label, this.ConfigPath, "Custom", "Label" index)
            IniWrite(item.Command, this.ConfigPath, "Custom", "Command" index)
        }
    }

    ; ------------------------------------------------------------------------
    ; Dynamic command builders
    ; ------------------------------------------------------------------------

    PromptValue(title, prompt, defaultValue := "") {
        result := InputBox(prompt, title, "w650 h170", defaultValue)
        if (result.Result != "OK")
            return ""
        return Trim(result.Value)
    }

    QuoteArgument(value) {
        ; Replace embedded double quotes to keep generated commands well formed.
        clean := StrReplace(value, Chr(34), "'")
        return Chr(34) clean Chr(34)
    }

    BuildPipInstall() {
        packages := this.PromptValue("pip install", "Package name or space-separated package names:")
        return packages = "" ? "" : "python -m pip install " packages
    }

    BuildPipUninstall() {
        packages := this.PromptValue("pip uninstall", "Package name or space-separated package names:")
        return packages = "" ? "" : "python -m pip uninstall " packages
    }

    BuildPipUpgrade() {
        packages := this.PromptValue("pip upgrade", "Package name or space-separated package names:")
        return packages = "" ? "" : "python -m pip install --upgrade " packages
    }

    BuildPythonRunFile() {
        selectedFile := FileSelect(1, A_WorkingDir, "Select Python script", "Python scripts (*.py)")
        return selectedFile = "" ? "" : "python " this.QuoteArgument(selectedFile)
    }

    BuildPythonModule() {
        moduleName := this.PromptValue("Run Python module", "Module name, for example http.server or pip:")
        return moduleName = "" ? "" : "python -m " moduleName
    }

    BuildGitClone() {
        repository := this.PromptValue("git clone", "Repository URL or GitHub owner/repository:")
        return repository = "" ? "" : "git clone " repository
    }

    BuildGitCommit() {
        message := this.PromptValue("git commit", "Commit message:")
        return message = "" ? "" : "git commit -m " this.QuoteArgument(message)
    }

    BuildGitSwitch() {
        branch := this.PromptValue("git switch", "Existing branch name:")
        return branch = "" ? "" : "git switch " branch
    }

    BuildGitNewBranch() {
        branch := this.PromptValue("New Git branch", "New branch name:")
        return branch = "" ? "" : "git switch -c " branch
    }

    BuildGitDeleteBranch() {
        branch := this.PromptValue("Delete Git branch", "Local branch name to delete:")
        return branch = "" ? "" : "git branch -d " branch
    }

    BuildGitRemoteAdd() {
        remote := this.PromptValue("Add Git remote", "Enter remote name and URL, for example:`norigin https://github.com/user/repo.git")
        return remote = "" ? "" : "git remote add " remote
    }

    BuildGitSetUpstream() {
        branch := this.PromptValue("Set upstream branch", "Branch name to push and track:")
        return branch = "" ? "" : "git push -u origin " branch
    }

    BuildGhRepoClone() {
        repository := this.PromptValue("gh repo clone", "GitHub owner/repository:")
        return repository = "" ? "" : "gh repo clone " repository
    }

    BuildGhPrCheckout() {
        number := this.PromptValue("gh pr checkout", "Pull request number, URL, or branch:")
        return number = "" ? "" : "gh pr checkout " number
    }

    BuildGhPrView() {
        number := this.PromptValue("gh pr view", "Pull request number or URL. Leave blank for the current branch:")
        return number = "" ? "gh pr view --web" : "gh pr view " number " --web"
    }

    BuildGhIssueView() {
        number := this.PromptValue("gh issue view", "Issue number or URL:")
        return number = "" ? "" : "gh issue view " number " --web"
    }

    BuildGhRunWatch() {
        runId := this.PromptValue("gh run watch", "Workflow run ID. Leave blank to select interactively:")
        return runId = "" ? "gh run watch" : "gh run watch " runId
    }

    BuildWslLaunchDistro() {
        distro := this.PromptValue("Launch WSL distribution", "Distribution name exactly as shown by wsl --list --verbose:")
        return distro = "" ? "" : "wsl -d " this.QuoteArgument(distro)
    }

    BuildWslSetDefault() {
        distro := this.PromptValue("Set default WSL distribution", "Distribution name exactly as shown by wsl --list --verbose:")
        return distro = "" ? "" : "wsl --set-default " this.QuoteArgument(distro)
    }

    BuildWslTerminate() {
        distro := this.PromptValue("Terminate WSL distribution", "Distribution name exactly as shown by wsl --list --verbose:")
        return distro = "" ? "" : "wsl --terminate " this.QuoteArgument(distro)
    }

    BuildPowerShellTestConnection() {
        host := this.PromptValue("Test connection", "Host name or IP address:", "8.8.8.8")
        return host = "" ? "" : "Test-Connection " host " -Count 4"
    }

    BuildPowerShellPortTest() {
        endpoint := this.PromptValue("Test TCP port", "Enter host and port separated by a space, for example:`n192.168.1.50 80")
        if (endpoint = "")
            return ""

        parts := StrSplit(endpoint, A_Space)
        if (parts.Length < 2) {
            MsgBox("Enter both a host and a port.", "Test TCP Port", "Icon!")
            return ""
        }

        return "Test-NetConnection " parts[1] " -Port " parts[2]
    }

    BuildPowerShellFindProcess() {
        processName := this.PromptValue("Find process", "Process name without .exe:")
        return processName = "" ? "" : "Get-Process -Name " processName " -ErrorAction SilentlyContinue"
    }

    BuildWingetSearch() {
        searchText := this.PromptValue("winget search", "Application or package name:")
        return searchText = "" ? "" : "winget search " this.QuoteArgument(searchText)
    }

    BuildWingetInstall() {
        packageId := this.PromptValue("winget install", "Exact package ID or search term:")
        return packageId = "" ? "" : "winget install " this.QuoteArgument(packageId)
    }

    BuildChangeDirectory() {
        folder := DirSelect(A_WorkingDir, 3, "Select the directory for Set-Location")
        return folder = "" ? "" : "Set-Location -LiteralPath " this.QuoteArgument(folder)
    }

    BuildOpenPathInExplorer() {
        folder := DirSelect(A_WorkingDir, 3, "Select a directory to open in Explorer")
        return folder = "" ? "" : "explorer.exe " this.QuoteArgument(folder)
    }

    ; ------------------------------------------------------------------------
    ; Command catalog
    ; ------------------------------------------------------------------------

    CreateCommandGroups() {
        groups := []

        pythonItems := []
        pythonItems.Push({Label: "Python version  |  python --version", Command: "python --version"})
        pythonItems.Push({Label: "Python launcher installations  |  py -0p", Command: "py -0p"})
        pythonItems.Push({Label: "Python executable path", Command: "python -c " Chr(34) "import sys; print(sys.executable)" Chr(34)})
        pythonItems.Push({Label: "Python environment details", Command: "python -c " Chr(34) "import platform,sys; print(platform.platform()); print(sys.version); print(sys.executable)" Chr(34)})
        pythonItems.Push({Label: "Run selected Python file...", Builder: ObjBindMethod(this, "BuildPythonRunFile")})
        pythonItems.Push({Label: "Run Python module...", Builder: ObjBindMethod(this, "BuildPythonModule")})
        pythonItems.Push({Label: "Create .venv", Command: "python -m venv .venv"})
        pythonItems.Push({Label: "Activate .venv - PowerShell", Command: ".\.venv\Scripts\Activate.ps1"})
        pythonItems.Push({Label: "Activate .venv - CMD", Command: ".venv\Scripts\activate.bat"})
        pythonItems.Push({Label: "Activate .venv - WSL/Linux", Command: "source .venv/bin/activate"})
        pythonItems.Push({Label: "Deactivate virtual environment", Command: "deactivate"})
        pythonItems.Push({Label: "pip version", Command: "python -m pip --version"})
        pythonItems.Push({Label: "pip list", Command: "python -m pip list"})
        pythonItems.Push({Label: "pip list outdated", Command: "python -m pip list --outdated"})
        pythonItems.Push({Label: "pip dependency check", Command: "python -m pip check"})
        pythonItems.Push({Label: "pip install...", Builder: ObjBindMethod(this, "BuildPipInstall")})
        pythonItems.Push({Label: "pip uninstall...", Builder: ObjBindMethod(this, "BuildPipUninstall")})
        pythonItems.Push({Label: "pip upgrade package...", Builder: ObjBindMethod(this, "BuildPipUpgrade")})
        pythonItems.Push({Label: "Upgrade pip", Command: "python -m pip install --upgrade pip"})
        pythonItems.Push({Label: "Freeze requirements.txt", Command: "python -m pip freeze > requirements.txt"})
        pythonItems.Push({Label: "Install requirements.txt", Command: "python -m pip install -r requirements.txt"})
        pythonItems.Push({Label: "Compile current directory", Command: "python -m compileall ."})
        pythonItems.Push({Label: "Start HTTP server on port 8000", Command: "python -m http.server 8000"})
        groups.Push({Name: "Python", Items: pythonItems})

        gitItems := []
        gitItems.Push({Label: "Status", Command: "git status"})
        gitItems.Push({Label: "Initialize repository", Command: "git init"})
        gitItems.Push({Label: "Clone repository...", Builder: ObjBindMethod(this, "BuildGitClone")})
        gitItems.Push({Label: "Add all changes", Command: "git add -A"})
        gitItems.Push({Label: "Commit staged changes...", Builder: ObjBindMethod(this, "BuildGitCommit")})
        gitItems.Push({Label: "Pull with rebase", Command: "git pull --rebase"})
        gitItems.Push({Label: "Push", Command: "git push"})
        gitItems.Push({Label: "Push and set upstream...", Builder: ObjBindMethod(this, "BuildGitSetUpstream")})
        gitItems.Push({Label: "Fetch all and prune", Command: "git fetch --all --prune"})
        gitItems.Push({Label: "List branches", Command: "git branch --all --verbose"})
        gitItems.Push({Label: "Switch branch...", Builder: ObjBindMethod(this, "BuildGitSwitch")})
        gitItems.Push({Label: "Create and switch branch...", Builder: ObjBindMethod(this, "BuildGitNewBranch")})
        gitItems.Push({Label: "Delete local branch safely...", Builder: ObjBindMethod(this, "BuildGitDeleteBranch")})
        gitItems.Push({Label: "Compact graph log", Command: "git log --graph --decorate --oneline --all"})
        gitItems.Push({Label: "Last 20 commits", Command: "git log -20 --date=short --pretty=format:" Chr(34) "%h %ad %an %s" Chr(34)})
        gitItems.Push({Label: "Working-tree diff", Command: "git diff"})
        gitItems.Push({Label: "Staged diff", Command: "git diff --staged"})
        gitItems.Push({Label: "List remotes", Command: "git remote -v"})
        gitItems.Push({Label: "Add remote...", Builder: ObjBindMethod(this, "BuildGitRemoteAdd")})
        gitItems.Push({Label: "Repository root path", Command: "git rev-parse --show-toplevel"})
        gitItems.Push({Label: "Current branch name", Command: "git branch --show-current"})
        gitItems.Push({Label: "List tracked files", Command: "git ls-files"})
        gitItems.Push({Label: "Show global configuration", Command: "git config --global --list"})
        gitItems.Push({Label: "Clean preview - does not delete", Command: "git clean -ndx"})
        groups.Push({Name: "Git", Items: gitItems})

        ghItems := []
        ghItems.Push({Label: "GitHub CLI version", Command: "gh --version"})
        ghItems.Push({Label: "Authentication status", Command: "gh auth status"})
        ghItems.Push({Label: "Interactive authentication", Command: "gh auth login"})
        ghItems.Push({Label: "Open repository in browser", Command: "gh repo view --web"})
        ghItems.Push({Label: "Clone repository...", Builder: ObjBindMethod(this, "BuildGhRepoClone")})
        ghItems.Push({Label: "Repository details", Command: "gh repo view"})
        ghItems.Push({Label: "Pull request status", Command: "gh pr status"})
        ghItems.Push({Label: "List pull requests", Command: "gh pr list"})
        ghItems.Push({Label: "Checkout pull request...", Builder: ObjBindMethod(this, "BuildGhPrCheckout")})
        ghItems.Push({Label: "Create pull request in browser", Command: "gh pr create --web"})
        ghItems.Push({Label: "View pull request in browser...", Builder: ObjBindMethod(this, "BuildGhPrView")})
        ghItems.Push({Label: "List issues", Command: "gh issue list"})
        ghItems.Push({Label: "Create issue in browser", Command: "gh issue create --web"})
        ghItems.Push({Label: "View issue in browser...", Builder: ObjBindMethod(this, "BuildGhIssueView")})
        ghItems.Push({Label: "List workflow runs", Command: "gh run list"})
        ghItems.Push({Label: "Watch workflow run...", Builder: ObjBindMethod(this, "BuildGhRunWatch")})
        ghItems.Push({Label: "List workflows", Command: "gh workflow list"})
        ghItems.Push({Label: "Browse repository interactively", Command: "gh browse"})
        groups.Push({Name: "GitHub CLI - gh", Items: ghItems})

        wslItems := []
        wslItems.Push({Label: "WSL version", Command: "wsl --version"})
        wslItems.Push({Label: "WSL status", Command: "wsl --status"})
        wslItems.Push({Label: "List installed distributions", Command: "wsl --list --verbose"})
        wslItems.Push({Label: "List available distributions", Command: "wsl --list --online"})
        wslItems.Push({Label: "Launch default distribution", Command: "wsl"})
        wslItems.Push({Label: "Launch distribution...", Builder: ObjBindMethod(this, "BuildWslLaunchDistro")})
        wslItems.Push({Label: "Set default distribution...", Builder: ObjBindMethod(this, "BuildWslSetDefault")})
        wslItems.Push({Label: "Terminate distribution...", Builder: ObjBindMethod(this, "BuildWslTerminate")})
        wslItems.Push({Label: "Update WSL", Command: "wsl --update"})
        wslItems.Push({Label: "Shut down all WSL instances", Command: "wsl --shutdown"})
        wslItems.Push({Label: "Linux identity and kernel", Command: "wsl -- bash -lc " Chr(34) "whoami; uname -a" Chr(34)})
        wslItems.Push({Label: "Linux IP addresses", Command: "wsl -- bash -lc " Chr(34) "ip -brief address" Chr(34)})
        wslItems.Push({Label: "Linux routing table", Command: "wsl -- bash -lc " Chr(34) "ip route" Chr(34)})
        wslItems.Push({Label: "Linux disk usage", Command: "wsl -- bash -lc " Chr(34) "df -h" Chr(34)})
        wslItems.Push({Label: "Linux memory usage", Command: "wsl -- bash -lc " Chr(34) "free -h" Chr(34)})
        wslItems.Push({Label: "Failed systemd services", Command: "wsl -- bash -lc " Chr(34) "systemctl --failed --no-pager" Chr(34)})
        wslItems.Push({Label: "Listening Linux ports", Command: "wsl -- bash -lc " Chr(34) "ss -tulpn" Chr(34)})
        wslItems.Push({Label: "Convert current Windows path to WSL", Command: "wsl wslpath " Chr(34) "%CD%" Chr(34)})
        groups.Push({Name: "WSL", Items: wslItems})

        powershellItems := []
        powershellItems.Push({Label: "PowerShell version table", Command: "$PSVersionTable"})
        powershellItems.Push({Label: "Current location", Command: "Get-Location"})
        powershellItems.Push({Label: "Change directory...", Builder: ObjBindMethod(this, "BuildChangeDirectory")})
        powershellItems.Push({Label: "List all items", Command: "Get-ChildItem -Force"})
        powershellItems.Push({Label: "Largest 25 files under current directory", Command: "Get-ChildItem -File -Recurse -ErrorAction SilentlyContinue | Sort-Object Length -Descending | Select-Object -First 25 FullName,@{N='MB';E={[math]::Round($_.Length/1MB,2)}}"})
        powershellItems.Push({Label: "Largest 25 folders under current directory", Command: "Get-ChildItem -Directory | ForEach-Object { $s=(Get-ChildItem $_.FullName -File -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum; [pscustomobject]@{Folder=$_.FullName;GB=[math]::Round($s/1GB,3)} } | Sort-Object GB -Descending | Select-Object -First 25"})
        powershellItems.Push({Label: "Find Python executables", Command: "Get-Command python,py -All -ErrorAction SilentlyContinue | Select-Object Name,Source,Version"})
        powershellItems.Push({Label: "Find Git and gh executables", Command: "Get-Command git,gh -All -ErrorAction SilentlyContinue | Select-Object Name,Source,Version"})
        powershellItems.Push({Label: "List processes by CPU", Command: "Get-Process | Sort-Object CPU -Descending | Select-Object -First 30 Name,Id,CPU,WorkingSet"})
        powershellItems.Push({Label: "Find process by name...", Builder: ObjBindMethod(this, "BuildPowerShellFindProcess")})
        powershellItems.Push({Label: "IP configuration", Command: "Get-NetIPConfiguration"})
        powershellItems.Push({Label: "IP addresses", Command: "Get-NetIPAddress | Sort-Object InterfaceAlias,AddressFamily"})
        powershellItems.Push({Label: "TCP connections", Command: "Get-NetTCPConnection | Sort-Object State,LocalPort"})
        powershellItems.Push({Label: "Test host connection...", Builder: ObjBindMethod(this, "BuildPowerShellTestConnection")})
        powershellItems.Push({Label: "Test TCP port...", Builder: ObjBindMethod(this, "BuildPowerShellPortTest")})
        powershellItems.Push({Label: "Execution policy list", Command: "Get-ExecutionPolicy -List"})
        powershellItems.Push({Label: "Environment variables", Command: "Get-ChildItem Env: | Sort-Object Name"})
        powershellItems.Push({Label: "PowerShell command history", Command: "Get-History"})
        powershellItems.Push({Label: "Clear console", Command: "Clear-Host"})
        powershellItems.Push({Label: "Open current directory in Explorer", Command: "explorer.exe ."})
        powershellItems.Push({Label: "Open selected directory in Explorer...", Builder: ObjBindMethod(this, "BuildOpenPathInExplorer")})
        powershellItems.Push({Label: "Open current directory in VS Code", Command: "code ."})
        groups.Push({Name: "PowerShell and Terminal", Items: powershellItems})

        packageItems := []
        packageItems.Push({Label: "winget version", Command: "winget --version"})
        packageItems.Push({Label: "winget search...", Builder: ObjBindMethod(this, "BuildWingetSearch")})
        packageItems.Push({Label: "winget install...", Builder: ObjBindMethod(this, "BuildWingetInstall")})
        packageItems.Push({Label: "List installed winget packages", Command: "winget list"})
        packageItems.Push({Label: "List available upgrades", Command: "winget upgrade"})
        packageItems.Push({Label: "Upgrade all packages", Command: "winget upgrade --all"})
        packageItems.Push({Label: "Chocolatey version", Command: "choco --version"})
        packageItems.Push({Label: "Chocolatey outdated packages", Command: "choco outdated"})
        packageItems.Push({Label: "Scoop status", Command: "scoop status"})
        packageItems.Push({Label: "Scoop update", Command: "scoop update"})
        groups.Push({Name: "Package managers", Items: packageItems})

        diagnosticsItems := []
        diagnosticsItems.Push({Label: "Where is python?", Command: "where.exe python"})
        diagnosticsItems.Push({Label: "Where is git?", Command: "where.exe git"})
        diagnosticsItems.Push({Label: "Where is gh?", Command: "where.exe gh"})
        diagnosticsItems.Push({Label: "System information", Command: "systeminfo"})
        diagnosticsItems.Push({Label: "Windows version", Command: "winver"})
        diagnosticsItems.Push({Label: "Detailed IP configuration", Command: "ipconfig /all"})
        diagnosticsItems.Push({Label: "Flush DNS cache", Command: "ipconfig /flushdns"})
        diagnosticsItems.Push({Label: "Routing table", Command: "route print"})
        diagnosticsItems.Push({Label: "Listening ports and owning PIDs", Command: "netstat -ano | findstr LISTENING"})
        diagnosticsItems.Push({Label: "DNS lookup for github.com", Command: "nslookup github.com"})
        diagnosticsItems.Push({Label: "Trace route to github.com", Command: "tracert github.com"})
        diagnosticsItems.Push({Label: "Disk volumes", Command: "Get-Volume | Sort-Object DriveLetter"})
        diagnosticsItems.Push({Label: "Physical disks", Command: "Get-PhysicalDisk | Format-Table -AutoSize"})
        diagnosticsItems.Push({Label: "Recent system errors", Command: "Get-WinEvent -FilterHashtable @{LogName='System';Level=2} -MaxEvents 30 | Format-List TimeCreated,ProviderName,Id,Message"})
        diagnosticsItems.Push({Label: "Recent application errors", Command: "Get-WinEvent -FilterHashtable @{LogName='Application';Level=2} -MaxEvents 30 | Format-List TimeCreated,ProviderName,Id,Message"})
        groups.Push({Name: "Windows diagnostics", Items: diagnosticsItems})

        return groups
    }

    ; ------------------------------------------------------------------------
    ; Utility functions
    ; ------------------------------------------------------------------------

    LaunchApplication(command, *) {
        try Run(command)
        catch as err
            MsgBox("Could not launch:`n" command "`n`n" err.Message, "Launch Failed", "Icon!")
    }

    ShowHotkeyReference(*) {
        MsgBox(
            "Ctrl+Alt+Space`n"
            "Open the command menu with the current send mode.`n`n"
            "Ctrl+Alt+Shift+Space`n"
            "Open the command menu in Copy Only mode.`n`n"
            "Ctrl+AppsKey`n"
            "Open the command menu using the keyboard context-menu key.`n`n"
            "Ctrl+Alt+R`n"
            "Paste the current clipboard into the target and press Enter.`n`n"
            "Ctrl+Alt+V`n"
            "Paste the current clipboard into the target without Enter.`n`n"
            "Ctrl+Alt+T`n"
            "Pin the currently active window as the target. Use this for VS Code or another integrated terminal.`n`n"
            "Ctrl+Alt+U`n"
            "Clear the pinned target.`n`n"
            "Target priority:`n"
            "1. Pinned window`n"
            "2. Native console that opened the menu`n"
            "3. Last active native console`n"
            "4. A newly opened Windows Terminal",
            "Console Command Menu Hotkeys"
        )
    }

    Notify(message) {
        ToolTip(message)
        SetTimer((*) => ToolTip(), -1800)
    }

    Truncate(text, maxLength) {
        if (StrLen(text) <= maxLength)
            return text
        return SubStr(text, 1, maxLength - 1) "â€¦"
    }

    MenuSafe(text) {
        ; A single ampersand marks a menu accelerator, so double it for display.
        return StrReplace(text, "&", "&&")
    }
}

; Create the persistent global application object.
global ConsoleMenuApp := ConsoleCommandMenu()

; ============================================================================
; Explorer Workspace Manager
; Added to the Global Console Command Menu application.
;
; Global hotkeys:
;   Ctrl+Alt+E               Open the Explorer Workspace Manager.
;   Ctrl+Alt+Shift+E         Add the automatically detected last Explorer folder.
;   Ctrl+Alt+Win+E           Replace slots with currently open Explorer locations.
;   Ctrl+Alt+Win+T           Consolidate the 10 slots into real Explorer tabs.
;   Ctrl+Alt+PageDown/Up     Cycle all live Explorer windows and tabs.
;   Ctrl+Alt+Shift+PageDown/Up
;                             Cycle the emulated GUI browser tabs.
;
; Main capabilities:
;   - Automatic Windows event-hook and Shell COM Explorer monitoring.
;   - Sequential Explorer-folder visit timeline.
;   - A true multi-tab Explorer-emulation GUI for every live Explorer tab.
;   - Ten persistent virtual folder tabs/slots, auto-filled from Explorer.
;   - Combined virtual view across all ten paths.
;   - Forward/back cycling through real Explorer windows and Windows 11 tabs.
;   - Windows 11 Explorer-tab consolidation.
;   - Wildcard, plain-text, and regular-expression filtering.
;   - File-type filters, recursive search, and hidden-file control.
;   - Favorites, named workspace snapshots, and export/import.
;   - File operations and context actions for Explorer, Terminal, VS Code,
;     PowerShell, CMD, Python, and AutoHotkey.
;   - Project-root detection for Git, Python, Node, .NET, and VS Code projects.
;   - Persistent navigation state and automatic stale-path detection.
; ============================================================================

class ExplorerWorkspaceManager {
    __New(consoleApp := 0) {
        this.ConsoleApp := consoleApp
        this.ConfigPath := A_ScriptDir "\ExplorerWorkspaceManager.ini"
        this.MaxSlots := 10
        this.MaxVisitLog := 500
        this.MaxDisplayedItems := 10000
        this.Sequence := 0
        this.SelectedSlot := 1
        this.WorkspacePaths := []
        this.VisitLog := []
        this.Favorites := []
        this.SnapshotNames := []
        this.PathStats := Map()
        this.BackHistory := []
        this.ForwardHistory := []
        this.CurrentPath := ""
        this.ViewMode := "Folder"
        this.LastExplorerHwnd := 0
        this.LastExplorerPath := ""
        this.LastRecordedPath := ""
        this.LastOpenWindowRefresh := 0

        ; Live Explorer browser/tab state. Shell.Application may expose multiple
        ; Windows 11 tabs with the same top-level HWND, so each entry retains
        ; both its HWND and its enumerated tab ordinal.
        this.OpenExplorerEntries := []
        this.KnownOpenExplorerEntries := Map()
        this.ExplorerCycleIndex := 0
        this.LastExplorerEntriesSignature := ""
        this.BrowserTabs := []
        this.RebuildingBrowserTabs := false
        this.SelectedBrowserTabKey := ""
        this.MaxBrowserTabs := 100

        ; Explorer watcher state. The WinEvent hook reacts immediately to
        ; foreground, focus, and Explorer title changes. Shell.Application COM
        ; resolves the actual filesystem path, including Windows 11 tabs.
        this.ShellApp := 0
        this.WinEventHooks := []
        this.WinEventCallback := 0
        this.PendingExplorerHwnd := 0
        this.ExplorerPathByHwnd := Map()
        this.LastFullExplorerScanTick := 0
        this.ExplorerProbeCallback := ObjBindMethod(this, "ProbeExplorerActivity")
        this.ExplorerPollCallback := ObjBindMethod(this, "PollExplorerActivity")

        this.GuiBuilt := false
        this.RefreshTimerCallback := ObjBindMethod(this, "DeferredRefresh")

        Loop this.MaxSlots
            this.WorkspacePaths.Push("")

        this.LoadState()

        Hotkey("^!e", ObjBindMethod(this, "Show"))
        Hotkey("^!+e", ObjBindMethod(this, "AddLastExplorerPathToWorkspace"))
        Hotkey("^!#e", ObjBindMethod(this, "CaptureOpenExplorerWindowsAndShow"))
        Hotkey("^!#t", ObjBindMethod(this, "ConsolidateIntoExplorerTabs"))
        Hotkey("^!PgDn", ObjBindMethod(this, "CycleExplorerEntries", 1))
        Hotkey("^!PgUp", ObjBindMethod(this, "CycleExplorerEntries", -1))
        Hotkey("^!+PgDn", ObjBindMethod(this, "CycleBrowserTabs", 1))
        Hotkey("^!+PgUp", ObjBindMethod(this, "CycleBrowserTabs", -1))

        this.InitializeExplorerWatcher()
        SetTimer(this.ExplorerPollCallback, 350)
        OnExit(ObjBindMethod(this, "SaveState"))
        OnExit(ObjBindMethod(this, "ShutdownExplorerWatcher"))
    }

    ; ------------------------------------------------------------------------
    ; Explorer monitoring and path history
    ; ------------------------------------------------------------------------

    InitializeExplorerWatcher() {
        ; Shell.Application is Windows' native Explorer automation library.
        ; It gives each Explorer browser/tab a Document.Folder path without
        ; stealing focus or sending keystrokes to the user.
        this.GetShellApplication()

        ; SetWinEventHook supplies immediate notifications rather than relying
        ; only on a timer. Separate exact hooks avoid subscribing to every event
        ; in the large range between foreground and object-name events.
        try {
            this.WinEventCallback := CallbackCreate(
                ObjBindMethod(this, "OnExplorerWinEvent"),
                "",
                7
            )

            eventIds := [
                0x0003, ; EVENT_SYSTEM_FOREGROUND
                0x8005, ; EVENT_OBJECT_FOCUS
                0x800C  ; EVENT_OBJECT_NAMECHANGE
            ]

            for eventId in eventIds {
                hook := DllCall(
                    "SetWinEventHook",
                    "UInt", eventId,
                    "UInt", eventId,
                    "Ptr", 0,
                    "Ptr", this.WinEventCallback,
                    "UInt", 0,
                    "UInt", 0,
                    "UInt", 0x0002, ; WINEVENT_SKIPOWNPROCESS | OUTOFCONTEXT
                    "Ptr"
                )
                if hook
                    this.WinEventHooks.Push(hook)
            }
        } catch {
            ; The 350 ms foreground poll remains active as a complete fallback.
        }

        this.ProbeExplorerActivity()
    }

    ShutdownExplorerWatcher(exitReason := "", exitCode := 0, *) {
        try SetTimer(this.ExplorerPollCallback, 0)
        try SetTimer(this.ExplorerProbeCallback, 0)

        for hook in this.WinEventHooks {
            try DllCall("UnhookWinEvent", "Ptr", hook)
        }
        this.WinEventHooks := []

        if this.WinEventCallback {
            try CallbackFree(this.WinEventCallback)
            this.WinEventCallback := 0
        }
    }

    OnExplorerWinEvent(hook, eventId, hwnd, objectId, childId, eventThread, eventTime) {
        if !hwnd
            return

        ; Object focus/name notifications can originate from child controls.
        ; Resolve them to the root Explorer window before testing the class.
        try rootHwnd := DllCall("GetAncestor", "Ptr", hwnd, "UInt", 2, "Ptr")
        catch
            rootHwnd := hwnd

        if !rootHwnd
            rootHwnd := hwnd

        if !this.IsExplorerWindow(rootHwnd)
            return

        this.PendingExplorerHwnd := rootHwnd
        SetTimer(this.ExplorerProbeCallback, -25)
    }

    PollExplorerActivity(*) {
        activeHwnd := WinExist("A")
        if this.IsExplorerWindow(activeHwnd) {
            this.PendingExplorerHwnd := activeHwnd
            this.ProbeExplorerActivity()
        }

        ; A periodic full Shell scan catches windows and Windows 11 tabs that
        ; are created, closed, or navigated without a foreground transition.
        if ((A_TickCount - this.LastFullExplorerScanTick) >= 900) {
            this.RefreshOpenExplorerState()
            this.AutoMergeExplorerPathsIntoWorkspace(false)
        }
    }

    ; Compatibility entry point retained for any existing bound callbacks.
    TrackExplorerActivity(*) {
        this.ProbeExplorerActivity()
    }

    ProbeExplorerActivity(*) {
        hwnd := this.PendingExplorerHwnd
        this.PendingExplorerHwnd := 0

        if !this.IsExplorerWindow(hwnd) {
            activeHwnd := WinExist("A")
            if this.IsExplorerWindow(activeHwnd)
                hwnd := activeHwnd
        }

        if this.IsExplorerWindow(hwnd) {
            path := this.GetExplorerPathByHwnd(hwnd)
            if (path != "" && DirExist(path))
                this.UpdateLastExplorerLocation(hwnd, path, "Explorer")
        }

        if ((A_TickCount - this.LastFullExplorerScanTick) >= 1800) {
            this.RefreshOpenExplorerState()
            this.AutoMergeExplorerPathsIntoWorkspace(false)
        }
    }

    UpdateLastExplorerLocation(hwnd, path, source := "Explorer") {
        path := this.NormalizePath(path)
        if (path = "" || !DirExist(path))
            return false

        this.LastExplorerHwnd := hwnd
        this.LastExplorerPath := path
        if hwnd
            this.ExplorerPathByHwnd[hwnd] := path

        if (StrLower(path) != StrLower(this.LastRecordedPath)) {
            this.LastRecordedPath := path
            this.RecordVisitedPath(path, source)
        }

        return true
    }

    IsExplorerWindow(hwnd) {
        if !hwnd || !WinExist("ahk_id " hwnd)
            return false

        try {
            processName := StrLower(WinGetProcessName("ahk_id " hwnd))
            windowClass := WinGetClass("ahk_id " hwnd)
        } catch {
            return false
        }

        return (
            processName = "explorer.exe"
            && (windowClass = "CabinetWClass" || windowClass = "ExploreWClass")
        )
    }

    GetShellApplication() {
        if this.ShellApp {
            try {
                unusedCount := this.ShellApp.Windows.Count
                return this.ShellApp
            }
        }

        try this.ShellApp := ComObject("Shell.Application")
        catch
            this.ShellApp := 0

        return this.ShellApp
    }

    NormalizeExplorerTitle(title) {
        title := Trim(title "")
        title := RegExReplace(title, "i)\s+-\s+File Explorer$")
        return Trim(title)
    }

    GetExplorerPathByHwnd(hwnd) {
        if !this.IsExplorerWindow(hwnd)
            return ""

        shellApp := this.GetShellApplication()
        if !shellApp
            return this.ExplorerPathByHwnd.Has(hwnd) ? this.ExplorerPathByHwnd[hwnd] : ""

        candidates := []
        activeTitle := ""
        try activeTitle := this.NormalizeExplorerTitle(WinGetTitle("ahk_id " hwnd))
        activeTitleLower := StrLower(activeTitle)

        try {
            for shellWindow in shellApp.Windows {
                try {
                    if ((shellWindow.HWND + 0) != hwnd)
                        continue

                    fullName := StrLower(shellWindow.FullName "")
                    if !InStr(fullName, "explorer.exe")
                        continue

                    path := this.NormalizePath(shellWindow.Document.Folder.Self.Path "")
                    if (path = "" || !DirExist(path))
                        continue

                    locationName := Trim(shellWindow.LocationName "")
                    displayName := this.PathDisplayName(path)
                    candidates.Push({
                        Path: path,
                        LocationName: locationName,
                        DisplayName: displayName
                    })
                }
            }
        }

        if (candidates.Length = 0)
            return this.ExplorerPathByHwnd.Has(hwnd) ? this.ExplorerPathByHwnd[hwnd] : ""

        if (candidates.Length = 1) {
            this.ExplorerPathByHwnd[hwnd] := candidates[1].Path
            return candidates[1].Path
        }

        ; Windows 11 tabs can share the same top-level HWND. Match the active
        ; window caption against both Shell LocationName and the final path name.
        for candidate in candidates {
            if (
                activeTitleLower != ""
                && (
                    StrLower(candidate.LocationName) = activeTitleLower
                    || StrLower(candidate.DisplayName) = activeTitleLower
                )
            ) {
                this.ExplorerPathByHwnd[hwnd] := candidate.Path
                return candidate.Path
            }
        }

        for candidate in candidates {
            if (
                activeTitleLower != ""
                && (
                    (candidate.LocationName != "" && InStr(activeTitle, candidate.LocationName, false))
                    || (candidate.DisplayName != "" && InStr(activeTitle, candidate.DisplayName, false))
                )
            ) {
                this.ExplorerPathByHwnd[hwnd] := candidate.Path
                return candidate.Path
            }
        }

        ; Preserve the previously resolved tab when it remains among candidates.
        if this.ExplorerPathByHwnd.Has(hwnd) {
            cachedPath := this.ExplorerPathByHwnd[hwnd]
            for candidate in candidates {
                if (StrLower(candidate.Path) = StrLower(cachedPath))
                    return candidate.Path
            }
        }

        ; ShellWindows commonly enumerates the active tab last for a shared HWND.
        resolvedPath := candidates[candidates.Length].Path
        this.ExplorerPathByHwnd[hwnd] := resolvedPath
        return resolvedPath
    }

    GetOpenExplorerWindows(dedupePaths := false) {
        result := []
        seenPaths := Map()
        tabCountByHwnd := Map()
        windowOrdinalByHwnd := Map()
        nextWindowOrdinal := 0
        shellApp := this.GetShellApplication()
        if !shellApp
            return result

        try {
            for shellWindow in shellApp.Windows {
                try {
                    fullName := StrLower(shellWindow.FullName "")
                    if !InStr(fullName, "explorer.exe")
                        continue

                    hwnd := shellWindow.HWND + 0
                    if !this.IsExplorerWindow(hwnd)
                        continue

                    path := this.NormalizePath(shellWindow.Document.Folder.Self.Path "")
                    if (path = "" || !DirExist(path))
                        continue

                    pathKey := StrLower(path)
                    if dedupePaths && seenPaths.Has(pathKey)
                        continue
                    seenPaths[pathKey] := true

                    if !windowOrdinalByHwnd.Has(hwnd) {
                        nextWindowOrdinal += 1
                        windowOrdinalByHwnd[hwnd] := nextWindowOrdinal
                        tabCountByHwnd[hwnd] := 0
                    }

                    tabCountByHwnd[hwnd] += 1
                    windowOrdinal := windowOrdinalByHwnd[hwnd]
                    tabOrdinal := tabCountByHwnd[hwnd]
                    title := Trim(shellWindow.LocationName "")
                    if (title = "")
                        title := this.PathDisplayName(path)

                    entryKey := hwnd "|" tabOrdinal
                    this.ExplorerPathByHwnd[hwnd] := path
                    result.Push({
                        Key: entryKey,
                        Hwnd: hwnd,
                        Path: path,
                        Title: title,
                        WindowOrdinal: windowOrdinal,
                        TabOrdinal: tabOrdinal
                    })
                }
            }
        }

        return result
    }

    BuildExplorerEntriesSignature(entries) {
        signature := ""
        for item in entries
            signature .= item.Key "|" StrLower(item.Path) ";"
        return signature
    }

    CaptureDiscoveredExplorerEntries(entries) {
        currentlyOpen := Map()
        for item in entries {
            discoveryKey := item.Hwnd "|" StrLower(item.Path)
            currentlyOpen[discoveryKey] := true
            if !this.KnownOpenExplorerEntries.Has(discoveryKey)
                this.RecordVisitedPath(item.Path, "Explorer opened")
        }
        this.KnownOpenExplorerEntries := currentlyOpen
    }

    RefreshOpenExplorerState(*) {
        this.LastFullExplorerScanTick := A_TickCount
        windows := this.GetOpenExplorerWindows(false)
        signature := this.BuildExplorerEntriesSignature(windows)
        changed := signature != this.LastExplorerEntriesSignature

        this.OpenExplorerEntries := windows
        this.CaptureDiscoveredExplorerEntries(windows)
        this.LastExplorerEntriesSignature := signature

        if this.GuiBuilt
            this.MainGui.Title := "Explorer Workspace Manager - " windows.Length " live Explorer tab" (windows.Length = 1 ? "" : "s")

        if changed && this.GuiBuilt {
            this.RebuildBrowserTabs()
            if (this.SourceCombo.Text = "Live Explorer tabs/windows")
                this.PopulateSourceList()
        }

        if (
            this.LastExplorerHwnd
            && this.IsExplorerWindow(this.LastExplorerHwnd)
            && this.LastExplorerPath != ""
            && DirExist(this.LastExplorerPath)
        )
            return windows

        ; Use Explorer z-order to choose the most recently active surviving
        ; window when the exact foreground window is not currently Explorer.
        try explorerHwnds := WinGetList("ahk_exe explorer.exe")
        catch
            explorerHwnds := []

        for hwnd in explorerHwnds {
            if !this.IsExplorerWindow(hwnd)
                continue
            path := this.GetExplorerPathByHwnd(hwnd)
            if (path != "" && DirExist(path)) {
                this.LastExplorerHwnd := hwnd
                this.LastExplorerPath := path
                return windows
            }
        }

        if (windows.Length > 0) {
            this.LastExplorerHwnd := windows[1].Hwnd
            this.LastExplorerPath := windows[1].Path
        } else {
            this.LastExplorerHwnd := 0
        }

        return windows
    }

    ResolveLastExplorerPath(*) {
        activeHwnd := WinExist("A")
        if this.IsExplorerWindow(activeHwnd) {
            path := this.GetExplorerPathByHwnd(activeHwnd)
            if (path != "" && DirExist(path)) {
                this.UpdateLastExplorerLocation(activeHwnd, path, "Explorer")
                return path
            }
        }

        if (
            this.LastExplorerPath != ""
            && DirExist(this.LastExplorerPath)
            && this.IsExplorerWindow(this.LastExplorerHwnd)
        )
            return this.LastExplorerPath

        this.RefreshOpenExplorerState()
        if (this.LastExplorerPath != "" && DirExist(this.LastExplorerPath))
            return this.LastExplorerPath

        return ""
    }

    AutoMergeExplorerPathsIntoWorkspace(showNotification := false, *) {
        candidates := []
        seen := Map()

        lastPath := this.ResolveLastExplorerPath()
        if (lastPath != "") {
            candidates.Push(lastPath)
            seen[StrLower(lastPath)] := true
        }

        for item in this.GetOpenExplorerWindows() {
            key := StrLower(item.Path)
            if seen.Has(key)
                continue
            seen[key] := true
            candidates.Push(item.Path)
        }

        added := 0
        for path in candidates {
            if this.FindPathIndex(this.WorkspacePaths, path)
                continue

            slot := this.FindFirstEmptySlot()
            if !slot
                break

            this.WorkspacePaths[slot] := path
            added += 1
        }

        if added > 0 {
            this.SaveWorkspace()
            this.UpdateSlotButtons()
            if this.GuiBuilt
                this.PopulateSourceList()
            if showNotification
                this.Notify("Auto-added " added " Explorer folder" (added = 1 ? "" : "s") ".")
        }

        return added
    }

    RecordVisitedPath(path, source := "Explorer") {
        path := this.NormalizePath(path)
        if (path = "" || !DirExist(path))
            return

        this.Sequence += 1
        timestamp := A_Now
        this.VisitLog.InsertAt(1, {
            Seq: this.Sequence,
            Path: path,
            At: timestamp,
            Source: source
        })

        while (this.VisitLog.Length > this.MaxVisitLog)
            this.VisitLog.Pop()

        key := StrLower(path)
        if this.PathStats.Has(key) {
            stats := this.PathStats[key]
            stats.Count += 1
            stats.LastAt := timestamp
            stats.Path := path
            this.PathStats[key] := stats
        } else {
            this.PathStats[key] := {
                Path: path,
                Count: 1,
                LastAt: timestamp
            }
        }

        this.SaveHistory()

        if this.IsMainGuiVisible() {
            sourceText := this.SourceCombo.Text
            if (sourceText = "Visit timeline")
                this.PopulateSourceList()
        }
    }

    RebuildPathStats() {
        this.PathStats := Map()
        for entry in this.VisitLog {
            key := StrLower(entry.Path)
            if this.PathStats.Has(key) {
                stats := this.PathStats[key]
                stats.Count += 1
                if (entry.At > stats.LastAt)
                    stats.LastAt := entry.At
                this.PathStats[key] := stats
            } else {
                this.PathStats[key] := {
                    Path: entry.Path,
                    Count: 1,
                    LastAt: entry.At
                }
            }
        }
    }

    ; ------------------------------------------------------------------------
    ; Main GUI
    ; ------------------------------------------------------------------------

    Show(*) {
        ; No Explorer selection or pinning is required. Resolve the most recent
        ; Explorer automatically and merge all currently open locations into
        ; available workspace slots before presenting the GUI.
        this.ProbeExplorerActivity()
        this.RefreshOpenExplorerState()
        this.AutoMergeExplorerPathsIntoWorkspace(false)

        if !this.GuiBuilt
            this.BuildGui()

        this.UpdateSlotButtons()
        this.PopulateSourceList()

        if (this.CurrentPath = "") {
            initialPath := this.WorkspacePaths[this.SelectedSlot]
            if (initialPath = "" || !DirExist(initialPath))
                initialPath := this.LastExplorerPath
            if (initialPath = "" || !DirExist(initialPath))
                initialPath := A_MyDocuments
            this.NavigateTo(initialPath, false, false)
        } else {
            this.RefreshFiles()
        }

        this.MainGui.Show("w1320 h780")
        this.FilterEdit.Focus()
    }

    BuildGui() {
        this.MainGui := Gui("+Resize +MinSize1200x650", "Explorer Workspace Manager")
        this.MainGui.SetFont("s9", "Segoe UI")
        this.MainGui.OnEvent("Close", ObjBindMethod(this, "HideGui"))
        this.MainGui.OnEvent("Escape", ObjBindMethod(this, "HideGui"))
        this.MainGui.OnEvent("Size", ObjBindMethod(this, "OnGuiSize"))

        ; This is a real GUI tab strip. It combines every live Explorer tab or
        ; window with the ten persistent virtual workspace slots and a combined
        ; virtual-folder page. The file list below is the active tab's browser.
        this.BrowserTabControl := this.MainGui.Add(
            "Tab3",
            "x10 y8 w1300 h34 +Buttons",
            ["Loading Explorer tabs..."]
        )
        this.BrowserTabControl.OnEvent("Change", ObjBindMethod(this, "OnBrowserTabChanged"))
        this.BrowserTabControl.OnEvent("ContextMenu", ObjBindMethod(this, "ShowBrowserTabContextMenu"))
        this.MainGui.UseTab()

        this.BackButton := this.MainGui.Add("Button", "x10 y48 w44 h28", "Back")
        this.BackButton.OnEvent("Click", ObjBindMethod(this, "NavigateBack"))

        this.ForwardButton := this.MainGui.Add("Button", "x58 y48 w58 h28", "Forward")
        this.ForwardButton.OnEvent("Click", ObjBindMethod(this, "NavigateForward"))

        this.UpButton := this.MainGui.Add("Button", "x120 y48 w42 h28", "Up")
        this.UpButton.OnEvent("Click", ObjBindMethod(this, "NavigateUp"))

        this.RefreshButton := this.MainGui.Add("Button", "x166 y48 w58 h28", "Refresh")
        this.RefreshButton.OnEvent("Click", ObjBindMethod(this, "RefreshFiles"))

        this.AddressEdit := this.MainGui.Add("Edit", "x232 y48 w514 h28")
        this.AddressEdit.OnEvent("Focus", ObjBindMethod(this, "SelectAddressText"))

        this.GoButton := this.MainGui.Add("Button", "x752 y48 w42 h28", "Go")
        this.GoButton.OnEvent("Click", ObjBindMethod(this, "GoToAddress"))

        this.PrevLiveButton := this.MainGui.Add("Button", "x800 y48 w70 h28", "Prev Live")
        this.PrevLiveButton.OnEvent("Click", ObjBindMethod(this, "CycleExplorerEntries", -1))

        this.NextLiveButton := this.MainGui.Add("Button", "x876 y48 w70 h28", "Next Live")
        this.NextLiveButton.OnEvent("Click", ObjBindMethod(this, "CycleExplorerEntries", 1))

        this.FocusLiveButton := this.MainGui.Add("Button", "x952 y48 w76 h28", "Focus Live")
        this.FocusLiveButton.OnEvent("Click", ObjBindMethod(this, "FocusSelectedExplorerEntry"))

        this.CombinedButton := this.MainGui.Add("Button", "x1034 y48 w104 h28", "Combined View")
        this.CombinedButton.OnEvent("Click", ObjBindMethod(this, "ShowCombinedView"))

        this.RealTabsButton := this.MainGui.Add("Button", "x1144 y48 w104 h28", "Real Tabs")
        this.RealTabsButton.OnEvent("Click", ObjBindMethod(this, "ConsolidateIntoExplorerTabs"))

        this.MenuButton := this.MainGui.Add("Button", "x1254 y48 w56 h28", "More")
        this.MenuButton.OnEvent("Click", ObjBindMethod(this, "ShowWorkspaceActions"))

        this.SourceCombo := this.MainGui.Add("ComboBox", "x10 y92 w320", [
            "Visit timeline",
            "Favorites",
            "Live Explorer tabs/windows",
            "Workspace slots"
        ])
        this.SourceCombo.Choose(1)
        this.SourceCombo.OnEvent("Change", ObjBindMethod(this, "PopulateSourceList"))

        this.SourceList := this.MainGui.Add("ListView", "x10 y124 w320 h505 Grid -Multi", [
            "#", "Folder", "Path", "Visits", "Last visited"
        ])
        this.SourceList.ModifyCol(1, 62)
        this.SourceList.ModifyCol(2, 130)
        this.SourceList.ModifyCol(3, 0)
        this.SourceList.ModifyCol(4, 54)
        this.SourceList.ModifyCol(5, 105)
        this.SourceList.OnEvent("DoubleClick", ObjBindMethod(this, "OpenSourceListItem"))
        this.SourceList.OnEvent("ContextMenu", ObjBindMethod(this, "ShowSourceContextMenu"))

        this.AddActiveButton := this.MainGui.Add("Button", "x10 y636 w100 h28", "Add Last")
        this.AddActiveButton.OnEvent("Click", ObjBindMethod(this, "AddLastExplorerPathToWorkspace"))

        this.AddSelectedButton := this.MainGui.Add("Button", "x116 y636 w100 h28", "Add Selected")
        this.AddSelectedButton.OnEvent("Click", ObjBindMethod(this, "AddSelectedSourceToWorkspace"))

        this.CaptureButton := this.MainGui.Add("Button", "x222 y636 w108 h28", "Capture Open")
        this.CaptureButton.OnEvent("Click", ObjBindMethod(this, "CaptureOpenExplorerWindows"))

        this.FilterLabel := this.MainGui.Add("Text", "x346 y94 w38 h22 +0x200", "Filter")
        this.FilterEdit := this.MainGui.Add("Edit", "x386 y92 w280 h26")
        this.FilterEdit.OnEvent("Change", ObjBindMethod(this, "QueueRefresh"))

        this.TypeCombo := this.MainGui.Add("ComboBox", "x674 y92 w156", [
            "All items",
            "Folders only",
            "Python",
            "AutoHotkey",
            "All code",
            "Images",
            "Video",
            "Audio",
            "Documents",
            "Archives",
            "Executables",
            "Modified in 24 hours"
        ])
        this.TypeCombo.Choose(1)
        this.TypeCombo.OnEvent("Change", ObjBindMethod(this, "QueueRefresh"))

        this.RegexCheck := this.MainGui.Add("CheckBox", "x840 y94 w62 h22", "Regex")
        this.RegexCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))

        this.RecursiveCheck := this.MainGui.Add("CheckBox", "x908 y94 w78 h22", "Recursive")
        this.RecursiveCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))

        this.HiddenCheck := this.MainGui.Add("CheckBox", "x992 y94 w98 h22", "Show hidden")
        this.HiddenCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))

        this.FilterHelpButton := this.MainGui.Add("Button", "x1096 y90 w88 h28", "Filter Help")
        this.FilterHelpButton.OnEvent("Click", ObjBindMethod(this, "ShowFilterHelp"))

        this.ClearFilterButton := this.MainGui.Add("Button", "x1190 y90 w120 h28", "Clear Filters")
        this.ClearFilterButton.OnEvent("Click", ObjBindMethod(this, "ClearFilters"))

        this.FileList := this.MainGui.Add("ListView", "x346 y124 w964 h505 Grid AltSubmit", [
            "Name", "Type", "Size", "Modified", "Source", "Full path"
        ])
        this.FileList.ModifyCol(1, 270)
        this.FileList.ModifyCol(2, 110)
        this.FileList.ModifyCol(3, 90)
        this.FileList.ModifyCol(4, 145)
        this.FileList.ModifyCol(5, 150)
        this.FileList.ModifyCol(6, 0)
        this.FileList.OnEvent("DoubleClick", ObjBindMethod(this, "OpenFileListItem"))
        this.FileList.OnEvent("Click", ObjBindMethod(this, "UpdateSelectionDetails"))
        this.FileList.OnEvent("ItemFocus", ObjBindMethod(this, "UpdateSelectionDetails"))
        this.FileList.OnEvent("ContextMenu", ObjBindMethod(this, "ShowFileContextMenu"))

        this.DetailEdit := this.MainGui.Add("Edit", "x346 y636 w964 h88 ReadOnly -Wrap VScroll")
        this.StatusText := this.MainGui.Add("Text", "x10 y735 w1300 h24 +0x200", "Ready")

        this.GuiBuilt := true
        this.UpdateSlotButtons()
    }

    HideGui(*) {
        this.MainGui.Hide()
    }

    OnGuiSize(guiObj, minMax, width, height) {
        if (minMax = -1 || !this.GuiBuilt)
            return

        margin := 10
        leftWidth := 320
        rightX := leftWidth + 26
        rightWidth := Max(400, width - rightX - margin)
        listTop := 124
        detailHeight := 88
        statusHeight := 24
        bottomGap := 10
        detailY := height - statusHeight - detailHeight - 36
        listHeight := Max(250, detailY - listTop - 7)
        sourceButtonY := detailY
        statusY := height - statusHeight - 8

        this.BrowserTabControl.Move(10, 8, width - 20, 34)

        addressWidth := Max(240, width - 232 - 574)
        this.AddressEdit.Move(232, 48, addressWidth, 28)
        goX := 238 + addressWidth
        this.GoButton.Move(goX, 48, 42, 28)
        this.PrevLiveButton.Move(goX + 48, 48, 70, 28)
        this.NextLiveButton.Move(goX + 124, 48, 70, 28)
        this.FocusLiveButton.Move(goX + 200, 48, 76, 28)
        this.CombinedButton.Move(goX + 282, 48, 104, 28)
        this.RealTabsButton.Move(goX + 392, 48, 104, 28)
        this.MenuButton.Move(goX + 502, 48, Max(56, width - (goX + 512)), 28)

        this.SourceList.Move(10, listTop, leftWidth, listHeight)
        this.AddActiveButton.Move(10, sourceButtonY, 100, 28)
        this.AddSelectedButton.Move(116, sourceButtonY, 100, 28)
        this.CaptureButton.Move(222, sourceButtonY, 108, 28)

        clearX := width - 120
        helpX := width - 214
        hiddenX := width - 318
        recursiveX := width - 402
        regexX := width - 470
        typeX := width - 636
        filterEditX := rightX + 40
        filterWidth := Max(130, typeX - filterEditX - 8)

        this.FilterLabel.Move(rightX, 94, 38, 22)
        this.FilterEdit.Move(filterEditX, 92, filterWidth, 26)
        this.TypeCombo.Move(typeX, 92, 156, 26)
        this.RegexCheck.Move(regexX, 94, 62, 22)
        this.RecursiveCheck.Move(recursiveX, 94, 78, 22)
        this.HiddenCheck.Move(hiddenX, 94, 98, 22)
        this.FilterHelpButton.Move(helpX, 90, 88, 28)
        this.ClearFilterButton.Move(clearX, 90, 110, 28)

        this.FileList.Move(rightX, listTop, rightWidth, listHeight)
        this.DetailEdit.Move(rightX, detailY, rightWidth, detailHeight)
        this.StatusText.Move(10, statusY, width - 20, statusHeight)
    }

    SelectAddressText(ctrl, *) {
        try ctrl.Focus()
    }

    QueueRefresh(*) {
        SetTimer(this.RefreshTimerCallback, 0)
        SetTimer(this.RefreshTimerCallback, -220)
    }

    DeferredRefresh(*) {
        if this.IsMainGuiVisible()
            this.RefreshFiles()
    }

    ; ------------------------------------------------------------------------
    ; Slot and workspace management
    ; ------------------------------------------------------------------------

    SelectWorkspaceSlot(index, *) {
        if (index < 1 || index > this.MaxSlots)
            return

        this.SelectedSlot := index
        this.UpdateSlotButtons()
        path := this.WorkspacePaths[index]

        if (path = "") {
            this.SetStatus("Slot " index " is empty. Use Add Active, Add Selected, or Workspace Actions.")
            return
        }

        if !DirExist(path) {
            this.SetStatus("Slot " index " points to a missing folder: " path)
            answer := MsgBox(
                "This workspace path no longer exists:`n`n" path "`n`nClear the slot?",
                "Missing Workspace Folder",
                "YesNo Icon!"
            )
            if (answer = "Yes") {
                this.WorkspacePaths[index] := ""
                this.UpdateSlotButtons()
                this.SaveWorkspace()
            }
            return
        }

        this.NavigateTo(path)
    }

    AddLastExplorerPathToWorkspace(*) {
        path := this.ResolveLastExplorerPath()
        if (path = "" || !DirExist(path)) {
            this.Notify("No Explorer folder is currently available.")
            return
        }

        this.AddPathToWorkspace(path)
    }

    AddSelectedSourceToWorkspace(*) {
        path := this.GetSelectedSourcePath()
        if (path = "") {
            this.Notify("Select a folder in the left list first.")
            return
        }
        this.AddPathToWorkspace(path)
    }

    AddPathToWorkspace(path, preferredSlot := 0, *) {
        path := this.NormalizePath(path)
        if (path = "" || !DirExist(path)) {
            this.Notify("The selected workspace path does not exist.")
            return false
        }

        existing := this.FindPathIndex(this.WorkspacePaths, path)
        if existing {
            this.SelectedSlot := existing
            this.UpdateSlotButtons()
            if this.IsMainGuiVisible()
                this.NavigateTo(path)
            this.Notify("Folder is already in slot " existing ".")
            return true
        }

        slot := preferredSlot
        if (slot < 1 || slot > this.MaxSlots)
            slot := this.FindFirstEmptySlot()

        if !slot
            slot := this.SelectedSlot

        if (this.WorkspacePaths[slot] != "") {
            answer := MsgBox(
                "All ten workspace slots are occupied.`n`nReplace slot " slot "?`n`n"
                this.WorkspacePaths[slot] "`n`nwith:`n" path,
                "Replace Workspace Slot",
                "YesNo Icon?"
            )
            if (answer != "Yes")
                return false
        }

        this.WorkspacePaths[slot] := path
        this.SelectedSlot := slot
        this.UpdateSlotButtons()
        this.SaveWorkspace()
        this.PopulateSourceList()

        if this.IsMainGuiVisible()
            this.NavigateTo(path)

        this.Notify("Added to workspace slot " slot ".")
        return true
    }

    FindFirstEmptySlot() {
        Loop this.MaxSlots {
            if (this.WorkspacePaths[A_Index] = "")
                return A_Index
        }
        return 0
    }

    RemoveSelectedSlot(*) {
        slot := this.SelectedSlot
        path := this.WorkspacePaths[slot]
        if (path = "") {
            this.Notify("The selected workspace slot is already empty.")
            return
        }

        this.WorkspacePaths[slot] := ""
        this.UpdateSlotButtons()
        this.SaveWorkspace()
        this.PopulateSourceList()
        this.Notify("Cleared workspace slot " slot ".")
    }

    ClearAllSlots(*) {
        answer := MsgBox(
            "Clear all ten workspace slots? The visit timeline and favorites will remain.",
            "Clear Workspace",
            "YesNo Icon?"
        )
        if (answer != "Yes")
            return

        Loop this.MaxSlots
            this.WorkspacePaths[A_Index] := ""

        this.SelectedSlot := 1
        this.UpdateSlotButtons()
        this.SaveWorkspace()
        this.PopulateSourceList()
        this.Notify("All workspace slots cleared.")
    }

    RefreshExplorerTabs(showNotification := true, *) {
        windows := this.RefreshOpenExplorerState()
        this.AutoMergeExplorerPathsIntoWorkspace(false)
        this.RebuildBrowserTabs()
        if showNotification
            this.Notify("Detected " windows.Length " live Explorer tab" (windows.Length = 1 ? "" : "s") ".")
        return windows
    }

    CaptureOpenExplorerWindowsAndShow(*) {
        this.CaptureOpenExplorerWindows()
        this.Show()
    }

    FindCurrentExplorerEntryIndex(entries) {
        if (entries.Length = 0)
            return 0

        activeHwnd := WinExist("A")
        activePath := ""
        if this.IsExplorerWindow(activeHwnd)
            activePath := this.GetExplorerPathByHwnd(activeHwnd)

        ; Prefer the last verified cycle position when it still describes the
        ; active Explorer location. This permits cycling duplicate-path tabs.
        if (
            this.ExplorerCycleIndex >= 1
            && this.ExplorerCycleIndex <= entries.Length
        ) {
            remembered := entries[this.ExplorerCycleIndex]
            if (
                activeHwnd = remembered.Hwnd
                && (
                    activePath = ""
                    || StrLower(activePath) = StrLower(remembered.Path)
                )
            )
                return this.ExplorerCycleIndex
        }

        if (activeHwnd && activePath != "") {
            for index, item in entries {
                if (
                    item.Hwnd = activeHwnd
                    && StrLower(item.Path) = StrLower(activePath)
                )
                    return index
            }
        }

        if (
            this.ExplorerCycleIndex >= 1
            && this.ExplorerCycleIndex <= entries.Length
        )
            return this.ExplorerCycleIndex

        if (this.LastExplorerPath != "") {
            for index, item in entries {
                if (StrLower(item.Path) = StrLower(this.LastExplorerPath))
                    return index
            }
        }

        return 0
    }

    CycleExplorerEntries(direction := 1, *) {
        entries := this.RefreshOpenExplorerState()
        if (entries.Length = 0) {
            this.Notify("No open Explorer folders were found.")
            return false
        }

        current := this.FindCurrentExplorerEntryIndex(entries)
        if !current
            targetIndex := direction >= 0 ? 1 : entries.Length
        else
            targetIndex := Mod(current - 1 + direction + entries.Length, entries.Length) + 1

        target := entries[targetIndex]
        currentEntry := current ? entries[current] : 0
        activated := this.ActivateExplorerEntry(target, direction, currentEntry)
        this.ExplorerCycleIndex := targetIndex
        if activated {
            this.UpdateLastExplorerLocation(target.Hwnd, target.Path, "Explorer cycle")
            if this.GuiBuilt {
                this.RebuildBrowserTabs("Explorer|" target.Key)
                if this.IsMainGuiVisible()
                    this.NavigateTo(target.Path, false, true)
            }
            this.Notify(
                "Explorer " targetIndex "/" entries.Length ": "
                this.PathDisplayName(target.Path)
            )
        }
        return activated
    }

    ActivateExplorerEntry(entry, direction := 1, currentEntry := 0, *) {
        if !IsObject(entry) || !this.IsExplorerWindow(entry.Hwnd)
            return false

        try {
            WinActivate("ahk_id " entry.Hwnd)
            if !WinWaitActive("ahk_id " entry.Hwnd, , 2)
                return false

            ; During sequential cycling, one Ctrl+Tab operation is more exact
            ; than path matching because two tabs can intentionally show the
            ; same directory.
            if (
                IsObject(currentEntry)
                && currentEntry.Hwnd = entry.Hwnd
                && currentEntry.Key != entry.Key
            ) {
                Send(direction >= 0 ? "^{Tab}" : "^+{Tab}")
                Sleep(160)
                return true
            }

            currentPath := this.GetExplorerPathByHwnd(entry.Hwnd)
            if (
                currentPath != ""
                && StrLower(currentPath) = StrLower(entry.Path)
            )
                return true

            ; Windows 11 tabs share an HWND. Cycle the tab strip in that window
            ; until the Shell COM-resolved path matches the requested entry.
            sameWindowCount := 0
            for item in this.OpenExplorerEntries {
                if (item.Hwnd = entry.Hwnd)
                    sameWindowCount += 1
            }

            Loop Max(1, sameWindowCount) {
                Send("^{Tab}")
                Sleep(140)
                currentPath := this.GetExplorerPathByHwnd(entry.Hwnd)
                if (
                    currentPath != ""
                    && StrLower(currentPath) = StrLower(entry.Path)
                )
                    return true
            }

            ; The window was activated even if Explorer did not expose a unique
            ; active-tab path quickly enough for a verified match.
            return WinActive("ahk_id " entry.Hwnd) != 0
        } catch {
            return false
        }
    }

    FocusSelectedExplorerEntry(*) {
        model := this.GetSelectedBrowserModel()
        if !IsObject(model) || model.Kind != "Explorer" {
            this.Notify("Select a live E#.# Explorer tab first.")
            return
        }

        entry := {
            Hwnd: model.Hwnd,
            Path: model.Path
        }
        if !this.ActivateExplorerEntry(entry, 1, 0)
            this.Notify("The matching Explorer tab is no longer available.")
    }

    CloseSelectedExplorerEntry(*) {
        model := this.GetSelectedBrowserModel()
        if !IsObject(model) || model.Kind != "Explorer" {
            this.Notify("Select a live E#.# Explorer tab first.")
            return
        }

        answer := MsgBox(
            "Close this real Explorer tab?`n`n" model.Path,
            "Close Explorer Tab",
            "YesNo Icon?"
        )
        if (answer != "Yes")
            return

        entry := {Hwnd: model.Hwnd, Path: model.Path}
        if this.ActivateExplorerEntry(entry, 1, 0) {
            Send("^w")
            Sleep(180)
            this.RefreshExplorerTabs(false)
        }
    }

    DuplicateSelectedExplorerEntry(*) {
        model := this.GetSelectedBrowserModel()
        if !IsObject(model) || model.Kind != "Explorer" {
            this.Notify("Select a live E#.# Explorer tab first.")
            return
        }

        entry := {Hwnd: model.Hwnd, Path: model.Path}
        if !this.ActivateExplorerEntry(entry, 1, 0) {
            this.Notify("The matching Explorer tab is no longer available.")
            return
        }

        try {
            Send("^t")
            Sleep(220)
            this.NavigateExplorerAddress(model.Path)
            this.RefreshExplorerTabs(false)
        } catch as err {
            MsgBox("Could not duplicate the Explorer tab.`n`n" err.Message, "Explorer Tab", "Icon!")
        }
    }

    CopyOpenExplorerPaths(*) {
        entries := this.RefreshOpenExplorerState()
        if (entries.Length = 0) {
            this.Notify("No open Explorer paths are available.")
            return
        }

        text := ""
        for item in entries {
            line := "W" item.WindowOrdinal ".T" item.TabOrdinal "`t" item.Path
            text .= (text = "" ? "" : "`r`n") line
        }
        this.CopyText(text)
        this.Notify("Copied " entries.Length " live Explorer path" (entries.Length = 1 ? "" : "s") ".")
    }

    ReplaceSlotFromLastExplorer(slot, *) {
        path := this.ResolveLastExplorerPath()
        if (path = "" || !DirExist(path)) {
            this.Notify("No live Explorer folder is available.")
            return
        }
        this.WorkspacePaths[slot] := path
        this.SelectedSlot := slot
        this.SaveWorkspace()
        this.RebuildBrowserTabs("Workspace|" slot)
        this.NavigateTo(path)
    }

    ClearWorkspaceSlot(slot, *) {
        if (slot < 1 || slot > this.MaxSlots)
            return
        this.WorkspacePaths[slot] := ""
        this.SelectedSlot := slot
        this.SaveWorkspace()
        this.RebuildBrowserTabs("Workspace|" slot)
        this.PopulateSourceList()
        this.SetStatus("Workspace slot " slot " cleared.")
    }

    CaptureOpenExplorerWindows(*) {
        windows := this.RefreshOpenExplorerState()
        if (windows.Length = 0) {
            this.Notify("No normal file-system Explorer windows were found.")
            return
        }

        captured := 0
        seen := Map()
        Loop this.MaxSlots
            this.WorkspacePaths[A_Index] := ""

        for item in windows {
            key := StrLower(item.Path)
            if seen.Has(key)
                continue
            seen[key] := true

            captured += 1
            if (captured > this.MaxSlots)
                break
            this.WorkspacePaths[captured] := item.Path
        }

        this.SelectedSlot := 1
        this.SaveWorkspace()
        this.UpdateSlotButtons()
        this.PopulateSourceList()

        if (captured > 0 && this.IsMainGuiVisible())
            this.NavigateTo(this.WorkspacePaths[1])

        this.Notify("Captured " captured " Explorer folder" (captured = 1 ? "" : "s") ".")
    }

    UpdateSlotButtons() {
        if !this.GuiBuilt
            return
        this.RebuildBrowserTabs()
    }

    RebuildBrowserTabs(preferredKey := "", *) {
        if !this.GuiBuilt || this.RebuildingBrowserTabs
            return

        this.RebuildingBrowserTabs := true
        try {
            if (preferredKey = "")
                preferredKey := this.GetSelectedBrowserTabKey()

            models := []
            labels := []

            ; Every live Shell browser entry is represented independently, even
            ; when two tabs point at the same path.
            liveCount := 0
            for item in this.OpenExplorerEntries {
                liveCount += 1
                if (liveCount > this.MaxBrowserTabs)
                    break

                label := "E" item.WindowOrdinal "." item.TabOrdinal ": " this.Truncate(item.Title, 22)
                models.Push({
                    Key: "Explorer|" item.Key,
                    Kind: "Explorer",
                    Path: item.Path,
                    Hwnd: item.Hwnd,
                    WindowOrdinal: item.WindowOrdinal,
                    TabOrdinal: item.TabOrdinal,
                    Slot: this.FindPathIndex(this.WorkspacePaths, item.Path)
                })
                labels.Push(label)
            }

            ; The ten persistent slots remain stable virtual folders regardless
            ; of how many real Explorer tabs are currently open.
            Loop this.MaxSlots {
                slot := A_Index
                path := this.WorkspacePaths[slot]
                label := path = "" ? "(empty)" : this.PathDisplayName(path)
                if (path != "" && !DirExist(path))
                    label .= " !"
                models.Push({
                    Key: "Workspace|" slot,
                    Kind: "Workspace",
                    Path: path,
                    Hwnd: 0,
                    WindowOrdinal: 0,
                    TabOrdinal: 0,
                    Slot: slot
                })
                labels.Push("S" slot ": " this.Truncate(label, 22))
            }

            models.Push({
                Key: "Combined",
                Kind: "Combined",
                Path: "workspace://combined",
                Hwnd: 0,
                WindowOrdinal: 0,
                TabOrdinal: 0,
                Slot: 0
            })
            labels.Push("Combined")

            this.BrowserTabs := models
            this.BrowserTabControl.Delete()
            this.BrowserTabControl.Add(labels)

            chosen := 0
            if (preferredKey != "") {
                for index, model in models {
                    if (model.Key = preferredKey) {
                        chosen := index
                        break
                    }
                }
            }

            if !chosen && this.ViewMode = "Combined"
                chosen := models.Length

            if !chosen && this.CurrentPath != "" {
                for index, model in models {
                    if (model.Path != "" && StrLower(model.Path) = StrLower(this.CurrentPath)) {
                        chosen := index
                        break
                    }
                }
            }

            if !chosen {
                targetKey := "Workspace|" this.SelectedSlot
                for index, model in models {
                    if (model.Key = targetKey) {
                        chosen := index
                        break
                    }
                }
            }

            if !chosen
                chosen := 1

            this.BrowserTabControl.Choose(chosen)
            this.SelectedBrowserTabKey := models[chosen].Key
        } finally {
            this.RebuildingBrowserTabs := false
        }
    }

    GetSelectedBrowserTabKey() {
        if !this.GuiBuilt || this.BrowserTabs.Length = 0
            return this.SelectedBrowserTabKey

        index := this.BrowserTabControl.Value
        if (index >= 1 && index <= this.BrowserTabs.Length)
            return this.BrowserTabs[index].Key
        return this.SelectedBrowserTabKey
    }

    GetSelectedBrowserModel() {
        if !this.GuiBuilt || this.BrowserTabs.Length = 0
            return 0
        index := this.BrowserTabControl.Value
        if (index < 1 || index > this.BrowserTabs.Length)
            return 0
        return this.BrowserTabs[index]
    }

    OnBrowserTabChanged(ctrl, *) {
        if this.RebuildingBrowserTabs
            return

        index := ctrl.Value
        if (index < 1 || index > this.BrowserTabs.Length)
            return

        model := this.BrowserTabs[index]
        this.SelectedBrowserTabKey := model.Key

        switch model.Kind {
            case "Explorer":
                if model.Slot
                    this.SelectedSlot := model.Slot
                if (model.Path != "" && DirExist(model.Path))
                    this.NavigateTo(model.Path, true, true)
            case "Workspace":
                this.SelectedSlot := model.Slot
                if (model.Path = "") {
                    this.SetStatus("Workspace slot " model.Slot " is empty. Capture Explorer tabs or add a folder.")
                    return
                }
                if !DirExist(model.Path) {
                    this.SetStatus("Workspace slot " model.Slot " points to a missing folder: " model.Path)
                    return
                }
                this.NavigateTo(model.Path, true, true)
            case "Combined":
                this.ShowCombinedView()
        }
    }

    CycleBrowserTabs(direction := 1, *) {
        if !this.GuiBuilt
            this.Show()
        if (this.BrowserTabs.Length = 0)
            return

        current := this.BrowserTabControl.Value
        if (current < 1)
            current := 1
        nextIndex := Mod(current - 1 + direction + this.BrowserTabs.Length, this.BrowserTabs.Length) + 1
        this.BrowserTabControl.Choose(nextIndex)
        this.OnBrowserTabChanged(this.BrowserTabControl)
    }

    ShowBrowserTabContextMenu(ctrl, itemIndex := 0, isRightClick := true, x := 0, y := 0) {
        model := this.GetSelectedBrowserModel()
        if !IsObject(model)
            return

        browserTabMenu := Menu()
        if (model.Path != "" && model.Path != "workspace://combined" && DirExist(model.Path)) {
            browserTabMenu.Add("Browse virtual tab", ObjBindMethod(this, "NavigateTo", model.Path, true, true))
            browserTabMenu.Add("Open in Explorer", ObjBindMethod(this, "OpenInExplorer", model.Path))
            browserTabMenu.Add("Open in VS Code", ObjBindMethod(this, "OpenVSCodeAt", model.Path))
            browserTabMenu.Add("Copy path", ObjBindMethod(this, "CopyText", model.Path))
        }

        if (model.Kind = "Explorer") {
            browserTabMenu.Add()
            browserTabMenu.Add("Focus matching real Explorer tab", ObjBindMethod(this, "FocusSelectedExplorerEntry"))
            browserTabMenu.Add("Close matching real Explorer tab", ObjBindMethod(this, "CloseSelectedExplorerEntry"))
            browserTabMenu.Add("Duplicate as a new real Explorer tab", ObjBindMethod(this, "DuplicateSelectedExplorerEntry"))
            browserTabMenu.Add("Pin path into workspace", ObjBindMethod(this, "AddPathToWorkspace", model.Path, 0))
        } else if (model.Kind = "Workspace") {
            browserTabMenu.Add()
            browserTabMenu.Add("Replace slot from last Explorer", ObjBindMethod(this, "ReplaceSlotFromLastExplorer", model.Slot))
            browserTabMenu.Add("Clear workspace slot", ObjBindMethod(this, "ClearWorkspaceSlot", model.Slot))
        }

        browserTabMenu.Add()
        browserTabMenu.Add("Copy all live Explorer paths", ObjBindMethod(this, "CopyOpenExplorerPaths"))
        browserTabMenu.Add("Refresh live Explorer tabs", ObjBindMethod(this, "RefreshExplorerTabs"))
        browserTabMenu.Show()
    }

    ShowCombinedView(*) {
        this.ViewMode := "Combined"
        this.CurrentPath := ""
        this.AddressEdit.Value := "workspace://combined"
        this.RefreshFiles()
        if this.GuiBuilt
            this.RebuildBrowserTabs("Combined")
        this.SetStatus("Combined virtual view across all valid workspace slots.")
    }

    ConsolidateIntoExplorerTabs(*) {
        paths := this.GetValidWorkspacePaths()
        if (paths.Length = 0) {
            this.Notify("No valid workspace paths are available.")
            return
        }

        this.SaveState()
        if this.GuiBuilt
            this.MainGui.Hide()

        targetHwnd := this.GetUsableExplorerHwnd()
        if !targetHwnd {
            try Run("explorer.exe " this.Quote(paths[1]))
            catch as err {
                MsgBox("Could not open Explorer.`n`n" err.Message, "Explorer Tabs", "Icon!")
                return
            }

            if !WinWaitActive("ahk_class CabinetWClass", , 4) {
                this.Notify("Explorer did not become active.")
                return
            }
            targetHwnd := WinExist("A")
        }

        try {
            WinActivate("ahk_id " targetHwnd)
            if !WinWaitActive("ahk_id " targetHwnd, , 3)
                throw Error("Explorer could not be activated.")

            savedClipboard := ClipboardAll()

            ; Reuse the current tab for the first workspace path.
            this.NavigateExplorerAddress(paths[1])

            Loop paths.Length - 1 {
                index := A_Index + 1
                Send("^t")
                Sleep(240)
                this.NavigateExplorerAddress(paths[index])
            }

            A_Clipboard := savedClipboard
            this.LastExplorerHwnd := targetHwnd
            this.LastExplorerPath := paths[paths.Length]
            this.Notify("Opened " paths.Length " workspace paths as Explorer tabs.")
        } catch as err {
            MsgBox(
                "Explorer-tab consolidation stopped before completion.`n`n" err.Message
                "`n`nThe paths remain safely stored in the workspace.",
                "Explorer Tabs",
                "Icon!"
            )
        }
    }

    NavigateExplorerAddress(path) {
        A_Clipboard := path
        if !ClipWait(0.75)
            throw Error("Could not place a path on the clipboard.")
        Send("^l")
        Sleep(80)
        Send("^v")
        Sleep(60)
        Send("{Enter}")
        Sleep(320)
    }

    GetUsableExplorerHwnd() {
        this.ResolveLastExplorerPath()
        if this.IsExplorerWindow(this.LastExplorerHwnd)
            return this.LastExplorerHwnd

        try explorerHwnds := WinGetList("ahk_exe explorer.exe")
        catch
            explorerHwnds := []

        for hwnd in explorerHwnds {
            if this.IsExplorerWindow(hwnd)
                return hwnd
        }

        return 0
    }

    GetValidWorkspacePaths() {
        paths := []
        seen := Map()
        for path in this.WorkspacePaths {
            if (path = "" || !DirExist(path))
                continue
            key := StrLower(path)
            if seen.Has(key)
                continue
            seen[key] := true
            paths.Push(path)
        }
        return paths
    }

    ; ------------------------------------------------------------------------
    ; Navigation and file browser
    ; ------------------------------------------------------------------------

    NavigateTo(path, addToBackHistory := true, recordVisit := true, *) {
        path := this.NormalizePath(path)
        if (path = "workspace://combined") {
            this.ShowCombinedView()
            return
        }

        if (path = "" || !DirExist(path)) {
            this.SetStatus("Folder does not exist: " path)
            return false
        }

        if (
            addToBackHistory
            && this.ViewMode = "Folder"
            && this.CurrentPath != ""
            && StrLower(this.CurrentPath) != StrLower(path)
        ) {
            this.BackHistory.Push(this.CurrentPath)
            while (this.BackHistory.Length > 100)
                this.BackHistory.RemoveAt(1)
            this.ForwardHistory := []
        }

        this.ViewMode := "Folder"
        this.CurrentPath := path
        this.AddressEdit.Value := path

        slot := this.FindPathIndex(this.WorkspacePaths, path)
        if slot
            this.SelectedSlot := slot
        this.UpdateSlotButtons()

        if recordVisit
            this.RecordVisitedPath(path, "Workspace GUI")

        this.RefreshFiles()
        return true
    }

    NavigateBack(*) {
        if (this.BackHistory.Length = 0) {
            this.Notify("No previous workspace location.")
            return
        }

        if (this.ViewMode = "Folder" && this.CurrentPath != "")
            this.ForwardHistory.Push(this.CurrentPath)

        path := this.BackHistory.Pop()
        this.NavigateTo(path, false)
    }

    NavigateForward(*) {
        if (this.ForwardHistory.Length = 0) {
            this.Notify("No forward workspace location.")
            return
        }

        if (this.ViewMode = "Folder" && this.CurrentPath != "")
            this.BackHistory.Push(this.CurrentPath)

        path := this.ForwardHistory.Pop()
        this.NavigateTo(path, false)
    }

    NavigateUp(*) {
        if (this.ViewMode != "Folder" || this.CurrentPath = "")
            return

        SplitPath(this.CurrentPath, , &parent)
        parent := this.NormalizePath(parent)
        if (parent != "" && StrLower(parent) != StrLower(this.CurrentPath))
            this.NavigateTo(parent)
    }

    GoToAddress(*) {
        path := Trim(this.AddressEdit.Value)
        if (StrLower(path) = "workspace://combined") {
            this.ShowCombinedView()
            return
        }
        this.NavigateTo(path)
    }

    RefreshFiles(*) {
        if !this.GuiBuilt
            return

        this.FileList.Opt("-Redraw")
        this.FileList.Delete()
        this.DetailEdit.Value := ""

        count := 0
        truncated := false
        invalidRegex := false

        if (this.ViewMode = "Combined") {
            paths := this.GetValidWorkspacePaths()
            for path in paths {
                result := this.AddFolderItemsToList(path, this.PathDisplayName(path), &count, &invalidRegex)
                if (result = "Limit") {
                    truncated := true
                    break
                }
                if invalidRegex
                    break
            }
        } else if (this.CurrentPath != "" && DirExist(this.CurrentPath)) {
            result := this.AddFolderItemsToList(
                this.CurrentPath,
                this.PathDisplayName(this.CurrentPath),
                &count,
                &invalidRegex
            )
            if (result = "Limit")
                truncated := true
        }

        this.FileList.Opt("+Redraw")

        if invalidRegex {
            this.SetStatus("The regular expression is invalid. Correct it or disable Regex.")
            return
        }

        locationText := this.ViewMode = "Combined"
            ? "Combined workspace"
            : this.CurrentPath
        suffix := truncated ? " | Display limit reached: " this.MaxDisplayedItems : ""
        this.SetStatus(locationText " | " count " item" (count = 1 ? "" : "s") suffix)
    }

    AddFolderItemsToList(rootPath, sourceName, &count, &invalidRegex) {
        recursive := this.RecursiveCheck.Value = 1
        loopMode := recursive ? "FDR" : "FD"
        showHidden := this.HiddenCheck.Value = 1
        query := Trim(this.FilterEdit.Value)
        filterType := this.TypeCombo.Text

        try {
            Loop Files rootPath "\*", loopMode {
                if (count >= this.MaxDisplayedItems)
                    return "Limit"

                attrib := A_LoopFileAttrib
                if !showHidden && (InStr(attrib, "H") || InStr(attrib, "S"))
                    continue

                isDirectory := InStr(attrib, "D") != 0
                fullPath := A_LoopFileFullPath
                name := A_LoopFileName
                modified := A_LoopFileTimeModified

                if !this.MatchesTypeFilter(name, fullPath, isDirectory, modified, filterType)
                    continue

                matchResult := this.MatchesTextFilter(name, fullPath, query)
                if (matchResult = -1) {
                    invalidRegex := true
                    return "InvalidRegex"
                }
                if !matchResult
                    continue

                typeText := isDirectory ? "Folder" : this.GetFileTypeText(name)
                sizeText := ""
                if !isDirectory {
                    try sizeText := this.FormatBytes(A_LoopFileSize)
                }

                modifiedText := ""
                try modifiedText := FormatTime(modified, "yyyy-MM-dd HH:mm:ss")

                this.FileList.Add("", name, typeText, sizeText, modifiedText, sourceName, fullPath)
                count += 1
            }
        } catch as err {
            this.SetStatus("Could not enumerate " rootPath ": " err.Message)
        }

        return "OK"
    }

    MatchesTextFilter(name, fullPath, query) {
        if (query = "")
            return true

        if (this.RegexCheck.Value = 1) {
            try return RegExMatch(name "`n" fullPath, query) != 0
            catch
                return -1
        }

        tokens := StrSplit(query, A_Space)
        for token in tokens {
            token := Trim(token)
            if (token = "")
                continue

            if (InStr(token, "*") || InStr(token, "?")) {
                regex := "i)^" this.WildcardToRegex(token) "$"
                try {
                    if !RegExMatch(name, regex)
                        return false
                } catch {
                    return false
                }
            } else {
                if !InStr(name, token, false) && !InStr(fullPath, token, false)
                    return false
            }
        }

        return true
    }

    WildcardToRegex(pattern) {
        result := ""
        Loop Parse pattern {
            ch := A_LoopField
            if (ch = "*")
                result .= ".*"
            else if (ch = "?")
                result .= "."
            else if InStr("\.^$+()[]{}|", ch)
                result .= "\" ch
            else
                result .= ch
        }
        return result
    }

    MatchesTypeFilter(name, fullPath, isDirectory, modified, filterType) {
        if (filterType = "All items")
            return true

        if (filterType = "Folders only")
            return isDirectory

        if isDirectory
            return false

        SplitPath(name, , , &extension)
        ext := StrLower(extension)

        switch filterType {
            case "Python":
                return ext = "py" || ext = "pyw" || ext = "pyi"
            case "AutoHotkey":
                return ext = "ahk"
            case "All code":
                return this.ExtensionIn(ext, "py,pyw,pyi,ahk,cs,csx,js,mjs,cjs,ts,tsx,jsx,html,htm,css,scss,less,json,xml,yaml,yml,toml,ini,c,cc,cpp,cxx,h,hpp,hxx,java,kt,kts,go,rs,rb,php,swift,sql,ps1,psm1,psd1,bat,cmd,sh,bash,zsh,lua,r,vue,svelte")
            case "Images":
                return this.ExtensionIn(ext, "png,jpg,jpeg,gif,bmp,webp,tif,tiff,svg,ico,heic,avif")
            case "Video":
                return this.ExtensionIn(ext, "mp4,mkv,avi,mov,wmv,webm,m4v,mpeg,mpg,ts,m2ts")
            case "Audio":
                return this.ExtensionIn(ext, "mp3,wav,flac,m4a,aac,ogg,wma,opus")
            case "Documents":
                return this.ExtensionIn(ext, "txt,md,rtf,pdf,doc,docx,odt,xls,xlsx,csv,ods,ppt,pptx,odp,epub")
            case "Archives":
                return this.ExtensionIn(ext, "zip,7z,rar,tar,gz,bz2,xz,cab,iso")
            case "Executables":
                return this.ExtensionIn(ext, "exe,msi,msix,appx,com,scr,lnk")
            case "Modified in 24 hours":
                try return DateDiff(A_Now, modified, "Hours") <= 24
                catch
                    return false
        }

        return true
    }

    ExtensionIn(extension, csv) {
        return InStr("," csv ",", "," extension ",", false) != 0
    }

    GetFileTypeText(name) {
        SplitPath(name, , , &extension)
        if (extension = "")
            return "File"
        return StrUpper(extension) " file"
    }

    OpenFileListItem(ctrl, row, *) {
        if !row
            row := ctrl.GetNext()
        if !row
            return

        path := ctrl.GetText(row, 6)
        if (path = "")
            return

        if DirExist(path)
            this.NavigateTo(path)
        else
            this.RunDefault(path)
    }

    UpdateSelectionDetails(ctrl, row := 0, *) {
        if !row
            row := ctrl.GetNext(0, "F")
        if !row
            row := ctrl.GetNext()
        if !row
            return

        path := ctrl.GetText(row, 6)
        if (path = "")
            return

        this.DetailEdit.Value := this.BuildPathDetails(path)
    }

    BuildPathDetails(path) {
        existsAsDir := DirExist(path)
        existsAsFile := FileExist(path)
        if (!existsAsDir && !existsAsFile)
            return "Missing: " path

        details := "Path: " path "`r`n"
        details .= "Kind: " (existsAsDir ? "Folder" : this.GetFileTypeText(path))

        if !existsAsDir {
            try details .= " | Size: " this.FormatBytes(FileGetSize(path))
        }

        try details .= " | Modified: " FormatTime(FileGetTime(path, "M"), "yyyy-MM-dd HH:mm:ss")
        try details .= " | Created: " FormatTime(FileGetTime(path, "C"), "yyyy-MM-dd HH:mm:ss")

        projectRoot := this.FindProjectRoot(path)
        if (projectRoot != "")
            details .= "`r`nProject root: " projectRoot

        return details
    }

    FindProjectRoot(path) {
        current := DirExist(path) ? path : this.ParentDirectory(path)
        Loop 30 {
            if (current = "")
                break

            if (
                DirExist(current "\.git")
                || FileExist(current "\pyproject.toml")
                || FileExist(current "\requirements.txt")
                || FileExist(current "\package.json")
                || FileExist(current "\Cargo.toml")
                || FileExist(current "\go.mod")
                || FileExist(current "\CMakeLists.txt")
                || DirExist(current "\.vscode")
                || this.DirectoryContainsExtension(current, "sln")
                || this.DirectoryContainsExtension(current, "csproj")
            )
                return current

            parent := this.ParentDirectory(current)
            if (parent = "" || StrLower(parent) = StrLower(current))
                break
            current := parent
        }
        return ""
    }

    DirectoryContainsExtension(path, extension) {
        try {
            Loop Files path "\*." extension, "F"
                return true
        }
        return false
    }

    ShowFileContextMenu(ctrl, row, isRightClick, x, y) {
        if !row
            return

        ctrl.Modify(row, "Select Focus")
        path := ctrl.GetText(row, 6)
        if (path = "")
            return

        fileContextMenu := Menu()
        fileContextMenu.Add("Open", ObjBindMethod(this, "RunDefault", path))
        fileContextMenu.Add("Open containing folder", ObjBindMethod(this, "OpenContainingFolder", path))
        fileContextMenu.Add("Open in new Explorer window", ObjBindMethod(this, "OpenInExplorer", path))
        fileContextMenu.Add()
        fileContextMenu.Add("Copy full path", ObjBindMethod(this, "CopyText", path))
        fileContextMenu.Add("Copy file or folder name", ObjBindMethod(this, "CopyText", this.PathDisplayName(path)))

        if DirExist(path) {
            fileContextMenu.Add("Add folder to workspace", ObjBindMethod(this, "AddPathToWorkspace", path, 0))
            fileContextMenu.Add("Add to favorites", ObjBindMethod(this, "AddFavorite", path))
        } else {
            parent := this.ParentDirectory(path)
            fileContextMenu.Add("Add containing folder to workspace", ObjBindMethod(this, "AddPathToWorkspace", parent, 0))
            fileContextMenu.Add("Add containing folder to favorites", ObjBindMethod(this, "AddFavorite", parent))
        }

        fileContextMenu.Add()
        toolsMenu := Menu()
        toolsMenu.Add("Windows Terminal here", ObjBindMethod(this, "OpenTerminalAt", path))
        toolsMenu.Add("PowerShell here", ObjBindMethod(this, "OpenPowerShellAt", path))
        toolsMenu.Add("Command Prompt here", ObjBindMethod(this, "OpenCmdAt", path))
        toolsMenu.Add("VS Code", ObjBindMethod(this, "OpenVSCodeAt", path))
        toolsMenu.Add("Detect project root", ObjBindMethod(this, "ShowProjectRoot", path))
        fileContextMenu.Add("Developer tools", toolsMenu)

        if !DirExist(path) {
            SplitPath(path, , , &extension)
            ext := StrLower(extension)
            if (ext = "py" || ext = "pyw")
                fileContextMenu.Add("Run Python file in Terminal", ObjBindMethod(this, "RunPythonFile", path))
            if (ext = "ahk")
                fileContextMenu.Add("Run AutoHotkey script", ObjBindMethod(this, "RunAutoHotkeyFile", path))
        }

        fileContextMenu.Add()
        fileContextMenu.Add("Rename...", ObjBindMethod(this, "RenamePath", path))
        fileContextMenu.Add("Move to Recycle Bin...", ObjBindMethod(this, "RecyclePath", path))
        fileContextMenu.Show()
    }

    ShowSourceContextMenu(ctrl, row, isRightClick, x, y) {
        if !row
            return

        ctrl.Modify(row, "Select Focus")
        path := ctrl.GetText(row, 3)
        if (path = "")
            return

        sourceContextMenu := Menu()
        sourceContextMenu.Add("Open in workspace browser", ObjBindMethod(this, "NavigateTo", path, true, true))
        sourceContextMenu.Add("Add to workspace slot", ObjBindMethod(this, "AddPathToWorkspace", path, 0))
        sourceContextMenu.Add("Add to favorites", ObjBindMethod(this, "AddFavorite", path))
        sourceContextMenu.Add("Open in Explorer", ObjBindMethod(this, "OpenInExplorer", path))
        sourceContextMenu.Add("Open in VS Code", ObjBindMethod(this, "OpenVSCodeAt", path))
        sourceContextMenu.Add("Copy path", ObjBindMethod(this, "CopyText", path))
        sourceContextMenu.Show()
    }

    RunDefault(path, *) {
        if DirExist(path) {
            this.NavigateTo(path)
            return
        }

        try Run(this.Quote(path))
        catch as err
            MsgBox("Could not open:`n" path "`n`n" err.Message, "Open Failed", "Icon!")
    }

    OpenContainingFolder(path, *) {
        if DirExist(path) {
            this.OpenInExplorer(path)
            return
        }
        try Run("explorer.exe /select," this.Quote(path))
        catch as err
            MsgBox("Could not reveal the item.`n`n" err.Message, "Explorer", "Icon!")
    }

    OpenInExplorer(path, *) {
        folder := DirExist(path) ? path : this.ParentDirectory(path)
        if (folder = "")
            return
        try Run("explorer.exe " this.Quote(folder))
        catch as err
            MsgBox("Could not open Explorer.`n`n" err.Message, "Explorer", "Icon!")
    }

    OpenTerminalAt(path, *) {
        folder := DirExist(path) ? path : this.ParentDirectory(path)
        try Run("wt.exe -d " this.Quote(folder))
        catch {
            this.OpenPowerShellAt(folder)
        }
    }

    OpenPowerShellAt(path, *) {
        folder := DirExist(path) ? path : this.ParentDirectory(path)
        escaped := StrReplace(folder, "'", "''")
        command := "powershell.exe -NoExit -Command " Chr(34)
            . "Set-Location -LiteralPath '" escaped "'" Chr(34)
        try Run(command)
        catch as err
            MsgBox("Could not open PowerShell.`n`n" err.Message, "PowerShell", "Icon!")
    }

    OpenCmdAt(path, *) {
        folder := DirExist(path) ? path : this.ParentDirectory(path)
        try Run("cmd.exe /K cd /d " this.Quote(folder))
        catch as err
            MsgBox("Could not open Command Prompt.`n`n" err.Message, "Command Prompt", "Icon!")
    }

    OpenVSCodeAt(path, *) {
        target := path
        try Run("code " this.Quote(target))
        catch as err
            MsgBox(
                "Could not launch VS Code with the 'code' command.`n`n" err.Message,
                "VS Code",
                "Icon!"
            )
    }

    RunPythonFile(path, *) {
        folder := this.ParentDirectory(path)
        command := "wt.exe -d " this.Quote(folder) " python " this.Quote(path)
        try Run(command)
        catch as err
            MsgBox("Could not run the Python file.`n`n" err.Message, "Python", "Icon!")
    }

    RunAutoHotkeyFile(path, *) {
        try Run(this.Quote(path))
        catch as err
            MsgBox("Could not run the AutoHotkey script.`n`n" err.Message, "AutoHotkey", "Icon!")
    }

    ShowProjectRoot(path, *) {
        root := this.FindProjectRoot(path)
        if (root = "") {
            this.Notify("No recognized project root was found above this item.")
            return
        }

        answer := MsgBox(
            "Detected project root:`n`n" root "`n`nAdd it to the workspace?",
            "Project Root",
            "YesNo Iconi"
        )
        if (answer = "Yes")
            this.AddPathToWorkspace(root)
    }

    RenamePath(path, *) {
        oldName := this.PathDisplayName(path)
        result := InputBox("Enter the new name:", "Rename", "w520 h150", oldName)
        if (result.Result != "OK")
            return

        newName := Trim(result.Value)
        if (newName = "" || newName = oldName)
            return

        parent := this.ParentDirectory(path)
        newPath := parent "\" newName
        if FileExist(newPath) || DirExist(newPath) {
            MsgBox("An item with that name already exists.", "Rename", "Icon!")
            return
        }

        try {
            if DirExist(path)
                DirMove(path, newPath)
            else
                FileMove(path, newPath)

            this.ReplaceStoredPath(path, newPath)
            this.RefreshFiles()
            this.Notify("Renamed successfully.")
        } catch as err {
            MsgBox("Could not rename the item.`n`n" err.Message, "Rename", "Icon!")
        }
    }

    RecyclePath(path, *) {
        answer := MsgBox(
            "Move this item to the Recycle Bin?`n`n" path,
            "Recycle Item",
            "YesNo Icon!"
        )
        if (answer != "Yes")
            return

        try {
            FileRecycle(path)
            this.RefreshFiles()
            this.Notify("Moved to the Recycle Bin.")
        } catch as err {
            MsgBox("Could not recycle the item.`n`n" err.Message, "Recycle Item", "Icon!")
        }
    }

    ReplaceStoredPath(oldPath, newPath) {
        Loop this.MaxSlots {
            if (StrLower(this.WorkspacePaths[A_Index]) = StrLower(oldPath))
                this.WorkspacePaths[A_Index] := newPath
        }

        for index, favorite in this.Favorites {
            if (StrLower(favorite) = StrLower(oldPath))
                this.Favorites[index] := newPath
        }

        this.SaveWorkspace()
        this.SaveFavorites()
        this.UpdateSlotButtons()
        this.PopulateSourceList()
    }

    ; ------------------------------------------------------------------------
    ; Left source list, favorites, timeline, and open windows
    ; ------------------------------------------------------------------------

    PopulateSourceList(*) {
        if !this.GuiBuilt
            return

        source := this.SourceCombo.Text
        this.SourceList.Opt("-Redraw")
        this.SourceList.Delete()

        switch source {
            case "Visit timeline":
                for entry in this.VisitLog {
                    stats := this.GetPathStats(entry.Path)
                    this.SourceList.Add(
                        "",
                        entry.Seq,
                        this.PathDisplayName(entry.Path),
                        entry.Path,
                        stats.Count,
                        this.FormatTimestamp(entry.At)
                    )
                }
            case "Favorites":
                for index, path in this.Favorites {
                    stats := this.GetPathStats(path)
                    this.SourceList.Add(
                        "",
                        index,
                        this.PathDisplayName(path),
                        path,
                        stats.Count,
                        this.FormatTimestamp(stats.LastAt)
                    )
                }
            case "Live Explorer tabs/windows":
                windows := this.RefreshOpenExplorerState()
                for index, item in windows {
                    stats := this.GetPathStats(item.Path)
                    this.SourceList.Add(
                        "",
                        "W" item.WindowOrdinal ".T" item.TabOrdinal,
                        item.Title != "" ? item.Title : this.PathDisplayName(item.Path),
                        item.Path,
                        stats.Count,
                        this.FormatTimestamp(stats.LastAt)
                    )
                }
            case "Workspace slots":
                Loop this.MaxSlots {
                    path := this.WorkspacePaths[A_Index]
                    if (path = "")
                        continue
                    stats := this.GetPathStats(path)
                    this.SourceList.Add(
                        "",
                        A_Index,
                        this.PathDisplayName(path),
                        path,
                        stats.Count,
                        this.FormatTimestamp(stats.LastAt)
                    )
                }
        }

        this.SourceList.Opt("+Redraw")
    }

    GetPathStats(path) {
        key := StrLower(path)
        if this.PathStats.Has(key)
            return this.PathStats[key]
        return {Path: path, Count: 0, LastAt: ""}
    }

    GetSelectedSourcePath() {
        row := this.SourceList.GetNext()
        if !row
            return ""
        return this.SourceList.GetText(row, 3)
    }

    OpenSourceListItem(ctrl, row, *) {
        if !row
            return
        path := ctrl.GetText(row, 3)
        if (path != "")
            this.NavigateTo(path)
    }

    AddFavorite(path := "", *) {
        if (path = "") {
            if (this.ViewMode = "Folder")
                path := this.CurrentPath
            else
                path := this.GetSelectedSourcePath()
        }

        path := this.NormalizePath(path)
        if (path = "" || !DirExist(path)) {
            this.Notify("No valid folder is selected for Favorites.")
            return
        }

        if this.FindPathIndex(this.Favorites, path) {
            this.Notify("Folder is already a favorite.")
            return
        }

        this.Favorites.InsertAt(1, path)
        this.SaveFavorites()
        if (this.SourceCombo.Text = "Favorites")
            this.PopulateSourceList()
        this.Notify("Added to favorites.")
    }

    RemoveSelectedFavorite(*) {
        if (this.SourceCombo.Text != "Favorites") {
            this.Notify("Switch the left list to Favorites first.")
            return
        }

        path := this.GetSelectedSourcePath()
        if (path = "")
            return

        index := this.FindPathIndex(this.Favorites, path)
        if index {
            this.Favorites.RemoveAt(index)
            this.SaveFavorites()
            this.PopulateSourceList()
            this.Notify("Favorite removed.")
        }
    }

    ClearVisitTimeline(*) {
        answer := MsgBox(
            "Clear the recorded Explorer visit timeline? Workspace slots and favorites will remain.",
            "Clear Visit Timeline",
            "YesNo Icon?"
        )
        if (answer != "Yes")
            return

        this.VisitLog := []
        this.PathStats := Map()
        this.Sequence := 0
        this.SaveHistory()
        this.PopulateSourceList()
        this.Notify("Visit timeline cleared.")
    }

    ; ------------------------------------------------------------------------
    ; Workspace actions, snapshots, import, and export
    ; ------------------------------------------------------------------------

    ShowWorkspaceActions(*) {
        workspaceActionsMenu := Menu()
        workspaceActionsMenu.Add("Add current folder to selected slot", ObjBindMethod(this, "AddCurrentFolderToSelectedSlot"))
        workspaceActionsMenu.Add("Add auto-detected last Explorer folder", ObjBindMethod(this, "AddLastExplorerPathToWorkspace"))
        workspaceActionsMenu.Add("Refresh live Explorer tabs", ObjBindMethod(this, "RefreshExplorerTabs"))
        workspaceActionsMenu.Add("Capture all open Explorer tabs/windows", ObjBindMethod(this, "CaptureOpenExplorerWindows"))
        workspaceActionsMenu.Add("Cycle to previous real Explorer tab", ObjBindMethod(this, "CycleExplorerEntries", -1))
        workspaceActionsMenu.Add("Cycle to next real Explorer tab", ObjBindMethod(this, "CycleExplorerEntries", 1))
        workspaceActionsMenu.Add("Focus selected real Explorer tab", ObjBindMethod(this, "FocusSelectedExplorerEntry"))
        workspaceActionsMenu.Add("Copy all live Explorer paths", ObjBindMethod(this, "CopyOpenExplorerPaths"))
        workspaceActionsMenu.Add("Clear selected slot", ObjBindMethod(this, "RemoveSelectedSlot"))
        workspaceActionsMenu.Add("Clear all slots", ObjBindMethod(this, "ClearAllSlots"))
        workspaceActionsMenu.Add()
        workspaceActionsMenu.Add("Combined virtual view", ObjBindMethod(this, "ShowCombinedView"))
        workspaceActionsMenu.Add("Open workspace as real Explorer tabs", ObjBindMethod(this, "ConsolidateIntoExplorerTabs"))
        workspaceActionsMenu.Add("Copy all workspace paths", ObjBindMethod(this, "CopyWorkspacePaths"))
        workspaceActionsMenu.Add()
        workspaceActionsMenu.Add("Add current folder to favorites", ObjBindMethod(this, "AddFavorite", ""))
        workspaceActionsMenu.Add("Remove selected favorite", ObjBindMethod(this, "RemoveSelectedFavorite"))
        workspaceActionsMenu.Add("Clear visit timeline", ObjBindMethod(this, "ClearVisitTimeline"))
        workspaceActionsMenu.Add()

        snapshotMenu := Menu()
        snapshotMenu.Add("Save current workspace snapshot...", ObjBindMethod(this, "SaveSnapshot"))
        if (this.SnapshotNames.Length > 0) {
            snapshotMenu.Add()
            for name in this.SnapshotNames
                snapshotMenu.Add(this.MenuSafe(name), ObjBindMethod(this, "LoadSnapshot", name))
            snapshotMenu.Add()
            snapshotMenu.Add("Delete snapshot...", ObjBindMethod(this, "DeleteSnapshot"))
        }
        workspaceActionsMenu.Add("Named snapshots", snapshotMenu)

        workspaceActionsMenu.Add("Export workspace path list...", ObjBindMethod(this, "ExportWorkspace"))
        workspaceActionsMenu.Add("Import workspace path list...", ObjBindMethod(this, "ImportWorkspace"))
        workspaceActionsMenu.Add()
        workspaceActionsMenu.Add("Hotkey reference", ObjBindMethod(this, "ShowHotkeyReference"))
        workspaceActionsMenu.Show()
    }

    AddCurrentFolderToSelectedSlot(*) {
        if (this.ViewMode != "Folder" || this.CurrentPath = "") {
            this.Notify("Combined View does not represent one physical folder.")
            return
        }
        this.AddPathToWorkspace(this.CurrentPath, this.SelectedSlot)
    }

    CopyWorkspacePaths(*) {
        paths := this.GetValidWorkspacePaths()
        if (paths.Length = 0) {
            this.Notify("No valid workspace paths to copy.")
            return
        }

        text := ""
        for path in paths
            text .= (text = "" ? "" : "`r`n") path
        this.CopyText(text)
        this.Notify("Copied " paths.Length " workspace paths.")
    }

    SaveSnapshot(*) {
        result := InputBox(
            "Enter a name for this 10-slot workspace snapshot:",
            "Save Workspace Snapshot",
            "w560 h160"
        )
        if (result.Result != "OK")
            return

        name := this.CleanSnapshotName(result.Value)
        if (name = "")
            return

        existing := this.FindTextIndex(this.SnapshotNames, name)
        if existing {
            answer := MsgBox(
                "A snapshot named '" name "' already exists. Replace it?",
                "Replace Snapshot",
                "YesNo Icon?"
            )
            if (answer != "Yes")
                return
        } else {
            this.SnapshotNames.Push(name)
        }

        section := "Snapshot_" name
        try IniDelete(this.ConfigPath, section)
        Loop this.MaxSlots
            IniWrite(this.WorkspacePaths[A_Index], this.ConfigPath, section, "Path" A_Index)

        this.SaveSnapshotNames()
        this.Notify("Saved workspace snapshot: " name)
    }

    LoadSnapshot(name, *) {
        section := "Snapshot_" name
        Loop this.MaxSlots
            this.WorkspacePaths[A_Index] := IniRead(this.ConfigPath, section, "Path" A_Index, "")

        this.SelectedSlot := 1
        this.UpdateSlotButtons()
        this.SaveWorkspace()
        this.PopulateSourceList()

        firstPath := ""
        for path in this.WorkspacePaths {
            if (path != "" && DirExist(path)) {
                firstPath := path
                break
            }
        }
        if (firstPath != "")
            this.NavigateTo(firstPath)
        else
            this.RefreshFiles()

        this.Notify("Loaded workspace snapshot: " name)
    }

    DeleteSnapshot(*) {
        if (this.SnapshotNames.Length = 0)
            return

        prompt := "Enter the exact snapshot name to delete:`n`n"
        for name in this.SnapshotNames
            prompt .= "- " name "`n"

        result := InputBox(prompt, "Delete Snapshot", "w580 h260")
        if (result.Result != "OK")
            return

        name := this.CleanSnapshotName(result.Value)
        index := this.FindTextIndex(this.SnapshotNames, name)
        if !index {
            this.Notify("Snapshot name not found.")
            return
        }

        try IniDelete(this.ConfigPath, "Snapshot_" name)
        this.SnapshotNames.RemoveAt(index)
        this.SaveSnapshotNames()
        this.Notify("Deleted workspace snapshot: " name)
    }

    ExportWorkspace(*) {
        defaultName := A_ScriptDir "\ExplorerWorkspace_" FormatTime(A_Now, "yyyyMMdd_HHmmss") ".txt"
        selected := FileSelect("S16", defaultName, "Export workspace paths", "Text files (*.txt)")
        if (selected = "")
            return

        content := "; Explorer Workspace Manager export`r`n"
        content .= "; Created " FormatTime(A_Now, "yyyy-MM-dd HH:mm:ss") "`r`n"
        Loop this.MaxSlots
            content .= this.WorkspacePaths[A_Index] "`r`n"

        try {
            if FileExist(selected)
                FileDelete(selected)
            FileAppend(content, selected, "UTF-8")
            this.Notify("Workspace exported.")
        } catch as err {
            MsgBox("Could not export the workspace.`n`n" err.Message, "Export", "Icon!")
        }
    }

    ImportWorkspace(*) {
        selected := FileSelect(1, A_ScriptDir, "Import workspace paths", "Text files (*.txt)")
        if (selected = "")
            return

        try content := FileRead(selected, "UTF-8")
        catch as err {
            MsgBox("Could not read the workspace file.`n`n" err.Message, "Import", "Icon!")
            return
        }

        imported := []
        Loop Parse content, "`n", "`r" {
            line := Trim(A_LoopField)
            if (line = "" || SubStr(line, 1, 1) = ";")
                continue
            path := this.NormalizePath(line)
            if (DirExist(path) && !this.FindPathIndex(imported, path))
                imported.Push(path)
            if (imported.Length >= this.MaxSlots)
                break
        }

        if (imported.Length = 0) {
            this.Notify("The file contained no valid folder paths.")
            return
        }

        Loop this.MaxSlots
            this.WorkspacePaths[A_Index] := A_Index <= imported.Length ? imported[A_Index] : ""

        this.SelectedSlot := 1
        this.SaveWorkspace()
        this.UpdateSlotButtons()
        this.PopulateSourceList()
        this.NavigateTo(imported[1])
        this.Notify("Imported " imported.Length " workspace paths.")
    }

    CleanSnapshotName(name) {
        name := Trim(name)
        name := RegExReplace(name, "[\[\]`r`n=]", "-")
        return this.Truncate(name, 60)
    }

    ; ------------------------------------------------------------------------
    ; Filters and help
    ; ------------------------------------------------------------------------

    ClearFilters(*) {
        this.FilterEdit.Value := ""
        this.TypeCombo.Choose(1)
        this.RegexCheck.Value := 0
        this.RecursiveCheck.Value := 0
        this.HiddenCheck.Value := 0
        this.RefreshFiles()
    }

    ShowFilterHelp(*) {
        MsgBox(
            "Plain text filtering:`n"
            "Each space-separated word must occur in the name or path.`n`n"
            "Wildcard filtering:`n"
            "*.py       Python files`n"
            "camera*    Names beginning with camera`n"
            "test?.ahk  One-character wildcard`n`n"
            "Regular expressions:`n"
            "Enable Regex, then enter an AutoHotkey/PCRE expression such as:`n"
            "(?i)^(main|app).*\\.py$`n`n"
            "Recursive mode searches below the current folder or every workspace root."
            " The display is capped at " this.MaxDisplayedItems " items to prevent an accidental drive-wide GUI lockup.",
            "Workspace Filter Help"
        )
    }

    ShowHotkeyReference(*) {
        MsgBox(
            "Ctrl+Alt+E`n"
            "Open the Explorer Workspace Manager. Open Explorer locations are detected and merged into empty slots automatically.`n`n"
            "Ctrl+Alt+Shift+E`n"
            "Add the automatically detected last Explorer folder to the first empty slot, or the selected slot when full.`n`n"
            "Ctrl+Alt+Win+E`n"
            "Capture every currently open Explorer tab/window and show the multi-tab workspace.`n`n"
            "Ctrl+Alt+PageDown / Ctrl+Alt+PageUp`n"
            "Cycle forward or backward through all real open Explorer tabs and windows.`n`n"
            "Ctrl+Alt+Shift+PageDown / Ctrl+Alt+Shift+PageUp`n"
            "Cycle the emulated browser tab strip without changing the real Explorer focus.`n`n"
            "Ctrl+Alt+Win+T`n"
            "Open the stored workspace paths as real Windows 11 Explorer tabs.`n`n"
            "E#.# tabs are live Explorer entries. S1-S10 are persistent virtual slots."
            " Right-click a tab for focus, close, pin, copy, and developer actions.",
            "Explorer Workspace Hotkeys"
        )
    }

    ; ------------------------------------------------------------------------
    ; Persistence
    ; ------------------------------------------------------------------------

    LoadState() {
        this.SelectedSlot := IniRead(this.ConfigPath, "Settings", "SelectedSlot", "1") + 0
        if (this.SelectedSlot < 1 || this.SelectedSlot > this.MaxSlots)
            this.SelectedSlot := 1

        this.CurrentPath := this.NormalizePath(IniRead(this.ConfigPath, "Settings", "CurrentPath", ""))
        if (this.CurrentPath != "" && !DirExist(this.CurrentPath))
            this.CurrentPath := ""

        this.LastExplorerPath := this.NormalizePath(
            IniRead(this.ConfigPath, "Settings", "LastExplorerPath", "")
        )
        if (this.LastExplorerPath != "" && !DirExist(this.LastExplorerPath))
            this.LastExplorerPath := ""

        Loop this.MaxSlots
            this.WorkspacePaths[A_Index] := this.NormalizePath(
                IniRead(this.ConfigPath, "Workspace", "Path" A_Index, "")
            )

        this.VisitLog := []
        this.Sequence := IniRead(this.ConfigPath, "History", "Sequence", "0") + 0
        historyCount := IniRead(this.ConfigPath, "History", "Count", "0") + 0
        Loop Min(historyCount, this.MaxVisitLog) {
            path := this.NormalizePath(IniRead(this.ConfigPath, "History", "Path" A_Index, ""))
            at := IniRead(this.ConfigPath, "History", "Time" A_Index, "")
            seq := IniRead(this.ConfigPath, "History", "Seq" A_Index, "0") + 0
            source := IniRead(this.ConfigPath, "History", "Source" A_Index, "Explorer")
            if (path != "")
                this.VisitLog.Push({Seq: seq, Path: path, At: at, Source: source})
        }
        this.RebuildPathStats()

        this.Favorites := []
        favoriteCount := IniRead(this.ConfigPath, "Favorites", "Count", "0") + 0
        Loop favoriteCount {
            path := this.NormalizePath(IniRead(this.ConfigPath, "Favorites", "Path" A_Index, ""))
            if (path != "" && !this.FindPathIndex(this.Favorites, path))
                this.Favorites.Push(path)
        }

        this.SnapshotNames := []
        snapshotCount := IniRead(this.ConfigPath, "Snapshots", "Count", "0") + 0
        Loop snapshotCount {
            name := IniRead(this.ConfigPath, "Snapshots", "Name" A_Index, "")
            if (name != "")
                this.SnapshotNames.Push(name)
        }
    }

    SaveState(*) {
        IniWrite(this.SelectedSlot, this.ConfigPath, "Settings", "SelectedSlot")
        IniWrite(this.ViewMode = "Folder" ? this.CurrentPath : "", this.ConfigPath, "Settings", "CurrentPath")
        IniWrite(this.LastExplorerPath, this.ConfigPath, "Settings", "LastExplorerPath")
        this.SaveWorkspace()
        this.SaveHistory()
        this.SaveFavorites()
        this.SaveSnapshotNames()
    }

    SaveWorkspace() {
        try IniDelete(this.ConfigPath, "Workspace")
        Loop this.MaxSlots
            IniWrite(this.WorkspacePaths[A_Index], this.ConfigPath, "Workspace", "Path" A_Index)
        IniWrite(this.SelectedSlot, this.ConfigPath, "Settings", "SelectedSlot")
    }

    SaveHistory() {
        try IniDelete(this.ConfigPath, "History")
        IniWrite(this.Sequence, this.ConfigPath, "History", "Sequence")
        IniWrite(this.VisitLog.Length, this.ConfigPath, "History", "Count")
        for index, entry in this.VisitLog {
            IniWrite(entry.Path, this.ConfigPath, "History", "Path" index)
            IniWrite(entry.At, this.ConfigPath, "History", "Time" index)
            IniWrite(entry.Seq, this.ConfigPath, "History", "Seq" index)
            IniWrite(entry.Source, this.ConfigPath, "History", "Source" index)
        }
    }

    SaveFavorites() {
        try IniDelete(this.ConfigPath, "Favorites")
        IniWrite(this.Favorites.Length, this.ConfigPath, "Favorites", "Count")
        for index, path in this.Favorites
            IniWrite(path, this.ConfigPath, "Favorites", "Path" index)
    }

    SaveSnapshotNames() {
        try IniDelete(this.ConfigPath, "Snapshots")
        IniWrite(this.SnapshotNames.Length, this.ConfigPath, "Snapshots", "Count")
        for index, name in this.SnapshotNames
            IniWrite(name, this.ConfigPath, "Snapshots", "Name" index)
    }

    ; ------------------------------------------------------------------------
    ; General utilities
    ; ------------------------------------------------------------------------

    NormalizePath(path) {
        path := Trim(path "", " `t`r`n" Chr(34))
        path := StrReplace(path, "/", "\")
        if (path = "")
            return ""

        ; Preserve drive roots such as C:\ while removing other trailing slashes.
        if RegExMatch(path, "i)^[A-Z]:\\$")
            return path

        ; Preserve UNC share roots while still normalizing their trailing slash.
        if RegExMatch(path, "^\\\\[^\\]+\\[^\\]+\\?$")
            return RTrim(path, "\")

        return RTrim(path, "\")
    }

    ParentDirectory(path) {
        path := this.NormalizePath(path)
        if (path = "")
            return ""
        SplitPath(path, , &parent)
        return this.NormalizePath(parent)
    }

    PathDisplayName(path) {
        path := this.NormalizePath(path)
        if (path = "")
            return ""
        if RegExMatch(path, "i)^[A-Z]:\\$")
            return path
        SplitPath(path, &name)
        return name != "" ? name : path
    }

    FindPathIndex(array, path) {
        key := StrLower(this.NormalizePath(path))
        if (key = "")
            return 0
        for index, item in array {
            if (StrLower(this.NormalizePath(item)) = key)
                return index
        }
        return 0
    }

    FindTextIndex(array, value) {
        for index, item in array {
            if (StrLower(item) = StrLower(value))
                return index
        }
        return 0
    }

    FormatTimestamp(timestamp) {
        if (timestamp = "")
            return ""
        try return FormatTime(timestamp, "MM-dd HH:mm:ss")
        catch
            return timestamp
    }

    FormatBytes(bytes) {
        bytes += 0
        if (bytes < 1024)
            return bytes " B"
        if (bytes < 1024 ** 2)
            return Round(bytes / 1024, 1) " KB"
        if (bytes < 1024 ** 3)
            return Round(bytes / (1024 ** 2), 1) " MB"
        if (bytes < 1024 ** 4)
            return Round(bytes / (1024 ** 3), 2) " GB"
        return Round(bytes / (1024 ** 4), 2) " TB"
    }

    Quote(value) {
        return Chr(34) StrReplace(value, Chr(34), "'") Chr(34)
    }

    CopyText(text, *) {
        A_Clipboard := text
        ClipWait(0.75)
    }

    Truncate(text, maxLength) {
        if (StrLen(text) <= maxLength)
            return text
        return SubStr(text, 1, maxLength - 1) "…"
    }

    MenuSafe(text) {
        return StrReplace(text, "&", "&&")
    }

    IsMainGuiVisible() {
        if !this.GuiBuilt
            return false
        try return DllCall("IsWindowVisible", "Ptr", this.MainGui.Hwnd, "Int") != 0
        catch
            return false
    }

    SetStatus(text) {
        if this.GuiBuilt
            this.StatusText.Text := text
    }

    Notify(message) {
        if IsObject(this.ConsoleApp) {
            try {
                this.ConsoleApp.Notify(message)
                return
            }
        }
        ToolTip(message)
        SetTimer((*) => ToolTip(), -1800)
    }
}

OpenExplorerWorkspaceManager(*) {
    global ExplorerWorkspaceApp
    ExplorerWorkspaceApp.Show()
}

; Add the Explorer workspace system to the existing console command application.
global ExplorerWorkspaceApp := ExplorerWorkspaceManager(ConsoleMenuApp)

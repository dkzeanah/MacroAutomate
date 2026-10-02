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
;   Numpad1               Append new Explorer folders to permanent shortcuts.
;   Ctrl+Win+A            Open embedded AutoHotkey Script Hub.
;
; Every selected command is copied to the clipboard first. Depending on the
; selected send mode, the command is then pasted or pasted and executed in the
; console window that invoked the menu, the pinned target, or the last console.
; ============================================================================

SendMode("Input")
DetectHiddenWindows(true)
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
            "Numpad1`n"
            "Append newly opened Explorer folders to the permanent Desktop shortcut collection and open its nested action menu.`n`n"
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
        return SubStr(text, 1, maxLength - 1) "Ã¢â‚¬Â¦"
    }

    MenuSafe(text) {
        ; A single ampersand marks a menu accelerator, so double it for display.
        return StrReplace(text, "&", "&&")
    }
}

; Create the persistent global application object.
global ConsoleMenuApp := ConsoleCommandMenu()

; ============================================================================
; Everything 1.5 SDK v3 native wrapper
; Uses Everything3.dll directly from AutoHotkey v2. No ES.exe subprocess.
; ============================================================================
class Everything3SDK {
    __New(dllPath) {
        this.DllPath := dllPath
        this.DllVersion := ""
        this.Module := 0
        this.Client := 0
        this.InstanceName := ""
        this.VersionText := ""
        this.LastError := ""
        this.LastViewportDiagnostic := "Not tested yet."
        this.LastConnectAttempt := 0
        this.ConnectRetryMs := 3000
        this.Procs := Map()

        this.Load()
    }

    Load() {
        if this.Module
            return true

        if !FileExist(this.DllPath) {
            this.LastError := "Everything3.dll was not found: " this.DllPath
            return false
        }

        ; SDK 3.0.0.4+ includes Windows file-version metadata. Older DLLs may
        ; legitimately return a blank version string here.
        try this.DllVersion := FileGetVersion(this.DllPath)
        catch
            this.DllVersion := ""

        this.Module := DllCall(
            "Kernel32\LoadLibraryW",
            "Str", this.DllPath,
            "Ptr"
        )
        if !this.Module {
            this.LastError := "LoadLibraryW failed for Everything3.dll. Win32 error: " A_LastError
            return false
        }

        ; Viewport functions are intentionally NOT required. Some older SDK3
        ; DLL builds return FALSE from SetSearchViewportCount while still
        ; changing the search state. Search() probes this behavior and falls
        ; back to Everything's count:<n> syntax if necessary.
        requiredExports := [
            "Everything3_ConnectW",
            "Everything3_DestroyClient",
            "Everything3_CreateSearchState",
            "Everything3_DestroySearchState",
            "Everything3_SetSearchTextW",
            "Everything3_Search",
            "Everything3_DestroyResultList",
            "Everything3_GetResultListViewportCount",
            "Everything3_GetResultFullPathNameW",
            "Everything3_IsFolderResult"
        ]

        for exportName in requiredExports {
            proc := DllCall(
                "Kernel32\GetProcAddress",
                "Ptr", this.Module,
                "AStr", exportName,
                "Ptr"
            )
            if !proc {
                this.LastError := "Everything3.dll is missing required export: " exportName
                this.UnloadModule()
                return false
            }
            this.Procs[exportName] := proc
        }

        ; A missing/running-later Everything process is not fatal. The wrapper
        ; remains loaded and EnsureConnected() will retry when a search is made.
        this.EnsureConnected(true)
        return true
    }

    EnsureConnected(force := false) {
        if this.Client
            return true

        if !this.Module
            return false

        if !force && this.LastConnectAttempt {
            elapsed := A_TickCount - this.LastConnectAttempt
            if (elapsed >= 0 && elapsed < this.ConnectRetryMs)
                return false
        }
        this.LastConnectAttempt := A_TickCount

        ; Current Everything 1.5 builds normally use the unnamed/default IPC
        ; instance. Older alpha builds commonly used the explicit 1.5a instance.
        client := DllCall(this.Procs["Everything3_ConnectW"], "Ptr", 0, "Ptr")
        defaultError := A_LastError
        instanceName := "default"

        if !client {
            client := DllCall(this.Procs["Everything3_ConnectW"], "Str", "1.5a", "Ptr")
            alphaError := A_LastError
            instanceName := "1.5a"
        } else {
            alphaError := 0
        }

        if !client {
            this.LastError := (
                "Could not connect to Everything 1.5. Start Everything and make sure "
                "the Everything 1.5 IPC server is enabled.`n"
                "Unnamed instance error: " this.FormatErrorCode(defaultError) "`n"
                "1.5a instance error: " this.FormatErrorCode(alphaError)
            )
            return false
        }

        this.Client := client
        this.InstanceName := instanceName
        this.VersionText := this.ReadVersionText()
        this.LastError := ""
        return true
    }

    Reconnect() {
        this.DisconnectClient()
        this.LastConnectAttempt := 0
        return this.EnsureConnected(true)
    }

    Search(searchText, maxResults := 1000) {
        if (maxResults < 1)
            maxResults := 1

        if !this.EnsureConnected() {
            return {
                Ok: false,
                Results: [],
                ViewportCount: 0,
                Query: searchText,
                OriginalQuery: searchText,
                Error: this.LastError
            }
        }

        searchState := 0
        resultList := 0
        results := []

        try {
            searchState := DllCall(this.Procs["Everything3_CreateSearchState"], "Ptr")
            createError := A_LastError
            if !searchState
                throw Error("Everything3_CreateSearchState failed. SDK/Win32 error: " this.FormatErrorCode(createError))

            ; Ask for one extra row so the caller can tell that its display cap
            ; truncated the result set.
            requestedViewport := maxResults + 1
            effectiveQuery := searchText
            viewportConfirmed := false
            viewportSetter := this.GetOptionalProc("Everything3_SetSearchViewportCount")
            viewportGetter := this.GetOptionalProc("Everything3_GetSearchViewportCount")

            if viewportSetter {
                ; Clear the thread last-error value before the call so a FALSE +
                ; error 0 result is unambiguous.
                DllCall("Kernel32\SetLastError", "UInt", 0)
                setResult := DllCall(
                    viewportSetter,
                    "Ptr", searchState,
                    "UPtr", requestedViewport,
                    "Int"
                )
                setError := A_LastError

                if setResult {
                    viewportConfirmed := true
                    this.LastViewportDiagnostic := (
                        "SetSearchViewportCount returned TRUE for " requestedViewport "."
                    )
                } else if viewportGetter {
                    actualViewport := DllCall(
                        viewportGetter,
                        "Ptr", searchState,
                        "UPtr"
                    )
                    getError := A_LastError

                    if (actualViewport = requestedViewport) {
                        ; This is the exact case shown by the user's screenshot:
                        ; FALSE with error 0, but the state may still have changed.
                        ; Treat the getter as authoritative instead of aborting.
                        viewportConfirmed := true
                        this.LastViewportDiagnostic := (
                            "SetSearchViewportCount returned FALSE, but GetSearchViewportCount "
                            "confirmed " actualViewport ". Setter error: "
                            this.FormatErrorCode(setError) ". Treated as success."
                        )
                    } else {
                        this.LastViewportDiagnostic := (
                            "Viewport setter was not usable. Requested " requestedViewport
                            ", getter returned " actualViewport ". Setter error: "
                            this.FormatErrorCode(setError) ", getter error: "
                            this.FormatErrorCode(getError) ". Using count:<n> fallback."
                        )
                    }
                } else {
                    this.LastViewportDiagnostic := (
                        "SetSearchViewportCount returned FALSE ("
                        this.FormatErrorCode(setError)
                        ") and GetSearchViewportCount is unavailable. Using count:<n> fallback."
                    )
                }
            } else {
                this.LastViewportDiagnostic := (
                    "Viewport setter export is unavailable. Using count:<n> fallback."
                )
            }

            ; count:<n> is an official Everything search function. It is a safe
            ; compatibility fallback for older/broken SDK3 viewport setters and
            ; also prevents an unnecessarily large search from being processed.
            if !viewportConfirmed
                effectiveQuery := "count:" requestedViewport " " searchText

            DllCall("Kernel32\SetLastError", "UInt", 0)
            setTextResult := DllCall(
                this.Procs["Everything3_SetSearchTextW"],
                "Ptr", searchState,
                "Str", effectiveQuery,
                "Int"
            )
            setTextError := A_LastError
            if !setTextResult
                throw Error("Everything3_SetSearchTextW failed. SDK/Win32 error: " this.FormatErrorCode(setTextError))

            DllCall("Kernel32\SetLastError", "UInt", 0)
            resultList := DllCall(
                this.Procs["Everything3_Search"],
                "Ptr", this.Client,
                "Ptr", searchState,
                "Ptr"
            )
            searchError := A_LastError
            if !resultList
                throw Error("Everything3_Search failed. SDK/Win32 error: " this.FormatErrorCode(searchError))

            viewportCount := DllCall(
                this.Procs["Everything3_GetResultListViewportCount"],
                "Ptr", resultList,
                "UPtr"
            )

            ; Never enumerate more than the number we explicitly asked for,
            ; even if an old DLL reports an unexpectedly large viewport.
            enumerateCount := Min(viewportCount, requestedViewport)

            Loop enumerateCount {
                resultIndex := A_Index - 1

                ; SDK v3 returns the required UTF-16 character count (including
                ; the NUL) when bufsize is zero, so long paths are never clipped.
                requiredChars := DllCall(
                    this.Procs["Everything3_GetResultFullPathNameW"],
                    "Ptr", resultList,
                    "UPtr", resultIndex,
                    "Ptr", 0,
                    "UPtr", 0,
                    "UPtr"
                )
                if (requiredChars < 1)
                    continue

                pathBuffer := Buffer(requiredChars * 2, 0)
                copied := DllCall(
                    this.Procs["Everything3_GetResultFullPathNameW"],
                    "Ptr", resultList,
                    "UPtr", resultIndex,
                    "Ptr", pathBuffer.Ptr,
                    "UPtr", requiredChars,
                    "UPtr"
                )
                if !copied
                    continue

                fullPath := StrGet(pathBuffer.Ptr, "UTF-16")
                if (fullPath = "")
                    continue

                isFolder := DllCall(
                    this.Procs["Everything3_IsFolderResult"],
                    "Ptr", resultList,
                    "UPtr", resultIndex,
                    "Int"
                ) != 0

                results.Push({Path: fullPath, IsDirectory: isFolder})
            }

            this.LastError := ""
            return {
                Ok: true,
                Results: results,
                ViewportCount: viewportCount,
                Query: effectiveQuery,
                OriginalQuery: searchText,
                Error: ""
            }
        } catch as err {
            this.LastError := err.Message
            return {
                Ok: false,
                Results: [],
                ViewportCount: 0,
                Query: searchText,
                OriginalQuery: searchText,
                Error: err.Message
            }
        } finally {
            if resultList {
                try DllCall(
                    this.Procs["Everything3_DestroyResultList"],
                    "Ptr", resultList
                )
            }
            if searchState {
                try DllCall(
                    this.Procs["Everything3_DestroySearchState"],
                    "Ptr", searchState
                )
            }
        }
    }

    ReadVersionText() {
        names := [
            "Everything3_GetMajorVersion",
            "Everything3_GetMinorVersion",
            "Everything3_GetRevision",
            "Everything3_GetBuildNumber"
        ]
        values := []

        for exportName in names {
            proc := this.GetOptionalProc(exportName)
            if !proc
                return ""
            try values.Push(DllCall(proc, "Ptr", this.Client, "UInt"))
            catch
                return ""
        }

        return values[1] "." values[2] "." values[3] "." values[4]
    }

    GetOptionalProc(exportName) {
        if !this.Module
            return 0

        if this.Procs.Has(exportName)
            return this.Procs[exportName]

        proc := DllCall(
            "Kernel32\GetProcAddress",
            "Ptr", this.Module,
            "AStr", exportName,
            "Ptr"
        )
        if proc
            this.Procs[exportName] := proc
        return proc
    }

    FormatErrorCode(code) {
        ; Everything3_GetLastError is a wrapper around Windows GetLastError.
        ; AutoHotkey captures that value in A_LastError immediately after each
        ; DllCall, so pass the captured value here instead of making another
        ; DllCall that could overwrite the thread's last-error state.
        return Format("{} (0x{:08X})", code, code & 0xFFFFFFFF)
    }

    DisconnectClient() {
        if this.Client {
            try DllCall(
                this.Procs["Everything3_DestroyClient"],
                "Ptr", this.Client
            )
            this.Client := 0
        }
        this.InstanceName := ""
        this.VersionText := ""
    }

    UnloadModule() {
        this.DisconnectClient()
        if this.Module {
            try DllCall("Kernel32\FreeLibrary", "Ptr", this.Module, "Int")
            this.Module := 0
        }
        this.Procs := Map()
    }

    Close() {
        this.UnloadModule()
    }

    __Delete() {
        this.Close()
    }
}
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
;   Numpad1                  Add unseen open Explorer folders to the permanent
;                             Desktop shortcuts and show the action menu.
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


; ============================================================================
; Embedded AutoHotkey v2 Script Hub
; ----------------------------------------------------------------------------
; Shares the Explorer Workspace Manager GUI instead of creating a second main
; window. The existing %AppData%\AHKScriptHub database format is retained so
; prior run history, favorites, Always Start flags, tags, and notes survive.
; ============================================================================

class ScriptHubManager {
    __New(workspaceApp) {
        this.Workspace := workspaceApp
        this.DataDir := A_AppData "\AHKScriptHub"
        this.DbFile := this.DataDir "\scripts.tsv"
        this.DbBackupFile := this.DataDir "\scripts.tsv.bak"
        this.SnapshotFile := this.DataDir "\running_snapshot.tsv"
        this.ActivityLog := this.DataDir "\activity.log"
        this.StartupLink := A_Startup "\Developer Workspace Hub.lnk"

        this.Scripts := Map()
        this.Running := Map()
        this.SeenPids := Map()
        this.PrecountedPids := Map()
        this.BootSnapshot := []
        this.RestoreDone := false
        this.Wmi := 0
        this.WmiSink := 0
        this.ProcessTraceActive := false
        this.ShutdownInProgress := false
        this.GuiAttached := false
        this.LastRefreshSignature := ""
        this.ScanCallback := ObjBindMethod(this, "ScanRunningScripts")
        this.RestoreCallback := ObjBindMethod(this, "RestorePreviousSession")

        this.EnsureDataDirectory()
        this.LoadDatabase()
        this.BootSnapshot := this.LoadRunningSnapshot()
        this.InitWmi()
        this.StartProcessTrace()
        this.EnsureStartupShortcut()

        ; Ctrl+Win+A now opens the Script Hub page inside the combined GUI.
        try Hotkey("^#a", ObjBindMethod(this, "ShowPane"))

        this.ScanRunningScripts()
        SetTimer(this.ScanCallback, 750)
        SetTimer(this.RestoreCallback, -1800)
        OnMessage(0x0011, ObjBindMethod(this, "OnQueryEndSession"))
        OnMessage(0x0016, ObjBindMethod(this, "OnEndSession"))
        OnExit(ObjBindMethod(this, "Shutdown"))
    }

    AttachGui(searchEdit, presetCombo, filterCombo, listView, detailEdit, statusText) {
        this.SearchEdit := searchEdit
        this.PresetCombo := presetCombo
        this.FilterCombo := filterCombo
        this.List := listView
        this.DetailEdit := detailEdit
        this.StatusText := statusText
        this.GuiAttached := true

        this.SearchEdit.OnEvent("Change", ObjBindMethod(this, "RefreshList"))
        this.PresetCombo.OnEvent("Change", ObjBindMethod(this, "ApplyPreset"))
        this.FilterCombo.OnEvent("Change", ObjBindMethod(this, "RefreshList"))
        this.List.OnEvent("DoubleClick", ObjBindMethod(this, "OnDoubleClick"))
        this.List.OnEvent("ContextMenu", ObjBindMethod(this, "OnContextMenu"))
        this.List.OnEvent("Click", ObjBindMethod(this, "UpdateDetails"))
        this.List.OnEvent("ItemFocus", ObjBindMethod(this, "UpdateDetails"))
        this.RefreshList()
    }

    ShowPane(*) {
        if IsObject(this.Workspace)
            this.Workspace.ShowScriptHubPane()
    }

    EnsureDataDirectory() {
        if !DirExist(this.DataDir)
            DirCreate(this.DataDir)
    }

    EnsureStartupShortcut() {
        ; Keep one startup entry for the merged application. It launches the
        ; combined script, not a second standalone Script Hub process.
        try {
            FileCreateShortcut(
                A_AhkPath,
                this.StartupLink,
                A_ScriptDir,
                Chr(34) A_ScriptFullPath Chr(34),
                "Developer Workspace Hub"
            )
        }
    }

    NewRecord(path) {
        return {
            Path: path,
            RunCount: 0,
            FirstSeen: this.NowStamp(),
            LastRun: "",
            Favorite: 0,
            AlwaysStart: 0,
            Tags: "",
            Notes: ""
        }
    }

    EnsureRecord(path) {
        path := this.NormalizePath(path)
        key := this.PathKey(path)
        if (path = "")
            return 0
        if !this.Scripts.Has(key)
            this.Scripts[key] := this.NewRecord(path)
        return this.Scripts[key]
    }

    EncodeField(value) {
        s := value ""
        s := StrReplace(s, "%", "%25")
        s := StrReplace(s, "`t", "%09")
        s := StrReplace(s, "`r", "%0D")
        s := StrReplace(s, "`n", "%0A")
        return s
    }

    DecodeField(value) {
        s := value ""
        s := StrReplace(s, "%0A", "`n")
        s := StrReplace(s, "%0D", "`r")
        s := StrReplace(s, "%09", "`t")
        s := StrReplace(s, "%25", "%")
        return s
    }

    SafeInt(value, defaultValue := 0) {
        s := Trim(value "")
        if (s = "")
            return defaultValue
        return IsNumber(s) ? s + 0 : defaultValue
    }

    LoadDatabase() {
        this.Scripts := Map()
        if !FileExist(this.DbFile)
            return

        try text := FileRead(this.DbFile, "UTF-8")
        catch
            return

        for rawLine in StrSplit(text, "`n", "`r") {
            line := Trim(rawLine, "`r`n")
            if (line = "" || SubStr(line, 1, 1) = "#")
                continue
            fields := StrSplit(line, "`t")
            if (fields.Length < 8)
                continue

            path := this.NormalizePath(this.DecodeField(fields[1]))
            if (path = "")
                continue

            rec := {
                Path: path,
                RunCount: this.SafeInt(this.DecodeField(fields[2])),
                FirstSeen: this.DecodeField(fields[3]),
                LastRun: this.DecodeField(fields[4]),
                Favorite: this.SafeInt(this.DecodeField(fields[5])) ? 1 : 0,
                AlwaysStart: this.SafeInt(this.DecodeField(fields[6])) ? 1 : 0,
                Tags: this.DecodeField(fields[7]),
                Notes: this.DecodeField(fields[8])
            }
            this.Scripts[this.PathKey(path)] := rec
        }
    }

    SaveDatabase() {
        this.EnsureDataDirectory()
        tempFile := this.DbFile ".tmp"
        out := "# AHK Script Hub DB v1`n"
        for key, rec in this.Scripts {
            out .= this.EncodeField(rec.Path) "`t"
                . this.EncodeField(rec.RunCount) "`t"
                . this.EncodeField(rec.FirstSeen) "`t"
                . this.EncodeField(rec.LastRun) "`t"
                . this.EncodeField(rec.Favorite) "`t"
                . this.EncodeField(rec.AlwaysStart) "`t"
                . this.EncodeField(rec.Tags) "`t"
                . this.EncodeField(rec.Notes) "`n"
        }

        try {
            if FileExist(tempFile)
                FileDelete(tempFile)
            FileAppend(out, tempFile, "UTF-8")
            if FileExist(this.DbFile)
                try FileCopy(this.DbFile, this.DbBackupFile, 1)
            FileMove(tempFile, this.DbFile, 1)
        }
    }

    LoadRunningSnapshot() {
        entries := []
        if !FileExist(this.SnapshotFile)
            return entries
        try text := FileRead(this.SnapshotFile, "UTF-8")
        catch
            return entries

        for rawLine in StrSplit(text, "`n", "`r") {
            line := Trim(rawLine, "`r`n")
            if (line = "" || SubStr(line, 1, 1) = "#")
                continue
            fields := StrSplit(line, "`t")
            if (fields.Length < 2)
                continue
            path := this.NormalizePath(this.DecodeField(fields[1]))
            count := Max(1, this.SafeInt(this.DecodeField(fields[2]), 1))
            if (path != "" && !this.SamePath(path, A_ScriptFullPath))
                entries.Push({Path: path, Count: count})
        }
        return entries
    }

    SaveRunningSnapshot() {
        this.EnsureDataDirectory()
        counts := this.RunningCountsByPath()
        out := "# AHK Script Hub running snapshot v1`n"
        for key, info in counts
            out .= this.EncodeField(info.Path) "`t" this.EncodeField(info.Count) "`n"
        try FileDelete(this.SnapshotFile)
        try FileAppend(out, this.SnapshotFile, "UTF-8")
    }

    RunningCountsByPath() {
        counts := Map()
        for pid, inst in this.Running {
            if this.SamePath(inst.Path, A_ScriptFullPath)
                continue
            key := this.PathKey(inst.Path)
            if counts.Has(key)
                counts[key].Count += 1
            else
                counts[key] := {Path: inst.Path, Count: 1}
        }
        return counts
    }

    InitWmi() {
        try this.Wmi := ComObjGet("winmgmts:{impersonationLevel=impersonate}!\\.\root\cimv2")
        catch
            this.Wmi := 0
    }

    StartProcessTrace() {
        global EmbeddedScriptHubInstance
        if !IsObject(this.Wmi)
            return
        EmbeddedScriptHubInstance := this
        try {
            this.WmiSink := ComObject("WbemScripting.SWbemSink")
            ComObjConnect(this.WmiSink, "EmbeddedHubWmi_")
            this.Wmi.ExecNotificationQueryAsync(
                this.WmiSink,
                "SELECT * FROM Win32_ProcessStartTrace WHERE ProcessName LIKE 'AutoHotkey%.exe'"
            )
            this.ProcessTraceActive := true
        } catch {
            this.WmiSink := 0
            this.ProcessTraceActive := false
        }
    }

    OnWmiProcessStart(eventObj) {
        pid := 0
        name := ""
        try pid := eventObj.ProcessID + 0
        try name := eventObj.ProcessName ""
        if (!pid || !RegExMatch(name, "i)^AutoHotkey.*\.exe$"))
            return

        ; Give the hidden v2 main window a moment to appear; otherwise resolve
        ; the script path immediately from the process command line.
        path := ""
        hwnd := 0
        Loop 4 {
            try {
                for candidateHwnd in WinGetList("ahk_pid " pid " ahk_class AutoHotkey") {
                    title := WinGetTitle("ahk_id " candidateHwnd)
                    path := this.ParseV2MainWindowTitle(title)
                    if (path != "") {
                        hwnd := candidateHwnd
                        break
                    }
                }
            }
            if (path != "")
                break
            Sleep(20)
        }

        if (path = "" && IsObject(this.Wmi)) {
            try {
                for proc in this.Wmi.ExecQuery(
                    "SELECT ProcessId,ExecutablePath,CommandLine FROM Win32_Process WHERE ProcessId=" pid
                ) {
                    exe := ""
                    cmd := ""
                    try exe := proc.ExecutablePath ""
                    try cmd := proc.CommandLine ""
                    if this.IsV2Interpreter(exe, cmd)
                        path := this.ExtractAbsoluteAhkPath(cmd)
                    break
                }
            }
        }

        if (path = "" || this.SamePath(path, A_ScriptFullPath))
            return
        this.RegisterObserved(this.Running, pid, path, hwnd, "wmi_event")
        if this.GuiAttached
            this.RefreshList()
    }

    OnQueryEndSession(wParam, lParam, msg, hwnd) {
        this.ShutdownInProgress := true
        if this.RestoreDone
            try this.SaveRunningSnapshot()
        return 1
    }

    OnEndSession(wParam, lParam, msg, hwnd) {
        if !wParam {
            this.ShutdownInProgress := false
            try this.SaveRunningSnapshot()
        }
        return 0
    }

    ScanRunningScripts(*) {
        current := Map()

        ; Fast source: hidden AutoHotkey v2 main windows contain the absolute
        ; script path in their normal title.
        try {
            for hwnd in WinGetList("ahk_class AutoHotkey") {
                try {
                    title := WinGetTitle("ahk_id " hwnd)
                    pid := WinGetPID("ahk_id " hwnd)
                } catch {
                    continue
                }
                path := this.ParseV2MainWindowTitle(title)
                if (pid && path != "" && !this.SamePath(path, A_ScriptFullPath))
                    this.RegisterObserved(current, pid, path, hwnd, "window")
            }
        }

        ; Authoritative recovery: WMI catches scripts with changed/hidden main
        ; titles by reading the interpreter command line.
        if IsObject(this.Wmi) {
            try {
                query := "SELECT ProcessId,Name,ExecutablePath,CommandLine FROM Win32_Process WHERE Name LIKE 'AutoHotkey%.exe'"
                for proc in this.Wmi.ExecQuery(query) {
                    pid := 0
                    exe := ""
                    cmd := ""
                    try pid := proc.ProcessId + 0
                    try exe := proc.ExecutablePath ""
                    try cmd := proc.CommandLine ""
                    if !pid
                        continue
                    if current.Has(pid)
                        continue
                    if !this.IsV2Interpreter(exe, cmd)
                        continue
                    path := this.ExtractAbsoluteAhkPath(cmd)
                    if (path != "" && !this.SamePath(path, A_ScriptFullPath))
                        this.RegisterObserved(current, pid, path, 0, "wmi")
                }
            }
        }

        changed := !this.RunningMapsEqual(this.Running, current)
        this.Running := current

        for pid, key in this.CloneMap(this.SeenPids) {
            if !this.Running.Has(pid) {
                try {
                    if !ProcessExist(pid)
                        this.SeenPids.Delete(pid)
                } catch {
                    this.SeenPids.Delete(pid)
                }
            }
        }

        this.CleanupPrecountedPids()
        if changed && this.GuiAttached
            this.RefreshList()
    }

    RegisterObserved(targetMap, pid, path, hwnd := 0, source := "") {
        path := this.NormalizePath(path)
        if (path = "")
            return
        key := this.PathKey(path)

        if !this.SeenPids.Has(pid) {
            if this.PrecountedPids.Has(pid)
                this.PrecountedPids.Delete(pid)
            else
                this.RecordLaunch(path, source = "" ? "observed" : source, pid)
            this.SeenPids[pid] := key
        }

        targetMap[pid] := {
            PID: pid,
            Path: path,
            Hwnd: hwnd,
            Source: source
        }
    }

    RunningMapsEqual(a, b) {
        if (a.Count != b.Count)
            return false
        for pid, inst in b {
            if !a.Has(pid) || this.PathKey(a[pid].Path) != this.PathKey(inst.Path)
                return false
        }
        return true
    }

    CloneMap(source) {
        copy := Map()
        for key, value in source
            copy[key] := value
        return copy
    }

    ParseV2MainWindowTitle(title) {
        if RegExMatch(title, "i)^(.*\.ahk) - AutoHotkey v2(?:\.|$)", &m)
            return this.NormalizePath(m[1])
        return ""
    }

    IsV2Interpreter(exePath, commandLine := "") {
        if (exePath != "") {
            if InStr(exePath, "\AutoHotkey\v2\", false)
                return true
            try {
                version := FileGetVersion(exePath)
                if RegExMatch(version, "^2(?:\.|$)")
                    return true
            }
        }
        return InStr(commandLine, "\AutoHotkey\v2\", false) != 0
    }

    ExtractAbsoluteAhkPath(commandLine) {
        if (commandLine = "")
            return ""
        args := this.CommandLineToArray(commandLine)
        for arg in args {
            candidate := Trim(arg)
            if RegExMatch(candidate, "i)\.ahk$") && this.IsAbsolutePath(candidate)
                return this.NormalizePath(candidate)
        }
        return ""
    }

    CommandLineToArray(commandLine) {
        args := []
        argc := 0
        argvPtr := DllCall("Shell32\CommandLineToArgvW", "Str", commandLine, "Int*", &argc, "Ptr")
        if !argvPtr
            return args
        try {
            Loop argc {
                itemPtr := NumGet(argvPtr, (A_Index - 1) * A_PtrSize, "Ptr")
                args.Push(StrGet(itemPtr))
            }
        } finally {
            DllCall("LocalFree", "Ptr", argvPtr, "Ptr")
        }
        return args
    }

    CleanupPrecountedPids() {
        nowTick := A_TickCount
        for pid, expires in this.CloneMap(this.PrecountedPids) {
            diff := (nowTick - expires) & 0xFFFFFFFF
            if !(diff & 0x80000000)
                this.PrecountedPids.Delete(pid)
        }
    }

    RecordLaunch(path, reason, pid := 0) {
        rec := this.EnsureRecord(path)
        if !IsObject(rec)
            return
        rec.RunCount += 1
        rec.LastRun := this.NowStamp()
        if (rec.FirstSeen = "")
            rec.FirstSeen := rec.LastRun
        this.SaveDatabase()
        this.LogEvent("RUN", "reason=" reason " pid=" pid " count=" rec.RunCount " path=" rec.Path)
        if this.GuiAttached
            this.RefreshList()
    }

    RestorePreviousSession(*) {
        this.ScanRunningScripts()
        current := this.RunningCountsByPath()

        for entry in this.BootSnapshot {
            path := entry.Path
            if !FileExist(path)
                continue
            key := this.PathKey(path)
            already := current.Has(key) ? current[key].Count : 0
            needed := Max(0, entry.Count - already)
            Loop needed {
                if this.RunManaged(path, "startup_restore") {
                    if current.Has(key)
                        current[key].Count += 1
                    else
                        current[key] := {Path: path, Count: 1}
                    Sleep(40)
                }
            }
        }

        for key, rec in this.Scripts {
            if !rec.AlwaysStart || !FileExist(rec.Path)
                continue
            if !(current.Has(key) && current[key].Count > 0) {
                if this.RunManaged(rec.Path, "always_start")
                    current[key] := {Path: rec.Path, Count: 1}
            }
        }

        this.RestoreDone := true
        this.SaveRunningSnapshot()
        if this.GuiAttached
            this.RefreshList()
    }

    RunManaged(path, reason := "hub", asAdmin := false) {
        path := this.NormalizePath(path)
        if !FileExist(path) {
            MsgBox("The script no longer exists:`n`n" path, "Script Hub", "Icon!")
            return false
        }
        SplitPath(path, , &workingDir)
        command := this.Quote(A_AhkPath) " " this.Quote(path)
        if asAdmin
            command := "*RunAs " command
        try Run(command, workingDir, , &pid)
        catch as err {
            MsgBox("Could not run:`n" path "`n`n" err.Message, "Script Hub", "Iconx")
            return false
        }

        this.RecordLaunch(path, reason, pid)
        if pid {
            this.PrecountedPids[pid] := (A_TickCount + 10000) & 0xFFFFFFFF
            this.SeenPids[pid] := this.PathKey(path)
            this.Running[pid] := {PID: pid, Path: path, Hwnd: 0, Source: reason}
        }
        return true
    }

    StopPath(path) {
        key := this.PathKey(path)
        pids := []
        for pid, inst in this.Running {
            if (this.PathKey(inst.Path) = key)
                pids.Push(pid)
        }
        for pid in pids {
            closed := false
            try {
                for hwnd in WinGetList("ahk_pid " pid " ahk_class AutoHotkey") {
                    try {
                        WinClose("ahk_id " hwnd)
                        closed := true
                        break
                    }
                }
            }
            if closed {
                Loop 20 {
                    if !ProcessExist(pid)
                        break
                    Sleep(50)
                }
            }
            if ProcessExist(pid)
                try ProcessClose(pid)
        }
        Sleep(50)
        this.ScanRunningScripts()
    }

    RestartPath(path) {
        this.StopPath(path)
        Sleep(100)
        return this.RunManaged(path, "restart")
    }

    GetSelectedPaths() {
        paths := []
        if !this.GuiAttached
            return paths
        row := 0
        while (row := this.List.GetNext(row)) {
            path := this.List.GetText(row, 9)
            if (path != "")
                paths.Push(path)
        }
        return paths
    }

    RunSelected(*) {
        for path in this.GetSelectedPaths()
            this.RunManaged(path, "gui_batch_run")
    }

    RunAdminSelected(*) {
        for path in this.GetSelectedPaths()
            this.RunManaged(path, "gui_batch_admin", true)
    }

    RestartSelected(*) {
        for path in this.GetSelectedPaths()
            this.RestartPath(path)
    }

    StopSelected(*) {
        for path in this.GetSelectedPaths()
            this.StopPath(path)
    }

    OpenVSCodeSelected(*) {
        paths := this.GetSelectedPaths()
        if (paths.Length)
            this.Workspace.OpenVSCodePaths(paths)
    }

    OpenFoldersSelected(*) {
        paths := this.GetSelectedPaths()
        if (paths.Length)
            this.Workspace.OpenContainingFoldersBatch(paths)
    }

    OpenEverythingSelected(*) {
        paths := this.GetSelectedPaths()
        if (paths.Length)
            this.Workspace.OpenEverythingPaths(paths)
    }

    CopySelected(*) {
        paths := this.GetSelectedPaths()
        if (paths.Length)
            this.Workspace.CopyPaths(paths)
    }

    ToggleFavoriteSelected(*) {
        paths := this.GetSelectedPaths()
        if !paths.Length
            return
        allSet := true
        for path in paths {
            rec := this.EnsureRecord(path)
            if !rec.Favorite {
                allSet := false
                break
            }
        }
        newValue := allSet ? 0 : 1
        for path in paths
            this.EnsureRecord(path).Favorite := newValue
        this.SaveDatabase()
        this.RefreshList()
    }

    ToggleAlwaysSelected(*) {
        paths := this.GetSelectedPaths()
        if !paths.Length
            return
        allSet := true
        for path in paths {
            rec := this.EnsureRecord(path)
            if !rec.AlwaysStart {
                allSet := false
                break
            }
        }
        newValue := allSet ? 0 : 1
        for path in paths
            this.EnsureRecord(path).AlwaysStart := newValue
        this.SaveDatabase()
        this.RefreshList()
    }

    AddScript(*) {
        path := FileSelect(1, A_Desktop, "Add AutoHotkey v2 script", "AutoHotkey scripts (*.ahk)")
        if (path = "" || this.SamePath(path, A_ScriptFullPath))
            return
        this.EnsureRecord(path)
        this.SaveDatabase()
        this.RefreshList()
    }

    ImportFolder(*) {
        folder := DirSelect(A_Desktop, 3, "Recursively import AutoHotkey scripts")
        if (folder = "")
            return
        found := 0
        added := 0
        Loop Files folder "\*.ahk", "FR" {
            found += 1
            path := this.NormalizePath(A_LoopFileFullPath)
            if this.SamePath(path, A_ScriptFullPath)
                continue
            key := this.PathKey(path)
            if !this.Scripts.Has(key) {
                this.Scripts[key] := this.NewRecord(path)
                added += 1
            }
        }
        this.SaveDatabase()
        this.RefreshList()
        this.Workspace.Notify("Imported " added " new scripts from " found " AHK files.")
    }

    RemoveSelected(*) {
        paths := this.GetSelectedPaths()
        if !paths.Length
            return
        answer := MsgBox(
            "Remove " paths.Length " selected script record" (paths.Length = 1 ? "" : "s") " from history?`n`nThe actual .ahk files will not be deleted.",
            "Script Hub",
            "YesNo Icon?"
        )
        if (answer != "Yes")
            return
        for path in paths {
            key := this.PathKey(path)
            if this.Scripts.Has(key)
                this.Scripts.Delete(key)
        }
        this.SaveDatabase()
        this.RefreshList()
    }

    EditMetadataSelected(*) {
        paths := this.GetSelectedPaths()
        if !paths.Length
            return
        if (paths.Length > 1) {
            MsgBox("Tags / Notes editing is single-item. Select one script for detailed metadata editing.", "Script Hub", "Iconi")
            return
        }
        this.EditMetadata(paths[1])
    }

    EditMetadata(path) {
        rec := this.EnsureRecord(path)
        metaGui := Gui("+AlwaysOnTop", "Tags / Notes - Script Hub")
        metaGui.SetFont("s9", "Segoe UI")
        metaGui.AddText("xm ym w600", rec.Path)
        metaGui.AddText("xm y+14", "Tags:")
        tagsEdit := metaGui.AddEdit("xm y+4 w600", rec.Tags)
        favoriteCheck := metaGui.AddCheckbox("xm y+12", "Favorite")
        favoriteCheck.Value := rec.Favorite
        alwaysCheck := metaGui.AddCheckbox("x+18 yp", "Always start at login")
        alwaysCheck.Value := rec.AlwaysStart
        metaGui.AddText("xm y+14", "Notes:")
        notesEdit := metaGui.AddEdit("xm y+4 w600 r10 WantTab", rec.Notes)
        saveButton := metaGui.AddButton("xm y+12 w100 Default", "Save")
        cancelButton := metaGui.AddButton("x+8 w100", "Cancel")
        saveButton.OnEvent("Click", (*) => this.SaveMetadata(metaGui, path, tagsEdit, favoriteCheck, alwaysCheck, notesEdit))
        cancelButton.OnEvent("Click", (*) => metaGui.Destroy())
        metaGui.OnEvent("Escape", (*) => metaGui.Destroy())
        metaGui.Show()
    }

    SaveMetadata(guiObj, path, tagsEdit, favoriteCheck, alwaysCheck, notesEdit) {
        rec := this.EnsureRecord(path)
        rec.Tags := tagsEdit.Value
        rec.Favorite := favoriteCheck.Value ? 1 : 0
        rec.AlwaysStart := alwaysCheck.Value ? 1 : 0
        rec.Notes := notesEdit.Value
        this.SaveDatabase()
        guiObj.Destroy()
        this.RefreshList()
    }

    ShowMoreMenu(*) {
        ; "menu := Menu()" self-shadows the built-in Menu class because AHK
        ; identifiers are case-insensitive. Use a distinct local name.
        moreMenu := Menu()
        moreMenu.Add("Run selected as Administrator", ObjBindMethod(this, "RunAdminSelected"))
        moreMenu.Add("Relocate selected script...", ObjBindMethod(this, "RelocateSelected"))
        moreMenu.Add("Remove selected from history", ObjBindMethod(this, "RemoveSelected"))
        moreMenu.Add()
        moreMenu.Add("Export history CSV...", ObjBindMethod(this, "ExportCsv"))
        moreMenu.Add("Open activity log", ObjBindMethod(this, "OpenActivityLog"))
        moreMenu.Add("Restore previous session now", ObjBindMethod(this, "RestorePreviousSession"))
        moreMenu.Add("Scan running scripts now", ObjBindMethod(this, "ScanRunningScripts"))
        moreMenu.Show()
    }

    RelocateSelected(*) {
        paths := this.GetSelectedPaths()
        if (paths.Length != 1) {
            MsgBox("Select exactly one stored script to relocate.", "Script Hub", "Iconi")
            return
        }
        oldPath := paths[1]
        oldKey := this.PathKey(oldPath)
        if !this.Scripts.Has(oldKey)
            return
        rec := this.Scripts[oldKey]
        newPath := FileSelect(1, rec.Path, "Locate replacement/moved AutoHotkey script", "AutoHotkey scripts (*.ahk)")
        if (newPath = "")
            return
        newPath := this.NormalizePath(newPath)
        newKey := this.PathKey(newPath)
        if this.SamePath(newPath, A_ScriptFullPath)
            return

        if (newKey != oldKey) {
            if this.Scripts.Has(newKey) {
                existing := this.Scripts[newKey]
                existing.RunCount += rec.RunCount
                if (existing.FirstSeen = "" || (rec.FirstSeen != "" && rec.FirstSeen < existing.FirstSeen))
                    existing.FirstSeen := rec.FirstSeen
                if (rec.LastRun > existing.LastRun)
                    existing.LastRun := rec.LastRun
                existing.Favorite := existing.Favorite || rec.Favorite
                existing.AlwaysStart := existing.AlwaysStart || rec.AlwaysStart
                if (existing.Tags = "")
                    existing.Tags := rec.Tags
                else if (rec.Tags != "" && !InStr(existing.Tags, rec.Tags))
                    existing.Tags .= ", " rec.Tags
                if (existing.Notes = "")
                    existing.Notes := rec.Notes
                else if (rec.Notes != "")
                    existing.Notes .= "`r`n`r`n[Merged old record]`r`n" rec.Notes
                this.Scripts.Delete(oldKey)
            } else {
                this.Scripts.Delete(oldKey)
                rec.Path := newPath
                this.Scripts[newKey] := rec
            }
        } else {
            rec.Path := newPath
        }
        this.SaveDatabase()
        this.RefreshList()
    }

    ExportCsv(*) {
        defaultPath := A_Desktop "\\AHK_Script_Hub_History_" FormatTime(, "yyyyMMdd_HHmmss") ".csv"
        path := FileSelect("S16", defaultPath, "Export Script Hub history", "CSV files (*.csv)")
        if (path = "")
            return
        if !RegExMatch(path, "i)\.csv$")
            path .= ".csv"
        out := "Favorite,Script,Runs,Status,Last Run,First Seen,Always Start,Tags,Notes,Path`r`n"
        runningCounts := this.RunningCountsByPath()
        for key, rec in this.Scripts {
            SplitPath(rec.Path, &name)
            exists := !!FileExist(rec.Path)
            running := runningCounts.Has(key) ? runningCounts[key].Count : 0
            status := exists ? (running ? "Running (" running ")" : "Stopped") : "MISSING"
            out .= this.Csv(rec.Favorite ? "Yes" : "No") ","
                . this.Csv(name) ","
                . this.Csv(rec.RunCount) ","
                . this.Csv(status) ","
                . this.Csv(rec.LastRun) ","
                . this.Csv(rec.FirstSeen) ","
                . this.Csv(rec.AlwaysStart ? "Yes" : "No") ","
                . this.Csv(rec.Tags) ","
                . this.Csv(rec.Notes) ","
                . this.Csv(rec.Path) "`r`n"
        }
        try {
            if FileExist(path)
                FileDelete(path)
            FileAppend(out, path, "UTF-8")
            Run("explorer.exe /select," this.Quote(path))
        } catch as err {
            MsgBox("Could not export CSV.`n`n" err.Message, "Script Hub", "Icon!")
        }
    }

    Csv(value) {
        s := value ""
        s := StrReplace(s, Chr(34), Chr(34) Chr(34))
        return Chr(34) s Chr(34)
    }

    OpenActivityLog(*) {
        if !FileExist(this.ActivityLog)
            try FileAppend("", this.ActivityLog, "UTF-8")
        try Run("notepad.exe " this.Quote(this.ActivityLog))
    }

    ApplyPreset(*) {
        if !this.GuiAttached
            return
        label := this.PresetCombo.Text
        presets := Map(
            "Examples / smart filters", "",
            "Running now", "running:true",
            "Favorites", "fav:true",
            "Always start", "always:true",
            "Missing scripts", "missing:true",
            "Run 10+ times", "runs:>10",
            "Run today", "lastrun:today",
            "Scripts on Desktop", "path:desktop",
            "Tagged automation", "tag:automation",
            "Recently modified files", "modified:past24hours"
        )
        if presets.Has(label) {
            this.SearchEdit.Value := presets[label]
            this.RefreshList()
        }
    }

    RefreshList(*) {
        if !this.GuiAttached || !IsObject(this.List)
            return

        selectedKeys := Map()
        for path in this.GetSelectedPaths()
            selectedKeys[this.PathKey(path)] := true

        query := Trim(this.SearchEdit.Value)
        filterText := this.FilterCombo.Text
        runningCounts := this.RunningCountsByPath()

        this.List.Opt("-Redraw")
        this.List.Delete()
        displayed := 0

        ; Favorites first, then normal records, matching the original hub.
        for favoritePass in [1, 0] {
            for key, rec in this.Scripts {
                if (rec.Favorite != favoritePass)
                    continue
                exists := !!FileExist(rec.Path)
                running := runningCounts.Has(key) ? runningCounts[key].Count : 0
                if !this.PassesFilter(rec, filterText, exists, running)
                    continue
                if !this.MatchesSmartQuery(rec, query, exists, running)
                    continue

                SplitPath(rec.Path, &name)
                status := exists ? (running ? "Running (" running ")" : "Stopped") : "MISSING"
                iconIndex := this.Workspace.GetShellIconIndex(rec.Path)
                options := iconIndex >= 0 ? "Icon" (iconIndex + 1) : ""
                row := this.List.Add(
                    options,
                    rec.Favorite ? "★" : "",
                    name,
                    rec.RunCount,
                    status,
                    rec.LastRun,
                    rec.FirstSeen,
                    rec.AlwaysStart ? "Yes" : "",
                    rec.Tags,
                    rec.Path
                )
                if selectedKeys.Has(key)
                    this.List.Modify(row, "Select")
                displayed += 1
            }
        }

        this.List.Opt("+Redraw")
        this.UpdateStatus(displayed)
    }

    PassesFilter(rec, filterText, exists, running) {
        switch filterText {
            case "Running":
                return running > 0
            case "Favorites":
                return rec.Favorite
            case "Always start":
                return rec.AlwaysStart
            case "Missing":
                return !exists
            default:
                return true
        }
    }

    MatchesSmartQuery(rec, query, exists, running) {
        if (query = "")
            return true
        SplitPath(rec.Path, &name)
        searchable := StrLower(name " " rec.Path " " rec.Tags " " rec.Notes)
        tokens := this.TokenizeQuery(query)

        for token in tokens {
            negate := false
            if (SubStr(token, 1, 1) = "!") {
                negate := true
                token := SubStr(token, 2)
            }
            matched := this.MatchSmartToken(token, rec, name, searchable, exists, running)
            if negate
                matched := !matched
            if !matched
                return false
        }
        return true
    }

    TokenizeQuery(query) {
        tokens := []
        current := ""
        quoted := false
        Loop Parse query {
            ch := A_LoopField
            if (ch = Chr(34)) {
                quoted := !quoted
                continue
            }
            if (!quoted && (ch = " " || ch = "`t")) {
                if (current != "") {
                    tokens.Push(current)
                    current := ""
                }
            } else {
                current .= ch
            }
        }
        if (current != "")
            tokens.Push(current)
        return tokens
    }

    MatchSmartToken(token, rec, name, searchable, exists, running) {
        lower := StrLower(token)
        if !InStr(lower, ":")
            return InStr(searchable, lower) != 0

        colon := InStr(lower, ":")
        key := SubStr(lower, 1, colon - 1)
        value := SubStr(lower, colon + 1)
        switch key {
            case "running":
                return (value = "true" || value = "1" || value = "yes") ? running > 0 : running = 0
            case "fav", "favorite":
                return (value = "true" || value = "1" || value = "yes") ? !!rec.Favorite : !rec.Favorite
            case "always":
                return (value = "true" || value = "1" || value = "yes") ? !!rec.AlwaysStart : !rec.AlwaysStart
            case "missing":
                return (value = "true" || value = "1" || value = "yes") ? !exists : exists
            case "tag":
                return InStr(StrLower(rec.Tags), value) != 0
            case "path":
                return InStr(StrLower(rec.Path), value) != 0
            case "name":
                return InStr(StrLower(name), value) != 0
            case "runs":
                if RegExMatch(value, "^([<>]=?|=)?(\d+)$", &m) {
                    op := m[1] = "" ? "=" : m[1]
                    n := m[2] + 0
                    switch op {
                        case ">": return rec.RunCount > n
                        case ">=": return rec.RunCount >= n
                        case "<": return rec.RunCount < n
                        case "<=": return rec.RunCount <= n
                        default: return rec.RunCount = n
                    }
                }
                return false
            case "lastrun":
                if (value = "today")
                    return SubStr(rec.LastRun, 1, 10) = FormatTime(, "yyyy-MM-dd")
                return InStr(StrLower(rec.LastRun), value) != 0
            case "modified":
                if !exists
                    return false
                try modified := FileGetTime(rec.Path, "M")
                catch
                    return false
                if (value = "past24hours")
                    return DateDiff(A_Now, modified, "Hours") <= 24
                if (value = "today")
                    return SubStr(modified, 1, 8) = FormatTime(, "yyyyMMdd")
                return true
        }
        return InStr(searchable, lower) != 0
    }

    OnDoubleClick(ctrl, row) {
        if (row <= 0)
            return
        path := ctrl.GetText(row, 9)
        if (path != "")
            this.RunManaged(path, "double_click")
    }

    OnContextMenu(ctrl, row, isRightClick, x, y) {
        if (row <= 0)
            return
        ; Preserve an existing multi-selection. If the right-clicked row was not
        ; selected, make it the sole focus/selection just like Explorer does.
        selected := false
        selectedRow := 0
        while (selectedRow := ctrl.GetNext(selectedRow)) {
            if (selectedRow = row) {
                selected := true
                break
            }
        }
        if !selected {
            ctrl.Modify(0, "-Select")
            ctrl.Modify(row, "Select Focus")
        } else {
            ctrl.Modify(row, "Focus")
        }
        paths := this.GetSelectedPaths()
        this.Workspace.ShowPathActionPalette(paths, "script", x, y)
    }

    UpdateDetails(*) {
        if !this.GuiAttached
            return
        paths := this.GetSelectedPaths()
        if (paths.Length = 0) {
            this.DetailEdit.Value := ""
            return
        }
        if (paths.Length > 1) {
            totalRuns := 0
            running := 0
            for path in paths {
                rec := this.EnsureRecord(path)
                totalRuns += rec.RunCount
                key := this.PathKey(path)
                for pid, inst in this.Running {
                    if (this.PathKey(inst.Path) = key)
                        running += 1
                }
            }
            this.DetailEdit.Value := paths.Length " scripts selected | Recorded runs: " totalRuns " | Running instances: " running
            return
        }
        rec := this.EnsureRecord(paths[1])
        this.DetailEdit.Value := (
            rec.Path "`r`nRuns: " rec.RunCount
            " | Last run: " rec.LastRun
            " | First seen: " rec.FirstSeen
            " | Favorite: " (rec.Favorite ? "Yes" : "No")
            " | Always start: " (rec.AlwaysStart ? "Yes" : "No")
            (rec.Tags != "" ? "`r`nTags: " rec.Tags : "")
            (rec.Notes != "" ? "`r`nNotes: " rec.Notes : "")
        )
    }

    UpdateStatus(displayed := -1) {
        if !this.GuiAttached
            return
        if (displayed < 0)
            displayed := this.List.GetCount()
        totalRuns := 0
        for key, rec in this.Scripts
            totalRuns += rec.RunCount
        this.StatusText.Text := (
            "Script Hub | Showing: " displayed
            " | Tracked: " this.Scripts.Count
            " | Running instances: " this.Running.Count
            " | Recorded launches: " totalRuns
            " | Hotkey: Ctrl+Win+A"
        )
    }

    Shutdown(exitReason := "", exitCode := 0, *) {
        global EmbeddedScriptHubInstance
        try SetTimer(this.ScanCallback, 0)
        if !this.ShutdownInProgress {
            try this.ScanRunningScripts()
            try this.SaveRunningSnapshot()
        }
        try this.SaveDatabase()
        try {
            if IsObject(this.Wmi) && IsObject(this.WmiSink)
                this.Wmi.CancelAsyncCall(this.WmiSink)
        }
        try {
            if IsObject(this.WmiSink)
                ComObjConnect(this.WmiSink)
        }
        EmbeddedScriptHubInstance := 0
        this.LogEvent("EXIT", "reason=" exitReason " code=" exitCode)
    }

    NormalizePath(path) {
        path := Trim(path "", " `t`r`n" Chr(34))
        if (path = "")
            return ""
        path := StrReplace(path, "/", "\")
        if !this.IsAbsolutePath(path)
            path := A_WorkingDir "\" path
        ; IMPORTANT: AutoHotkey identifiers are case-insensitive.
        ; Do not name this local variable "buffer", because that shadows the
        ; built-in Buffer class on the right-hand side (buffer := Buffer(...)).
        pathBuffer := Buffer(32768 * 2, 0)
        length := DllCall(
            "GetFullPathNameW",
            "Str", path,
            "UInt", 32768,
            "Ptr", pathBuffer.Ptr,
            "Ptr", 0,
            "UInt"
        )
        if (length > 0 && length < 32768)
            path := StrGet(pathBuffer.Ptr)
        if (StrLen(path) > 3 && SubStr(path, -1) = "\")
            path := RTrim(path, "\")
        return path
    }

    IsAbsolutePath(path) {
        return RegExMatch(path, "i)^[A-Z]:\\") || (SubStr(path, 1, 2) = "\\")
    }

    PathKey(path) {
        return StrLower(this.NormalizePath(path))
    }

    SamePath(a, b) {
        return (a != "" && b != "" && this.PathKey(a) = this.PathKey(b))
    }

    Quote(value) {
        return Chr(34) value Chr(34)
    }

    NowStamp() {
        return FormatTime(, "yyyy-MM-dd HH:mm:ss")
    }

    LogEvent(kind, message) {
        try {
            clean := StrReplace(message "", "`r", " ")
            clean := StrReplace(clean, "`n", " ")
            clean := StrReplace(clean, "`t", " ")
            FileAppend(this.NowStamp() "`t" kind "`t" clean "`r`n", this.ActivityLog, "UTF-8")
        }
    }
}

class ExplorerWorkspaceManager {
    __New(consoleApp := 0) {
        this.ConsoleApp := consoleApp
        this.ConfigPath := A_ScriptDir "\ExplorerWorkspaceManager.ini"
        this.MaxSlots := 10
        this.MaxVisitLog := 500
        this.MaxDisplayedItems := 10000

        ; Everything 1.5 SDK v3 search backend. Prefer the DLL beside this
        ; application, then fall back to the exact library path requested.
        this.EverythingDllPath := A_ScriptDir "\lib\Everything3.dll"
        if !FileExist(this.EverythingDllPath)
            this.EverythingDllPath := "C:\Users\Don\Desktop\aAutomateMacro\lib\Everything3.dll"
        this.Everything := Everything3SDK(this.EverythingDllPath)
        this.UsedEverythingThisRefresh := false
        this.UsedLocalThisRefresh := false
        this.LastEverythingQuery := ""
        this.LastSearchBackend := "Idle"
        this.ScriptHubMode := false
        this.ActionPalette := 0
        this.ShellVerbObjects := []
        this.SystemImageList := 0

        ; Script Hub shares this manager's GUI and Windows shell helpers.
        this.ScriptHub := ScriptHubManager(this)

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

        ; Numpad1 maintains an append-only, physical shortcut collection on the
        ; user's redirected Desktop. Existing .lnk files are never removed or
        ; rebuilt automatically; unseen folder targets receive the next number.
        this.ExplorerShortcutFolder := A_Desktop "\Explorer Window Shortcuts"
        this.ExplorerShortcutMenu := 0
        this.ExplorerShortcutSubmenus := []
        this.MaxRunnableCandidates := 30

        ; Responsive GUI state. The tab strip grows vertically to display every
        ; wrapped live/workspace tab instead of clipping rows behind the toolbar.
        this.LastGuiWidth := 1320
        this.LastGuiHeight := 780
        this.TabStripHeight := 34
        this.AutoMaximizeGui := true
        this.FullscreenActive := false
        this.FullscreenRestore := 0
        this.LayoutTimerCallback := ObjBindMethod(this, "ApplyResponsiveLayout")

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
        Hotkey("Numpad1", ObjBindMethod(this, "ShowExplorerShortcutMenu"))
        Hotkey("NumpadEnd", ObjBindMethod(this, "ShowExplorerShortcutMenu"))

        this.InitializeExplorerWatcher()
        SetTimer(this.ExplorerPollCallback, 350)
        OnExit(ObjBindMethod(this, "SaveState"))
        OnExit(ObjBindMethod(this, "ShutdownExplorerWatcher"))
        OnExit(ObjBindMethod(this, "ShutdownEverything"))
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

        if this.AutoMaximizeGui
            this.MainGui.Show("Maximize")
        else
            this.MainGui.Show("w1320 h780")

        ; The native tab control reports its final wrapped row count only after
        ; it has been shown. Re-run layout once that measurement is available.
        this.RequestResponsiveLayout()
        this.FilterEdit.Focus()
    }

    BuildGui() {
        this.MainGui := Gui("+Resize +MinSize1000x620", "Developer Workspace Hub — Explorer + Script Hub + Everything3")
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
        ; Gui.UseTab does not exist in AutoHotkey v2. UseTab belongs to the
        ; Tab control and an empty call places subsequent controls outside all pages.
        this.BrowserTabControl.UseTab()

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
            "Workspace slots",
            "AHK Script Hub"
        ])
        this.SourceCombo.Choose(1)
        this.SourceCombo.OnEvent("Change", ObjBindMethod(this, "OnSourceComboChanged"))
        this.ScriptHubQuickButton := this.MainGui.Add("Button", "x250 y90 w80 h28", "Scripts")
        this.ScriptHubQuickButton.OnEvent("Click", ObjBindMethod(this, "ToggleScriptHubPane"))

        this.SourceList := this.MainGui.Add("ListView", "x10 y124 w320 h505 Grid +Multi", [
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


        ; Everything-style smart search presets. When Smart syntax is checked,
        ; the filter edit is passed directly to Everything3 after the current
        ; parent:/ancestor: scope is prepended.
        this.SmartSearchPresets := Map(
            "Examples / developer searches", "",
            "Code modified today", "dm:today ext:ahk;py;pyw;cs;csx;js;ts;tsx;jsx;html;css;json;ps1;bat;cmd;sh;cpp;c;h;hpp;java;go;rs",
            "Code modified in 24 hours", "dm:past24hours ext:ahk;py;pyw;cs;js;ts;tsx;html;css;json;ps1;cpp;c;h;hpp;go;rs",
            "AutoHotkey scripts", "ext:ahk",
            "Python source", "ext:py;pyw;pyi",
            "C# / .NET", "ext:cs;csx;csproj;sln;props;targets",
            "Web source", "ext:html;htm;css;scss;js;mjs;cjs;jsx;ts;tsx;json;vue;svelte",
            "Project manifests", "<package.json|pyproject.toml|requirements.txt|*.sln|*.csproj|Cargo.toml|go.mod|CMakeLists.txt|Makefile|Dockerfile>",
            "Git metadata folders", "folder: .git",
            "Large developer files > 1 MB", "size:>1mb ext:ahk;py;cs;js;ts;tsx;json;xml;log;txt",
            "Zero-byte files", "size:0",
            "Archives", "ext:zip;7z;rar;tar;gz;bz2;xz",
            "Logs / traces", "ext:log;trace;out;err",
            "TODO / FIXME content", "content:<TODO|FIXME|HACK>"
        )
        presetLabels := []
        for label, queryText in this.SmartSearchPresets
            presetLabels.Push(label)
        this.SmartPresetCombo := this.MainGui.Add("ComboBox", "x346 y124 w430", presetLabels)
        this.SmartPresetCombo.Choose(1)
        this.SmartPresetCombo.OnEvent("Change", ObjBindMethod(this, "ApplySmartSearchPreset"))

        this.SmartSyntaxCheck := this.MainGui.Add("CheckBox", "x784 y126 w122 h22 Checked", "Smart syntax")
        this.SmartSyntaxCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))

        ; --------------------------------------------------------------------
        ; Visible Everything3 SDK controls.
        ; The native DLL was previously an invisible search backend. These
        ; controls make the active backend, connection/version, and exact SDK
        ; query visible directly inside the Explorer Workspace Manager.
        ; --------------------------------------------------------------------
        this.EverythingEnableCheck := this.MainGui.Add(
            "CheckBox",
            "x346 y156 w150 h24 Checked",
            "Use Everything3 DLL"
        )
        this.EverythingEnableCheck.OnEvent("Click", ObjBindMethod(this, "QueueRefresh"))

        this.EverythingInfoText := this.MainGui.Add(
            "Text",
            "x502 y156 w570 h24 +0x200",
            "Everything3: initializing..."
        )

        this.EverythingStatusButton := this.MainGui.Add("Button", "x1078 y154 w100 h28", "SDK Status")
        this.EverythingStatusButton.OnEvent("Click", ObjBindMethod(this, "ShowEverythingStatus"))

        this.EverythingReconnectButton := this.MainGui.Add("Button", "x1184 y154 w126 h28", "Reconnect SDK")
        this.EverythingReconnectButton.OnEvent("Click", ObjBindMethod(this, "ReconnectEverything"))

        this.EverythingQueryLabel := this.MainGui.Add("Text", "x346 y188 w64 h24 +0x200", "SDK Query")
        this.EverythingQueryEdit := this.MainGui.Add(
            "Edit",
            "x414 y186 w786 h26 ReadOnly -Wrap",
            "(no Everything3 SDK query has run yet)"
        )
        this.EverythingCopyQueryButton := this.MainGui.Add("Button", "x1206 y184 w104 h28", "Copy Query")
        this.EverythingCopyQueryButton.OnEvent("Click", ObjBindMethod(this, "CopyEverythingQuery"))

        this.FileList := this.MainGui.Add("ListView", "x346 y222 w964 h407 Grid AltSubmit +Multi", [
            "Name", "Type", "Size", "Modified", "Source", "Engine", "Full path"
        ])
        this.FileList.ModifyCol(1, 255)
        this.FileList.ModifyCol(2, 105)
        this.FileList.ModifyCol(3, 84)
        this.FileList.ModifyCol(4, 138)
        this.FileList.ModifyCol(5, 125)
        this.FileList.ModifyCol(6, 105)
        this.FileList.ModifyCol(7, 0)
        this.FileList.OnEvent("DoubleClick", ObjBindMethod(this, "OpenFileListItem"))
        this.FileList.OnEvent("Click", ObjBindMethod(this, "UpdateSelectionDetails"))
        this.FileList.OnEvent("ItemFocus", ObjBindMethod(this, "UpdateSelectionDetails"))
        this.FileList.OnEvent("ContextMenu", ObjBindMethod(this, "ShowFileContextMenu"))


        ; --------------------------------------------------------------------
        ; Embedded Script Hub pane. These controls occupy the main content area
        ; only while "AHK Script Hub" is selected in SourceCombo.
        ; --------------------------------------------------------------------
        this.ScriptSearchLabel := this.MainGui.Add("Text", "x10 y124 w52 h24 +0x200 Hidden", "Search")
        this.ScriptSearchEdit := this.MainGui.Add("Edit", "x66 y122 w350 h26 Hidden")
        this.ScriptPresetCombo := this.MainGui.Add("ComboBox", "x424 y122 w250 Hidden", [
            "Examples / smart filters",
            "Running now",
            "Favorites",
            "Always start",
            "Missing scripts",
            "Run 10+ times",
            "Run today",
            "Scripts on Desktop",
            "Tagged automation",
            "Recently modified files"
        ])
        this.ScriptPresetCombo.Choose(1)
        this.ScriptFilterCombo := this.MainGui.Add("ComboBox", "x682 y122 w150 Hidden", [
            "All scripts", "Running", "Favorites", "Always start", "Missing"
        ])
        this.ScriptFilterCombo.Choose(1)

        this.ScriptRunButton := this.MainGui.Add("Button", "x10 y156 w82 h28 Hidden", "▶ Run")
        this.ScriptRestartButton := this.MainGui.Add("Button", "x98 y156 w90 h28 Hidden", "↻ Restart")
        this.ScriptStopButton := this.MainGui.Add("Button", "x194 y156 w82 h28 Hidden", "■ Stop")
        this.ScriptVSCodeButton := this.MainGui.Add("Button", "x282 y156 w100 h28 Hidden", "VS Code")
        this.ScriptFolderButton := this.MainGui.Add("Button", "x388 y156 w104 h28 Hidden", "Explorer")
        this.ScriptEverythingButton := this.MainGui.Add("Button", "x498 y156 w110 h28 Hidden", "Everything")
        this.ScriptAddButton := this.MainGui.Add("Button", "x614 y156 w94 h28 Hidden", "+ Script")
        this.ScriptImportButton := this.MainGui.Add("Button", "x714 y156 w104 h28 Hidden", "Import Folder")
        this.ScriptMetaButton := this.MainGui.Add("Button", "x824 y156 w100 h28 Hidden", "Tags / Notes")
        this.ScriptFavoriteButton := this.MainGui.Add("Button", "x930 y156 w94 h28 Hidden", "★ Favorite")
        this.ScriptAlwaysButton := this.MainGui.Add("Button", "x1030 y156 w104 h28 Hidden", "Always Start")
        this.ScriptCopyButton := this.MainGui.Add("Button", "x1140 y156 w90 h28 Hidden", "Copy Paths")
        this.ScriptRemoveButton := this.MainGui.Add("Button", "x1236 y156 w74 h28 Hidden", "More")

        this.ScriptList := this.MainGui.Add("ListView", "x10 y192 w1300 h437 Grid AltSubmit +Multi Hidden", [
            "Fav", "Script", "Runs", "Status", "Last Run", "First Seen", "Always", "Tags", "Path"
        ])
        this.ScriptList.ModifyCol(1, 42)
        this.ScriptList.ModifyCol(2, 210)
        this.ScriptList.ModifyCol(3, 60)
        this.ScriptList.ModifyCol(4, 105)
        this.ScriptList.ModifyCol(5, 145)
        this.ScriptList.ModifyCol(6, 145)
        this.ScriptList.ModifyCol(7, 65)
        this.ScriptList.ModifyCol(8, 150)
        this.ScriptList.ModifyCol(9, 390)
        this.ScriptDetailEdit := this.MainGui.Add("Edit", "x10 y636 w1300 h88 ReadOnly -Wrap VScroll Hidden")

        ; Attach shell icons to both content grids.
        this.AttachShellImageList(this.FileList)
        this.AttachShellImageList(this.ScriptList)

        ; Bind Script Hub buttons directly to batch-aware manager methods.
        this.ScriptRunButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "RunSelected"))
        this.ScriptRestartButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "RestartSelected"))
        this.ScriptStopButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "StopSelected"))
        this.ScriptVSCodeButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "OpenVSCodeSelected"))
        this.ScriptFolderButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "OpenFoldersSelected"))
        this.ScriptEverythingButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "OpenEverythingSelected"))
        this.ScriptAddButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "AddScript"))
        this.ScriptImportButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "ImportFolder"))
        this.ScriptMetaButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "EditMetadataSelected"))
        this.ScriptFavoriteButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "ToggleFavoriteSelected"))
        this.ScriptAlwaysButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "ToggleAlwaysSelected"))
        this.ScriptCopyButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "CopySelected"))
        this.ScriptRemoveButton.OnEvent("Click", ObjBindMethod(this.ScriptHub, "ShowMoreMenu"))

        this.DetailEdit := this.MainGui.Add("Edit", "x346 y636 w964 h88 ReadOnly -Wrap VScroll")
        this.StatusText := this.MainGui.Add("Text", "x10 y735 w1300 h24 +0x200", "Ready")

        this.ScriptHub.AttachGui(
            this.ScriptSearchEdit,
            this.ScriptPresetCombo,
            this.ScriptFilterCombo,
            this.ScriptList,
            this.ScriptDetailEdit,
            this.StatusText
        )

        this.GuiBuilt := true
        this.UpdateSlotButtons()
        this.UpdateEverythingGuiStatus("Idle")
    }

    HideGui(*) {
        this.MainGui.Hide()
    }

    OnGuiSize(guiObj, minMax, width, height) {
        if (minMax = -1 || !this.GuiBuilt)
            return

        this.LastGuiWidth := width
        this.LastGuiHeight := height

        margin := 10
        tabY := 8

        ; Give the native tab control temporary vertical room, query its actual
        ; wrapped row count, then shrink it to exactly the required height.
        provisionalTabHeight := Min(260, Max(72, Floor(height * 0.30)))
        this.BrowserTabControl.Move(margin, tabY, width - (margin * 2), provisionalTabHeight)
        tabRows := this.GetBrowserTabRowCount()
        this.TabStripHeight := this.ClampValue((tabRows * 26) + 8, 34, Max(34, Floor(height * 0.31)))
        this.BrowserTabControl.Move(margin, tabY, width - (margin * 2), this.TabStripHeight)

        toolbarY := tabY + this.TabStripHeight + 6
        toolbarHeight := 28

        ; Navigation and address bar. The address edit absorbs all horizontal
        ; growth while the action buttons remain fully visible at the right.
        this.BackButton.Move(10, toolbarY, 44, toolbarHeight)
        this.ForwardButton.Move(58, toolbarY, 58, toolbarHeight)
        this.UpButton.Move(120, toolbarY, 42, toolbarHeight)
        this.RefreshButton.Move(166, toolbarY, 58, toolbarHeight)

        addressX := 232
        fixedActionWidth := 568
        addressWidth := Max(180, width - addressX - fixedActionWidth)
        this.AddressEdit.Move(addressX, toolbarY, addressWidth, toolbarHeight)

        goX := addressX + addressWidth + 6
        this.GoButton.Move(goX, toolbarY, 42, toolbarHeight)
        this.PrevLiveButton.Move(goX + 48, toolbarY, 70, toolbarHeight)
        this.NextLiveButton.Move(goX + 124, toolbarY, 70, toolbarHeight)
        this.FocusLiveButton.Move(goX + 200, toolbarY, 76, toolbarHeight)
        this.CombinedButton.Move(goX + 282, toolbarY, 104, toolbarHeight)
        this.RealTabsButton.Move(goX + 392, toolbarY, 96, toolbarHeight)
        this.MenuButton.Move(goX + 494, toolbarY, Max(54, width - margin - (goX + 494)), toolbarHeight)

        ; Scale the source pane with the client width instead of leaving a fixed
        ; 320-pixel column on every monitor and resolution.
        leftWidth := this.ClampValue(Round(width * 0.23), 280, 420)
        rightX := margin + leftWidth + 16
        rightWidth := Max(360, width - rightX - margin)
        filterY := toolbarY + toolbarHeight + 14

        quickButtonWidth := 82
        this.SourceCombo.Move(margin, filterY, Max(120, leftWidth - quickButtonWidth - 6))
        this.ScriptHubQuickButton.Move(margin + leftWidth - quickButtonWidth, filterY - 2, quickButtonWidth, 28)

        if this.ScriptHubMode {
            ; Script Hub uses the full client width below the source selector.
            searchY := filterY + 34
            searchLabelWidth := 52
            presetWidth := this.ClampValue(Round(width * 0.20), 210, 310)
            filterWidth := 150
            searchEditX := margin + searchLabelWidth + 4
            filterX := width - margin - filterWidth
            presetX := filterX - 6 - presetWidth
            searchEditWidth := Max(180, presetX - 6 - searchEditX)

            this.ScriptSearchLabel.Move(margin, searchY + 2, searchLabelWidth, 24)
            this.ScriptSearchEdit.Move(searchEditX, searchY, searchEditWidth, 26)
            this.ScriptPresetCombo.Move(presetX, searchY, presetWidth)
            this.ScriptFilterCombo.Move(filterX, searchY, filterWidth)

            buttonY := searchY + 34
            buttons := [
                this.ScriptRunButton, this.ScriptRestartButton, this.ScriptStopButton,
                this.ScriptVSCodeButton, this.ScriptFolderButton, this.ScriptEverythingButton,
                this.ScriptAddButton, this.ScriptImportButton, this.ScriptMetaButton,
                this.ScriptFavoriteButton, this.ScriptAlwaysButton, this.ScriptCopyButton,
                this.ScriptRemoveButton
            ]
            usable := width - (margin * 2)
            gap := 5
            buttonWidth := Max(68, Floor((usable - gap * (buttons.Length - 1)) / buttons.Length))
            xPos := margin
            for button in buttons {
                button.Move(xPos, buttonY, buttonWidth, 28)
                xPos += buttonWidth + gap
            }

            statusHeight := 24
            statusY := height - statusHeight - 6
            detailHeight := this.ClampValue(Round(height * 0.13), 88, 150)
            detailY := statusY - detailHeight - 8
            listY := buttonY + 36
            listHeight := Max(150, detailY - listY - 8)
            this.ScriptList.Move(margin, listY, width - (margin * 2), listHeight)
            this.ScriptDetailEdit.Move(margin, detailY, width - (margin * 2), detailHeight)
            this.StatusText.Move(margin, statusY, width - (margin * 2), statusHeight)
            this.ResizeScriptHubColumns(width - (margin * 2))
            return
        }

        ; The filter controls use one row on a wide/fullscreen window and wrap
        ; into two rows on smaller widths. No filter widget is allowed to extend
        ; outside the client area.
        filterLabelWidth := 38
        typeWidth := 150
        clearWidth := 102
        helpWidth := 88
        hiddenWidth := 96
        recursiveWidth := 82
        regexWidth := 62
        controlGap := 6

        wideFilterThreshold := 860
        if (rightWidth >= wideFilterThreshold) {
            clearX := rightX + rightWidth - clearWidth
            helpX := clearX - controlGap - helpWidth
            hiddenX := helpX - controlGap - hiddenWidth
            recursiveX := hiddenX - controlGap - recursiveWidth
            regexX := recursiveX - controlGap - regexWidth
            typeX := regexX - controlGap - typeWidth
            filterEditX := rightX + filterLabelWidth + controlGap
            filterWidth := Max(130, typeX - controlGap - filterEditX)

            this.FilterLabel.Move(rightX, filterY + 2, filterLabelWidth, 22)
            this.FilterEdit.Move(filterEditX, filterY, filterWidth, 26)
            this.TypeCombo.Move(typeX, filterY, typeWidth)
            this.RegexCheck.Move(regexX, filterY + 2, regexWidth, 22)
            this.RecursiveCheck.Move(recursiveX, filterY + 2, recursiveWidth, 22)
            this.HiddenCheck.Move(hiddenX, filterY + 2, hiddenWidth, 22)
            this.FilterHelpButton.Move(helpX, filterY - 2, helpWidth, 28)
            this.ClearFilterButton.Move(clearX, filterY - 2, clearWidth, 28)
            contentTop := filterY + 34
        } else {
            typeX := rightX + rightWidth - typeWidth
            filterEditX := rightX + filterLabelWidth + controlGap
            filterWidth := Max(120, typeX - controlGap - filterEditX)
            secondFilterY := filterY + 32

            this.FilterLabel.Move(rightX, filterY + 2, filterLabelWidth, 22)
            this.FilterEdit.Move(filterEditX, filterY, filterWidth, 26)
            this.TypeCombo.Move(typeX, filterY, typeWidth)

            this.RegexCheck.Move(rightX, secondFilterY + 2, regexWidth, 22)
            this.RecursiveCheck.Move(rightX + regexWidth + 8, secondFilterY + 2, recursiveWidth, 22)
            this.HiddenCheck.Move(rightX + regexWidth + recursiveWidth + 16, secondFilterY + 2, hiddenWidth, 22)
            this.FilterHelpButton.Move(rightX + rightWidth - clearWidth - helpWidth - controlGap, secondFilterY - 2, helpWidth, 28)
            this.ClearFilterButton.Move(rightX + rightWidth - clearWidth, secondFilterY - 2, clearWidth, 28)
            contentTop := secondFilterY + 34
        }

        ; Developer smart-query preset row plus two visible Everything3 SDK
        ; telemetry rows.
        sourceContentTop := contentTop
        smartPresetY := contentTop
        smartCheckWidth := 124
        smartComboWidth := Max(160, rightWidth - smartCheckWidth - 8)
        this.SmartPresetCombo.Move(rightX, smartPresetY, smartComboWidth)
        this.SmartSyntaxCheck.Move(rightX + smartComboWidth + 8, smartPresetY + 2, smartCheckWidth, 22)

        everythingStatusY := smartPresetY + 32
        everythingQueryY := everythingStatusY + 32
        rightContentTop := everythingQueryY + 34

        everythingCheckWidth := this.ClampValue(Round(rightWidth * 0.18), 142, 178)
        sdkStatusWidth := 92
        reconnectWidth := 108
        actionGap := 6
        statusButtonX := rightX + rightWidth - reconnectWidth - actionGap - sdkStatusWidth
        reconnectX := rightX + rightWidth - reconnectWidth
        infoX := rightX + everythingCheckWidth + 8
        infoWidth := Max(120, statusButtonX - actionGap - infoX)

        this.EverythingEnableCheck.Move(rightX, everythingStatusY + 2, everythingCheckWidth, 24)
        this.EverythingInfoText.Move(infoX, everythingStatusY + 2, infoWidth, 24)
        this.EverythingStatusButton.Move(statusButtonX, everythingStatusY - 2, sdkStatusWidth, 28)
        this.EverythingReconnectButton.Move(reconnectX, everythingStatusY - 2, reconnectWidth, 28)

        queryLabelWidth := 64
        copyQueryWidth := 94
        queryEditX := rightX + queryLabelWidth + 4
        copyQueryX := rightX + rightWidth - copyQueryWidth
        queryEditWidth := Max(120, copyQueryX - actionGap - queryEditX)
        this.EverythingQueryLabel.Move(rightX, everythingQueryY + 2, queryLabelWidth, 24)
        this.EverythingQueryEdit.Move(queryEditX, everythingQueryY, queryEditWidth, 26)
        this.EverythingCopyQueryButton.Move(copyQueryX, everythingQueryY - 2, copyQueryWidth, 28)

        statusHeight := 24
        statusY := height - statusHeight - 6
        detailHeight := this.ClampValue(Round(height * 0.13), 88, 150)
        detailY := statusY - detailHeight - 8
        sourceListHeight := Max(170, detailY - sourceContentTop - 8)
        fileListHeight := Max(140, detailY - rightContentTop - 8)
        sourceButtonY := detailY

        this.SourceList.Move(margin, sourceContentTop, leftWidth, sourceListHeight)

        sourceButtonGap := 6
        sourceButtonWidth := Floor((leftWidth - (sourceButtonGap * 2)) / 3)
        this.AddActiveButton.Move(margin, sourceButtonY, sourceButtonWidth, 28)
        this.AddSelectedButton.Move(margin + sourceButtonWidth + sourceButtonGap, sourceButtonY, sourceButtonWidth, 28)
        this.CaptureButton.Move(margin + ((sourceButtonWidth + sourceButtonGap) * 2), sourceButtonY, sourceButtonWidth, 28)

        this.FileList.Move(rightX, rightContentTop, rightWidth, fileListHeight)
        this.DetailEdit.Move(rightX, detailY, rightWidth, detailHeight)
        this.StatusText.Move(margin, statusY, width - (margin * 2), statusHeight)

        this.ResizeResponsiveColumns(leftWidth, rightWidth)
    }


    ResizeScriptHubColumns(width) {
        if !this.GuiBuilt
            return
        fixed := 42 + 64 + 110 + 140 + 140 + 68
        remaining := Max(300, width - fixed)
        nameWidth := this.ClampValue(Round(remaining * 0.28), 160, 300)
        tagWidth := this.ClampValue(Round(remaining * 0.18), 100, 220)
        pathWidth := Max(180, width - (fixed + nameWidth + tagWidth + 24))
        try this.ScriptList.ModifyCol(1, 42)
        try this.ScriptList.ModifyCol(2, nameWidth)
        try this.ScriptList.ModifyCol(3, 64)
        try this.ScriptList.ModifyCol(4, 110)
        try this.ScriptList.ModifyCol(5, 140)
        try this.ScriptList.ModifyCol(6, 140)
        try this.ScriptList.ModifyCol(7, 68)
        try this.ScriptList.ModifyCol(8, tagWidth)
        try this.ScriptList.ModifyCol(9, pathWidth)
    }

    RequestResponsiveLayout(*) {
        if !this.GuiBuilt
            return
        SetTimer(this.LayoutTimerCallback, 0)
        SetTimer(this.LayoutTimerCallback, -35)
    }

    ApplyResponsiveLayout(*) {
        if !this.GuiBuilt
            return

        try {
            WinGetClientPos(&clientX, &clientY, &clientWidth, &clientHeight, "ahk_id " this.MainGui.Hwnd)
            if (clientWidth > 0 && clientHeight > 0)
                this.OnGuiSize(this.MainGui, 0, clientWidth, clientHeight)
        }
    }

    GetBrowserTabRowCount() {
        if !this.GuiBuilt || !this.BrowserTabControl.Hwnd
            return 1

        ; TCM_GETROWCOUNT = TCM_FIRST + 44 = 0x132C.
        try rows := DllCall(
            "SendMessageW",
            "Ptr", this.BrowserTabControl.Hwnd,
            "UInt", 0x132C,
            "Ptr", 0,
            "Ptr", 0,
            "Ptr"
        )
        catch
            rows := 1

        return Max(1, rows)
    }

    ResizeResponsiveColumns(leftWidth, rightWidth) {
        if !this.GuiBuilt
            return

        ; Source list columns: #, Folder, hidden Path, Visits, Last visited.
        sourceUsable := Max(250, leftWidth - 22)
        sourceNumberWidth := 48
        sourceVisitsWidth := 58
        sourceLastWidth := 108
        sourceFolderWidth := Max(92, sourceUsable - sourceNumberWidth - sourceVisitsWidth - sourceLastWidth)
        this.SourceList.ModifyCol(1, sourceNumberWidth)
        this.SourceList.ModifyCol(2, sourceFolderWidth)
        this.SourceList.ModifyCol(3, 0)
        this.SourceList.ModifyCol(4, sourceVisitsWidth)
        this.SourceList.ModifyCol(5, sourceLastWidth)

        ; File list columns scale proportionally. Engine is deliberately visible
        ; so each row shows whether it came from Everything3 or local AHK.
        ; Full path remains hidden as the final column.
        fileUsable := Max(330, rightWidth - 24)
        nameWidth := Max(160, Round(fileUsable * 0.30))
        typeWidth := Max(82, Round(fileUsable * 0.11))
        sizeWidth := Max(72, Round(fileUsable * 0.09))
        modifiedWidth := Max(120, Round(fileUsable * 0.17))
        engineWidth := Max(90, Round(fileUsable * 0.12))
        sourceWidth := Max(100, fileUsable - nameWidth - typeWidth - sizeWidth - modifiedWidth - engineWidth)
        this.FileList.ModifyCol(1, nameWidth)
        this.FileList.ModifyCol(2, typeWidth)
        this.FileList.ModifyCol(3, sizeWidth)
        this.FileList.ModifyCol(4, modifiedWidth)
        this.FileList.ModifyCol(5, sourceWidth)
        this.FileList.ModifyCol(6, engineWidth)
        this.FileList.ModifyCol(7, 0)
    }

    BuildResponsiveBrowserTabLabels(models) {
        labels := []
        count := models.Length
        if (count = 0)
            return labels

        width := this.LastGuiWidth > 0 ? this.LastGuiWidth : A_ScreenWidth
        targetRows := count <= 18 ? 1 : count <= 36 ? 2 : count <= 60 ? 3 : 4
        if (width < 1400 && count > 18)
            targetRows += 1

        usableWidth := Max(760, width - 24)
        estimatedTabWidth := (usableWidth * targetRows) / count
        maxCaptionChars := this.ClampValue(Floor((estimatedTabWidth - 46) / 7), 6, 22)

        for model in models {
            switch model.Kind {
                case "Explorer":
                    caption := model.HasOwnProp("Title") ? model.Title : ""
                    if (caption = "")
                        caption := this.PathDisplayName(model.Path)
                    labels.Push(
                        "E" model.WindowOrdinal "." model.TabOrdinal ": "
                        this.Truncate(caption, maxCaptionChars)
                    )
                case "Workspace":
                    caption := model.Path = "" ? "(empty)" : this.PathDisplayName(model.Path)
                    if (model.Path != "" && !DirExist(model.Path))
                        caption .= " !"
                    labels.Push("S" model.Slot ": " this.Truncate(caption, maxCaptionChars))
                case "Combined":
                    labels.Push("Combined")
            }
        }
        return labels
    }

    ClampValue(value, minimum, maximum) {
        return Min(maximum, Max(minimum, value))
    }

    MaximizeGui(*) {
        if !this.GuiBuilt
            return
        try WinMaximize("ahk_id " this.MainGui.Hwnd)
        this.RequestResponsiveLayout()
    }

    ToggleFullscreen(*) {
        if !this.GuiBuilt
            return

        hwnd := this.MainGui.Hwnd
        if !this.FullscreenActive {
            try WinGetPos(&restoreX, &restoreY, &restoreW, &restoreH, "ahk_id " hwnd)
            catch
                return

            this.FullscreenRestore := {
                X: restoreX,
                Y: restoreY,
                W: restoreW,
                H: restoreH,
                WasMaximized: WinGetMinMax("ahk_id " hwnd) = 1
            }

            monitorHandle := DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")
            monitorInfo := Buffer(40, 0)
            NumPut("UInt", 40, monitorInfo, 0)
            if !DllCall("GetMonitorInfoW", "Ptr", monitorHandle, "Ptr", monitorInfo.Ptr)
                return

            monitorLeft := NumGet(monitorInfo, 4, "Int")
            monitorTop := NumGet(monitorInfo, 8, "Int")
            monitorRight := NumGet(monitorInfo, 12, "Int")
            monitorBottom := NumGet(monitorInfo, 16, "Int")

            this.MainGui.Opt("-Caption -Border")
            WinRestore("ahk_id " hwnd)
            WinMove(
                monitorLeft,
                monitorTop,
                monitorRight - monitorLeft,
                monitorBottom - monitorTop,
                "ahk_id " hwnd
            )
            this.FullscreenActive := true
        } else {
            restore := this.FullscreenRestore
            this.MainGui.Opt("+Caption +Border")
            if IsObject(restore) {
                WinMove(restore.X, restore.Y, restore.W, restore.H, "ahk_id " hwnd)
                if restore.WasMaximized
                    WinMaximize("ahk_id " hwnd)
            }
            this.FullscreenActive := false
        }

        this.RequestResponsiveLayout()
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

    ; ------------------------------------------------------------------------
    ; Desktop Explorer shortcut launcher (Numpad1)
    ; ------------------------------------------------------------------------

    ShowExplorerShortcutMenu(*) {
        ; Every invocation adds only open folder targets that are not already
        ; represented by a saved .lnk. Existing shortcuts persist indefinitely.
        try this.AppendOpenExplorerShortcuts(false)
        catch as err {
            MsgBox(
                "Could not update the Explorer shortcut collection.`n`n" err.Message,
                "Explorer Shortcut Menu",
                "Icon!"
            )
        }

        this.BuildExplorerShortcutMenu()
        this.ExplorerShortcutMenu.Show()
    }

    AppendOpenExplorerShortcuts(forceNotice := true, *) {
        if !DirExist(this.ExplorerShortcutFolder)
            DirCreate(this.ExplorerShortcutFolder)

        collection := this.ScanExplorerShortcutCollection()
        entries := this.GetOpenExplorerWindows(false)
        if (entries.Length = 0) {
            if forceNotice {
                this.Notify(
                    "No open Explorer folders were found. All " collection.Count
                    . " saved shortcut" (collection.Count = 1 ? " was" : "s were")
                    . " preserved."
                )
            }
            return 0
        }

        added := 0
        nextSequence := collection.MaxSequence + 1
        seenThisRefresh := Map()
        for entry in entries {
            path := this.NormalizePath(entry.Path)
            pathKey := StrLower(path)
            if (
                path = ""
                || collection.Targets.Has(pathKey)
                || seenThisRefresh.Has(pathKey)
            )
                continue

            seenThisRefresh[pathKey] := true
            title := entry.Title != "" ? entry.Title : this.PathDisplayName(entry.Path)
            title := this.CleanShortcutFileName(title)

            ; Sequence numbers never reset. If a user-created file happens to
            ; occupy the next filename, advance until a free permanent number
            ; is available without touching the existing item.
            Loop {
                fileName := "Explorer - " Format("{:06}", nextSequence)
                    . " - " title ".lnk"
                linkPath := this.ExplorerShortcutFolder "\" fileName
                if !FileExist(linkPath)
                    break
                nextSequence += 1
            }

            linkPath := this.ExplorerShortcutFolder "\" fileName
            description := "Permanent Explorer folder #" nextSequence ": " path

            try {
                FileCreateShortcut(
                    path,
                    linkPath,
                    path,
                    "",
                    description
                )
                added += 1
                collection.Targets[pathKey] := true
                nextSequence += 1
            } catch as err {
                OutputDebug(
                    "Explorer shortcut creation failed: " linkPath " | " err.Message
                )
            }
        }

        if forceNotice {
            total := collection.Count + added
            if (added = 0)
                this.Notify("No new Explorer folders found. " total " shortcuts remain saved.")
            else
                this.Notify(
                    "Added " added " new Explorer shortcut" (added = 1 ? "" : "s")
                    . ". Permanent total: " total "."
                )
        }
        return added
    }

    ScanExplorerShortcutCollection() {
        targets := Map()
        maxSequence := 0
        shortcutCount := 0

        if !DirExist(this.ExplorerShortcutFolder) {
            return {
                Targets: targets,
                MaxSequence: maxSequence,
                Count: shortcutCount
            }
        }

        Loop Files this.ExplorerShortcutFolder "\*.lnk", "F" {
            shortcutCount += 1

            target := ""
            try FileGetShortcut(A_LoopFileFullPath, &target)
            catch
                target := ""

            target := this.NormalizePath(target)
            if (target != "")
                targets[StrLower(target)] := true

            if RegExMatch(
                A_LoopFileName,
                "i)^Explorer - (\d+) - ",
                &sequenceMatch
            ) {
                sequence := sequenceMatch[1] + 0
                if (sequence > maxSequence)
                    maxSequence := sequence
            }
        }

        return {
            Targets: targets,
            MaxSequence: maxSequence,
            Count: shortcutCount
        }
    }

    RefreshExplorerShortcutMenu(*) {
        this.AppendOpenExplorerShortcuts(true)
        this.BuildExplorerShortcutMenu()
        this.ExplorerShortcutMenu.Show()
    }

    BuildExplorerShortcutMenu() {
        links := this.LoadExplorerShortcutLinks()
        mainMenu := Menu()
        this.ExplorerShortcutSubmenus := []

        if (links.Length = 0) {
            emptyLabel := "(No Explorer folder shortcuts saved)"
            mainMenu.Add(emptyLabel, (*) => 0)
            mainMenu.Disable(emptyLabel)
        } else {
            for index, link in links {
                actionMenu := this.BuildExplorerFolderActionMenu(link)
                this.ExplorerShortcutSubmenus.Push(actionMenu)
                label := Format("{:06}", index) ". " link.DisplayName
                label := this.Truncate(label, 92)
                mainMenu.Add(this.MenuSafe(label), actionMenu)
            }
        }

        mainMenu.Add()
        mainMenu.Add(
            "Add new open Explorer folders (append only)",
            ObjBindMethod(this, "RefreshExplorerShortcutMenu")
        )
        mainMenu.Add(
            "Open Desktop shortcut collection",
            ObjBindMethod(this, "OpenExplorerShortcutFolder")
        )
        mainMenu.Add(
            "Open full Explorer Workspace Manager",
            ObjBindMethod(this, "Show")
        )
        this.ExplorerShortcutMenu := mainMenu
    }

    LoadExplorerShortcutLinks() {
        links := []
        if !DirExist(this.ExplorerShortcutFolder)
            return links

        discoveryOrder := 0
        Loop Files this.ExplorerShortcutFolder "\*.lnk", "F" {
            discoveryOrder += 1
            target := ""
            workingDir := ""
            arguments := ""
            description := ""
            try FileGetShortcut(
                A_LoopFileFullPath,
                &target,
                &workingDir,
                &arguments,
                &description
            )
            catch
                continue

            target := this.NormalizePath(target)
            if (target = "")
                continue

            SplitPath(A_LoopFileName, , , , &nameWithoutExtension)
            displayName := RegExReplace(
                nameWithoutExtension,
                "i)^Explorer - \d+ - "
            )
            if (displayName = "")
                displayName := this.PathDisplayName(target)

            sequence := 1000000000 + discoveryOrder
            if RegExMatch(
                A_LoopFileName,
                "i)^Explorer - (\d+) - ",
                &sequenceMatch
            )
                sequence := sequenceMatch[1] + 0

            targetExists := DirExist(target) != 0
            if !targetExists
                displayName .= " [currently unavailable]"

            links.Push({
                LinkPath: A_LoopFileFullPath,
                Target: target,
                DisplayName: displayName,
                Description: description,
                Sequence: sequence,
                TargetExists: targetExists
            })
        }
        this.SortExplorerShortcutLinks(links)
        return links
    }

    SortExplorerShortcutLinks(links) {
        if (links.Length > 1)
            this.QuickSortExplorerShortcutLinks(links, 1, links.Length)
    }

    QuickSortExplorerShortcutLinks(links, left, right) {
        low := left
        high := right
        pivot := links[Floor((left + right) / 2)]

        while (low <= high) {
            while (this.CompareExplorerShortcutLinks(links[low], pivot) < 0)
                low += 1
            while (this.CompareExplorerShortcutLinks(links[high], pivot) > 0)
                high -= 1

            if (low <= high) {
                temporary := links[low]
                links[low] := links[high]
                links[high] := temporary
                low += 1
                high -= 1
            }
        }

        if (left < high)
            this.QuickSortExplorerShortcutLinks(links, left, high)
        if (low < right)
            this.QuickSortExplorerShortcutLinks(links, low, right)
    }

    CompareExplorerShortcutLinks(first, second) {
        if (first.Sequence < second.Sequence)
            return -1
        if (first.Sequence > second.Sequence)
            return 1
        return StrCompare(StrLower(first.LinkPath), StrLower(second.LinkPath))
    }

    BuildExplorerFolderActionMenu(link) {
        actionMenu := Menu()
        if !link.TargetExists {
            unavailableLabel := "(Folder is currently unavailable)"
            actionMenu.Add(unavailableLabel, (*) => 0)
            actionMenu.Disable(unavailableLabel)
            actionMenu.Add()
            actionMenu.Add(
                "Copy saved folder path",
                ObjBindMethod(this, "CopyText", link.Target)
            )
            actionMenu.Add(
                "Show persistent shortcut file",
                ObjBindMethod(this, "OpenContainingFolder", link.LinkPath)
            )
            return actionMenu
        }

        actionMenu.Add(
            "Open in Explorer",
            ObjBindMethod(this, "OpenInExplorer", link.Target)
        )
        actionMenu.Add(
            "Open with Code",
            ObjBindMethod(this, "OpenVSCodeAt", link.Target)
        )
        actionMenu.Add(
            "Open with Everything 1.5",
            ObjBindMethod(this, "OpenEverythingAt", link.Target)
        )
        actionMenu.Add(
            "Open Windows Terminal here",
            ObjBindMethod(this, "OpenTerminalAt", link.Target)
        )
        actionMenu.Add(
            "Open PowerShell here",
            ObjBindMethod(this, "OpenPowerShellAt", link.Target)
        )
        actionMenu.Add(
            "Open Command Prompt here",
            ObjBindMethod(this, "OpenCmdAt", link.Target)
        )
        actionMenu.Add()

        runnable := this.GetRunnableProjectInfo(link.Target)
        if (runnable.Candidates.Length > 0) {
            actionMenu.Add(
                "Run project (best detected entry point)",
                ObjBindMethod(this, "RunDetectedProject", link.Target)
            )

            candidateMenu := Menu()
            for candidate in runnable.Candidates {
                candidateMenu.Add(
                    this.MenuSafe(this.Truncate(candidate.Label, 92)),
                    ObjBindMethod(this, "RunProjectCandidate", candidate)
                )
            }
            this.ExplorerShortcutSubmenus.Push(candidateMenu)
            actionMenu.Add("Run a detected entry point", candidateMenu)
        } else {
            noRunLabel := "(No runnable entry point detected)"
            actionMenu.Add(noRunLabel, (*) => 0)
            actionMenu.Disable(noRunLabel)
        }

        actionMenu.Add()
        actionMenu.Add(
            "Copy folder path",
            ObjBindMethod(this, "CopyText", link.Target)
        )
        actionMenu.Add(
            "Show shortcut file",
            ObjBindMethod(this, "OpenContainingFolder", link.LinkPath)
        )
        return actionMenu
    }

    GetRunnableProjectInfo(path) {
        folder := DirExist(path) ? this.NormalizePath(path) : this.ParentDirectory(path)
        if (folder = "")
            return {Folder: "", Candidates: []}

        projectRoot := this.FindProjectRoot(folder)
        if (projectRoot != "") {
            rootCandidates := this.FindRunnableCandidates(projectRoot)
            if (rootCandidates.Length > 0)
                return {Folder: projectRoot, Candidates: rootCandidates}
        }

        return {Folder: folder, Candidates: this.FindRunnableCandidates(folder)}
    }

    FindRunnableCandidates(folder) {
        candidates := []
        seen := Map()
        folder := this.NormalizePath(folder)
        if (folder = "" || !DirExist(folder))
            return candidates

        ; Explicit launcher names are ordered from most intentional to most
        ; general. Common source subfolders are included without performing an
        ; unbounded recursive scan through dependency or virtual-env trees.
        explicit := [
            ["run.bat", "Batch", "Batch: run.bat"],
            ["start.bat", "Batch", "Batch: start.bat"],
            ["launch.bat", "Batch", "Batch: launch.bat"],
            ["run.cmd", "Batch", "Command: run.cmd"],
            ["start.cmd", "Batch", "Command: start.cmd"],
            ["run.ps1", "PowerShell", "PowerShell: run.ps1"],
            ["start.ps1", "PowerShell", "PowerShell: start.ps1"],
            ["main.py", "Python", "Python: main.py"],
            ["app.py", "Python", "Python: app.py"],
            ["run.py", "Python", "Python: run.py"],
            ["launcher.py", "Python", "Python: launcher.py"],
            ["gui.py", "Python", "Python: gui.py"],
            ["__main__.py", "Python", "Python: __main__.py"],
            ["main.ahk", "AutoHotkey", "AutoHotkey: main.ahk"],
            ["run.ahk", "AutoHotkey", "AutoHotkey: run.ahk"],
            ["start.ahk", "AutoHotkey", "AutoHotkey: start.ahk"],
            ["main.exe", "Executable", "Program: main.exe"],
            ["app.exe", "Executable", "Program: app.exe"]
        ]
        roots := ["", "src", "app", "scripts", "tools"]

        for rootName in roots {
            base := rootName = "" ? folder : folder "\" rootName
            if !DirExist(base)
                continue
            for specification in explicit {
                candidatePath := base "\" specification[1]
                candidateLabel := specification[3]
                if (rootName != "")
                    candidateLabel .= " (" rootName "\" specification[1] ")"
                this.AddRunnableCandidate(
                    candidates,
                    seen,
                    candidatePath,
                    specification[2],
                    candidateLabel
                )
                if (candidates.Length >= this.MaxRunnableCandidates)
                    return candidates
            }
        }

        packagePath := folder "\package.json"
        nodeScript := this.DetectPreferredNodeScript(packagePath)
        if (nodeScript != "") {
            this.AddRunnableCandidate(
                candidates,
                seen,
                packagePath,
                "Node",
                "Node: npm run " nodeScript,
                nodeScript
            )
        }

        ; Root-level .NET projects are run with an explicit --project target.
        try {
            Loop Files folder "\*.csproj", "F" {
                this.AddRunnableCandidate(
                    candidates,
                    seen,
                    A_LoopFileFullPath,
                    "DotNet",
                    ".NET: dotnet run --project " A_LoopFileName
                )
                if (candidates.Length >= this.MaxRunnableCandidates)
                    return candidates
            }
        }

        ; Include additional root launchers after the preferred exact names.
        for pattern in ["*.bat", "*.cmd", "*.ps1", "*.py", "*.pyw", "*.ahk"] {
            try {
                Loop Files folder "\" pattern, "F" {
                    SplitPath(A_LoopFileName, , , &extension)
                    kind := this.RunnableKindFromExtension(extension)
                    if (kind != "")
                        this.AddRunnableCandidate(
                            candidates,
                            seen,
                            A_LoopFileFullPath,
                            kind,
                            kind ": " A_LoopFileName
                        )
                    if (candidates.Length >= this.MaxRunnableCandidates)
                        return candidates
                }
            }
        }

        return candidates
    }

    AddRunnableCandidate(candidates, seen, path, kind, label, argument := "") {
        attributes := FileExist(path)
        if (attributes = "" || InStr(attributes, "D"))
            return false

        key := StrLower(this.NormalizePath(path)) "|" StrLower(kind) "|" StrLower(argument)
        if seen.Has(key)
            return false

        seen[key] := true
        candidates.Push({
            Path: this.NormalizePath(path),
            Kind: kind,
            Label: label,
            Argument: argument
        })
        return true
    }

    DetectPreferredNodeScript(packagePath) {
        if !FileExist(packagePath)
            return ""

        try content := FileRead(packagePath, "UTF-8")
        catch
            return ""

        quote := Chr(34)
        scriptsPattern := "s)" quote "scripts" quote "\s*:\s*\{(.*?)\}"
        if !RegExMatch(content, scriptsPattern, &match)
            return ""

        scriptsBlock := match[1]
        for scriptName in ["dev", "start", "serve", "watch"] {
            if RegExMatch(
                scriptsBlock,
                quote scriptName quote "\s*:"
            )
                return scriptName
        }
        return ""
    }

    RunnableKindFromExtension(extension) {
        switch StrLower(extension) {
            case "bat", "cmd":
                return "Batch"
            case "ps1":
                return "PowerShell"
            case "py", "pyw":
                return "Python"
            case "ahk":
                return "AutoHotkey"
        }
        return ""
    }

    RunDetectedProject(path, *) {
        runnable := this.GetRunnableProjectInfo(path)
        if (runnable.Candidates.Length = 0) {
            MsgBox(
                "No supported project entry point was found in:`n`n" runnable.Folder,
                "Run Project",
                "Icon!"
            )
            return
        }
        this.RunProjectCandidate(runnable.Candidates[1])
    }

    RunProjectCandidate(candidate, *) {
        path := candidate.Path
        if !FileExist(path) {
            MsgBox("The entry point no longer exists:`n`n" path, "Run Project", "Icon!")
            return
        }

        folder := this.ParentDirectory(path)
        try {
            switch candidate.Kind {
                case "Batch":
                    Run(A_ComSpec " /K " this.Quote(path), folder)
                case "PowerShell":
                    Run(
                        "powershell.exe -NoExit -ExecutionPolicy Bypass -File " this.Quote(path),
                        folder
                    )
                case "Python":
                    Run(A_ComSpec " /K python " this.Quote(path), folder)
                case "AutoHotkey":
                    Run(this.Quote(path), folder)
                case "Executable":
                    Run(this.Quote(path), folder)
                case "Node":
                    Run(A_ComSpec " /K npm run " candidate.Argument, folder)
                case "DotNet":
                    Run(A_ComSpec " /K dotnet run --project " this.Quote(path), folder)
                default:
                    throw Error("Unsupported runnable type: " candidate.Kind)
            }
        } catch as err {
            MsgBox(
                "Could not run:`n" path "`n`n" err.Message,
                "Run Project",
                "Icon!"
            )
        }
    }

    OpenExplorerShortcutFolder(*) {
        if !DirExist(this.ExplorerShortcutFolder)
            DirCreate(this.ExplorerShortcutFolder)
        this.OpenInExplorer(this.ExplorerShortcutFolder)
    }

    CleanShortcutFileName(name) {
        name := Trim(name "")
        for character in ["<", ">", ":", Chr(34), "/", "\", "|", "?", "*"]
            name := StrReplace(name, character, "_")
        name := Trim(name, " .")
        if (name = "")
            name := "Folder"
        return this.Truncate(name, 80)
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
                    Title: item.Title,
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

            ; Rebuild every caption using the current window width and tab
            ; count. Large sessions use shorter captions so all tabs require
            ; only a practical number of wrapped rows.
            labels := this.BuildResponsiveBrowserTabLabels(models)

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
            this.RequestResponsiveLayout()
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
            browserTabMenu.Add("Open with Everything 1.5", ObjBindMethod(this, "OpenEverythingAt", model.Path))
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
        if !this.GuiBuilt || this.ScriptHubMode
            return

        this.FileList.Opt("-Redraw")
        this.FileList.Delete()
        this.DetailEdit.Value := ""

        count := 0
        truncated := false
        invalidRegex := false
        this.UsedEverythingThisRefresh := false
        this.UsedLocalThisRefresh := false
        this.LastEverythingQuery := ""
        this.LastSearchBackend := "Idle"

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
            this.LastSearchBackend := "Local AHK (Regex)"
            this.UpdateEverythingGuiStatus(this.LastSearchBackend)
            this.SetStatus("The regular expression is invalid. Correct it or disable Regex.")
            return
        }

        locationText := this.ViewMode = "Combined"
            ? "Combined workspace"
            : this.CurrentPath
        suffix := truncated ? " | Display limit reached: " this.MaxDisplayedItems : ""

        if (this.UsedEverythingThisRefresh && this.UsedLocalThisRefresh)
            backendText := "Everything3 + local fallback"
        else if this.UsedEverythingThisRefresh
            backendText := "Everything3 SDK"
        else if this.UsedLocalThisRefresh
            backendText := this.RegexCheck.Value = 1
                ? "Local AHK (Regex)"
                : (this.SmartSyntaxCheck.Value = 1 ? "Local AHK (smart syntax degraded)" : "Local AHK")
        else
            backendText := "Idle"

        this.LastSearchBackend := backendText
        this.UpdateEverythingGuiStatus(backendText)

        this.SetStatus(
            locationText " | " count " item" (count = 1 ? "" : "s")
            suffix " | Search: " backendText
        )
    }

    AddFolderItemsToList(rootPath, sourceName, &count, &invalidRegex) {
        ; Everything3 uses its indexed database for normal text/wildcard searches.
        ; AutoHotkey's local Loop Files implementation remains the exact fallback
        ; and is always used for Regex mode so existing PCRE semantics do not change.
        if (
            this.RegexCheck.Value != 1
            && this.EverythingEnableCheck.Value = 1
            && this.Everything
            && this.Everything.EnsureConnected()
        ) {
            result := this.AddFolderItemsToListEverything(
                rootPath,
                sourceName,
                &count,
                &invalidRegex
            )
            if (result != "Fallback") {
                this.UsedEverythingThisRefresh := true
                return result
            }
        }

        this.UsedLocalThisRefresh := true
        return this.AddFolderItemsToListLocal(
            rootPath,
            sourceName,
            &count,
            &invalidRegex
        )
    }

    AddFolderItemsToListEverything(rootPath, sourceName, &count, &invalidRegex) {
        remaining := this.MaxDisplayedItems - count
        if (remaining <= 0)
            return "Limit"

        everythingQuery := this.BuildEverythingSearchQuery(rootPath)
        this.LastEverythingQuery := everythingQuery
        sdkResult := this.Everything.Search(everythingQuery, remaining)
        if sdkResult.HasOwnProp("Query")
            this.LastEverythingQuery := sdkResult.Query
        if !sdkResult.Ok
            return "Fallback"

        query := Trim(this.FilterEdit.Value)
        filterType := this.TypeCombo.Text
        showHidden := this.HiddenCheck.Value = 1

        for item in sdkResult.Results {
            if (count >= this.MaxDisplayedItems)
                return "Limit"

            fullPath := item.Path
            attributes := ""
            try attributes := FileExist(fullPath)
            catch
                attributes := ""

            ; Keep parity with the old Loop Files backend: do not show stale
            ; index entries whose target no longer exists on the filesystem.
            if (attributes = "")
                continue

            if !showHidden && (InStr(attributes, "H") || InStr(attributes, "S"))
                continue

            isDirectory := InStr(attributes, "D") != 0
            SplitPath(fullPath, &name)

            modified := ""
            try modified := FileGetTime(fullPath, "M")

            ; Apply the original filters a second time as a correctness guard.
            ; Everything does the expensive narrowing; these checks preserve the
            ; exact behavior expected by the rest of this GUI.
            if !this.MatchesTypeFilter(name, fullPath, isDirectory, modified, filterType)
                continue

            if (this.SmartSyntaxCheck.Value != 1) {
                matchResult := this.MatchesTextFilter(name, fullPath, query)
                if (matchResult = -1) {
                    invalidRegex := true
                    return "InvalidRegex"
                }
                if !matchResult
                    continue
            }

            typeText := isDirectory ? "Folder" : this.GetFileTypeText(name)
            sizeText := ""
            if !isDirectory {
                try sizeText := this.FormatBytes(FileGetSize(fullPath))
            }

            modifiedText := ""
            if (modified != "") {
                try modifiedText := FormatTime(modified, "yyyy-MM-dd HH:mm:ss")
            }

            iconIndex := this.GetShellIconIndex(fullPath)
            rowOptions := iconIndex >= 0 ? "Icon" (iconIndex + 1) : ""
            this.FileList.Add(rowOptions, name, typeText, sizeText, modifiedText, sourceName, "Everything3", fullPath)
            count += 1
        }

        ; Search() requests one result beyond the GUI capacity. If Everything
        ; supplied that extra row, there are more indexed matches than we display.
        if (sdkResult.ViewportCount > remaining)
            return "Limit"

        return "OK"
    }

    AddFolderItemsToListLocal(rootPath, sourceName, &count, &invalidRegex) {
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

                iconIndex := this.GetShellIconIndex(fullPath)
                rowOptions := iconIndex >= 0 ? "Icon" (iconIndex + 1) : ""
                this.FileList.Add(rowOptions, name, typeText, sizeText, modifiedText, sourceName, "Local AHK", fullPath)
                count += 1
            }
        } catch as err {
            this.SetStatus("Could not enumerate " rootPath ": " err.Message)
        }

        return "OK"
    }

    BuildEverythingSearchQuery(rootPath) {
        parts := []
        recursive := this.RecursiveCheck.Value = 1
        showHidden := this.HiddenCheck.Value = 1
        query := Trim(this.FilterEdit.Value)
        filterType := this.TypeCombo.Text

        scopeFunction := recursive ? "ancestor:" : "parent:"
        parts.Push(scopeFunction this.QuoteEverythingValue(rootPath))

        if !showHidden {
            parts.Push("!attrib:h")
            parts.Push("!attrib:s")
        }

        typeExpression := this.GetEverythingTypeExpression(filterType)
        if (typeExpression != "")
            parts.Push(typeExpression)

        if (query != "") {
            if (this.SmartSyntaxCheck.Value = 1) {
                ; Everything-style mode: preserve operators, OR groups, size/date
                ; functions, ext:, content:, wildcards, and quoted expressions.
                parts.Push(query)
            } else {
                ; Compatibility mode retains the original path-token behavior.
                tokens := StrSplit(query, A_Space)
                for token in tokens {
                    token := Trim(token)
                    if (token = "")
                        continue

                    escapedToken := this.EscapeEverythingSearchText(token)
                    if (InStr(token, "*") || InStr(token, "?"))
                        parts.Push("whole:wildcards:" this.QuoteEverythingValue(escapedToken, false))
                    else
                        parts.Push("path:" this.QuoteEverythingValue(escapedToken, false))
                }
            }
        }

        return this.JoinEverythingSearchParts(parts)
    }

    GetEverythingTypeExpression(filterType) {
        switch filterType {
            case "All items":
                return ""
            case "Folders only":
                return "folder:"
            case "Python":
                return "ext:py;pyw;pyi"
            case "AutoHotkey":
                return "ext:ahk"
            case "All code":
                return "ext:py;pyw;pyi;ahk;cs;csx;js;mjs;cjs;ts;tsx;jsx;html;htm;css;scss;less;json;xml;yaml;yml;toml;ini;c;cc;cpp;cxx;h;hpp;hxx;java;kt;kts;go;rs;rb;php;swift;sql;ps1;psm1;psd1;bat;cmd;sh;bash;zsh;lua;r;vue;svelte"
            case "Images":
                return "ext:png;jpg;jpeg;gif;bmp;webp;tif;tiff;svg;ico;heic;avif"
            case "Video":
                return "ext:mp4;mkv;avi;mov;wmv;webm;m4v;mpeg;mpg;ts;m2ts"
            case "Audio":
                return "ext:mp3;wav;flac;m4a;aac;ogg;wma;opus"
            case "Documents":
                return "ext:txt;md;rtf;pdf;doc;docx;odt;xls;xlsx;csv;ods;ppt;pptx;odp;epub"
            case "Archives":
                return "ext:zip;7z;rar;tar;gz;bz2;xz;cab;iso"
            case "Executables":
                return "ext:exe;msi;msix;appx;com;scr;lnk"
            case "Modified in 24 hours":
                return "file: dm:past24hours"
        }
        return ""
    }

    EscapeEverythingSearchText(text) {
        ; Search values are always quoted below, so Everything treats operators
        ; such as |, !, <, > and : as literal text. Only an embedded quote needs
        ; encoding before the value is wrapped in double quotes.
        return StrReplace(text, Chr(34), "&quot:")
    }

    QuoteEverythingValue(value, escape := true) {
        if escape
            value := StrReplace(value, Chr(34), "&quot:")
        return Chr(34) value Chr(34)
    }

    JoinEverythingSearchParts(parts) {
        text := ""
        for part in parts {
            if (part = "")
                continue
            text .= (text = "" ? "" : " ") part
        }
        return text
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

        path := ctrl.GetText(row, 7)
        if (path = "")
            return

        if DirExist(path)
            this.NavigateTo(path)
        else
            this.RunDefault(path)
    }

    UpdateSelectionDetails(*) {
        paths := this.GetSelectedFilePaths()
        if (paths.Length = 0) {
            this.DetailEdit.Value := ""
            return
        }
        if (paths.Length > 1) {
            totalSize := 0
            files := 0
            folders := 0
            for path in paths {
                if DirExist(path) {
                    folders += 1
                } else if FileExist(path) {
                    files += 1
                    try totalSize += FileGetSize(path)
                }
            }
            this.DetailEdit.Value := (
                paths.Length " items selected | Files: " files " | Folders: " folders
                " | File bytes: " this.FormatBytes(totalSize)
                "`r`nRight-click for colored batch actions."
            )
            return
        }

        path := paths[1]
        if DirExist(path) {
            this.DetailEdit.Value := "Folder:`r`n" path
            return
        }
        if FileExist(path) {
            sizeText := ""
            modifiedText := ""
            try sizeText := this.FormatBytes(FileGetSize(path))
            try modifiedText := FormatTime(FileGetTime(path, "M"), "yyyy-MM-dd HH:mm:ss")
            this.DetailEdit.Value := "File:`r`n" path "`r`nSize: " sizeText " | Modified: " modifiedText
            return
        }
        this.DetailEdit.Value := path
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

        ; Do not destroy an intentional multi-selection just because one member
        ; of the selection was right-clicked.
        selected := false
        selectedRow := 0
        while (selectedRow := ctrl.GetNext(selectedRow)) {
            if (selectedRow = row) {
                selected := true
                break
            }
        }
        if !selected {
            ctrl.Modify(0, "-Select")
            ctrl.Modify(row, "Select Focus")
        } else {
            ctrl.Modify(row, "Focus")
        }

        paths := this.GetSelectedFilePaths()
        if (paths.Length)
            this.ShowPathActionPalette(paths, "file", x, y)
    }


    ToggleScriptHubPane(*) {
        if this.ScriptHubMode {
            this.SourceCombo.Choose(1)
            this.OnSourceComboChanged()
        } else {
            this.ShowScriptHubPane()
        }
    }

    OnSourceComboChanged(*) {
        if (this.SourceCombo.Text = "AHK Script Hub") {
            this.ShowScriptHubPane(false)
            return
        }
        this.SetScriptHubMode(false)
        this.PopulateSourceList()
        this.RefreshFiles()
    }

    ShowScriptHubPane(showGui := true, *) {
        if !this.GuiBuilt {
            this.Show()
        } else if showGui && !this.IsMainGuiVisible() {
            if this.AutoMaximizeGui
                this.MainGui.Show("Maximize")
            else
                this.MainGui.Show("w1320 h780")
        }

        this.SourceCombo.Choose(5)
        this.SetScriptHubMode(true)
        this.ScriptHub.ScanRunningScripts()
        this.ScriptHub.RefreshList()
        this.RequestResponsiveLayout()
        try this.ScriptSearchEdit.Focus()
    }

    SetScriptHubMode(enabled) {
        enabled := !!enabled
        this.ScriptHubMode := enabled
        try {
            this.ScriptHubQuickButton.Text := enabled ? "Explorer" : "Scripts"
        }

        explorerControls := [
            this.SourceList, this.AddActiveButton, this.AddSelectedButton, this.CaptureButton,
            this.FilterLabel, this.FilterEdit, this.TypeCombo, this.RegexCheck,
            this.RecursiveCheck, this.HiddenCheck, this.FilterHelpButton, this.ClearFilterButton,
            this.SmartPresetCombo, this.SmartSyntaxCheck,
            this.EverythingEnableCheck, this.EverythingInfoText, this.EverythingStatusButton,
            this.EverythingReconnectButton, this.EverythingQueryLabel, this.EverythingQueryEdit,
            this.EverythingCopyQueryButton, this.FileList, this.DetailEdit
        ]
        scriptControls := [
            this.ScriptSearchLabel, this.ScriptSearchEdit, this.ScriptPresetCombo,
            this.ScriptFilterCombo, this.ScriptRunButton, this.ScriptRestartButton,
            this.ScriptStopButton, this.ScriptVSCodeButton, this.ScriptFolderButton,
            this.ScriptEverythingButton, this.ScriptAddButton, this.ScriptImportButton,
            this.ScriptMetaButton, this.ScriptFavoriteButton, this.ScriptAlwaysButton,
            this.ScriptCopyButton, this.ScriptRemoveButton, this.ScriptList,
            this.ScriptDetailEdit
        ]

        for ctrl in explorerControls {
            try {
                if enabled
                    ctrl.Hide()
                else
                    ctrl.Show()
            }
        }
        for ctrl in scriptControls {
            try {
                if enabled
                    ctrl.Show()
                else
                    ctrl.Hide()
            }
        }

        if enabled
            this.ScriptHub.UpdateStatus()
        else
            this.UpdateEverythingGuiStatus(this.LastSearchBackend)

        this.RequestResponsiveLayout()
    }

    ApplySmartSearchPreset(*) {
        label := this.SmartPresetCombo.Text
        if !this.SmartSearchPresets.Has(label)
            return
        query := this.SmartSearchPresets[label]
        this.FilterEdit.Value := query
        this.SmartSyntaxCheck.Value := 1
        this.RegexCheck.Value := 0
        this.QueueRefresh()
    }

    AttachShellImageList(listView) {
        ; SHGFI_SYSICONINDEX returns the process-wide Windows system image list.
        ; LVM_SETIMAGELIST attaches it directly, so every row can use the exact
        ; file/folder icon Explorer would display without extracting icon files.
        probe := A_WinDir "\System32\shell32.dll"
        info := Buffer(A_PtrSize + 8 + 520 + 160, 0)
        himl := DllCall(
            "Shell32\SHGetFileInfoW",
            "Str", probe,
            "UInt", 0,
            "Ptr", info.Ptr,
            "UInt", info.Size,
            "UInt", 0x4000 | 0x1, ; SHGFI_SYSICONINDEX | SHGFI_SMALLICON
            "Ptr"
        )
        if !himl
            return false
        DllCall(
            "SendMessageW",
            "Ptr", listView.Hwnd,
            "UInt", 0x1003, ; LVM_SETIMAGELIST
            "Ptr", 1,      ; LVSIL_SMALL
            "Ptr", himl,
            "Ptr"
        )
        this.SystemImageList := himl
        return true
    }

    GetShellIconIndex(path) {
        info := Buffer(A_PtrSize + 8 + 520 + 160, 0)
        flags := 0x4000 | 0x1 ; SHGFI_SYSICONINDEX | SHGFI_SMALLICON
        result := DllCall(
            "Shell32\SHGetFileInfoW",
            "Str", path,
            "UInt", 0,
            "Ptr", info.Ptr,
            "UInt", info.Size,
            "UInt", flags,
            "Ptr"
        )
        if !result
            return -1
        return NumGet(info, A_PtrSize, "Int")
    }

    GetSelectedFilePaths() {
        paths := []
        row := 0
        while (row := this.FileList.GetNext(row)) {
            path := this.FileList.GetText(row, 7)
            if (path != "")
                paths.Push(path)
        }
        return paths
    }

    ShowPathActionPalette(paths, kind := "file", x := 0, y := 0) {
        if !IsObject(paths) || paths.Length = 0
            return

        try {
            if IsObject(this.ActionPalette)
                this.ActionPalette.Destroy()
        }

        palette := Gui("-Caption +AlwaysOnTop +ToolWindow +Border", "Workspace Actions")
        palette.SetFont("s9", "Segoe UI")
        palette.BackColor := "F7F7F7"
        rowY := 0
        width := 320
        countText := paths.Length = 1 ? this.PathDisplayName(paths[1]) : paths.Length " selected items"
        header := palette.AddText("x10 y6 w300 h26 +0x200", countText)
        rowY := 34

        if (kind = "script") {
            this.AddPaletteRow(palette, &rowY, width, "▶ Run selected script(s)", "D8F5D0", ObjBindMethod(this.ScriptHub, "RunSelected"))
            this.AddPaletteRow(palette, &rowY, width, "↻ Restart selected script(s)", "E6F4D7", ObjBindMethod(this.ScriptHub, "RestartSelected"))
            this.AddPaletteRow(palette, &rowY, width, "■ Stop selected script(s)", "FFD0D0", ObjBindMethod(this.ScriptHub, "StopSelected"))
            this.AddPaletteRow(palette, &rowY, width, "Run as Administrator", "F4F4F4", ObjBindMethod(this.ScriptHub, "RunAdminSelected"))
        } else {
            this.AddPaletteRow(palette, &rowY, width, "Open selected", "D8F5D0", ObjBindMethod(this, "RunPathsDefault", paths))
        }

        ; Requested visual action categories.
        this.AddPaletteRow(palette, &rowY, width, "Explorer / Open containing folder", "FFF2A8", ObjBindMethod(this, "OpenContainingFoldersBatch", paths))
        this.AddPaletteRow(palette, &rowY, width, "Everything 1.5 / Open path", "FFD29A", ObjBindMethod(this, "OpenEverythingPaths", paths))
        this.AddPaletteRow(palette, &rowY, width, "VS Code / Open selected", "BFD8FF", ObjBindMethod(this, "OpenVSCodePaths", paths))
        this.AddPaletteRow(palette, &rowY, width, "Terminal at containing folder", "E8E8E8", ObjBindMethod(this, "OpenTerminalPaths", paths))
        this.AddPaletteRow(palette, &rowY, width, "Windows Shell Actions  ▸", "EDEDED", ObjBindMethod(this, "ShowShellVerbsForPath", paths[1]))
        this.AddPaletteRow(palette, &rowY, width, "Full native Explorer context menu", "E2E2E2", ObjBindMethod(this, "ShowNativeExplorerContextMenu", paths[1]))
        this.AddPaletteRow(palette, &rowY, width, "Copy full path(s)", "F4F4F4", ObjBindMethod(this, "CopyPaths", paths))

        if (kind = "file") {
            this.AddPaletteRow(palette, &rowY, width, "Add folder(s) to workspace", "EEE6FF", ObjBindMethod(this, "AddPathsToWorkspace", paths))
            this.AddPaletteRow(palette, &rowY, width, "Move selected to Recycle Bin", "FFD7D7", ObjBindMethod(this, "RecyclePaths", paths))
        } else {
            this.AddPaletteRow(palette, &rowY, width, "★ Toggle favorite", "FFF6C9", ObjBindMethod(this.ScriptHub, "ToggleFavoriteSelected"))
            this.AddPaletteRow(palette, &rowY, width, "Toggle Always Start", "E8E8FF", ObjBindMethod(this.ScriptHub, "ToggleAlwaysSelected"))
            this.AddPaletteRow(palette, &rowY, width, "Tags / Notes", "F2F2F2", ObjBindMethod(this.ScriptHub, "EditMetadataSelected"))
            this.AddPaletteRow(palette, &rowY, width, "Relocate stored path", "EFEFEF", ObjBindMethod(this.ScriptHub, "RelocateSelected"))
            this.AddPaletteRow(palette, &rowY, width, "Remove from history", "FFD7D7", ObjBindMethod(this.ScriptHub, "RemoveSelected"))
        }

        closeText := palette.AddText("x0 y" rowY " w" width " h28 Center +0x200", "Close")
        closeText.OnEvent("Click", (*) => palette.Destroy())
        rowY += 30
        palette.OnEvent("Escape", (*) => palette.Destroy())
        this.ActionPalette := palette

        if !x || !y
            MouseGetPos(&x, &y)
        try palette.Show("x" x " y" y " w" width " h" rowY)
        catch {
            palette.Show("AutoSize")
        }
    }

    AddPaletteRow(guiObj, &rowY, width, label, color, callback) {
        background := guiObj.AddProgress(
            "x0 y" rowY " w" width " h30 c" color " Background" color,
            100
        )
        textCtrl := guiObj.AddText(
            "x12 y" (rowY + 2) " w" (width - 24) " h26 +0x200 BackgroundTrans",
            label
        )
        textCtrl.OnEvent("Click", (*) => this.InvokePaletteAction(guiObj, callback))
        rowY += 31
    }

    InvokePaletteAction(guiObj, callback, *) {
        ; Destroy first so actions that launch a real popup (Shell verbs) are not
        ; obscured by the colored palette.
        try guiObj.Destroy()
        try callback.Call()
        catch as err
            MsgBox("Action failed.`n`n" err.Message, "Developer Workspace Hub", "Icon!")
    }

    RunPathsDefault(paths, *) {
        for path in paths {
            try Run(this.Quote(path))
            catch
                continue
        }
    }

    OpenContainingFoldersBatch(paths, *) {
        seen := Map()
        for path in paths {
            if FileExist(path) && !DirExist(path) {
                ; For one file, preserve Explorer's useful /select behavior.
                if (paths.Length = 1) {
                    try Run("explorer.exe /select," this.Quote(path))
                    return
                }
            }
            folder := DirExist(path) ? path : this.ParentDirectory(path)
            key := StrLower(folder)
            if (folder = "" || seen.Has(key))
                continue
            seen[key] := true
            try Run("explorer.exe " this.Quote(folder))
        }
    }

    OpenEverythingPaths(paths, *) {
        seen := Map()
        for path in paths {
            folder := DirExist(path) ? this.NormalizePath(path) : this.ParentDirectory(path)
            if (folder = "")
                continue
            key := StrLower(folder)
            if seen.Has(key)
                continue
            seen[key] := true
            this.OpenEverythingAt(path)
        }
    }

    OpenVSCodePaths(paths, *) {
        if (paths.Length = 0)
            return
        command := "code"
        for path in paths
            command .= " " this.Quote(path)
        try {
            Run(command)
            return
        }
        ; Reuse the robust single-target locator if 'code' is not on PATH.
        this.OpenVSCodeAt(paths[1])
    }

    OpenTerminalPaths(paths, *) {
        if (paths.Length = 0)
            return
        folder := DirExist(paths[1]) ? paths[1] : this.ParentDirectory(paths[1])
        this.OpenTerminalAt(folder)
    }

    CopyPaths(paths, *) {
        out := ""
        for path in paths
            out .= (out = "" ? "" : "`r`n") path
        this.CopyText(out)
        this.Notify(paths.Length " path" (paths.Length = 1 ? "" : "s") " copied.")
    }

    AddPathsToWorkspace(paths, *) {
        seen := Map()
        for path in paths {
            folder := DirExist(path) ? path : this.ParentDirectory(path)
            key := StrLower(folder)
            if (folder = "" || seen.Has(key))
                continue
            seen[key] := true
            this.AddPathToWorkspace(folder)
        }
    }

    RecyclePaths(paths, *) {
        if (paths.Length = 0)
            return
        answer := MsgBox(
            "Move " paths.Length " selected item" (paths.Length = 1 ? "" : "s") " to the Recycle Bin?",
            "Recycle Selected Items",
            "YesNo Icon?"
        )
        if (answer != "Yes")
            return
        for path in paths {
            try FileRecycle(path)
            catch
                continue
        }
        this.RefreshFiles()
    }

    ShowNativeExplorerContextMenu(path, *) {
        ; This intentionally delegates the final menu rendering to Explorer so
        ; Windows 11 shell extensions, Open With, Send To, properties handlers,
        ; and other modern native entries appear exactly as Windows provides them.
        path := this.NormalizePath(path)
        if (path = "")
            return
        try {
            Run("explorer.exe /select," this.Quote(path))
            if WinWaitActive("ahk_class CabinetWClass", , 4) {
                Sleep(350)
                Send("+{F10}")
            }
        } catch as err {
            MsgBox("Could not open the native Explorer context menu.`n`n" err.Message, "Windows Context Menu", "Icon!")
        }
    }

    ShowShellVerbsForPath(path, *) {
        ; Shell.Application exposes the same registered file/folder verbs used by
        ; Explorer. This submenu therefore comes from Windows' shell handlers
        ; rather than a hard-coded list in this script.
        shell := ComObject("Shell.Application")
        path := this.NormalizePath(path)
        if (path = "")
            return

        folderPath := DirExist(path) ? this.ParentDirectory(path) : this.ParentDirectory(path)
        SplitPath(path, &name)
        if (folderPath = "" || name = "") {
            MsgBox("Windows shell verbs are unavailable for this root item.", "Shell Actions", "Iconi")
            return
        }

        folder := shell.Namespace(folderPath)
        if !IsObject(folder) {
            MsgBox("Windows could not open the Shell namespace for:`n" folderPath, "Shell Actions", "Icon!")
            return
        }
        item := folder.ParseName(name)
        if !IsObject(item) {
            MsgBox("Windows could not resolve the Shell item:`n" path, "Shell Actions", "Icon!")
            return
        }

        ; Avoid "menu := Menu()" for the same case-insensitive self-shadowing
        ; reason as Buffer above.
        shellMenu := Menu()
        this.ShellVerbObjects := []
        labels := Map()
        index := 0
        try verbs := item.Verbs
        catch
            verbs := 0
        if IsObject(verbs) {
            for verb in verbs {
                label := Trim(StrReplace(verb.Name "", "&", ""))
                if (label = "")
                    continue
                baseLabel := label
                suffix := 2
                while labels.Has(StrLower(label)) {
                    label := baseLabel " (" suffix ")"
                    suffix += 1
                }
                labels[StrLower(label)] := true
                index += 1
                this.ShellVerbObjects.Push(verb)
                shellMenu.Add(this.MenuSafe(label), ObjBindMethod(this, "InvokeShellVerb", index))
            }
        }
        if (index = 0) {
            shellMenu.Add("(No Shell verbs returned)", (*) => 0)
            shellMenu.Disable("(No Shell verbs returned)")
        }
        shellMenu.Show()
    }

    InvokeShellVerb(index, *) {
        if (index < 1 || index > this.ShellVerbObjects.Length)
            return
        verb := this.ShellVerbObjects[index]
        try verb.DoIt()
        catch as err
            MsgBox("Windows shell action failed.`n`n" err.Message, "Shell Actions", "Icon!")
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
        sourceContextMenu.Add("Open with Everything 1.5", ObjBindMethod(this, "OpenEverythingAt", path))
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
        try {
            Run("code " this.Quote(target))
            return
        }

        ; Fall back to the standard per-user and machine-wide installations
        ; when the VS Code shell command was not added to PATH.
        candidates := [
            A_LocalAppData "\Programs\Microsoft VS Code\Code.exe",
            A_LocalAppData "\Programs\Microsoft VS Code Insiders\Code - Insiders.exe",
            A_ProgramFiles "\Microsoft VS Code\Code.exe"
        ]
        programFilesX86 := EnvGet("ProgramFiles(x86)")
        if (programFilesX86 != "")
            candidates.Push(programFilesX86 "\Microsoft VS Code\Code.exe")

        for executable in candidates {
            if !FileExist(executable)
                continue
            try {
                Run(this.Quote(executable) " " this.Quote(target))
                return
            }
        }

        MsgBox(
            "VS Code was not found. Install it or add the 'code' command to PATH.",
            "VS Code",
            "Icon!"
        )
    }

    UpdateEverythingGuiStatus(backendText := "") {
        if !this.GuiBuilt
            return

        if (backendText = "")
            backendText := this.LastSearchBackend != "" ? this.LastSearchBackend : "Idle"

        loaded := this.Everything && this.Everything.Module
        connected := this.Everything && this.Everything.Client
        dllVersion := this.Everything && this.Everything.DllVersion != ""
            ? this.Everything.DllVersion
            : "?"
        everythingVersion := this.Everything && this.Everything.VersionText != ""
            ? this.Everything.VersionText
            : "?"

        if !this.EverythingEnableCheck.Value
            modeText := "DISABLED - using Local AHK"
        else if (this.RegexCheck.Value = 1)
            modeText := "BYPASSED - Regex uses Local AHK"
        else if (backendText = "Everything3 SDK")
            modeText := "ACTIVE - Everything3 SDK"
        else if InStr(backendText, "Everything3")
            modeText := "ACTIVE + FALLBACK"
        else if connected
            modeText := "READY - next normal search uses SDK"
        else
            modeText := "OFFLINE - Local AHK fallback"

        connectionText := connected ? "Connected" : loaded ? "DLL loaded, not connected" : "DLL not loaded"
        this.EverythingInfoText.Text := (
            connectionText
            " | DLL " dllVersion
            " | Everything " everythingVersion
            " | " modeText
        )

        queryText := this.LastEverythingQuery != ""
            ? this.LastEverythingQuery
            : "(no Everything3 SDK query has run for this view yet)"
        this.EverythingQueryEdit.Value := queryText
    }

    CopyEverythingQuery(*) {
        query := this.LastEverythingQuery
        if (query = "") {
            this.Notify("No Everything3 SDK query has run yet.")
            return
        }

        A_Clipboard := query
        if ClipWait(0.75)
            this.Notify("Everything3 SDK query copied.")
        else
            this.Notify("Could not copy the Everything3 query.")
    }

    ShowEverythingStatus(*) {
        connected := this.Everything && this.Everything.Client ? "Yes" : "No"
        loaded := this.Everything && this.Everything.Module ? "Yes" : "No"
        instance := this.Everything && this.Everything.InstanceName != ""
            ? this.Everything.InstanceName
            : "None"
        version := this.Everything && this.Everything.VersionText != ""
            ? this.Everything.VersionText
            : "Unknown/not connected"
        dllVersion := this.Everything && this.Everything.DllVersion != ""
            ? this.Everything.DllVersion
            : "Unknown/pre-3.0.0.4"
        viewportDiagnostic := this.Everything && this.Everything.LastViewportDiagnostic != ""
            ? this.Everything.LastViewportDiagnostic
            : "Not tested yet."
        lastError := this.Everything && this.Everything.LastError != ""
            ? this.Everything.LastError
            : "None"
        lastQuery := this.LastEverythingQuery != ""
            ? this.LastEverythingQuery
            : "No SDK query has run yet."

        MsgBox(
            "DLL:`n" this.EverythingDllPath "`n`n"
            "DLL loaded: " loaded "`n"
            "SDK DLL version: " dllVersion "`n"
            "Connected: " connected "`n"
            "Instance: " instance "`n"
            "Everything version: " version "`n`n"
            "Viewport compatibility:`n" viewportDiagnostic "`n`n"
            "Last SDK query:`n" lastQuery "`n`n"
            "Last error:`n" lastError,
            "Everything3 SDK Status"
        )
    }

    ReconnectEverything(*) {
        if !this.Everything {
            this.Notify("Everything3 SDK wrapper is not initialized.")
            return
        }

        if this.Everything.Reconnect() {
            this.Notify(
                "Everything3 connected to " this.Everything.InstanceName
                (this.Everything.VersionText != "" ? " | v" this.Everything.VersionText : "")
            )
            this.UpdateEverythingGuiStatus("Ready")
            this.RefreshFiles()
        } else {
            MsgBox(
                "Everything3 could not connect.`n`n" this.Everything.LastError,
                "Everything3 SDK",
                "Icon!"
            )
        }
    }

    ShutdownEverything(exitReason := "", exitCode := 0, *) {
        if this.Everything {
            try this.Everything.Close()
        }
    }

    OpenEverythingAt(path, *) {
        folder := DirExist(path) ? this.NormalizePath(path) : this.ParentDirectory(path)
        if (folder = "" || !DirExist(folder)) {
            MsgBox(
                "The folder could not be resolved for Everything:`n`n" path,
                "Everything 1.5",
                "Icon!"
            )
            return
        }

        ; Use the user's Everything 1.5 relaunch command and open a separate
        ; window whose search is scoped to the selected Explorer folder.
        everythingExe := "C:\Program Files\Everything\Everything.exe"
        if !FileExist(everythingExe) {
            MsgBox(
                "Everything 1.5 was not found at:`n`n" everythingExe,
                "Everything 1.5",
                "Icon!"
            )
            return
        }

        command := this.Quote(everythingExe)
            . " -is-relaunch-command -newwindow -path " this.Quote(folder)

        ; When the selected item is a file, also seed Everything's search box
        ; with the exact filename so the requested path is immediately visible
        ; rather than merely opening its parent directory.
        if !DirExist(path) {
            SplitPath(path, &selectedName)
            if (selectedName != "")
                command .= " -search " this.Quote("exact:" selectedName)
        }

        try Run(command, folder)
        catch as err {
            MsgBox(
                "Could not open the folder in Everything 1.5.`n`n" err.Message,
                "Everything 1.5",
                "Icon!"
            )
        }
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
        if (source = "AHK Script Hub") {
            this.SetScriptHubMode(true)
            this.ScriptHub.RefreshList()
            return
        }
        this.SetScriptHubMode(false)
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
        workspaceActionsMenu.Add("Show Numpad1 shortcut launcher", ObjBindMethod(this, "ShowExplorerShortcutMenu"))
        workspaceActionsMenu.Add("Open Desktop shortcut collection", ObjBindMethod(this, "OpenExplorerShortcutFolder"))
        workspaceActionsMenu.Add()
        workspaceActionsMenu.Add("Maximize responsive GUI", ObjBindMethod(this, "MaximizeGui"))
        workspaceActionsMenu.Add("Toggle borderless fullscreen", ObjBindMethod(this, "ToggleFullscreen"))
        workspaceActionsMenu.Add()
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
        workspaceActionsMenu.Add("Everything3 SDK status", ObjBindMethod(this, "ShowEverythingStatus"))
        workspaceActionsMenu.Add("Reconnect Everything3 SDK", ObjBindMethod(this, "ReconnectEverything"))
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
            "Numpad1`n"
            "Append only previously unseen open Explorer folders to the permanent Desktop shortcut collection, then show the nested action menu. Existing shortcuts are never removed automatically.`n`n"
            "E#.# tabs are live Explorer entries. S1-S10 are persistent virtual slots."
            " Right-click a tab for focus, close, pin, copy, and developer actions.`n`n"
            "The GUI opens maximized. Its tab strip grows to every wrapped row,"
            " toolbars wrap responsively, and More contains a borderless fullscreen toggle.",
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
        return SubStr(text, 1, maxLength - 1) "â€¦"
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

global EmbeddedScriptHubInstance := 0

EmbeddedHubWmi_OnObjectReady(eventObj, asyncContext := 0, *) {
    global EmbeddedScriptHubInstance
    if IsObject(EmbeddedScriptHubInstance)
        try EmbeddedScriptHubInstance.OnWmiProcessStart(eventObj)
}

EmbeddedHubWmi_OnCompleted(hResult, errorObj := 0, asyncContext := 0, *) {
    global EmbeddedScriptHubInstance
    if IsObject(EmbeddedScriptHubInstance)
        EmbeddedScriptHubInstance.ProcessTraceActive := false
}

OpenExplorerWorkspaceManager(*) {
    global ExplorerWorkspaceApp
    ExplorerWorkspaceApp.Show()
}

; Add the Explorer workspace system to the existing console command application.
global ExplorerWorkspaceApp := ExplorerWorkspaceManager(ConsoleMenuApp)

; Explicit global summon binding. The ExplorerWorkspaceManager constructor also
; registers Ctrl+Alt+E, but binding it here after construction guarantees the
; global hotkey resolves through the fully initialized application object.
Hotkey("^!e", OpenExplorerWorkspaceManager)

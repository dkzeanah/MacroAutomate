#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ============================================================
; Chrome Save-As Directory Automation
;
; Operation:
;   1. Copy an existing directory path to the clipboard.
;   2. When Chrome's "Save As" window appears:
;        - Press Alt+D
;        - Paste the directory
;        - Press Enter
;        - Click Save
;
; Hotkeys:
;   F8       = Run manually on the active Save As window
;   Ctrl+F8  = Toggle automatic detection on/off
; ============================================================

; Restrict automation to Chrome.
; Set this to an empty string "" to support Save As dialogs
; from every application.
TARGET_EXE := "chrome.exe"

; How frequently the script checks for a newly opened dialog.
WATCH_INTERVAL_MS := 100

; Time allowed for Windows Explorer to navigate to the folder.
NAVIGATION_DELAY_MS := 800

; Prevent the same Save As dialog from being processed repeatedly.
HandledDialogs := Map()

; Automatic watching is enabled when the script starts.
AutoDetectionEnabled := true

SetTimer(WatchForSaveAsDialog, WATCH_INTERVAL_MS)


; ============================================================
; MANUAL HOTKEY
; ============================================================

F8:: {
    hwnd := WinExist("A")

    if !IsTargetSaveAsDialog(hwnd) {
        ShowTemporaryMessage("The active window is not a supported Save As dialog.")
        return
    }

    AutomateSaveAsDialog(hwnd)
}


; ============================================================
; TOGGLE AUTOMATIC DETECTION
; ============================================================

^F8:: {
    global AutoDetectionEnabled

    AutoDetectionEnabled := !AutoDetectionEnabled

    stateText := AutoDetectionEnabled ? "enabled" : "disabled"
    ShowTemporaryMessage("Automatic Save As handling " stateText ".")
}


; ============================================================
; AUTOMATIC WINDOW WATCHER
; ============================================================

WatchForSaveAsDialog() {
    global AutoDetectionEnabled
    global HandledDialogs

    if !AutoDetectionEnabled
        return

    RemoveClosedDialogsFromHistory()

    hwnd := WinExist("A")

    if !IsTargetSaveAsDialog(hwnd)
        return

    ; Do not process the same window more than once.
    if HandledDialogs.Has(hwnd)
        return

    HandledDialogs[hwnd] := A_TickCount

    ; Run outside the timer callback so the watcher remains responsive.
    SetTimer(AutomateSaveAsDialog.Bind(hwnd), -50)
}


; ============================================================
; COMPLETE SAVE-AS AUTOMATION
; ============================================================

AutomateSaveAsDialog(hwnd) {
    global NAVIGATION_DELAY_MS

    windowSelector := "ahk_id " hwnd

    if !WinExist(windowSelector)
        return false

    clipboardDirectory := GetClipboardDirectory()

    if clipboardDirectory = "" {
        ShowTemporaryMessage(
            "Clipboard does not contain an existing directory path.`n"
            . "Copy the destination folder path and press F8."
        )
        return false
    }

    try {
        WinActivate(windowSelector)

        if !WinWaitActive(windowSelector, , 2) {
            ShowTemporaryMessage("The Save As dialog could not be activated.")
            return false
        }

        ; Focus the Windows file-dialog address bar.
        SendEvent("!d")
        Sleep(120)

        ; Replace any existing address-bar contents.
        SendEvent("^a")
        Sleep(60)

        ; Paste the directory from the clipboard.
        SendEvent("^v")
        Sleep(100)

        ; Navigate to the pasted directory.
        SendEvent("{Enter}")
        Sleep(NAVIGATION_DELAY_MS)

        if !WinExist(windowSelector)
            return true

        ; Click the actual Save button.
        if ClickSaveButton(hwnd)
            return true

        ; Last-resort fallback: activate the dialog's default button.
        WinActivate(windowSelector)
        SendEvent("{Enter}")

        return true
    }
    catch as error {
        ShowTemporaryMessage(
            "Save As automation failed:`n" error.Message
        )
        return false
    }
}


; ============================================================
; SAVE BUTTON DETECTION
; ============================================================

ClickSaveButton(hwnd) {
    windowSelector := "ahk_id " hwnd

    if !WinExist(windowSelector)
        return false

    ; First search every control for one whose text is "Save".
    try {
        controls := WinGetControls(windowSelector)

        for controlName in controls {
            controlText := ""

            try controlText := ControlGetText(
                controlName,
                windowSelector
            )

            normalizedText := StrLower(
                Trim(
                    StrReplace(controlText, "&")
                )
            )

            if normalizedText = "save" {
                ControlClick(
                    controlName,
                    windowSelector,
                    ,
                    "Left",
                    1,
                    "NA"
                )

                return true
            }
        }
    }

    ; Standard Windows Save As dialogs normally use Button1
    ; as the Save button.
    try {
        buttonText := ControlGetText(
            "Button1",
            windowSelector
        )

        normalizedButtonText := StrLower(
            Trim(
                StrReplace(buttonText, "&")
            )
        )

        if normalizedButtonText = "save" {
            ControlClick(
                "Button1",
                windowSelector,
                ,
                "Left",
                1,
                "NA"
            )

            return true
        }
    }

    ; Keyboard fallback for dialogs that hide their button controls.
    try {
        WinActivate(windowSelector)
        SendEvent("!s")
        return true
    }

    return false
}


; ============================================================
; SAVE-AS WINDOW VALIDATION
; ============================================================

IsTargetSaveAsDialog(hwnd) {
    global TARGET_EXE

    if !hwnd
        return false

    windowSelector := "ahk_id " hwnd

    try {
        ; Standard Windows file dialogs use the #32770 window class.
        if WinGetClass(windowSelector) != "#32770"
            return false

        ; Match only the actual Save As dialog.
        ; This intentionally excludes "Confirm Save As".
        windowTitle := Trim(WinGetTitle(windowSelector))

        if StrLower(windowTitle) != "save as"
            return false

        if TARGET_EXE != "" {
            processName := WinGetProcessName(windowSelector)

            if StrLower(processName) != StrLower(TARGET_EXE)
                return false
        }

        return true
    }
    catch {
        return false
    }
}


; ============================================================
; CLIPBOARD DIRECTORY VALIDATION
; ============================================================

GetClipboardDirectory() {
    clipboardText := Trim(A_Clipboard, " `t`r`n")

    if clipboardText = ""
        return ""

    ; Remove surrounding quotation marks copied from Explorer,
    ; terminal windows, or scripts.
    if (
        StrLen(clipboardText) >= 2
        && SubStr(clipboardText, 1, 1) = '"'
        && SubStr(clipboardText, -1) = '"'
    ) {
        clipboardText := SubStr(
            clipboardText,
            2,
            StrLen(clipboardText) - 2
        )
    }

    clipboardText := Trim(clipboardText)

    ; Avoid automatically pasting arbitrary clipboard text.
    if !DirExist(clipboardText)
        return ""

    return clipboardText
}


; ============================================================
; CLEAN UP CLOSED WINDOW HANDLES
; ============================================================

RemoveClosedDialogsFromHistory() {
    global HandledDialogs

    closedHandles := []

    for hwnd, handledTime in HandledDialogs {
        if !WinExist("ahk_id " hwnd)
            closedHandles.Push(hwnd)
    }

    for hwnd in closedHandles
        HandledDialogs.Delete(hwnd)
}


; ============================================================
; TEMPORARY STATUS MESSAGE
; ============================================================

ShowTemporaryMessage(message, durationMs := 1800) {
    ToolTip(message)

    SetTimer(
        () => ToolTip(),
        -durationMs
    )
}
#Requires AutoHotkey v2.0

; ============================================================================
; ScriptHubClient.ahk
; Cooperative tray-menu bridge for AHK Script Hub.
;
; Add this one line near the top of any AutoHotkey v2 script:
;   #Include "%A_AppData%\AHKScriptHub\ScriptHubClient.ahk"
;
; The bridge automatically:
;   - walks the script's REAL A_TrayMenu Win32 HMENU tree;
;   - publishes custom + standard menu items to Script Hub;
;   - mirrors separators, nested submenus, checked/default/disabled state;
;   - lets Script Hub route a mirrored click back by the real command ID;
;   - hides this script's own tray icon only while Hub consolidation is enabled;
;   - restores the original icon state if Hub exits or consolidation is disabled.
;
; No menu items or callbacks need to be rewritten to use this bridge.
; ============================================================================

class ScriptHubClientBridge {
    static IPC_TITLE := "AHK Script Hub IPC {9E10E19C-60E3-4D5A-BE43-4A11C68C76A1}"
    static QUERY_MESSAGE_NAME := "AHKScriptHub.QueryState.{9E10E19C-60E3-4D5A-BE43-4A11C68C76A1}"
    static WM_COPYDATA := 0x004A
    static COPYDATA_MAGIC := 0x53484231 ; "SHB1"

    static Started := false
    static QueryMessage := 0
    static HubHwnd := 0
    static LastPayload := ""
    static InitialIconHidden := false
    static HiddenByBridge := false

    static Start() {
        if this.Started
            return

        this.Started := true
        this.InitialIconHidden := !!A_IconHidden
        this.QueryMessage := DllCall(
            "User32\RegisterWindowMessageW",
            "Str", this.QUERY_MESSAGE_NAME,
            "UInt"
        )

        ; Polling is deliberate: menu state can change without a central event.
        ; 400 ms keeps check/enable state fresh without meaningful CPU cost.
        SetTimer((*) => ScriptHubClientBridge.Tick(), 400)
        OnExit((reason, code) => ScriptHubClientBridge.OnClientExit(reason, code))

        ; Perform an immediate registration attempt after the host script has
        ; begun its auto-execute section. Later menu changes are auto-detected.
        SetTimer((*) => ScriptHubClientBridge.Tick(true), -25)
    }

    static Tick(force := false) {
        hub := this.FindHubWindow()

        if !hub {
            this.HubHwnd := 0
            this.LastPayload := ""
            this.RestoreIconIfOwned()
            return
        }

        if (hub != this.HubHwnd) {
            this.HubHwnd := hub
            this.LastPayload := ""
            force := true
        }

        consolidationEnabled := this.QueryHubConsolidation(hub)

        if consolidationEnabled {
            if !A_IconHidden {
                A_IconHidden := true
                this.HiddenByBridge := true
            }
        } else {
            this.RestoreIconIfOwned()
        }

        payload := this.BuildPayload()
        if (force || payload != this.LastPayload) {
            if this.SendCopyData(hub, payload)
                this.LastPayload := payload
        }
    }

    static FindHubWindow() {
        oldDetect := A_DetectHiddenWindows
        A_DetectHiddenWindows := true
        hwnd := 0

        try hwnd := WinExist(this.IPC_TITLE " ahk_class AutoHotkeyGUI")

        A_DetectHiddenWindows := oldDetect
        return hwnd
    }

    static QueryHubConsolidation(hubHwnd) {
        if (!hubHwnd || !this.QueryMessage)
            return false

        try {
            result := DllCall(
                "User32\SendMessageW",
                "Ptr", hubHwnd,
                "UInt", this.QueryMessage,
                "UPtr", DllCall("Kernel32\GetCurrentProcessId", "UInt"),
                "Ptr", A_ScriptHwnd,
                "Ptr"
            )
            return result != 0
        } catch {
            return false
        }
    }

    static RestoreIconIfOwned() {
        ; Never unhide an icon which was already intentionally hidden by the
        ; host script before this bridge started.
        if (this.HiddenByBridge && !this.InitialIconHidden) {
            try A_IconHidden := false
        }
        this.HiddenByBridge := false
    }

    static OnClientExit(exitReason, exitCode) {
        this.RestoreIconIfOwned()
    }

    static BuildPayload() {
        pid := DllCall("Kernel32\GetCurrentProcessId", "UInt")
        payload := "AHKSH1`t" pid "`t" A_ScriptHwnd "`t" this.EncodeField(A_ScriptFullPath) "`n"

        try {
            hMenu := A_TrayMenu.Handle
            this.SerializeMenu(hMenu, 0, &payload)
        } catch {
            ; An empty snapshot is still useful; Hub will retain management
            ; controls even if this process has no usable tray menu.
        }

        return payload
    }

    static SerializeMenu(hMenu, depth, &payload) {
        if !hMenu
            return

        count := DllCall("User32\GetMenuItemCount", "Ptr", hMenu, "Int")
        if (count < 0)
            return

        ; GMDI_USEDISABLED lets a disabled default item still be identified.
        defaultPos := DllCall(
            "User32\GetMenuDefaultItem",
            "Ptr", hMenu,
            "UInt", 1, ; by position
            "UInt", 1,
            "Int"
        )

        Loop count {
            pos := A_Index - 1
            state := DllCall(
                "User32\GetMenuState",
                "Ptr", hMenu,
                "UInt", pos,
                "UInt", 0x0400, ; MF_BYPOSITION
                "UInt"
            )

            if (state = 0xFFFFFFFF)
                state := 0

            if (pos = defaultPos)
                state |= 0x1000 ; MFS_DEFAULT

            hSub := DllCall(
                "User32\GetSubMenu",
                "Ptr", hMenu,
                "Int", pos,
                "Ptr"
            )

            id := DllCall(
                "User32\GetMenuItemID",
                "Ptr", hMenu,
                "Int", pos,
                "UInt"
            )

            textBuf := Buffer(8192, 0)
            chars := DllCall(
                "User32\GetMenuStringW",
                "Ptr", hMenu,
                "UInt", pos,
                "Ptr", textBuf.Ptr,
                "Int", 4095,
                "UInt", 0x0400, ; MF_BYPOSITION
                "Int"
            )
            text := chars > 0 ? StrGet(textBuf.Ptr, chars, "UTF-16") : ""

            if (state & 0x0800) { ; MF_SEPARATOR
                kind := "S"
                id := 0
            } else if hSub {
                kind := "M"
                id := 0
            } else {
                kind := "C"
            }

            payload .= "I`t" depth "`t" kind "`t" id "`t" state "`t" this.EncodeField(text) "`n"

            if hSub
                this.SerializeMenu(hSub, depth + 1, &payload)
        }
    }

    static SendCopyData(targetHwnd, payload) {
        ; WM_COPYDATA is synchronous, so payload memory remains valid until the
        ; receiver has copied/parses the string.
        bytes := StrPut(payload, "UTF-16") * 2
        textBuf := Buffer(bytes, 0)
        StrPut(payload, textBuf, "UTF-16")

        cds := Buffer(A_PtrSize * 3, 0)
        NumPut("UPtr", this.COPYDATA_MAGIC, cds, 0)
        NumPut("UInt", bytes, cds, A_PtrSize)
        NumPut("Ptr", textBuf.Ptr, cds, A_PtrSize * 2)

        try {
            return !!DllCall(
                "User32\SendMessageW",
                "Ptr", targetHwnd,
                "UInt", this.WM_COPYDATA,
                "Ptr", A_ScriptHwnd,
                "Ptr", cds.Ptr,
                "Ptr"
            )
        } catch {
            return false
        }
    }

    static EncodeField(value) {
        s := value ""
        s := StrReplace(s, "%", "%25")
        s := StrReplace(s, "`t", "%09")
        s := StrReplace(s, "`r", "%0D")
        s := StrReplace(s, "`n", "%0A")
        return s
    }
}

ScriptHubClientBridge.Start()

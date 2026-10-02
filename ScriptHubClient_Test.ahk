#Requires AutoHotkey v2.0
#SingleInstance Force
#Include "ScriptHubClient.ahk"

Persistent()

; A deliberately non-trivial tray menu for verifying full mirroring.
A_TrayMenu.Delete()

modeMenu := Menu()
modeMenu.Add("Mode A", SetMode.Bind("A"))
modeMenu.Add("Mode B", SetMode.Bind("B"))
modeMenu.Add("Disabled Example", (*) => 0)
modeMenu.Check("Mode A")
modeMenu.Disable("Disabled Example")

nestedMenu := Menu()
nestedMenu.Add("Show Test Message", ShowTestMessage)
nestedMenu.Add("Toggle Mode", ToggleMode)
nestedMenu.Add("Modes", modeMenu)

A_TrayMenu.Add("Show Test Message", ShowTestMessage)
A_TrayMenu.Add("Nested Custom Menu", nestedMenu)
A_TrayMenu.Add()
A_TrayMenu.Add("Checked Example", ToggleChecked)
A_TrayMenu.Check("Checked Example")
A_TrayMenu.Add()
A_TrayMenu.AddStandard()
A_TrayMenu.Default := "Show Test Message"
A_IconTip := "Script Hub full-menu bridge test"

^!F12::ShowTestMessage()

ShowTestMessage(*) {
    MsgBox("This callback came from the test script's REAL A_TrayMenu command ID.", "Script Hub Test")
}

ToggleChecked(itemName := "Checked Example", itemPos := 0, menuObj := 0) {
    A_TrayMenu.ToggleCheck("Checked Example")
}

SetMode(mode, *) {
    global modeMenu
    modeMenu.Uncheck("Mode A")
    modeMenu.Uncheck("Mode B")
    modeMenu.Check("Mode " mode)
    ToolTip("Mode changed to " mode)
    SetTimer((*) => ToolTip(), -900)
}

ToggleMode(*) {
    static current := "A"
    current := current = "A" ? "B" : "A"
    SetMode(current)
}

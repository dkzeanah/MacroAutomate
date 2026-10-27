#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\FanBridgeClient.ahk

global pairGui := Gui("+AlwaysOnTop", "Fan — Connect existing Chrome")
pairGui.SetFont("s10", "Segoe UI")
pairGui.Add("Text", "w700 h72", "Open the Fan extension in your normal Chrome job window. Paste this fresh code and click Connect this normal window.`nThis dialog will confirm when Fan receives the connection. The code expires in 10 minutes.")
global pairCode := pairGui.Add("Edit", "w700 ReadOnly")
pairGui.Add("Button", "w210", "Copy pairing code").OnEvent("Click", (*) => (A_Clipboard := pairCode.Value))
pairGui.Add("Button", "x+12 w210", "Generate fresh code").OnEvent("Click", (*) => ChromePair_Generate())
global pairStatus := pairGui.Add("Text", "xm w700 h54", "Waiting for the Chrome connector…")
pairGui.Add("Text", "w700 h45", "If Chrome shows an error, copy its exact text back to Codex. If it connected successfully, this status changes automatically.")
pairGui.OnEvent("Close", (*) => ExitApp())
ChromePair_Generate()
SetTimer(ChromePair_Check, 2000)
pairGui.Show()

ChromePair_Generate() {
    try {
        result := FanBridge.Call("fan_job_chrome_pair")
        pairCode.Value := result["pair_code"]
        pairStatus.Value := "Fresh code ready — waiting for Chrome to connect."
    } catch as err
        pairStatus.Value := err.Message
}

ChromePair_Check() {
    try {
        result := FanBridge.Call("fan_job_chrome_status")
        if result.Get("connected", false) {
            pairStatus.Value := "CONNECTED — Fan received the handshake from your selected normal Chrome window."
            SetTimer(ChromePair_Check, 0)
            pairGui.Opt("-AlwaysOnTop")
        }
    } catch as err
        pairStatus.Value := err.Message
}

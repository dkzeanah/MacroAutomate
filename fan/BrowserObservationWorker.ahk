#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
; Reuse native accessibility reading in its own process, without GUI/startup.
#Include Core\_Bootstrap.ahk
#Include ..\lib\FanBridgeJson.ahk
global observationRequest := FanBridgeJsonDecode(FileRead(A_Args[1],"UTF-8"))
g_FanSeedPath := observationRequest["db_path"]
FileAppend("Reader: loading native modules`n","*")
#Include Core\_Dependencies.ahk
#Include Core\_Globals.ahk
#Include Core\_Modules.ahk
FileAppend("Reader: probing Chrome`n","*")
DeepActivity_Suspend()
try result := FanPage_Probe(Map("hwnd",observationRequest["hwnd"],"_passive",true))
catch as observationError
    result := Map("ok",false,"error",observationError.Message)
FileAppend("Reader: storing result`n","*")
Track_WriteFile(observationRequest["output"] . ".tmp",TrackJsonEncode(result))
FileMove(observationRequest["output"] . ".tmp",observationRequest["output"],1)
ExitApp()

#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\FanBridgeClient.ahk
if A_Args.Length != 1
    ExitApp(2)
request := FanBridgeJsonDecode(FileRead(A_Args[1],"UTF-8"))
allowed := Map("fan_page_learn",true,"fan_page_get",true,"fan_page_image",true,"fan_page_resolve",true)
try {
    if !allowed.Has(request["tool"])
        throw Error("Unsupported browser review operation")
    result := FanBridge.Call(request["tool"],request["args"],175000)
} catch as workerError
    result := Map("ok",false,"error",workerError.Message)
output := request["result"]
FileAppend(FanBridgeJsonEncode(result),output . ".tmp","UTF-8-RAW")
FileMove(output . ".tmp",output,1)
ExitApp()

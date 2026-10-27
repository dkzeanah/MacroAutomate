#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include %A_ScriptDir%\..\..\..\lib\FanBridgeClient.ahk

Normalize(text) => StrLower(RegExReplace(text,"[^a-zA-Z0-9]",""))
Stop(reason) {
    FileAppend("NAV_STOP: " . reason . "`n","*")
    ExitApp(2)
}
Guard(hwnd) {
    if !WinActive(hwnd) || WinGetTitle(hwnd)!="DomeSim Studio" || StrLower(WinGetProcessName(hwnd))!="python.exe"
        Stop("Exact DomeSim Studio target lost foreground")
}

args := FanBridgeJsonDecode(EnvGet("FAN_TOOL_INPUT")), hwnd := args["hwnd"], label := args["label"]
allowed := ["Presentation Lab","Presenter & Video Studio","Story Editor","Dome Layer Studio","2 Trees Book Studio",
    "Dome Creator","Dome Home Assembly Line","Assembly Line Lite","Local Voice Studio","Project Utilities"]
accepted := false
for name in allowed
    if name=label
        accepted := true
if !accepted || !WinExist(hwnd) || WinGetTitle(hwnd)!="DomeSim Studio" || StrLower(WinGetProcessName(hwnd))!="python.exe"
    Stop("Unknown label or window identity")
WinActivate(hwnd)
if !WinWaitActive(hwnd,,5)
    Stop("Could not activate exact window")
Guard(hwnd)
probe := FanBridge.Call("fan_window_probe",Map("hwnd",hwnd),45000)
if !probe.Get("ok",false)
    Stop("Live geometry probe failed")
region := probe["frame"]["region"]
sidebar := Map("x",region["x"]+Round(region["w"]*.01),"y",region["y"]+Round(region["h"]*.17),
    "w",Round(region["w"]*.145),"h",Round(region["h"]*.61))
pattern := "DAADomeNav20261024_" . Normalize(label), point := 0, method := ""
found := FanBridge.FindPattern(pattern,hwnd,sidebar)
if found.Get("ok",false)
    for match in found.Get("matches",[]) {
        c := match["center"]
        if c["x"]>=sidebar["x"] && c["x"]<sidebar["x"]+sidebar["w"] && c["y"]>=sidebar["y"] && c["y"]<sidebar["y"]+sidebar["h"] {
            if !IsObject(point) || c["x"]<point["x"]
                point := c, method := "live FindText match of retained sidebar pattern"
        }
    }
if !IsObject(point) {
    observed := FanBridge.Call("fan_window_inspect",Map("hwnd",hwnd,"region",sidebar,"include_image",false,"include_ocr",true,"limit",60),60000)
    box := 0
    for line in observed.Get("ocr",Map()).Get("lines",[]) {
        if Normalize(line["text"])!=Normalize(label)
            continue
        b := line["bounds"]
        if !IsObject(box) || b["x"]<box["x"]
            box := b
    }
    if !IsObject(box)
        Stop("Exact navigation label was not observed in the learned sidebar zone")
    point := Map("x",box["x"]+box["w"]//2,"y",box["y"]+box["h"]//2), method := "fresh zoned OCR"
    ; Preserve an original image-derived pattern for subsequent local reuse.
    capture := Map("x",Max(sidebar["x"],box["x"]-3),"y",Max(sidebar["y"],box["y"]-3),
        "w",box["w"]+6,"h",box["h"]+6)
    try FanBridge.Call("fan_pattern_capture",Map("name",pattern,"hwnd",hwnd,"region",capture,
        "threshold","**50","description","DomeSim Studio navigation only: " . label . "; observed sidebar OCR; always verify resulting heading"),60000)
}
Guard(hwnd)
hit := DllCall("WindowFromPoint","Int64",(point["y"]<<32)|(point["x"] & 0xFFFFFFFF),"Ptr")
if !hit || DllCall("GetAncestor","Ptr",hit,"UInt",2,"Ptr")!=hwnd
    Stop("Observed sidebar label is covered")
FanBridge.Call("daa_trace",Map("label","Select navigation: " . label,"hwnd",hwnd,"phase","before", "x",point["x"],"y",point["y"],"evidence",method . "; frame " . probe["frame"]["frame_id"]))
Guard(hwnd)
oldCoord := A_CoordModeMouse
try {
    CoordMode("Mouse","Screen"), MouseMove(point["x"],point["y"],8), Click()
} finally CoordMode("Mouse",oldCoord)
Sleep(250)
Guard(hwnd)
after := FanBridge.Call("fan_window_inspect",Map("hwnd",hwnd,"include_image",true,"include_ocr",true,"grid",false,"limit",100),60000)
verified := false
for line in after.Get("ocr",Map()).Get("lines",[])
    if Normalize(line["text"])=Normalize(label) && line["bounds"]["x"]>=sidebar["x"]+sidebar["w"]
        verified := true
if !verified || !after.Get("frame",Map()).Get("geometry_stable",false)
    Stop("Feature heading was not verified after selection; no retry or Run action issued")
FanBridge.Call("daa_trace",Map("label","Verified feature heading: " . label,"hwnd",hwnd,"phase","after",
    "x",point["x"],"y",point["y"],"evidence","Zoned OCR heading in frame " . after["frame"]["frame_id"]))
FileAppend("NAV_VERIFIED:" . label . "`n","*")

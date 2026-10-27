#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include Core\_Gdip.ahk
#Include ..\lib\NativeWorkbench.ahk
FanData_ProjectRoot() => A_ScriptDir . "\.."
AgentWorkbench_OpenWeb(*) => 0
NativeTest_Tools() {
    s := g_NativeWB, mode := s["ui"]["category"].Value
    NativeWB_RenderTools(mode=1 ? s["registry"]["tools"] : mode=3 ? s["registry"]["methods"] : s["registry"]["artifacts"])
}
global failures := 0
Check(ok,label) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
original := WinExist("A")
try {
    s := g_NativeWB, s["root"] := A_ScriptDir . "\DeepSeekBridge"
    NativeWB_Build(), g := s["gui"], u := s["ui"]
    g.Show("NoActivate w1420 h820")
    Check(WinGetClass(g.Hwnd)="AutoHotkeyGUI","viewer is an actual native AutoHotkey GUI")
    Check(u["tabs"].Text="Observation canvas","native observation canvas is the default")
    Check(u["follow"].Value && !u["follow"].Enabled,"follow newest is always checked")
    Check(u["copy"].Text="Copy analysis log","analysis export has a native button")
    Check(u["pause"].Text="Pause" && u["runDot"].Text="●","native pause and bottom-left activity indicator exist")
    u["tabs"].Choose(5)
    Check(u["tabs"].Text="Knowledge stats" && IsObject(u["statsRows"]),"knowledge statistics have their own native tab")
    u["tabs"].Choose(1)
    s["registry"] := Map("tools",[Map("name","fan_ocr","description","Read text","family","OCR")],
        "methods",[Map("name","FindText","path","FindText.ahk","line",1,"signature","FindText()","family","FindText")],
        "artifacts",[Map("name","Fixture.ahk","kind","script","revision",5,"path","fixture.ahk")])
    NativeTest_Tools()
    Check(u["tools"].GetCount()=1 && u["tools"].GetText(1,1)="fan_ocr","direct tools populate native list")
    s["active"]["fan_ocr"] := true, NativeWB_Highlight()
    Check(u["tools"].GetText(1,2)="ACTIVE" && s["colors"].Has(0),"running tool gets active state and row highlight")
    u["category"].Choose(2), NativeTest_Tools()
    Check(u["tools"].GetText(1,1)="Fixture.ahk" && u["tools"].GetText(1,2)="r5","script list displays file name and source revision")
    s["active"]["Fixture.ahk"] := true, NativeWB_Highlight()
    Check(u["tools"].GetText(1,2)="ACTIVE","running script file itself is highlighted")
    u["category"].Choose(3), NativeTest_Tools()
    s["recent"]["FindTextClass.FindText"] := A_TickCount, NativeWB_Highlight()
    Check(u["tools"].GetText(1,2)="recent" && s["colors"].Has(0),"traced library method highlights its native row")
    u["toolQuery"].Value := "missing", NativeTest_Tools()
    Check(u["tools"].GetCount()=0,"native tooling search filters the actual list")
    controls := Map("id","fixture:controls","event_id",1,"at","2026-10-18T10:00:00Z","kind","controls","title","Identified controls","data",Map("controls",[Map("role","Button","name","Calculate","value","","bounds",Map("x",1,"y",2,"w",150,"h",39))]))
    ocr := Map("id","fixture:ocr","event_id",2,"at","2026-10-18T10:00:01Z","kind","ocr","title","OCR","data",Map("text","21 + 21 = 42","words",[Map("text","42","bounds",Map("x",1,"y",2,"w",30,"h",20))]))
    pattern := Map("id","fixture:pattern","event_id",3,"at","2026-10-18T10:00:02Z","kind","findtext","title","FindText matches","data",Map("total_matches",1,"translation",Map("width",2,"height",2,"bits","1001")))
    for card in [controls,ocr,pattern]
        NativeWB_AddCard(card)
    NativeWB_AddCard(controls)
    Check(u["timeline"].GetCount()=3,"one chronological native item per observation; duplicate events are ignored")
    NativeWB_SelectCard(u["timeline"],1,true)
    Check(u["follow"].Value,"inspecting history preserves follow newest for the next arriving entry")
    NativeWB_ShowCard(controls)
    Check(!s.Get("overlays",[]).Length,"programmatic auto-follow does not draw desktop overlays")
    Check(NativeOverlay_Boxes(controls,1).Length=1,"selected control maps to its retained candidate bounds")
    WinGetPos(&gx,&gy,&gw,&gh,"ahk_id " . g.Hwnd)
    frame := Map("hwnd",g.Hwnd,"pid",DllCall("GetCurrentProcessId"),"window_rect",Map("x",gx,"y",gy,"w",gw,"h",gh))
    Check(NativeOverlay_Validate(frame)=g.Hwnd,"overlay projection verifies the live window process and rectangle")
    frame["window_rect"]["x"] += 10, rejected := false
    try NativeOverlay_Validate(frame)
    catch
        rejected := true
    Check(rejected,"moved-window evidence refuses stale coordinate projection")
    frame["window_rect"]["x"] -= 10
    outline := Map("kind","controls","frame",frame,"data",Map("controls",[Map("bounds",Map("x",gx+90,"y",gy+7,"w",100,"h",15))]))
    hit := DllCall("WindowFromPoint","Int64",((gy+14)<<32)|((gx+140)&0xFFFFFFFF),"Ptr")
    visibleCandidate := hit && DllCall("GetAncestor","Ptr",hit,"UInt",2,"Ptr")=g.Hwnd
    NativeOverlay_Show(outline,1)
    Check(s["overlays"].Length=(visibleCandidate ? 1 : 0),"selection draws visible candidates and skips covered candidates")
    NativeOverlay_Clear()
    overlayForeground := WinExist("A")
    s["overlays"].Push(NativeOverlay_Border(gx+90,gy+7,100,15))
    Check(DllCall("IsWindowVisible","Ptr",s["overlays"][1].Hwnd),"native outline window actually renders")
    testRegion := DllCall("CreateRectRgn","Int",0,"Int",0,"Int",0,"Int",0,"Ptr")
    DllCall("GetWindowRgn","Ptr",s["overlays"][1].Hwnd,"Ptr",testRegion)
    Check(!DllCall("PtInRegion","Ptr",testRegion,"Int",50,"Int",7),"outline is hollow so the target contents remain visible")
    DllCall("DeleteObject","Ptr",testRegion)
    transparent := true
    for border in s["overlays"]
        transparent := transparent && (WinGetExStyle(border.Hwnd)&0x08080020)=0x08080020
    Check(transparent && WinExist("A")=overlayForeground,"outlines are click-through and do not activate the target")
    NativeOverlay_Clear()
    Check(!s["overlays"].Length,"outline cleanup removes every temporary border")
    s["task"] := Map("status","running","prompt","Inspect actual window")
    NativeDAA_State(Map("control",Map("paused",true),"chain",Map("step_count",1),"current_subtask",Map("branch","navigation"),"steps",[Map("number",1,"tool","fan_ocr","status","running")]))
    Check(u["pause"].Text="Resume" && InStr(u["footer"].Value,"Subtask: navigation") && InStr(u["footer"].Value,"PAUSED"),"live state identifies goal, subtask, action and resume requirement")
    Check(u["controls"].GetCount()=1 && u["controls"].GetText(1,2)="Calculate","identified controls are grouped in a readable native table")
    NativeWB_ShowCard(ocr)
    Check(InStr(u["details"].Value,"21 + 21 = 42") && InStr(u["details"].Value,"WORD / LINE LOCATIONS"),"OCR exposes readable text and complete retained locations")
    NativeWB_ShowCard(pattern)
    Check(FileExist(s["picture"]),"FindText binary pixels render as an actual native picture")
    Check(InStr(u["details"].Value,'"bits"') && InStr(u["details"].Value,"1001"),"FindText encoding and match details remain inspectable")
    u["tabs"].Choose(6)
    Check(u["tabs"].Text="DAA chains" && IsObject(u["chainTree"]) && IsObject(u["cueNext"]),"numbered execution map and operator narration controls are native")
    NativeDAA_Translate(s["picture"])
    Check(InStr(u["ascii"].Value,"ASCII luminance") && InStr(u["encoding"].Value,"BASE64 PREFIX"),"actual retained pixels translate into bounded ASCII and Base64 previews")
    NativeDAA_Mini([])
    Check(InStr(u["miniNote"].Value,"LIVE desktop origin"),"mini desktop captures actual virtual-screen geometry without application input")
    u["tabs"].Choose(7)
    Check(u["tabs"].Text="Explorer paths" && IsObject(u["explorerRows"]),"Explorer attention rankings have a native view")
    summary := NativeDAA_Comparison(Map("target","DomeSim Studio","first_tour",Map("provider_requests",4,"spending",Map("usd_high",0.01)),"local_replay",Map("provider_requests",0,"spending",Map("usd_high",0)),"provider_calls_avoided_vs_this_baseline",4))
    Check(InStr(summary,"4 → 0") && InStr(summary,"difference versus this baseline 4"),"replay banner shows measured provider-call reduction rather than invented savings")
    u["tabs"].Choose(1)
    comparison := Map("event_id",4,"kind","comparison","title","Saved replay comparison","data",Map("first_pass",Map("api_requests",3,"spending",Map("usd_low",0.012,"usd_high",0.012)),"replay",Map("api_requests",0,"spending",Map("usd_low",0,"usd_high",0)),"api_requests_avoided_vs_baseline",3,"source",Map("name","VSCodeLearnedLesson.ahk","revision",7,"unchanged",true),"verified_result",Map("answer",42,"run_count",2)))
    NativeWB_ShowCard(comparison)
    Check(InStr(u["details"].Value,"Reviewed baseline pass: 3 API requests") && InStr(u["details"].Value,"Saved replay: 0 API requests") && InStr(u["details"].Value,"$0.012000") && InStr(u["details"].Value,"execution count 2"),"native comparison exposes actual calls, cost and verified execution count")
    viewUpdateForeground := WinExist("A")
    NativeWB_Stream(u["thinking"],"Round 1`r`n" . StrReplace(Format("{:6000}","")," ","thinking`r`n"))
    Check(SendMessage(0xCE,0,0,u["thinking"])>0,"native thinking view follows the bottom of the stream")
    NativeWB_Resize(g,0,1280,760)
    u["tools"].GetPos(&x,&y,&w,&h)
    Check(x=950 && w=310 && h=410,"native layout responds to resizing")
    Check(WinExist("A")=viewUpdateForeground,"native viewer updates preserve the foreground window")
} catch as err {
    Check(false,err.Message . " · " . err.File . ":" . err.Line)
} finally {
    SetTimer(NativeWB_Tick,0), SetTimer(NativeWB_Tools,0)
    if IsObject(g_NativeWB["gui"])
        g_NativeWB["gui"].Destroy()
}
ExitApp(failures)

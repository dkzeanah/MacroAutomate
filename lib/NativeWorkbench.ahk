#Include FanBridgeJson.ahk
#Include NativeDaaWorkbench.ahk
#Include NativeObservationOverlay.ahk
; Native controls only: no browser, WebView, HTML or embedded Chrome runtime.
global g_NativeWB := Map("gui",0,"ui",Map(),"busy",false,"selected","","cursor",0,
    "runs",[],"cards",[],"seen",Map(),"thinking","","conversation","","round",0,
    "registry",Map("tools",[],"methods",[],"artifacts",[]),"toolRows",[],"discoveryRows",[],
    "recent",Map(),"active",Map(),"lastRuns",0,"lastRegistry",0,"lastDiscoveries",0,
    "picture","","task",Map(),"colors",Map(),"root","","toolSignature","")

NativeWorkbench_Open(view := "canvas") {
    s := g_NativeWB
    if !IsObject(s["gui"]) {
        s["root"] := FanData_ProjectRoot() . "\fan\DeepSeekBridge"
        NativeWB_Build()
    }
    try {
        start := "DeepBridge_Start"
        %start%()
    }
    s["ui"]["tabs"].Choose(view="chains" ? 6 : view="explorer" ? 7 : view="stats" ? 5 : view="discoveries" ? 4 : view="thinking" ? 2 : 1)
    g := s["gui"], options := "NoActivate w1420 h820"
    try {
        chooseMonitor := "LearningValidation_Monitor"
        monitor := %chooseMonitor%()
        if monitor {
            MonitorGetWorkArea(monitor,&l,&t,&r,&b)
            options := "NoActivate x" . (l+16) . " y" . (t+16) . " w" . Min(1420,r-l-32) . " h" . Min(820,b-t-32)
        }
        place := "SecondaryWindows_Place"
        %place%(g,options)
    } catch
        g.Show(options)
    SetTimer(NativeWB_Tick,1000)
    SetTimer((*)=>NativeWB_Tick(),-50)
}

NativeWB_Build() {
    s := g_NativeWB, u := s["ui"]
    g := Gui("+Resize +MinSize1050x660 -DPIScale","Live Learning Workbench — Native AHK")
    g.SetFont("s10","Segoe UI"), s["gui"] := g
    u["heading"] := g.Add("Text","x12 y10 w550 h26","Live Learning Workbench")
    u["heading"].SetFont("s13 Bold")
    u["status"] := g.Add("Text","x12 y42 w1380 h22","Connecting to retained observations and live native tools…")
    u["bridge"] := g.Add("Button","x800 y8 w130 h28","Bridge")
    u["bridge"].OnEvent("Click",NativeWB_Bridge)
    u["stored"] := g.Add("Button","x940 y8 w130 h28","Lessons")
    u["stored"].OnEvent("Click",(*)=>NativeWB_Invoke("LearningLab_Open"))
    u["web"] := g.Add("Button","x1080 y8 w105 h28","Web (optional)")
    u["web"].OnEvent("Click",(*)=>AgentWorkbench_OpenWeb())
    u["stop"] := g.Add("Button","x1195 y8 w125 h28","Stop run")
    u["stop"].OnEvent("Click",NativeWB_Stop)
    u["pause"] := g.Add("Button","x1325 y8 w85 h28","Pause")
    u["pause"].OnEvent("Click",NativeDAA_Pause)
    u["followRuns"] := g.Add("Checkbox","x12 y78 w215 h22 Checked","Follow new tasks")
    u["follow"] := g.Add("Checkbox","x245 y78 w180 h22 Checked Disabled","Follow newest entries")
    u["task"] := g.Add("Button","x430 y74 w130 h27","Read full task")
    u["task"].OnEvent("Click",(*)=>NativeWB_TextWindow("Task instructions",s["task"].Get("prompt","Select a task")))
    u["copy"] := g.Add("Button","x570 y74 w140 h27","Copy analysis log")
    u["copy"].OnEvent("Click",NativeWB_CopyLog)
    u["runs"] := g.Add("ListView","x12 y106 w220 h640 -Multi",["State","Performed sequence"])
    u["runs"].ModifyCol(1,84), u["runs"].ModifyCol(2,125)
    u["runs"].OnEvent("ItemSelect",NativeWB_SelectRun)
    u["older"] := g.Add("Button","x12 y755 w220 h27","Load older sequences")
    u["older"].OnEvent("Click",(*)=>NativeWB_LoadRuns(true))
    u["tabs"] := g.Add("Tab3","x244 y108 w830 h670",["Observation canvas","Thinking","Conversation","Discoveries","Knowledge stats","DAA chains","Explorer paths"])
    u["tabs"].OnEvent("Change",(*)=>NativeWB_Tab())
    u["tabs"].UseTab(1)
    u["timeline"] := g.Add("ListView","x256 y144 w805 h172 -Multi",["#","Type","Observation / action","Time"])
    for col,width in [48,85,485,115]
        u["timeline"].ModifyCol(col,width)
    u["timeline"].OnEvent("ItemSelect",NativeWB_SelectCard)
    u["caption"] := g.Add("Text","x256 y324 w805 h42","Each capture, OCR result, control group and FindText result has its own chronological entry.")
    u["picture"] := g.Add("Picture","x256 y370 w310 h220")
    u["picture"].OnEvent("DoubleClick",(*)=>NativeWB_ImageWindow())
    u["details"] := g.Add("Edit","x576 y370 w485 h385 ReadOnly Multi +VScroll +Wrap")
    u["controls"] := g.Add("ListView","x256 y370 w805 h385 -Multi",["Role","Name","Value / state","Observed bounds"])
    for col,width in [100,210,220,230]
        u["controls"].ModifyCol(col,width)
    u["tabs"].UseTab(2)
    u["thinking"] := g.Add("Edit","x256 y146 w805 h610 ReadOnly Multi +VScroll +Wrap")
    u["thinking"].SetFont("s10","Segoe UI")
    u["tabs"].UseTab(3)
    u["conversation"] := g.Add("Edit","x256 y146 w805 h610 ReadOnly Multi +VScroll +Wrap")
    u["tabs"].UseTab(4)
    u["discoveryQuery"] := g.Add("Edit","x256 y145 w570 h27")
    SendMessage(0x1501,true,StrPtr("Find a claim number, discovery or source…"),u["discoveryQuery"])
    u["discoveryQuery"].OnEvent("Change",(*)=>SetTimer(NativeWB_Discoveries,-350))
    u["lesson"] := g.Add("Button","x835 y145 w225 h27","Show native lesson / rehearsal")
    u["lesson"].OnEvent("Click",NativeWB_Lesson)
    u["discoveries"] := g.Add("ListView","x256 y181 w805 h170 -Multi",["Kind / source","Discovery / claim","Support"])
    for col,width in [135,480,165]
        u["discoveries"].ModifyCol(col,width)
    u["discoveries"].OnEvent("ItemSelect",NativeWB_SelectDiscovery)
    u["evidence"] := g.Add("Edit","x256 y360 w805 h395 ReadOnly Multi +VScroll +Wrap")
    u["tabs"].UseTab(5)
    u["statsQuery"] := g.Add("Edit","x256 y145 w805 h27")
    SendMessage(0x1501,true,StrPtr("Filter window maps by app or title…"),u["statsQuery"])
    u["statsQuery"].OnEvent("Change",(*)=>SetTimer(NativeWB_Stats,-350))
    u["statsSummary"] := g.Add("Text","x256 y178 w805 h72","Waiting for local knowledge statistics…")
    u["statsCost"] := g.Add("Text","x256 y252 w805 h48","")
    u["statsRows"] := g.Add("ListView","x256 y310 w805 h150 -Multi",["Window / app","Facts","Reuse / fresh","Est. tokens saved"])
    for col,width in [360,100,130,160]
        u["statsRows"].ModifyCol(col,width)
    u["statsRows"].OnEvent("ItemSelect",NativeWB_SelectWindow)
    u["statsMore"] := g.Add("Button","x256 y466 w190 h30","Next facts")
    u["statsMore"].OnEvent("Click",(*)=>NativeWB_WindowFacts(true))
    u["pathQuery"] := g.Add("Edit","x456 y466 w390 h30")
    SendMessage(0x1501,true,StrPtr("Find an indexed Desktop project/path…"),u["pathQuery"])
    u["pathQuery"].OnEvent("Change",(*)=>SetTimer(NativeWB_ProjectPaths,-400))
    u["statsDetails"] := g.Add("Edit","x256 y504 w805 h251 ReadOnly Multi +VScroll +Wrap")
    NativeDAA_Build(g,u)
    u["tabs"].UseTab(0)
    u["toolHeading"] := g.Add("Text","x1090 y78 w310 h22","Usable tooling · active green / recent amber")
    u["category"] := g.Add("DropDownList","x1090 y109 w310 Choose1",["Direct agent tools","Written .ahk files","Library functions","Saved workflows / patterns"])
    u["category"].OnEvent("Change",(*)=>NativeWB_Tools())
    u["toolQuery"] := g.Add("Edit","x1090 y142 w310 h26")
    SendMessage(0x1501,true,StrPtr("FindText, OCR, Acc, script name…"),u["toolQuery"])
    u["toolQuery"].OnEvent("Change",(*)=>SetTimer(NativeWB_Tools,-200))
    u["tools"] := g.Add("ListView","x1090 y176 w310 h500 -Multi",["Tool / function / file","Activity"])
    u["tools"].ModifyCol(1,210), u["tools"].ModifyCol(2,80)
    u["tools"].OnNotify(-12,NativeWB_ToolDraw)
    u["tools"].OnEvent("DoubleClick",(*)=>NativeWB_Source())
    u["source"] := g.Add("Button","x1090 y685 w310 h28","Read selected source / schema")
    u["source"].OnEvent("Click",NativeWB_Source)
    u["moreTools"] := g.Add("Button","x1090 y650 w310 h28","Load more tooling")
    u["moreTools"].OnEvent("Click",(*)=>NativeWB_Tools(true))
    u["toolNote"] := g.Add("Text","x1090 y720 w310 h64","Library source references. SDK calls are traced; other scripts need tracing.")
    u["runDot"] := g.Add("Text","x12 y790 w20 h24 c808080","●")
    u["runDot"].SetFont("s14")
    u["footer"] := g.Add("Text","x36 y773 w1356 h44","Native AHK · Ctrl + right-drag to move · select an observation to outline retained bounds")
    OnMessage(0x202,NativeOverlay_Input), OnMessage(0x101,NativeOverlay_Input)
    g.OnEvent("Size",NativeWB_Resize)
    g.OnEvent("Close",(*)=>(g.Hide(),NativeOverlay_Clear(),SetTimer(NativeWB_Tick,0)))
    g.OnEvent("Escape",(*)=>g.Hide())
    u["picture"].Visible := false, u["controls"].Visible := false
}

NativeWB_Invoke(name, args*) {
    if g_NativeWB.Get("owner",0) {
        if name="LearningLab_Open"
            return NativeWB_Owner(2)
        if name="LearningLab_Present"
            return NativeWB_Owner(3,args[1].Get("claim_id",0))
    }
    try return %name%(args*)
    catch as err
        NativeWB_TextWindow("Workbench",err.Message)
}

NativeWB_Bridge(*) {
    global MainGui, TabCtrl
    if g_NativeWB.Get("owner",0)
        return NativeWB_Owner(1)
    try {
        TabCtrl.Choose(20), MainGui.Show()
        NativeWB_Invoke("DeepBridge_Render")
    }
}

NativeWB_Owner(action,identity := 0) {
    hwnd := g_NativeWB.Get("owner",0)
    if hwnd && WinExist("ahk_id " . hwnd)
        PostMessage(0x84F7,action,identity,,hwnd)
}

NativeWB_Config() {
    config := Map()
    for line in StrSplit(FileRead(g_NativeWB["root"] . "\.env","UTF-8"),"`n","`r") {
        at := InStr(line,"=")
        if at>1
            config[Trim(SubStr(line,1,at-1))] := Trim(SubStr(line,at+1))
    }
    return config
}

NativeWB_HTTP(path, body := unset, save := "", raw := false) {
    config := NativeWB_Config(), request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetProxy(1), request.SetTimeouts(500,500,1500,5000)
    request.Open(IsSet(body) ? "POST" : "GET","http://127.0.0.1:" . config.Get("MONITOR_PORT","8766") . path,false)
    request.SetRequestHeader("X-Bridge-Token",config.Get("BRIDGE_TOKEN",""))
    if IsSet(body) {
        request.SetRequestHeader("Content-Type","application/json; charset=utf-8")
        request.Send(FanBridgeJsonEncode(body))
    } else
        request.Send()
    if request.Status!=200
        throw Error("Local Workbench HTTP " . request.Status . " · " . SubStr(request.ResponseText,1,220))
    if save!="" {
        stream := ComObject("ADODB.Stream"), stream.Type := 1, stream.Open()
        try {
            stream.Write(request.ResponseBody), stream.SaveToFile(save,2)
        } finally stream.Close()
        return save
    }
    return raw ? request.ResponseText : FanBridgeJsonDecode(request.ResponseText)
}

NativeWB_Encode(text) {
    bytes := Buffer(StrPut(text,"UTF-8")), length := StrPut(text,bytes,"UTF-8")-1, out := ""
    loop length {
        c := NumGet(bytes,A_Index-1,"UChar")
        out .= (c>=65 && c<=90 || c>=97 && c<=122 || c>=48 && c<=57 || c=45 || c=46 || c=95) ? Chr(c) : Format("%{:02X}",c)
    }
    return out
}

NativeWB_Tick(*) {
    s := g_NativeWB, u := s["ui"]
    if s["busy"] || !IsObject(s["gui"]) || !DllCall("IsWindowVisible","Ptr",s["gui"].Hwnd)
        return
    s["busy"] := true
    try {
        health := NativeWB_HTTP("/api/health"), s["active"] := Map()
        activity := health.Get("activity",Map())
        s["automationActive"] := activity.Get("running_tasks",0)>0 || activity.Get("application_runs",0)>0 || health.Get("managed_scripts",[]).Length>0
        for name in health.Get("activity",Map()).Get("tools",[])
            s["active"][name] := true
        for script in health.Get("managed_scripts",[])
            s["active"][script["name"]] := true
        if A_TickCount-s["lastRuns"]>4000
            NativeWB_LoadRuns()
        if A_TickCount-s["lastRegistry"]>5000 && (u["category"].Value!=3 || !s["toolRows"].Length) {
            NativeWB_Tools()
            s["lastRegistry"] := A_TickCount
        }
        if s["selected"]!="" && (u["tabs"].Value<=3 || u["tabs"].Value=6)
            NativeWB_Events()
        if u["tabs"].Value=4 && A_TickCount-s["lastDiscoveries"]>5000
            NativeWB_Discoveries()
        if u["tabs"].Value=5 && A_TickCount-s.Get("lastStats",0)>5000
            NativeWB_Stats()
        if s["selected"]!=""
            NativeDAA_Refresh()
        if u["tabs"].Value=7
            NativeDAA_Explorer()
        NativeWB_Highlight()
        active := ""
        for name in s["active"]
            active .= (active!="" ? ", " : "") . name
        nativeBusy := false
        for name in s["active"]
            if SubStr(name,1,4)="fan_"
                nativeBusy := true
        u["status"].Value := (nativeBusy ? "Native tool active" : health.Get("fan_connected",false) ? "Native tools connected" : "Native tools connecting")
            . " · " . s["task"].Get("status","Select a task") . " · " . s["cards"].Length . " chronological entries"
            . (active!="" ? " · ACTIVE: " . active : " · Viewing retained evidence")
            . " · Task: " . SubStr(StrReplace(s["task"].Get("prompt",""),"`n"," "),1,65)
    } catch as err {
        u["status"].Value := "Connecting · " . err.Message
        u["runDot"].SetFont("c808080"), u["pause"].Enabled := false
        u["footer"].Value := "Bridge unavailable · current execution cannot be verified. Needs: reconnect to the local Bridge."
    }
    finally s["busy"] := false
}

NativeWB_LoadRuns(older := false) {
    s := g_NativeWB, lv := s["ui"]["runs"], previous := s["runs"].Length ? s["runs"][1]["id"] : ""
    data := NativeWB_HTTP("/api/runs?compact=1&offset=" . (older ? s["runs"].Length : 0))
    if older {
        for row in data["runs"] {
            s["runs"].Push(row), lv.Add("",row["status"],StrReplace(row["prompt"],"`n"," "))
        }
    } else {
        signature := ""
        for item in data["runs"]
            signature .= item["id"] . ":" . item["status"] . "|"
        if signature=s.Get("runSignature","") {
            s["lastRuns"] := A_TickCount
            return
        }
        s["runSignature"] := signature
        s["runs"] := data["runs"], lv.Opt("-Redraw"), lv.Delete()
        for row in s["runs"] {
            n := lv.Add("",row["status"],StrReplace(row["prompt"],"`n"," "))
            if row["id"]=s["selected"]
                lv.Modify(n,"Select")
        }
        lv.Opt("+Redraw")
        if s["runs"].Length && (s["selected"]="" || s["ui"]["followRuns"].Value && previous!=s["runs"][1]["id"]) {
            chosen := s["runs"][1]
            if s["selected"]="" && s.Get("initialTask","")!=""
                for item in s["runs"]
                    if item["id"]=s["initialTask"]
                        chosen := item
            NativeWB_SetRun(chosen)
        }
    }
    s["lastRuns"] := A_TickCount
}

NativeWB_SelectRun(lv,row,selected) {
    if !selected || row>g_NativeWB["runs"].Length || g_NativeWB["busy"]
        return
    g_NativeWB["ui"]["followRuns"].Value := false
    NativeWB_SetRun(g_NativeWB["runs"][row])
}

NativeWB_SetRun(task) {
    s := g_NativeWB
    s["selected"] := task["id"], s["task"] := task, s["cursor"] := 0
    s["cards"] := [], s["seen"] := Map(), s["thinking"] := "", s["conversation"] := "", s["round"] := 0
    s["currentCard"] := Map(), s["picture"] := ""
    s["lastEvidenceImage"] := "", s["lastEvidenceFrame"] := Map(), s["translatedImage"] := "", s["chainSignature"] := ""
    s["comparisonLoaded"] := false
    s["ui"]["timeline"].Delete(), s["ui"]["thinking"].Value := "", s["ui"]["conversation"].Value := ""
    s["ui"]["caption"].Value := SubStr(StrReplace(task["prompt"],"`n"," "),1,220)
    s["ui"]["picture"].Visible := false, s["ui"]["controls"].Visible := false, s["ui"]["details"].Value := "Waiting for retained observations…"
}

NativeWB_Events() {
    s := g_NativeWB, u := s["ui"], previousCount := s["cards"].Length
    data := NativeWB_HTTP("/api/events?compact=1&limit=8&task=" . s["selected"] . "&after=" . s["cursor"])
    if data["task"]["id"]!=s["selected"]
        return
    s["task"] := data["task"], cards := Map()
    for card in data["cards"] {
        id := card["event_id"]
        if !cards.Has(id)
            cards[id] := []
        cards[id].Push(card)
    }
    for event in data["events"] {
        p := event["payload"], kind := event["kind"], name := p.Get("name",event["subject"])
        if kind="reasoning" {
            if s["round"]!=p.Get("round",0)
                s["thinking"] .= "`r`n`r`nRound " . p.Get("round",0) . " · provider thinking`r`n`r`n", s["round"] := p.Get("round",0)
            s["thinking"] .= p.Get("text","")
        } else if kind="agent_text"
            s["conversation"] .= p.Get("text","")
        else if kind="agent_answer" && s["conversation"]=""
            s["conversation"] := p.Get("text","")
        if kind="agent_tool_call" || kind="agent_tool_result" || kind="agent_error" || kind="vision_error" {
            detail := p
            if kind="agent_tool_call" {
                try detail := FanBridgeJsonDecode(p["arguments"])
                if detail is Map && detail.Has("source")
                    detail := detail.Clone(), detail["source"] := "Saved source: " . StrLen(detail["source"]) . " characters. Inspect it in Written .ahk files."
            } else if kind="agent_tool_result"
                detail := p.Get("result",Map())
            NativeWB_AddCard(Map("id",event["id"] . ":operation","event_id",event["id"],"at",event["at"],"kind",kind="agent_tool_call" ? "action" : "result","title",name . (kind="agent_tool_call" ? " · requested" : " · returned"),"tool",name,"source_kind","tool operation","data",detail))
        }
        if DateDiff(A_NowUTC,RegExReplace(SubStr(event["at"],1,19),"\D"),"Seconds")<8 {
            if kind="native_method" {
                s["recent"][p.Get("method","")] := A_TickCount, s["recent"][p.Get("family","")] := A_TickCount
                u["status"].Value := "Native method: " . p.Get("method","")
            }
            if kind="agent_tool_call" || kind="agent_tool_result"
                s["recent"][name] := A_TickCount
        }
        if cards.Has(event["id"])
            for card in cards[event["id"]]
                NativeWB_AddCard(card)
    }
    s["cursor"] := data["cursor"]
    NativeWB_Stream(u["thinking"],s["thinking"]), NativeWB_Stream(u["conversation"],s["conversation"])
    if u["follow"].Value && s["cards"].Length>previousCount && u["tabs"].Value=1 {
        count := s["cards"].Length
        if u["timeline"].GetNext()!=count {
            u["timeline"].Modify(count,"Select Vis Focus")
            NativeWB_ShowCard(s["cards"][count])
        }
    }
}

NativeWB_AddCard(card) {
    s := g_NativeWB
    if s["seen"].Has(card["id"])
        return
    frameId := card.Get("frame",Map()).Get("frame_id","")
    if frameId!="" && InStr("|image|controls|ocr|zones|findtext|","|" . card["kind"] . "|") {
        visualKey := "frame:" . frameId . ":" . card["kind"] . ":" . card.Get("image","")
        if s["seen"].Has(visualKey)
            return
        s["seen"][visualKey] := true
    }
    s["seen"][card["id"]] := true, s["cards"].Push(card)
    s["ui"]["timeline"].Add("",s["cards"].Length,card["kind"],card["title"],SubStr(card["at"],12,8))
}

NativeWB_Stream(control,text) {
    if control.Value=text
        return
    control.Value := text
    if g_NativeWB["ui"]["follow"].Value {
        length := SendMessage(0xE,0,0,control)
        SendMessage(0xB1,length,length,control), SendMessage(0xB7,0,0,control), SendMessage(0x115,7,0,control)
    }
}

NativeWB_SelectCard(lv,row,selected) {
    if selected && row<=g_NativeWB["cards"].Length {
        try NativeWB_ShowCard(g_NativeWB["cards"][row])
        catch as err
            g_NativeWB["ui"]["details"].Value := err.Message
    }
}

NativeWB_ShowCard(card) {
    s := g_NativeWB, u := s["ui"], d := card["data"], s["currentCard"] := card
    caption := card["title"] . " · " . card.Get("source_kind","observed") . " · evidence #" . card["event_id"]
    if card.Get("window","")!=""
        caption .= "`r`n" . card["window"]
    u["caption"].Value := caption, s["picture"] := ""
    u["controls"].Delete()
    if card["kind"]="controls" {
        for c in d.Get("controls",[]) {
            box := c.Get("bounds",Map())
            value := c.Get("protected",false) ? "[protected]" : c.Get("value","")
            u["controls"].Add("",c.Get("role",""),c.Get("name",""),value,NativeWB_Bounds(box))
        }
    }
    text := ""
    if card["kind"]="ocr" {
        text := "OBSERVED OCR · grouped after window zoning`r`n" . d.Get("grouping_note","") . "`r`n"
        for group in d.Get("groups",[])
            text .= "`r`n[" . group["id"] . "]`r`n" . group["text"] . "`r`n"
        if !d.Get("groups",[]).Length
            text .= "`r`n" . d.Get("text","No text recognized")
        text .= "`r`n`r`nWORD / LINE LOCATIONS · raw recognizer order retained in raw_text`r`n" . FanBridgeJsonEncode(d,2)
    }
    else if card["kind"]="comparison" {
        first := d.Get("first_pass",Map()), replay := d.Get("replay",Map()), source := d.Get("source",Map()), result := d.Get("verified_result",Map())
        a := first.Get("spending",Map()), b := replay.Get("spending",Map()), prep := d.Get("preparation_including_stopped_attempts",Map())
        text := "REAL VS CODE · FIRST PASS AND SAVED REPLAY`r`n`r`n"
            . "Reviewed baseline pass: " . first.Get("api_requests",0) . " API requests · " . Format("${:.6f}–${:.6f}",a.Get("usd_low",0),a.Get("usd_high",0)) . " estimated recorded cost`r`n"
            . "Saved replay: " . replay.Get("api_requests",0) . " API requests · " . Format("${:.6f}–${:.6f}",b.Get("usd_low",0),b.Get("usd_high",0)) . " estimated recorded cost`r`n"
            . "Requests avoided versus that baseline: " . d.Get("api_requests_avoided_vs_baseline",0) . "`r`n`r`n"
            . "Preparation including stopped attempts: " . prep.Get("api_requests",0) . " API requests · " . Format("${:.6f}–${:.6f}",prep.Get("usd_low",0),prep.Get("usd_high",0)) . " recorded estimate · " . prep.Get("unpriced_or_missing_usage",0) . " requests with unknown cost`r`n`r`n"
            . "REUSED TOOL`r`n" . source.Get("name","") . " · revision " . source.Get("revision","") . "`r`nSource unchanged: " . (source.Get("unchanged",false) ? "YES" : "not established") . "`r`nSHA-256: " . source.Get("sha256","")
            . "`r`n`r`nVERIFIED RESULT`r`n" . result.Get("marker","") . " · answer " . result.Get("answer","") . " · execution count " . result.Get("run_count","")
            . "`r`n`r`n" . d.Get("comparison_limit","") . "`r`n`r`nFULL PROVENANCE / REUSE DECISIONS`r`n" . FanBridgeJsonEncode(d,2)
    }
    else if card["kind"]="interpretation"
        text := "MODEL INTERPRETATION · verify against observed controls/pixels`r`n`r`n" . d.Get("text",FanBridgeJsonEncode(d,2))
    else if card["kind"]="findtext" {
        text := "OBSERVED FINDTEXT RESULT`r`n" . d.Get("total_matches","") . " matches`r`n`r`n" . FanBridgeJsonEncode(d,2)
        translation := d.Get("translation",Map())
        if translation.Get("bits","")!=""
            s["picture"] := NativeWB_Binary(translation,card["event_id"])
    } else
        text := FanBridgeJsonEncode(d,2)
    if card.Get("frame",Map()).Count
        text .= "`r`n`r`nWINDOW / GEOMETRY / CAPTURE CONTEXT`r`n" . FanBridgeJsonEncode(card["frame"],2)
    u["details"].Value := text
    if card.Get("image","")!="" {
        folder := s["root"] . "\.runtime\captures\workbench"
        DirCreate(folder), path := folder . "\event-" . card["event_id"] . "-" . card["image"] . ".png"
        try {
            if !FileExist(path)
                NativeWB_HTTP("/api/image?event=" . card["event_id"] . "&variant=" . card["image"],unset,path)
            s["picture"] := path
        } catch as err
            u["details"].Value := "Image was not retained: " . err.Message . "`r`n`r`n" . text
    }
    if s["picture"]!="" && FileExist(s["picture"]) && (card.Get("image","")!="annotated" || s.Get("lastEvidenceImage","")="")
        s["lastEvidenceImage"] := s["picture"], s["lastEvidenceFrame"] := card.Get("frame",Map())
    s["gui"].GetClientPos(,,&w,&h)
    NativeWB_Resize(s["gui"],0,w,h)
}

NativeWB_Bounds(box) => "x " . box.Get("x","") . ", y " . box.Get("y","") . " · " . box.Get("w","") . " × " . box.Get("h","")

NativeWB_Binary(data,identity) {
    w := data["width"], h := data["height"], bits := data["bits"]
    if w<1 || h<1 || w*h>1200000
        return ""
    pixels := Buffer(w*h*4,255)
    loop Min(StrLen(bits),w*h)
        NumPut("UInt",SubStr(bits,A_Index,1)="1" ? 0xFF000000 : 0xFFFFFFFF,pixels,(A_Index-1)*4)
    token := Gdip_Startup(), bitmap := 0
    folder := g_NativeWB["root"] . "\.runtime\captures\workbench"
    DirCreate(folder), path := folder . "\binary-" . identity . ".png"
    try {
        if DllCall("gdiplus\GdipCreateBitmapFromScan0","Int",w,"Int",h,"Int",w*4,"Int",0x26200A,"Ptr",pixels,"Ptr*",&bitmap)=0
            Gdip_SaveBitmapToFile(bitmap,path)
    } finally {
        if bitmap
            Gdip_DisposeImage(bitmap)
        Gdip_Shutdown(token)
    }
    return FileExist(path) ? path : ""
}

NativeWB_Tools(append := false,*) {
    s := g_NativeWB, u := s["ui"], mode := u["category"].Value
    kind := mode=1 ? "tools" : mode=2 ? "scripts" : mode=3 ? "methods" : "artifacts"
    data := NativeWB_HTTP("/api/tooling?kind=" . kind . "&query=" . NativeWB_Encode(u["toolQuery"].Value) . "&offset=" . (append ? s["toolRows"].Length : 0))
    rows := append ? s["toolRows"].Clone() : []
    for row in data["rows"]
        rows.Push(row)
    NativeWB_RenderTools(rows)
    u["toolHeading"].Value := rows.Length . " / " . data["total"] . " entries · active / recent"
    u["moreTools"].Enabled := data["has_more"]
}

NativeWB_RenderTools(list) {
    s := g_NativeWB, u := s["ui"], mode := u["category"].Value, query := StrLower(u["toolQuery"].Value)
    previous := u["tools"].GetNext(), previousName := previous && previous<=s["toolRows"].Length ? s["toolRows"][previous]["name"] : ""
    s["toolRows"] := [], u["tools"].Opt("-Redraw"), u["tools"].Delete()
    for item in list {
        if mode=2 && item.Get("kind","")!="script" || mode=4 && item.Get("kind","")="script"
            continue
        if query!="" && !InStr(StrLower(item["name"] . " " . item.Get("path","") . " " . item.Get("family","") . " " . item.Get("description","")),query)
            continue
        s["toolRows"].Push(item)
        row := u["tools"].Add("",item["name"],"")
        if item["name"]=previousName
            u["tools"].Modify(row,"Select")
    }
    u["tools"].Opt("+Redraw"), NativeWB_Highlight()
    u["toolHeading"].Value := s["toolRows"].Length . " entries · active / recent"
}

NativeWB_Highlight() {
    s := g_NativeWB, colors := Map()
    for row,item in s["toolRows"] {
        name := item["name"], active := s["active"].Has(name), recent := A_TickCount-s["recent"].Get(name,s["recent"].Get(item.Get("family",""),-100000))<5000
        for method,tick in s["recent"]
            if A_TickCount-tick<5000 && RegExReplace(method,"^.*\.","")=name
                recent := true
        state := active ? "ACTIVE" : recent ? "recent" : item.Get("kind","")="script" ? "r" . item["revision"] : ""
        if s["ui"]["tools"].GetText(row,2)!=state
            s["ui"]["tools"].Modify(row,"Col2",state)
        if active || recent
            colors[row-1] := active ? 0xDDF2DA : 0xCBEAFF
    }
    s["colors"] := colors
    DllCall("InvalidateRect","Ptr",s["ui"]["tools"].Hwnd,"Ptr",0,"Int",false)
}

NativeWB_ToolDraw(control,lParam) {
    stage := NumGet(lParam,A_PtrSize=8 ? 24 : 12,"UInt")
    if stage=1
        return 0x20
    if stage=0x10001 {
        row := NumGet(lParam,A_PtrSize=8 ? 56 : 36,"UPtr")
        if g_NativeWB["colors"].Has(row) {
            NumPut("UInt",0x202020,lParam,A_PtrSize=8 ? 80 : 48)
            NumPut("UInt",g_NativeWB["colors"][row],lParam,A_PtrSize=8 ? 84 : 52)
        }
        return 0
    }
}

NativeWB_Source(*) {
    s := g_NativeWB, row := s["ui"]["tools"].GetNext()
    if !row || row>s["toolRows"].Length
        return
    item := s["toolRows"][row]
    try {
        if item.Has("kind") {
            record := NativeWB_HTTP("/api/artifact?name=" . NativeWB_Encode(item["name"]))
            text := record["kind"] . " · revision " . record["revision"] . "`r`n" . record.Get("metadata",Map()).Get("path","")
                . "`r`nSHA-256 " . record.Get("metadata",Map()).Get("sha256","")
                . "`r`n`r`nUSAGE`r`n" . record.Get("usage","") . "`r`n`r`nSOURCE`r`n" . record["content"]
                . "`r`n`r`nINPUT SCHEMA / METADATA`r`n" . FanBridgeJsonEncode(record.Get("metadata",Map()),2)
        } else if item.Has("signature") {
            record := NativeWB_HTTP("/api/method?path=" . NativeWB_Encode(item["path"]) . "&line=" . item["line"])
            text := item["path"] . ":" . item["line"] . "`r`n`r`n" . record["source"]
        } else {
            tool := NativeWB_HTTP("/api/tool?name=" . NativeWB_Encode(item["name"]))
            text := tool["description"] . "`r`n`r`n" . FanBridgeJsonEncode(tool["parameters"],2)
        }
        NativeWB_TextWindow(item["name"],text,true)
    } catch as err
        s["ui"]["status"].Value := err.Message
}

NativeWB_Discoveries(*) {
    s := g_NativeWB, u := s["ui"]
    try {
        data := NativeWB_HTTP("/api/discoveries?compact=1&query=" . NativeWB_Encode(u["discoveryQuery"].Value))
        previous := u["discoveries"].GetNext(), s["discoveryRows"] := []
        u["discoveries"].Opt("-Redraw"), u["discoveries"].Delete()
        for claim in data.Get("claims",[]) {
            claim["_kind"] := "claim", s["discoveryRows"].Push(claim)
            u["discoveries"].Add("","Claim " . claim["id"] . " · " . claim["source"],claim["claim"],claim["passes"] . " / " . claim["failures"] . " eligible")
        }
        for record in data.Get("discoveries",[]) {
            record["_kind"] := "note", s["discoveryRows"].Push(record)
            u["discoveries"].Add("",record.Get("metadata",Map()).Get("source_kind","reference"),record["description"],record["name"])
        }
        u["discoveries"].Opt("+Redraw"), s["lastDiscoveries"] := A_TickCount
        if previous && previous<=s["discoveryRows"].Length
            u["discoveries"].Modify(previous,"Select")
    } catch as err
        u["status"].Value := err.Message
}

NativeWB_SelectDiscovery(lv,row,selected) {
    if !selected || row>g_NativeWB["discoveryRows"].Length
        return
    record := g_NativeWB["discoveryRows"][row], text := ""
    try {
        if record["_kind"]="claim" {
            values := NativeWB_HTTP("/api/claim?id=" . record["id"]), item := values[1]
            text := "CLAIM " . record["id"] . " · " . record["source"] . "`r`n" . record["claim"] . "`r`n`r`nHOW TO USE IT`r`n" . record.Get("use_text","")
                . "`r`n`r`n" . record["observations"] . " observations; " . record["passes"] . " eligible support / " . record["failures"] . " contradictions. Support is scoped to the recorded context."
            if item.Has("lesson") {
                text .= "`r`n`r`nSTORED LESSON`r`n"
                for step in item["lesson"]["steps"]
                    text .= "`r`n" . step.Get("layer","Step") . "`r`n" . step.Get("text",FanBridgeJsonEncode(step)) . "`r`n"
            }
            text .= "`r`nSUPPORTING EVIDENCE · rehearsals do not validate original-app behavior`r`n"
            for e in item.Get("evidence",[])
                text .= "`r`n" . e.Get("ts","") . " · " . e["outcome"] . " · " . (e["eligible"] ? "eligible" : "reference / rehearsal") . "`r`n" . e.Get("detail","") . "`r`nContext: " . e.Get("context","") . "`r`nProvenance: " . e.Get("provenance","") . "`r`n"
        } else {
            text := record["description"] . "`r`n" . record["name"] . " · " . record.Get("metadata",Map()).Get("source_kind","reference") . "`r`n`r`n"
            content := record.Has("content") ? record["content"] : NativeWB_HTTP("/api/artifact?name=" . NativeWB_Encode(record["name"]))["content"]
            try content := FanBridgeJsonEncode(FanBridgeJsonDecode(content),2)
            text .= content
        }
        g_NativeWB["ui"]["evidence"].Value := text
    } catch as err
        g_NativeWB["ui"]["evidence"].Value := err.Message
}

NativeWB_Lesson(*) {
    s := g_NativeWB, row := s["ui"]["discoveries"].GetNext()
    if row && row<=s["discoveryRows"].Length && s["discoveryRows"][row]["_kind"]="claim"
        NativeWB_Invoke("LearningLab_Present",Map("claim_id",s["discoveryRows"][row]["id"]))
}

NativeWB_Stop(*) {
    if g_NativeWB["selected"]!=""
        try NativeWB_HTTP("/api/cancel",Map("task",g_NativeWB["selected"]))
}

NativeWB_CopyLog(*) {
    s := g_NativeWB
    if s["selected"]=""
        return
    try {
        A_Clipboard := NativeWB_HTTP("/api/report?task=" . s["selected"],,,true)
        s["ui"]["status"].Value := "Analysis log copied. Includes task, chronological evidence, errors and reuse estimates. Review paths/titles before pasting into another LLM."
    } catch as err
        s["ui"]["status"].Value := err.Message
}

NativeWB_Stats(*) {
    s := g_NativeWB, u := s["ui"]
    try {
        data := NativeWB_HTTP("/api/knowledge-stats?task=" . s["selected"] . "&query=" . NativeWB_Encode(u["statsQuery"].Value))
        wanted := s.Get("windowId",s.Get("initialWindow","")), chosen := 0, s["statsRendering"] := true
        s["windowRows"] := data["windows"], u["statsRows"].Opt("-Redraw"), u["statsRows"].Delete()
        for index,item in s["windowRows"] {
            if item["id"]=wanted
                chosen := index
            facts := 0
            for kind,count in item["counts"]
                facts += count
            u["statsRows"].Add("",item["title"] . " · " . item["app"],facts,item["reused"] . " / " . item["fresh"],item["estimated_saved"])
        }
        if !chosen && s["windowRows"].Length
            chosen := 1
        if chosen
            u["statsRows"].Modify(chosen,"Select")
        u["statsRows"].Opt("+Redraw"), s["statsRendering"] := false
        projects := data["projects"], paths := 0
        for kind,count in projects["counts"]
            paths += count
        u["statsSummary"].Value := s["windowRows"].Length . " matching window maps · " . data["uses"] . " recorded uses · ~" . data["estimated_saved"] . " text tokens saved (estimate)"
            . "`r`n75% eligible reuse / 25% fresh; changed/new/aged → fresh."
            . "`r`nDesktop: " . paths . " indexed paths · " . (projects["scan"].Get("complete",0) ? "scan complete" : "indexing incrementally")
        u["statsCost"].Value := NativeWB_CostLine(data)
        s["lastStats"] := A_TickCount
        if chosen && s.Get("windowId","")!=s["windowRows"][chosen]["id"]
            NativeWB_SelectWindow(u["statsRows"],chosen,true)
        else if !chosen
            s["windowId"] := "", u["statsDetails"].Value := "No matching window maps."
    } catch as err
        u["statsSummary"].Value := err.Message
    finally s["statsRendering"] := false
}

NativeWB_CostLine(data) {
    all := data.Get("spending",Map()), run := data.Get("run_spending",Map())
    return "Est. USD: all " . Format("${:.6f}–${:.6f}",all.Get("usd_low",0),all.Get("usd_high",0))
        . " · run " . Format("${:.6f}–${:.6f}",run.Get("usd_low",0),run.Get("usd_high",0))
        . " · unknown usage: " . all.Get("unpriced_or_missing_usage",0)
}

NativeWB_SelectWindow(lv,row,selected) {
    s := g_NativeWB
    if selected && !s.Get("statsRendering",false) && row<=s.Get("windowRows",[]).Length {
        s["windowId"] := s["windowRows"][row]["id"], s["factOffset"] := 0
        NativeWB_WindowFacts()
    }
}

NativeWB_WindowFacts(more := false) {
    s := g_NativeWB
    if !s.Get("windowId","")
        return
    if more
        s["factOffset"] := s.Get("factMore",false) ? s["factOffset"]+40 : 0
    try {
        data := NativeWB_HTTP("/api/window-knowledge?id=" . s["windowId"] . "&offset=" . s["factOffset"])
        text := data["window"]["title"] . " · " . data["window"]["app"] . "`r`n" . data["relations"] . "`r`n" . data["warning"]
            . "`r`nFacts " . (s["factOffset"]+1) . "–" . Min(data["total"],s["factOffset"]+40) . " of " . data["total"] . "`r`n"
        for fact in data["facts"]
            text .= "`r`n[" . fact["kind"] . "] " . fact["label"] . "`r`nParent: " . fact["parent"] . " · Zone: " . fact["zone"] . " · Observations: " . fact["observations"]
                . "`r`n" . FanBridgeJsonEncode(fact["data"],2) . "`r`n"
        s["factMore"] := data["has_more"], s["ui"]["statsDetails"].Value := text
    } catch as err
        s["ui"]["statsDetails"].Value := err.Message
}

NativeWB_ProjectPaths(*) {
    s := g_NativeWB
    try {
        data := NativeWB_HTTP("/api/project-paths?query=" . NativeWB_Encode(s["ui"]["pathQuery"].Value)), text := data["note"] . "`r`n"
        for item in data["paths"]
            text .= "`r`n[" . item["kind"] . "] " . item["path"] . "`r`nMarker: " . item["marker"] . " · Observed: " . item["last_seen"] . "`r`n"
        s["ui"]["statsDetails"].Value := text
    } catch as err
        s["ui"]["statsDetails"].Value := err.Message
}

NativeWB_Tab() {
    s := g_NativeWB
    s["gui"].GetClientPos(,,&w,&h), NativeWB_Resize(s["gui"],0,w,h)
    if s["ui"]["tabs"].Value=4
        SetTimer(NativeWB_Discoveries,-30)
    if s["ui"]["tabs"].Value=5
        SetTimer(NativeWB_Stats,-30)
    if s["ui"]["tabs"].Value=6
        SetTimer((*)=>NativeDAA_Safe(NativeDAA_Refresh),-30)
    if s["ui"]["tabs"].Value=7
        SetTimer((*)=>NativeDAA_Safe(NativeDAA_Explorer),-30)
}

NativeWB_Resize(g,state,w,h) {
    if state=-1
        return
    u := g_NativeWB["ui"], right := w-330, cw := Max(460,w-590), bottom := h-55
    u["status"].Move(,,w-24), u["runs"].Move(12,106,220,h-178), u["older"].Move(12,h-60,220)
    for index,name in ["bridge","stored","web","stop","pause"]
        u[name].Move(w-625+(index-1)*125,8,118)
    u["tabs"].Move(244,108,cw,h-143)
    u["timeline"].Move(256,144,cw-24,172), u["timeline"].ModifyCol(3,Max(160,cw-290))
    u["caption"].Move(256,324,cw-24,42)
    u["thinking"].Move(256,146,cw-24,h-200), u["conversation"].Move(256,146,cw-24,h-200)
    u["discoveryQuery"].Move(256,145,Max(160,cw-265)), u["lesson"].Move(256+cw-255,145,230)
    u["discoveries"].Move(256,181,cw-24,170), u["discoveries"].ModifyCol(2,Max(160,cw-320))
    u["evidence"].Move(256,360,cw-24,Max(100,h-415))
    u["statsQuery"].Move(256,145,cw-24), u["statsSummary"].Move(256,178,cw-24,72), u["statsCost"].Move(256,252,cw-24,48)
    u["statsRows"].Move(256,310,cw-24,150)
    for col,width in [Max(150,cw-410),70,115,185]
        u["statsRows"].ModifyCol(col,width)
    u["statsMore"].Move(256,466,190), u["pathQuery"].Move(456,466,Max(170,cw-224))
    u["statsDetails"].Move(256,504,cw-24,Max(100,h-559))
    u["toolHeading"].Move(right,78,310), u["category"].Move(right,109,310), u["toolQuery"].Move(right,142,310)
    u["tools"].Move(right,176,310,Max(120,h-350)), u["moreTools"].Move(right,h-162,310), u["source"].Move(right,h-126,310), u["toolNote"].Move(right,h-91,310,64)
    u["runDot"].Move(12,h-28,20), u["footer"].Move(36,h-47,w-48,44)
    NativeDAA_Resize(u,cw,h)
    canvas := u["tabs"].Value=1, card := g_NativeWB.Get("currentCard",Map()), controls := canvas && card.Get("kind","")="controls"
    u["controls"].Move(256,370,cw-24,Max(100,h-425)), u["controls"].Visible := controls
    hasPicture := canvas && g_NativeWB["picture"]!="" && !controls
    u["picture"].Visible := hasPicture, u["details"].Visible := canvas && !controls
    if hasPicture {
        pw := Min(340,(cw-40)//2), ph := Max(100,h-425)
        u["picture"].Move(256,370,pw,ph)
        try NativeWB_FitPicture(u["picture"],g_NativeWB["picture"],pw,ph)
        u["details"].Move(268+pw,370,cw-pw-36,ph)
    } else
        u["details"].Move(256,370,cw-24,Max(100,h-425))
}

NativeWB_FitPicture(control,path,maxW,maxH) {
    token := Gdip_Startup(), bitmap := 0, width := 0, height := 0
    try {
        if DllCall("gdiplus\GdipCreateBitmapFromFile","WStr",path,"Ptr*",&bitmap)
            throw Error("Could not load retained image")
        DllCall("gdiplus\GdipGetImageWidth","Ptr",bitmap,"UInt*",&width)
        DllCall("gdiplus\GdipGetImageHeight","Ptr",bitmap,"UInt*",&height)
        scale := Min(maxW/Max(1,width),maxH/Max(1,height))
        control.Value := "*w" . Max(1,Floor(width*scale)) . " *h" . Max(1,Floor(height*scale)) . " " . path
    } finally {
        if bitmap
            Gdip_DisposeImage(bitmap)
        Gdip_Shutdown(token)
    }
}

NativeWB_TextWindow(title,text,code := false) {
    g := Gui("+Resize +MinSize600x400 -DPIScale",title . " — Workbench")
    g.SetFont(code ? "s10" : "s10",code ? "Consolas" : "Segoe UI")
    edit := g.Add("Edit","x12 y12 w880 h600 ReadOnly Multi +VScroll +HScroll",text)
    g.OnEvent("Size",(gui,state,w,h)=>state!=-1 ? edit.Move(12,12,w-24,h-24) : 0)
    g.OnEvent("Close",(*)=>g.Destroy()), g.OnEvent("Escape",(*)=>g.Destroy())
    g.Show("w910 h640")
}

NativeWB_ImageWindow() {
    if g_NativeWB["picture"]=""
        return
    g := Gui("+Resize -DPIScale","Retained observation — Workbench")
    monitor := MonitorGetPrimary()
    try {
        choose := "LearningValidation_Monitor"
        if second := %choose%()
            monitor := second
    }
    MonitorGetWorkArea(monitor,&l,&t,&r,&b)
    width := Min(1050,r-l-60), height := Min(900,b-t-90)
    picture := g.Add("Picture","x12 y12 w" . width . " h" . height)
    NativeWB_FitPicture(picture,g_NativeWB["picture"],width,height)
    g.OnEvent("Close",(*)=>g.Destroy()), g.OnEvent("Escape",(*)=>g.Destroy())
    try {
        place := "SecondaryWindows_Place"
        %place%(g,"x" . (l+20) . " y" . (t+20) . " w" . (width+24) . " h" . (height+24))
    } catch
        g.Show("w" . (width+24) . " h" . (height+24))
}

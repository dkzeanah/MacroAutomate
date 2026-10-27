; Native execution map / local image translations. No browser or desktop input.
#Include DaaGraphics.ahk
NativeDAA_Build(g,u) {
    u["tabs"].UseTab(6)
    u["chainSummary"] := g.Add("Text","x256 y145 w805 h48","DAA chains: numbered attempts, callers, branches and checked outcomes")
    u["chainCue"] := g.Add("Edit","x256 y197 w805 h48 ReadOnly Multi +VScroll","Narration cues appear here. You control OBS separately.")
    u["chainBudget"] := g.Add("Edit","x256 y251 w70 h30 Number","512")
    u["chainApply"] := g.Add("Button","x336 y251 w180 h30","Set maximum")
    u["chainApply"].OnEvent("Click",NativeDAA_Budget)
    u["cueNext"] := g.Add("Button","x526 y251 w150 h30","Continue tour")
    u["cueNext"].OnEvent("Click",(*)=>NativeWB_HTTP("/api/tour-next",Map("task",g_NativeWB["selected"])))
    u["chainNote"] := g.Add("Text","x650 y243 w410 h24","Red: requested input · blue: live cursor")
    u["chainTree"] := g.Add("TreeView","x256 y277 w310 h220")
    u["chainTree"].OnEvent("ItemSelect",NativeDAA_Select)
    u["mini"] := g.Add("Picture","x580 y277 w480 h168")
    u["miniNote"] := g.Add("Text","x580 y449 w480 h40","Live virtual desktop + retained input trail. Historical markers do not certify current targets.")
    u["chainDetails"] := g.Add("Edit","x256 y505 w310 h247 ReadOnly Multi +VScroll +Wrap")
    u["rawSnippet"] := g.Add("Picture","x580 y505 w150 h100")
    u["ascii"] := g.Add("Edit","x740 y505 w320 h153 ReadOnly Multi -Wrap +HScroll +VScroll","ASCII preview appears after an observed image.")
    u["ascii"].SetFont("s7","Consolas")
    u["encoding"] := g.Add("Edit","x580 y666 w480 h86 ReadOnly Multi +VScroll +Wrap","Base64 prefix of the retained image crop; full pixels remain local.")
    u["encoding"].SetFont("s8","Consolas")
    u["tabs"].UseTab(7)
    u["explorerQuery"] := g.Add("Edit","x256 y145 w805 h27")
    SendMessage(0x1501,true,StrPtr("Filter locally observed Explorer paths…"),u["explorerQuery"])
    u["explorerQuery"].OnEvent("Change",(*)=>SetTimer((*)=>NativeDAA_Safe(NativeDAA_Explorer),-300))
    u["explorerNote"] := g.Add("Text","x256 y181 w805 h70","Local folder dwell and visits; selected files are references, not measured editing time.")
    u["explorerRows"] := g.Add("ListView","x256 y260 w805 h490 -Multi",["Observed path","Active seconds","Visits","Samples","Kind"])
    for col,width in [390,110,70,70,140]
        u["explorerRows"].ModifyCol(col,width)
}

NativeDAA_Safe(callback) {
    try callback.Call()
    catch as err
        g_NativeWB["ui"]["status"].Value := "DAA view · " . err.Message
}

NativeDAA_Refresh(*) {
    s := g_NativeWB, u := s["ui"]
    if s["selected"]=""
        return
    data := NativeWB_HTTP("/api/chain?task=" . s["selected"] . "&limit=500"), chain := data["chain"]
    NativeDAA_State(data)
    s["chainSteps"] := data["steps"], s["chainByTree"] := Map()
    signature := ""
    for step in data["steps"]
        signature .= step["id"] . step["status"] . "|"
    if signature!=s.Get("chainSignature","") {
        s["chainSignature"] := signature, u["chainTree"].Opt("-Redraw"), u["chainTree"].Delete(), nodes := Map()
        for step in data["steps"] {
            parent := nodes.Get(step["parent_id"],0)
            label := "#" . step["number"] . " " . step["origin"] . " → " . step["tool"] . " · " . step["status"]
            if step["branch"]!=""
                label .= " [" . step["branch"] . "]"
            node := u["chainTree"].Add(label,parent,"Expand")
            nodes[step["id"]] := node, s["chainByTree"][node] := step
        }
        u["chainTree"].Opt("+Redraw")
        if data["steps"].Length && s.Get("chainByTree",Map()).Count
            u["chainTree"].Modify(node,"Select Vis")
    }
    cost := data.Get("spending",Map())
    taskState := data.Get("control",Map()).Get("task_status",s["task"].Get("status","waiting"))
    u["chainSummary"].Value := "Chain " . SubStr(s["selected"],1,12) . " · " . chain.Get("step_count",0) . " / " . chain.Get("max_steps",512) . " attempted interactions · " . taskState
        . "`r`nProvider calls " . data.Get("provider_requests",0) . " · recorded estimate " . Format("${:.6f}",cost.Get("usd_high",0)) . " · unknown usage " . cost.Get("unpriced_or_missing_usage",0) . " · est. text tokens saved " . data.Get("estimated_saved",0)
    cue := data.Get("cue",Map())
    u["chainCue"].Value := cue.Get("text","No narration cue for this run.")
    u["cueNext"].Enabled := cue.Get("status","")="waiting"
    if s["task"].Get("status","")="complete" && !s.Get("comparisonLoaded",false)
        try {
            record := NativeWB_HTTP("/api/artifact?name=knowledge%3ADAALatestReplayEvidence")
            comparison := FanBridgeJsonDecode(record["content"])
            if comparison.Get("task_id","")=s["selected"]
                s["demoComparison"] := comparison, s["comparisonLoaded"] := true
        }
    if s.Get("comparisonLoaded",false)
        u["chainCue"].Value := NativeDAA_Comparison(s["demoComparison"])
    if !data["steps"].Length
        u["chainDetails"].Value := "Numbering begins at the first automation tool. Planning/provider activity is counted separately above. The chain tree and image translations fill as actual results arrive."
    if u["tabs"].Value!=6
        return
    NativeDAA_Mini(data["steps"])
    latest := data.Get("latest_image",Map())
    if latest.Get("event",0) && latest["event"]!=s.Get("chainImageEvent",0) {
        folder := s["root"] . "\.runtime\captures\workbench", DirCreate(folder)
        path := folder . "\daa-evidence-" . latest["event"] . ".png"
        NativeWB_HTTP("/api/image?event=" . latest["event"] . "&variant=image",unset,path)
        s["lastEvidenceImage"] := path, s["lastEvidenceFrame"] := latest["frame"], s["chainImageEvent"] := latest["event"]
    }
    image := s.Get("lastEvidenceImage","")
    if image!="" && FileExist(image) && image!=s.Get("translatedImage","") {
        snippet := NativeDAA_Snippet(image,s.Get("lastEvidenceFrame",Map()),data["steps"])
        NativeDAA_Translate(snippet), s["translatedImage"] := image
        try NativeWB_FitPicture(u["rawSnippet"],snippet,150,100)
    }
}

NativeDAA_State(data) {
    s := g_NativeWB, u := s["ui"], paused := data.Get("control",Map()).Get("paused",false)
    s["paused"] := paused
    running := data.Get("control",Map()).Get("task_status",s["task"].Get("status",""))="running", chain := data.Get("chain",Map())
    color := paused ? "D99500" : s.Get("automationActive",false) || running && chain.Get("step_count",0)>0 ? "FF2020" : "808080"
    u["runDot"].SetFont("c" . color)
    u["pause"].Text := paused ? "Resume" : "Pause", u["pause"].Enabled := running
    sub := data.Get("current_subtask",Map()), action := data.Get("current_action",Map()), cue := data.Get("cue",Map())
    doing := "Planning / waiting for first tool"
    for step in data.Get("steps",[])
        doing := "#" . step["number"] . " " . step["tool"] . " · " . step["status"]
    if action.Get("label","")!=""
        doing .= " · " . SubStr(action["label"],1,90)
    need := paused ? "Resume to continue at an instrumented boundary" : cue.Get("status","")="waiting" ? "Narrate, then Continue tour" : running ? "Await next checked result" : "Review retained evidence / start a task"
    goal := SubStr(StrReplace(s["task"].Get("prompt","No task selected"),"`n"," "),1,110)
    subtask := SubStr(sub.Get("branch",sub.Get("step","No saved-unit subtask reported")),1,45)
    u["footer"].Value := "Goal: " . goal . " · Subtask: " . subtask . "`r`n" . (paused ? "PAUSED · " : "Doing: ") . doing . " · Needs: " . need
}

NativeDAA_Pause(*) {
    s := g_NativeWB
    try {
        NativeWB_HTTP("/api/pause",Map("task",s["selected"],"paused",!s.Get("paused",false)))
        NativeDAA_Refresh()
    } catch as err
        s["ui"]["status"].Value := "Pause / Resume · " . err.Message
}

NativeDAA_Comparison(data) {
    first := data.Get("first_tour",Map()), replay := data.Get("local_replay",Map())
    a := first.Get("spending",Map()), b := replay.Get("spending",Map())
    return "VERIFIED REPLAY · " . data.Get("target","") . " · pinned source revisions unchanged`r`n"
        . "Provider requests " . first.Get("provider_requests",0) . " → " . replay.Get("provider_requests",0)
        . " · difference versus this baseline " . data.Get("provider_calls_avoided_vs_this_baseline",0)
        . " · recorded estimates " . Format("${:.6f} → ${:.6f}",a.Get("usd_high",0),b.Get("usd_high",0))
        . "`r`n" . data.Get("limits","")
}

NativeDAA_Snippet(path,frame,steps) {
    token := Gdip_Startup(), bitmap := 0, crop := 0
    try {
        if DllCall("gdiplus\GdipCreateBitmapFromFile","WStr",path,"Ptr*",&bitmap)
            return path
        w := 0, h := 0
        DllCall("gdiplus\GdipGetImageWidth","Ptr",bitmap,"UInt*",&w)
        DllCall("gdiplus\GdipGetImageHeight","Ptr",bitmap,"UInt*",&h)
        cx := w//2, cy := h//2, region := frame.Get("region",Map())
        if region.Get("w",0)>0 && region.Get("h",0)>0
            for step in steps {
                point := step["arguments"]
                if point.Has("x") && point.Has("y") {
                    px := (point["x"]-region["x"])*w/region["w"], py := (point["y"]-region["y"])*h/region["h"]
                    if px>=0 && px<w && py>=0 && py<h
                        cx := Round(px), cy := Round(py)
                }
            }
        cw := Min(180,w), ch := Min(110,h), x := Max(0,Min(w-cw,cx-cw//2)), y := Max(0,Min(h-ch,cy-ch//2))
        if DllCall("gdiplus\GdipCloneBitmapAreaI","Int",x,"Int",y,"Int",cw,"Int",ch,"Int",0x26200A,"Ptr",bitmap,"Ptr*",&crop)
            return path
        target := g_NativeWB["root"] . "\.runtime\captures\workbench\daa-snippet.png"
        if Gdip_SaveBitmapToFile(crop,target)
            return path
        return target
    } finally {
        if crop
            Gdip_DisposeImage(crop)
        if bitmap
            Gdip_DisposeImage(bitmap)
        Gdip_Shutdown(token)
    }
}

NativeDAA_Select(tv,item) {
    s := g_NativeWB
    if s.Get("chainByTree",Map()).Has(item)
        s["ui"]["chainDetails"].Value := FanBridgeJsonEncode(s["chainByTree"][item],2)
}

NativeDAA_Budget(*) {
    s := g_NativeWB
    try {
        value := Integer(s["ui"]["chainBudget"].Value)
        NativeWB_HTTP("/api/chain-budget",Map("task",s["selected"],"max_steps",value))
        NativeDAA_Refresh()
    } catch as err
        s["ui"]["chainDetails"].Value := err.Message
}

NativeDAA_Explorer(*) {
    u := g_NativeWB["ui"], data := NativeWB_HTTP("/api/explorer-usage?query=" . NativeWB_Encode(u["explorerQuery"].Value))
    u["explorerNote"].Value := data["note"], u["explorerRows"].Delete()
    for row in data["paths"]
        u["explorerRows"].Add("",row["path"],Round(row["active_ms"]/1000,1),row["visits"],row["observations"],row["kind"])
}

NativeDAA_Mini(steps) {
    s := g_NativeWB, u := s["ui"], token := Gdip_Startup(), raw := 0, small := 0, graphics := 0, pen := 0
    x := SysGet(76), y := SysGet(77), w := SysGet(78), h := SysGet(79)
    if w<1 || h<1 || w*h>40000000
        return
    try {
        u["mini"].GetPos(,,&maxW,&maxH), scale := Min(maxW/w,maxH/h)
        sw := Max(1,Round(w*scale)), sh := Max(1,Round(h*scale))
        raw := Gdip_BitmapFromScreen(x . "|" . y . "|" . w . "|" . h)
        small := DaaGdip_CreateBitmap(sw,sh), graphics := DaaGdip_GraphicsFromImage(small)
        DaaGdip_DrawImage(graphics,raw,0,0,sw,sh,0,0,w,h), pen := DaaGdip_CreatePen(0xFFFF3535,2)
        previous := 0
        for step in steps {
            args := step["arguments"]
            if !(args is Map) || !args.Has("x") || !args.Has("y")
                continue
            px := (args["x"]-x)*scale, py := (args["y"]-y)*scale
            if px<0 || py<0 || px>sw || py>sh
                continue
            if IsObject(previous)
                DaaGdip_DrawLine(graphics,pen,previous["x"],previous["y"],px,py)
            DaaGdip_DrawEllipse(graphics,pen,px-4,py-4,8,8)
            NativeDAA_Number(graphics,step["number"],px+5,py)
            previous := Map("x",px,"y",py)
        }
        cursor := Buffer(8)
        if DllCall("GetCursorPos","Ptr",cursor) {
            cx := (NumGet(cursor,0,"Int")-x)*scale, cy := (NumGet(cursor,4,"Int")-y)*scale
            blue := DaaGdip_CreatePen(0xFF22B9FF,2)
            DaaGdip_DrawEllipse(graphics,blue,cx-3,cy-3,6,6), DaaGdip_DeletePen(blue)
        }
        folder := s["root"] . "\.runtime\captures\workbench", DirCreate(folder)
        s["miniFrame"] := !s.Get("miniFrame",false)
        path := folder . "\daa-mini-" . (s["miniFrame"] ? "a" : "b") . ".png"
        if Gdip_SaveBitmapToFile(small,path)=0
            u["mini"].Value := path
        u["miniNote"].Value := "LIVE desktop origin " . x . "," . y . " · " . w . "×" . h . " · retained numbered input markers (not current targets)"
    } finally {
        if pen
            DaaGdip_DeletePen(pen)
        if graphics
            DaaGdip_DeleteGraphics(graphics)
        if small
            Gdip_DisposeImage(small)
        if raw
            Gdip_DisposeImage(raw)
        Gdip_Shutdown(token)
    }
}

NativeDAA_Number(graphics,text,x,y) {
    family := 0, font := 0, brush := 0, format := 0, rect := Buffer(16,0)
    try {
        DllCall("gdiplus\GdipCreateFontFamilyFromName","WStr","Segoe UI","Ptr",0,"Ptr*",&family)
        DllCall("gdiplus\GdipCreateFont","Ptr",family,"Float",9,"Int",1,"Int",2,"Ptr*",&font)
        DllCall("gdiplus\GdipCreateSolidFill","UInt",0xFFFF3535,"Ptr*",&brush)
        DllCall("gdiplus\GdipStringFormatGetGenericDefault","Ptr*",&format)
        NumPut("Float",x,"Float",y,"Float",44,"Float",15,rect)
        DllCall("gdiplus\GdipDrawString","Ptr",graphics,"WStr",text,"Int",-1,"Ptr",font,"Ptr",rect,"Ptr",format,"Ptr",brush)
    } finally {
        if format
            DllCall("gdiplus\GdipDeleteStringFormat","Ptr",format)
        if brush
            DllCall("gdiplus\GdipDeleteBrush","Ptr",brush)
        if font
            DllCall("gdiplus\GdipDeleteFont","Ptr",font)
        if family
            DllCall("gdiplus\GdipDeleteFontFamily","Ptr",family)
    }
}

NativeDAA_Translate(path) {
    u := g_NativeWB["ui"], token := Gdip_Startup(), bitmap := 0
    try {
        if DllCall("gdiplus\GdipCreateBitmapFromFile","WStr",path,"Ptr*",&bitmap)
            throw Error("Retained image not readable")
        w := 0, h := 0
        DllCall("gdiplus\GdipGetImageWidth","Ptr",bitmap,"UInt*",&w)
        DllCall("gdiplus\GdipGetImageHeight","Ptr",bitmap,"UInt*",&h)
        ascii := "ASCII luminance preview · retained image`r`n", ramp := "@%#*+=-:. "
        loop 20 {
            yy := Min(h-1,Floor((A_Index-.5)*h/20))
            loop 48 {
                xx := Min(w-1,Floor((A_Index-.5)*w/48)), pixel := 0
                DllCall("gdiplus\GdipBitmapGetPixel","Ptr",bitmap,"Int",xx,"Int",yy,"UInt*",&pixel)
                light := (77*((pixel>>16)&255)+150*((pixel>>8)&255)+29*(pixel&255))//256
                ascii .= SubStr(ramp,1+Min(9,light*10//256),1)
            }
            ascii .= "`r`n"
        }
        u["ascii"].Value := ascii
        raw := FileRead(path,"RAW"), bytes := Min(raw.Size,768), chars := 0
        DllCall("crypt32\CryptBinaryToStringW","Ptr",raw,"UInt",bytes,"UInt",0x40000001,"Ptr",0,"UInt*",&chars)
        output := Buffer(chars*2)
        DllCall("crypt32\CryptBinaryToStringW","Ptr",raw,"UInt",bytes,"UInt",0x40000001,"Ptr",output,"UInt*",&chars)
        u["encoding"].Value := "BASE64 PREFIX · " . raw.Size . " image bytes · " . w . "×" . h . "`r`n" . StrGet(output,"UTF-16") . "`r`n[bounded display; full image retained locally]"
    } finally {
        if bitmap
            Gdip_DisposeImage(bitmap)
        Gdip_Shutdown(token)
    }
}

NativeDAA_Resize(u,cw,h) {
    left := Max(180,Round((cw-38)*.40)), rightX := 268+left, rightW := cw-left-36, mh := Max(100,Min(190,Round((h-420)*.45)))
    u["chainSummary"].Move(256,145,cw-24,48), u["chainCue"].Move(256,197,cw-24,48)
    u["chainTree"].Move(256,290,left,207), u["chainDetails"].Move(256,505,left,Max(100,h-560))
    u["mini"].Move(rightX,290,rightW,mh), u["miniNote"].Move(rightX,294+mh,rightW,42)
    u["rawSnippet"].Move(rightX,330+mh,Min(150,rightW//3),90)
    u["ascii"].Move(rightX+Min(160,rightW//3+10),330+mh,Max(100,rightW-Min(160,rightW//3+10)),125)
    u["encoding"].Move(rightX,463+mh,rightW,Max(70,h-(518+mh)))
    u["chainNote"].Move(686,251,Max(50,cw-454),30)
    u["explorerQuery"].Move(256,145,cw-24), u["explorerNote"].Move(256,181,cw-24,70)
    u["explorerRows"].Move(256,260,cw-24,Max(120,h-315)), u["explorerRows"].ModifyCol(1,Max(200,cw-390))
}

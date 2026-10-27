; Passive taskbar learning. App identity comes from current accessibility labels
; and pinned-shortcut metadata; pixels and FindText bits remain separate evidence.
TaskbarKnowledge_Schema() {
    db := TrackDB()
    if !db
        throw Error("Tracking database is unavailable")
    db.Exec("CREATE TABLE IF NOT EXISTS taskbar_knowledge(id INTEGER PRIMARY KEY,identity TEXT UNIQUE,label TEXT,exe TEXT,shortcut_label TEXT,bar_class TEXT,acc_path TEXT,bounds TEXT,pattern TEXT,binary_bits TEXT,photo_ref TEXT,first_ts TEXT,last_ts TEXT,seen_count INTEGER DEFAULT 1,verified_count INTEGER DEFAULT 0,failure_count INTEGER DEFAULT 0)")
    ; TrackSQLite treats numeric-looking strings as numbers. Prefix the bind and
    ; strip it in SQL so long binary strings retain every leading zero and bit.
    for row in db.Query("SELECT id,pattern FROM taskbar_knowledge WHERE binary_bits GLOB '*[^01]*' OR binary_bits IS NULL OR binary_bits=''") {
        if RegExMatch(row["pattern"],"\$\d+\.([\w+/]+)",&encoded) {
            bits := FanVision_FT().base64tobit(encoded[1])
            db.Run("UPDATE taskbar_knowledge SET binary_bits=substr(?,2) WHERE id=?","b" . bits,row["id"])
        }
    }
    return db
}

TaskbarKnowledge_Normalize(name) {
    name := StrLower(name)
    name := RegExReplace(name,"i)\s*-\s*\d+ running windows?","")
    name := RegExReplace(name,"i)\s+pinned$","")
    name := StrReplace(name,"autohotkey","ahk")
    return RegExReplace(name,"[^a-z0-9]","")
}

TaskbarKnowledge_Shortcuts() {
    out := []
    folder := A_AppData . "\Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
    loop files folder . "\*.lnk" {
        try {
            FileGetShortcut(A_LoopFileFullPath,&target)
            SplitPath(target,&exe)
            label := RegExReplace(A_LoopFileName,"i)\.lnk$")
            out.Push(Map("label",label,"exe",exe,"normalized",TaskbarKnowledge_Normalize(label)))
        }
    }
    return out
}

TaskbarKnowledge_Bars() {
    out := []
    for cls in ["Shell_TrayWnd","Shell_SecondaryTrayWnd"] {
        for hwnd in WinGetList("ahk_class " . cls) {
            if !DllCall("IsWindowVisible","Ptr",hwnd)
                continue
            region := FanVision_WindowRect(hwnd)
            if region["w"] > 0 && region["h"] > 0
                out.Push(Map("hwnd",hwnd,"class",cls,"region",region))
        }
    }
    return out
}

TaskbarKnowledge_Buttons(bar) {
    out := [], seen := Map()
    catalog := FanVision_Controls(bar["hwnd"],bar["region"],500,true)
    for ctl in catalog["controls"] {
        bounds := ctl["bounds"], label := Trim(ctl["name"])
        if label = "" || !ctl["enabled"] || ctl["protected"] || !RegExMatch(ctl["role"],"i)button")
            continue
        if bounds["w"] < 3 || bounds["h"] < 3 || bounds["w"] > 500 || bounds["h"] > 200 || !FanVision_Contains(bar["region"],bounds)
            continue
        key := label . "|" . bounds["x"] . "," . bounds["y"]
        if !seen.Has(key)
            out.Push(ctl), seen[key] := true
    }
    return Map("buttons",out,"coverage",catalog)
}

TaskbarKnowledge_Learn(*) {
    db := TaskbarKnowledge_Schema(), shortcuts := TaskbarKnowledge_Shortcuts(), learned := [], warnings := []
    DeepActivity_Suspend()
    try {
        for bar in TaskbarKnowledge_Bars() {
            FanAPI_Progress("fan_taskbar_learn","Reading visible taskbar controls")
            buttons := TaskbarKnowledge_Buttons(bar)
            if buttons["coverage"]["truncated"]
                warnings.Push("Accessibility traversal was bounded; this taskbar may be incomplete.")
            for ctl in buttons["buttons"] {
                try {
                    label := ctl["name"], exe := "", shortcutLabel := "", normalized := TaskbarKnowledge_Normalize(label)
                    FanAPI_Progress("fan_taskbar_learn","Capturing: " . label)
                    for shortcut in shortcuts {
                        if shortcut["normalized"] = normalized || (StrLen(shortcut["normalized"])>=4 && InStr(normalized,shortcut["normalized"]))
                            exe := shortcut["exe"], shortcutLabel := shortcut["label"]
                    }
                    identity := TrackHash(bar["class"] . "|" . normalized), patternName := "Taskbar_" . identity
                    args := Map("hwnd",bar["hwnd"],"region",ctl["bounds"],"name",patternName,"overwrite",true,
                        "description","Taskbar icon: " . label . "; observed accessibility label; shortcut executable " . exe,"threshold","**50")
                    captured := FanVision_PatternCapture(args)
                    if !captured.Get("ok",false) {
                        warnings.Push(label . ": " . captured.Get("error","capture refused"))
                        continue
                    }
                    pattern := captured["text"], bits := ""
                    if RegExMatch(pattern,"\$\d+\.([\w+/]+)",&encoded)
                        bits := FanVision_FT().base64tobit(encoded[1])
                    photo := Photo_Store(captured["image_path"],"Taskbar: " . label), now := TrackTS()
                    db.Run("INSERT INTO taskbar_knowledge(identity,label,exe,shortcut_label,bar_class,acc_path,bounds,pattern,binary_bits,photo_ref,first_ts,last_ts) VALUES(?,?,?,?,?,?,?,?,substr(?,2),?,?,?) ON CONFLICT(identity) DO UPDATE SET label=excluded.label,exe=excluded.exe,shortcut_label=excluded.shortcut_label,acc_path=excluded.acc_path,bounds=excluded.bounds,pattern=excluded.pattern,binary_bits=excluded.binary_bits,photo_ref=excluded.photo_ref,last_ts=excluded.last_ts,seen_count=seen_count+1",
                        identity,label,exe,shortcutLabel,bar["class"],ctl["accessibility_path"],TrackJsonEncode(ctl["bounds"]),pattern,"b" . bits,photo,now,now)
                    id := db.Scalar("SELECT id FROM taskbar_knowledge WHERE identity=?",identity)
                    learned.Push(Map("id",id,"label",label,"exe",exe,"photo_ref",photo,"pattern_name",patternName,"binary_length",StrLen(bits),"bounds",ctl["bounds"]))
                    LearningLab_Record("Taskbar",id,"Taskbar target: " . label,"observed",Map("scope","taskbar","exe",exe),
                        "Named accessible button, screenshot and binary FindText pattern captured. Pinned shortcut metadata is not a verified foreground result.","taskbar_knowledge:" . id,"Use fan_taskbar_open with this label. It re-resolves the current taskbar and verifies the resulting foreground application.")
                } catch as captureError {
                    warnings.Push(ctl["name"] . ": " . captureError.Message)
                }
            }
        }
    } finally DeepActivity_Resume()
    for item in learned
        DeepActivity_Box(item["bounds"])
    g_DeepActivity["expires"] := A_TickCount+2500
    DeepActivity_Set(true,"Learned " . learned.Length . " taskbar targets",5000)
    return Map("ok",true,"targets",learned,"warnings",warnings,"count",learned.Length,
        "coverage","Visible accessible taskbar buttons only; hidden/overflow/unlabelled controls remain unknown.","source_kind","observed")
}

TaskbarKnowledge_List(args) {
    db := TaskbarKnowledge_Schema(), query := "%" . args.Get("query","") . "%", limit := Min(100,Max(1,args.Get("limit",30)))
    rows := db.Query("SELECT id,label,exe,shortcut_label,bar_class,acc_path,bounds,photo_ref,last_ts,seen_count,verified_count,failure_count,length(binary_bits) binary_length FROM taskbar_knowledge WHERE label LIKE ? OR exe LIKE ? ORDER BY last_ts DESC,id LIMIT ?",query,query,limit)
    return Map("ok",true,"targets",rows,"source_kind","observed","usage","Historical target map; open rechecks the live taskbar. Screenshots are stored by photo_ref and FindText patterns by Taskbar_<identity>.")
}

TaskbarKnowledge_Open(args) {
    db := TaskbarKnowledge_Schema(), requested := TaskbarKnowledge_Normalize(args["name"]), choices := []
    if requested = ""
        throw Error("Name an application from the learned taskbar")
    for row in db.Query("SELECT * FROM taskbar_knowledge ORDER BY CASE WHEN bar_class='Shell_TrayWnd' THEN 0 ELSE 1 END,last_ts DESC,id DESC") {
        normalized := TaskbarKnowledge_Normalize(row["label"]), alias := TaskbarKnowledge_Normalize(row["shortcut_label"])
        exe := TaskbarKnowledge_Normalize(RegExReplace(row["exe"],"i)\.exe$"))
        if requested = normalized || requested = alias || requested = exe || (StrLen(requested)>=4 && InStr(normalized,requested))
            choices.Push(row)
    }
    if choices.Length > 1 {
        sameApp := true
        for choice in choices
            if TaskbarKnowledge_Normalize(choice["label"]) != TaskbarKnowledge_Normalize(choices[1]["label"]) || choice["exe"] != choices[1]["exe"]
                sameApp := false
        if sameApp
            choices := [choices[1]]
    }
    if choices.Length != 1
        return Map("ok",false,"action_performed",false,"error",choices.Length ? "Ambiguous taskbar application; use the full saved label" : "Application was not learned on the taskbar; run fan_taskbar_learn first")
    row := choices[1], live := []
    DeepActivity_Suspend()
    try {
        for bar in TaskbarKnowledge_Bars() {
            if bar["class"] != row["bar_class"]
                continue
            for ctl in TaskbarKnowledge_Buttons(bar)["buttons"] {
                if TaskbarKnowledge_Normalize(ctl["name"]) != TaskbarKnowledge_Normalize(row["label"])
                    continue
                bounds := ctl["bounds"]
                matched := FanVision_PatternSearch(Map("hwnd",bar["hwnd"],"region",bounds,"text",row["pattern"],"err1",0.12,"err0",0.10))
                if matched.Get("ok",false) && matched["matches"].Length = 1 && matched["frame"]["geometry_stable"]
                    live.Push(Map("ctl",ctl,"bar",bar))
            }
        }
    } finally DeepActivity_Resume()
    if live.Length != 1 {
        db.Run("UPDATE taskbar_knowledge SET failure_count=failure_count+1 WHERE id=?",row["id"])
        return Map("ok",false,"action_performed",false,"error","Current named icon and FindText pattern did not resolve uniquely. Relearn the visible taskbar; no click was sent.")
    }
    target := live[1]["ctl"], bounds := target["bounds"]
    DeepActivity_Target(bounds,"Open " . row["label"] . " via learned taskbar",400)
    ; Re-resolve identity, geometry and pixels after the visible pre-action pause.
    fresh := false
    DeepActivity_Suspend()
    try {
        for ctl in TaskbarKnowledge_Buttons(live[1]["bar"])["buttons"] {
            if TaskbarKnowledge_Normalize(ctl["name"]) != TaskbarKnowledge_Normalize(row["label"]) || TrackJsonEncode(ctl["bounds"]) != TrackJsonEncode(bounds)
                continue
            checked := FanVision_PatternSearch(Map("hwnd",live[1]["bar"]["hwnd"],"region",bounds,"text",row["pattern"],"err1",0.12,"err0",0.10))
            fresh := checked.Get("ok",false) && checked["matches"].Length = 1 && checked["frame"]["geometry_stable"]
        }
    } finally DeepActivity_Resume()
    if !fresh
        return Map("ok",false,"action_performed",false,"error","Taskbar identity, geometry or pixels changed before input; no click was sent")
    DeepActivity_Target(bounds,"Opening " . row["label"])
    foreground := WinExist("A")
    if foreground && row["exe"] != "" && StrLower(WinGetProcessName(foreground)) = StrLower(row["exe"]) {
        db.Run("UPDATE taskbar_knowledge SET verified_count=verified_count+1 WHERE id=?",row["id"])
        LearningLab_Record("Taskbar",row["id"],"Taskbar target: " . row["label"],"pass",LearningLab_Context(foreground),
            "Fresh taskbar identity and FindText check passed. Requested program was already in the foreground; no click was needed.","taskbar_knowledge:" . row["id"],"Reuse the named taskbar target; re-resolve it before each operation.")
        return Map("ok",true,"verified",true,"action_performed",false,"name",row["label"],"hwnd",foreground,
            "exe",row["exe"],"title",WinGetTitle(foreground),"status","already_foreground","source_hash",TrackHash(row["pattern"]))
    }
    Click(target["center"]["x"],target["center"]["y"])
    verified := false, foreground := 0, actualExe := "", title := ""
    Loop 20 {
        Sleep(100)
        foreground := WinExist("A")
        if !foreground
            continue
        actualExe := WinGetProcessName(foreground), title := WinGetTitle(foreground)
        verified := row["exe"] != "" && StrLower(actualExe) = StrLower(row["exe"])
        if verified
            break
    }
    db.Run("UPDATE taskbar_knowledge SET verified_count=verified_count+?,failure_count=failure_count+? WHERE id=?",verified ? 1 : 0,verified ? 0 : 1,row["id"])
    LearningLab_Record("Taskbar",row["id"],"Taskbar target: " . row["label"],verified ? "pass" : "observed",LearningLab_Context(foreground),
        "Fresh label + FindText matched; click sent. Foreground executable: " . actualExe . "; expected: " . row["exe"],"taskbar_knowledge:" . row["id"],"Reuse the named taskbar target; re-resolve it before each click.")
    return Map("ok",verified,"verified",verified,"action_performed",true,"name",row["label"],"hwnd",foreground,"exe",actualExe,"title",title,"target",bounds,"source_hash",TrackHash(row["pattern"]),
        "error",verified ? "" : "Click was sent, but the foreground program could not be verified. Do not automatically repeat it.")
}

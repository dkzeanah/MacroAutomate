#Include FanHarness.ahk
#Include LearningProcedure.ahk
#Include AgentWorkbench.ahk
; Local evidence ledger and isolated lesson/replay runner. No LLM calls or input
; injection. Replay results never become fresh real-world verification evidence.
global g_LearningLab := Map("gui", 0, "rows", [], "selected", 0, "playing", false,
    "step", 0, "steps", [], "next", 0, "error", "", "busy", false)

LearningLab_Schema(db := 0) {
    static ready := 0
    if !db
        db := TrackDB()
    if !db
        return false
    if IsObject(ready) && ready = db
        return true
    db.Exec("CREATE TABLE IF NOT EXISTS learning_claim(id INTEGER PRIMARY KEY, source TEXT, identity TEXT, claim TEXT, use_text TEXT, created_ts TEXT, UNIQUE(source,identity))")
    db.Exec("CREATE TABLE IF NOT EXISTS learning_evidence(id INTEGER PRIMARY KEY, claim_id INTEGER, ts TEXT, outcome TEXT, context TEXT, detail TEXT, provenance TEXT, eligible INTEGER, session TEXT)")
    db.Exec("CREATE INDEX IF NOT EXISTS ix_learning_evidence_claim ON learning_evidence(claim_id,id)")
    db.Exec("CREATE TABLE IF NOT EXISTS learning_trial(id INTEGER PRIMARY KEY, claim_id INTEGER, ts TEXT, dimension TEXT, level_a TEXT, level_b TEXT, result TEXT, revision INTEGER, UNIQUE(claim_id,dimension,level_a,level_b,revision))")
    db.Exec("CREATE TABLE IF NOT EXISTS learning_lesson(claim_id INTEGER PRIMARY KEY, ts TEXT, revision INTEGER, steps TEXT)")
    db.Exec("CREATE TABLE IF NOT EXISTS learning_exploration(claim_id INTEGER PRIMARY KEY, signature TEXT, cursor INTEGER, offset INTEGER, stride INTEGER, total INTEGER)")
    db.Exec("CREATE TABLE IF NOT EXISTS learning_permutation(id INTEGER PRIMARY KEY,claim_id INTEGER,ts TEXT,signature TEXT,ordinal INTEGER,context TEXT,result TEXT,UNIQUE(claim_id,signature,ordinal))")
    ready := db
    return true
}

LearningLab_Context(hwnd := 0) {
    c := Map("scope", "unknown")
    try {
        if !hwnd
            hwnd := WinExist("A")
        if !hwnd || WinGetPID(hwnd) = DllCall("GetCurrentProcessId", "UInt")
            return c
        WinGetPos(&x,&y,&w,&h,hwnd)
        c := Map("scope", "observed window", "exe", WinGetProcessName(hwnd),
            "window", WinGetClass(hwnd), "size", w . "x" . h,
            "dpi", DllCall("GetDpiForWindow", "Ptr", hwnd, "UInt"),
            "time_band", Integer(FormatTime(,"HH"))//6)
        Loop MonitorGetCount() {
            MonitorGet(A_Index,&l,&t,&r,&b)
            if x+w/2 >= l && x+w/2 < r && y+h/2 >= t && y+h/2 < b
                c["monitor"] := A_Index
        }
    }
    return c
}

LearningLab_Record(source, identity, claim, outcome := "observed", context := "", detail := "", provenance := "", useText := "") {
    global g_LearningLab
    try {
        if !LearningLab_Schema()
            return 0
        if !(context is Map)
            context := Map("scope", "unknown")
        db := TrackDB(), now := TrackTS()
        db.Run("INSERT INTO learning_claim(source,identity,claim,use_text,created_ts) VALUES(?,?,?,?,?) ON CONFLICT(source,identity) DO UPDATE SET claim=excluded.claim,use_text=excluded.use_text",
            source, String(identity), SubStr(claim,1,1000), useText, now)
        id := db.Scalar("SELECT id FROM learning_claim WHERE source=? AND identity=?",source,String(identity))
        if outcome != "pass" && outcome != "fail"
            outcome := "observed"
        contextText := TrackJsonEncode(context)
        ; A burst of repeated scans is not independent supporting evidence.
        prior := db.QueryRow("SELECT ts FROM learning_evidence WHERE claim_id=? AND outcome=? AND context=? AND eligible=1 ORDER BY id DESC LIMIT 1",id,outcome,contextText)
        eligible := !prior.Count || DateDiff(A_Now, RegExReplace(prior["ts"],"\D"), "Seconds") >= 30
        static session := A_Now . "-" . DllCall("GetCurrentProcessId", "UInt")
        db.Run("INSERT INTO learning_evidence(claim_id,ts,outcome,context,detail,provenance,eligible,session) VALUES(?,?,?,?,?,?,?,?)",
            id,now,outcome,contextText,SubStr(detail,1,6000),provenance,eligible,session)
        return id
    } catch as err {
        g_LearningLab["error"] := err.Message
        return 0
    }
}

LearningLab_Summary(id) {
    db := TrackDB()
    row := db.QueryRow("SELECT c.*, SUM(CASE WHEN e.eligible=1 AND e.outcome='pass' THEN 1 ELSE 0 END) AS passes, SUM(CASE WHEN e.eligible=1 AND e.outcome='fail' THEN 1 ELSE 0 END) AS failures, COUNT(e.id) AS observations, COUNT(DISTINCT CASE WHEN e.eligible=1 AND e.outcome='pass' THEN e.context END) AS contexts, COUNT(DISTINCT CASE WHEN e.eligible=1 AND e.outcome='pass' THEN e.session END) AS sessions FROM learning_claim c LEFT JOIN learning_evidence e ON e.claim_id=c.id WHERE c.id=? GROUP BY c.id",id)
    if !row.Count
        return row
    p := row["passes"]+0, f := row["failures"]+0
    row["state"] := f ? "Contradicted / review" : p >= 5 && row["contexts"] >= 2 && row["sessions"] >= 2 ? "Supported in observed contexts" : p ? "Tentative verification" : "Observation only"
    ; Wilson lower bound, deliberately not labelled probability of truth.
    n := p+f, z := 1.96
    row["strength"] := n ? Max(0,((p/n)+z*z/(2*n)-z*Sqrt((p/n)*(1-p/n)/n+z*z/(4*n*n)))/(1+z*z/n)) : 0
    return row
}

LearningLab_Groups(id, dimension) {
    groups := Map()
    for e in TrackDB().Query("SELECT outcome,context FROM learning_evidence WHERE claim_id=? AND eligible=1 AND outcome IN ('pass','fail') ORDER BY id",id) {
        c := TrackJsonDecode(e["context"])
        value := String(c.Get(dimension,"unknown"))
        if !groups.Has(value)
            groups[value] := Map("pass",0,"fail",0)
        groups[value][e["outcome"]]++
    }
    return groups
}

LearningLab_Explain(id) {
    s := LearningLab_Summary(id)
    if !s.Count
        return "No evidence yet. Use Vision Scout, Usage Predictor, App Learner, or Study Assistant, then Refresh."
    historical := TrackDB().QueryRow("SELECT detail FROM learning_evidence WHERE claim_id=? AND context LIKE '%historical sequence%' ORDER BY id DESC LIMIT 1",id)
    text := s["claim"] . "`r`n`r`nWhat I know: " . s["state"] . "."
        . (historical.Count ? "`r`n`r`nRecorded learning: " . StrSplit(historical["detail"],"`n")[1] : "")
        . "`r`nEvidence: " . s["passes"] . " spaced positive checks; " . s["failures"] . " negative checks; " . s["observations"] . " total records."
        . "`r`nCoverage: " . s["contexts"] . " positive environment combinations across " . s["sessions"] . " program sessions. Repeats within 30 seconds in the same environment do not add strength."
        . "`r`nConservative repeatability bound: " . Round(100*s["strength"]) . "% (95% Wilson lower bound for recorded checks; sampling is observational, not proof of truth)."
        . "`r`n`r`nHow you can use it: " . s["use_text"]
        . "`r`n`r`nEnvironment layers (positive / negative checks):"
    for dimension in ["scope","exe","window","size","dpi","monitor","time_band"] {
        groups := LearningLab_Groups(id,dimension)
        text .= "`r`n  " . dimension . ": "
        for level, counts in groups
            text .= level . " [" . counts["pass"] . "/" . counts["fail"] . "]  "
    }
    text .= "`r`n`r`nWhat remains uncertain: size, DPI, monitor, application state and time can co-vary. A difference between groups is a possible confound, not a causal explanation. Missing outcomes are unknown, never failures. Pixel matching does not verify a control's meaning or an action's success."
        . "`r`nNext: collect fresh checks in naturally occurring contexts; review negative examples. Replay only compares stored outcomes and cannot establish causality or validate unobserved permutations."
        . "`r`n`r`nLatest evidence (ledger IDs link the lesson to the underlying source):"
    for e in TrackDB().Query("SELECT * FROM learning_evidence WHERE claim_id=? ORDER BY id DESC LIMIT 12",id)
        text .= "`r`n#" . e["id"] . " " . e["ts"] . " " . e["outcome"] . " | " . e["provenance"] . "`r`n" . e["detail"] . "`r`n" . e["context"]
    text .= "`r`n`r`nRecent replay comparisons:"
    for trial in TrackDB().Query("SELECT result FROM learning_trial WHERE claim_id=? ORDER BY id DESC LIMIT 5",id)
        text .= "`r`n" . trial["result"]
    text .= "`r`n`r`nEnvironment permutation plans (not executed desktop experiments):"
    for plan in TrackDB().Query("SELECT context,result FROM learning_permutation WHERE claim_id=? ORDER BY id DESC LIMIT 5",id)
        text .= "`r`n" . plan["context"] . "`r`n" . plan["result"]
    return text
}

LearningLab_BuildLesson(id) {
    s := LearningLab_Summary(id)
    if !s.Count
        return []
    rehearsal := s["use_text"], sequenceSteps := []
    if s["source"] = "Usage sequences" {
        e := TrackDB().QueryRow("SELECT context FROM learning_evidence WHERE claim_id=? ORDER BY id DESC LIMIT 1",id)
        if e.Count {
            c := TrackJsonDecode(e["context"])
            rehearsal := "Generated sequence rehearsal: " . c.Get("sequence","") . " -> " . c.Get("expected","") . ". Review the same application state and locate each target freshly before any real execution."
            for token in StrSplit(c.Get("sequence","")," > ")
                sequenceSteps.Push(LearningLab_DescribeToken(token))
            sequenceSteps.Push(LearningLab_DescribeToken(c.Get("expected","")))
        }
    }
    steps := [Map("layer","Observation","text",s["source"] . " recorded: " . s["claim"]),
        Map("layer","Evidence","text",s["passes"] . " spaced checks support this; " . s["failures"] . " contradict it. " . s["state"] . "."),
        Map("layer","Context","text","Coverage is " . s["contexts"] . " observed combinations across " . s["sessions"] . " sessions. Inspect the environment layers before generalizing."),
        Map("layer","Alternatives","text","Possible confounds: window size, DPI, monitor, application state, time, and repeated capture of the same example. Correlation alone does not eliminate them."),
        Map("layer","Rehearsal","text",rehearsal . " This rehearsal describes the plan inside this window; it performs no desktop actions."),
        Map("layer","Next experiment","text","Compare one pair of observed environment levels using stored checks. Unseen combinations remain on the evidence collection wishlist. Obtain a fresh real-world check before using a learned target.")]
    for index, description in sequenceSteps
        steps.InsertAt(5+index,Map("layer","Simulated step " . index,"text",description . ". Preview only: no keys or clicks are sent."))
    if s["source"] = "Usage sequences" {
        reuseText := "Save rehearsal compiles the exact recorded tokens once. Run saved executes that stored native workflow in an isolated fixture, with zero DeepSeek calls. Original application behavior remains unverified."
        if TrackDB().TableExists("learning_procedure") {
            saved := TrackDB().QueryRow("SELECT name,run_count FROM learning_procedure WHERE claim_id=? ORDER BY compiled_ts DESC LIMIT 1",id)
            if saved.Count
                reuseText .= " Saved procedure: " . saved["name"] . "; completed fixture runs: " . saved["run_count"] . "."
        }
        steps.Push(Map("layer","Reuse without generation","text",reuseText))
    }
    TrackDB().Run("INSERT INTO learning_lesson(claim_id,ts,revision,steps) VALUES(?,?,?,?) ON CONFLICT(claim_id) DO UPDATE SET ts=excluded.ts,revision=excluded.revision,steps=excluded.steps",
        id,TrackTS(),s["observations"],TrackJsonEncode(steps))
    return steps
}

LearningLab_Replay(id) {
    ; Randomized traversal without replacement at this evidence revision. One
    ; dimension/pair per tick, with a fixed per-claim evidence cap.
    s := LearningLab_Summary(id), candidates := []
    if !s.Count
        return "No claim selected."
    if s["observations"] > 2000
        return "Replay paused for this large claim (over 2,000 records); review its evidence manually."
    db := TrackDB()
    for dimension in ["exe","window","size","dpi","monitor","time_band"] {
        levels := []
        for level, counts in LearningLab_Groups(id,dimension)
            if level != "unknown" && levels.Length < 12
                levels.Push(Map("level",level,"counts",counts))
        for i, a in levels {
            for j, b in levels {
                if j <= i
                    continue
                if !db.Scalar("SELECT COUNT(*) FROM learning_trial WHERE claim_id=? AND dimension=? AND level_a=? AND level_b=? AND revision=?",id,dimension,a["level"],b["level"],s["observations"])
                    candidates.Push(Map("dimension",dimension,"a",a,"b",b))
            }
        }
    }
    if !candidates.Length
        return "No untested observed pairs at this revision. Waiting for new real-world evidence; unseen combinations remain unknown."
    item := candidates[Random(1,candidates.Length)], a := item["a"], b := item["b"]
    ac := a["counts"], bc := b["counts"]
    an := ac["pass"]+ac["fail"], bn := bc["pass"]+bc["fail"]
    delta := Abs(ac["pass"]/an - bc["pass"]/bn)
    result := item["dimension"] . ": " . a["level"] . " (" . ac["pass"] . "/" . an . ") vs " . b["level"] . " (" . bc["pass"] . "/" . bn . "). "
        . (Min(an,bn) < 3 ? "Insufficient checks in at least one group." : delta > 0.25 ? "Possible contextual dependency; inspect co-varying dimensions." : "No large difference in these stored samples.")
        . " Observational replay only; no causal claim or new verification."
    result .= " " . LearningLab_MatchedComparison(id,item["dimension"],a["level"],b["level"])
    db.Run("INSERT OR IGNORE INTO learning_trial(claim_id,ts,dimension,level_a,level_b,result,revision) VALUES(?,?,?,?,?,?,?)",
        id,TrackTS(),item["dimension"],a["level"],b["level"],result,s["observations"])
    LearningLab_BuildLesson(id)
    return result
}

LearningLab_MatchedComparison(id,dimension,a,b) {
    strata := Map()
    for e in TrackDB().Query("SELECT context,outcome FROM learning_evidence WHERE claim_id=? AND eligible=1 AND outcome IN ('pass','fail') ORDER BY id LIMIT 2000",id) {
        context := TrackJsonDecode(e["context"]), level := String(context.Get(dimension,"unknown"))
        if level != a && level != b
            continue
        rest := Map()
        for key in ["scope","exe","window","size","dpi","monitor","time_band","source","verification","sequence","expected"]
            if key != dimension
                rest[key] := context.Get(key,"unknown")
        signature := TrackJsonEncode(rest)
        if !strata.Has(signature)
            strata[signature] := Map("a",Map("pass",0,"fail",0),"b",Map("pass",0,"fail",0))
        strata[signature][level = a ? "a" : "b"][e["outcome"]]++
    }
    matched := 0, maxDifference := 0
    for signature, groups in strata {
        an := groups["a"]["pass"]+groups["a"]["fail"], bn := groups["b"]["pass"]+groups["b"]["fail"]
        if an && bn {
            matched++
            maxDifference := Max(maxDifference,Abs(groups["a"]["pass"]/an-groups["b"]["pass"]/bn))
        }
    }
    return matched ? "Holding other recorded dimensions fixed: " . matched . " shared strata; largest observed rate gap " . Round(maxDifference*100) . " percentage points. Unmeasured confounds remain."
        : "No matched environments holding the other recorded dimensions fixed; the apparent effect cannot be separated from confounding."
}

LearningLab_Permutation(id) {
    ; Walk the finite Cartesian product in a randomized order without repeats.
    ; These are evidence-collection plans, never synthetic confirmations.
    db := TrackDB(), dimensions := ["exe","window","size","dpi","monitor","time_band"]
    evidence := db.Query("SELECT context,outcome FROM learning_evidence WHERE claim_id=? AND eligible=1 AND outcome IN ('pass','fail') ORDER BY id LIMIT 2001",id)
    if !evidence.Length
        return "Waiting for real checks before building environment permutations."
    if evidence.Length > 2000
        return "Permutation planning paused at the 2,000-check work budget."
    levels := Map(), total := 1, subset := false
    for dimension in dimensions {
        unique := Map()
        for e in evidence {
            c := TrackJsonDecode(e["context"])
            value := String(c.Get(dimension,"unknown"))
            unique[value] := true
        }
        values := []
        for value in unique {
            if values.Length >= 8 {
                subset := true
                break
            }
            values.Push(value)
        }
        levels[dimension] := values
        total *= values.Length
    }
    signature := TrackHash(TrackJsonEncode(levels))
    plan := db.QueryRow("SELECT * FROM learning_exploration WHERE claim_id=?",id)
    if !plan.Count || plan["signature"] != signature {
        stride := Random(1,Max(1,total-1))
        while LearningLab_GCD(stride,total) != 1
            stride := Mod(stride,total)+1
        db.Run("INSERT INTO learning_exploration(claim_id,signature,cursor,offset,stride,total) VALUES(?,?,0,?,?,?) ON CONFLICT(claim_id) DO UPDATE SET signature=excluded.signature,cursor=0,offset=excluded.offset,stride=excluded.stride,total=excluded.total",
            id,signature,Random(0,total-1),stride,total)
        plan := db.QueryRow("SELECT * FROM learning_exploration WHERE claim_id=?",id)
    }
    if plan["cursor"] >= total
        return "All " . total . " planned combinations traversed. Missing evidence remains unknown; new environment levels start a new traversal."
    ordinal := Mod(plan["offset"]+plan["cursor"]*plan["stride"],total), remaining := ordinal, combination := Map()
    for dimension in dimensions {
        values := levels[dimension]
        combination[dimension] := values[Mod(remaining,values.Length)+1]
        remaining := remaining//values.Length
    }
    passes := 0, failures := 0
    for e in evidence {
        c := TrackJsonDecode(e["context"]), matches := true
        for dimension in dimensions
            if String(c.Get(dimension,"unknown")) != combination[dimension]
                matches := false
        if matches
            e["outcome"] = "pass" ? passes++ : failures++
    }
    result := passes+failures ? "Stored checks: " . passes . " positive, " . failures . " negative. This is replay, not new verification."
        : "Evidence needed. Wait for this environment to occur naturally, then perform a fresh recognition or prediction check. Feasibility and causality remain untested."
    if subset
        result .= " Budget: first 8 observed levels per dimension only."
    db.Run("INSERT OR IGNORE INTO learning_permutation(claim_id,ts,signature,ordinal,context,result) VALUES(?,?,?,?,?,?)",id,TrackTS(),signature,ordinal,TrackJsonEncode(combination),result)
    db.Run("UPDATE learning_exploration SET cursor=cursor+1 WHERE claim_id=?",id)
    return "Permutation " . (plan["cursor"]+1) . "/" . total . ": " . TrackJsonEncode(combination) . " " . result
}

LearningLab_GCD(a,b) {
    while b
        r := Mod(a,b), a := b, b := r
    return a
}

LearningLab_Start() {
    LearningLab_Schema()
    g_LearningLab["next"] := A_TickCount+Random(45000,90000)
    SetTimer(LearningLab_Tick,5000)
}

LearningLab_Tick() {
    global g_LearningLab
    if g_LearningLab["busy"] || A_TickCount < g_LearningLab["next"] || A_TimeIdlePhysical < 1500
        return
    g_LearningLab["next"] := A_TickCount+Random(45000,90000)
    if !FanData_Config().Get("learning_replay",true)
        return
    g_LearningLab["busy"] := true
    try {
        ids := TrackDB().Query("SELECT id FROM learning_claim ORDER BY id DESC LIMIT 100")
        if ids.Length {
            id := ids[Random(1,ids.Length)]["id"]
            LearningLab_Replay(id)
            LearningLab_Permutation(id)
        }
    } catch as err {
        g_LearningLab["error"] := err.Message
    } finally g_LearningLab["busy"] := false
}

LearningLab_Open(*) {
    global g_LearningLab
    if IsObject(g_LearningLab["gui"]) {
        g_LearningLab["gui"].Show("NoActivate")
        LearningLab_Refresh()
        return
    }
    g := Gui("+Resize +MinSize780x560 -DPIScale", "Stored Evidence and Lessons — Learning Workbench")
    g.SetFont("s10","Segoe UI")
    g_LearningLab["gui"] := g
    g.Add("Button","x12 y10 w100 h28","Refresh").OnEvent("Click",LearningLab_Refresh)
    g.Add("Button","x120 y10 w145 h28","Show lesson").OnEvent("Click",LearningLab_Play)
    g.Add("Button","x273 y10 w110 h28","Stop lesson").OnEvent("Click",LearningLab_Stop)
    g.Add("Button","x391 y10 w140 h28","Replay one pair").OnEvent("Click",LearningLab_RunSelected)
    cb := g.Add("Checkbox","x545 y14 w320","Spread out background replays")
    cb.Value := FanData_Config().Get("learning_replay",true)
    cb.OnEvent("Click",(*) => LearningLab_SetReplay(cb.Value))
    g.Add("Button","x12 y44 w130 h28","Save rehearsal").OnEvent("Click",(*)=>LearningProcedure_UI(false))
    g.Add("Button","x150 y44 w120 h28","Run saved").OnEvent("Click",(*)=>LearningProcedure_UI(true))
    g.Add("Button","x278 y44 w130 h28","Python Atlas").OnEvent("Click",(*)=>FanHarness_Open("index"))
    g.Add("Button","x420 y44 w155 h28","Live discoveries").OnEvent("Click",(*)=>AgentWorkbench_Open("discoveries"))
    g.Add("Button","x583 y44 w155 h28","Observation canvas").OnEvent("Click",(*)=>AgentWorkbench_Open("canvas"))
    g.Add("Button","x746 y44 w155 h28","Tools and methods").OnEvent("Click",(*)=>AgentWorkbench_Open("canvas"))
    g_LearningLab["list"] := g.Add("ListView","x12 y88 w900 h155 -Multi",["ID","Learner","Claim","Status","+ / -"])
    for col, width in [45,120,380,230,70]
        g_LearningLab["list"].ModifyCol(col,width)
    g_LearningLab["list"].OnEvent("ItemSelect",LearningLab_Select)
    g_LearningLab["tree"] := g.Add("TreeView","x12 y252 w250 h360")
    g_LearningLab["details"] := g.Add("Edit","x274 y252 w638 h360 ReadOnly Multi","")
    g_LearningLab["status"] := g.Add("Text","x12 y622 w900 h58","Waiting for evidence.")
    g.OnEvent("Size",LearningLab_Resize)
    g.OnEvent("Close",(*) => (LearningLab_Stop(),g.Hide()))
    monitor := LearningValidation_Monitor()
    if monitor {
        MonitorGetWorkArea(monitor,&l,&t,&r,&b)
        SecondaryWindows_Place(g,"NoActivate x" . (l+20) . " y" . (t+20) . " w" . Min(940,r-l-40) . " h" . Min(700,b-t-40))
    } else
        SecondaryWindows_Place(g,"NoActivate w940 h700")
    LearningLab_Refresh()
}

LearningLab_Present(args) {
    query := Trim(args.Get("query",""))
    claimId := args.Get("claim_id",0)
    if query = "" && !claimId
        return Map("ok",false,"error","Name a stored claim, for example SciTE")
    LearningLab_Schema()
    rows := claimId ? TrackDB().Query("SELECT id FROM learning_claim WHERE id=?",claimId) : TrackDB().Query("SELECT id FROM learning_claim WHERE claim LIKE ? ORDER BY CASE WHEN source='Taskbar' THEN 0 ELSE 1 END,EXISTS(SELECT 1 FROM learning_evidence e WHERE e.claim_id=learning_claim.id AND e.outcome='pass') DESC,id DESC LIMIT 1","%" . query . "%")
    if !rows.Length
        return Map("ok",false,"error","No retained claim matches this request; observe or learn it first")
    id := rows[1]["id"]
    g_LearningLab["selected"] := id
    LearningLab_Open()
    LearningLab_Refresh()
    LearningLab_Play()
    summary := LearningLab_Summary(id)
    return Map("ok",true,"claim_id",id,"claim",summary["claim"],"source",summary["source"],"state",summary["state"],
        "explanation",LearningLab_Explain(id),"lesson_steps",LearningLab_BuildLesson(id).Length,
        "verification","Stored-evidence lesson shown in the Workbench. No input is sent to underlying applications.")
}

LearningLab_Resize(g,state,w,h) {
    if state = -1
        return
    g_LearningLab["list"].Move(12,88,w-24,155)
    g_LearningLab["tree"].Move(12,252,250,Max(100,h-332))
    g_LearningLab["details"].Move(274,252,w-286,Max(100,h-332))
    g_LearningLab["status"].Move(12,h-70,w-24,60)
}

LearningLab_Refresh(*) {
    LearningLab_Schema()
    LearningLab_ImportInventory()
    lv := g_LearningLab["list"]
    selected := g_LearningLab["selected"]
    lv.Delete(), g_LearningLab["rows"] := []
    for row in TrackDB().Query("SELECT id FROM learning_claim ORDER BY CASE WHEN id=? THEN 0 ELSE 1 END,id DESC LIMIT 250",selected) {
        s := LearningLab_Summary(row["id"])
        g_LearningLab["rows"].Push(s["id"])
        index := lv.Add(,s["id"],s["source"],s["claim"],s["state"],s["passes"] . " / " . s["failures"])
        if s["id"] = selected
            lv.Modify(index,"Select")
    }
    if !selected && g_LearningLab["rows"].Length
        lv.Modify(1,"Select")
    current := lv.GetNext()
    if current
        LearningLab_Select(lv,current,true)
    g_LearningLab["status"].Value := "Showing latest 250 claims. All evidence remains in the database. " . g_LearningLab["error"]
}

LearningLab_Select(lv,row,selected) {
    if !selected || row > g_LearningLab["rows"].Length
        return
    LearningLab_Stop()
    id := g_LearningLab["rows"][row]
    g_LearningLab["selected"] := id
    g_LearningLab["details"].Value := LearningLab_Explain(id)
    steps := LearningLab_BuildLesson(id), tree := g_LearningLab["tree"]
    tree.Delete(), nodes := []
    root := tree.Add("Claim #" . id,0,"Expand")
    for step in steps {
        node := tree.Add(step["layer"],root,"Expand")
        tree.Add(step["text"],node)
        nodes.Push(node)
    }
    g_LearningLab["nodes"] := nodes
}

LearningLab_Play(*) {
    id := g_LearningLab["selected"]
    if !id
        return
    g_LearningLab["steps"] := LearningLab_BuildLesson(id)
    g_LearningLab["step"] := 0, g_LearningLab["playing"] := true
    SetTimer(LearningLab_PlayTick,3500)
    LearningLab_PlayTick()
}

LearningLab_PlayTick() {
    if !g_LearningLab["playing"]
        return
    index := ++g_LearningLab["step"]
    if index > g_LearningLab["steps"].Length
        return LearningLab_Stop()
    step := g_LearningLab["steps"][index]
    g_LearningLab["tree"].Modify(g_LearningLab["nodes"][index],"Select Vis")
    g_LearningLab["status"].Value := index . "/" . g_LearningLab["steps"].Length . " " . step["layer"] . ": " . SubStr(step["text"],1,180)
    g_LearningLab["details"].Value := "LESSON " . index . "/" . g_LearningLab["steps"].Length . " - " . step["layer"] . "`r`n" . step["text"]
        . "`r`n`r`n" . LearningLab_Explain(g_LearningLab["selected"])
}

LearningLab_Stop(*) {
    g_LearningLab["playing"] := false
    SetTimer(LearningLab_PlayTick,0)
}

LearningLab_RunSelected(*) {
    if g_LearningLab["selected"]
        g_LearningLab["status"].Value := LearningLab_Replay(g_LearningLab["selected"]) . "`n" . LearningLab_Permutation(g_LearningLab["selected"])
}

LearningLab_SetReplay(enabled) {
    config := FanData_Config().Clone()
    config["learning_replay"] := !!enabled
    FanData_SaveConfig(config)
}

LearningLab_Study(qaId,answer,state,source,evidence) {
    ; Different answers to the same question are different claims. Contradicting
    ; a candidate must not silently transfer support to its replacement.
    outcome := state = "user-confirmed" || state = "source-confirmed" || state = "portal-confirmed" ? "pass"
        : state = "disputed" || state = "rejected" ? "fail" : "observed"
    LearningLab_Record("Study",qaId . ":" . TrackHash(answer),"Question #" . qaId . " answer: " . SubStr(answer,1,200),outcome,
        Map("scope","question:" . qaId,"source",source,"verification",state),"State: " . state . ". Source evidence: " . evidence,
        "qa_item:" . qaId,"Review this question and its source evidence in Study Assistant. Confirmed answers can be reused for this question; changed wording still needs review.")
}

LearningLab_CheckPrediction(prefixHash,prefixText,actualToken) {
    ; Called BEFORE training on this event. Only natural events reach this hook;
    ; the existing usage recorder excludes its automated replays.
    best := TrackDB().QueryRow("SELECT * FROM usage_transition WHERE prefix_hash=? AND prefix_text=? AND support>=2 ORDER BY support DESC,id LIMIT 1",prefixHash,prefixText)
    if !best.Count
        return
    context := LearningLab_Context()
    context["sequence"] := prefixText
    context["expected"] := best["next_token"]
    LearningLab_Record("Usage sequences",prefixHash . ":" . TrackHash(best["next_token"]),
        "After " . prefixText . ", expect " . best["next_token"],best["next_token"] = actualToken ? "pass" : "fail",context,
        "Prediction scored before training. Expected: " . best["next_token"] . "; observed: " . actualToken . ". A different user choice is a counterexample to this prediction, not an execution error.",
        "usage_transition:" . best["id"],"Rehearse this sequence here, then review it in Usage Predictor. Preserve alternate continuations and re-locate targets before accepting any offered action.")
}

LearningLab_DescribeToken(token) {
    if SubStr(token,1,4) = "KEY:"
        return "Press " . StrReplace(StrReplace(StrReplace(StrReplace(SubStr(token,5),"^","Ctrl+"),"!","Alt+"),"{",""),"}","")
    if SubStr(token,1,4) = "APP:"
        return "Switch to " . SubStr(token,5)
    if RegExMatch(token,"^CLICK:E(\d+):([LRM])$",&match) {
        description := "saved visual region #" . match[1]
        if TrackDB().TableExists("usage_element") {
            row := TrackDB().QueryRow("SELECT ue.name,ue.role,w.name AS win_name FROM usage_element ue LEFT JOIN win w ON w.id=ue.win_id WHERE ue.id=?",Integer(match[1]))
            if row.Count
                description .= " (" . row["name"] . "; " . row["role"] . "; " . row["win_name"] . ")"
        }
        return (match[2] = "R" ? "Right-click " : match[2] = "M" ? "Middle-click " : "Left-click ") . description
    }
    if SubStr(token,1,5) = "TYPE:"
        return "Enter text matching the recorded shape " . SubStr(token,6) . "; literal text is not filled by this rehearsal"
    return token
}

LearningLab_ImportSequence(row) {
    identity := row["prefix_hash"] . ":" . TrackHash(row["next_token"])
    existing := TrackDB().Scalar("SELECT id FROM learning_claim WHERE source='Usage sequences' AND identity=?",identity)
    if existing
        return existing
    chain := ""
    for token in StrSplit(row["prefix_text"]," > ")
        chain .= (chain = "" ? "" : " -> ") . LearningLab_DescribeToken(token)
    chain .= " -> " . LearningLab_DescribeToken(row["next_token"])
    return LearningLab_Record("Usage sequences",identity,chain,"observed",
        Map("scope","historical sequence","sequence",row["prefix_text"],"expected",row["next_token"]),
        "Existing learner recorded this continuation " . row["support"] . " times; accepted automation count: " . row["accepted"] . ". Historical frequency is not held-out accuracy.`nRehearsal: " . chain,
        "usage_transition:" . row["id"],"Use Show lesson to rehearse the saved steps. Review the sequence in Usage Predictor and freshly locate its targets before accepting real execution. The saved regions have not acquired semantic meaning merely through repetition.")
}

LearningLab_ShowKnown(*) {
    try {
        LearningLab_Schema()
        chosen := 0
        if TrackDB().TableExists("usage_transition") {
            for row in TrackDB().Query("SELECT * FROM usage_transition WHERE prefix_len=2 AND support>=3 ORDER BY support DESC LIMIT 100") {
                parts := StrSplit(row["prefix_text"]," > ")
                if parts.Length = 2 && parts[1] != parts[2] && InStr(row["prefix_text"],"CLICK:") {
                    chosen := LearningLab_ImportSequence(row)
                    break
                }
            }
        }
        if chosen
            g_LearningLab["selected"] := chosen
        LearningLab_Open()
        if chosen {
            for index, id in g_LearningLab["rows"] {
                if id = chosen {
                    g_LearningLab["list"].Modify(index,"Select Focus Vis")
                    LearningLab_Select(g_LearningLab["list"],index,true)
                    break
                }
            }
            LearningLab_Play()
        }
        SetTimer(LearningLab_SavePreview,-800)
    } catch as err {
        g_LearningLab["error"] := err.Message
    }
}

LearningLab_SavePreview(*) {
    old := DllCall("SetThreadDpiAwarenessContext","Ptr",-4,"Ptr")
    try {
        WinGetPos(&x,&y,&w,&h,g_LearningLab["gui"])
        bitmap := Gdip_BitmapFromScreen(x . "|" . y . "|" . w . "|" . h)
        if bitmap {
            try Gdip_SaveBitmapToFile(bitmap,FanData_ProjectRoot() . "\fan\tests\runtime\LearningWorkbench_Live.png")
            finally Gdip_DisposeImage(bitmap)
        }
    } finally DllCall("SetThreadDpiAwarenessContext","Ptr",old,"Ptr")
}

LearningLab_ImportInventory() {
    ; Seed old records once as observations, not fabricated historical checks.
    db := TrackDB()
    if db.TableExists("usage_transition") {
        ; Old training counts remain historical observations, never new passes.
        for row in db.Query("SELECT * FROM usage_transition WHERE prefix_len=2 AND support>=3 ORDER BY support DESC LIMIT 12")
            LearningLab_ImportSequence(row)
    }
    sources := [Map("table","vs_element","source","Vision Scout","claim","Saved visual target","use","Review and test this candidate in Vision Scout; certify it before exporting to Patterns."),
        Map("table","usage_element","source","Usage Predictor","claim","Saved visual region","use","Inspect this region and its associated usage sequence. A frequent region is not proof of a successful action."),
        Map("table","ui_element","source","App Learner","claim","Saved control locator","use","Review this control in App Learner and locate it fresh before creating an action."),
        Map("table","qa_item","source","Study","claim","Saved study question","use","Review the answer, its verification state and source in Study Assistant. A candidate is not established knowledge.")]
    for src in sources {
        if !db.TableExists(src["table"])
            continue
        for row in db.Query("SELECT * FROM " . src["table"] . " WHERE id NOT IN (SELECT CAST(identity AS INTEGER) FROM learning_claim WHERE source=?) ORDER BY id DESC LIMIT 30",src["source"]) {
            label := row.Get("question",row.Get("name",row.Get("ocr_text","")))
            LearningLab_Record(src["source"],row["id"],src["claim"] . " #" . row["id"] . ": " . SubStr(label,1,180),"observed",Map("scope","legacy inventory"),
                "Existing record imported for review. Previous counts or certification are not reconstructed as independent checks. State: " . row.Get("state",row.Get("review_state","unknown"))
                . ". Role: " . row.Get("role","") . ". Shortcut: " . row.Get("shortcut","") . ". Answer: " . row.Get("answer","") . ". Source evidence: " . row.Get("evidence",""),src["table"] . ":" . row["id"],src["use"])
        }
    }
}

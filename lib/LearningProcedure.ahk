#Include DeepSeekActivity.ahk
; Stored observed sequences -> immutable native workflows -> isolated rehearsal.
; Fixture results never become evidence that the original application succeeded.
global g_LearningProcedure := Map("gui",0,"name","","plan",[],"position",0,"history",[],"targets",Map(),"busy",false)

LearningProcedure_Schema() {
    db := TrackDB()
    db.Exec("CREATE TABLE IF NOT EXISTS learning_procedure(name TEXT PRIMARY KEY,claim_id INTEGER,source_evidence_id INTEGER,source_context TEXT,plan TEXT,compiled_ts TEXT,run_count INTEGER DEFAULT 0,last_run TEXT)")
    db.Exec("CREATE TABLE IF NOT EXISTS learning_procedure_run(id INTEGER PRIMARY KEY,name TEXT,ts TEXT,result TEXT)")
    return db
}

LearningProcedure_Compile(args) {
    db := LearningProcedure_Schema(), id := args["claim_id"], summary := LearningLab_Summary(id)
    if !summary.Count || summary["source"] != "Usage sequences"
        throw Error("Select a recorded Usage sequences claim; single-target observations are not multi-step procedures")
    source := db.QueryRow("SELECT * FROM learning_evidence WHERE claim_id=? ORDER BY id DESC LIMIT 1",id)
    if !source.Count
        throw Error("The claim has no source evidence")
    context := TrackJsonDecode(source["context"])
    tokens := StrSplit(context.Get("sequence","")," > ")
    tokens.Push(context.Get("expected",""))
    if tokens.Length < 2 || tokens.Length > 20
        throw Error("Rehearsal requires 2..20 explicitly stored tokens")
    plan := []
    for index, token in tokens {
        if !RegExMatch(token,"^(CLICK:E\d+:[LRM]|KEY:.+|APP:.+|TYPE:.+)$")
            throw Error("Unsupported or missing source token at step " . index)
        item := Map("token",token,"description",LearningLab_DescribeToken(token),"original_target_verified",false)
        if RegExMatch(token,"^CLICK:E(\d+):",&element) {
            target := db.QueryRow("SELECT name,role,pattern,verified FROM usage_element WHERE id=?",Integer(element[1]))
            if !target.Count
                throw Error("Source target no longer exists: " . element[1])
            item["element_id"] := Integer(element[1]), item["pattern"] := target["pattern"]
            item["note"] := StrLen(target["pattern"]) < 40 ? "Saved visual pattern is incomplete; original-app replay is blocked." : "Historical pattern only; original-app replay needs a fresh target check."
        } else
            item["note"] := "Token is represented inside the fixture; no global input is sent."
        plan.Push(item)
    }
    name := "Learned rehearsal " . id . "-" . TrackHash(source["context"]), steps := []
    for index, item in plan
        steps.Push(Map("action","Learned Rehearsal Step","target","","param",TrackJsonEncode(Map("procedure",name,"step",index))))
    saved := db.QueryRow("SELECT * FROM learning_procedure WHERE name=?",name)
    if !saved.Count {
        saveFunction := "FanAPI_Workflow"
        %saveFunction%("fan_workflow_save",Map("name",name,"steps",steps,"description","Deterministic isolated rehearsal of stored claim " . id))
        db.Run("INSERT INTO learning_procedure(name,claim_id,source_evidence_id,source_context,plan,compiled_ts) VALUES(?,?,?,?,?,?)",name,id,source["id"],source["context"],TrackJsonEncode(plan),TrackTS())
    }
    return Map("ok",true,"name",name,"workflow_name",name,"claim_id",id,"source_evidence_id",source["id"],"source_provenance",source["provenance"],
        "source_kind","observed_sequence","steps",steps,"plan",plan,"reused",saved.Count>0,"scope","isolated_fixture_only","original_app_verified",false,"llm_calls",0)
}

LearningProcedure_Get(name) {
    row := LearningProcedure_Schema().QueryRow("SELECT * FROM learning_procedure WHERE name=?",name)
    if !row.Count
        throw Error("No saved procedure with this name. Save rehearsal once first.")
    source := TrackDB().QueryRow("SELECT context FROM learning_evidence WHERE id=?",row["source_evidence_id"])
    if !source.Count || source["context"] != row["source_context"]
        throw Error("Source evidence changed or is missing; review the procedure before reuse")
    row["plan"] := TrackJsonDecode(row["plan"])
    return row
}

LearningProcedure_Show(row) {
    if IsObject(g_LearningProcedure["gui"])
        g_LearningProcedure["gui"].Destroy()
    g := Gui("+Resize -DPIScale","Learned automation rehearsal — " . row["name"])
    g.SetFont("s10","Segoe UI")
    g.Add("Text","x12 y12 w810 h50","Real stored sequence, replayed in an isolated fixture. No clicks, keys, focus changes or application commands go to underlying windows. Original application success remains unverified.")
    g_LearningProcedure["gui"] := g, g_LearningProcedure["name"] := row["name"]
    g_LearningProcedure["plan"] := row["plan"], g_LearningProcedure["position"] := 0
    g_LearningProcedure["history"] := [], g_LearningProcedure["targets"] := Map()
    for index, item in row["plan"] {
        token := item["token"]
        if g_LearningProcedure["targets"].Has(token)
            continue
        y := 75 + g_LearningProcedure["targets"].Count*66
        control := g.Add("Button","x12 y" . y . " w800 h56",item["description"])
        control.OnEvent("Click",LearningProcedure_Activate.Bind(token))
        g_LearningProcedure["targets"][token] := control
    }
    y := 85+g_LearningProcedure["targets"].Count*66
    g_LearningProcedure["log"] := g.Add("Edit","x12 y" . y . " w800 h170 ReadOnly Multi","")
    g.OnEvent("Close",(*)=>g.Hide())
    g.Show("NoActivate w830 h" . (y+185))
}

LearningProcedure_Activate(token,*) {
    next := g_LearningProcedure["position"]+1, plan := g_LearningProcedure["plan"]
    if next > plan.Length || plan[next]["token"] != token
        return false
    g_LearningProcedure["position"] := next
    g_LearningProcedure["history"].Push(token)
    g_LearningProcedure["log"].Value .= next . ". " . plan[next]["description"] . "`r`n    " . plan[next]["note"] . "`r`n"
    return true
}

LearningProcedure_Step(param) {
    args := TrackJsonDecode(param), name := args.Get("procedure","")
    if !g_LearningProcedure["busy"] || name != g_LearningProcedure["name"]
        throw Error("This action only runs inside the prepared isolated rehearsal")
    row := LearningProcedure_Get(name), index := args.Get("step",0)
    if index != g_LearningProcedure["position"]+1 || index > row["plan"].Length || index < 1
        throw Error("Saved procedure step is out of order")
    token := row["plan"][index]["token"], ctl := g_LearningProcedure["targets"][token]
    if !DllCall("IsWindowVisible","Ptr",g_LearningProcedure["gui"].Hwnd)
        throw Error("Rehearsal window is hidden; stopped without external input")
    WinGetPos(&x,&y,&w,&h,ctl.Hwnd)
    DeepActivity_Target(Map("x",x,"y",y,"w",w,"h",h),"Stored rehearsal step " . index,250)
    return LearningProcedure_Activate(token)
}

LearningProcedure_Run(args) {
    global g_UPReplaying
    if g_LearningProcedure["busy"]
        throw Error("A learned rehearsal is already running")
    row := LearningProcedure_Get(args["name"]), name := row["name"]
    getFunction := "FanAPI_Workflow"
    stored := %getFunction%("fan_workflow_get",Map("name",name))["workflow"]
    steps := stored["steps"]
    if steps.Length != row["plan"].Length
        throw Error("Saved workflow no longer matches its source plan")
    for index, step in steps {
        expected := TrackJsonEncode(Map("procedure",name,"step",index))
        if step["action"] != "Learned Rehearsal Step" || step["param"] != expected || !step.Get("enabled",true)
            throw Error("Saved workflow was edited; no actions were executed")
    }
    LearningProcedure_Show(row)
    priorReplay := IsSet(g_UPReplaying) ? g_UPReplaying : false
    g_UPReplaying := true, g_LearningProcedure["busy"] := true
    try {
        runFunction := "FanAPI_RunWorkflow"
        result := %runFunction%(name,stored,30)
        result["verified"] := result.Get("ok",false) && g_LearningProcedure["position"] = row["plan"].Length
        result["scope"] := "isolated_fixture_only", result["original_app_verified"] := false
        result["llm_calls"] := 0, result["source_claim"] := row["claim_id"]
        result["observed_tokens"] := g_LearningProcedure["history"].Clone()
        db := LearningProcedure_Schema()
        db.Run("UPDATE learning_procedure SET run_count=run_count+1,last_run=? WHERE name=?",TrackTS(),name)
        db.Run("INSERT INTO learning_procedure_run(name,ts,result) VALUES(?,?,?)",name,TrackTS(),TrackJsonEncode(result))
        return result
    } finally g_UPReplaying := priorReplay, g_LearningProcedure["busy"] := false
}

LearningProcedure_UI(runSaved) {
    try {
        id := g_LearningLab["selected"]
        if runSaved {
            saved := LearningProcedure_Schema().QueryRow("SELECT name FROM learning_procedure WHERE claim_id=? ORDER BY compiled_ts DESC LIMIT 1",id)
            if !saved.Count
                throw Error("Click Save rehearsal once, then Run saved. No code generation is needed.")
            result := LearningProcedure_Run(Map("name",saved["name"]))
            g_LearningLab["status"].Value := "Reused stored workflow: " . result["completed"] . " steps; DeepSeek calls: 0. Original application remains unverified."
        } else {
            result := LearningProcedure_Compile(Map("claim_id",id))
            g_LearningLab["status"].Value := "Saved " . result["name"] . " from evidence #" . result["source_evidence_id"] . ". Click Run saved to reuse it."
        }
    } catch as err
        g_LearningLab["status"].Value := err.Message
}

#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackingDB.ahk
#Include Core\_Gdip.ahk

global DATA_DIR := A_Temp . "\FanProcedure-" . DllCall("GetCurrentProcessId","UInt")
DirCreate(DATA_DIR)
global g_FanDataConfigOverride := DATA_DIR . "\settings.json", MainGui := 0
global g_Sequences := Map(), g_UPReplaying := false, saves := 0, failures := 0
FanData_SaveConfig(Map("learning_validation",false))
Check(value,label) {
    global failures
    if !value
        failures++
    FileAppend((value ? "PASS " : "FAIL ") . label . "`n","*")
}
FanAPI_Workflow(operation,args) {
    global saves
    if operation = "fan_workflow_save" {
        saves++
        g_Sequences[args["name"]] := Map("steps",args["steps"])
        return Map("ok",true)
    }
    return Map("workflow",g_Sequences[args["name"]])
}
FanAPI_RunWorkflow(name,workflow,timeout) {
    completed := 0
    for step in workflow["steps"] {
        if !LearningProcedure_Step(step["param"])
            return Map("ok",false,"completed",completed)
        completed++
    }
    return Map("ok",true,"completed",completed,"name",name)
}
DllCall("SetThreadDpiAwarenessContext","Ptr",-4,"Ptr")
try {
    Check(TrackDB_Init(DATA_DIR . "\fixture.sqlite"),"isolated fixture DB opens")
    LearningLab_Schema()
    TrackDB().Exec("CREATE TABLE usage_element(id INTEGER PRIMARY KEY,name TEXT,role TEXT,pattern TEXT,verified INTEGER,win_id INTEGER DEFAULT 0)")
    TrackDB().Run("INSERT INTO usage_element(id,name,role,pattern,verified) VALUES(1,'recorded region one','click-target','short',0)")
    TrackDB().Run("INSERT INTO usage_element(id,name,role,pattern,verified) VALUES(2,'recorded region two','click-target','short',0)")
    id := LearningLab_Record("Usage sequences","test-chain","Recorded 1 -> 2 -> 1","observed",Map("sequence","CLICK:E1:L > CLICK:E2:L","expected","CLICK:E1:L"),"Synthetic test fixture","fixture:source")
    recipe := LearningProcedure_Compile(Map("claim_id",id))
    Check(recipe["plan"].Length=3 && recipe["plan"][3]["token"]="CLICK:E1:L","compiler preserves recorded order and repetition")
    Check(!recipe["original_app_verified"] && recipe["llm_calls"]=0,"compilation does not invent real-world verification")
    again := LearningProcedure_Compile(Map("claim_id",id))
    Check(again["reused"] && saves=1,"second compile reuses saved workflow without another save")
    active := WinExist("A")
    result := LearningProcedure_Run(Map("name",recipe["name"]))
    Check(result["verified"] && result["completed"]=3,"saved native workflow executes all three local steps")
    Check(result["observed_tokens"][2]="CLICK:E2:L" && result["llm_calls"]=0,"execution trace follows evidence with no model calls")
    Check(WinExist("A")=active,"isolated rehearsal preserves foreground focus")
    Check(LearningLab_Summary(id)["passes"]=0,"fixture success does not reinforce the original application claim")
    Check(InStr(LearningLab_BuildLesson(id)[-1]["text"],recipe["name"]),"lesson explains the actual saved reusable procedure")
    g_Sequences[recipe["name"]]["steps"][1]["action"] := "Send Keys"
    rejected := false
    try LearningProcedure_Run(Map("name",recipe["name"]))
    catch
        rejected := true
    Check(rejected,"edited workflow cannot escape the isolated action whitelist")
} catch as err {
    failures++
    FileAppend("FAIL unhandled: " . err.Message . "`n" . err.Stack . "`n","*")
} finally {
    DeepActivity_Shutdown()
    if IsObject(g_LearningProcedure["gui"])
        g_LearningProcedure["gui"].Destroy()
    TrackDB_Close()
}
ExitApp(failures ? 1 : 0)

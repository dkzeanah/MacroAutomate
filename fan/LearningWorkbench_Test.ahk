#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
#Include ..\lib\TrackSQLite.ahk
#Include ..\lib\TrackUtil.ahk
#Include ..\lib\TrackingDB.ahk
#Include Core\_Gdip.ahk
global passed := 0, failed := 0, DATA_DIR := A_Temp . "\FanEvidence-" . DllCall("GetCurrentProcessId","UInt")
DirCreate(DATA_DIR)
global g_FanDataConfigOverride := DATA_DIR . "\settings.json"
global MainGui := 0
DllCall("SetThreadDpiAwarenessContext","Ptr",-4,"Ptr")
FanData_SaveConfig(Map("learning_validation",false))
Check(ok,label) {
    global passed, failed
    ok ? passed++ : failed++
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
global fixture := 0, restored := 0
try {
    Check(TrackDB_Init(DATA_DIR . "\fixture.sqlite"),"isolated evidence database opens")
    Check(LearningLab_Schema(),"additive evidence schema initializes")
    a := Map("scope","fixture","exe","fixture.exe","size","800x600","dpi",96,"monitor",1)
    b := a.Clone(), b["dpi"] := 144, b["monitor"] := 2
    id := LearningLab_Record("Fixture","same","Fixture pattern","observed",a,"candidate","fixture:1","Inspect fixture")
    Check(id && LearningLab_Summary(id)["passes"] = 0,"observations never become verification")
    Loop 10
        LearningLab_Record("Fixture","same","Fixture pattern","pass",a,"recognition","fixture:1","Inspect fixture")
    s := LearningLab_Summary(id)
    Check(s["observations"] = 11 && s["passes"] = 1,"burst deduplication retains audit but adds one independent check")
    Check(s["state"] = "Tentative verification" && s["strength"] < .5,"one check cannot become supported knowledge")
    ; Synthetic elapsed times and session IDs simulate independent visits.
    Loop 5 {
        TrackDB().Run("UPDATE learning_evidence SET ts='2000-01-01 00:00:00' WHERE claim_id=?",id)
        LearningLab_Record("Fixture","same","Fixture pattern","pass",Mod(A_Index,2) ? a : b,"fresh synthetic check","fixture:1","Inspect fixture")
    }
    TrackDB().Run("UPDATE learning_evidence SET session='other-fixture-session' WHERE claim_id=? AND id=(SELECT MAX(id) FROM learning_evidence WHERE claim_id=?)",id,id)
    Check(LearningLab_Summary(id)["state"] = "Supported in observed contexts","support requires spaced evidence across contexts and sessions")
    before := LearningLab_Summary(id)["passes"]
    Check(InStr(LearningLab_MatchedComparison(id,"dpi","96","144"),"No matched"),"co-varying DPI and monitor remain confounded")
    c := a.Clone(), c["dpi"] := 144
    LearningLab_Record("Fixture","same","Fixture pattern","fail",c,"contradiction","fixture:1","Inspect fixture")
    Check(LearningLab_Summary(id)["state"] = "Contradicted / review","negative checks force review")
    Check(InStr(LearningLab_MatchedComparison(id,"dpi","96","144"),"shared strata"),"single-variable matched context comparison is available")
    Check(InStr(LearningLab_Explain(id),"How you can use it"),"explanation translates evidence into practical use")
    steps := LearningLab_BuildLesson(id)
    Check(steps.Length = 6 && TrackDB().Scalar("SELECT COUNT(*) FROM learning_lesson") = 1,"six-layer executable rehearsal is generated and persisted")
    LearningLab_Replay(id)
    LearningLab_Replay(id)
    Check(TrackDB().Scalar("SELECT COUNT(*) FROM learning_trial") = 2,"replay traverses untested pairs without repeating a pair")
    Loop 5
        permutation := LearningLab_Permutation(id)
    Check(TrackDB().Scalar("SELECT COUNT(*) FROM learning_permutation WHERE claim_id=?",id) = 4,"all four known environment combinations traversed without replacement")
    Check(InStr(permutation,"All 4"),"exhausted traversal stops until environment levels change")
    Check(TrackDB().Scalar("SELECT COUNT(*) FROM learning_permutation WHERE result LIKE 'Evidence needed%'") = 1,"unseen permutation becomes an evidence request, not a fabricated test")
    Check(LearningLab_Summary(id)["passes"] = before,"replay and permutations cannot reinforce their own results")
    LearningLab_Study(7,"answer A","candidate","model","proposal")
    LearningLab_Study(7,"answer A","user-confirmed","review","reference")
    LearningLab_Study(7,"answer B","candidate","model","replacement")
    study := TrackDB().Query("SELECT id FROM learning_claim WHERE source='Study' ORDER BY id")
    Check(study.Length = 2 && LearningLab_Summary(study[2]["id"])["passes"] = 0,"a replacement answer cannot inherit another answer's support")
    active := WinExist("A")
    fixture := Gui("+ToolWindow -Caption -DPIScale +E0x08000020","Evidence window fixture")
    fixture.Add("Text","w250 h40","Synthetic click-through HUD")
    MonitorGetWorkArea(1,&l,&t,&r,&bottom)
    fixture.Show("NA x" . (r-20) . " y" . (bottom-20) . " w300 h90")
    SecondaryWindows_Clamp(fixture.Hwnd)
    WinGetPos(&x,&y,&w,&h,fixture)
    contained := false
    Loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index,&ml,&mt,&mr,&mb)
        if x>=ml && y>=mt && x+w<=mr && y+h<=mb
            contained := true
    }
    Check(contained,"HUD outer bounds fit entirely within one monitor work area")
    SecondaryWindows_Save(fixture.Hwnd)
    restored := Gui("+ToolWindow -Caption -DPIScale +E0x08000020","Evidence window fixture")
    SecondaryWindows_Place(restored,"NA w300 h90")
    WinGetPos(&rx,&ry,,,restored)
    Check(rx=x && ry=y,"saved window position restores")
    Check(WinExist("A") = active,"placement and clamp never activate the HUD")
    TrackDB().Exec("CREATE TABLE usage_transition(id INTEGER PRIMARY KEY,prefix_hash TEXT,prefix_text TEXT,support INTEGER,next_token TEXT,prefix_len INTEGER DEFAULT 2,accepted INTEGER DEFAULT 0)")
    TrackDB().Run("INSERT INTO usage_transition(id,prefix_hash,prefix_text,support,next_token) VALUES(1,'fixture-prefix','APP:fixture > KEY:^s',3,'KEY:{Enter}')")
    LearningLab_CheckPrediction("fixture-prefix","APP:fixture > KEY:^s","KEY:{Escape}")
    pred := TrackDB().QueryRow("SELECT id FROM learning_claim WHERE source='Usage sequences'")
    Check(pred.Count && LearningLab_Summary(pred["id"])["failures"] = 1,"prospective workflow prediction preserves a counterexample before training")
    Check(InStr(LearningLab_BuildLesson(pred["id"])[5]["text"],"APP:fixture > KEY:^s"),"rehearsal contains the actual learned sequence")
    fixture.Destroy(), fixture := 0, restored.Destroy(), restored := 0
    LearningLab_Open()
    LearningLab_Play()
    Check(g_LearningLab["playing"] && g_LearningLab["step"] = 1,"generated lesson runner advances its own mind-map layer")
    LearningLab_Stop()
    Check(!g_LearningLab["playing"],"lesson playback can be stopped immediately")
    Check(WinExist("A") = active,"workbench and lesson playback preserve foreground focus")
    token := Gdip_Startup()
    WinGetPos(&sx,&sy,&sw,&sh,g_LearningLab["gui"])
    image := Gdip_BitmapFromScreen(sx . "|" . sy . "|" . sw . "|" . sh)
    if image {
        Gdip_SaveBitmapToFile(image,A_ScriptDir . "\tests\runtime\LearningWorkbench_Test.png")
        Gdip_DisposeImage(image)
    }
    Gdip_Shutdown(token)
} catch as err {
    Check(false,err.Message . " at " . err.File . ":" . err.Line)
} finally {
    LearningLab_Stop()
    if IsObject(fixture)
        fixture.Destroy()
    if IsObject(restored)
        restored.Destroy()
    if IsObject(g_LearningLab["gui"])
        g_LearningLab["gui"].Destroy()
    TrackDB_Close()
    ; Retain failed fixtures for diagnosis; successful fixtures contain no user data.
    if !failed
        DirDelete(DATA_DIR,true)
}
FileAppend("RESULT " . passed . " passed, " . failed . " failed`n","*")
ExitApp(failed ? 1 : 0)

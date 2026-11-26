; Real controls and isolated SQLite fixture supplied by FanGui_Test.ahk.
LearningChrome_Check(ok, message) {
    global guiFailures
    guiFailures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . message . "`n", "*")
}

LearningChrome_Fit(controls, width, height, label) {
    rects := [], failures := []
    for ctl in controls {
        actual := LearningUI_Rect(ctl)
        x := actual["x"], y := actual["y"], w := actual["w"], h := actual["h"]
        name := ctl.Type . " " . SubStr(ctl.Text,1,28)
        if x < 8 || y < 50 || x+w > width-8 || y+h > height-24 || w <= 0 || h <= 0
            failures.Push(name . " bounds " . x . "," . y . "," . w . "," . h)
        rects.Push(Map("x",x,"y",y,"w",w,"h",h,"name",name))
    }
    for index, a in rects {
        for next, b in rects {
            if next <= index
                continue
            overlapW := Min(a["x"]+a["w"],b["x"]+b["w"])-Max(a["x"],b["x"])
            overlapH := Min(a["y"]+a["h"],b["y"]+b["h"])-Max(a["y"],b["y"])
            if overlapW > 1 && overlapH > 1
                failures.Push(a["name"] . " overlaps " . b["name"])
        }
    }
    LearningChrome_Check(!failures.Length,label . " fits without overlap at " . width . "x" . height)
    for issue in failures
        FileAppend("  " . issue . "`n","*")
}

LearningChrome_Cases() {
    db := TrackDB()
    db.Run("INSERT INTO " . AppMap_AppTable() . "(name,exe,cls,title,learned_ts) VALUES('Fixture app','fixture.exe','FixtureClass','Fixture app',?)",TrackTS())
    appId := db.LastInsertId()
    db.Run("INSERT INTO ui_element(app_id,kind,name,acc_path,x,y,w,h) VALUES(?,'acc','Fixture Save','1.2',1,2,30,20)",appId)
    db.Run("INSERT INTO vs_element(win_id,app_id,x,y,w,h,bin_text,review_state,last_seen) VALUES(0,0,1,2,30,20,'fixture-pattern','certified',?)",TrackTS())
    db.Run("INSERT INTO usage_element(win_id,app_id,signature,name,pattern,last_ts) VALUES(0,0,'fixture','Fixture use','fixture-pattern',?)",TrackTS())
    db.Run("INSERT INTO usage_transition(prefix_hash,prefix_text,prefix_len,next_token,support,last_ts) VALUES('fixture','APP:fixture > KEY:^o',2,'KEY:^s',3,?)",TrackTS())
    db.Run("INSERT INTO vs_sequence(sig,steps,count,length,last_seen) VALUES('fixture','[" . Chr(34) . "win:Fixture" . Chr(34) . "]',4,1,?)",TrackTS())
    LearningHub_Refresh()
    sources := Map(), sequences := 0
    for row in g_LearnHub["allRows"] {
        sources[row["source"]] := true
        sequences += row["source"] = "Sequence" ? 1 : 0
    }
    LearningChrome_Check(sources.Count=4 && sequences=2,"one results collection includes interface, visual, usage and both sequence engines")
    g_LearnHub["ui"]["source"].Choose(2), LearningHub_Filter()
    LearningChrome_Check(g_LearnHub["rows"].Length=1 && g_LearnHub["rows"][1]["source"]="Interface","source filter narrows the shared results without switching tool views")
    g_LearnHub["ui"]["source"].Choose(1)
    g_LearnHub["ui"]["search"].Value := "this-is-not-a-result", LearningHub_Filter()
    LearningChrome_Check(!g_LearnHub["rows"].Length,"shared search excludes unmatched learning results")
    g_LearnHub["ui"]["search"].Value := "", LearningHub_Filter()
    for size in [[860,760],[884,780],[1040,780],[1500,950]] {
        LearningHub_Layout(size[1],size[2]), ChromeLearning_Layout(size[1],size[2])
        LearningChrome_Fit(g_LearnHub["controls"],size[1],size[2],"real Learning workspace")
        LearningChrome_Fit(g_ChromeLearn["controls"],size[1],size[2],"real Chrome workspace")
    }
    FanNav_Open(16), learnedHandle := g_LearnHub["ui"]["results"].Hwnd
    FanNav_Open(17)
    LearningChrome_Check(TabCtrl.Value=14 && g_LearnHub["ui"]["results"].Hwnd=learnedHandle,"legacy learner routes share the same real controls, not hidden alternate views")
    LearningChrome_ContextCases()
}

LearningChrome_ContextCases() {
    db := TrackDB(), priorTarget := g_ChromeLearn["target"]
    first := Map("context_id","fixture-window-A","hwnd",123,"pid",1,"title","Fixture Work page","profile_label","Work","profile_source","user_assigned","url","","url_title","")
    second := Map("context_id","fixture-window-B","hwnd",456,"pid",1,"title","Fixture Personal page","profile_label","Personal","profile_source","user_assigned","url","","url_title","")
    g_ChromeLearn["target"] := second
    ChromeLearning_Captured(first,Map("ok",true,"page_id","fixture-page-A","title","Fixture Work page","url","https://example.test/work"))
    LearningChrome_Check(!g_ChromeLearn["job"].Count && db.Scalar("SELECT context_id FROM chrome_learning_capture WHERE page_id='fixture-page-A'")="fixture-window-A","an asynchronous capture remains bound to its original window after selection changes")
    g_ChromeLearn["ui"]["scope"].Choose(1), ChromeLearning_LoadCaptures()
    LearningChrome_Check(!g_ChromeLearn["captures"].Length,"another window does not inherit the first window's capture")
    g_ChromeLearn["ui"]["scope"].Choose(2), ChromeLearning_LoadCaptures()
    LearningChrome_Check(g_ChromeLearn["captures"].Length=1 && g_ChromeLearn["capture"]["profile_label"]="Work","history retains original profile attribution across window sessions")
    g_ChromeLearn["elements"] := [Map("element_id","fixture","description","Photosynthesis uses light energy.","ocr_text","Observed science source.")]
    list := g_ChromeLearn["ui"]["elements"]
    list.Add(,"text","Fixture science evidence","document")
    g_ChromeLearn["job"] := Map("fixture",true)
    list.Modify(1,"Select")
    ChromeLearning_Verify()
    LearningChrome_Check(InStr(g_ChromeLearn["ui"]["status"].Value,"another window session"),"live verification refuses a capture from a different window session")
    before := db.Scalar("SELECT COUNT(*) FROM study_source")
    ChromeLearning_Import()
    imported := db.QueryRow("SELECT s.title,s.topic,(SELECT GROUP_CONCAT(text,char(10)) FROM study_passage WHERE source_id=s.id) AS text FROM study_source s ORDER BY s.id DESC LIMIT 1")
    LearningChrome_Check(db.Scalar("SELECT COUNT(*) FROM study_source")=before+1 && imported["topic"]="Work"
        && InStr(imported["text"],"https://example.test/work") && !InStr(imported["title"],"Personal"),"Study import uses the captured page's profile and URL, not the currently selected window")
    list.Modify(0,"-Select"), g_ChromeLearn["job"] := Map()
    g_ChromeLearn["contexts"]["123"] := first
    ChromeLearning_WindowDestroyed(0,0x8001,123,0,0,0,0)
    LearningChrome_Check(first.Get("closed",false) && !g_ChromeLearn["contexts"].Has("123"),"destroyed windows invalidate session identity before an HWND can be reused")
    g_ChromeLearn["target"] := priorTarget
}

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
    LearningChrome_ProfileCases()
}

LearningChrome_ContextCases() {
    db := TrackDB(), priorTarget := g_ChromeLearn["target"]
    first := Map("context_id","fixture-window-A","hwnd",123,"pid",1,"title","Fixture Work page","profile_label","Work","profile_id","chrome:fixture-work","profile_source","window_relaunch","url","","url_title","")
    second := Map("context_id","fixture-window-B","hwnd",456,"pid",1,"title","Fixture Personal page","profile_label","Personal","profile_id","chrome:fixture-personal","profile_source","window_relaunch","url","","url_title","")
    g_ChromeLearn["target"] := second
    ChromeLearning_Captured(first,Map("ok",true,"page_id","fixture-page-A","title","Fixture Work page","url","https://example.test/work"))
    LearningChrome_Check(!g_ChromeLearn["job"].Count && db.Scalar("SELECT context_id FROM chrome_learning_capture WHERE page_id='fixture-page-A'")="fixture-window-A","an asynchronous capture remains bound to its original window after selection changes")
    g_ChromeLearn["ui"]["scope"].Choose(1), ChromeLearning_LoadCaptures()
    LearningChrome_Check(!g_ChromeLearn["captures"].Length,"another window does not inherit the first window's capture")
    g_ChromeLearn["ui"]["scope"].Choose(2), ChromeLearning_LoadCaptures()
    LearningChrome_Check(!g_ChromeLearn["captures"].Length,"current profile excludes another profile's captures")
    g_ChromeLearn["ui"]["scope"].Choose(3), ChromeLearning_LoadCaptures()
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

LearningChrome_SetWindowProperty(hwnd, propertyId, text) {
    iid := Buffer(16), key := Buffer(20), value := Buffer(24,0), store := 0
    DllCall("ole32\CLSIDFromString","WStr","{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}","Ptr",iid)
    DllCall("ole32\CLSIDFromString","WStr","{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}","Ptr",key)
    NumPut("UInt",propertyId,key,16), NumPut("UShort",31,value,0), NumPut("Ptr",StrPtr(text),value,8)
    DllCall("shell32\SHGetPropertyStoreForWindow","Ptr",hwnd,"Ptr",iid,"Ptr*",&store)
    try ComCall(6,store,"Ptr",key,"Ptr",value)
    finally ObjRelease(store)
}

LearningChrome_ProfileCases() {
    global g_UPRecentEvents, g_UPMinSupport, g_UPMinConfidence, g_UPPrediction, g_UPPredictionSignature
    root := A_Temp . "\FanProfileFixtures-" . DllCall("GetCurrentProcessId","UInt")
    DirCreate(root . "\Default"), DirCreate(root . "\Profile 1")
    Track_WriteFile(root . "\Local State",TrackJsonEncode(Map("profile",Map("info_cache",Map("Default",Map("name","Same name"),"Profile 1",Map("name","Same name"))))))
    first := Gui(), second := Gui(), third := Gui()
    for index, window in [first,second,third] {
        dir := index=2 ? "Profile 1" : "Default"
        LearningChrome_SetWindowProperty(window.Hwnd,2,'"chrome.exe" --user-data-dir="' . root . '" --profile-directory="' . dir . '"')
    }
    a := ChromeProfiles_Detect(first.Hwnd), b := ChromeProfiles_Detect(second.Hwnd), c := ChromeProfiles_Detect(third.Hwnd)
    LearningChrome_Check(a["profile_source"]="window_relaunch" && a["profile_label"]="Same name","automatic detection reads native per-window identity and local profile display name")
    LearningChrome_Check(a["profile_id"]!=b["profile_id"] && a["profile_id"]=c["profile_id"],"duplicate display names stay distinct; two windows of one profile share a stable profile identity")
    session := ChromeProfiles_WindowSession(first.Hwnd)
    LearningChrome_Check(session=ChromeProfiles_WindowSession(first.Hwnd) && session!=ChromeProfiles_WindowSession(third.Hwnd),"window identities persist on the native window and separate same-profile windows")
    profiles := Map("Profile 1",Map(),"Profile1",Map())
    LearningChrome_Check(ChromeProfiles_Match("Chrome.UserData.Profile1","","C:\User Data",profiles)="","ambiguous sanitized profile identities are refused")
    LearningChrome_Check(ChromeProfiles_Match("Chrome.UserData.Profile2","","C:\User Data",Map("Profile 2",Map()))="Profile 2","unique Chromium taskbar profile identity supports the no-relaunch fallback")
    LearningChrome_Check(ChromeProfiles_Match("Chrome",'chrome.exe --profile-directory="..\Other"',root,Map())="","profile directory traversal is refused")
    identA := TrackDB_ResolveWindow("Same browser title","Chrome_WidgetWin_1","chrome.exe",false,first.Hwnd)
    identB := TrackDB_ResolveWindow("Same browser title","Chrome_WidgetWin_1","chrome.exe",false,second.Hwnd)
    identC := TrackDB_ResolveWindow("Same browser title","Chrome_WidgetWin_1","chrome.exe",false,third.Hwnd)
    LearningChrome_Check(identA["app_id"]!=identB["app_id"] && identA["win_id"]!=identC["win_id"],"shared tracking identity isolates different profiles and same-profile windows with identical titles")
    for window in [first,second,third] {
        ctx := Map("exe","chrome.exe","class","Chrome_WidgetWin_1","hwnd",window.Hwnd,"title","Same browser title","x",0,"y",0,"w",800,"h",600)
        AutoDiscovery_SaveAppTarget(ctx,"1.2","Save","button","",{x:10,y:10,w:20,h:20})
    }
    LearningChrome_Check(TrackDB().Scalar("SELECT COUNT(DISTINCT learning_scope) FROM " . AppMap_AppTable() . " WHERE title='Same browser title'")=3,"passive interface discovery creates three separate maps for three Chrome windows")
    desktopCtx := Map("exe","fixture-desktop.exe","class","FixtureDesktop","hwnd",0,"title","Desktop fixture","x",0,"y",0,"w",800,"h",600)
    Loop 2
        AutoDiscovery_SaveAppTarget(desktopCtx,"1.2","Save","button","",{x:10,y:10,w:20,h:20})
    LearningChrome_Check(TrackDB().Scalar("SELECT COUNT(*) FROM " . AppMap_AppTable() . " WHERE exe='fixture-desktop.exe'")=1,"unscoped desktop discovery reuses its existing map with SQLite NULL bindings")
    scopeA := ChromeProfiles_TrackingScope(first.Hwnd)["key"]
    appA := TrackDB().QueryRow("SELECT * FROM " . AppMap_AppTable() . " WHERE learning_scope=?",scopeA)
    LearningChrome_Check(AppMap_LiveHwnd(appA)=0,"fixture windows cannot resolve as real Chrome automation targets")
    g_UPRecentEvents := [], g_UPPrediction := [], g_UPPredictionSignature := ""
    ctxA := Map("exe","chrome.exe","app_id",identA["app_id"],"win_id",identA["win_id"])
    ctxB := Map("exe","chrome.exe","app_id",identB["app_id"],"win_id",identB["win_id"])
    for token in ["KEY:^o","KEY:^s","KEY:Enter"]
        UsagePredictor_RecordEvent("KEY",token,Map(),ctxA)
    UsagePredictor_RecordEvent("KEY","KEY:^o",Map(),ctxB)
    LearningChrome_Check(g_UPRecentEvents.Length=1,"switching Chrome profile/window resets the active sequence context")
    LearningChrome_Check(TrackDB().Scalar("SELECT COUNT(*) FROM usage_transition WHERE prefix_hash=?",TrackHash("chrome-window:" . identA["app_id"] . "|KEY:^o > KEY:^s"))=1,"learned key-only sequences include the originating Chrome window scope")
    LearningChrome_Check(!UsagePredictor_ReplayAction(Map("kind","KEY","data",Map("learning_scope","chrome-window:impossible","key","^s"))),"prediction replay refuses a different active Chrome window before sending input")
    for window in [first,second,third]
        window.Destroy()
}

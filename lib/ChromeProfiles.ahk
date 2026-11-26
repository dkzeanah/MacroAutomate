; Read-only window identity. Never infer a profile from a shared PID or title.
; Chromium shell_integration_win.cc: GetProfileIdFromPath / GetAppUserModelIdImpl.
ChromeProfiles_WindowProperty(hwnd, propertyId := 5) {
    iid := Buffer(16), key := Buffer(20), value := Buffer(24,0), store := 0
    DllCall("ole32\CLSIDFromString","WStr","{886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99}","Ptr",iid)
    DllCall("ole32\CLSIDFromString","WStr","{9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3}","Ptr",key)
    NumPut("UInt",propertyId,key,16)
    if DllCall("shell32\SHGetPropertyStoreForWindow","Ptr",hwnd,"Ptr",iid,"Ptr*",&store,"Int") < 0
        return ""
    try {
        ComCall(5,store,"Ptr",key,"Ptr",value)
        return NumGet(value,0,"UShort") = 31 && NumGet(value,8,"Ptr") ? StrGet(NumGet(value,8,"Ptr")) : ""
    } finally {
        DllCall("ole32\PropVariantClear","Ptr",value)
        ObjRelease(store)
    }
}

ChromeProfiles_Switch(command, name) {
    count := 0, argv := DllCall("shell32\CommandLineToArgvW","WStr",command,"Int*",&count,"Ptr")
    if !argv
        return ""
    try {
        Loop count {
            arg := StrGet(NumGet(argv,(A_Index-1)*A_PtrSize,"Ptr"))
            if InStr(arg,"--" . name . "=") = 1
                return SubStr(arg,StrLen(name)+4)
            if arg = "--" . name && A_Index < count
                return StrGet(NumGet(argv,A_Index*A_PtrSize,"Ptr"))
        }
        return ""
    } finally DllCall("LocalFree","Ptr",argv)
}

ChromeProfiles_Path(path) {
    buf := Buffer(65536)
    if !DllCall("GetFullPathNameW","WStr",path,"UInt",32768,"Ptr",buf,"Ptr",0)
        return ""
    return RTrim(StrGet(buf),"\")
}

ChromeProfiles_Root(hwnd, relaunch) {
    static cache := Map()
    pid := WinGetPID(hwnd), exe := WinGetProcessPath(hwnd), root := ChromeProfiles_Switch(relaunch,"user-data-dir")
    if root != ""
        return ChromeProfiles_Path(root)
    ; Only the process's user-data ROOT is useful; its --profile-directory is
    ; deliberately ignored because one browser process can own several profiles.
    if cache.Has(pid) && A_TickCount-cache[pid]["tick"] < 30000
        return cache[pid]["root"]
    try {
        service := ComObjGet("winmgmts:")
        for process in service.ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" . pid)
            root := ChromeProfiles_Switch(process.CommandLine,"user-data-dir")
    }
    for hive in ["HKLM", "HKCU"] {
        try {
            policy := RegRead(hive . "\Software\Policies\Google\Chrome","UserDataDir")
            policy := StrReplace(StrReplace(policy,"${local_app_data}",EnvGet("LOCALAPPDATA")),"${profile}",EnvGet("USERPROFILE"))
            if policy != ""
                root := policy
        }
    }
    if root = "" {
        channel := InStr(exe,"Chrome Beta") ? "Chrome Beta" : InStr(exe,"Chrome Dev") ? "Chrome Dev" : InStr(exe,"Chrome SxS") ? "Chrome SxS" : "Chrome"
        root := EnvGet("LOCALAPPDATA") . "\Google\" . channel . "\User Data"
    }
    root := ChromeProfiles_Path(root)
    cache[pid] := Map("root",root,"tick",A_TickCount)
    return root
}

ChromeProfiles_Catalog(root) {
    static cache := Map()
    path := root . "\Local State", stamp := ""
    try stamp := FileGetTime(path,"M") . ":" . FileGetSize(path)
    if cache.Has(root) && cache[root]["stamp"] = stamp && A_TickCount-cache[root]["tick"] < 30000
        return cache[root]["profiles"]
    profiles := Map()
    try profiles := TrackJsonDecode(FileRead(path,"UTF-8"))["profile"]["info_cache"]
    cache[root] := Map("stamp",stamp,"profiles",profiles,"tick",A_TickCount)
    return profiles
}

ChromeProfiles_Match(appId, command, root, profiles) {
    directory := ChromeProfiles_Switch(command,"profile-directory")
    if directory != "" {
        ; Accept only one immediate profile directory, never an arbitrary path.
        if directory = "." || directory = ".." || RegExMatch(directory,'[\\/:]')
            return ""
        return directory
    }
    ; Older Chrome windows may expose only the taskbar AppUserModelID.
    ; Match the exact sanitized Chromium suffix, and refuse collisions.
    SplitPath(root,&base)
    matches := []
    for dir, info in profiles {
        suffix := RegExReplace(base . "." . dir,"[^a-zA-Z0-9.]","")
        if (dir = "Default" && RegExMatch(appId,"^Chrome(?:Beta|Dev|Canary)?(?:\.[A-Z0-9]+)?$"))
            || (appId != "" && SubStr(appId,-StrLen(suffix)-1) = "." . suffix)
            matches.Push(dir)
    }
    return matches.Length = 1 ? matches[1] : ""
}

ChromeProfiles_Detect(hwnd) {
    result := Map("profile_id","","profile_label","Profile unavailable","profile_source","unavailable","profile_path","","app_user_model_id","")
    try {
        command := ChromeProfiles_WindowProperty(hwnd,2), appId := ChromeProfiles_WindowProperty(hwnd)
        root := ChromeProfiles_Root(hwnd,command), profiles := ChromeProfiles_Catalog(root)
        directory := ChromeProfiles_Match(appId,command,root,profiles)
        result["app_user_model_id"] := appId
        if directory = "" || !DirExist(root . "\" . directory)
            return result
        path := ChromeProfiles_Path(root . "\" . directory)
        info := profiles.Get(directory,Map())
        result["profile_id"] := "chrome:" . StrLower(path)
        result["profile_path"] := path
        result["profile_label"] := info.Get("name",directory)
        result["profile_source"] := ChromeProfiles_Switch(command,"profile-directory") != "" ? "window_relaunch" : "window_app_id"
    }
    return result
}

ChromeProfiles_WindowSession(hwnd) {
    ; An integer window property survives Fan reloads; Windows removes it when
    ; Chrome destroys the window. No foreign-process pointer or title heuristic.
    name := "Fan.ChromeLearning.WindowSession.v1"
    token := DllCall("GetPropW","Ptr",hwnd,"WStr",name,"Ptr")
    if !token {
        tokenBytes := Buffer(4)
        DllCall("bcrypt\BCryptGenRandom","Ptr",0,"Ptr",tokenBytes,"UInt",4,"UInt",2)
        token := NumGet(tokenBytes,0,"UInt") | 1
        if !DllCall("SetPropW","Ptr",hwnd,"WStr",name,"Ptr",token)
            return "chrome-" . hwnd . "-" . A_Now . "-" . A_TickCount
    }
    return "chrome-" . WinGetPID(hwnd) . "-" . hwnd . "-" . token
}

ChromeProfiles_TrackingScope(hwnd) {
    static cache := Map()
    session := ChromeProfiles_WindowSession(hwnd)
    if !cache.Has(session) || A_TickCount-cache[session]["tick"] >= 10000 {
        profile := ChromeProfiles_Detect(hwnd)
        cache[session] := Map("tick",A_TickCount,"key",profile["profile_id"] . "|" . session,"label",profile["profile_label"])
    }
    return cache[session]
}

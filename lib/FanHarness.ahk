; Process boundary only. Atlas owns its Python UI, database and runtime.
FanHarness_Root() => FanData_ProjectRoot() . "\fan\harness"

FanHarness_Open(tab := "index", query := "",*) {
    root := FanHarness_Root(), python := root . "\.venv\Scripts\pythonw.exe"
    if !FileExist(python)
        throw Error("The Python Atlas runtime is missing")
    ; UTF-8 hex avoids shell/command-line quoting of a user's search text.
    bytes := Buffer(StrPut(query,"UTF-8")), encoded := ""
    StrPut(query,bytes,"UTF-8")
    loop bytes.Size-1
        encoded .= Format("{:02x}",NumGet(bytes,A_Index-1,"UChar"))
    Run('"' . python . '" "' . root . '\launch_studio.py" --tab ' . tab . (encoded != "" ? ' --query-hex ' . encoded : ""),root,"Hide")
}

FanHarness_Present(args) {
    FanHarness_Open("index",args.Get("query",""))
    return Map("ok",true,"launched",true,"scope","separate_python_application","workspace",FanHarness_Root(),"llm_calls",0)
}

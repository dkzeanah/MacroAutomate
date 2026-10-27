#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\..\..\lib\DeepSeekActivity.ahk
#Include ..\..\..\lib\FanBridgeJson.ahk
#Include ..\..\..\lib\BoundWindow.ahk
Persistent
OnExit(DeepActivity_Shutdown)
DllCall("SetThreadDpiAwarenessContext", "Ptr", -4, "Ptr")

; The worker handles ONLY pre-registered commands. It does not eval AI-supplied code.
SetWorkingDir A_ScriptDir "\.."
EnvPath := A_ScriptDir "\..\.env"
Config := ReadEnv(EnvPath)
if !Config.Has('BRIDGE_TOKEN') || !Config['BRIDGE_TOKEN'] {
    MsgBox 'Run python setup.py first (missing BRIDGE_TOKEN).'
    ExitApp
}
BridgeToken := Config['BRIDGE_TOKEN']
BridgeBase := 'http://127.0.0.1:' (Config.Has('BRIDGE_PORT') ? Config['BRIDGE_PORT'] : '8765')
SetTitleMatchMode 2
SetTimer PollGateway, 350

; Ctrl+Alt+J sends a natural-language task to the agent daemon.
^!j:: {
    response := InputBox('Send a task to the DeepSeek agent:', 'DeepSeek Agent Task', 'w550 h160')
    if response.Result != 'OK' || !response.Value
        return
    try {
        result := Http('POST', '/tasks', '{"prompt":"' JsonEscape(response.Value) '"}', 'application/json')
        MsgBox 'Task queued. Check status using the task ID in the gateway SQLite database.`n' result
    } catch as err {
        MsgBox 'Could not queue task: ' err.Message
    }
}

; Ctrl+Alt+Shift+J shows worker identity and status.
^!+j::MsgBox('AHK worker running at ' BridgeBase)

PollGateway() {
    static busy := false
    if busy
        return
    busy := true
    try {
        response := Http('GET', '/worker/next')
        if response = 'NONE'
            return
        lines := StrSplit(StrReplace(response, '`r', ''), '`n')
        if lines.Length < 3
            return
        id := lines[1]
        tool := lines[2]
        arg := (lines[3] = '-' ? '' : UrlDecode(lines[3]))
        try DeepActivity_Before(tool, arg)
        result := ExecuteTool(tool, arg)
        ; Show the actual input target, after the operation has executed.
        if InStr(result, '{"ok":true') = 1
            try DeepActivity_Input(tool, arg)
        Http('POST', '/worker/result', 'id=' UrlEncode(id) '&result=' UrlEncode(result), 'application/x-www-form-urlencoded')
    } catch as err {
        ; Worker continues polling even if gateway temporarily disconnects.
        OutputDebug 'DeepSeek AHK Worker: ' err.Message
    } finally {
        busy := false
    }
}

ExecuteTool(name, arg) {
    try {
        target := Map()
        if SubStr(arg,1,7)="@BOUND@" {
            envelope := FanBridgeJsonDecode(SubStr(arg,8)), arg := envelope["value"], waited := false
            loop {
                if DateDiff(A_NowUTC,"19700101000000","Seconds")>=envelope["deadline"]
                    throw Error("Action deadline elapsed; no delayed input was issued")
                task := envelope.Get("task_id","")
                state := task!="" ? FanBridgeJsonDecode(Http("GET","/tasks/" . task)) : Map("status","running")
                if state["status"]!="running"
                    throw Error("Task stopped before its action")
                if !state.Get("paused",false)
                    break
                waited := true, Sleep(200)
            }
            if waited && (name="mouse_click" || name="mouse_move")
                throw Error("Paused coordinate observation requires a fresh locator before input")
            target := envelope.Get("target_window",Map())
            if target.Get("hwnd",0) {
                actual := BoundWindow_Prepare(target["hwnd"],target,task)
                if name="mouse_click" || name="mouse_move"
                    for key,value in target.Get("window_rect",Map())
                        if actual["window_rect"].Get(key,"")!=value
                            throw Error("Assigned window moved; capture a fresh locator before coordinate input")
            }
        }
        switch name {
            case 'window_list':
                result := '['
                for hwnd in WinGetList() {
                    title := WinGetTitle('ahk_id ' hwnd)
                    if !title
                        continue
                    if result != '['
                        result .= ','
                    result .= '{"hwnd":' hwnd ',"title":"' JsonEscape(title) '"}'
                }
                return '{"ok":true,"windows":' result '],"count":' (result = '[' ? 0 : StrSplit(result, '"hwnd"').Length-1) '}'
            case 'window_active':
                hwnd := WinExist('A')
                if !hwnd
                    return '{"ok":false,"error":"No foreground window"}'
                return '{"ok":true,"hwnd":' hwnd ',"title":"' JsonEscape(WinGetTitle('ahk_id ' hwnd)) '"}'
            case 'window_activate':
                matches := WinGetList(arg)
                if !matches.Length
                    return '{"ok":false,"error":"Window not found"}'
                if matches.Length!=1
                    return '{"ok":false,"error":"Multiple windows match; supply a unique observed target"}'
                actual := BoundWindow_Prepare(matches[1],Map(),IsSet(task) ? task : "")
                return FanBridgeJsonEncode(Map("ok",true,"hwnd",matches[1],"target_window",actual))
            case 'mouse_move':
                coordinates := StrSplit(arg, ',')
                CoordMode 'Mouse', 'Screen'
                MouseMove Integer(coordinates[1]), Integer(coordinates[2]), 0
                return FanBridgeJsonEncode(Map("ok",true,"target_window",target))
            case 'mouse_click':
                coordinates := StrSplit(arg, ',')
                CoordMode 'Mouse', 'Screen'
                Click Integer(coordinates[1]), Integer(coordinates[2])
                return FanBridgeJsonEncode(Map("ok",true,"target_window",target))
            case 'text_type':
                ; Never type into windows running elevated from this standard worker.
                if !WinExist('A')
                    return '{"ok":false,"error":"No active window"}'
                SendText arg
                return FanBridgeJsonEncode(Map("ok",true,"characters",StrLen(arg),"target_window",target))
            case 'key_send':
                if !WinExist('A')
                    return '{"ok":false,"error":"No active window"}'
                Send arg
                return FanBridgeJsonEncode(Map("ok",true,"target_window",target))
            default:
                return '{"ok":false,"error":"Tool not registered"}'
        }
    } catch as err {
        return '{"ok":false,"error":"' JsonEscape(err.Message) '"}'
    }
}

Http(method, route, body := '', contentType := '') {
    global BridgeBase, BridgeToken
    request := ComObject('WinHttp.WinHttpRequest.5.1')
    request.SetProxy(1)
    request.SetTimeouts(1000, 1000, 2000, 3000)
    request.Open(method, BridgeBase route, false)
    request.SetRequestHeader('X-Bridge-Token', BridgeToken)
    if contentType
        request.SetRequestHeader('Content-Type', contentType)
    request.Send(body)
    if request.Status < 200 || request.Status >= 300
        throw Error('HTTP ' request.Status ': ' request.ResponseText)
    return request.ResponseText
}

ReadEnv(path) {
    result := Map()
    for line in StrSplit(FileRead(path, 'UTF-8'), '`n', '`r') {
        line := Trim(line)
        if !line || SubStr(line, 1, 1) = '#'
            continue
        position := InStr(line, '=')
        if position > 0
            result[Trim(SubStr(line, 1, position - 1))] := Trim(SubStr(line, position + 1))
    }
    return result
}

JsonEscape(value) {
    value := StrReplace(value, '\', '\\')
    value := StrReplace(value, '"', '\"')
    value := StrReplace(value, '`r', '\r')
    value := StrReplace(value, '`n', '\n')
    value := StrReplace(value, '`t', '\t')
    return value
}

UrlEncode(value) {
    size := StrPut(value, 'UTF-8')
    buf := Buffer(size, 0)
    StrPut(value, buf, 'UTF-8')
    out := ''
    Loop size - 1 {
        byte := NumGet(buf, A_Index - 1, 'UChar')
        if (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57) || InStr('-_.~', Chr(byte))
            out .= Chr(byte)
        else
            out .= Format('%{:02X}', byte)
    }
    return out
}

UrlDecode(value) {
    buf := Buffer(StrLen(value) + 1, 0)
    i := 1, n := 0
    while i <= StrLen(value) {
        char := SubStr(value, i, 1)
        if char = '%' && i + 2 <= StrLen(value) {
            byte := Integer('0x' SubStr(value, i + 1, 2))
            i += 3
        } else {
            byte := Ord(char)
            i += 1
        }
        NumPut('UChar', byte, buf, n)
        n += 1
    }
    return StrGet(buf, n, 'UTF-8')
}

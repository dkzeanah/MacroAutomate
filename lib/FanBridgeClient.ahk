; Include this library in generated AHK v2 scripts to call the running Fan app.
; It contains no GUI/trackers/startup code from MacroAutomator.ahk.
#Requires AutoHotkey v2.0
#Include %A_LineFile%\..\FanBridgeJson.ahk
SplitPath(A_LineFile,, &g_FanSdkDir)
global g_FanSdkBridgeRoot := g_FanSdkDir . "\..\fan\DeepSeekBridge"

class FanBridge {
    static Root := g_FanSdkBridgeRoot

    static Call(tool, args := 0, timeoutMs := 45000) {
        if tool = "fan_taskbar_learn" || tool = "fan_taskbar_open"
            timeoutMs := Max(timeoutMs,tool = "fan_taskbar_learn" ? 270000 : 110000)
        config := Map()
        for line in StrSplit(FileRead(this.Root . "\.env", "UTF-8"), "`n", "`r") {
            at := InStr(line, "=")
            if at > 1
                config[Trim(SubStr(line, 1, at-1))] := Trim(SubStr(line, at+1))
        }
        if !config.Has("BRIDGE_TOKEN")
            throw Error("Fan Bridge configuration is missing. Start Macro Automator first.")
        if !RegExMatch(tool, "^(fan|daa)_[a-z_]+$")
            throw Error("Use a tool name from FanBridge.Capabilities().")
        started := A_TickCount, waited := false
        loop {
        request := ComObject("WinHttp.WinHttpRequest.5.1")
        request.SetProxy(1)
        request.SetTimeouts(1000, 1000, 3000, Max(1000, Min(timeoutMs, 310000)))
        request.Open("POST", "http://127.0.0.1:" . config.Get("BRIDGE_PORT", "8765") . "/tools/" . tool, false)
        request.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        request.SetRequestHeader("X-Bridge-Token", config["BRIDGE_TOKEN"])
        task := EnvGet("FAN_BRIDGE_TASK_ID")
        if task != ""
            request.SetRequestHeader("X-Bridge-Task", task)
        run := EnvGet("FAN_BRIDGE_RUN_ID")
        if run != ""
            request.SetRequestHeader("X-Bridge-Run", run)
        request.SetRequestHeader("X-Bridge-Origin", "ahk")
        if parent := EnvGet("FAN_BRIDGE_CHAIN_PARENT")
            request.SetRequestHeader("X-Bridge-Parent", parent)
        request.Send(FanBridgeJsonEncode(IsObject(args) ? args : Map()))
        result := FanBridgeJsonDecode(request.ResponseText)
        if request.Status < 200 || request.Status >= 300
            throw Error("Fan Bridge HTTP " . request.Status . ": " . result.Get("detail", "request failed"))
        if result.Get("paused",false) {
            if A_TickCount-started>=timeoutMs
                throw Error("Automation time budget reached while paused; next action was not issued")
            waited := true, Sleep(250)
            continue
        }
        if waited && tool="daa_trace" && IsObject(args) && args.Get("phase","")="before" && args.Has("x")
            throw Error("Resumed after coordinate observation; capture the target again before issuing input")
        return result
        }
    }

    static Capabilities() => this.Call("fan_capabilities")
    static PrepareWindow(hwnd) => this.Call("fan_window_prepare",Map("hwnd",hwnd))
    static Unit(name, inputs := 0) => this.Call("daa_unit_run",Map("name",name,"inputs",IsObject(inputs) ? inputs : Map()),300000)
    static Trace(label, hwnd := 0, phase := "before", point := 0) {
        args := Map("label",label,"hwnd",hwnd,"phase",phase)
        if IsObject(point)
            args["x"] := point["x"], args["y"] := point["y"]
        return this.Call("daa_trace",args)
    }
    static Insights(query := "", limit := 20) => this.Call("fan_learning_insights", Map("query", query, "limit", limit))
    static DiscoveredTargets(query := "", limit := 30) => this.Call("fan_discovered_targets", Map("query", query, "limit", limit))
    static Inspect(hwnd := 0, image := true) => this.Call("fan_window_inspect", Map("hwnd", hwnd, "include_image", image, "grid", true))
    static LearnPage(hwnd := 0, refresh := false) => this.Call("fan_page_learn", Map("hwnd", hwnd, "refresh", refresh), 155000)
    static PageElements(pageId, query := "", offset := 0) => this.Call("fan_page_get", Map("page_id", pageId, "query", query, "offset", offset))
    static ResolvePageElement(pageId, elementId, hwnd := 0) => this.Call("fan_page_resolve", Map("page_id", pageId, "element_id", elementId, "hwnd", hwnd), 60000)
    static PageImage(pageId, elementId := "") => this.Call("fan_page_image", Map("page_id", pageId, "element_id", elementId))
    static OCR(hwnd := 0, region := 0) {
        args := Map("hwnd", hwnd)
        if IsObject(region)
            args["region"] := region
        return this.Call("fan_ocr", args)
    }
    static FindPattern(name, hwnd := 0, region := 0) {
        args := Map("name", name, "hwnd", hwnd)
        if IsObject(region)
            args["region"] := region
        return this.Call("fan_pattern_search", args)
    }
    static LearnPattern(name, region, hwnd := 0, description := "") => this.Call("fan_pattern_capture", Map("name", name, "region", region, "hwnd", hwnd, "description", description))
    static SaveWorkflow(name, steps, overwrite := false) => this.Call("fan_workflow_save", Map("name", name, "steps", steps, "overwrite", overwrite))
    static RunWorkflow(name, timeoutSeconds := 120) => this.Call("fan_workflow_run", Map("name", name, "timeout_seconds", timeoutSeconds), timeoutSeconds*1000+10000)
}

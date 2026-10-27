; ═══════════════════════════════════════════════════════════════════════════════
; AutoPilot.ahk — DeepSeek-driven daily autonomy orchestrator (AutoHotkey v2)
; ═══════════════════════════════════════════════════════════════════════════════
; A standalone companion that layers a self-discovering, DeepSeek-planned
; "act as me" loop on top of a running Macro Automator (fan\MacroAutomator.ahk).
; It is deliberately a *client*: it plans via the DeepSeek Bridge agent and
; executes only the bounded, already-verified primitives the running app
; exposes through the Fan API. It never injects input the app would not allow.
;
; Run the main app first:  AutoHotkey64.exe fan\MacroAutomator.ahk
; Then drive the day from here:
;
;   AutoPilot.ahk --probe                 machine + bridge facts (JSON)
;   AutoPilot.ahk --report                probe + deduced settings (JSON)
;   AutoPilot.ahk --apply                 push safe deduced workflow settings
;   AutoPilot.ahk --ask "<question>"      one prompt to the DeepSeek agent
;   AutoPilot.ahk --plan "<today's goal>" build + save a DeepSeek day plan
;   AutoPilot.ahk --run                   execute the saved plan (guarded)
;   AutoPilot.ahk --loop <seconds>        periodic re-probe/plan/run (all day)
;   AutoPilot.ahk --self-test             reachability + deduction self-check
;
; Hotkeys while resident (--loop/--run): Ctrl+Alt+Shift+X abort, F1 status.
; ═══════════════════════════════════════════════════════════════════════════════
#Requires AutoHotkey v2.0
#SingleInstance Force
SetWorkingDir(A_ScriptDir)
#Include %A_ScriptDir%\lib\AutoConfig.ahk

global g_AutoPilotAbort := false
global g_AutoPilotPlanDir := A_ScriptDir . "\data\autopilot"
global g_AutoPilotPlanFile := g_AutoPilotPlanDir . "\plan.json"
global g_AutoPilotRunLog := g_AutoPilotPlanDir . "\run_log.jsonl"

AutoPilot_Abort(*) {
    global g_AutoPilotAbort
    g_AutoPilotAbort := true
}
^!+x::AutoPilot_Abort()
F1::AutoPilot_Status()

AutoPilot_Main()

AutoPilot_Main() {
    args := A_Args
    if !args.Length {
        AutoPilot_Usage()
        ExitApp
    }
    switch args[1] {
        case "--probe":
            AutoPilot_Out(FanBridgeJsonEncode(AutoConfig_Probe()))
            ExitApp
        case "--report", "--deduce":
            AutoPilot_Out(AutoConfig_Report())
            ExitApp
        case "--apply":
            AutoPilot_Out(FanBridgeJsonEncode(AutoConfig_Apply()))
            ExitApp
        case "--ask":
            prompt := args.Length >= 2 ? args[2] : ""
            if prompt = "" {
                AutoPilot_Out("[ERROR] --ask requires a prompt argument")
                ExitApp(1)
            }
            AutoPilot_Out(AutoPilot_AskDeepSeek(prompt))
            ExitApp
        case "--plan":
            goal := args.Length >= 2 ? args[2] : "Complete my recurring development workflow today"
            AutoPilot_PlanDay(goal)
            ExitApp
        case "--run":
            AutoPilot_RunPlan()
            ExitApp
        case "--loop":
            interval := args.Length >= 2 ? Max(60, Integer(args[2])) : 900
            AutoPilot_Loop(interval)   ; resident — stays alive until aborted
        case "--self-test":
            r := AutoConfig_SelfTest()
            AutoPilot_Out(FanBridgeJsonEncode(r))
            ExitApp(r["ok"] ? 0 : 1)
        default:
            AutoPilot_Usage()
            ExitApp
    }
}

AutoPilot_Usage() {
    AutoPilot_Out("AutoPilot — DeepSeek daily autonomy for Macro Automator`n"
        . "  --probe | --report | --apply | --ask <q> | --plan <goal> | --run | --loop <sec> | --self-test`n"
        . "Start fan\\MacroAutomator.ahk first (owns the gateway + AHK worker).")
}

; ───────────────────────────────────────────────────────────────────────────────
; DeepSeek agent round-trip through the loopback bridge gateway.
; ───────────────────────────────────────────────────────────────────────────────
AutoPilot_AskDeepSeek(prompt, timeoutMs := 120000) {
    try {
        doc := FanBridgeJsonDecode(AutoPilot_Http("POST", "/tasks",
            FanBridgeJsonEncode(Map("prompt", prompt, "history", [], "images", []))))
        id := doc.Get("id", "")
        if id = ""
            return "[ERROR] Bridge returned no task id"
        started := A_TickCount
        loop {
            Sleep(500)
            if g_AutoPilotAbort
                return "[ABORTED] " . id
            task := FanBridgeJsonDecode(AutoPilot_Http("GET", "/tasks/" . id))
            status := task.Get("status", "")
            if RegExMatch(status, "^(complete|error|cancelled)$")
                return status = "complete" ? task.Get("response", "") : "[ERROR] " . task.Get("response", status)
            if A_TickCount - started > timeoutMs
                return "[TIMEOUT] task " . id . " still running; inspect DeepSeek Bridge history"
        }
    } catch as err {
        return "[ERROR] " . err.Message
    }
}

AutoPilot_Http(method, path, body := "") {
    token := AutoPilot_Env("BRIDGE_TOKEN")
    port := AutoPilot_Env("BRIDGE_PORT", "8765")
    if token = ""
        throw Error("Bridge token missing; is fan\DeepSeekBridge\.env present and Fan running?")
    whr := ComObject("WinHttp.WinHttpRequest.5.1")
    whr.SetProxy(1)
    whr.SetTimeouts(1000, 1000, 3000, 60000)
    whr.Open(method, "http://127.0.0.1:" . port . path, false)
    whr.SetRequestHeader("X-Bridge-Token", token)
    whr.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
    whr.Send(body)
    if whr.Status < 200 || whr.Status >= 300
        throw Error("Bridge HTTP " . whr.Status)
    return whr.ResponseText
}

AutoPilot_Env(name, default := "") {
    root := A_ScriptDir . "\fan\DeepSeekBridge\.env"
    if !FileExist(root)
        return default
    for line in StrSplit(FileRead(root, "UTF-8"), "`n", "`r") {
        at := InStr(line, "=")
        if at > 1 && Trim(SubStr(line, 1, at - 1)) = name
            return Trim(SubStr(line, at + 1))
    }
    return default
}

; ───────────────────────────────────────────────────────────────────────────────
; Plan the day: fold the self-discovery report into a DeepSeek planning prompt.
; ───────────────────────────────────────────────────────────────────────────────
AutoPilot_PlanDay(goal) {
    DirCreate(g_AutoPilotPlanDir)
    ded := AutoConfig_Deduce()
    workflows := ded["facts"].Get("saved_workflows", [])
    workflowList := workflows.Length ? AutoConfig_Join(workflows, ", ") : "(none saved yet)"

    prompt := "You are the daily autopilot for the Macro Automator desktop-automation system. "
        . "Produce a concise, ordered JSON day plan that a guarded executor can follow. "
        . "Prefer existing saved workflows and the Fan API tools; never invent raw screen coordinates. "
        . "`n`nTODAY'S GOAL: " . goal
        . "`nSAVED WORKFLOWS: " . workflowList
        . "`nSELF-DISCOVERY REPORT:`n" . AutoConfig_Report("text")
        . "`n`nReturn ONLY a JSON array of objects: {`"step`": n, `"kind`": `"workflow`"|`"tool`"|`"note`", "
        . "`"name`": string, `"args`": {}, `"note`": string}. Cap it at 12 steps. "
        . "A workflow step uses `"name`" = an exact saved workflow name. A tool step uses `"name`" = a Fan API tool (fan_*)."

    AutoPilot_Out("Planning today's run with DeepSeek…")
    raw := AutoPilot_AskDeepSeek(prompt, 180000)
    AutoPilot_Out(raw)

    plan := AutoPilot_ExtractJson(raw)
    if IsObject(plan) {
        FileDelete(g_AutoPilotPlanFile)
        FileAppend(FanBridgeJsonEncode(plan), g_AutoPilotPlanFile, "UTF-8")
        AutoPilot_Out("Plan saved to " . g_AutoPilotPlanFile)
    } else {
        txt := g_AutoPilotPlanDir . "\plan.txt"
        FileDelete(txt)
        FileAppend(raw, txt, "UTF-8")
        AutoPilot_Out("Could not parse a JSON plan; saved the raw reply to " . txt)
    }
}

; Tolerant JSON extraction: return the first [ ... ] array if decodable.
AutoPilot_ExtractJson(text) {
    if RegExMatch(text, "s)\[.*\]", &m) {
        try {
            v := FanBridgeJsonDecode(m[0])
            if v is Array
                return v
        }
    }
    return ""
}

; ───────────────────────────────────────────────────────────────────────────────
; Execute the saved plan, one bounded step at a time, with an abort hotkey.
; ───────────────────────────────────────────────────────────────────────────────
AutoPilot_RunPlan() {
    if !FileExist(g_AutoPilotPlanFile) {
        AutoPilot_Out("[ERROR] No plan.json — run --plan first.")
        return
    }
    plan := FanBridgeJsonDecode(FileRead(g_AutoPilotPlanFile, "UTF-8"))
    if !(plan is Array) {
        AutoPilot_Out("[ERROR] plan.json is not a JSON array.")
        return
    }
    DirCreate(g_AutoPilotPlanDir)
    for , step in plan {
        if g_AutoPilotAbort {
            AutoPilot_Log("aborted", step)
            break
        }
        kind := step.Get("kind", ""), name := step.Get("name", "")
        try {
            if kind = "workflow" && name != "" {
                AutoPilot_Log("run", step)
                AutoPilot_Out("RUN workflow: " . name)
                r := FanBridge.RunWorkflow(name, 120)
                AutoPilot_Log("done", Map("step", step, "result", r))
            } else if kind = "tool" && RegExMatch(name, "^(fan|daa)_[a-z_]+$") {
                AutoPilot_Log("tool", step)
                AutoPilot_Out("CALL tool: " . name)
                r := FanBridge.Call(name, step.Get("args", Map()))
                AutoPilot_Log("done", Map("step", step, "result", r))
            } else {
                AutoPilot_Out("NOTE (manual step): " . (step.Get("note", name)))
                AutoPilot_Log("note", step)
            }
        } catch as err {
            AutoPilot_Out("FAILED: " . name . " — " . err.Message)
            AutoPilot_Log("error", Map("step", step, "error", err.Message))
        }
    }
    AutoPilot_Out("Run complete." . (g_AutoPilotAbort ? " (aborted)" : ""))
}

; ───────────────────────────────────────────────────────────────────────────────
; All-day loop: re-probe and (if a plan exists) execute, within a safety budget.
; ───────────────────────────────────────────────────────────────────────────────
AutoPilot_Loop(intervalSec) {
    AutoPilot_Out("AutoPilot loop every " . intervalSec . "s. Ctrl+Alt+Shift+X aborts; F1 status.")
    AutoPilot_Out(AutoConfig_Report("text"))
    loop {
        if g_AutoPilotAbort {
            AutoPilot_Out("Loop aborted.")
            return
        }
        if FileExist(g_AutoPilotPlanFile)
            AutoPilot_RunPlan()
        AutoPilot_Log("tick", Map("at", A_Now, "plan", FileExist(g_AutoPilotPlanFile) ? 1 : 0))
        Sleep(intervalSec * 1000)
    }
}

AutoPilot_Status() {
    facts := AutoConfig_Probe()
    ToolTip("AutoPilot resident — abort=" . (g_AutoPilotAbort ? "YES" : "no")
        . "`nforeground: " . facts.Get("foreground_title", "?")
        . "`nbridge env: " . (facts["bridge_env"] != "" ? "present" : "missing"), 0, 0)
    SetTimer(() => ToolTip(), -3000)
}

AutoPilot_Log(kind, data) {
    DirCreate(g_AutoPilotPlanDir)
    try FileAppend(FanBridgeJsonEncode(Map("kind", kind, "at", A_Now, "data", data)) . "`n", g_AutoPilotRunLog, "UTF-8")
}

AutoPilot_Out(s) {
    try FileAppend(s . "`n", "*")
}

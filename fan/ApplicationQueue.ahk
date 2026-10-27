#Requires AutoHotkey v2.0
#SingleInstance Force
#Include ..\lib\FanBridgeClient.ahk
global jobUI := Map(), jobWindow := Gui("+Resize +MinSize1020x740", "Applications — Retained Queue and Chrome Runner")
jobWindow.SetFont("s9", "Segoe UI")
jobWindow.Add("Text", "x14 y12 w985 h42", "Page memory, settings and the queue persist. Connect the existing normal Chrome window you use for jobs. Unknown required answers and site verification require your action. Submitted requires a site confirmation.")
jobWindow.Add("Text", "x14 y62 w490 h22", "Settings: up to five sites, job criteria, résumé and truthful answers")
jobUI["config"] := jobWindow.Add("Edit", "x14 y88 w490 h245 Multi +Wrap +VScroll")
jobWindow.Add("Button", "x14 y344 w155 h28", "Save settings").OnEvent("Click", (*) => JobUI_Save())
jobWindow.Add("Button", "x182 y344 w155 h28", "Reload settings").OnEvent("Click", (*) => JobUI_Load())
jobWindow.Add("Button", "x350 y344 w150 h28", "DeepSeek sharing").OnEvent("Click", (*) => JobUI_Sharing())
jobWindow.Add("Text", "x530 y62 w450 h22", "Add a job from a configured website")
jobUI["url"] := jobWindow.Add("Edit", "x530 y88 w450 h28")
jobWindow.Add("Text", "x530 y125 w450 h22", "Job title / company")
jobUI["title"] := jobWindow.Add("Edit", "x530 y152 w450 h28")
jobUI["company"] := jobWindow.Add("Edit", "x530 y192 w450 h28")
jobWindow.Add("Button", "x530 y234 w150 h28", "Queue job URL").OnEvent("Click", (*) => JobUI_Add())
jobWindow.Add("Button", "x694 y234 w135 h28", "Search entry links").OnEvent("Click", (*) => JobUI_Searches())
jobWindow.Add("Button", "x842 y234 w137 h28", "Import learned links").OnEvent("Click", (*) => JobUI_Discover())
jobWindow.Add("Button", "x530 y281 w190 h28", "Start 8-hour run").OnEvent("Click", (*) => JobUI_Start())
jobWindow.Add("Button", "x735 y281 w245 h28", "Connect existing Chrome").OnEvent("Click", (*) => JobUI_Chrome())
jobWindow.Add("Button", "x530 y326 w130 h28", "Pause / Resume").OnEvent("Click", (*) => JobUI_Control("toggle"))
jobWindow.Add("Button", "x677 y326 w130 h28", "Stop run").OnEvent("Click", (*) => JobUI_Control("stop"))
jobWindow.Add("Button", "x824 y326 w155 h28", "Refresh queue").OnEvent("Click", (*) => JobUI_Refresh())
jobUI["list"] := jobWindow.Add("ListView", "x14 y391 w980 h265", ["Status", "Job", "Company", "URL"])
jobUI["list"].ModifyCol(1,130), jobUI["list"].ModifyCol(2,230), jobUI["list"].ModifyCol(3,180), jobUI["list"].ModifyCol(4,420)
jobUI["status"] := jobWindow.Add("Text", "x14 y674 w980 h45", "Ready — retained queue")
jobWindow.OnEvent("Close", (*) => ExitApp())
jobWindow.OnEvent("Size", (g,state,w,h) => state=-1 ? 0 : JobUI_Size(w,h))
JobUI_Load()
JobUI_Refresh()
SetTimer(JobUI_Refresh, 4000)
jobWindow.Show("w1020 h740")
if A_Args.Length && A_Args[1] = "/connect"
    SetTimer(JobUI_Chrome, -250)

JobUI_Size(width, height) {
    jobUI["list"].Move(,,width-28,height-475)
    jobUI["status"].Move(14,height-66,width-28)
}

JobUI_Load() {
    try {
        config := FanBridge.Call("fan_job_config_get")["configuration"]
        jobUI["config"].Value := FanBridgeJsonEncode(config, 2)
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Save() {
    try {
        result := FanBridge.Call("fan_job_config_set", FanBridgeJsonDecode(jobUI["config"].Value))
        jobUI["status"].Value := result["execution_status"]
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Add() {
    try {
        result := FanBridge.Call("fan_job_enqueue", Map("url",jobUI["url"].Value,"title",jobUI["title"].Value,"company",jobUI["company"].Value))
        jobUI["status"].Value := result.Get("duplicate",false) ? "This URL is already retained in the queue" : "Job URL queued locally"
        JobUI_Refresh()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Start() {
    try {
        JobUI_EnableChrome()
        result := FanBridge.Call("fan_job_start",Map("hours",8))
        jobUI["run"] := result["run_id"]
        JobUI_Refresh()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_EnableChrome() {
    status := FanBridge.Call("fan_job_chrome_status")
    if !status.Get("connected", false)
        throw Error("Click Connect existing Chrome and pair your normal Chrome window first.")
    config := FanBridge.Call("fan_job_config_get")["configuration"]
    config["browser_execution"] := true, config["automatic_discovery"] := true
    config["browser_mode"] := "existing_chrome"
    FanBridge.Call("fan_job_config_set", config)
    jobUI["config"].Value := FanBridgeJsonEncode(config, 2)
}

JobUI_Chrome() {
    try {
        result := FanBridge.Call("fan_job_chrome_pair")
        g := Gui("+Owner" . jobWindow.Hwnd, "Connect your existing Chrome window")
        g.SetFont("s10", "Segoe UI")
        g.Add("Text", "w750 h115", "In your normal Chrome window, open chrome://extensions, turn on Developer mode, click Load unpacked, and select the folder below.`nThen open LinkedIn or a public job page in that window. Click the Fan extension, paste this pairing code, and click Connect this normal window.`nThe code expires in 10 minutes. No new Chrome profile or incognito window is launched.")
        g.Add("Edit", "w750 ReadOnly", result["extension_folder"])
        g.Add("Text", "w750", "Pairing code")
        code := g.Add("Edit", "w750 ReadOnly", result["pair_code"])
        g.Add("Button", "w200", "Copy pairing code").OnEvent("Click", (*) => (A_Clipboard := code.Value))
        g.Add("Text", "w750 h55", "Chrome will display its debugger banner. The connector handles approved public job pages only. Passwords, verification codes and CAPTCHA stay manual.")
        g.OnEvent("Close", (*) => g.Destroy())
        g.Show()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Sharing() {
    try {
        policy := FanBridge.Call("fan_job_sharing_get")["policy"]
        g := Gui("+Owner" . jobWindow.Hwnd, "Job-page sharing with DeepSeek")
        g.SetFont("s9", "Segoe UI")
        g.Add("Text", "w700 h95", "Destination: https://api.deepseek.com`nPayload: job-page screenshots (including other visible browser content), element maps, and résumé-based applicant details.`nScope: configured job sites and LinkedIn. Page memory stays local; approved observations are sent when requested. This setting does not enable application submission.")
        enabled := g.Add("CheckBox", "w700", "Allow this sharing with DeepSeek")
        enabled.Value := policy["enabled"]
        g.Add("Button", "w170", "Save local preference").OnEvent("Click", (*) => JobUI_SaveSharing(g, enabled))
        g.OnEvent("Close", (*) => g.Destroy())
        g.Show()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_SaveSharing(g, enabled) {
    try {
        FanBridge.Call("fan_job_sharing_set", Map("enabled", enabled.Value ? true : false))
        jobUI["status"].Value := enabled.Value ? "Approved job-site sharing with api.deepseek.com enabled" : "Job-site sharing disabled; local memory retained"
        g.Destroy()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Discover() {
    input := InputBox("Enter the saved page ID from Local Chrome Page Learner. Only observed job links from configured sites will be imported.", "Import learned job links", "w580 h150")
    if input.Result != "OK" || Trim(input.Value) = ""
        return
    try {
        result := FanBridge.Call("fan_job_discover", Map("page_id", Trim(input.Value)))
        jobUI["status"].Value := result["jobs"].Length . " observed job links checked; existing URLs were deduplicated"
        JobUI_Refresh()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Searches() {
    try {
        entries := FanBridge.Call("fan_job_searches")["searches"]
        g := Gui("+Owner" . jobWindow.Hwnd, "Configured job search links")
        g.SetFont("s9", "Segoe UI")
        g.Add("Text", "w860 h38", "Choose an entry link. Employer platforms use a search-engine discovery link. Advertised salary and location still need verification.")
        list := g.Add("ListBox", "w860 h350", JobUI_SearchLabels(entries))
        g.Add("Button", "w150", "Open selected search").OnEvent("Click", (*) => JobUI_OpenSearch(list, entries))
        g.OnEvent("Close", (*) => g.Destroy())
        g.Show()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_SearchLabels(entries) {
    labels := []
    for e in entries
        labels.Push(e["site"] . " · " . e["role"] . " · " . e["location"])
    return labels
}

JobUI_OpenSearch(list, entries) {
    if list.Value < 1
        return
    url := entries[list.Value]["url"]
    if RegExMatch(url, "^https://")
        Run(url)
}

JobUI_Control(action) {
    if !jobUI.Has("run")
        return
    if action = "toggle"
        action := jobUI.Get("runStatus","") = "paused" ? "resume" : "pause"
    try {
        if action = "resume"
            JobUI_EnableChrome()
        FanBridge.Call("fan_job_control",Map("run_id",jobUI["run"],"action",action))
        JobUI_Refresh()
    } catch as err
        jobUI["status"].Value := err.Message
}

JobUI_Refresh() {
    try {
        result := FanBridge.Call("fan_job_status")
        jobUI["list"].Delete()
        for item in result["items"]
            jobUI["list"].Add(,item["status"],item["title"],item["company"],item["job_url"])
        if result["runs"].Length {
            run := result["runs"][1]
            jobUI["run"] := run["run_id"], jobUI["runStatus"] := run["status"]
            jobUI["status"].Value := "Run: " . run["status"] . " · " . FanBridgeJsonEncode(result["counts"]) . " · " . result.Get("mode", "local_preparation") . " · requested mode: " . result.Get("requested_submission_mode", "review")
        }
    } catch as err
        jobUI["status"].Value := err.Message
}

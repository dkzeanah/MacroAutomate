#Requires AutoHotkey v2.0
#SingleInstance Off
#Warn All, Off
; Reuse the maintained extraction/provider/database modules, without a GUI or collectors.
#Include Core\_Bootstrap.ahk
#Include ..\lib\FanBridgeJson.ahk
global request := FanBridgeJsonDecode(FileRead(A_Args[1],"UTF-8"))
g_FanSeedPath := request["args"]["db_path"]
#Include Core\_Dependencies.ahk
#Include Core\_Globals.ahk
#Include Core\_Modules.ahk
SetTimer(CheckMediaCancellation,200)
try {
    if !TrackDB_Init(g_FanSeedPath)
        throw Error("Unable to open the selected media database")
    options := request["args"], jobId := options.Get("job_id",0)
    g_StudyLLM_SpentUSD := options.Get("spent_usd",0)
    g_StudyLLM_Endpoint := options.Get("endpoint",g_StudyLLM_Endpoint)
    g_StudyLLM_VisionModel := options.Get("vision_model",g_StudyLLM_VisionModel)
    if !jobId || !Media_Frames(jobId).Length {
        Track_WriteFile(request["progress"],TrackJsonEncode(Map("fraction",0,"message","Extracting timestamped video frames")))
        duration := Media_ProbeDuration(options["path"])
        effectiveFps := duration>0 ? Min(options["fps"],options["max_frames"]/duration) : options["fps"]
        extracted := options["scene"] ? Media_ExtractSceneFrames(options["path"],0.3,options["max_frames"])
            : Media_ExtractFrames(options["path"],effectiveFps,options["max_frames"])
        if !extracted["ok"]
            throw Error(extracted["error"])
        if !jobId {
            SplitPath(options["path"],&title)
            jobId := Media_NewJob(options["scene"] ? "scene" : "fps",options["path"],title,effectiveFps)
        }
        Media_StoreFrames(jobId,extracted["frames"])
    }
    if FileExist(request["cancel"])
        throw Error("Cancelled")
    result := Media_AnalyzeJob(jobId,options["question"],options["batch"],MediaWorkerProgress)
    result["job_id"] := jobId
} catch as mediaError
    result := Map("ok",false,"error",mediaError.Message,"job_id",IsSet(jobId) ? jobId : 0,"cost",0)
Track_WriteFile(request["result"] . ".tmp",TrackJsonEncode(result))
FileMove(request["result"] . ".tmp",request["result"],1)
ExitApp()

CheckMediaCancellation() {
    if FileExist(request["cancel"])
        Media_CancelAll(), StudyLLM_CancelRequest()
}

MediaWorkerProgress(fraction, message) {
    Track_WriteFile(request["progress"] . ".tmp",TrackJsonEncode(Map("fraction",fraction,"message",message)))
    FileMove(request["progress"] . ".tmp",request["progress"],1)
}

; ═══════════════════════════════════════════════════════════════════════════════
; MediaLLM.ahk - Multi-image DeepSeek vision + structured JSON output
; ═══════════════════════════════════════════════════════════════════════════════
; DeepSeek Flash understands images, not video. This layer sends BATCHES of
; frames (with per-frame timestamp labels) to the vision model and asks for
; structured JSON back, which the media pipeline (MediaPipeline.ahk) and the
; environment-intelligence mapper (EnvIntel.ahk) turn into timelines and
; machine-readable region maps.
;
; It reuses the existing DeepSeek provider plumbing from StudyLLM.ahk:
;   credential load, endpoint, vision model, the POST helper, token/field
;   extraction, cost estimation, the shared session cost cap and spend counter,
;   and the cancel flag. JSON is parsed with TrackJsonDecode (lib/TrackUtil.ahk).
; ═══════════════════════════════════════════════════════════════════════════════

global g_MediaLLM_MaxBatch := 16      ; frames per request (DeepSeek allows far
                                      ; more, but small batches validate/retry well)

; Analyze a batch of images. Returns Map(ok, text, model, promptTokens,
; completionTokens, costUSD, error).
;   images : array of image path strings, or Maps {path, label}
;   prompt : the instruction/question
;   opts   : Map with optional detail ("high"|"low"|"auto"), maxTokens, model
MediaLLM_Analyze(images, prompt, opts := "") {
    global g_StudyLLM_Endpoint, g_StudyLLM_VisionModel, g_StudyLLM_SpentUSD
    global g_StudyLLM_Cancel, g_MediaLLM_MaxBatch
    if !IsObject(opts)
        opts := Map()
    if !IsObject(images) || images.Length = 0
        return MediaLLM_Fail("No images to analyze")
    if (images.Length > g_MediaLLM_MaxBatch)
        return MediaLLM_Fail("Too many images in one request (" . images.Length
                           . " > " . g_MediaLLM_MaxBatch . ") - batch them")

    key := StudyLLM_Key()
    if (key = "")
        return MediaLLM_Fail("No DeepSeek API key (set DEEPSEEK_API_KEY or save one)")

    ; Shared session budget with the study layer.
    budget := Study_GetSetting("cost_cap_usd", "2.00") + 0.0
    if (budget > 0 && g_StudyLLM_SpentUSD >= budget)
        return MediaLLM_Fail("Session cost cap ($" . Round(budget, 2) . ") reached")

    g_StudyLLM_Cancel := false
    detail := opts.Has("detail") ? opts["detail"] : "high"
    maxTokens := opts.Has("maxTokens") ? Integer(opts["maxTokens"]) : 1200
    model := opts.Has("model") ? opts["model"] : g_StudyLLM_VisionModel

    ; ── build the content array: prompt text, then each image with its label ──
    content := '[{"type":"text","text":' . StudyLLM_JStr(prompt) . '}'
    for , im in images {
        path := IsObject(im) ? im["path"] : im
        label := (IsObject(im) && im.Has("label")) ? im["label"] : ""
        if !FileExist(path)
            continue
        dataUrl := StudyLLM_ImageDataUrl(path)
        if (dataUrl = "")
            continue
        if (label != "")
            content .= ',{"type":"text","text":' . StudyLLM_JStr(label) . '}'
        content .= ',{"type":"image_url","image_url":{"url":' . StudyLLM_JStr(dataUrl)
                 . ',"detail":' . StudyLLM_JStr(detail) . '}}'
    }
    content .= "]"

    sys := "You are a precise video/image analysis engine. Report only what is "
         . "visible. When asked for JSON, output JSON only - no prose, no code "
         . "fences."
    body := '{"model":' . StudyLLM_JStr(model)
          . ',"messages":[{"role":"system","content":' . StudyLLM_JStr(sys) . '},'
          . '{"role":"user","content":' . content . '}]'
          . ',"stream":false,"temperature":0.1,"max_tokens":' . maxTokens . '}'

    attempts := 0, lastErr := ""
    loop {
        attempts++
        if g_StudyLLM_Cancel
            return MediaLLM_Fail("Cancelled")
        res := StudyLLM_Post(g_StudyLLM_Endpoint . "/chat/completions", key, body)
        if res["ok"]
            break
        lastErr := res["error"]
        if !(res["status"] = 429 || res["status"] >= 500 || res["status"] = 0)
            return MediaLLM_Fail(lastErr)
        if (attempts >= 3)
            return MediaLLM_Fail(lastErr . " (after " . attempts . " attempts)")
        Sleep((2 ** (attempts - 1)) * 800)
    }

    text := Trim(StudyLLM_JsonStringField(res["text"], "content"))
    if (text = "")
        return MediaLLM_Fail("Model returned no content")
    pt := StudyLLM_JsonIntField(res["text"], "prompt_tokens")
    ct := StudyLLM_JsonIntField(res["text"], "completion_tokens")
    cost := StudyLLM_EstimateCost(model, pt, ct)
    g_StudyLLM_SpentUSD += cost

    return Map("ok", true, "text", text, "model", model, "promptTokens", pt
             , "completionTokens", ct, "costUSD", cost, "error", "")
}

; Same as Analyze but asks for and parses JSON. Returns Map(ok, value, raw,
; model, costUSD, error) where value is the decoded Map/Array (or "" on failure).
MediaLLM_AnalyzeJson(images, instruction, opts := "") {
    full := instruction . "`n`nRespond with JSON only."
    res := MediaLLM_Analyze(images, full, opts)
    out := Map("ok", false, "value", "", "raw", "", "model", "", "costUSD", 0, "error", "")
    if !res["ok"] {
        out["error"] := res["error"]
        return out
    }
    out["raw"] := res["text"]
    out["model"] := res["model"]
    out["costUSD"] := res["costUSD"]
    parsed := MediaLLM_ExtractJson(res["text"])
    if !parsed["ok"] {
        out["error"] := "Could not parse JSON from model output: " . parsed["error"]
        return out
    }
    out["ok"] := true
    out["value"] := parsed["value"]
    return out
}

; Pull the first JSON value out of model output, tolerating code fences and
; surrounding prose. Returns Map(ok, value, error).
MediaLLM_ExtractJson(text) {
    out := Map("ok", false, "value", "", "error", "")
    ; Scan for the first balanced {...} or [...] - this naturally skips any
    ; surrounding prose or ``` code fences without needing to match backticks
    ; (which are AHK's escape character inside strings).
    span := MediaLLM_BalancedJson(Trim(text))
    if (span = "") {
        out["error"] := "no JSON object/array found"
        return out
    }
    try {
        out["value"] := TrackJsonDecode(span)
        out["ok"] := true
    } catch as err {
        out["error"] := err.Message
    }
    return out
}

; Return the first balanced {..} or [..] substring, respecting strings/escapes.
MediaLLM_BalancedJson(s) {
    start := 0, open := "", close := ""
    Loop Parse, s {
        if (A_LoopField = "{" || A_LoopField = "[") {
            start := A_Index
            open := A_LoopField
            close := (open = "{") ? "}" : "]"
            break
        }
    }
    if !start
        return ""
    depth := 0, inStr := false, esc := false
    i := start
    len := StrLen(s)
    while (i <= len) {
        c := SubStr(s, i, 1)
        if inStr {
            if esc
                esc := false
            else if (c = "\")
                esc := true
            else if (c = '"')
                inStr := false
        } else {
            if (c = '"')
                inStr := true
            else if (c = open)
                depth++
            else if (c = close) {
                depth--
                if (depth = 0)
                    return SubStr(s, start, i - start + 1)
            }
        }
        i++
    }
    return ""
}

MediaLLM_Fail(msg) {
    return Map("ok", false, "text", "", "model", "", "promptTokens", 0
             , "completionTokens", 0, "costUSD", 0, "error", msg)
}

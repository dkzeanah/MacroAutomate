; ═══════════════════════════════════════════════════════════════════════════════
; StudyLLM.ahk - External LLM provider layer for the study assistant
; ═══════════════════════════════════════════════════════════════════════════════
; A thin provider interface with DeepSeek as the first adapter. The answer engine
; (StudyAssistant.ahk) only ever calls StudyLLM_Ask(); it does not know or care
; which provider answers, so Ollama / OpenAI / Claude adapters can be added later
; without touching question storage or answer policy (spec section 5).
;
; CREDENTIALS
;   The API key is read, in order, from:
;     1. the DEEPSEEK_API_KEY environment variable
;     2. Windows Credential Manager, generic credential "MacroAutomator/DeepSeek"
;   It is NEVER written to source, settings, SQLite, logs, screenshots, reports,
;   or request diagnostics. StudyLLM_SaveKey() stores it in Credential Manager
;   (DPAPI-protected per user) so it survives restarts without living in a file.
;
; MODELS (verified against api-docs.deepseek.com on 2026-10-05)
;   deepseek-v4-pro  text only, 1M context      -> hard text reasoning
;   deepseek-flash   vision + text, 1M context  -> images / diagrams / uncertain OCR
;   The requested name "deepseek-v4-flash-vision-exp" is a RETIRED alias that now
;   routes to deepseek-flash; we send the current name and note the mapping.
; ═══════════════════════════════════════════════════════════════════════════════

global g_StudyLLM_CredTarget := "MacroAutomator/DeepSeek"
global g_StudyLLM_Endpoint   := "https://api.deepseek.com"
global g_StudyLLM_TextModel  := "deepseek-v4-pro"
global g_StudyLLM_VisionModel := "deepseek-flash"
global g_StudyLLM_Cancel     := false     ; set true to abort an in-flight request
global g_StudyLLM_Busy       := false
global g_StudyLLM_SpentUSD   := 0.0       ; rough running cost this session

; Rough list prices (USD / 1M tokens, cache-miss peak) for a conservative cost
; estimate. Off-peak is cheaper, so this never under-reports spend.
global g_StudyLLM_Price := Map(
    "deepseek-v4-pro", Map("in", 1.32, "out", 3.96),
    "deepseek-flash",  Map("in", 0.30, "out", 1.20))

; ─────────────────────────────────────────────────────────────────────────────
; CREDENTIAL STORE
; ─────────────────────────────────────────────────────────────────────────────
; Returns the key or "" - and is the ONLY place the key is handled in cleartext.
StudyLLM_Key() {
    v := EnvGet("DEEPSEEK_API_KEY")
    if (Trim(v) != "")
        return Trim(v)
    return StudyLLM_CredRead(g_StudyLLM_CredTarget)
}

StudyLLM_HasKey() => StudyLLM_Key() != ""

; Where the key is coming from, for status display (never the value itself).
StudyLLM_KeySource() {
    if (Trim(EnvGet("DEEPSEEK_API_KEY")) != "")
        return "DEEPSEEK_API_KEY environment variable"
    if (StudyLLM_CredRead(g_StudyLLM_CredTarget) != "")
        return "Windows Credential Manager"
    return ""
}

; Store the key in Windows Credential Manager (CRED_TYPE_GENERIC, DPAPI-backed).
StudyLLM_SaveKey(key) {
    global g_StudyLLM_CredTarget
    key := Trim(key)
    if (key = "")
        return false
    target := g_StudyLLM_CredTarget
    blob := Buffer(StrPut(key, "UTF-8"))
    StrPut(key, blob, "UTF-8")
    tgt := Buffer(StrPut(target, "UTF-16") * 2)
    StrPut(target, tgt, "UTF-16")
    user := Buffer(StrPut("DeepSeek", "UTF-16") * 2)
    StrPut("DeepSeek", user, "UTF-16")

    ; CREDENTIALW field offsets. The 64-bit layout (what AutoHotkey64 uses) is:
    ;   0  Flags(DWORD)            4  Type(DWORD)
    ;   8  TargetName(LPWSTR)     16  Comment(LPWSTR)
    ;   24 LastWritten(FILETIME)  32  CredentialBlobSize(DWORD)
    ;   40 CredentialBlob(LPBYTE) 48  Persist(DWORD) 52 AttributeCount(DWORD)
    ;   56 Attributes(ptr)        64  TargetAlias(LPWSTR) 72 UserName(LPWSTR)  -> 80 bytes
    ; The 32-bit layout packs the same fields on 4-byte pointers (52 bytes).
    if (A_PtrSize = 8) {
        cred := Buffer(80, 0)
        NumPut("UInt", 1, cred, 4)                 ; Type = CRED_TYPE_GENERIC
        NumPut("Ptr", tgt.Ptr, cred, 8)            ; TargetName
        NumPut("UInt", blob.Size - 1, cred, 32)    ; CredentialBlobSize excludes NUL
        NumPut("Ptr", blob.Ptr, cred, 40)          ; CredentialBlob
        NumPut("UInt", 2, cred, 48)                ; Persist = LOCAL_MACHINE
        NumPut("Ptr", user.Ptr, cred, 72)          ; UserName
    } else {
        cred := Buffer(52, 0)
        NumPut("UInt", 1, cred, 4)                 ; Type
        NumPut("Ptr", tgt.Ptr, cred, 8)            ; TargetName
        NumPut("UInt", blob.Size - 1, cred, 24)
        NumPut("Ptr", blob.Ptr, cred, 28)          ; CredentialBlob
        NumPut("UInt", 2, cred, 32)                ; Persist
        NumPut("Ptr", user.Ptr, cred, 48)          ; UserName
    }
    ok := DllCall("Advapi32\CredWriteW", "Ptr", cred.Ptr, "UInt", 0, "Int")
    return ok != 0
}

StudyLLM_DeleteKey() {
    global g_StudyLLM_CredTarget
    tgt := Buffer(StrPut(g_StudyLLM_CredTarget, "UTF-16") * 2)
    StrPut(g_StudyLLM_CredTarget, tgt, "UTF-16")
    return DllCall("Advapi32\CredDeleteW", "Ptr", tgt.Ptr, "UInt", 1, "UInt", 0, "Int") != 0
}

StudyLLM_CredRead(target) {
    tgt := Buffer(StrPut(target, "UTF-16") * 2)
    StrPut(target, tgt, "UTF-16")
    pCred := 0
    if !DllCall("Advapi32\CredReadW", "Ptr", tgt.Ptr, "UInt", 1, "UInt", 0, "Ptr*", &pCred, "Int")
        return ""
    key := ""
    try {
        ; CredentialBlobSize / CredentialBlob sit after Flags,Type,TargetName,
        ; Comment,LastWritten in the CREDENTIALW struct.
        off := 8 + A_PtrSize + A_PtrSize + 8        ; Flags+Type(+pad), Target, Comment, FILETIME
        blobSize := NumGet(pCred, off, "UInt")
        off += 4 + (A_PtrSize = 8 ? 4 : 0)
        blobPtr := NumGet(pCred, off, "Ptr")
        if (blobSize > 0 && blobPtr)
            key := StrGet(blobPtr, blobSize, "UTF-8")
    }
    DllCall("Advapi32\CredFree", "Ptr", pCred)
    return Trim(key)
}

; ─────────────────────────────────────────────────────────────────────────────
; PUBLIC ENTRY POINT
; ─────────────────────────────────────────────────────────────────────────────
; Ask the configured provider a question.
;   opts: Map with optional keys
;         context    - supporting text/snippets to ground the answer
;         imagePath  - a cropped screenshot to send (forces the vision model)
;         wantVision - true to prefer the vision model even without an image
;         maxTokens  - output cap (default 800)
; Returns Map(ok, answer, model, provider, promptTokens, completionTokens,
;             costUSD, error). answer is "" on failure and error explains why.
StudyLLM_Ask(question, opts := "") {
    global g_StudyLLM_Cancel, g_StudyLLM_Busy
    if g_StudyLLM_Busy
        return StudyLLM_Fail("A provider request is already active; wait for it to finish")
    g_StudyLLM_Busy := true
    try {
        g_StudyLLM_Cancel := false
        if !IsObject(opts)
            opts := Map()
        provider := Study_GetSetting("provider", "deepseek")
        switch provider {
            case "deepseek":
                return StudyLLM_DeepSeek(question, opts)
            default:
                return StudyLLM_Fail("Unknown provider '" . provider . "' - only 'deepseek' is implemented")
        }
    } finally {
        g_StudyLLM_Busy := false
    }
}

; Is the provider reachable and configured? Probes GET /models (spec section 5).
; Returns Map(ok, detail, models). Never sends the key anywhere but the API.
StudyLLM_Probe() {
    key := StudyLLM_Key()
    if (key = "")
        return Map("ok", false, "detail", "No API key (set DEEPSEEK_API_KEY or save one)", "models", [])
    out := Map("ok", false, "detail", "", "models", [])
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        whr.SetTimeouts(4000, 4000, 8000, 10000)
        whr.Open("GET", g_StudyLLM_Endpoint . "/models", false)
        whr.SetRequestHeader("Authorization", "Bearer " . key)
        whr.Send()
        if (whr.Status = 200) {
            out["ok"] := true
            for , id in StudyLLM_ExtractModelIds(whr.ResponseText)
                out["models"].Push(id)
            out["detail"] := "Reachable - " . out["models"].Length . " model(s) available"
        } else {
            out["detail"] := "HTTP " . whr.Status . " from /models"
        }
    } catch as err {
        out["detail"] := "Cannot reach " . g_StudyLLM_Endpoint . " (" . err.Message . ")"
    }
    return out
}

; ─────────────────────────────────────────────────────────────────────────────
; DEEPSEEK ADAPTER
; ─────────────────────────────────────────────────────────────────────────────
StudyLLM_DeepSeek(question, opts) {
    global g_StudyLLM_Endpoint, g_StudyLLM_TextModel, g_StudyLLM_VisionModel
    global g_StudyLLM_SpentUSD, g_StudyLLM_Cancel

    key := StudyLLM_Key()
    StudyConsole_Secret(key)
    if (key = "")
        return StudyLLM_Fail("No DeepSeek API key available")

    ; Estimated session ceiling; reserve the request's maximum output as well.
    budget := Study_GetSetting("cost_cap_usd", "2.00") + 0.0
    if (budget > 0 && g_StudyLLM_SpentUSD >= budget)
        return StudyLLM_Fail("Session cost cap ($" . Round(budget, 2) . ") reached - not calling the API")

    context := opts.Has("context") ? opts["context"] : ""
    imagePath := opts.Has("imagePath") ? opts["imagePath"] : ""
    if imagePath != "" && !FileExist(imagePath)
        return StudyLLM_Fail("Captured image is unavailable; capture again before a visual request")
    wantVision := (imagePath != "") || (opts.Has("wantVision") && opts["wantVision"])
    maxTokens := opts.Has("maxTokens") ? Integer(opts["maxTokens"]) : 800
    model := wantVision ? g_StudyLLM_VisionModel : g_StudyLLM_TextModel

    sys := "You are a study assistant. Answer the question as precisely as possible using "
         . "the supplied study material when it is relevant. If the material does not cover "
         . "it, answer from general knowledge and say so. Be concise: give the answer first, "
         . "then a one or two sentence justification. For multiple-choice, name the correct "
         . "option letter(s) explicitly."
    if opts.Has("system")
        sys := opts["system"]

    userText := question
    if (Trim(context) != "")
        userText .= "`n`n--- STUDY MATERIAL (may be partial) ---`n" . context
    if (maxTokens < 1 || maxTokens > 8192)
        return StudyLLM_Fail("Output token limit must be 1..8192")
    if !g_StudyLLM_Price.Has(model)
        return StudyLLM_Fail("Configure token prices for this model before calling it")
    history := opts.Get("history", [])
    reserve := StudyLLM_EstimateCost(model, StrLen(sys . userText . TrackJsonEncode(history)) + (wantVision ? 16384 : 0), maxTokens)
    if (budget > 0 && g_StudyLLM_SpentUSD + reserve > budget)
        return StudyLLM_Fail("Estimated request exceeds the remaining session budget")

    ; Build the request body by hand (the bundled JSON.ahk targets a different
    ; AHK syntax and is not loaded in this build).
    body := '{"model":' . StudyLLM_JStr(model)
          . ',"messages":[{"role":"system","content":' . StudyLLM_JStr(sys) . '},'
    for , message in history {
        if !IsObject(message) || !message.Has("role") || !message.Has("content")
            return StudyLLM_Fail("Invalid chat history")
        if message["role"] != "user" && message["role"] != "assistant"
            return StudyLLM_Fail("Unsupported chat history role")
        body .= '{"role":' . StudyLLM_JStr(message["role"]) . ',"content":' . StudyLLM_JStr(message["content"]) . '},'
    }
    if (imagePath != "" && FileExist(imagePath)) {
        dataUrl := StudyLLM_ImageDataUrl(imagePath)
        if (dataUrl = "")
            return StudyLLM_Fail("Could not read the image for a vision request")
        body .= '{"role":"user","content":['
             .  '{"type":"text","text":' . StudyLLM_JStr(userText) . '},'
             .  '{"type":"image_url","image_url":{"url":' . StudyLLM_JStr(dataUrl)
             .  ',"detail":"high"}}]}'
    } else {
        body .= '{"role":"user","content":' . StudyLLM_JStr(userText) . '}'
    }
    thinking := opts.Has("thinking") && opts["thinking"] ? "enabled" : "disabled"
    streaming := opts.Get("stream", false)
    body .= '],"stream":' . (streaming ? 'true,"stream_options":{"include_usage":true}' : 'false')
        . ',"temperature":0.2,"thinking":{"type":' . StudyLLM_JStr(thinking)
        . '},"max_tokens":' . maxTokens . '}'
    StudyConsole_Log("LLM", "request.prepared", Map("provider", "deepseek", "model", model,
        "purpose", opts.Get("purpose", "study answer"), "endpoint", g_StudyLLM_Endpoint . "/chat/completions",
        "system", sys, "prompt", userText, "image_path", imagePath, "vision", wantVision,
        "max_tokens", maxTokens, "thinking", thinking, "reserve_usd", reserve, "library", "WinHTTP + Crypt32 image encoding"))

    ; Timeouts + bounded retry/backoff for transient failures and rate limits.
    attempts := 0, maxAttempts := 3, lastErr := ""
    loop {
        attempts++
        if g_StudyLLM_Cancel
            return StudyLLM_Fail("Cancelled")
        StudyConsole_Log("LLM", "http.attempt", Map("attempt", attempts, "model", model, "image", imagePath != ""))
        res := streaming
            ? StudyLLM_PostStream(g_StudyLLM_Endpoint . "/chat/completions", key, body, opts.Get("onDelta", 0), opts.Get("onProgress", 0))
            : StudyLLM_Post(g_StudyLLM_Endpoint . "/chat/completions", key, body)
        StudyConsole_Log("LLM", "http.result", Map("attempt", attempts, "status", res["status"], "ok", res["ok"], "error", res["error"]))
        if res["ok"]
            break
        lastErr := res["error"]
        ; Replaying a partly displayed response would duplicate chat output.
        if res.Get("partial", false) || g_StudyLLM_Cancel
            return StudyLLM_Fail(lastErr)
        ; Retry only on throttling / transient server errors.
        if !(res["status"] = 429 || res["status"] >= 500 || res["status"] = 0)
            return StudyLLM_Fail(lastErr)
        if (attempts >= maxAttempts)
            return StudyLLM_Fail(lastErr . " (after " . attempts . " attempts)")
        backoff := (2 ** (attempts - 1)) * 800
        StudyConsole_Log("LLM", "retry.backoff", Map("ms", backoff, "reason", lastErr), "WARN")
        StudyLLM_Sleep(backoff)
    }

    try {
        doc := TrackJsonDecode(res["text"])
        pt := doc.Has("usage") ? doc["usage"]["prompt_tokens"] : 0
        ct := doc.Has("usage") ? doc["usage"]["completion_tokens"] : 0
        cost := StudyLLM_EstimateCost(model, pt, ct)
        g_StudyLLM_SpentUSD += cost
        content := doc["choices"][1]["message"]["content"]
        finish := doc["choices"][1]["finish_reason"]
        StudyConsole_Log("LLM", "completion", Map("model", model, "answer", content, "finish", finish,
            "prompt_tokens", pt, "completion_tokens", ct, "cost_usd", cost, "session_usd", g_StudyLLM_SpentUSD))
        if (finish != "stop")
            return StudyLLM_Fail("Incomplete model response (" . finish . ") - not executing")
    } catch
        return StudyLLM_Fail("Malformed completion response - not executing")
    content := Trim(content)
    if (content = "")
        return StudyLLM_Fail("Model returned an empty answer")

    return Map("ok", true, "answer", content, "model", model, "provider", "deepseek"
             , "promptTokens", pt, "completionTokens", ct, "costUSD", cost, "error", "")
}

; The hidden worker delivers raw UTF-8 bytes. Keep them until a complete SSE line is
; available so a UTF-8 character split across network packets stays intact.
class StudyLLM_StreamSink {
    __New(callback := 0) {
        this.Callback := callback
        this.Pending := []
        this.Content := "", this.Reasoning := "", this.Finish := ""
        this.Usage := Map(), this.Done := false, this.Error := "", this.Status := 0
    }

    Feed(data, size) {
        if this.Error != ""
            return
        try {
            Loop size {
                byte := NumGet(data, A_Index - 1, "UChar")
                if byte = 10 {
                    bytes := Buffer(this.Pending.Length + 1, 0)
                    for index, value in this.Pending
                        NumPut("UChar", value, bytes, index - 1)
                    line := StrGet(bytes, this.Pending.Length, "UTF-8")
                    this.Pending := []
                    this.Line(Trim(line, "`r"))
                } else {
                    this.Pending.Push(byte)
                    if this.Pending.Length > 1048576
                        throw Error("Stream event exceeded the size limit")
                }
            }
        } catch as err {
            this.Error := "Invalid streaming response: " . err.Message
        }
    }

    Line(line) {
        if SubStr(line, 1, 7) = "status:" {
            this.Status := Integer(Trim(SubStr(line, 8)))
            return
        }
        if SubStr(line, 1, 6) = "error:" {
            this.Error := Trim(SubStr(line, 7))
            return
        }
        if this.Status != 200
            return
        if SubStr(line, 1, 5) != "data:"
            return
        payload := Trim(SubStr(line, 6))
        if payload = "[DONE]" {
            this.Done := true
            return
        }
        if payload = ""
            return
        doc := TrackJsonDecode(payload)
        if doc.Has("error")
            throw Error("Provider returned an error event")
        if doc.Has("usage") && IsObject(doc["usage"])
            this.Usage := doc["usage"]
        if !doc.Has("choices") || !doc["choices"].Length
            return
        choice := doc["choices"][1]
        if choice.Has("finish_reason") && choice["finish_reason"] != ""
            this.Finish := choice["finish_reason"]
        delta := choice.Get("delta", Map())
        for field, kind in Map("content", "answer", "reasoning_content", "reasoning") {
            text := delta.Get(field, "")
            if text = ""
                continue
            if kind = "answer"
                this.Content .= text
            else
                this.Reasoning .= text
            if IsObject(this.Callback)
                this.Callback.Call(kind, text)
        }
    }

}

StudyLLM_PostStream(url, key, body, callback := 0, progress := 0) {
    global g_StudyLLM_SpentUSD
    out := Map("ok", false, "status", 0, "text", "", "error", "", "partial", false)
    sink := StudyLLM_StreamSink(callback), worker := 0
    try {
        worker := StudyLLM_StreamWorker(url, key, body)
        if IsObject(progress)
            progress("Request sent — waiting for DeepSeek to respond")
        started := A_TickCount
        connected := false
        loop {
            received := worker.Read()
            if received["size"]
                sink.Feed(received["bytes"], received["size"])
            if sink.Status = 200 && !connected {
                connected := true
                if IsObject(progress)
                    progress("DeepSeek connected — waiting for the first reply token")
            }
            if g_StudyLLM_Cancel || sink.Error != "" || A_TickCount - started > 120000 {
                out["status"] := sink.Status ? sink.Status : -1
                out["error"] := sink.Error != "" ? sink.Error : g_StudyLLM_Cancel ? "Cancelled" : "Request timed out"
                return out
            }
            if worker.Finished() && !received["size"]
                break
            Sleep(25)
        }
        out["status"] := sink.Status
        if sink.Status != 200 {
            out["error"] := "Streaming transport exited without a successful response"
        } else if sink.Error != "" || !sink.Done || sink.Finish = "" || sink.Pending.Length {
            out["error"] := sink.Error != "" ? sink.Error : "Incomplete streaming response"
        } else {
            out["ok"] := true
            out["text"] := TrackJsonEncode(Map("choices", [Map("message", Map("content", sink.Content),
                "finish_reason", sink.Finish)], "usage", Map("prompt_tokens", sink.Usage.Get("prompt_tokens", 0),
                "completion_tokens", sink.Usage.Get("completion_tokens", 0))))
        }
    } catch as err {
        out["error"] := "Streaming request failed: " . err.Message
    } finally {
        if IsObject(worker)
            worker.Close()
        out["partial"] := sink.Content != "" || sink.Reasoning != ""
        if !out["ok"] && out["partial"] {
            ; Cancelled/failed generations still incur provider usage.
            request := TrackJsonDecode(body)
            cost := StudyLLM_EstimateCost(request["model"], sink.Usage.Get("prompt_tokens", StrLen(body)),
                sink.Usage.Get("completion_tokens", Ceil(StrLen(sink.Content . sink.Reasoning) / 4)))
            g_StudyLLM_SpentUSD += cost
        }
    }
    return out
}

; A hidden child owns blocking HTTP reads. Anonymous pipes keep credentials
; out of files/environment/command lines and let the GUI poll without blocking.
class StudyLLM_StreamWorker {
    __New(url, key, body) {
        this.Process := 0, this.Output := 0, this.Input := 0
        childInput := 0, childOutput := 0
        attributes := Buffer(A_PtrSize * 3, 0)
        NumPut("UInt", attributes.Size, attributes)
        NumPut("Int", 1, attributes, A_PtrSize * 2)
        try {
            if !DllCall("CreatePipe", "Ptr*", &parentOutput := 0, "Ptr*", &childOutput, "Ptr", attributes, "UInt", 0)
                throw OSError()
            this.Output := parentOutput
            if !DllCall("CreatePipe", "Ptr*", &childInput, "Ptr*", &parentInput := 0, "Ptr", attributes, "UInt", 0)
                throw OSError()
            this.Input := parentInput
            DllCall("SetHandleInformation", "Ptr", this.Output, "UInt", 1, "UInt", 0)
            DllCall("SetHandleInformation", "Ptr", this.Input, "UInt", 1, "UInt", 0)
            startup := Buffer(A_PtrSize = 8 ? 104 : 68, 0)
            NumPut("UInt", startup.Size, startup)
            NumPut("UInt", 0x100, startup, A_PtrSize = 8 ? 60 : 44)
            inputOffset := A_PtrSize = 8 ? 80 : 56
            NumPut("Ptr", childInput, "Ptr", childOutput, "Ptr", childOutput, startup, inputOffset)
            info := Buffer(A_PtrSize * 2 + 8, 0)
            SplitPath(A_LineFile, , &libraryDir)
            helper := libraryDir . "\StudyStream.ps1"
            if !FileExist(helper)
                throw Error("Missing streaming worker: " . helper)
            command := '"' . A_WinDir . '\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' . helper . '"'
            commandBuffer := Buffer(StrPut(command, "UTF-16") * 2)
            StrPut(command, commandBuffer, "UTF-16")
            if !DllCall("CreateProcessW", "Ptr", 0, "Ptr", commandBuffer, "Ptr", 0, "Ptr", 0, "Int", true,
                "UInt", 0x08000000, "Ptr", 0, "Str", libraryDir, "Ptr", startup, "Ptr", info)
                throw OSError()
            this.Process := NumGet(info, 0, "Ptr")
            DllCall("CloseHandle", "Ptr", NumGet(info, A_PtrSize, "Ptr"))
            DllCall("CloseHandle", "Ptr", childInput), childInput := 0
            DllCall("CloseHandle", "Ptr", childOutput), childOutput := 0
            inputText := TrackJsonEncode(Map("url", url, "key", key, "body", body)) . "`n"
            inputBytes := Buffer(StrPut(inputText, "UTF-8"))
            StrPut(inputText, inputBytes, "UTF-8")
            offset := 0
            while offset < inputBytes.Size - 1 {
                if !DllCall("WriteFile", "Ptr", this.Input, "Ptr", inputBytes.Ptr + offset,
                    "UInt", inputBytes.Size - 1 - offset, "UInt*", &written := 0, "Ptr", 0) || !written
                    throw OSError()
                offset += written
            }
            DllCall("CloseHandle", "Ptr", this.Input), this.Input := 0
        } catch {
            this.Close()
            throw
        } finally {
            if childInput
                DllCall("CloseHandle", "Ptr", childInput)
            if childOutput
                DllCall("CloseHandle", "Ptr", childOutput)
        }
    }

    Read() {
        available := 0
        if !DllCall("PeekNamedPipe", "Ptr", this.Output, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt*", &available, "Ptr", 0)
            return Map("size", 0, "bytes", Buffer(0))
        bytes := Buffer(Min(available, 65536)), count := 0
        if bytes.Size
            DllCall("ReadFile", "Ptr", this.Output, "Ptr", bytes, "UInt", bytes.Size, "UInt*", &count, "Ptr", 0)
        return Map("size", count, "bytes", bytes)
    }

    Finished() => !this.Process || DllCall("WaitForSingleObject", "Ptr", this.Process, "UInt", 0) = 0

    Close() {
        if this.Process && !this.Finished()
            DllCall("TerminateProcess", "Ptr", this.Process, "UInt", 1)
        for handle in [this.Input, this.Output, this.Process]
            if handle
                DllCall("CloseHandle", "Ptr", handle)
        this.Input := 0, this.Output := 0, this.Process := 0
    }
}

; A single cancellable async POST. Returns Map(ok, status, text, error).
StudyLLM_Post(url, key, body) {
    out := Map("ok", false, "status", 0, "text", "", "error", "")
    try {
        whr := ComObject("WinHttp.WinHttpRequest.5.1")
        ; resolve, connect, send, receive (ms). Vision answers can be slow.
        whr.SetTimeouts(5000, 8000, 15000, 120000)
        whr.Open("POST", url, true)
        whr.SetRequestHeader("Content-Type", "application/json")
        whr.SetRequestHeader("Authorization", "Bearer " . key)
        ; WinHTTP encodes the BSTR body as UTF-8. Async receive lets ABORT land.
        whr.Send(body)
        started := A_TickCount
        while !whr.WaitForResponse(0) {
            if (g_StudyLLM_Cancel || A_TickCount - started > 120000) {
                whr.Abort()
                out["status"] := -1
                out["error"] := g_StudyLLM_Cancel ? "Cancelled" : "Request timed out"
                return out
            }
            Sleep(25)
        }
        out["status"] := whr.Status
        out["text"] := whr.ResponseText
        if (whr.Status = 200) {
            out["ok"] := true
        } else {
            ; Surface the API's error message, never the request headers.
            msg := StudyLLM_JsonStringField(whr.ResponseText, "message")
            out["error"] := "DeepSeek HTTP " . whr.Status
                          . (msg != "" ? ": " . TrackEllipsis(msg, 180) : "")
        }
    } catch as err {
        out["error"] := "Request failed: " . err.Message
    }
    return out
}

; A non-blocking-ish sleep that still lets a cancel land between slices.
StudyLLM_Sleep(ms) {
    global g_StudyLLM_Cancel
    elapsed := 0
    while (elapsed < ms) {
        if g_StudyLLM_Cancel
            return
        Sleep(100)
        elapsed += 100
    }
}

StudyLLM_CancelRequest() {
    global g_StudyLLM_Cancel
    g_StudyLLM_Cancel := true
}

StudyLLM_EstimateCost(model, promptTokens, completionTokens) {
    global g_StudyLLM_Price
    if !g_StudyLLM_Price.Has(model)
        return 0.0
    p := g_StudyLLM_Price[model]
    return (promptTokens / 1000000.0) * p["in"] + (completionTokens / 1000000.0) * p["out"]
}

StudyLLM_Fail(msg) {
    StudyConsole_Log("LLM", "failed", msg, "ERROR")
    return Map("ok", false, "answer", "", "model", "", "provider", "deepseek"
             , "promptTokens", 0, "completionTokens", 0, "costUSD", 0, "error", msg)
}

; ─────────────────────────────────────────────────────────────────────────────
; IMAGE ENCODING
; ─────────────────────────────────────────────────────────────────────────────
; Read an image file and return a base64 data URL, or "" on failure.
StudyLLM_ImageDataUrl(path) {
    if !FileExist(path)
        return ""
    SplitPath(path, , , &ext)
    ext := StrLower(ext)
    if !RegExMatch(ext, "^(png|jpg|jpeg|gif|webp)$")
        return ""
    mime := (ext = "png") ? "image/png"
          : (ext = "gif") ? "image/gif"
          : (ext = "webp") ? "image/webp" : "image/jpeg"
    b64 := StudyLLM_Base64File(path)
    if (b64 = "")
        return ""
    return "data:" . mime . ";base64," . b64
}

StudyLLM_Base64File(path) {
    raw := ""
    try raw := FileRead(path, "RAW")
    if !IsObject(raw) || raw.Size = 0
        return ""
    CRYPT_STRING_BASE64 := 0x1, CRYPT_STRING_NOCRLF := 0x40000000
    flags := CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
    size := 0
    if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", raw.Ptr, "UInt", raw.Size
              , "UInt", flags, "Ptr", 0, "UInt*", &size)
        return ""
    outBuf := Buffer(size * 2)
    if !DllCall("Crypt32\CryptBinaryToStringW", "Ptr", raw.Ptr, "UInt", raw.Size
              , "UInt", flags, "Ptr", outBuf.Ptr, "UInt*", &size)
        return ""
    return StrGet(outBuf.Ptr, size, "UTF-16")
}

; ─────────────────────────────────────────────────────────────────────────────
; MINIMAL JSON (encode a string; pull one string/int field out of a response)
; ─────────────────────────────────────────────────────────────────────────────
; Encode an AHK string as a JSON string literal (with surrounding quotes).
StudyLLM_JStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`t", "\t")
    s := StrReplace(s, Chr(8), "\b")
    s := StrReplace(s, Chr(12), "\f")
    return '"' . s . '"'
}

; Extract the first string value for `key` from a JSON document, decoding escapes.
; Scans for the key then reads the following quoted token honouring backslash
; escapes, so braces or quotes inside the value do not confuse it.
StudyLLM_JsonStringField(json, key) {
    needle := '"' . key . '"'
    p := InStr(json, needle)
    if !p
        return ""
    p += StrLen(needle)
    ; skip whitespace and the colon
    while (p <= StrLen(json) && InStr(" `t`r`n:", SubStr(json, p, 1)))
        p++
    if (SubStr(json, p, 1) != '"')
        return ""
    p++   ; past the opening quote
    out := "", len := StrLen(json)
    while (p <= len) {
        ch := SubStr(json, p, 1)
        if (ch = "\") {
            nx := SubStr(json, p + 1, 1)
            switch nx {
                case '"': out .= '"'
                case "\": out .= "\"
                case "/": out .= "/"
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "b": out .= Chr(8)
                case "f": out .= Chr(12)
                case "u":
                    code := SubStr(json, p + 2, 4)
                    if RegExMatch(code, "^[0-9A-Fa-f]{4}$") {
                        out .= Chr(Integer("0x" . code))
                        p += 6
                        continue
                    }
                    out .= nx
                default: out .= nx
            }
            p += 2
            continue
        }
        if (ch = '"')
            break
        out .= ch
        p++
    }
    return out
}

; Extract an integer field (e.g. a token count). Returns 0 when absent.
StudyLLM_JsonIntField(json, key) {
    if RegExMatch(json, '"' . key . '"\s*:\s*(\d+)', &m)
        return Integer(m[1])
    return 0
}

; Pull model ids out of a /models response ("data":[{"id":"..."}...]).
StudyLLM_ExtractModelIds(json) {
    ids := [], pos := 1
    while (pos := RegExMatch(json, '"id"\s*:\s*"([^"]+)"', &m, pos)) {
        ids.Push(m[1])
        pos += StrLen(m[0])
    }
    return ids
}

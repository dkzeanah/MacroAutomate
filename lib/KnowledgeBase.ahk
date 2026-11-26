; ═══════════════════════════════════════════════════════════════════════════════
; KnowledgeBase.ahk - knowledge heads (page 30) and the document inbox (page 31)
; ═══════════════════════════════════════════════════════════════════════════════
; The engine is the Python package fan\knowledge (SQLite + sqlite-vec vectors,
; Fan's own embedding model, head discovery). This module runs its jobs, shows
; the 20 head topics with their simple-to-complex elements, searches and answers
; questions, watches inbox folders, and turns inbox records into workflow runs.
; Writes are queued one at a time; read-only queries run alongside them.
; ═══════════════════════════════════════════════════════════════════════════════

global g_KB := Map("ui", Map(), "queue", [], "writing", false, "heads", [], "elements", [], "results", [],
    "records", [], "sources", [], "inboxSignature", "", "lastAnswer", "", "lastExport", "")

KB_WriteModes() => Map("kb_ingest", 1, "kb_text", 1, "kb_rediscover", 1, "kb_rename", 1, "kb_forget_source", 1,
    "intake_scan", 1, "intake_update", 1, "intake_export", 1)

; Queue writers one at a time; readers run immediately in their own slot.
KB_Job(mode, request, callback, timeoutMs := 600000) {
    global g_KB
    if KB_WriteModes().Has(mode) {
        if g_KB["writing"] {
            g_KB["queue"].Push([mode, request, callback, timeoutMs])
            return true
        }
        g_KB["writing"] := true
        started := Autopilot_Job(mode, request, KB_WriteDone.Bind(callback), timeoutMs, "fan.knowledge.cli", "kb_write")
        if !started
            g_KB["writing"] := false
        return started
    }
    return Autopilot_Job(mode, request, callback, timeoutMs, "fan.knowledge.cli", "kb_read_" . mode)
}

KB_WriteDone(callback, result) {
    global g_KB
    g_KB["writing"] := false
    try callback.Call(result)
    catch as err
        LogErrorToFile(err, "caught", "Knowledge job result")
    if g_KB["queue"].Length {
        next := g_KB["queue"].RemoveAt(1)
        KB_Job(next[1], next[2], next[3], next[4])
    }
}

KB_Status(text) {
    global g_KB
    if g_KB["ui"].Has("status")
        try g_KB["ui"]["status"].Value := text
}

KB_InboxStatus(text) {
    global g_KB
    if g_KB["ui"].Has("inboxStatus")
        try g_KB["ui"]["inboxStatus"].Value := text
}

KB_Start() {
    inbox := APP_ROOT . "\data\inbox"
    if !DirExist(inbox)
        try DirCreate(inbox)
    if TrackDB_Ready() && TrackDB_MetaGet("kb_inbox_folders", "") = ""
        TrackDB_MetaSet("kb_inbox_folders", TrackJsonEncode([inbox]))
    SetTimer(KB_InboxTick, 120000)
    SetTimer(KB_InboxTick, -45000)
}

; ─── page 30 · Knowledge ──────────────────────────────────────────────────────

KB_BuildPages() {
    global MainGui, TabCtrl, g_KB
    ui := g_KB["ui"]
    AutopilotUI_Title(30, "Knowledge base — everything you've read, in up to 20 head topics",
        "Add documents (PDF, Word, Excel, PowerPoint, CSV, text, web pages, email, scans). Fan splits them into single ideas, groups them under "
        . "head topics it discovers from your own wording (dome, domes, GeodesicDome and domes.com count as one), and orders each topic from simple to complex.")
    ui["addFiles"] := MainGui.Add("Button", "x16 y124 w110 h28", "Add files…")
    ui["addFolder"] := MainGui.Add("Button", "x132 y124 w110 h28", "Add folder…")
    ui["addNotes"] := MainGui.Add("Button", "x248 y124 w140 h28", "Add Fan notes")
    ui["rediscover"] := MainGui.Add("Button", "x394 y124 w130 h28", "Rediscover heads")
    ui["export"] := MainGui.Add("Button", "x530 y124 w170 h28", "Export knowledge pack")
    ui["sourcesBtn"] := MainGui.Add("Button", "x706 y124 w170 h28", "Documents…")
    ui["status"] := MainGui.Add("Text", "x16 y158 w860 h18 cGray", "Add a folder of documents to begin. Everything stays on this computer.")
    ui["heads"] := MainGui.Add("ListView", "x16 y180 w410 h196 Grid -Multi AltSubmit", ["Head topic", "Ideas", "Docs", "Levels 1-5", "Key terms"])
    for col, width in [120, 50, 42, 82, 400]
        ui["heads"].ModifyCol(col, width)
    ui["rename"] := MainGui.Add("Button", "x16 y380 w110 h24", "Rename head")
    ui["unlock"] := MainGui.Add("Button", "x132 y380 w130 h24", "Let Fan rename it")
    ui["headInfo"] := MainGui.Add("Text", "x436 y180 w440 h40", "Select a head to see its ideas, simplest first.")
    ui["elements"] := MainGui.Add("ListView", "x436 y222 w440 h182 Grid -Multi", ["#", "Level", "Idea", "From"])
    for col, width in [34, 44, 270, 88]
        ui["elements"].ModifyCol(col, width)
    ui["query"] := MainGui.Add("Edit", "x16 y414 w560 h24", "")
    SendMessage(0x1501, 1, StrPtr("Search or ask a question, e.g. how do I join dome struts?"), ui["query"])  ; EM_SETCUEBANNER
    ui["search"] := MainGui.Add("Button", "x584 y413 w80 h26", "Search")
    ui["ask"] := MainGui.Add("Button", "x670 y413 w80 h26", "Ask")
    ui["inHead"] := MainGui.Add("CheckBox", "x758 y417 w118", "Selected head")
    ui["answer"] := MainGui.Add("Edit", "x16 y446 w860 h96 ReadOnly Multi", "")
    ui["results"] := MainGui.Add("ListView", "x16 y548 w860 h144 Grid -Multi", ["Match", "Head", "Level", "Idea", "Source"])
    for col, width in [52, 100, 44, 500, 150]
        ui["results"].ModifyCol(col, width)
    ui["backend"] := MainGui.Add("Text", "x16 y698 w860 h28 cGray", "")
    ui["addFiles"].OnEvent("Click", KB_AddFiles)
    ui["addFolder"].OnEvent("Click", KB_AddFolder)
    ui["addNotes"].OnEvent("Click", KB_AddNotes)
    ui["rediscover"].OnEvent("Click", (*) => (KB_Status("Rediscovering head topics..."), KB_Job("kb_rediscover", Map(), KB_StatusDone)))
    ui["export"].OnEvent("Click", KB_Export)
    ui["sourcesBtn"].OnEvent("Click", KB_ShowSources)
    ui["heads"].OnEvent("ItemSelect", KB_HeadSelected)
    ui["rename"].OnEvent("Click", KB_Rename)
    ui["unlock"].OnEvent("Click", KB_Unlock)
    ui["search"].OnEvent("Click", (*) => KB_Query("kb_search"))
    ui["ask"].OnEvent("Click", (*) => KB_Query("kb_ask"))
    ui["results"].OnEvent("DoubleClick", KB_OpenResult)
    ui["elements"].OnEvent("DoubleClick", KB_OpenElement)

    ; ── 31 · Document inbox ──────────────────────────────────────────────────
    AutopilotUI_Title(31, "Document inbox — drop files in, get records out",
        "Invoices, receipts, purchase orders, statements, quotes and forms dropped into a watched folder are read, their fields are extracted, "
        . "and they join the knowledge base. Export the records to CSV, or hand them to a data-entry workflow as $var.total, $var.vendor and so on.")
    ui["folders"] := MainGui.Add("ListBox", "x16 y124 w560 h64", [])
    ui["addInbox"] := MainGui.Add("Button", "x584 y124 w140 h26", "Watch a folder…")
    ui["removeInbox"] := MainGui.Add("Button", "x730 y124 w146 h26", "Stop watching")
    ui["openInbox"] := MainGui.Add("Button", "x584 y156 w140 h26", "Open inbox folder")
    ui["watch"] := MainGui.Add("CheckBox", "x730 y160 w146", "Watch automatically")
    ui["checkNow"] := MainGui.Add("Button", "x16 y196 w110 h28", "Check now")
    ui["exportCsv"] := MainGui.Add("Button", "x132 y196 w110 h28", "Export CSV")
    ui["openExports"] := MainGui.Add("Button", "x248 y196 w120 h28", "Open exports")
    ui["useAi"] := MainGui.Add("CheckBox", "x382 y202 w494", "Use AI to read documents (sends document text to DeepSeek)")
    ui["inboxStatus"] := MainGui.Add("Text", "x16 y230 w860 h18 cGray", "")
    ui["records"] := MainGui.Add("ListView", "x16 y252 w860 h240 Grid -Multi AltSubmit",
        ["Received", "File", "Type", "Number", "From", "Date", "Due", "Total", "Status"])
    for col, width in [112, 170, 80, 80, 140, 78, 78, 70, 60]
        ui["records"].ModifyCol(col, width)
    ui["fields"] := MainGui.Add("Edit", "x16 y498 w560 h120 Multi WantReturn", "")
    ui["saveFields"] := MainGui.Add("Button", "x584 y498 w140 h26", "Save field edits")
    ui["markEntered"] := MainGui.Add("Button", "x730 y498 w146 h26", "Mark entered")
    ui["ignoreRecord"] := MainGui.Add("Button", "x584 y530 w140 h26", "Ignore")
    ui["openRecord"] := MainGui.Add("Button", "x730 y530 w146 h26", "Open document")
    ui["fieldHelp"] := MainGui.Add("Text", "x584 y562 w292 h56 cGray", "One field per line as name: value. Fields found by AI are marked; check them before entering.")
    MainGui.Add("Text", "x16 y630 w170", "Data-entry workflow for")
    ui["ruleType"] := MainGui.Add("DropDownList", "x186 y626 w130", ["invoice", "receipt", "purchase_order", "statement", "quote", "contract", "resume", "letter", "form", "other"])
    MainGui.Add("Text", "x322 y630 w20", "→")
    ui["ruleWorkflow"] := MainGui.Add("DropDownList", "x342 y626 w234", [])
    ui["saveRule"] := MainGui.Add("Button", "x584 y624 w140 h26", "Save rule")
    ui["runRecord"] := MainGui.Add("Button", "x730 y624 w146 h26", "Run for this record")
    ui["ruleInfo"] := MainGui.Add("Text", "x16 y658 w860 h34 cGray", "")
    MainGui.Add("Text", "x16 y698 w860 h28 cGray",
        "When a new document matches a rule, Fan asks before running its workflow. The workflow starts with the fields as variables ($var.number, $var.total, $var.due_date, $var.vendor…).")
    ui["watch"].Value := TrackDB_MetaGet("kb_inbox_watch", "1") = "1"
    ui["useAi"].Value := TrackDB_MetaGet("kb_inbox_ai", "0") = "1"
    ui["ruleType"].Choose(1)
    ui["addInbox"].OnEvent("Click", KB_AddInbox)
    ui["removeInbox"].OnEvent("Click", KB_RemoveInbox)
    ui["openInbox"].OnEvent("Click", (*) => Run('"' . APP_ROOT . '\data\inbox"'))
    ui["watch"].OnEvent("Click", (ctl, *) => TrackDB_MetaSet("kb_inbox_watch", ctl.Value ? "1" : "0"))
    ui["useAi"].OnEvent("Click", (ctl, *) => TrackDB_MetaSet("kb_inbox_ai", ctl.Value ? "1" : "0"))
    ui["checkNow"].OnEvent("Click", (*) => KB_InboxScan(true))
    ui["exportCsv"].OnEvent("Click", KB_ExportCsv)
    ui["openExports"].OnEvent("Click", KB_OpenExports)
    ui["records"].OnEvent("ItemSelect", KB_RecordSelected)
    ui["records"].OnEvent("DoubleClick", KB_OpenRecord)
    ui["saveFields"].OnEvent("Click", KB_SaveFields)
    ui["markEntered"].OnEvent("Click", (*) => KB_SetRecordStatus("entered"))
    ui["ignoreRecord"].OnEvent("Click", (*) => KB_SetRecordStatus("ignored"))
    ui["openRecord"].OnEvent("Click", KB_OpenRecord)
    ui["saveRule"].OnEvent("Click", KB_SaveRule)
    ui["ruleType"].OnEvent("Change", (*) => KB_ShowRule())
    ui["runRecord"].OnEvent("Click", KB_RunRecord)
    TabCtrl.UseTab(0)
}

KB_PageShown(page) {
    try {
        if page = 30
            KB_Job("kb_status", Map(), KB_StatusDone)
        else if page = 31
            KB_RefreshInboxPage()
    } catch as err
        LogErrorToFile(err, "caught", "Knowledge page " . page)
}

KB_StatusDone(result) {
    global g_KB
    ui := g_KB["ui"]
    if !result.Get("ok", false) {
        KB_Status("Knowledge base: " . result.Get("error", "unknown error"))
        return
    }
    if result.Has("heads")
        KB_FillHeads(result["heads"])
    stats := result.Get("stats", 0)
    if stats is Map {
        ui["backend"].Value := "Vector index: " . stats["backend_detail"] . " · model " . stats["model"] . " · " . stats["elements"]
            . " ideas from " . stats["sources"] . " documents (" . stats["roots"] . " word roots) · " . stats["megabytes"] . " MB · heads last discovered " . stats["last_discovery"]
    }
    mode := result.Get("mode", "")
    if mode = "kb_ingest" {
        failed := result.Get("failed", [])
        KB_Status("Read " . result["ingested"].Length . " document(s): " . result["new_elements"] . " new ideas, " . result["reinforced"]
            . " repeats strengthened, " . result["skipped"] . " unchanged" . (failed.Length ? ", " . failed.Length . " failed (see Documents…)" : "")
            . (result.Get("rediscovered", false) ? ". Head topics were rediscovered." : ".") . (result.Get("stopped_early", false) ? " Time limit reached; add again to continue." : ""))
    } else if mode = "kb_rediscover"
        KB_Status("Rediscovered " . result["heads"].Length . " head topic(s); " . result.Get("moved", 0) . " ideas changed head.")
    else if mode = "kb_status" && result["stats"]["elements"] = 0
        KB_Status("Add a folder of documents to begin. Everything stays on this computer.")
}

KB_FillHeads(heads) {
    global g_KB
    g_KB["heads"] := heads
    lv := g_KB["ui"]["heads"]
    lv.Opt("-Redraw"), lv.Delete()
    for , h in heads {
        levels := h["levels"]
        lv.Add("", h["name"] . (h["locked"] ? " ✎" : ""), h["elements"], h["sources"], levels[1] . "·" . levels[2] . "·" . levels[3] . "·" . levels[4] . "·" . levels[5],
            StrJoin(h["roots"], ", "))
    }
    lv.Opt("+Redraw")
}

KB_SelectedHead() {
    global g_KB
    row := AutopilotUI_Selected(g_KB["ui"]["heads"])
    return row && row <= g_KB["heads"].Length ? g_KB["heads"][row] : 0
}

KB_HeadSelected(lv, row, selected) {
    global g_KB
    if !selected || row > g_KB["heads"].Length
        return
    h := g_KB["heads"][row]
    g_KB["ui"]["headInfo"].Value := h["name"] . (h["aliases"].Length ? " — also written " . StrJoin(h["aliases"], ", ") : "")
        . (h["phrases"].Length ? "`nPhrases: " . StrJoin(h["phrases"], ", ") : "")
    KB_Job("kb_head", Map("head_id", h["id"], "limit", 400), KB_HeadDone)
}

KB_HeadDone(result) {
    global g_KB
    if !result.Get("ok", false)
        return KB_Status("Could not load the head: " . result.Get("error", ""))
    g_KB["elements"] := result["elements"]
    lv := g_KB["ui"]["elements"]
    lv.Opt("-Redraw"), lv.Delete()
    for , e in result["elements"]
        lv.Add("", e["seq"], e["level"] . (e["definition"] ? " ★" : ""), e["text"], e["source"])
    lv.Opt("+Redraw")
}

KB_AddFiles(*) {
    files := FileSelect("M3", , "Add documents to the knowledge base",
        "Documents (*.pdf; *.docx; *.doc; *.xlsx; *.xls; *.pptx; *.csv; *.txt; *.md; *.html; *.htm; *.eml; *.rtf; *.odt; *.json; *.png; *.jpg; *.tif)")
    if !(files is Array) || !files.Length
        return
    KB_Status("Reading " . files.Length . " document(s)...")
    KB_Job("kb_ingest", Map("paths", files, "origin", "manual", "max_seconds", 1500), KB_StatusDone, 1800000)
}

KB_AddFolder(*) {
    folder := DirSelect("*" . A_MyDocuments, 0, "Choose a folder of documents (subfolders are included)")
    if folder = ""
        return
    KB_Status("Reading documents in " . folder . "... this can take a while for large folders.")
    KB_Job("kb_ingest", Map("folders", [folder], "origin", "folder", "max_seconds", 3000), KB_StatusDone, 3600000)
}

KB_AddNotes(*) {
    global NOTES_DIR
    folders := []
    if IsSet(NOTES_DIR) && DirExist(NOTES_DIR)
        folders.Push(NOTES_DIR)
    if DirExist(APP_ROOT . "\data\notes")
        folders.Push(APP_ROOT . "\data\notes")
    if !folders.Length
        return KB_Status("No Fan notes folder was found.")
    KB_Status("Reading Fan notes...")
    KB_Job("kb_ingest", Map("folders", folders, "origin", "fan-notes"), KB_StatusDone)
}

KB_Rename(*) {
    h := KB_SelectedHead()
    if !IsObject(h) || h["id"] = 0
        return MsgBoxTop("Select a head topic first.", "Knowledge base", "Iconi")
    reply := InputBox("New name for '" . h["name"] . "' (Fan keeps your name when it rediscovers heads):", "Rename head", "w420 h140", h["name"])
    if reply.Result = "OK" && Trim(reply.Value) != ""
        KB_Job("kb_rename", Map("head_id", h["id"], "name", Trim(reply.Value)), KB_StatusDone)
}

KB_Unlock(*) {
    h := KB_SelectedHead()
    if IsObject(h) && h["id"]
        KB_Job("kb_rename", Map("head_id", h["id"], "unlock", 1), KB_StatusDone)
}

KB_Query(mode) {
    global g_KB
    ui := g_KB["ui"]
    text := Trim(ui["query"].Value)
    if text = ""
        return
    request := Map(mode = "kb_ask" ? "question" : "query", text, "k", mode = "kb_ask" ? 8 : 25)
    h := KB_SelectedHead()
    if mode = "kb_search" && ui["inHead"].Value && IsObject(h)
        request["head_id"] := h["id"]
    ui["answer"].Value := mode = "kb_ask" ? "Thinking through your head topics..." : "Searching..."
    KB_Job(mode, request, KB_QueryDone)
}

KB_QueryDone(result) {
    global g_KB
    ui := g_KB["ui"]
    if !result.Get("ok", false) {
        ui["answer"].Value := "Search failed: " . result.Get("error", "")
        return
    }
    names := Map()
    for , h in g_KB["heads"]
        names[h["id"]] := h["name"]
    items := result.Has("answer") ? result["answer"] : result["elements"]
    if result.Has("answer") {
        heads := []
        for , h in result["heads"]
            heads.Push(h["name"] . " " . Round(h["score"] * 100) . "%")
        start := []
        for , e in result["start_here"]
            start.Push("• " . e["text"])
        ui["answer"].Value := (heads.Length ? "Best matching heads: " . StrJoin(heads, ", ") . "`r`n`r`n" : "")
            . (start.Length ? "Start here:`r`n" . StrJoin(start, "`r`n") . "`r`n`r`n" : "")
            . (result["summary"] != "" ? result["summary"] : "Nothing in your documents answers that yet.")
    } else
        ui["answer"].Value := items.Length . " matching idea(s) for '" . result["query"] . "'. Double-click one to open its document."
    g_KB["results"] := items
    lv := ui["results"]
    lv.Opt("-Redraw"), lv.Delete()
    for , e in items
        lv.Add("", e["score"] != "" ? Round(e["score"] * 100) . "%" : "", names.Has(e["head_id"]) ? names[e["head_id"]] : "(unsorted)",
            e["level"], e["text"], e["source"] . (e["locator"] != "" ? " · " . e["locator"] : ""))
    lv.Opt("+Redraw")
}

KB_OpenPath(path) {
    if path = "" || SubStr(path, 1, 7) = "text://" || !FileExist(path)
        return MsgBoxTop("That idea came from text that is not a file on disk.", "Knowledge base", "Iconi")
    try Run('"' . path . '"')
}

KB_OpenResult(lv, row) {
    global g_KB
    if row && row <= g_KB["results"].Length
        KB_OpenPath(g_KB["results"][row]["path"])
}

KB_OpenElement(lv, row) {
    global g_KB
    if row && row <= g_KB["elements"].Length
        KB_OpenPath(g_KB["elements"][row]["path"])
}

KB_Export(*) {
    out := APP_ROOT . "\data\knowledge\export"
    KB_Status("Exporting the knowledge pack...")
    KB_Job("kb_export", Map("out_dir", out), KB_ExportDone)
}

KB_ExportDone(result) {
    if !result.Get("ok", false)
        return KB_Status("Export failed: " . result.Get("error", ""))
    KB_Status("Exported " . result["heads"] . " head topics, " . result["vocabulary"] . " terms (" . result["megabytes"]
        . " MB) and a primer per head to data\knowledge\export.")
    try Run('"' . APP_ROOT . '\data\knowledge\export"')
}

KB_ShowSources(*) {
    KB_Job("kb_sources", Map("limit", 1000), KB_SourcesDone)
}

KB_SourcesDone(result) {
    global MainGui, g_KB
    if !result.Get("ok", false)
        return KB_Status(result.Get("error", ""))
    g_KB["sources"] := result["sources"]
    dialog := Gui("+Owner" . MainGui.Hwnd . " +Resize", "Documents in the knowledge base")
    dialog.SetFont("s9", "Segoe UI")
    lv := dialog.Add("ListView", "w880 h420 Grid", ["Updated", "Document", "Kind", "Read with", "Ideas", "Status", "Problem"])
    for col, width in [120, 260, 50, 90, 50, 60, 240]
        lv.ModifyCol(col, width)
    for , s in result["sources"]
        lv.Add("", s["updated"], s["title"], s["kind"], s["method"], s["elements"], s["status"], s["error"])
    dialog.Add("Button", "w170", "Open document").OnEvent("Click", (*) => (row := lv.GetNext(), row ? KB_OpenPath(g_KB["sources"][row]["path"]) : 0))
    dialog.Add("Button", "x+8 w220", "Forget this document").OnEvent("Click", (*) => KB_ForgetSource(lv, dialog))
    dialog.Add("Button", "x+8 w100", "Close").OnEvent("Click", (*) => dialog.Destroy())
    dialog.OnEvent("Escape", (*) => dialog.Destroy())
    dialog.Show()
}

KB_ForgetSource(lv, dialog) {
    global g_KB
    row := lv.GetNext()
    if !row
        return
    source := g_KB["sources"][row]
    if MsgBoxTop("Remove everything learned only from '" . source["title"] . "'? Ideas also found in other documents are kept.", "Knowledge base", "YesNo Icon? Default2") != "Yes"
        return
    dialog.Destroy()
    KB_Job("kb_forget_source", Map("source_id", source["id"]), (r) => (KB_Status("Forgot " . source["title"] . "."), KB_PageShown(30)))
}

; ─── page 31 · Document inbox ─────────────────────────────────────────────────

KB_InboxFolders() {
    folders := []
    try {
        saved := TrackJsonDecode(TrackDB_MetaGet("kb_inbox_folders", "[]"))
        if saved is Array
            for , folder in saved
                if folder != ""
                    folders.Push(folder)
    }
    return folders
}

KB_SetInboxFolders(folders) {
    TrackDB_MetaSet("kb_inbox_folders", TrackJsonEncode(folders))
    g_KB["inboxSignature"] := ""
    KB_RefreshInboxPage()
}

KB_RefreshInboxPage() {
    global g_KB, g_Sequences
    ui := g_KB["ui"]
    ui["folders"].Delete(), ui["folders"].Add(KB_InboxFolders())
    names := []
    for name in g_Sequences
        names.Push(name)
    ui["ruleWorkflow"].Delete(), ui["ruleWorkflow"].Add(names)
    KB_ShowRule()
    KB_Job("intake_records", Map("limit", 300), KB_RecordsDone)
}

KB_AddInbox(*) {
    folder := DirSelect("*" . A_MyDocuments, 1, "Choose a folder to watch for new documents")
    if folder = ""
        return
    folders := KB_InboxFolders()
    for , existing in folders
        if existing = folder
            return
    folders.Push(folder)
    KB_SetInboxFolders(folders)
}

KB_RemoveInbox(*) {
    global g_KB
    index := g_KB["ui"]["folders"].Value
    folders := KB_InboxFolders()
    if index && index <= folders.Length {
        folders.RemoveAt(index)
        KB_SetInboxFolders(folders)
    }
}

; Cheap change detection: count + newest modification time of supported files.
KB_InboxSignature(folders) {
    count := 0, newest := ""
    for , folder in folders {
        if !DirExist(folder)
            continue
        loop files folder . "\*.*", "FR" {
            if !RegExMatch(A_LoopFileExt, "i)^(pdf|docx?|xlsx?|xlsm|pptx|csv|tsv|txt|md|html?|eml|rtf|odt|ods|json|png|jpe?g|tiff?|bmp)$")
                continue
            count++
            if A_LoopFileTimeModified > newest
                newest := A_LoopFileTimeModified
            if count > 20000
                break
        }
    }
    return count . "|" . newest
}

KB_InboxTick() {
    global g_KB
    if TrackDB_MetaGet("kb_inbox_watch", "1") != "1"
        return
    folders := KB_InboxFolders()
    if !folders.Length || g_KB["writing"]
        return
    signature := KB_InboxSignature(folders)
    if signature = g_KB["inboxSignature"]
        return
    g_KB["inboxSignature"] := signature
    KB_InboxScan(false)
}

KB_InboxScan(manual) {
    global g_StudyLLM_Endpoint, g_StudyLLM_TextModel, g_StudyLLM_SpentUSD
    folders := KB_InboxFolders()
    if !folders.Length
        return KB_InboxStatus("Add a folder to watch first.")
    useAi := TrackDB_MetaGet("kb_inbox_ai", "0") = "1"
    budget := 0
    try budget := Study_GetSetting("cost_cap_usd", "2.00") + 0.0
    request := Map("folders", folders, "use_ai", useAi ? 1 : 0, "endpoint", g_StudyLLM_Endpoint, "model", g_StudyLLM_TextModel,
        "budget_usd", budget > 0 ? Max(0, budget - g_StudyLLM_SpentUSD) : 5, "max_seconds", 1500)
    KB_InboxStatus("Checking " . folders.Length . " folder(s) for new documents...")
    KB_Job("intake_scan", request, KB_ScanDone.Bind(manual), 1800000)
}

KB_ScanDone(manual, result) {
    global g_KB
    if !result.Get("ok", false)
        return KB_InboxStatus("Inbox check failed: " . result.Get("error", ""))
    records := result.Get("records", [])
    failed := result.Get("failed", [])
    KB_InboxStatus(records.Length ? records.Length . " new document(s) read" . (failed.Length ? ", " . failed.Length . " could not be read" : "") . "."
        : (manual ? "No new documents." : "") . (failed.Length ? " " . failed.Length . " could not be read." : ""))
    KB_RecordsDone(Map("ok", true, "records_list", result.Get("records_list", [])))
    if records.Length
        KB_OfferRules(records)
}

KB_OfferRules(newRecords) {
    global g_KB, g_Sequences
    rules := KB_Rules()
    for , item in newRecords {
        type := item["doc_type"]
        if !rules.Has(type) || !g_Sequences.Has(rules[type])
            continue
        for , record in g_KB["records"] {
            if record["title"] != item["title"] || record["status"] != "new"
                continue
            f := record["fields"]
            summary := "New " . StrReplace(type, "_", " ") . (f.Has("vendor") ? " from " . f["vendor"] : "")
                . (f.Has("total") ? " (" . f["total"] . ")" : "") . (f.Has("number") ? ", no. " . f["number"] : "")
            Autopilot_Toast("Fan read a document", summary . ". Enter it with '" . rules[type] . "'?",
                [["Enter it now", KB_RunRecordId.Bind(record["id"])], ["Later", (*) => 0]], 40)
            return  ; one prompt at a time
        }
    }
}

KB_RecordsDone(result) {
    global g_KB
    if !result.Get("ok", false)
        return KB_InboxStatus(result.Get("error", ""))
    g_KB["records"] := result["records_list"]
    lv := g_KB["ui"]["records"]
    lv.Opt("-Redraw"), lv.Delete()
    for , r in g_KB["records"] {
        f := r["fields"]
        lv.Add("", r["received"], r["title"], StrReplace(r["doc_type"], "_", " "), f.Get("number", ""), f.Get("vendor", ""),
            f.Get("date", ""), f.Get("due_date", ""), f.Has("total") ? f["total"] : "", r["status"])
    }
    lv.Opt("+Redraw")
}

KB_SelectedRecord() {
    global g_KB
    row := AutopilotUI_Selected(g_KB["ui"]["records"])
    return row && row <= g_KB["records"].Length ? g_KB["records"][row] : 0
}

KB_RecordSelected(lv, row, selected) {
    global g_KB
    if !selected
        return
    r := KB_SelectedRecord()
    if !IsObject(r)
        return
    lines := []
    for key, value in r["fields"] {
        how := r["field_sources"].Has(key) ? "   (" . r["field_sources"][key] . ")" : ""
        lines.Push(key . ": " . value . how)
    }
    g_KB["ui"]["fields"].Value := StrJoin(lines, "`r`n")
    try g_KB["ui"]["ruleType"].Choose(r["doc_type"])
    KB_ShowRule()
}

KB_SaveFields(*) {
    global g_KB
    r := KB_SelectedRecord()
    if !IsObject(r)
        return MsgBoxTop("Select a record first.", "Document inbox", "Iconi")
    fields := Map()
    for , line in StrSplit(g_KB["ui"]["fields"].Value, "`n", "`r") {
        if !RegExMatch(line, "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*?)\s*(?:\((?:label|AI \(check it\)|edited by you|pattern|letterhead \(first line\)|largest amount|email domain|first date in the document|keywords[^)]*)\))?\s*$", &m)
            continue
        fields[m[1]] := m[2]
    }
    for key in r["fields"]
        if !fields.Has(key)
            fields[key] := ""  ; removed lines clear the field
    KB_Job("intake_update", Map("record_id", r["id"], "fields", fields), KB_RecordsDone)
}

KB_SetRecordStatus(status) {
    r := KB_SelectedRecord()
    if IsObject(r)
        KB_Job("intake_update", Map("record_id", r["id"], "status", status), KB_RecordsDone)
}

KB_OpenRecord(*) {
    r := KB_SelectedRecord()
    if IsObject(r)
        KB_OpenPath(r["path"])
}

KB_ExportCsv(*) {
    KB_InboxStatus("Exporting new records...")
    KB_Job("intake_export", Map("out_dir", APP_ROOT . "\data\intake\exports"), KB_ExportCsvDone)
}

KB_ExportCsvDone(result) {
    if !result.Get("ok", false)
        return KB_InboxStatus("Export failed: " . result.Get("error", ""))
    parts := []
    for , f in result["files"]
        parts.Push(f["records"] . " " . StrReplace(f["type"], "_", " "))
    KB_InboxStatus(result["records"] ? "Exported " . StrJoin(parts, ", ") . " to data\intake\exports." : "Nothing new to export.")
    KB_RecordsDone(result)
}

KB_OpenExports(*) {
    dir := APP_ROOT . "\data\intake\exports"
    if !DirExist(dir)
        DirCreate(dir)
    Run('"' . dir . '"')
}

KB_Rules() {
    rules := Map()
    try {
        saved := TrackJsonDecode(TrackDB_MetaGet("kb_intake_rules", "{}"))
        if saved is Map
            rules := saved
    }
    return rules
}

KB_ShowRule() {
    global g_KB
    ui := g_KB["ui"]
    rules := KB_Rules(), type := ui["ruleType"].Text
    if rules.Has(type)
        try ui["ruleWorkflow"].Choose(rules[type])
    parts := []
    for t, w in rules
        parts.Push(StrReplace(t, "_", " ") . " → " . w)
    ui["ruleInfo"].Value := parts.Length ? "Rules: " . StrJoin(parts, " · ") : "No rules yet. Pick a document type and the workflow that enters it, then Save rule."
}

KB_SaveRule(*) {
    global g_KB
    ui := g_KB["ui"]
    if ui["ruleWorkflow"].Text = ""
        return MsgBoxTop("Choose the workflow that enters this kind of document.", "Document inbox", "Iconi")
    rules := KB_Rules()
    rules[ui["ruleType"].Text] := ui["ruleWorkflow"].Text
    TrackDB_MetaSet("kb_intake_rules", TrackJsonEncode(rules))
    KB_ShowRule()
}

KB_RunRecord(*) {
    r := KB_SelectedRecord()
    if !IsObject(r)
        return MsgBoxTop("Select a record first.", "Document inbox", "Iconi")
    KB_RunRecordId(r["id"])
}

KB_RunRecordId(recordId, *) {
    global MainGui
    for , r in g_KB["records"]
        if r["id"] = recordId
            record := r
    if !IsSet(record)
        return
    rules := KB_Rules()
    workflow := rules.Has(record["doc_type"]) ? rules[record["doc_type"]] : g_KB["ui"]["ruleWorkflow"].Text
    if workflow = ""
        return MsgBoxTop("Set a data-entry workflow for " . record["doc_type"] . " documents first.", "Document inbox", "Iconi")
    KB_Job("intake_variables", Map("record_id", recordId), KB_RunWithVariables.Bind(workflow, recordId))
}

KB_RunWithVariables(workflow, recordId, result) {
    if !result.Get("ok", false)
        return KB_InboxStatus(result.Get("error", ""))
    variables := result["variables"]
    preview := []
    for key, value in variables
        if key != "document_path"
            preview.Push(key . " = " . value)
    if MsgBoxTop("Run '" . workflow . "' with these values?`n`n" . StrJoin(preview, "`n") . "`n`nFan will use your mouse and keyboard. Press Esc to stop.",
        "Document inbox", "OKCancel Iconi") != "OK"
        return
    try {
        out := Autopilot_RunWorkflow(workflow, Map("variables", variables, "inputs", variables, "evidence", "steps"))
        if out["ok"]
            KB_Job("intake_update", Map("record_id", recordId, "status", "entered", "note", "Entered by '" . workflow . "' on " . Autopilot_Now()), KB_RecordsDone)
        KB_InboxStatus(out["ok"] ? "Entered with '" . workflow . "'. The run report has screenshots of each step." : "Stopped: " . SubStr(out["error"], 1, 160))
    } catch as err
        MsgBoxTop(err.Message, "Document inbox", "Icon!")
}

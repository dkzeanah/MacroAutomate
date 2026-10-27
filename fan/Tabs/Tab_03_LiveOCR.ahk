; ===============================================================================
; Tabs\Tab_03_LiveOCR.ahk
; TAB 3 Live OCR: capture, watch words, OCR revolver, Quick OCR (Ctrl+Shift+Q), OCR actions
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

; pattern: Optional regex to extract specific text
; labelIndex: Which word index in region (0 = all, 1 = first word, etc.)
DefineWatchWord(name, region, pattern := "", labelIndex := 0) {
    global g_WatchWords

    g_WatchWords[name] := Map(
        "region", region,
        "pattern", pattern,
        "labelIndex", labelIndex,
        "lastValue", "",
        "lastCoords", Map("x", 0, "y", 0, "w", 0, "h", 0),
        "lastUpdate", 0
    )

    SaveWatchWords()
    return true
}

; Update a watch word by running OCR on its region
UpdateWatchWord(name) {
    global g_WatchWords, g_WordVariables

    if !g_WatchWords.Has(name)
        return false

    watch := g_WatchWords[name]
    region := watch["region"]

    try {
        w := region["x2"] - region["x1"]
        h := region["y2"] - region["y1"]

        if w < 10 || h < 10
            return false

        result := OCR.FromRect(region["x1"], region["y1"], w, h)

        if result.Words.Length = 0
            return false

        ; Get text based on labelIndex
        if watch["labelIndex"] = 0 {
            ; All text
            value := result.Text
            coords := Map("x", region["x1"], "y", region["y1"], "w", w, "h", h)
        } else if watch["labelIndex"] <= result.Words.Length {
            ; Specific word
            word := result.Words[watch["labelIndex"]]
            value := word.Text
            coords := Map("x", word.x, "y", word.y, "w", word.w, "h", word.h)
        } else {
            return false
        }

        ; Apply regex pattern if specified
        if watch["pattern"] != "" {
            if RegExMatch(value, watch["pattern"], &match)
                value := match[0]
        }

        ; Update watch word
        watch["lastValue"] := value
        watch["lastCoords"] := coords
        watch["lastUpdate"] := A_TickCount

        ; Store in variables for workflow use
        g_WordVariables["$word." . name] := value
        g_SpoolVariables["$word." . name] := value

        return true
    } catch {
        return false
    }
}

; Update all watch words
UpdateAllWatchWords() {
    global g_WatchWords

    for name, watch in g_WatchWords {
        UpdateWatchWord(name)
    }
}

; Get watch word value
GetWatchWordValue(name) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return ""

    return g_WatchWords[name]["lastValue"]
}

; Get watch word coordinates
GetWatchWordCoords(name) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return Map("x", 0, "y", 0, "w", 0, "h", 0)

    return g_WatchWords[name]["lastCoords"]
}

; Click on a watch word (uses last known coordinates)
ClickWatchWord(name, clickType := "Click") {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return false

    coords := g_WatchWords[name]["lastCoords"]
    if coords["w"] = 0
        return false

    x := coords["x"] + coords["w"] // 2
    y := coords["y"] + coords["h"] // 2

    switch clickType {
        case "Click": Click(x, y)
        case "DblClick": Click(x, y, 2)
        case "RClick": Click(x, y, "Right")
    }

    return true
}

; Highlight a watch word on screen
HighlightWatchWord(name, duration := 2000) {
    global g_WatchWords

    if !g_WatchWords.Has(name)
        return 0

    coords := g_WatchWords[name]["lastCoords"]
    if coords["w"] = 0
        return 0

    return HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], duration, "word", name . ": " . g_WatchWords[name]["lastValue"])
}

; Save watch words to file
SaveWatchWords() {
    global g_WatchWords, OCR_WORDS_FILE

    try FanFileDelete(OCR_WORDS_FILE)

    for name, watch in g_WatchWords {
        section := "[" . name . "]`n"
        section .= "x1=" . watch["region"]["x1"] . "`n"
        section .= "y1=" . watch["region"]["y1"] . "`n"
        section .= "x2=" . watch["region"]["x2"] . "`n"
        section .= "y2=" . watch["region"]["y2"] . "`n"
        section .= "pattern=" . watch["pattern"] . "`n"
        section .= "labelIndex=" . watch["labelIndex"] . "`n"

        FanFileAppend(section . "`n", OCR_WORDS_FILE)
    }
}

; Load watch words from file
LoadWatchWords() {
    global g_WatchWords, OCR_WORDS_FILE

    if !FanFileExist(OCR_WORDS_FILE)
        return

    try {
        content := FanFileRead(OCR_WORDS_FILE)
    } catch {
        return  ; File read failed, just return
    }

    if content = ""
        return

    currentName := ""
    currentWatch := Map()

    for line in StrSplit(content, "`n") {
        line := Trim(line)
        if line = ""
            continue

        if SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]" {
            ; Save previous watch if exists
            if currentName != "" && currentWatch.Has("region") {
                g_WatchWords[currentName] := currentWatch
            }

            currentName := SubStr(line, 2, -1)
            currentWatch := Map(
                "region", Map("x1", 0, "y1", 0, "x2", 0, "y2", 0),
                "pattern", "",
                "labelIndex", 0,
                "lastValue", "",
                "lastCoords", Map("x", 0, "y", 0, "w", 0, "h", 0),
                "lastUpdate", 0
            )
        } else if InStr(line, "=") {
            parts := StrSplit(line, "=", , 2)
            key := parts[1]
            val := parts.Length > 1 ? parts[2] : ""

            switch key {
                case "x1": currentWatch["region"]["x1"] := Integer(val)
                case "y1": currentWatch["region"]["y1"] := Integer(val)
                case "x2": currentWatch["region"]["x2"] := Integer(val)
                case "y2": currentWatch["region"]["y2"] := Integer(val)
                case "pattern": currentWatch["pattern"] := val
                case "labelIndex": currentWatch["labelIndex"] := Integer(val)
            }
        }
    }

    ; Save last watch
    if currentName != "" && currentWatch.Has("region") {
        g_WatchWords[currentName] := currentWatch
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN TEST HIGHLIGHTING - USES STANDARDIZED OVERLAY SYSTEM
; ═══════════════════════════════════════════════════════════════════════════════
; PATTERN TEST HIGHLIGHTING - Uses standardized overlay system
; =============================================================================

; Test a FindText pattern and highlight the result



; ═══════════════════════════════════════════════════════════════════════════════
; LIVE OCR FUNCTIONS (TAB 3)
; ═══════════════════════════════════════════════════════════════════════════════
; LIVE OCR FUNCTIONS (Tab 3)
; =============================================================================

global g_OCRRegion := Map("x1", 0, "y1", 0, "x2", 0, "y2", 0)  ; Custom OCR region
global g_LastOCRResult := ""  ; Store last OCR result object

ToggleOCRRecording(*) {
    global g_OCRRecording, OCRRecordingToggle, g_OCRSettings

    g_OCRRecording := OCRRecordingToggle.Value
    UpdateOCRRecordingStatus()

    if g_OCRRecording {
        interval := Integer(MainGui["OCRInterval"].Value)
        if interval < 100
            interval := 100
        SetTimer(LiveOCRCapture, interval)
        SpoolLogAdd("Live OCR started (interval: " . interval . "ms)")
    } else {
        SetTimer(LiveOCRCapture, 0)
        SpoolLogAdd("Live OCR stopped")
    }
}

UpdateOCRRecordingStatus() {
    global g_OCRRecording
    try {
        ctrl := MainGui["OCRRecordingStatus"]
        if g_OCRRecording {
            ctrl.Value := "RECORDING"
            ctrl.Opt("cRed")
        } else {
            ctrl.Value := "STOPPED"
            ctrl.Opt("cGray")
        }
    }
}

; Continuous OCR capture function
LiveOCRCapture() {
    global g_OCRRegion, g_OCRLog, g_LastOCRResult, OCR_LOG_FILE, g_DB

    try {
        startTime := A_TickCount

        ; Get OCR options
        scale := 1.0
        try scale := Float(MainGui["OCRScale"].Value)
        grayscale := MainGui["OCRGrayscale"].Value
        lang := MainGui["OCRLang"].Text

        opts := {lang: lang, scale: scale, grayscale: grayscale}

        ; Perform OCR based on region
        if g_OCRRegion["x2"] > 0 && g_OCRRegion["y2"] > 0 {
            ; Custom region
            w := g_OCRRegion["x2"] - g_OCRRegion["x1"]
            h := g_OCRRegion["y2"] - g_OCRRegion["y1"]
            result := OCR.FromRect(g_OCRRegion["x1"], g_OCRRegion["y1"], w, h, opts)
        } else {
            ; Full screen
            result := OCR.FromDesktop(opts)
        }

        g_LastOCRResult := result

        captureTime := A_TickCount - startTime

        ; Update display
        MainGui["OCROutput"].Value := result.Text
        MainGui["OCRWordCount"].Value := result.Words.Length
        MainGui["OCRLineCount"].Value := result.Lines.Length
        MainGui["OCRTextAngle"].Value := Round(result.TextAngle, 1) . "°"
        MainGui["OCRCaptureTime"].Value := captureTime . " ms"

        ; Update word list
        RefreshOCRWordLV(result)

        ; Log to file if recording
        if g_OCRRecording && result.Text != "" {
            timestamp := FormatTime(, "yyyy-MM-dd HH:mm:ss")
            cleanText := StrReplace(result.Text, "`n", " ")
            logEntry := timestamp . "|" . cleanText . "|" . result.Words.Length
            g_OCRLog.Push(logEntry)
            MainGui["OCRLogCount"].Value := g_OCRLog.Length

            ; Persist full history to SQLite (durable across restarts, no size cap)
            if IsObject(g_DB)
                g_DB.Exec("INSERT INTO ocr_log (ts, text, word_count) VALUES (" . SQLQuote(timestamp) . ", " . SQLQuote(cleanText) . ", " . result.Words.Length . ");")

            ; Append to file
            try FanFileAppend(logEntry . "`n", OCR_LOG_FILE)
        }
    } catch as err {
        MainGui["OCROutput"].Value := "OCR Error: " . err.Message
    }
}

CaptureOCROnce(*) {
    LiveOCRCapture()
    ShowStatus("OCR capture complete", "ok")
}

SelectOCRRegion(*) {
    global g_OCRRegion, MainGui

    MainGui.Hide()
    Sleep(100)

    ; Create overlay
    overlayGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "OCRRegionOverlay")
    overlayGui.BackColor := "000000"
    overlayGui.Show("x0 y0 w" . A_ScreenWidth . " h" . A_ScreenHeight . " NoActivate")
    WinSetTransparent(1, overlayGui)

    TrackToolTip("🎯 Drag to select OCR region`nESC to cancel`nRight-click for Full Screen", A_ScreenWidth//2 - 150, 50)

    x1 := 0, y1 := 0, x2 := 0, y2 := 0
    cancelled := false
    fullScreen := false

    selBox := ""

    ; Wait for input
    while !GetKeyState("LButton", "P") && !GetKeyState("RButton", "P") && !GetKeyState("Escape", "P") {
        Sleep(10)
    }

    if GetKeyState("Escape", "P") {
        cancelled := true
    } else if GetKeyState("RButton", "P") {
        fullScreen := true
    }

    if !cancelled && !fullScreen {
        MouseGetPos(&x1, &y1)

        selBox := Gui("+AlwaysOnTop -Caption +ToolWindow", "OCRSelectBox")
        selBox.BackColor := "00FF00"

        while GetKeyState("LButton", "P") {
            MouseGetPos(&x2, &y2)
            left := Min(x1, x2)
            top := Min(y1, y2)
            w := Abs(x2 - x1)
            h := Abs(y2 - y1)

            if w > 5 && h > 5 {
                selBox.Show("x" . left . " y" . top . " w" . w . " h" . h . " NoActivate")
                WinSetTransparent(80, selBox)
                TrackToolTip("Region: " . w . " x " . h, x2 + 20, y2 + 20)
            }
            Sleep(16)
        }
    }

    TrackToolTip()
    try selBox.Destroy()
    overlayGui.Destroy()

    if cancelled {
        MainGui.Show()
        return
    }

    if fullScreen {
        g_OCRRegion["x1"] := 0
        g_OCRRegion["y1"] := 0
        g_OCRRegion["x2"] := 0
        g_OCRRegion["y2"] := 0
        MainGui["OCRRegionDisplay"].Value := "Region: Full Screen"
        MainGui["OCRRegionPreview"].Value := "Full Screen`n" . A_ScreenWidth . " x " . A_ScreenHeight
    } else {
        g_OCRRegion["x1"] := Min(x1, x2)
        g_OCRRegion["y1"] := Min(y1, y2)
        g_OCRRegion["x2"] := Max(x1, x2)
        g_OCRRegion["y2"] := Max(y1, y2)

        w := g_OCRRegion["x2"] - g_OCRRegion["x1"]
        h := g_OCRRegion["y2"] - g_OCRRegion["y1"]

        MainGui["OCRRegionDisplay"].Value := "Region: " . w . "x" . h
        MainGui["OCRRegionPreview"].Value := "Custom Region`n" . g_OCRRegion["x1"] . "," . g_OCRRegion["y1"] . " to " . g_OCRRegion["x2"] . "," . g_OCRRegion["y2"] . "`n" . w . " x " . h . " pixels"
    }

    MainGui.Show()
}

GetOCRLanguages(*) {
    try {
        langs := OCR.GetAvailableLanguages()
        langList := ""
        for lang in langs
            langList .= lang . "`n"
        MsgBoxTop("Available OCR Languages:`n`n" . langList, "OCR Languages")
    } catch as err {
        MsgBoxTop("Error getting languages: " . err.Message, "Error")
    }
}

RefreshOCRWordLV(result) {
    global OCRLV

    OCRLV.Delete()

    ; Only show Word, X, Y (w/h available via click)
    for word in result.Words {
        OCRLV.Add("", word.Text, word.x, word.y)
    }
}

OnOCRWordSelect(LV, RowNumber, *) {
    global g_LastOCRResult

    if !IsNumber(RowNumber) || RowNumber < 1 || !IsObject(g_LastOCRResult)
        return

    ; Get word and highlight it using standardized overlay
    if RowNumber <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[RowNumber]
        ; Use our standardized overlay system instead of OCR library
        HighlightRegion(word.x, word.y, word.w, word.h, 2000, "word", word.Text)
    }
}

FindInOCR(*) {
    global g_LastOCRResult, OCRSearchEdit

    if !IsObject(g_LastOCRResult) {
        ShowStatus("No OCR result to search", "fail")
        return
    }

    needle := MainGui["OCRSearch"].Value
    if needle = "" {
        ShowStatus("Enter search text", "fail")
        return
    }

    caseSense := MainGui["OCRCaseSense"].Value

    ; Search through words manually for more reliable results
    foundWords := []
    for word in g_LastOCRResult.Words {
        if caseSense {
            if InStr(word.Text, needle, true)
                foundWords.Push(word)
        } else {
            if InStr(word.Text, needle)
                foundWords.Push(word)
        }
    }

    if foundWords.Length > 0 {
        ; Highlight first match
        w := foundWords[1]
        HighlightRegion(w.x, w.y, w.w, w.h, 3000, "match", needle)
        ShowStatus("Found: '" . needle . "' at " . w.x . "," . w.y . " (" . foundWords.Length . " total)", "ok")
    } else {
        ; Try finding in full text
        if InStr(g_LastOCRResult.Text, needle, caseSense) {
            ShowStatus("Found in text but not as separate word", "info")
        } else {
            ShowStatus("'" . needle . "' not found", "info")
        }
    }
}

HighlightOCRMatch(*) {
    global g_LastOCRResult

    if !IsObject(g_LastOCRResult) {
        ShowStatus("No OCR result", "fail")
        return
    }

    needle := MainGui["OCRSearch"].Value
    if needle = "" {
        ShowStatus("Enter search text", "fail")
        return
    }

    caseSense := MainGui["OCRCaseSense"].Value

    ; Find and highlight ALL matching words
    foundCount := 0
    for word in g_LastOCRResult.Words {
        match := caseSense ? InStr(word.Text, needle, true) : InStr(word.Text, needle)
        if match {
            HighlightRegion(word.x, word.y, word.w, word.h, 5000, "match", "")
            foundCount++
        }
    }

    if foundCount > 0 {
        ShowStatus("Highlighted " . foundCount . " matches", "ok")
    } else {
        ShowStatus("No word matches found", "info")
    }
}

ClearOCRHighlights(*) {
    ; Use our standardized overlay clearing
    ClearAllOverlays()
    ShowStatus("Highlights cleared", "ok")
}


; ═══════════════════════════════════════════════════════════════════════════════
; WATCH WORD UI HANDLERS
; ═══════════════════════════════════════════════════════════════════════════════
; WATCH WORD UI HANDLERS
; =============================================================================

; Double-click on OCR word - highlight and show info
OnOCRWordDblClick(LV, RowNumber, *) {
    global g_LastOCRResult

    if !IsNumber(RowNumber) || RowNumber < 1 || !IsObject(g_LastOCRResult)
        return

    if RowNumber <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[RowNumber]
        FlashHighlight(word.x, word.y, word.w, word.h, 3, 300, "word")
        ShowCoordTooltip(word.x, word.y, "Word: " . word.Text . "`nX:" . word.x . " Y:" . word.y . " W:" . word.w . " H:" . word.h, 3000)
    }
}

; Highlight selected OCR word
HighlightSelectedOCRWord(*) {
    global g_LastOCRResult, OCRLV

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult)
        return

    if row <= g_LastOCRResult.Words.Length {
        word := g_LastOCRResult.Words[row]
        HighlightRegion(word.x, word.y, word.w, word.h, 3000, "word", word.Text)
    }
}

; Add selected OCR word as watch word
AddSelectedWordAsWatch(*) {
    global g_LastOCRResult, OCRLV, g_OCRRegion

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult) {
        ShowStatus("Select a word first", "fail")
        return
    }

    ; Get watch word name from input
    name := MainGui["WatchWordName"].Value
    if name = "" {
        ShowStatus("Enter a name for the watch word", "fail")
        return
    }

    ; Get word coords
    word := g_LastOCRResult.Words[row]

    ; Create region around word with some padding
    padding := 5
    region := Map(
        "x1", word.x - padding,
        "y1", word.y - padding,
        "x2", word.x + word.w + padding,
        "y2", word.y + word.h + padding
    )

    ; Define watch word
    DefineWatchWord(name, region, "", 1)  ; labelIndex 1 = first word

    ; Update immediately
    UpdateWatchWord(name)
    RefreshWatchWordLV()

    ShowStatus("Watch word '" . name . "' created: " . word.Text, "ok")
    HighlightRegion(region["x1"], region["y1"], region["x2"] - region["x1"], region["y2"] - region["y1"], 2000, "selection", name)
}

; Click on selected OCR word
ClickSelectedOCRWord(*) {
    global g_LastOCRResult, OCRLV

    row := OCRLV.GetNext(0, "Focused")
    if row = 0 || !IsObject(g_LastOCRResult) {
        ShowStatus("Select a word first", "fail")
        return
    }

    word := g_LastOCRResult.Words[row]
    x := word.x + word.w // 2
    y := word.y + word.h // 2

    ; Brief highlight then click
    HighlightRegion(word.x, word.y, word.w, word.h, 500, "highlight", "")
    Sleep(200)
    Click(x, y)
    ShowStatus("Clicked: " . word.Text, "ok")
}

; Define watch word from current OCR region
DefineWatchWordFromOCR(*) {
    global g_OCRRegion

    name := MainGui["WatchWordName"].Value
    if name = "" {
        ShowStatus("Enter a name for the watch word", "fail")
        return
    }

    ; Use current OCR region
    if g_OCRRegion["x2"] = 0 && g_OCRRegion["y2"] = 0 {
        ShowStatus("Select a region first (use Select Region button)", "fail")
        return
    }

    region := Map(
        "x1", g_OCRRegion["x1"],
        "y1", g_OCRRegion["y1"],
        "x2", g_OCRRegion["x2"],
        "y2", g_OCRRegion["y2"]
    )

    DefineWatchWord(name, region, "", 0)  ; 0 = all text in region
    UpdateWatchWord(name)
    RefreshWatchWordLV()

    ShowStatus("Watch word '" . name . "' created from region", "ok")
}

; Show all watch word values
ShowWatchWordValues(*) {
    global g_WatchWords, g_WordVariables

    ; Update all first
    UpdateAllWatchWords()
    RefreshWatchWordLV()

    ; Build summary
    summary := "Watch Word Values:`n`n"
    for name, watch in g_WatchWords {
        summary .= "$word." . name . " = " . watch["lastValue"] . "`n"
        summary .= "  Coords: " . watch["lastCoords"]["x"] . "," . watch["lastCoords"]["y"] . "`n"
    }

    if g_WatchWords.Count = 0
        summary := "No watch words defined.`n`nDefine watch words to capture dynamic text like patient names, dates, IDs, etc."

    MsgBoxTop(summary, "Watch Word Values")
}

; Manage watch words dialog
ManageWatchWords(*) {
    global g_WatchWords

    manageGui := Gui("+AlwaysOnTop", "Manage Watch Words")
    manageGui.SetFont("s9", "Consolas")

    manageGui.Add("Text", "w400", "Watch words capture dynamic text from specific screen regions.")
    manageGui.Add("Text", "w400 cGray", "Use $word.Name in workflows to reference captured values.")

    ; List view of watch words
    lv := manageGui.Add("ListView", "w400 h200 Grid", ["Name", "Region", "Last Value"])
    lv.ModifyCol(1, 100)
    lv.ModifyCol(2, 150)
    lv.ModifyCol(3, 140)

    for name, watch in g_WatchWords {
        r := watch["region"]
        regionStr := r["x1"] . "," . r["y1"] . " → " . r["x2"] . "," . r["y2"]
        lv.Add("", name, regionStr, watch["lastValue"])
    }

    manageGui.Add("Button", "w80", "Update All").OnEvent("Click", (*) => (UpdateAllWatchWords(), manageGui.Destroy(), ManageWatchWords()))
    manageGui.Add("Button", "x+10 w80", "Highlight").OnEvent("Click", (*) => HighlightAllWatchWords())
    manageGui.Add("Button", "x+10 w80", "Delete").OnEvent("Click", (*) => DeleteSelectedWatchWordFromList(lv))
    manageGui.Add("Button", "x+10 w80", "Close").OnEvent("Click", (*) => manageGui.Destroy())

    manageGui.Show()
}

; Highlight all watch words on screen
HighlightAllWatchWords() {
    global g_WatchWords

    UpdateAllWatchWords()

    for name, watch in g_WatchWords {
        coords := watch["lastCoords"]
        if coords["w"] > 0 {
            HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], 3000, "word", name)
        }
    }
}

; Delete watch word from manage list
DeleteSelectedWatchWordFromList(lv) {
    global g_WatchWords

    row := lv.GetNext(0, "Focused")
    if row = 0
        return

    name := lv.GetText(row, 1)
    g_WatchWords.Delete(name)
    SaveWatchWords()
    lv.Delete(row)
}

; Refresh watch word list view
RefreshWatchWordLV() {
    global g_WatchWords, WatchWordLV

    try {
        WatchWordLV.Delete()
        for name, watch in g_WatchWords {
            WatchWordLV.Add("", name, watch["lastValue"])
        }
    }
}

; Watch word LV selection handler
OnWatchWordSelect(LV, RowNumber, *) {
    ; Just update UI state if needed
}

; Double-click watch word - highlight on screen
OnWatchWordDblClick(LV, RowNumber, *) {
    global g_WatchWords
    if !TryGetListViewText(LV, RowNumber, 1, &name)
        return
    if g_WatchWords.Has(name) {
        HighlightWatchWord(name, 3000)
    }
}

; Highlight selected watch word
HighlightSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)
    if g_WatchWords.Has(name) {
        UpdateWatchWord(name)  ; Refresh value first
        HighlightWatchWord(name, 3000)
        ShowStatus(name . " = " . g_WatchWords[name]["lastValue"], "ok")
    }
}

; Use selected watch word (insert into clipboard or show value)
UseSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)
    if g_WatchWords.Has(name) {
        UpdateWatchWord(name)
        value := g_WatchWords[name]["lastValue"]

        ; Copy value to clipboard
        A_Clipboard := value
        ShowStatus("Copied to clipboard: " . value, "ok")
    }
}

; Delete selected watch word
DeleteSelectedWatchWord(*) {
    global g_WatchWords, WatchWordLV

    row := WatchWordLV.GetNext(0, "Focused")
    if row = 0
        return

    name := WatchWordLV.GetText(row, 1)

    if MsgBox("Delete watch word '" . name . "'?", "Confirm", "YesNo") = "Yes" {
        g_WatchWords.Delete(name)
        SaveWatchWords()
        RefreshWatchWordLV()
        ShowStatus("Deleted: " . name, "ok")
    }
}

; Test all patterns and overlay system
TestAllOverlays(*) {
    global g_Patterns, g_WatchWords

    ; Clear existing
    ClearAllOverlays()

    ; Test patterns
    patternCount := TestAllPatternsHighlight(3000)

    ; Test watch words
    watchCount := 0
    for name, watch in g_WatchWords {
        UpdateWatchWord(name)
        coords := watch["lastCoords"]
        if coords["w"] > 0 {
            HighlightRegion(coords["x"], coords["y"], coords["w"], coords["h"], 3000, "word", name . ": " . watch["lastValue"])
            watchCount++
        }
    }

    ShowStatus("Patterns: " . patternCount . " | Watch Words: " . watchCount, "ok")
}

ViewOCRLog(*) {
    global g_DB

    logText := ""
    if IsObject(g_DB) && g_DB.GetTable("SELECT ts, text, word_count FROM ocr_log ORDER BY id DESC LIMIT 2000;", &tb) {
        row := ""
        Loop tb.RowCount {
            tb.GetRow(A_Index, &row)
            logText .= row[1] . "|" . row[2] . "|" . row[3] . "`n"
        }
    }

    ; Show in popup
    logGui := Gui("+AlwaysOnTop", "OCR Log (most recent 2000 - full history kept in DB)")
    logGui.Add("Edit", "w600 h400 ReadOnly Multi VScroll", logText)
    logGui.Add("Button", "w100", "Close").OnEvent("Click", (*) => logGui.Destroy())
    logGui.Show()
}

ClearOCRLog(*) {
    global g_OCRLog, OCR_LOG_FILE, g_DB
    g_OCRLog := []
    MainGui["OCRLogCount"].Value := "0"
    try FanFileDelete(OCR_LOG_FILE)
    if IsObject(g_DB)
        g_DB.Exec("DELETE FROM ocr_log;")
    ShowStatus("OCR log cleared", "ok")
}

ExportOCRLog(*) {
    global g_DB, DATA_DIR

    exportFile := DATA_DIR . "\ocr_export_" . FormatTime(, "yyyyMMdd_HHmmss") . ".csv"

    content := "Timestamp,Text,WordCount`n"
    if IsObject(g_DB) && g_DB.GetTable("SELECT ts, text, word_count FROM ocr_log ORDER BY id;", &tb) {
        row := ""
        Loop tb.RowCount {
            tb.GetRow(A_Index, &row)
            content .= row[1] . "|" . row[2] . "|" . row[3] . "`n"
        }
    }

    try {
        FanFileAppend(content, exportFile)
        ShowStatus("Exported to: " . exportFile, "ok")
        Run("explorer.exe /select," . exportFile)
    } catch as err {
        ShowStatus("Export error: " . err.Message, "fail")
    }
}


; ═══════════════════════════════════════════════════════════════════════════════
; OCR TEXT MANIPULATION FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; OCR TEXT MANIPULATION FUNCTIONS
; =============================================================================

; Copy OCR text to clipboard
CopyOCRToClipboard(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to copy", "fail")
        return
    }

    A_Clipboard := text
    g_LastOCRText := text
    ShowStatus("Copied " . StrLen(text) . " chars to clipboard", "ok")
}

; Load OCR text into revolver (using dropdown selection)
LoadOCRToRevolverDD(*) {
    global OCROutputEdit, OCRSplitDD, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to load", "fail")
        return
    }

    g_LastOCRText := text

    ; Get split mode from dropdown
    mode := OCRSplitDD.Text

    switch mode {
        case "Tab": LoadOCRRevolver("tab")
        case "Line": LoadOCRRevolver("line")
        case "Space": LoadOCRRevolver(" ")
        case "Comma": LoadOCRRevolver(",")
        case "2 parts": LoadOCRRevolver("2")
        case "3 parts": LoadOCRRevolver("3")
        case "4 parts": LoadOCRRevolver("4")
        case "5 parts": LoadOCRRevolver("5")
        default: LoadOCRRevolver("4")
    }

    UpdateOCRRevolverStatus()
}

; Load OCR to revolver (simple button version)
LoadOCRToRevolver(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to load", "fail")
        return
    }

    g_LastOCRText := text

    ; Default: split into 4 parts
    LoadOCRRevolver("4")
    UpdateOCRRevolverStatus()
}

; Fire OCR revolver from UI button
FireOCRRevolverUI(*) {
    FireOCRRevolver()
    UpdateOCRRevolverStatus()
}

; Update revolver status display
UpdateOCRRevolverStatus() {
    global g_OCRRevolver, g_OCRRevolverIndex

    try {
        if g_OCRRevolver.Length = 0 {
            MainGui["OCRRevolverStatus"].Value := "Empty"
        } else {
            MainGui["OCRRevolverStatus"].Value := g_OCRRevolverIndex . "/" . g_OCRRevolver.Length . " parts"
        }
    }
}

; Save OCR text to variable
SaveOCRToVariable(*) {
    global OCROutputEdit, g_SpoolVariables, g_WordVariables

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to save", "fail")
        return
    }

    ; Ask for variable name
    varGui := Gui("+AlwaysOnTop", "Save to Variable")
    varGui.Add("Text", , "Variable name:")
    varNameEdit := varGui.Add("Edit", "w200", "ocrText")
    varGui.Add("Button", "Default w100", "Save").OnEvent("Click", (*) => (
        g_SpoolVariables[varNameEdit.Value] := text,
        g_WordVariables["$var." . varNameEdit.Value] := text,
        RefreshOCRVarsLV(),
        ShowStatus("Saved to $var." . varNameEdit.Value, "ok"),
        varGui.Destroy()
    ))
    varGui.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => varGui.Destroy())
    varGui.Show()
}

; Click on text found in OCR
ClickTextInOCR(*) {
    global OCROutputEdit, OCRSearchEdit, g_OCRSettings, g_LastOCRRegion

    searchText := OCRSearchEdit.Value
    if searchText = "" {
        ShowStatus("Enter text to find and click", "fail")
        return
    }

    ; Use last captured region or full screen
    region := g_LastOCRRegion.Count > 0 ? g_LastOCRRegion : Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)

    ExecuteOCRClick(region["x1"] . "," . region["y1"] . "," . region["x2"] . "," . region["y2"], searchText)
}

; Extract text using regex
ExtractOCRRegex(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to extract from", "fail")
        return
    }

    ; Ask for regex pattern
    regGui := Gui("+AlwaysOnTop", "Extract with Regex")
    regGui.Add("Text", , "Regex pattern:")
    patternEdit := regGui.Add("Edit", "w300", "\d+")
    regGui.Add("Text", , "Common patterns:")
    regGui.Add("Text", "cGray", "\d+ = numbers | [A-Z]+ = uppercase | \d{3}-\d{4} = phone")

    extractBtn := regGui.Add("Button", "Default w100", "Extract")
    extractBtn.OnEvent("Click", (*) => ExtractRegexAndShow(text, patternEdit.Value, regGui))
    regGui.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => regGui.Destroy())
    regGui.Show()
}

; Helper for regex extraction
ExtractRegexAndShow(text, pattern, parentGui) {
    global g_LastOCRText

    matches := []
    pos := 1

    while pos := RegExMatch(text, pattern, &match, pos) {
        matches.Push(match[0])
        pos += StrLen(match[0])
    }

    if matches.Length = 0 {
        ShowStatus("No matches found", "fail")
        return
    }

    ; Join matches and copy to clipboard
    result := ""
    for m in matches
        result .= m . "`n"
    result := RTrim(result, "`n")

    A_Clipboard := result
    g_LastOCRText := result

    parentGui.Destroy()
    ShowStatus("Extracted " . matches.Length . " matches to clipboard", "ok")
}

; Split OCR text dialog
SplitOCRText(*) {
    global OCROutputEdit, g_LastOCRText

    text := OCROutputEdit.Value
    if text = "" {
        ShowStatus("No OCR text to split", "fail")
        return
    }

    g_LastOCRText := text

    ; Show split options dialog
    splitGui := Gui("+AlwaysOnTop", "Split OCR Text")
    splitGui.Add("Text", , "Split by:")
    splitDD := splitGui.Add("DropDownList", "w150", ["4 equal parts", "Tab characters", "Newlines", "Spaces", "Commas", "Custom delimiter"])
    splitDD.Choose(1)

    splitGui.Add("Text", , "Custom delimiter:")
    delimEdit := splitGui.Add("Edit", "w150", "|")

    splitGui.Add("Button", "Default w100", "Split & Load").OnEvent("Click", (*) => (
        DoSplitOCR(splitDD.Text, delimEdit.Value, splitGui)
    ))
    splitGui.Add("Button", "x+10 w100", "Cancel").OnEvent("Click", (*) => splitGui.Destroy())
    splitGui.Show()
}

; Perform the split
DoSplitOCR(mode, customDelim, parentGui) {
    switch mode {
        case "4 equal parts": LoadOCRRevolver("4")
        case "Tab characters": LoadOCRRevolver("tab")
        case "Newlines": LoadOCRRevolver("line")
        case "Spaces": LoadOCRRevolver(" ")
        case "Commas": LoadOCRRevolver(",")
        case "Custom delimiter": LoadOCRRevolver(customDelim)
        default: LoadOCRRevolver("4")
    }

    parentGui.Destroy()
    UpdateOCRRevolverStatus()
}

; Show OCR help
ShowOCRHelp(*) {
    helpText := "
    (
OCR Text Operations Help:

📋 Copy: Copy all OCR text to clipboard

🔫 Load Rev: Split text into parts for sequential pasting
   - Choose split mode (4 parts, Tab, Line, etc.)
   - Use Fire Rev to paste each part in order

→ Var: Save OCR text to a variable ($var.name)
   - Use in workflows: Type Text → $var.ocrText

Click Text: Click on specific text found via OCR
   - Enter search text in Find field first

Regex: Extract matching text using regex patterns
   - Common: \d+ (numbers), [A-Z]+ (caps)

Split: Choose how to split text for revolver

WORKFLOW ACTIONS:
- OCR Region: Capture text from screen area
- OCR Click: Find and click on text
- OCR Wait: Wait for text to appear
- Load OCR Revolver: Split captured text
- Fire OCR Revolver: Paste next part
    )"

    MsgBoxTop(helpText, "OCR Operations Help")
}


; ═══════════════════════════════════════════════════════════════════════════════
; OCR-ENHANCED SPOOL DETECTION
; ═══════════════════════════════════════════════════════════════════════════════
; OCR-ENHANCED SPOOL DETECTION
; =============================================================================


; Use Windows OCR for text detection in spools
SpoolDetectOCRWindows(region, searchText, useRegex := false) {
    try {
        w := region["x2"] - region["x1"]
        h := region["y2"] - region["y1"]

        if w < 40 || h < 40 {
            ; Region too small, use full screen
            result := OCR.FromDesktop()
        } else {
            result := OCR.FromRect(region["x1"], region["y1"], w, h)
        }

        if useRegex {
            return Map("found", RegExMatch(result.Text, searchText), "text", result.Text)
        } else {
            return Map("found", InStr(result.Text, searchText), "text", result.Text)
        }
    } catch {
        return Map("found", false, "text", "")
    }
}


; Note: RefreshNotificationLV is defined above with the notification functions

RefreshOCRVarsLV() {
    global g_SpoolVariables, OCRVarsLV

    try {
        OCRVarsLV.Delete()
        for name, val in g_SpoolVariables {
            OCRVarsLV.Add("", name, SubStr(val, 1, 30))
        }
    }
}

ClearOCRVars(*) {
    global g_SpoolVariables
    g_SpoolVariables := Map()
    RefreshOCRVarsLV()
}

UseOCRVar(*) {
    global OCRVarsLV, g_SpoolVariables, ParamCombo

    row := OCRVarsLV.GetNext(0, "Focused")
    if row = 0
        return

    varName := OCRVarsLV.GetText(row, 1)
    if g_SpoolVariables.Has(varName) {
        try ParamCombo.Text := g_SpoolVariables[varName]
    }
}



; Test if OCR is available
global g_OCRAvailable := false

TestOCRAvailability() {
    global g_OCRAvailable
    try {
        if !IsSet(OCR) {
            g_OCRAvailable := false
            return false
        }
        testResult := OCR.FromRect(0, 0, 100, 100, {lang: "en-US", scale: 1})
        g_OCRAvailable := true
        return true
    } catch {
        g_OCRAvailable := false
        return false
    }
}

Tab_LiveOCR_Build() {
    global OCRIntervalEdit, OCRLangDD, OCRLV, OCROutputEdit, OCRRecordingToggle, OCRRegionPreview, OCRScaleEdit, OCRSearchEdit, OCRSplitDD, WatchWordLV, WatchWordNameEdit
    TabCtrl.UseTab(3)

    ; --- LIVE OCR CONTROLS ---
    MainGui.Add("GroupBox", "x15 y50 w860 h85", "Live OCR Monitor - Windows UWP Text Recognition")
    MainGui.Add("Text", "x25 y68 w700", "Continuously captures and recognizes text from a screen region. Use to verify OCR is working correctly.")
    MainGui.Add("Text", "x25 y83 w700 cGray", "OCR Library: Windows.Media.Ocr (UWP) | Supports multiple languages | Auto-detects text orientation")

    OCRRecordingToggle := MainGui.Add("CheckBox", "x25 y103 w150 vOCRRecordingToggle", "🔴 Live Recording")
    OCRRecordingToggle.OnEvent("Click", ToggleOCRRecording)
    MainGui.Add("Text", "x180 y104 w100 cRed vOCRRecordingStatus", "STOPPED")
    MainGui.Add("Button", "x290 y100 w90 h22", "Capture Once").OnEvent("Click", CaptureOCROnce)
    MainGui.Add("Button", "x385 y100 w90 h22", "Select Region").OnEvent("Click", SelectOCRRegion)
    MainGui.Add("Text", "x480 y104 w200 vOCRRegionDisplay cGray", "Region: Full Screen")
    MainGui.Add("Button", "x700 y100 w80 h22", "Test All").OnEvent("Click", TestAllOverlays)
    MainGui.Add("Button", "x785 y100 w80 h22", "Clear All").OnEvent("Click", (*) => ClearAllOverlays())

    ; --- OCR SETTINGS ---
    MainGui.Add("GroupBox", "x15 y140 w200 h100", "OCR Settings")
    MainGui.Add("Text", "x25 y160", "Language:")
    OCRLangDD := MainGui.Add("DropDownList", "x85 y157 w100 vOCRLang", ["en-us", "es", "fr", "de", "it", "pt", "zh-Hans", "ja", "ko"])
    OCRLangDD.Choose(1)
    MainGui.Add("Text", "x25 y188", "Scale:")
    OCRScaleEdit := MainGui.Add("Edit", "x65 y185 w40 vOCRScale", "1.0")
    MainGui.Add("CheckBox", "x115 y188 vOCRGrayscale", "Gray")
    MainGui.Add("Text", "x25 y215", "Interval:")
    OCRIntervalEdit := MainGui.Add("Edit", "x75 y212 w45 vOCRInterval Number", "500")
    MainGui.Add("Text", "x125 y215", "ms")

    ; --- CAPTURE REGION PREVIEW ---
    MainGui.Add("GroupBox", "x225 y140 w180 h100", "Capture Region")
    OCRRegionPreview := MainGui.Add("Text", "x235 y160 w160 h70 Border vOCRRegionPreview cGray Center", "Full Screen`n(Select Region)")

    ; --- OCR RESULT DISPLAY ---
    MainGui.Add("GroupBox", "x415 y140 w170 h100", "Last Capture Info")
    MainGui.Add("Text", "x425 y158", "Words:")
    MainGui.Add("Text", "x470 y158 w50 vOCRWordCount cBlue", "0")
    MainGui.Add("Text", "x425 y175", "Lines:")
    MainGui.Add("Text", "x470 y175 w50 vOCRLineCount cBlue", "0")
    MainGui.Add("Text", "x425 y192", "Angle:")
    MainGui.Add("Text", "x470 y192 w50 vOCRTextAngle cBlue", "0°")
    MainGui.Add("Text", "x425 y209", "Time:")
    MainGui.Add("Text", "x470 y209 w50 vOCRCaptureTime cBlue", "0ms")

    ; --- WATCH WORDS (Dynamic Text Variables) ---
    MainGui.Add("GroupBox", "x595 y140 w280 h100", "Watch Words (Dynamic Variables)")
    MainGui.Add("Text", "x605 y158 w260 cGray", "Define regions to auto-capture text into variables")
    MainGui.Add("Text", "x605 y175", "Name:")
    WatchWordNameEdit := MainGui.Add("Edit", "x650 y172 w100 vWatchWordName")
    MainGui.Add("Button", "x755 y172 w110 h20", "Define from OCR").OnEvent("Click", DefineWatchWordFromOCR)
    MainGui.Add("Button", "x605 y198 w80 h20", "Update All").OnEvent("Click", (*) => UpdateAllWatchWords())
    MainGui.Add("Button", "x690 y198 w80 h20", "Show Values").OnEvent("Click", ShowWatchWordValues)
    MainGui.Add("Button", "x775 y198 w90 h20", "Manage...").OnEvent("Click", ManageWatchWords)

    ; --- LIVE OCR OUTPUT ---
    MainGui.Add("GroupBox", "x15 y245 w430 h205", "Live OCR Text Output")
    OCROutputEdit := MainGui.Add("Edit", "x25 y263 w410 h165 ReadOnly Multi VScroll vOCROutput", "")
    ; Text manipulation buttons
    MainGui.Add("Button", "x25 y432 w60 h18", "📋 Copy").OnEvent("Click", CopyOCRToClipboard)
    MainGui.Add("Button", "x90 y432 w80 h18", "🔫 Load Rev").OnEvent("Click", LoadOCRToRevolver)
    MainGui.Add("Button", "x175 y432 w60 h18", "→ Var").OnEvent("Click", SaveOCRToVariable)
    MainGui.Add("Button", "x240 y432 w80 h18", "Click Text").OnEvent("Click", ClickTextInOCR)
    MainGui.Add("Button", "x325 y432 w55 h18", "Regex").OnEvent("Click", ExtractOCRRegex)
    MainGui.Add("Button", "x385 y432 w50 h18", "Split").OnEvent("Click", SplitOCRText)

    ; --- WORD LIST ---
    MainGui.Add("GroupBox", "x455 y245 w200 h205", "Detected Words")
    OCRLV := MainGui.Add("ListView", "x465 y263 w180 h145 Grid NoSortHdr vOCRLV", ["Word", "X", "Y"])
    OCRLV.ModifyCol(1, 90)
    OCRLV.ModifyCol(2, 40)
    OCRLV.ModifyCol(3, 40)
    OCRLV.OnEvent("ItemSelect", OnOCRWordSelect)
    OCRLV.OnEvent("DoubleClick", OnOCRWordDblClick)
    MainGui.Add("Button", "x465 y413 w60 h20", "Highlight").OnEvent("Click", HighlightSelectedOCRWord)
    MainGui.Add("Button", "x530 y413 w60 h20", "Watch").OnEvent("Click", AddSelectedWordAsWatch)
    MainGui.Add("Button", "x595 y413 w50 h20", "Click").OnEvent("Click", ClickSelectedOCRWord)

    ; --- WATCH WORD VALUES ---
    MainGui.Add("GroupBox", "x665 y245 w210 h205", "Watch Word Values")
    WatchWordLV := MainGui.Add("ListView", "x675 y263 w190 h145 Grid NoSortHdr vWatchWordLV", ["Name", "Value"])
    WatchWordLV.ModifyCol(1, 70)
    WatchWordLV.ModifyCol(2, 110)
    WatchWordLV.OnEvent("ItemSelect", OnWatchWordSelect)
    WatchWordLV.OnEvent("DoubleClick", OnWatchWordDblClick)
    MainGui.Add("Button", "x675 y413 w60 h20", "Highlight").OnEvent("Click", HighlightSelectedWatchWord)
    MainGui.Add("Button", "x740 y413 w60 h20", "Use").OnEvent("Click", UseSelectedWatchWord)
    MainGui.Add("Button", "x805 y413 w60 h20", "Delete").OnEvent("Click", DeleteSelectedWatchWord)

    ; --- SEARCH IN OCR ---
    MainGui.Add("GroupBox", "x15 y455 w430 h85", "Search & Text Operations")
    MainGui.Add("Text", "x25 y473", "Find:")
    OCRSearchEdit := MainGui.Add("Edit", "x60 y470 w150 vOCRSearch")
    MainGui.Add("Button", "x215 y470 w50 h22", "Find").OnEvent("Click", FindInOCR)
    MainGui.Add("Button", "x270 y470 w65 h22", "Highlight").OnEvent("Click", HighlightOCRMatch)
    MainGui.Add("Button", "x340 y470 w55 h22", "Clear").OnEvent("Click", ClearOCRHighlights)
    MainGui.Add("CheckBox", "x400 y473 vOCRCaseSense", "Case")
    ; Revolver loading options
    MainGui.Add("Text", "x25 y500", "Revolver:")
    OCRSplitDD := MainGui.Add("DropDownList", "x75 y497 w80 vOCRSplitMode", ["4 parts", "Tab", "Line", "Space", "Comma", "2 parts", "3 parts", "5 parts"])
    OCRSplitDD.Choose(1)
    MainGui.Add("Button", "x160 y497 w75 h22", "Load Rev").OnEvent("Click", LoadOCRToRevolverDD)
    MainGui.Add("Button", "x240 y497 w75 h22", "Fire Rev").OnEvent("Click", FireOCRRevolverUI)
    MainGui.Add("Text", "x320 y500 w100 vOCRRevolverStatus cGray", "Ready")

    ; --- OCR LOG ---
    MainGui.Add("GroupBox", "x455 y455 w420 h85", "OCR Recording Log & Info")
    MainGui.Add("Button", "x465 y473 w60 h22", "View").OnEvent("Click", ViewOCRLog)
    MainGui.Add("Button", "x530 y473 w60 h22", "Clear").OnEvent("Click", ClearOCRLog)
    MainGui.Add("Button", "x595 y473 w60 h22", "Export").OnEvent("Click", ExportOCRLog)
    MainGui.Add("Text", "x660 y478 w40 vOCRLogCount cGray", "0")
    MainGui.Add("Text", "x700 y478 w50 cGray", "entries")
    MainGui.Add("Button", "x755 y473 w60 h22", "Languages").OnEvent("Click", GetOCRLanguages)
    MainGui.Add("Button", "x820 y473 w50 h22", "Help").OnEvent("Click", ShowOCRHelp)
    ; Info row
    MainGui.Add("Text", "x465 y500 w380 cGray", "OCR Revolver: paste captured text in parts. Load splits text, Fire pastes sequentially.")


}


; GRAB OCR TEXT TO VARIABLE - Capture OCR text and store in variable
; Format: "GrabOCRToVar,variableName,x1,y1,x2,y2" or "GrabOCRToVar,variableName,RegionName"
ExecuteGrabOCRToVar(params, targetRegion := "") {
    global g_ExtractedData, g_SpoolVariables, g_SpoolRegions, g_WordVariables

    if targetRegion != "" {
        varName := Trim(params)
        if ResolveWorkflowRegion(targetRegion, &region) {
            x := region["x1"], y := region["y1"]
            w := region["x2"] - region["x1"], h := region["y2"] - region["y1"]
        } else {
            coords := StrSplit(targetRegion, ",")
            if coords.Length < 4 {
                ShowStatus("Grab OCR target was not found: " . targetRegion, "fail")
                return false
            }
            try {
                x := Integer(coords[1]), y := Integer(coords[2])
                w := Integer(coords[3]), h := Integer(coords[4])
            } catch {
                ShowStatus("Grab OCR coordinates are invalid", "fail")
                return false
            }
        }
    } else {
        parts := StrSplit(params, ",")
        if parts.Length < 5 {
            ShowStatus("GrabOCRToVar format: varName,x,y,width,height", "fail")
            ShowNotificationBasic("Invalid Format", "Grab OCR to Var requires:`nvarName,x,y,width,height`n`nExample:`npatientID,100,100,400,200", 0, "error")
            return false
        }
        varName := Trim(parts[1])
        try {
            x := Integer(parts[2]), y := Integer(parts[3])
            w := Integer(parts[4]), h := Integer(parts[5])
        } catch {
            ShowStatus("Grab OCR coordinates are invalid", "fail")
            return false
        }
    }

    if !RegExMatch(varName, "^[A-Za-z_][A-Za-z0-9_]*$") {
        ShowStatus("Grab OCR needs a valid variable name", "fail")
        return false
    }

    ; Flash the region being captured
    FlashOCRRegion(x, y, w, h)

    ; Perform OCR
    try {
        result := OCR.FromRect(x, y, w, h)
        text := Trim(result.Text)

        ; Store in variables with both formats
        g_ExtractedData["$" . varName] := text
        g_ExtractedData["$var." . varName] := text
        g_ExtractedData[varName] := text
        g_SpoolVariables["$" . varName] := text
        g_SpoolVariables["$var." . varName] := text
        g_SpoolVariables[varName] := text
        g_WordVariables["$var." . varName] := text

        ShowStatus("OCR captured to $" . varName . ": " . text, "ok")

        ; Show notification with captured text and copy button
        ShowNotificationBasic("OCR Captured", "Variable: $" . varName . "`n`nText Captured:`n" . text, 0, "success", text)

        return true
    } catch as err {
        LogErrorToFile(err, "caught", "Grab OCR to Var")
        ShowStatus("OCR capture failed: " . err.Message, "fail")
        ShowNotificationBasic("OCR Failed", "Could not capture text`n`nRegion: " . x . "," . y . "," . w . "," . h . "`n`nError: " . err.Message, 0, "error")
        return false
    }
}

; Capture the primary screen, save recognized text, and outline every word.
; The notification is intentionally a separate workflow step so it proves that
; $var.name substitution is working rather than displaying a local value.
ExecuteFullScreenOCRToVar(varName) {
    global g_ExtractedData, g_SpoolVariables, g_WordVariables
    global g_LastOCRResult, g_LastOCRText, g_LastOCRRegion, g_OCRSettings

    varName := Trim(varName)
    if !RegExMatch(varName, "^[A-Za-z_][A-Za-z0-9_]*$") {
        ShowActionNotification("Full Screen OCR", "error", "Invalid variable name",
            "Use a plain name such as fullScreenOCR (letters, numbers, and underscores only).")
        return false
    }

    try {
        ShowStatus("Full-screen OCR in progress...", "wait")
        result := OCR.FromRect(0, 0, A_ScreenWidth, A_ScreenHeight, WorkflowOCR_Options())
        text := Trim(result.Text)
        if text = ""
            throw Error("Windows OCR completed but did not find readable text on the screen.")

        g_LastOCRResult := result
        g_LastOCRText := text
        g_LastOCRRegion := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)

        ; Store every supported key form. $var.name is the preferred workflow form.
        g_ExtractedData[varName] := text
        g_ExtractedData["$" . varName] := text
        g_ExtractedData["$var." . varName] := text
        g_SpoolVariables[varName] := text
        g_SpoolVariables["$" . varName] := text
        g_SpoolVariables["$var." . varName] := text
        g_WordVariables["$var." . varName] := text

        HighlightOCRWordsYellow(result.Words, 0, 0, 10000)
        ShowStatus("OCR stored " . StrLen(text) . " characters in $var." . varName
            . " (" . result.Words.Length . " yellow boxes)", "ok")
        try RefreshOCRVarsLV()
        return true
    } catch as err {
        LogErrorToFile(err, "caught", "OCR Full Screen to Var")
        ShowActionNotification("Full Screen OCR", "error", "OCR capture failed",
            err.Message . "`n`nThe full details were written to the error log.")
        return false
    }
}

FlashOCRRegion(x, y, w, h, duration := 300) {
    ; Create a highlighted overlay to show OCR capture region
    flashGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashGui.BackColor := "Yellow"
    WinSetTransparent(100, flashGui.Hwnd)

    ; Show flash
    flashGui.Show("x" . x . " y" . y . " w" . w . " h" . h . " NoActivate")

    ; Remove after duration
    SetTimer(() => flashGui.Destroy(), -duration)
}

FlashClickPosition(x, y, duration := 200) {
    ; Create a crosshair flash at click position
    size := 30
    thickness := 4

    ; Horizontal line
    flashH := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashH.BackColor := "Red"
    WinSetTransparent(150, flashH.Hwnd)
    flashH.Show("x" . (x - size) . " y" . (y - thickness//2) . " w" . (size*2) . " h" . thickness . " NoActivate")

    ; Vertical line
    flashV := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
    flashV.BackColor := "Red"
    WinSetTransparent(150, flashV.Hwnd)
    flashV.Show("x" . (x - thickness//2) . " y" . (y - size) . " w" . thickness . " h" . (size*2) . " NoActivate")

    ; Remove after duration
    SetTimer(() => (flashH.Destroy(), flashV.Destroy()), -duration)
}

; USE VARIABLE IN PASTE - Paste text that includes variables
; Format: "UseVarPaste,Hello $name, your ID is $id"
ExecuteUseVarPaste(params) {
    global g_ExtractedData, g_Settings

    if params = "" {
        ShowStatus("UseVarPaste requires text with variables", "fail")
        return false
    }

    ; Replace all variables in the text
    text := params

    ; Find all $variable references
    for varName, value in g_ExtractedData {
        if InStr(text, varName) {
            text := StrReplace(text, varName, value)
        }
    }

    ; Type the text
    Sleep(g_Settings["PreActionDelay"])
    SendText(text)
    Sleep(g_Settings["PostActionDelay"])

    ShowStatus("Pasted with variables: " . text, "ok")
    return true
}



; ═══════════════════════════════════════════════════════════════════════════════
; OCR WORKFLOW ACTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; OCR WORKFLOW ACTIONS
; =============================================================================

; Execute OCR Region action - capture and process text from screen region
; OCR.FromRect accepts one options object and returns screen coordinates even
; when the capture has a nonzero origin or is scaled for recognition.
WorkflowOCR_Options() {
    global g_OCRSettings
    return {lang: g_OCRSettings["language"], scale: g_OCRSettings["scale"]}
}

WorkflowOCR_Center(box) {
    return Map("x", box.x + (box.w // 2), "y", box.y + (box.h // 2))
}

ExecuteOCRRegion(target, param) {
    global g_LastOCRText, g_LastOCRRegion, g_SpoolVariables, g_WordVariables, g_OCRSettings

    ; Parse region from target
    region := ParseRegionCoords(target)
    if !region {
        ShowActionNotification("OCR Region", "error",
            "Invalid region coordinates",
            "Could not parse region from target: " . target . "`n`nExpected format: x,y,width,height`nExample: 100,100,400,200")
        return false
    }

    ; Store for later use
    g_LastOCRRegion := region

    ; Check if OCR is available
    if !IsOCRAvailable() {
        return ReportOCRError("Extract", region, "OCR.ahk library not found or not loaded. Ensure OCR.ahk is in the script directory.")
    }

    ; Perform OCR on region using Windows UWP
    text := ""
    try {
        ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                  region["x2"] - region["x1"],
                                  region["y2"] - region["y1"],
                                  WorkflowOCR_Options())
        text := ocrResult.Text
    } catch as e {
        return ReportOCRError("Extract", region, e.Message)
    }

    if text = "" {
        return ReportOCRError("Extract", region, "No text detected in specified region. Text may be too small, obscured, or region may be incorrect.")
    }

    ; Store the captured text
    g_LastOCRText := text

    ; Process based on param
    param := Trim(param)

    if param = "" || param = "copy" {
        ; Copy to clipboard
        A_Clipboard := text
        ShowStatus("OCR: Copied " . StrLen(text) . " chars to clipboard", "ok")
        return true
    }

    if SubStr(param, 1, 4) = "var:" {
        ; Store in variable
        varName := SubStr(param, 5)
        g_SpoolVariables[varName] := text
        g_WordVariables["$var." . varName] := text
        ShowActionNotification("OCR Region", "success",
            "Extracted " . StrLen(text) . " characters`nStored in variable: $var." . varName . "`n`nPreview: " . SubStr(text, 1, 50) . (StrLen(text) > 50 ? "..." : ""))
        try RefreshOCRVarsLV()
        return true
    }

    if SubStr(param, 1, 6) = "split:" {
        ; Split and load into revolver
        splitParam := SubStr(param, 7)
        LoadOCRRevolver(splitParam)
        return true
    }

    if SubStr(param, 1, 6) = "regex:" {
        ; Extract using regex
        pattern := SubStr(param, 7)
        if RegExMatch(text, pattern, &match) {
            extractedText := match[0]
            A_Clipboard := extractedText
            g_LastOCRText := extractedText
            ShowStatus("OCR regex: " . SubStr(extractedText, 1, 30), "ok")
            return true
        } else {
            ShowStatus("OCR: Regex no match", "fail")
            return false
        }
    }

    ; Default: copy to clipboard
    A_Clipboard := text
    ShowStatus("OCR captured: " . SubStr(text, 1, 30) . "...", "ok")
    return true
}





; Execute OCR Click - find text and click on it
ExecuteOCRClick(target, param) {
    global g_OCRSettings

    ; Parse region
    region := ParseRegionCoords(target)
    if !region {
        ; Use full screen
        region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Perform OCR
    searchText := Trim(param)
    if searchText = "" {
        ShowActionNotification("OCR Click", "error", "No search text specified", "PARAM must contain the text to find and click")
        return false
    }

    if !IsOCRAvailable() {
        return ReportOCRError("Click", region, "OCR.ahk library not found or not loaded")
    }

    try {
        ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                  region["x2"] - region["x1"],
                                  region["y2"] - region["y1"],
                                  WorkflowOCR_Options())

        ; Search for the text
        for word in ocrResult.Words {
            if InStr(word.Text, searchText) || InStr(searchText, word.Text) {
                ; Found it - click on center
                center := WorkflowOCR_Center(word)
                clickX := center["x"], clickY := center["y"]

                ; Highlight briefly
                HighlightRegion(clickX - 5, clickY - 5, 10, 10, 500, "match", searchText)

                Click(clickX, clickY)
                ShowActionNotification("OCR Click", "success", "Clicked on '" . searchText . "' at " . clickX . "," . clickY)
                return true
            }
        }

        ; Try partial match on full text lines
        for line in ocrResult.Lines {
            if InStr(line.Text, searchText) {
                ; Click center of line
                center := WorkflowOCR_Center(line)
                clickX := center["x"], clickY := center["y"]

                HighlightRegion(clickX - 20, clickY - 5, 40, 10, 500, "match", searchText)

                Click(clickX, clickY)
                ShowActionNotification("OCR Click", "success", "Clicked on line containing '" . searchText . "'")
                return true
            }
        }

    } catch as e {
        return ReportOCRError("Click", region, e.Message)
    }

    ShowActionNotification("OCR Click", "error",
        "Text not found: '" . searchText . "'",
        "Possible causes:`n• Text is not visible in region`n• Text is too small or blurry`n• Wrong search text`n`nSolutions:`n• Verify text exists and is readable`n• Increase scale in OCR settings`n• Try broader search region`n• Check spelling of search text")
    return false
}

; Execute OCR Wait - wait for text to appear
ExecuteOCRWait(target, param) {
    global g_OCRSettings, g_AbortSequence

    ; Parse region
    region := ParseRegionCoords(target)
    if !region {
        region := Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Parse param: timeout or "text:searchText,timeout"
    timeout := 5000
    searchText := ""

    param := Trim(param)
    if SubStr(param, 1, 5) = "text:" {
        ; Extract search text and optional timeout
        rest := SubStr(param, 6)
        if InStr(rest, ",") {
            parts := StrSplit(rest, ",")
            searchText := Trim(parts[1])
            timeout := Integer(Trim(parts[2]))
        } else {
            searchText := rest
        }
    } else if param != "" {
        timeout := Integer(param)
    }

    ShowStatus("OCR Wait: " . (searchText != "" ? searchText : "any text") . " (" . timeout . "ms)", "wait")

    startTime := A_TickCount
    while (A_TickCount - startTime) < timeout {
        if g_AbortSequence
            return false

        try {
            ocrResult := OCR.FromRect(region["x1"], region["y1"],
                                      region["x2"] - region["x1"],
                                      region["y2"] - region["y1"],
                                      WorkflowOCR_Options())

            if searchText = "" {
                ; Wait for any text
                if ocrResult.Text != "" {
                    ShowStatus("OCR Wait: Text detected", "ok")
                    return true
                }
            } else {
                ; Wait for specific text
                if InStr(ocrResult.Text, searchText) {
                    ShowStatus("OCR Wait: Found '" . searchText . "'", "ok")
                    return true
                }
            }
        }

        Sleep(200)
    }

    ShowStatus("OCR Wait: Timeout", "fail")
    return false
}

; Load OCR text into revolver for sequential pasting
LoadOCRRevolver(param) {
    global g_LastOCRText, g_OCRRevolver, g_OCRRevolverIndex

    if g_LastOCRText = "" {
        ShowStatus("No OCR text to load", "fail")
        return false
    }

    text := g_LastOCRText
    param := Trim(param)
    parts := []

    ; Determine split method
    if param = "tab" {
        ; Split by tabs
        parts := StrSplit(text, "`t")
    } else if param = "line" || param = "lines" {
        ; Split by newlines
        parts := StrSplit(text, "`n")
    } else if IsNumber(param) {
        ; Split into N equal parts
        n := Integer(param)
        if n < 2
            n := 2
        partLen := Ceil(StrLen(text) / n)
        loop n {
            startPos := (A_Index - 1) * partLen + 1
            if startPos <= StrLen(text)
                parts.Push(SubStr(text, startPos, partLen))
        }
    } else if StrLen(param) = 1 {
        ; Split by delimiter character
        parts := StrSplit(text, param)
    } else {
        ; Default: split by spaces into words
        parts := StrSplit(text, " ")
    }

    ; Clean up empty parts
    g_OCRRevolver := []
    for part in parts {
        part := Trim(part)
        if part != ""
            g_OCRRevolver.Push(part)
    }

    g_OCRRevolverIndex := 0

    ShowStatus("OCR Revolver loaded: " . g_OCRRevolver.Length . " parts", "ok")
    return true
}

; Fire next part from OCR revolver
FireOCRRevolver() {
    global g_OCRRevolver, g_OCRRevolverIndex

    if g_OCRRevolver.Length = 0 {
        ShowStatus("OCR Revolver empty", "fail")
        return false
    }

    ; Get next part (cycle around)
    g_OCRRevolverIndex++
    if g_OCRRevolverIndex > g_OCRRevolver.Length
        g_OCRRevolverIndex := 1

    text := g_OCRRevolver[g_OCRRevolverIndex]

    ; Type or paste the text
    A_Clipboard := text
    Sleep(50)
    Send("^v")

    remaining := g_OCRRevolver.Length - g_OCRRevolverIndex
    ShowStatus("OCR Revolver " . g_OCRRevolverIndex . "/" . g_OCRRevolver.Length . ": " . SubStr(text, 1, 20), "ok")

    return true
}

; Parse region coordinates from string "x1,y1,x2,y2" or use saved region

; Check if OCR is available
CheckOCRAvailable() {
    try {
        testResult := OCR.FromRect(0, 0, 100, 100)
        return true
    } catch {
        MsgBox("OCR functionality requires Windows 10 version 1903 or later.`n`nPlease ensure:`n1. Windows is updated`n2. OCR.ahk is in the same folder`n3. You're running Windows 10/11", "OCR Not Available", "Icon!")
        return false
    }
}

ParseRegionCoords(target) {
    target := Trim(target)

    ; Empty or shortcuts
    if target = "" || target = "full" || target = "screen" {
        return Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Last/current
    if target = "current" || target = "last" {
        global g_LastOCRRegion
        if IsSet(g_LastOCRRegion) && g_LastOCRRegion.Count > 0
            return g_LastOCRRegion
        return Map("x1", 0, "y1", 0, "x2", A_ScreenWidth, "y2", A_ScreenHeight)
    }

    ; Dynamic regions keep portable .maw workflows independent of resolution
    ; and window position. Examples: window:MacroAutomator Demo Lab, demo:lab.
    if ResolveWorkflowRegion(target, &dynamicRegion)
        return dynamicRegion

    ; Parse "x1,y1,x2,y2" format
    parts := StrSplit(target, ",")
    if parts.Length >= 4 {
        try {
            x1 := Integer(Trim(parts[1]))
            y1 := Integer(Trim(parts[2]))
            x2 := Integer(Trim(parts[3]))
            y2 := Integer(Trim(parts[4]))

            ; Validate
            if x2 <= x1 || y2 <= y1 {
                return false
            }

            return Map("x1", x1, "y1", y1, "x2", x2, "y2", y2)
        } catch {
            return false
        }
    }

    return false
}

; primary screen).

QuickOCRCapture(*) {
    global g_LastOCRResult
    static busy := false

    if busy              ; one capture at a time
        return
    busy := true
    try {
        sel := QuickOCR_SelectRegion()
        if sel.Count
            QuickOCR_Run(sel)
    } catch as err {
        LogErrorToFile(err, "caught", "Quick OCR (Ctrl+Shift+Q)")
        ShowStatus("Quick OCR failed: " . err.Message, "fail")
    } finally {
        busy := false
    }
}

; Drag out a rectangle over the virtual desktop.
; Returns Map(x, y, w, h) in screen coordinates, or an empty Map when cancelled.
QuickOCR_SelectRegion() {
    ; Virtual-desktop metrics so the overlay covers every monitor, not just the
    ; primary one (A_ScreenWidth/Height describe the primary screen only).
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)

    ; The dim sheet deliberately does NOT use +E0x20 (WS_EX_TRANSPARENT): it must
    ; absorb the drag, otherwise the clicks fall through and press buttons in
    ; whatever application is underneath.
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow", "QuickOCROverlay")
    overlay.BackColor := "101010"
    overlay.Show("x" . vx . " y" . vy . " w" . vw . " h" . vh . " NoActivate")
    WinSetTransparent(70, overlay)

    ; The selection box IS click-through, so it never interrupts the drag.
    selBox := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "QuickOCRBox")
    selBox.BackColor := "00C000"

    TrackToolTip("Quick OCR - drag a box over the text"
          . "`nESC or right-click cancels", vx + vw // 2 - 140, vy + 40)

    rect := Map()
    x1 := 0, y1 := 0, x2 := 0, y2 := 0

    ; Wait for the drag to begin (or for a cancel).
    while true {
        if (GetKeyState("Escape", "P") || GetKeyState("RButton", "P"))
            break
        if GetKeyState("LButton", "P") {
            MouseGetPos(&x1, &y1)
            ; Track the rubber band until the button comes back up.
            while GetKeyState("LButton", "P") {
                if GetKeyState("Escape", "P") {
                    x1 := 0, y1 := 0, x2 := 0, y2 := 0
                    break
                }
                MouseGetPos(&x2, &y2)
                bl := Min(x1, x2), bt := Min(y1, y2)
                bw := Abs(x2 - x1), bh := Abs(y2 - y1)
                if (bw > 2 && bh > 2) {
                    selBox.Show("x" . bl . " y" . bt . " w" . bw . " h" . bh . " NoActivate")
                    WinSetTransparent(120, selBox)
                    TrackToolTip(bw . " x " . bh, x2 + 18, y2 + 18)
                }
                Sleep(16)
            }
            break
        }
        Sleep(10)
    }

    if (x1 || y1 || x2 || y2) {
        rx := Min(x1, x2), ry := Min(y1, y2)
        rw := Abs(x2 - x1), rh := Abs(y2 - y1)
        if (rw >= 8 && rh >= 8)
            rect := Map("x", rx, "y", ry, "w", rw, "h", rh)
        else
            ShowStatus("Quick OCR cancelled - selection too small", "fail")
    }

    ; Tear the overlay down and let the screen repaint BEFORE anything is
    ; captured, or the dim sheet ends up inside the screenshot.
    try selBox.Destroy()
    try overlay.Destroy()
    TrackToolTip()
    Sleep(160)

    return rect
}

; OCR one screen rectangle, copy the text, and show the result window.
QuickOCR_Run(sel) {
    global g_LastOCRResult

    started := A_TickCount
    result := OCR.FromRect(sel["x"], sel["y"], sel["w"], sel["h"], QuickOCR_Options())
    elapsed := A_TickCount - started

    g_LastOCRResult := result          ; keeps the Live OCR tab helpers usable
    text := result.Text

    if (Trim(text) = "") {
        ShowStatus("Quick OCR: no text found in that area", "fail")
        HighlightRegion(sel["x"], sel["y"], sel["w"], sel["h"], 1200, "highlight", "no text")
        return
    }

    A_Clipboard := text
    ShowStatus("Quick OCR: " . result.Words.Length . " words copied to clipboard", "ok")
    QuickOCR_ShowResult(result, sel, elapsed)
}

; Language/scale/grayscale from the Live OCR tab when it exists; sensible
; defaults otherwise. Quick captures default to scale 2 because they are
; usually small patches of text, where upscaling markedly improves accuracy.
QuickOCR_Options() {
    global MainGui
    opts := {scale: 2.0}
    try {
        sc := Float(MainGui["OCRScale"].Value)
        if (sc > 0)
            opts.scale := sc
    }
    try opts.grayscale := MainGui["OCRGrayscale"].Value
    try {
        lang := MainGui["OCRLang"].Text
        if (lang != "")
            opts.lang := lang
    }
    return opts
}

; Compact, always-on-top result window: the text is already on the clipboard,
; this is for reading it, re-copying it, or grabbing another area.
QuickOCR_ShowResult(result, sel, elapsed) {
    static resultGui := ""

    if IsObject(resultGui) {
        try resultGui.Destroy()
        resultGui := ""
    }

    text := result.Text
    g := Gui("+AlwaysOnTop +Resize", "Quick OCR - " . result.Words.Length . " words")
    g.MarginX := 10, g.MarginY := 10

    info := g.Add("Text", "x10 y10 w520 cGray"
        , result.Words.Length . " words, " . result.Lines.Length . " lines  |  "
        . sel["w"] . " x " . sel["h"] . " at " . sel["x"] . "," . sel["y"]
        . "  |  " . elapsed . " ms  |  copied to clipboard")

    ed := g.Add("Edit", "x10 y32 w520 h220 Multi VScroll ReadOnly vQuickOCRText", text)
    ed.SetFont("s10", "Consolas")

    g.Add("Button", "x10 y262 w100 h26", "Copy Again").OnEvent("Click"
        , (*) => (A_Clipboard := text, ShowStatus("Copied " . StrLen(text) . " chars", "ok")))
    g.Add("Button", "x116 y262 w110 h26", "Show Region").OnEvent("Click"
        , (*) => HighlightRegion(sel["x"], sel["y"], sel["w"], sel["h"], 1500, "highlight", "Quick OCR"))
    g.Add("Button", "x232 y262 w120 h26", "New Capture ^+Q").OnEvent("Click"
        , (*) => (g.Destroy(), SetTimer(() => QuickOCRCapture(), -120)))
    g.Add("Button", "x358 y262 w80 h26 Default", "Close").OnEvent("Click", (*) => g.Destroy())

    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Size", QuickOCR_ResultResize)
    g.Show("w540 h300")
    resultGui := g
}

QuickOCR_ResultResize(g, minMax, w, h) {
    if (minMax = -1)
        return
    try g["QuickOCRText"].Move(, , w - 20, h - 90)
    ; Keep the button row pinned to the bottom edge.
    try {
        for ctrl in g {
            if (ctrl.Type = "Button")
                ctrl.Move(, h - 38)
        }
    }
}


GetActionExamples(actionType) {
    examples := Map()

    examples["Click"] := "Example: coord=MyButton, button=left, count=1"
    examples["ClickImage"] := "Example: pattern=SubmitBtn, variation=15"
    examples["OCR"] := "Example: region=TextArea, language=en-us, scale=1.5"
    examples["OCRClick"] := "Example: text=Submit, region=ButtonArea, partial=true"
    examples["Send"] := "Example: text=Hello{Enter}, raw=false"
    examples["Wait"] := "Example: duration=1000"
    examples["Drag"] := "Example: from=Start, to=End, speed=5"
    examples["WaitForText"] := "Example: text=Complete, region=Status, timeout=60"
    examples["WaitForImage"] := "Example: pattern=Loading, timeout=30"
    examples["SetVariable"] := "Example: name=MyVar, value=test"

    if examples.Has(actionType)
        return "📝 Example usage:`n   " . examples[actionType]

    return ""
}

ReportOCRError(operation, region, details := "") {
    errorMsg := "OCR Operation: " . operation . "`n"
    if IsObject(region) && region.Has("x1") {
        regionText := region["x1"] . "," . region["y1"] . "," . region["x2"] . "," . region["y2"]
    } else if IsObject(region) && region.Has("x") {
        regionText := region["x"] . "," . region["y"] . "," . region["w"] . "," . region["h"]
    } else {
        regionText := String(region)
    }
    errorMsg .= "Region: " . regionText . "`n"

    reasons := []

    if !IsOCRAvailable()
        reasons.Push("OCR.ahk library not found or not loaded")

    if IsObject(region) {
        if region.Has("w") && region.Has("h") && (region["w"] <= 0 || region["h"] <= 0)
            reasons.Push("Invalid region dimensions (width/height must be > 0)")
        else if region.Has("x1") && region.Has("x2") && (region["x2"] <= region["x1"] || region["y2"] <= region["y1"])
            reasons.Push("Invalid region dimensions (width/height must be > 0)")
    }

    if details != ""
        reasons.Push(details)

    if reasons.Length = 0
        reasons.Push("No text detected in specified region")

    errorMsg .= "`nPossible causes:`n"
    for reason in reasons
        errorMsg .= "  • " . reason . "`n"

    errorMsg .= "`nSolutions:`n"
    errorMsg .= "  • Verify OCR.ahk is in script directory`n"
    errorMsg .= "  • Increase scale parameter (try 1.5-2.0)`n"
    errorMsg .= "  • Ensure region contains visible text`n"
    errorMsg .= "  • Check region coordinates are correct`n"
    errorMsg .= "  • Verify text is not obscured or too small"

    ShowActionNotification("OCR", "error", "OCR failed", errorMsg)
    LogDiagnostic(errorMsg, "OCR " . operation)

    global g_LastActionError := errorMsg
    return false
}

; IsOCRAvailable() {
;     try {
;         return IsFunc("OCR") || IsSet(OCR)
;     }
;     return false
; }
IsOCRAvailable() {
    try return FanFileExist(OCR.HelperPath) != ""
    return false
}


; ═══════════════════════════════════════════════════════════════════════════════
; SnapshotEngine.ahk - Feature 4: 5-minute whole-desktop snapshot cycles
; ═══════════════════════════════════════════════════════════════════════════════
; Every 5 minutes (configurable) the engine walks every visible top-level
; window and, for each, produces THREE linked representations of the same frame:
;
;   1. RAW IMAGE   a full-resolution .png saved to a known, tracked path
;                  (data\tracking\snapshots\<cycle>\<n>_<window>.png)
;   2. BASE64      the raw file's bytes, base64-encoded, stored as text in the DB
;   3. BINARY      a thresholded 1-bit "FindText image" in the exact
;                  |<>*threshold$W.base64 format FindText itself emits, so it can
;                  be pasted straight into a FindText pattern
;
;   (plus optional OCR text of the frame)
;
; All three, keyed to the same snap_entry row, feed the tabbed viewer where the
; user highlights an element and names it. That named element is what the
; automation engine consumes later.
;
; Capturing runs one window per timer tick (SnapshotEngine.ahk drives an
; internal queue) so a cycle never freezes the UI thread for long.
; ═══════════════════════════════════════════════════════════════════════════════

; ─── Configuration ───────────────────────────────────────────────────────────
global g_SnapOn := false
global g_SnapIntervalMs := 300000       ; 5 minutes between cycles
global g_SnapStepMs := 250              ; Delay between capturing each window
global g_SnapBinaryMaxDim := 320        ; Cap on the binary form's longest side
global g_SnapImageFormat := "png"       ; png | jpg
global g_SnapMinArea := 10000           ; Skip windows smaller than this (px^2)
global g_SnapDoOCR := false             ; Run OCR on each capture (slower)
global g_SnapDir := ""                  ; Resolved snapshots root

; ─── Cycle state ─────────────────────────────────────────────────────────────
global g_SnapCycleId := 0
global g_SnapQueue := []                ; Pending hwnds for the active cycle
global g_SnapCycleDir := ""
global g_SnapCycleCount := 0
global g_SnapBusy := false
global g_SnapLastCycleTs := ""
global g_SnapOnCycleDone := ""          ; Optional callback(cycleId) after a cycle

; ═══════════════════════════════════════════════════════════════════════════════
; PUBLIC CONTROL
; ═══════════════════════════════════════════════════════════════════════════════

Snap_Init() {
    global g_SnapDir, DATA_DIR
    g_SnapDir := DATA_DIR . "\tracking\snapshots"
    if !DirExist(g_SnapDir) {
        try DirCreate(g_SnapDir)
    }
}

Snap_Start() {
    global g_SnapOn, g_SnapIntervalMs

    if !TrackDB_Ready() {
        if !TrackDB_Init()
            return false
    }
    Snap_Init()
    if g_SnapOn
        return true

    g_SnapOn := true
    SetTimer(Snap_CycleTick, g_SnapIntervalMs)
    return true
}

Snap_Stop() {
    global g_SnapOn
    if !g_SnapOn
        return
    SetTimer(Snap_CycleTick, 0)
    SetTimer(Snap_StepTick, 0)
    Snap_AbortCycle()
    g_SnapOn := false
}

Snap_Toggle() {
    global g_SnapOn
    if g_SnapOn
        Snap_Stop()
    else
        Snap_Start()
    return g_SnapOn
}

Snap_IsOn() {
    global g_SnapOn
    return g_SnapOn
}

; ═══════════════════════════════════════════════════════════════════════════════
; CYCLE ORCHESTRATION
; ═══════════════════════════════════════════════════════════════════════════════

; Timer entry: begin a new cycle unless one is still draining.
Snap_CycleTick() {
    global g_SnapBusy
    if g_SnapBusy
        return
    Snap_RunCycleNow()
}

; Kick off a cycle immediately (also used by the "Snapshot Now" button).
; Returns the new cycle id, or 0 when one is already running.
Snap_RunCycleNow(note := "") {
    global g_SnapBusy, g_SnapCycleId, g_SnapQueue, g_SnapCycleDir
    global g_SnapCycleCount, g_SnapDir, g_SnapStepMs, g_SnapMinArea

    if g_SnapBusy
        return 0
    if !TrackDB_Ready()
        return 0

    ; ─── Enumerate capturable windows ────────────────────────────────────────
    queue := []
    myPid := DllCall("GetCurrentProcessId", "UInt")
    for hwnd in WinGetList() {
        ; Only visible, titled, non-tool windows with real area.
        if !WinExist("ahk_id " . hwnd)
            continue
        title := ""
        try title := WinGetTitle("ahk_id " . hwnd)
        if (title = "" || title = "Program Manager")
            continue
        pid := 0
        try pid := WinGetPID("ahk_id " . hwnd)
        if (pid = myPid)          ; Skip our own GUI
            continue
        style := 0
        try style := WinGetStyle("ahk_id " . hwnd)
        if !(style & 0x10000000)  ; WS_VISIBLE
            continue
        if (style & 0x20000000)   ; WS_MINIMIZE
            continue
        try {
            WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
            if (ww * wh < g_SnapMinArea)
                continue
        } catch {
            continue
        }
        queue.Push(hwnd)
    }

    if !queue.Length
        return 0

    ; ─── Open the cycle + its output directory ───────────────────────────────
    cycleId := TrackDB_StartCycle(note)
    if !cycleId
        return 0

    Snap_Init()
    cycleDir := g_SnapDir . "\" . cycleId
    if !DirExist(cycleDir) {
        try DirCreate(cycleDir)
    }

    g_SnapCycleId := cycleId
    g_SnapQueue := queue
    g_SnapCycleDir := cycleDir
    g_SnapCycleCount := 0
    g_SnapBusy := true

    ; Drain one window per tick so the UI stays responsive.
    SetTimer(Snap_StepTick, g_SnapStepMs)
    return cycleId
}

; Capture the next queued window.
Snap_StepTick() {
    global g_SnapQueue, g_SnapCycleId, g_SnapCycleDir, g_SnapCycleCount, g_SnapBusy

    if !g_SnapQueue.Length {
        Snap_FinishCycle()
        return
    }

    hwnd := g_SnapQueue.RemoveAt(1)
    try {
        if Snap_CaptureWindow(g_SnapCycleId, g_SnapCycleDir, hwnd, g_SnapCycleCount + 1)
            g_SnapCycleCount++
    } catch as err {
        TrackLogError("Snap_CaptureWindow", err)
    }

    if !g_SnapQueue.Length
        Snap_FinishCycle()
}

Snap_FinishCycle() {
    global g_SnapCycleId, g_SnapCycleCount, g_SnapBusy, g_SnapLastCycleTs, g_SnapOnCycleDone

    SetTimer(Snap_StepTick, 0)
    if g_SnapCycleId {
        try TrackDB_FinishCycle(g_SnapCycleId, g_SnapCycleCount)
        g_SnapLastCycleTs := TrackTS()
        finished := g_SnapCycleId
    } else {
        finished := 0
    }
    g_SnapBusy := false
    id := g_SnapCycleId
    g_SnapCycleId := 0

    if (finished && g_SnapOnCycleDone != "") {
        try (g_SnapOnCycleDone)(finished)
    }
}

Snap_AbortCycle() {
    global g_SnapCycleId, g_SnapCycleCount, g_SnapQueue, g_SnapBusy
    SetTimer(Snap_StepTick, 0)
    if g_SnapCycleId {
        try TrackDB_FinishCycle(g_SnapCycleId, g_SnapCycleCount)
    }
    g_SnapQueue := []
    g_SnapCycleId := 0
    g_SnapBusy := false
}

; ═══════════════════════════════════════════════════════════════════════════════
; SINGLE WINDOW CAPTURE
; ═══════════════════════════════════════════════════════════════════════════════

; Capture one window into all representations and store a snap_entry row.
; Returns true on success.
Snap_CaptureWindow(cycleId, cycleDir, hwnd, index) {
    global g_SnapImageFormat, g_SnapDoOCR

    if !WinExist("ahk_id " . hwnd)
        return false

    title := "", exe := "", class := ""
    try title := WinGetTitle("ahk_id " . hwnd)
    try exe := WinGetProcessName("ahk_id " . hwnd)
    try class := WinGetClass("ahk_id " . hwnd)
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
    if (ww < 1 || wh < 1)
        return false

    x2 := wx + ww - 1
    y2 := wy + wh - 1

    ; Clip to the virtual desktop so off-screen regions do not distort capture.
    vx := SysGet(76), vy := SysGet(77), vw := SysGet(78), vh := SysGet(79)
    capX := Max(wx, vx)
    capY := Max(wy, vy)
    capX2 := Min(x2, vx + vw - 1)
    capY2 := Min(y2, vy + vh - 1)
    capW := capX2 - capX + 1
    capH := capY2 - capY + 1
    if (capW < 4 || capH < 4)
        return false

    ; ─── Resolve identity so the snapshot ties into window/mouse/key data ────
    winId := 0, appId := 0
    try {
        ident := TrackDB_ResolveWindow(title, class, exe)
        winId := ident["win_id"]
        appId := ident["app_id"]
    } catch as err {
        TrackLogError("Snap_Resolve", err)
    }

    ; ─── 1. RAW IMAGE to disk ────────────────────────────────────────────────
    ext := (g_SnapImageFormat = "jpg") ? "jpg" : "png"
    fileName := Format("{:02d}", index) . "_" . TrackSafeName(title = "" ? exe : title)
              . "." . ext
    imgPath := cycleDir . "\" . fileName

    pBitmap := 0
    try pBitmap := Gdip_BitmapFromScreen(capX . "|" . capY . "|" . capW . "|" . capH)
    if !pBitmap
        return false

    saveOk := Gdip_SaveBitmapToFile(pBitmap, imgPath) = 0
    Gdip_DisposeImage(pBitmap)
    if !saveOk
        return false

    imgBytes := 0
    try imgBytes := FileGetSize(imgPath)

    ; ─── 2. BASE64 of the raw file ───────────────────────────────────────────
    b64 := ""
    try b64 := TrackBase64EncodeFile(imgPath)
    imgHash := TrackHash(b64 = "" ? imgPath : SubStr(b64, 1, 4096))

    ; ─── 3. BINARY (FindText image form) ─────────────────────────────────────
    bin := Snap_MakeBinary(capX, capY, capW, capH)

    ; ─── OCR (optional) ──────────────────────────────────────────────────────
    ocrText := ""
    if g_SnapDoOCR {
        try {
            res := OCR.FromRect(capX, capY, capW, capH)
            ocrText := res.Text
        } catch as err {
            ; OCR is best-effort; a failure must not abort the capture.
        }
    }

    ; ─── Persist ─────────────────────────────────────────────────────────────
    entry := Map(
        "cycle_id", cycleId,
        "win_id", winId,
        "app_id", appId,
        "hwnd", hwnd,
        "title", title,
        "exe", exe,
        "class", class,
        "ts", TrackTS(),
        "x", capX, "y", capY, "w", capW, "h", capH,
        "image_path", imgPath,
        "image_format", ext,
        "image_bytes", imgBytes,
        "image_hash", imgHash,
        "b64", b64,
        "b64_len", StrLen(b64),
        "bin_text", bin["text"],
        "bin_w", bin["w"],
        "bin_h", bin["h"],
        "threshold", bin["threshold"],
        "ocr_text", ocrText
    )
    try TrackDB_AddSnapEntry(entry)
    catch as err {
        TrackLogError("Snap_AddEntry", err)
        return false
    }
    return true
}

; ═══════════════════════════════════════════════════════════════════════════════
; BINARY IMAGE (FindText-compatible)
; ═══════════════════════════════════════════════════════════════════════════════
; Produces the same "|<>*threshold$W.base64bits" string FindText uses, by:
;   1. taking a fresh screen capture of the region into FindText's bit buffer
;   2. down-sampling to a capped resolution (nearest neighbour)
;   3. computing a grayscale Otsu threshold
;   4. emitting 1/0 per pixel and packing with FindText().bit2base64()
;
; The cap keeps a full-screen window from producing a multi-megabyte blob while
; the format stays byte-for-byte usable inside FindText patterns.
Snap_MakeBinary(x, y, w, h) {
    global g_SnapBinaryMaxDim

    result := Map("text", "", "w", 0, "h", 0, "threshold", "")

    ft := FindText()
    ; Snapshot the region into FindText's internal buffer so GetColor reads it.
    try ft.ScreenShot(x, y, x + w - 1, y + h - 1)
    catch as err {
        TrackLogError("Snap_MakeBinary(screenshot)", err)
        return result
    }

    ; Down-sample factor so the longest side <= cap.
    longest := Max(w, h)
    step := 1
    if (longest > g_SnapBinaryMaxDim)
        step := Ceil(longest / g_SnapBinaryMaxDim)
    outW := Max(1, w // step)
    outH := Max(1, h // step)

    ; First pass: grayscale samples + histogram for Otsu.
    gray := []
    hist := []
    Loop 256
        hist.Push(0)

    idx := 0
    row := 0
    while (row < outH) {
        sy := y + row * step
        col := 0
        while (col < outW) {
            sx := x + col * step
            c := ft.GetColor(sx, sy, 0)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            ; Rec.601 luma
            lum := (r * 38 + g * 75 + b * 15) >> 7
            gray.Push(lum)
            hist[lum + 1] := hist[lum + 1] + 1
            col++
        }
        row++
    }

    threshold := Snap_Otsu(hist, gray.Length)

    ; Second pass: pixels darker than the threshold are "on" (1), matching how
    ; FindText treats foreground text/edges.
    bits := ""
    for lum in gray
        bits .= (lum <= threshold) ? "1" : "0"

    packed := ""
    try packed := ft.bit2base64(bits)
    catch as err {
        TrackLogError("Snap_MakeBinary(pack)", err)
        return result
    }

    result["text"] := "|<>*" . threshold . "$" . outW . "." . packed
    result["w"] := outW
    result["h"] := outH
    result["threshold"] := "*" . threshold
    return result
}

; Otsu's method: pick the grayscale threshold that maximises between-class
; variance. `hist` is a 256-bin histogram, `total` the pixel count.
Snap_Otsu(hist, total) {
    if (total <= 0)
        return 128

    sumAll := 0.0
    Loop 256
        sumAll += (A_Index - 1) * hist[A_Index]

    sumB := 0.0
    wB := 0
    maxVar := -1.0
    threshold := 128

    Loop 256 {
        wB += hist[A_Index]
        if (wB = 0)
            continue
        wF := total - wB
        if (wF = 0)
            break
        sumB += (A_Index - 1) * hist[A_Index]
        mB := sumB / wB
        mF := (sumAll - sumB) / wF
        between := wB * wF * (mB - mF) * (mB - mF)
        if (between > maxVar) {
            maxVar := between
            threshold := A_Index - 1
        }
    }
    return threshold
}

; ═══════════════════════════════════════════════════════════════════════════════
; BINARY IMAGE RENDERING (for the viewer)
; ═══════════════════════════════════════════════════════════════════════════════

; Decode a FindText image string back into a PNG so the viewer can show the
; binary form as an actual (upscaled) picture. Returns the output path or "".
Snap_RenderBinary(binText, outPath, scale := 2, onColor := 0xFF000000, offColor := 0xFFFFFFFF) {
    if (binText = "")
        return ""

    ; Parse "|<...>*threshold$W.base64"
    if !RegExMatch(binText, "\$(\d+)\.([\w+/]+)", &m)
        return ""
    w := Integer(m[1])
    if (w < 1)
        return ""

    ft := FindText()
    bits := ""
    try bits := ft.base64tobit(m[2])
    catch as err {
        TrackLogError("Snap_RenderBinary", err)
        return ""
    }
    if (bits = "")
        return ""

    h := StrLen(bits) // w
    if (h < 1)
        return ""

    scale := Max(1, Integer(scale))
    canvas := PixelCanvas(w * scale, h * scale, offColor)

    ; Walk the bit string row-major, painting "on" pixels as scale x scale blocks.
    i := 1
    len := StrLen(bits)
    row := 0
    while (row < h) {
        col := 0
        while (col < w) {
            if (i > len)
                break
            if (SubStr(bits, i, 1) = "1")
                canvas.FillRect(col * scale, row * scale, scale, scale, onColor)
            i++
            col++
        }
        row++
    }

    return canvas.Save(outPath) ? outPath : ""
}

; ═══════════════════════════════════════════════════════════════════════════════
; FILE -> BINARY / CROP  (used by the element registry, no screen dependency)
; ═══════════════════════════════════════════════════════════════════════════════

; Convert an image FILE region into a FindText image string. Because it reads
; the stored .png rather than the live screen, an element pattern can be built
; long after the source window has closed or moved.
;
; x,y,w,h are pixels within the source image (0 = whole image).
Snap_FileToBinary(path, x := 0, y := 0, w := 0, h := 0) {
    global g_SnapBinaryMaxDim
    result := Map("text", "", "w", 0, "h", 0, "threshold", "")

    if !FileExist(path)
        return result

    pBitmap := SnapGdip_LoadFile(path)
    if !pBitmap
        return result

    imgW := 0, imgH := 0
    SnapGdip_Dimensions(pBitmap, &imgW, &imgH)
    if (imgW < 1 || imgH < 1) {
        SnapGdip_Dispose(pBitmap)
        return result
    }

    if (w <= 0)
        w := imgW - x
    if (h <= 0)
        h := imgH - y
    x := Integer(TrackClamp(x, 0, imgW - 1))
    y := Integer(TrackClamp(y, 0, imgH - 1))
    w := Integer(TrackClamp(w, 1, imgW - x))
    h := Integer(TrackClamp(h, 1, imgH - y))

    longest := Max(w, h)
    step := (longest > g_SnapBinaryMaxDim) ? Ceil(longest / g_SnapBinaryMaxDim) : 1
    outW := Max(1, w // step)
    outH := Max(1, h // step)

    gray := []
    hist := []
    Loop 256
        hist.Push(0)

    row := 0
    while (row < outH) {
        sy := y + row * step
        col := 0
        while (col < outW) {
            sx := x + col * step
            c := SnapGdip_GetPixel(pBitmap, sx, sy)
            r := (c >> 16) & 0xFF
            g := (c >> 8) & 0xFF
            b := c & 0xFF
            lum := (r * 38 + g * 75 + b * 15) >> 7
            gray.Push(lum)
            hist[lum + 1] := hist[lum + 1] + 1
            col++
        }
        row++
    }
    SnapGdip_Dispose(pBitmap)

    threshold := Snap_Otsu(hist, gray.Length)
    bits := ""
    for lum in gray
        bits .= (lum <= threshold) ? "1" : "0"

    packed := ""
    try packed := FindText().bit2base64(bits)
    catch as err {
        TrackLogError("Snap_FileToBinary(pack)", err)
        return result
    }

    result["text"] := "|<>*" . threshold . "$" . outW . "." . packed
    result["w"] := outW
    result["h"] := outH
    result["threshold"] := "*" . threshold
    return result
}

; Crop a region out of an image file into a new PNG. Returns outPath or "".
Snap_CropToFile(srcPath, x, y, w, h, outPath) {
    if !FileExist(srcPath)
        return ""
    pBitmap := SnapGdip_LoadFile(srcPath)
    if !pBitmap
        return ""

    imgW := 0, imgH := 0
    SnapGdip_Dimensions(pBitmap, &imgW, &imgH)
    x := Integer(TrackClamp(x, 0, imgW - 1))
    y := Integer(TrackClamp(y, 0, imgH - 1))
    w := Integer(TrackClamp(w, 1, imgW - x))
    h := Integer(TrackClamp(h, 1, imgH - y))

    pClone := 0
    ; PixelFormat32bppARGB = 0x0026200A
    DllCall("gdiplus\GdipCloneBitmapAreaI", "Int", x, "Int", y, "Int", w, "Int", h
        , "Int", 0x0026200A, "Ptr", pBitmap, "Ptr*", &pClone)
    SnapGdip_Dispose(pBitmap)
    if !pClone
        return ""

    dir := ""
    SplitPath(outPath, , &dir)
    if (dir != "" && !DirExist(dir)) {
        try DirCreate(dir)
    }
    if FileExist(outPath) {
        try FileDelete(outPath)
    }
    ok := Gdip_SaveBitmapToFile(pClone, outPath) = 0
    SnapGdip_Dispose(pClone)
    return ok ? outPath : ""
}

; ─── Small GDI+ readers (kept local so the feature is self-contained) ────────

SnapGdip_LoadFile(path) {
    pBitmap := 0
    if (DllCall("gdiplus\GdipCreateBitmapFromFile", "WStr", path, "Ptr*", &pBitmap) != 0)
        return 0
    return pBitmap
}

SnapGdip_Dimensions(pBitmap, &w, &h) {
    w := 0, h := 0
    DllCall("gdiplus\GdipGetImageWidth", "Ptr", pBitmap, "UInt*", &w)
    DllCall("gdiplus\GdipGetImageHeight", "Ptr", pBitmap, "UInt*", &h)
}

SnapGdip_GetPixel(pBitmap, x, y) {
    argb := 0
    DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", pBitmap, "Int", x, "Int", y, "UInt*", &argb)
    return argb & 0xFFFFFF
}

SnapGdip_Dispose(pBitmap) {
    if pBitmap
        DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
}

; ═══════════════════════════════════════════════════════════════════════════════
; ASCII PREVIEW (compact, for tooltips / text views)
; ═══════════════════════════════════════════════════════════════════════════════

Snap_BinaryToAscii(binText, maxWidth := 100) {
    if !RegExMatch(binText, "\$(\d+)\.([\w+/]+)", &m)
        return ""
    w := Integer(m[1])
    if (w < 1)
        return ""
    ft := FindText()
    bits := ""
    try bits := ft.base64tobit(m[2])
    if (bits = "")
        return ""
    h := StrLen(bits) // w

    ; Down-sample columns/rows to fit maxWidth.
    step := (w > maxWidth) ? Ceil(w / maxWidth) : 1
    out := ""
    row := 0
    while (row < h) {
        line := ""
        col := 0
        while (col < w) {
            ch := SubStr(bits, row * w + col + 1, 1)
            line .= (ch = "1") ? "#" : " "
            col += step
        }
        out .= RegExReplace(line, "\s+$") . "`n"
        row += step
    }
    return out
}

; ═══════════════════════════════════════════════════════════════════════════════
; STATUS
; ═══════════════════════════════════════════════════════════════════════════════

Snap_StatusLine() {
    global g_SnapOn, g_SnapBusy, g_SnapCycleCount, g_SnapQueue, g_SnapLastCycleTs
    if !g_SnapOn
        return "Snapshots: OFF"
    if g_SnapBusy
        return "Snapshots: capturing (" . g_SnapCycleCount . " done, "
             . g_SnapQueue.Length . " left)"
    return "Snapshots: ON" . (g_SnapLastCycleTs != "" ? " (last " . g_SnapLastCycleTs . ")" : "")
}

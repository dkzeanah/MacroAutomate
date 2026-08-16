; ═══════════════════════════════════════════════════════════════════════════════
; TrackUtil.ahk - Shared helpers for the MacroAutomator tracking subsystem
; ═══════════════════════════════════════════════════════════════════════════════
; Time keys, window-name normalisation, JSON, CSV, hashing and small string
; utilities used by the window / mouse / key / snapshot trackers.
; ═══════════════════════════════════════════════════════════════════════════════

; ═══════════════════════════════════════════════════════════════════════════════
; TIME KEYS
; ═══════════════════════════════════════════════════════════════════════════════

; ISO-8601-ish timestamp with millisecond precision, sortable as text.
TrackTS(when := "") {
    stamp := (when = "") ? A_Now : when
    return FormatTime(stamp, "yyyy-MM-dd HH:mm:ss")
}

; Bucket key for 1-minute snapshots: "yyyyMMddHHmm".
TrackMinuteKey(when := "") {
    stamp := (when = "") ? A_Now : when
    return FormatTime(stamp, "yyyyMMddHHmm")
}

; Day bucket, used for per-day rollups.
TrackDayKey(when := "") {
    stamp := (when = "") ? A_Now : when
    return FormatTime(stamp, "yyyy-MM-dd")
}

; Human readable duration from milliseconds: "2h 14m 03s".
TrackFormatMs(ms) {
    if !IsNumber(ms)
        return "0s"
    ms := Integer(ms)
    if (ms < 0)
        ms := 0
    totalSec := ms // 1000
    h := totalSec // 3600
    m := Mod(totalSec, 3600) // 60
    s := Mod(totalSec, 60)
    if (h > 0)
        return h . "h " . Format("{:02d}", m) . "m " . Format("{:02d}", s) . "s"
    if (m > 0)
        return m . "m " . Format("{:02d}", s) . "s"
    return s . "s"
}

; Milliseconds between two A_Now style stamps (yyyyMMddHHmmss).
TrackStampDiffMs(fromStamp, toStamp) {
    d := DateDiff(toStamp, fromStamp, "Seconds")
    return d * 1000
}

; ═══════════════════════════════════════════════════════════════════════════════
; WINDOW IDENTITY
; ═══════════════════════════════════════════════════════════════════════════════

; Stable key for an application surface: process + window class.
TrackAppKey(exe, class) {
    exe := Trim(exe) = "" ? "unknown.exe" : Trim(exe)
    class := Trim(class) = "" ? "?" : Trim(class)
    return exe . "|" . class
}

; Reduce a raw window title to a stable, unique-per-purpose name.
;
; Removals are limited to volatility that would otherwise fragment tracking:
;   "(3) Inbox - Gmail"        -> "Inbox - Gmail"
;   "* untitled.txt - Notepad" -> "untitled.txt"
;   "Doc.docx - Word"          -> "Doc.docx"      (trailing app name matching exe)
;   "  spaced   out  "         -> "spaced out"
;
; aggressive:=true additionally masks long digit runs so per-record titles
; ("Order 100482 - CRM") collapse into one tracked name ("Order # - CRM").
TrackNormalizeWindowName(title, exe := "", aggressive := false) {
    name := Trim(title)
    if (name = "")
        return "(untitled)"

    ; Leading unread/notification counters
    name := RegExReplace(name, "^\(\d+\)\s*", "")
    ; Leading dirty-document markers
    name := RegExReplace(name, "^[\*●•]\s*", "")

    ; Trailing " - <application>" when it echoes the executable name
    if (exe != "") {
        SplitPath(exe, , , , &exeBase)
        if (exeBase != "") {
            ; Escape the base name for use inside the pattern
            esc := RegExReplace(exeBase, "([\\.\*\?\+\[\]\{\}\(\)\|\^\$])", "\$1")
            name := RegExReplace(name, "i)\s*[-\x{2013}\x{2014}\|]\s*" . esc . "\s*$", "")
        }
    }

    ; Common browser/editor suffixes that add no identity
    name := RegExReplace(name, "i)\s*[-\x{2013}\x{2014}]\s*(Google Chrome|Mozilla Firefox|Microsoft.\s*Edge|Microsoft Edge|Brave|Opera)\s*$", "")

    if aggressive {
        ; Mask record identifiers so "Order 1004" and "Order 1005" share a name
        name := RegExReplace(name, "\d{3,}", "#")
    }

    ; Collapse whitespace
    name := Trim(RegExReplace(name, "\s+", " "))
    if (name = "")
        return "(untitled)"
    if (StrLen(name) > 200)
        name := SubStr(name, 1, 197) . "..."
    return name
}

; Snapshot of the currently focused window, or an empty-ish Map when none.
TrackGetActiveWindow() {
    info := Map("hwnd", 0, "title", "", "class", "", "exe", "", "pid", 0,
                "x", 0, "y", 0, "w", 0, "h", 0, "ok", false)
    hwnd := 0
    try hwnd := WinGetID("A")
    if !hwnd
        return info
    info["hwnd"] := hwnd
    try info["title"] := WinGetTitle("ahk_id " . hwnd)
    try info["class"] := WinGetClass("ahk_id " . hwnd)
    try info["exe"] := WinGetProcessName("ahk_id " . hwnd)
    try info["pid"] := WinGetPID("ahk_id " . hwnd)
    try {
        WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " . hwnd)
        info["x"] := wx, info["y"] := wy, info["w"] := ww, info["h"] := wh
    }
    info["ok"] := true
    return info
}

; ═══════════════════════════════════════════════════════════════════════════════
; JSON
; ═══════════════════════════════════════════════════════════════════════════════
; Minimal encoder/decoder. Maps become objects, Arrays become arrays, numbers
; stay unquoted, everything else is emitted as a string.

TrackJsonEscape(str) {
    str := StrReplace(str, "\", "\\")
    str := StrReplace(str, '"', '\"')
    str := StrReplace(str, "`n", "\n")
    str := StrReplace(str, "`r", "\r")
    str := StrReplace(str, "`t", "\t")
    str := StrReplace(str, Chr(8), "\b")
    str := StrReplace(str, Chr(12), "\f")
    ; Strip remaining control characters that would produce invalid JSON
    return RegExReplace(str, "[\x00-\x1F]", "")
}

TrackJsonEncode(value, indent := 0, level := 0) {
    pad := ""
    padIn := ""
    nl := ""
    if (indent > 0) {
        nl := "`n"
        Loop level * indent
            pad .= " "
        Loop (level + 1) * indent
            padIn .= " "
    }

    if (value is Map) {
        if (value.Count = 0)
            return "{}"
        parts := []
        for k, v in value
            parts.Push(padIn . '"' . TrackJsonEscape(String(k)) . '":' . (indent > 0 ? " " : "")
                . TrackJsonEncode(v, indent, level + 1))
        return "{" . nl . TrackArrayJoin(parts, "," . nl) . nl . pad . "}"
    }

    if (value is Array) {
        if (value.Length = 0)
            return "[]"
        parts := []
        for v in value
            parts.Push(padIn . TrackJsonEncode(v, indent, level + 1))
        return "[" . nl . TrackArrayJoin(parts, "," . nl) . nl . pad . "]"
    }

    if (value is Integer || value is Float)
        return String(value)

    if (value == "")
        return '""'

    ; Numeric-looking strings stay strings so ids and codes round-trip intact.
    return '"' . TrackJsonEscape(String(value)) . '"'
}

; Parse a JSON document into Maps / Arrays / strings / numbers.
; Throws on malformed input.
TrackJsonDecode(text) {
    pos := 1
    val := _TrackJsonValue(text, &pos)
    _TrackJsonSkipWs(text, &pos)
    return val
}

_TrackJsonSkipWs(text, &pos) {
    while (pos <= StrLen(text)) {
        c := SubStr(text, pos, 1)
        if (c = " " || c = "`t" || c = "`n" || c = "`r")
            pos++
        else
            break
    }
}

_TrackJsonValue(text, &pos) {
    _TrackJsonSkipWs(text, &pos)
    if (pos > StrLen(text))
        throw Error("JSON: unexpected end of input")
    c := SubStr(text, pos, 1)
    switch c {
        case "{": return _TrackJsonObject(text, &pos)
        case "[": return _TrackJsonArray(text, &pos)
        case '"': return _TrackJsonString(text, &pos)
    }
    if (c = "t" && SubStr(text, pos, 4) = "true") {
        pos += 4
        return true
    }
    if (c = "f" && SubStr(text, pos, 5) = "false") {
        pos += 5
        return false
    }
    if (c = "n" && SubStr(text, pos, 4) = "null") {
        pos += 4
        return ""
    }
    if RegExMatch(text, "^-?\d+(\.\d+)?([eE][+-]?\d+)?", &m, pos) {
        pos += StrLen(m[0])
        return InStr(m[0], ".") || InStr(m[0], "e") || InStr(m[0], "E") ? Float(m[0]) : Integer(m[0])
    }
    throw Error("JSON: unexpected character '" . c . "' at " . pos)
}

_TrackJsonObject(text, &pos) {
    obj := Map()
    pos++  ; consume {
    _TrackJsonSkipWs(text, &pos)
    if (SubStr(text, pos, 1) = "}") {
        pos++
        return obj
    }
    loop {
        _TrackJsonSkipWs(text, &pos)
        key := _TrackJsonString(text, &pos)
        _TrackJsonSkipWs(text, &pos)
        if (SubStr(text, pos, 1) != ":")
            throw Error("JSON: expected ':' at " . pos)
        pos++
        obj[key] := _TrackJsonValue(text, &pos)
        _TrackJsonSkipWs(text, &pos)
        c := SubStr(text, pos, 1)
        if (c = ",") {
            pos++
            continue
        }
        if (c = "}") {
            pos++
            return obj
        }
        throw Error("JSON: expected ',' or '}' at " . pos)
    }
}

_TrackJsonArray(text, &pos) {
    arr := []
    pos++  ; consume [
    _TrackJsonSkipWs(text, &pos)
    if (SubStr(text, pos, 1) = "]") {
        pos++
        return arr
    }
    loop {
        arr.Push(_TrackJsonValue(text, &pos))
        _TrackJsonSkipWs(text, &pos)
        c := SubStr(text, pos, 1)
        if (c = ",") {
            pos++
            continue
        }
        if (c = "]") {
            pos++
            return arr
        }
        throw Error("JSON: expected ',' or ']' at " . pos)
    }
}

_TrackJsonString(text, &pos) {
    if (SubStr(text, pos, 1) != '"')
        throw Error("JSON: expected string at " . pos)
    pos++
    out := ""
    while (pos <= StrLen(text)) {
        c := SubStr(text, pos, 1)
        if (c = '"') {
            pos++
            return out
        }
        if (c = "\") {
            pos++
            e := SubStr(text, pos, 1)
            switch e {
                case "n": out .= "`n"
                case "r": out .= "`r"
                case "t": out .= "`t"
                case "b": out .= Chr(8)
                case "f": out .= Chr(12)
                case "u":
                    hex := SubStr(text, pos + 1, 4)
                    out .= Chr(Integer("0x" . hex))
                    pos += 4
                default: out .= e
            }
            pos++
            continue
        }
        out .= c
        pos++
    }
    throw Error("JSON: unterminated string")
}

; ═══════════════════════════════════════════════════════════════════════════════
; CSV
; ═══════════════════════════════════════════════════════════════════════════════

TrackCsvCell(value) {
    s := String(value)
    if RegExMatch(s, '[",\r\n]')
        return '"' . StrReplace(s, '"', '""') . '"'
    return s
}

TrackCsvRow(cells) {
    parts := []
    for c in cells
        parts.Push(TrackCsvCell(c))
    return TrackArrayJoin(parts, ",")
}

; ═══════════════════════════════════════════════════════════════════════════════
; STRING / ARRAY HELPERS
; ═══════════════════════════════════════════════════════════════════════════════

TrackArrayJoin(arr, sep := ",") {
    out := ""
    for i, v in arr
        out .= (i > 1 ? sep : "") . v
    return out
}

TrackArrayHas(arr, value) {
    for v in arr {
        if (v = value)
            return true
    }
    return false
}

; Fast non-cryptographic hash (FNV-1a, 32-bit) rendered as 8 hex digits.
; Used to de-duplicate clipboard entries and image payloads cheaply.
TrackHash(str) {
    h := 2166136261
    Loop Parse, str {
        h := (h ^ Ord(A_LoopField)) & 0xFFFFFFFF
        h := (h * 16777619) & 0xFFFFFFFF
    }
    return Format("{:08x}", h)
}

; Truncate for display without breaking layout.
TrackEllipsis(str, maxLen) {
    str := StrReplace(StrReplace(String(str), "`r", " "), "`n", " ")
    if (StrLen(str) <= maxLen)
        return str
    return SubStr(str, 1, maxLen - 3) . "..."
}

; Filesystem-safe token derived from an arbitrary name.
TrackSafeName(name) {
    s := RegExReplace(String(name), "[^\w\-\.]+", "_")
    s := RegExReplace(s, "_{2,}", "_")
    s := Trim(s, "_")
    if (s = "")
        s := "unnamed"
    if (StrLen(s) > 80)
        s := SubStr(s, 1, 80)
    return s
}

; Clamp a number into a range.
TrackClamp(v, lo, hi) {
    if (v < lo)
        return lo
    if (v > hi)
        return hi
    return v
}

; ═══════════════════════════════════════════════════════════════════════════════
; BASE64
; ═══════════════════════════════════════════════════════════════════════════════
; Wraps CryptBinaryToString / CryptStringToBinary so snapshot images can be
; stored as text in the database and rebuilt on demand.

; Encode raw file bytes as a base64 string (no line breaks).
TrackBase64EncodeFile(path) {
    if !FileExist(path)
        return ""
    f := FileOpen(path, "r")
    if !f
        return ""
    size := f.Length
    buf := Buffer(size, 0)
    f.RawRead(buf, size)
    f.Close()
    return TrackBase64Encode(buf, size)
}

; Encode a Buffer of `size` bytes.
TrackBase64Encode(buf, size) {
    CRYPT_STRING_BASE64 := 0x1, CRYPT_STRING_NOCRLF := 0x40000000
    flags := CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", size
        , "UInt", flags, "Ptr", 0, "UInt*", &chars := 0)
        return ""
    out := Buffer(chars * 2, 0)
    if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf, "UInt", size
        , "UInt", flags, "Ptr", out, "UInt*", &chars)
        return ""
    return StrGet(out, chars, "UTF-16")
}

; Decode a base64 string back to a file on disk. Returns true on success.
TrackBase64DecodeToFile(b64, path) {
    CRYPT_STRING_BASE64 := 0x1
    if (b64 = "")
        return false
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0
        , "UInt", CRYPT_STRING_BASE64, "Ptr", 0, "UInt*", &size := 0
        , "Ptr", 0, "Ptr", 0)
        return false
    buf := Buffer(size, 0)
    if !DllCall("crypt32\CryptStringToBinaryW", "Str", b64, "UInt", 0
        , "UInt", CRYPT_STRING_BASE64, "Ptr", buf, "UInt*", &size
        , "Ptr", 0, "Ptr", 0)
        return false
    try {
        if FileExist(path)
            FileDelete(path)
        f := FileOpen(path, "w")
        f.RawWrite(buf, size)
        f.Close()
    } catch {
        return false
    }
    return true
}

; Standalone JSON codec shared with TrackUtil, isolated for generated agent scripts.
FanBridgeJsonJoin(values, separator := ",") {
    text := ""
    for index, value in values
        text .= (index > 1 ? separator : "") . value
    return text
}

FanBridgeJsonEscape(str) {
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

FanBridgeJsonEncode(value, indent := 0, level := 0) {
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
            parts.Push(padIn . '"' . FanBridgeJsonEscape(String(k)) . '":' . (indent > 0 ? " " : "")
                . FanBridgeJsonEncode(v, indent, level + 1))
        return "{" . nl . FanBridgeJsonJoin(parts, "," . nl) . nl . pad . "}"
    }

    if (value is Array) {
        if (value.Length = 0)
            return "[]"
        parts := []
        for v in value
            parts.Push(padIn . FanBridgeJsonEncode(v, indent, level + 1))
        return "[" . nl . FanBridgeJsonJoin(parts, "," . nl) . nl . pad . "]"
    }

    if (value is Integer || value is Float)
        return String(value)

    if (value == "")
        return '""'

    ; Numeric-looking strings stay strings so ids and codes round-trip intact.
    return '"' . FanBridgeJsonEscape(String(value)) . '"'
}

; Parse a JSON document into Maps / Arrays / strings / numbers.
; Throws on malformed input.
FanBridgeJsonDecode(text) {
    pos := 1
    val := _FanBridgeJsonValue(text, &pos)
    _FanBridgeJsonSkipWs(text, &pos)
    if (pos <= StrLen(text))
        throw Error("JSON: trailing content at " . pos)
    return val
}

_FanBridgeJsonSkipWs(text, &pos) {
    while (pos <= StrLen(text)) {
        c := SubStr(text, pos, 1)
        if (c = " " || c = "`t" || c = "`n" || c = "`r")
            pos++
        else
            break
    }
}

_FanBridgeJsonValue(text, &pos) {
    _FanBridgeJsonSkipWs(text, &pos)
    if (pos > StrLen(text))
        throw Error("JSON: unexpected end of input")
    c := SubStr(text, pos, 1)
    switch c {
        case "{": return _FanBridgeJsonObject(text, &pos)
        case "[": return _FanBridgeJsonArray(text, &pos)
        case '"': return _FanBridgeJsonString(text, &pos)
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
    if RegExMatch(SubStr(text, pos), "^-?\d+(\.\d+)?([eE][+-]?\d+)?", &m) {
        pos += StrLen(m[0])
        return InStr(m[0], ".") || InStr(m[0], "e") || InStr(m[0], "E") ? Float(m[0]) : Integer(m[0])
    }
    throw Error("JSON: unexpected character '" . c . "' at " . pos)
}

_FanBridgeJsonObject(text, &pos) {
    obj := Map()
    pos++  ; consume {
    _FanBridgeJsonSkipWs(text, &pos)
    if (SubStr(text, pos, 1) = "}") {
        pos++
        return obj
    }
    loop {
        _FanBridgeJsonSkipWs(text, &pos)
        key := _FanBridgeJsonString(text, &pos)
        _FanBridgeJsonSkipWs(text, &pos)
        if (SubStr(text, pos, 1) != ":")
            throw Error("JSON: expected ':' at " . pos)
        pos++
        obj[key] := _FanBridgeJsonValue(text, &pos)
        _FanBridgeJsonSkipWs(text, &pos)
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

_FanBridgeJsonArray(text, &pos) {
    arr := []
    pos++  ; consume [
    _FanBridgeJsonSkipWs(text, &pos)
    if (SubStr(text, pos, 1) = "]") {
        pos++
        return arr
    }
    loop {
        arr.Push(_FanBridgeJsonValue(text, &pos))
        _FanBridgeJsonSkipWs(text, &pos)
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

_FanBridgeJsonString(text, &pos) {
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



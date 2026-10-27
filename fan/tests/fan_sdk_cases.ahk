; Included by a process loading only FanBridgeClient and its standalone codec.
global failures := 0, passed := 0
Assert(test, label) {
    global failures, passed
    if test
        passed += 1
    else
        failures += 1
    FileAppend((test ? "PASS " : "FAIL ") . label . "`n", "*")
}
Throws(fn) {
    try fn.Call()
    catch
        return true
    return false
}
class FixtureBridge extends FanBridge {
    static Call(tool, args := 0, timeoutMs := 45000) => Map("tool", tool, "args", args, "timeout", timeoutMs)
}
try {
    input := Map("text", "café 漢字 💜`nquoted: " . Chr(34) . "hello" . Chr(34) . "\path",
        "code", "00123", "n", -4321, "fraction", .125, "nested", [Map("enabled", true), "last"])
    encoded := FanBridgeJsonEncode(input), decoded := FanBridgeJsonDecode(encoded)
    Assert(decoded["text"] = input["text"], "Standalone SDK JSON preserves Unicode, escapes and literal backslashes")
    Assert(Type(decoded["code"]) = "String" && decoded["code"] = "00123", "Standalone codec keeps numeric-looking strings distinct")
    Assert(decoded["n"] = -4321 && decoded["fraction"] = .125 && decoded["nested"][2] = "last", "Standalone codec preserves numbers and nested arrays/maps")
    Assert(FanBridgeJsonDecode('{"text":"\u00e9\u6f22\ud83d\udc9c"}')["text"] = "é漢💜", "Escaped UTF-16 surrogate pair decodes to the original Unicode string")
    Assert(InStr(FanBridgeJsonEncode(input, 2), "`n") && FanBridgeJsonDecode(FanBridgeJsonEncode(input, 2))["code"] = "00123", "Indented standalone JSON remains valid")
    Assert(Throws(() => FanBridgeJsonDecode('{"text":')), "Malformed JSON object rejected")
    Assert(Throws(() => FanBridgeJsonDecode('{} trailing')), "Trailing JSON content rejected")
    ocr := FixtureBridge.OCR(123)
    Assert(ocr["tool"] = "fan_ocr" && !ocr["args"].Has("region"), "SDK OCR default omits invalid empty region")
    pattern := FixtureBridge.FindPattern("Known", 123)
    Assert(pattern["tool"] = "fan_pattern_search" && !pattern["args"].Has("region"), "SDK pattern search default omits invalid empty region")
    crop := Map("x", -1200, "y", 30, "w", 80, "h", 45)
    Assert(FixtureBridge.OCR(123, crop)["args"]["region"]["x"] = -1200, "SDK forwards real crop with negative monitor coordinates")
    Assert(FixtureBridge.RunWorkflow("Known", 20)["timeout"] = 30000, "SDK workflow timeout includes response allowance")
} catch as err {
    Assert(false, "Uncaught SDK error " . err.Message . " line " . err.Line)
}
FileAppend("SDK RESULT " . passed . " passed, " . failures . " failed`n", "*")
ExitApp(failures ? 1 : 0)

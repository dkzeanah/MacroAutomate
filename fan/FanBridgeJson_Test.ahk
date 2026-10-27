#Requires AutoHotkey v2.0
#SingleInstance Off
#Include ..\lib\FanBridgeJson.ahk
failures := 0
Check(ok,label) {
    global failures
    failures += !ok
    FileAppend((ok ? "PASS " : "FAIL ") . label . "`n","*")
}
try {
    value := FanBridgeJsonDecode('{"name":"native viewer","empty":"","items":[1,-2,3.5,2e2,-1.25E-2],"bool":true,"no":false,"nil":null}')
    Check(value["name"]="native viewer" && value["empty"]="","plain and empty strings decode correctly")
    Check(value["items"][2]=-2 && value["items"][4]=200 && value["items"][5]=-0.0125,"numeric offsets, negatives and exponent values decode correctly")
    Check(value["bool"]=true && value["no"]=false && value["nil"]="","boolean and null values preserve existing semantics")
    value := FanBridgeJsonDecode('{"path":"C:\\Users\\Don","quoted":"say \"hello\"","line":"one\ntwo","unicode":"\u0041\u03b1"}')
    Check(value["path"]="C:\Users\Don" && value["quoted"]='say "hello"',"escaped paths and quotes retain the escape-aware parser")
    Check(value["line"]="one`ntwo" && value["unicode"]="Aα","escaped lines and Unicode decode correctly")
    value := Map("name","Native AHK","nested",[Map("x",2,"text","α → ✓"),"a\b"])
    roundTrip := FanBridgeJsonDecode(FanBridgeJsonEncode(value))
    Check(roundTrip["nested"][1]["text"]="α → ✓" && roundTrip["nested"][2]="a\b","nested source metadata round-trips correctly")
    if FileExist(A_ScriptDir . "\tests\runtime\registry-json-fixture.json") {
        text := FileRead(A_ScriptDir . "\tests\runtime\registry-json-fixture.json","UTF-8"), start := A_TickCount
        registry := FanBridgeJsonDecode(text), elapsed := A_TickCount-start
        Check(registry["rows"].Length>=50 && registry["total"]>=50,"real native tool inventory page decodes intact")
        Check(elapsed<5000,"native inventory decoding completes within five seconds (" . elapsed . " ms)")
    }
} catch as err
    Check(false,err.Message)
ExitApp(failures)

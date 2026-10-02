; ===============================================================================
; Core\_Gdip.ahk
; GDI+ screenshot core used by pattern capture
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================



; ═══════════════════════════════════════════════════════════════════════════════
; GDI+ SCREENSHOT FUNCTIONS
; ═══════════════════════════════════════════════════════════════════════════════
; GDI+ SCREENSHOT FUNCTIONS
; =============================================================================

ShutdownGdip(ExitReason, ExitCode) {
    global g_GdipToken
    if g_GdipToken
        Gdip_Shutdown(g_GdipToken)
    return 0
}

; Capture 100x100 region, save to screenshots folder
; If x,y provided, captures at those coords. Otherwise uses mouse position.
CapturePatternScreenshot(patternName, x := "", y := "") {
    global SCREENSHOTS_DIR

    ; If no coords provided, use mouse position
    if x = "" || y = "" {
        MouseGetPos(&x, &y)
    }

    ; 100x100 box centered on point
    regionX := x - 50
    regionY := y - 50
    regionW := 100
    regionH := 100

    ; Capture without cursor
    pBitmap := Gdip_BitmapFromScreen(regionX "|" regionY "|" regionW "|" regionH)

    if !pBitmap {
        ShowStatus("Screenshot capture failed", "fail")
        return ""
    }

    ; Clean filename (remove special chars)
    safeName := RegExReplace(patternName, "[^\w\-]", "_")
    fileName := safeName . ".png"
    savePath := SCREENSHOTS_DIR . "\" . fileName

    result := Gdip_SaveBitmapToFile(pBitmap, savePath)
    Gdip_DisposeImage(pBitmap)

    if result = 0 {
        ShowStatus("Screenshot saved: " . fileName, "ok")
        return savePath
    }

    ShowStatus("Screenshot save failed", "fail")
    return ""
}

; GDI+ Core Functions
Gdip_Startup() {
    if !DllCall("LoadLibrary", "str", "gdiplus", "UPtr")
        return 0
    si := Buffer(A_PtrSize = 8 ? 24 : 16, 0)
    NumPut("UInt", 1, si)
    DllCall("gdiplus\GdiplusStartup", "UPtr*", &pToken:=0, "UPtr", si.Ptr, "UPtr", 0)
    return pToken
}

Gdip_Shutdown(pToken) {
    DllCall("gdiplus\GdiplusShutdown", "UPtr", pToken)
    hModule := DllCall("GetModuleHandle", "str", "gdiplus", "UPtr")
    if hModule
        DllCall("FreeLibrary", "UPtr", hModule)
}

Gdip_BitmapFromScreen(Screen:=0, Raster:="") {
    hhdc := 0
    if (Screen = 0) {
        _x := DllCall("GetSystemMetrics", "Int", 76)
        _y := DllCall("GetSystemMetrics", "Int", 77)
        _w := DllCall("GetSystemMetrics", "Int", 78)
        _h := DllCall("GetSystemMetrics", "Int", 79)
    } else if IsInteger(Screen) {
        return 0  ; Monitor enum not implemented here
    } else {
        S := StrSplit(Screen, "|")
        _x := S[1], _y := S[2], _w := S[3], _h := S[4]
    }

    if (_x = "") || (_y = "") || (_w = "") || (_h = "")
        return 0

    chdc := CreateCompatibleDC()
    hbm := CreateDIBSection(_w, _h, chdc)
    obm := SelectObject(chdc, hbm)
    hhdc := GetDC()
    BitBlt(chdc, 0, 0, _w, _h, hhdc, _x, _y, Raster)
    ReleaseDC(hhdc)
    pBitmap := Gdip_CreateBitmapFromHBITMAP(hbm)
    SelectObject(chdc, obm)
    DeleteObject(hbm)
    DeleteDC(chdc)
    return pBitmap
}

Gdip_SaveBitmapToFile(pBitmap, sOutput, Quality:=75) {
    SplitPath(sOutput,,, &extension)
    if !RegExMatch(extension, "^(?i:BMP|DIB|RLE|JPG|JPEG|JPE|JFIF|GIF|TIF|TIFF|PNG)$")
        return -1
    extension := "." . extension
    DllCall("gdiplus\GdipGetImageEncodersSize", "uint*", &nCount:=0, "uint*", &nSize:=0)
    ci := Buffer(nSize)
    DllCall("gdiplus\GdipGetImageEncoders", "UInt", nCount, "UInt", nSize, "UPtr", ci.Ptr)
    if !(nCount && nSize)
        return -2
    pCodec := 0
    loop nCount {
        address := NumGet(ci, (idx := (48+7*A_PtrSize)*(A_Index-1))+32+3*A_PtrSize, "UPtr")
        sString := StrGet(address, "UTF-16")
        if !InStr(sString, "*" . extension)
            continue
        pCodec := ci.Ptr+idx
        break
    }
    if !pCodec
        return -3
    _p := 0
        if RegExMatch(extension, "^\.(?i:JPG|JPEG|JPE|JFIF)$") {
            DllCall("gdiplus\GdipGetEncoderParameterListSize", "UPtr", pBitmap, "UPtr", pCodec, "uint*", &nSize)
            EncoderParameters := Buffer(nSize, 0)
            DllCall("gdiplus\GdipGetEncoderParameterList", "UPtr", pBitmap, "UPtr", pCodec, "UInt", nSize, "UPtr", EncoderParameters.Ptr)
            nCount := NumGet(EncoderParameters, "UInt")
            loop nCount {
                elem := (24+(A_PtrSize ? A_PtrSize : 4))*(A_Index-1) + 4 + (pad := A_PtrSize = 8 ? 4 : 0)
                if (NumGet(EncoderParameters, elem+16, "UInt") = 1) && (NumGet(EncoderParameters, elem+20, "UInt") = 6) {
                    _p := elem + EncoderParameters.Ptr - pad - 4
                    NumPut("UInt", Quality, NumGet(NumPut("UInt", 4, NumPut("UInt", 1, _p+0)+20), "UInt"))
                    break
                }
            }
        }

    return DllCall("gdiplus\GdipSaveImageToFile", "UPtr", pBitmap, "UPtr", StrPtr(sOutput), "UPtr", pCodec, "UInt", _p ? _p : 0) ? -5 : 0
}

Gdip_CreateBitmapFromHBITMAP(hBitmap, Palette:=0) {
    DllCall("gdiplus\GdipCreateBitmapFromHBITMAP", "UPtr", hBitmap, "UPtr", Palette, "UPtr*", &pBitmap:=0)
    return pBitmap
}

Gdip_DisposeImage(pBitmap) {
    return DllCall("gdiplus\GdipDisposeImage", "UPtr", pBitmap)
}

CreateDIBSection(w, h, hdc:="", bpp:=32, &ppvBits:=0) {
    hdc2 := hdc ? hdc : GetDC()
    bi := Buffer(40, 0)
    NumPut("UInt", 40, "UInt", w, "UInt", h, "ushort", 1, "ushort", bpp, "UInt", 0, bi)
    bits := 0
    hbm := DllCall("CreateDIBSection", "UPtr", hdc2, "UPtr", bi.Ptr, "UInt", 0, "UPtr*", &bits, "UPtr", 0, "UInt", 0, "UPtr")
    ppvBits := bits   ; a ByRef parameter cannot be passed to DllCall as &param
    if !hdc
        ReleaseDC(hdc2)
    return hbm
}

CreateCompatibleDC(hdc:=0) {
    return DllCall("CreateCompatibleDC", "UPtr", hdc)
}

SelectObject(hdc, hgdiobj) {
    return DllCall("SelectObject", "UPtr", hdc, "UPtr", hgdiobj)
}

DeleteObject(hObject) {
    return DllCall("DeleteObject", "UPtr", hObject)
}

GetDC(hwnd:=0) {
    return DllCall("GetDC", "UPtr", hwnd)
}

ReleaseDC(hdc, hwnd:=0) {
    return DllCall("ReleaseDC", "UPtr", hwnd, "UPtr", hdc)
}

DeleteDC(hdc) {
    return DllCall("DeleteDC", "UPtr", hdc)
}

BitBlt(ddc, dx, dy, dw, dh, sdc, sx, sy, Raster:="") {
    return DllCall("gdi32\BitBlt", "UPtr", ddc, "Int", dx, "Int", dy, "Int", dw, "Int", dh, "UPtr", sdc, "Int", sx, "Int", sy, "UInt", Raster ? Raster : 0x00CC0020)
}


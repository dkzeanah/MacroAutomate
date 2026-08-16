;===============================================================================
;  FindText_Macro.ahk  -  AutoHotkey v2
;------------------------------------------------------------------------------
;  A practical macro template built on the FindText library (v8.9).
;
;  Requirements:
;    - AutoHotkey v2.0 or newer  (FindText requires AHK v2.0 beta 7+)
;    - FindText.ahk in the SAME folder as this script
;
;  Quick start:
;    1. Run this script -> the instruction GUI appears.
;    2. Press F2 (or click Capture) and select any area on screen
;       with the mouse (right-click twice, see capture tooltip).
;    3. Press F3 (or click Find & Click) to search the whole screen
;       for that image and click its center.
;    4. Press F4 to show/hide this window.
;
;  The captured image-code is saved to FindText_Macro.ini next to
;  this script, so it survives restarts.
;===============================================================================

#Requires AutoHotkey v2.0
#SingleInstance Force

; If FindText.ahk is in the AHK "Lib" folder, use:  #Include <FindText>
#Include FindText.ahk

;-------------------------------------------------------------------------------
; Globals
;-------------------------------------------------------------------------------
global CapturedText := ""
global GuiShown := true
CaptureIni := A_ScriptDir "\FindText_Macro.ini"

;-------------------------------------------------------------------------------
; Main GUI with built-in instructions
;-------------------------------------------------------------------------------
MainGui := Gui("+AlwaysOnTop", "FindText Macro — Instructions & Control")
MainGui.SetFont("s10", "Segoe UI")

; ---- Instructions group ----
MainGui.Add("GroupBox", "xm w500 h300", "Built-in Instructions")
Instructions := "
(
1. CAPTURE  — Press F2 or click [Capture Image]
   • Right-click ONCE  -> fixes the top-left corner of the box
   • Move the mouse    -> sizes the box (arrow keys fine-tune)
   • Right-click again -> capture is finished
   The selected area is converted into FindText image-code and
   saved to FindText_Macro.ini automatically (restored on start).

2. FIND & CLICK — Press F3 or click [Find & Click]
   Searches the whole screen for the captured image and clicks
   the center of the match. [Find Only] just highlights it.

3. ADVANCED — [Open FindText GUI] starts the full library GUI
   (gray/color modes, multi-color, OCR, fine-tuning...). Copy the
   code it generates, paste it into the box below, [Save Text].

4. TIP — join several images in one search with  |  between codes,
   e.g.  |<>*123$41.xxxx|<>*123$29.yyyy
)"
MainGui.Add("Text", "xm+15 yp+25 w470 h265", Instructions)

; ---- Captured text group ----
MainGui.Add("GroupBox", "xm w500 h210", "Captured Image Text (FindText code)")
EditBox := MainGui.Add("Edit", "xm+15 yp+25 w470 h170 -Wrap", "")

; ---- Buttons ----
MainGui.Add("Button", "xm w160", "Capture Image (F2)").OnEvent("Click", DoCapture)
MainGui.Add("Button", "x+10 w160", "Find & Click (F3)").OnEvent("Click", DoFindAndClick)
MainGui.Add("Button", "x+10 w160", "Find Only").OnEvent("Click", DoFindOnly)
MainGui.Add("Button", "xm w160", "Save Text").OnEvent("Click", DoSaveText)
MainGui.Add("Button", "x+10 w160", "Copy Text").OnEvent("Click", DoCopyText)
MainGui.Add("Button", "x+10 w160", "Clear Text").OnEvent("Click", DoClearText)
MainGui.Add("Button", "xm w160", "Open FindText GUI").OnEvent("Click", OpenFindTextGui)

; ---- Status + hotkey hints ----
Status := MainGui.Add("Text", "xm w500", "Ready — press F2 to capture your first image.")
MainGui.Add("Text", "xm w500 cGray", "Hotkeys:  F2 = Capture     F3 = Find & Click     F4 = Show/Hide this window")

MainGui.OnEvent("Close", (*) => MainGui.Hide())
MainGui.Show()

; Restore last captured text
Try
    CapturedText := IniRead(CaptureIni, "FindText", "Text", "")
Catch
    CapturedText := ""
EditBox.Value := CapturedText
Status.Text := CapturedText != "" ? "Saved image-code loaded. Press F3 to find & click it."
    : "Ready — press F2 to capture your first image."

;-------------------------------------------------------------------------------
; Hotkeys
;-------------------------------------------------------------------------------
F2:: DoCapture()
F3:: DoFindAndClick()
F4:: ToggleGui()

;-------------------------------------------------------------------------------
; Tray menu
;-------------------------------------------------------------------------------
A_TrayMenu.Add("Show GUI", ToggleGui)
A_TrayMenu.Add("Exit", (*) => ExitApp())

;-------------------------------------------------------------------------------
; Functions
;-------------------------------------------------------------------------------

; F2: capture any screen area -> store as FindText image-code
DoCapture(*) {
    global CapturedText
    MainGui.Hide()                    ; hide our GUI so it can't block the capture
    Sleep(150)
    rect := FindText().Gui("Capture") ; right-click twice -> returns [x1, y1, x2, y2]
    MainGui.Show()
    if !IsObject(rect) || rect.Length < 4 {
        Status.Text := "Capture cancelled or failed."
        return
    }
    x1 := rect[1], y1 := rect[2], x2 := rect[3], y2 := rect[4]
    Text := FindText().GetTextFromScreen(x1, y1, x2, y2) ; convert region to code
    if Text = "" {
        Status.Text := "Capture failed — could not generate image-code for the selected area."
        return
    }
    CapturedText := Text
    EditBox.Value := Text
    Try
        IniWrite(CapturedText, CaptureIni, "FindText", "Text")
    w := Abs(x2 - x1) + 1, h := Abs(y2 - y1) + 1
    Status.Text := "Captured " w "x" h " px at (" x1 "," y1 ").  Press F3 to find & click it."
}

; F3: find the captured image and click its center
DoFindAndClick(*) => FindImage(true)

; Button: find only, highlight without clicking
DoFindOnly(*) => FindImage(false)

FindImage(clickIt) {
    global CapturedText
    if CapturedText = "" {
        Status.Text := "Nothing captured yet — press F2 first."
        return
    }
    ; search the full screen with 10% fault tolerance
    ok := FindText(&fx, &fy, 0, 0, 0, 0, 0.1, 0.1, CapturedText)
    if ok.Length {
        v := ok[1]
        FindText().RangeTip(v.x, v.y, v.w, v.h, "Red")      ; highlight match
        SetTimer((*) => FindText().RangeTip(), -1500)       ; clear after 1.5s
        id := v.id != "" ? "  [" v.id "]" : ""
        if clickIt {
            FindText().Click(v.mx, v.my)                    ; click center
            Status.Text := "Found (" v.mx "," v.my ") and clicked." id
        } else
            Status.Text := "Found (" v.mx "," v.my "), highlighted." id
    } else
        Status.Text := "Image NOT found on screen. Try re-capturing with F2 (or lower tolerance in the code)."
}

; Save whatever is in the edit box (e.g. pasted from the FindText GUI)
DoSaveText(*) {
    global CapturedText
    CapturedText := EditBox.Value
    if CapturedText = "" {
        Status.Text := "The text box is empty — nothing saved."
        return
    }
    Try
        IniWrite(CapturedText, CaptureIni, "FindText", "Text")
    Status.Text := "Image-code saved (" StrLen(CapturedText) " chars).  Press F3 to find & click it."
}

DoCopyText(*) {
    global CapturedText
    if CapturedText = "" {
        Status.Text := "Nothing to copy yet."
        return
    }
    A_Clipboard := CapturedText
    Status.Text := "Image-code copied to clipboard (" StrLen(CapturedText) " chars)."
}

DoClearText(*) {
    global CapturedText
    CapturedText := ""
    EditBox.Value := ""
    Try
        IniDelete(CaptureIni, "FindText", "Text")
    Status.Text := "Captured image-code cleared."
}

; Show the library's own full-featured GUI (advanced captures)
OpenFindTextGui(*) {
    FindText().Gui("Show")
}

ToggleGui(*) {
    global GuiShown
    if GuiShown {
        MainGui.Hide()
        GuiShown := false
    } else {
        MainGui.Show()
        GuiShown := true
    }
}
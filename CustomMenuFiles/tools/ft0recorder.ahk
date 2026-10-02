#Requires AutoHotkey v2.0
#SingleInstance Force
#Include FindText.ahk

class PatternRecorder {
    __New() {
        this.patterns := Map()
        this.gui := Gui("+Resize", "FindText Recorder")

        this.gui.Add("Text",, "Pattern Name:")
        this.nameEdit := this.gui.Add("Edit", "w200")

        this.captureBtn := this.gui.Add("Button", "w200", "Capture Region")
        this.captureBtn.OnEvent("Click", (*) => this.StartCapture())

        this.testBtn := this.gui.Add("Button", "w200", "Test Pattern")
        this.testBtn.OnEvent("Click", (*) => this.TestPattern())

        this.output := this.gui.Add("Edit", "w400 h200 ReadOnly")

        this.gui.Show()
    }

    StartCapture() {
        this.gui.Hide()
        MsgBox "Drag to select region..."

        CoordMode "Mouse", "Screen"
        MouseGetPos &x1, &y1

        KeyWait "LButton", "D"
        MouseGetPos &x2, &y2
        KeyWait "LButton"

        this.gui.Show()

        ; Capture region
        pattern := FindText().Pic(x1, y1, x2, y2)

        name := this.nameEdit.Value
        if (name = "") {
            MsgBox "Enter pattern name"
            return
        }

        this.patterns[name] := pattern
        this.output.Value := pattern
    }

    TestPattern() {
        name := this.nameEdit.Value
        if !this.patterns.Has(name) {
            MsgBox "Pattern not found"
            return
        }

        pat := this.patterns[name]

        if (ok := FindText(&x, &y, 0, 0, A_ScreenWidth, A_ScreenHeight, 0, 0, pat)) {
            MouseMove x, y
            MsgBox "FOUND at " x "," y
        } else {
            MsgBox "NOT FOUND"
        }
    }
}

PatternRecorder()
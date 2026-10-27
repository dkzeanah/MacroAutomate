; Follow appended stream content without moving keyboard focus.
DeepBridge_Pane(control, value) {
    value := StudyConsole_Redact(value)
    if StrReplace(control.Value, "`r", "") = StrReplace(value, "`r", "")
        return
    control.Value := value
    ; EM_SETSEL(-1,-1) removes a selection and leaves WM_SETTEXT's caret at
    ; the beginning. Use the actual UTF-16 text length to place it at EOF.
    length := SendMessage(0x000E, 0, 0, control)
    SendMessage(0x00B1, length, length, control)
    SendMessage(0x00B7, 0, 0, control)
    SendMessage(0x0115, 7, 0, control) ; WM_VSCROLL / SB_BOTTOM.
}

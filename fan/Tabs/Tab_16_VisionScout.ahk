; ===============================================================================
; Tabs\Tab_16_VisionScout.ahk
; TAB 16 Vision Scout: tab glue (UI from lib\VisionScout.ahk)
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_VisionScout_Build() {
    try VisionScout_Init()
    catch as err
        LogErrorToFile(err, "caught", "Vision Scout subsystem initialization")
    ; Legacy page 16 is redirected to the real combined Learning workspace.
    ; The visual engine remains independent; its separate builder is retained
    ; as a library API for other entry points, not mounted as another view here.
}


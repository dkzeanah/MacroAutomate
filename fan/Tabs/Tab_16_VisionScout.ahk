; ===============================================================================
; Tabs\Tab_16_VisionScout.ahk
; TAB 16 Vision Scout: tab glue (UI from lib\VisionScout.ahk)
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_VisionScout_Build() {
    TabCtrl.UseTab(16)
    try VisionScout_Init()
    catch as err
        LogErrorToFile(err, "caught", "Vision Scout subsystem initialization")
    try VisionScout_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Vision Scout tab construction")
}


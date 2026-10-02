; ===============================================================================
; Tabs\Tab_14_AppLearner.ahk
; TAB 14 App Learner: tab glue (UI from lib\AppLearner.ahk)
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_AppLearner_Build() {
    TabCtrl.UseTab(14)
    try AppLearner_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "App Learner tab construction")
}


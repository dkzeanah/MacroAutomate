; ===============================================================================
; Tabs\Tab_15_SnapshotRecovery.ahk
; TAB 15 Snapshot Recovery: tab glue (UI from lib\SnapshotRecovery.ahk)
; Extracted from macroautomaterv9-deepseek.ahk - not a standalone script:
; it is #Include'd by MacroAutomator.ahk. See SPLIT_MANIFEST.md for ranges.
; ===============================================================================

Tab_SnapshotRecovery_Build() {
    TabCtrl.UseTab(15)
    try SnapRec_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Snapshot Recovery tab construction")
}


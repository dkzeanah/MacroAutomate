; ===============================================================================
; Tabs\Tab_18_StudyAssistant.ahk
; TAB 18 Study Assistant: tab glue (UI from lib\StudyAssistant.ahk)
; Study-only build of fan\REALTIME_STUDY_ASSISTANT_SPEC.md: ingest material,
; build concept memory, answer captured questions from local evidence (DeepSeek
; only as a fallback), verify and "learn once", and export study material.
; It never drives the mouse/keyboard or enters answers anywhere.
; ===============================================================================

Tab_StudyAssistant_Build() {
    global g_StudyTabIndex
    g_StudyTabIndex := 18
    TabCtrl.UseTab(g_StudyTabIndex)
    try Study_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Study Assistant tab construction")
}

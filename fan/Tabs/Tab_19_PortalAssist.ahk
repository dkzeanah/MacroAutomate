; ===============================================================================
; Tabs\Tab_19_PortalAssist.ahk
; TAB 19 Live Portal: tab glue for the real-time automation half of the
; study assistant (lib\StudyLive.ahk - session pinning, perception, the live
; answer bridge and the self-composed human-paced entry engine).
; ===============================================================================

Tab_PortalAssist_Build() {
    TabCtrl.UseTab(19)
    try StudyLive_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "Live Portal tab construction")
}

; ===============================================================================
; Tabs\Tab_17_UsagePredictor.ahk
; TAB 17 Usage Predictor: tab glue (UI from lib\UsagePatternPredictor.ahk)
; Added while merging the ChatGPT and DeepSeek v9 branches. The learner remains
; independent from Vision Scout so both models and review workflows are kept.
; ===============================================================================

Tab_UsagePredictor_Build() {
    global g_UPTabIndex
    g_UPTabIndex := 14
    try UsagePredictor_ApplySchema()
    catch as err
        LogErrorToFile(err, "caught", "Usage Predictor tab construction")
}

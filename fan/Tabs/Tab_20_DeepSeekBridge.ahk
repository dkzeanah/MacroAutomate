Tab_DeepSeekBridge_Build() {
    TabCtrl.UseTab(20)
    try DeepBridge_BuildTab(MainGui)
    catch as err
        LogErrorToFile(err, "caught", "DeepSeek Bridge tab construction")
}

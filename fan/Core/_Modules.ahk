; Entry lifecycle: modules. Included by MacroAutomator.ahk.
; ===============================================================================
; CORE FUNCTION LIBRARIES (definitions only - order-independent in AHK v2)
; ===============================================================================
#Include %A_ScriptDir%\Core\_Helpers.ahk
#Include %A_ScriptDir%\Core\_Db.ahk
#Include %A_ScriptDir%\Core\_Notifications.ahk
#Include %A_ScriptDir%\Core\_Gdip.ahk
#Include %A_ScriptDir%\Actions\_Engine.ahk
#Include %A_ScriptDir%\Core\_Navigation.ahk

; ===============================================================================
; TAB FILES (GUI builders + event handlers, one file per tab)
; ===============================================================================
#Include %A_ScriptDir%\Tabs\Tab_01_Workflow.ahk
#Include %A_ScriptDir%\Tabs\Tab_01_Workflow_Forms.ahk
#Include %A_ScriptDir%\Tabs\Tab_02_Patterns.ahk
#Include %A_ScriptDir%\Tabs\Tab_03_LiveOCR.ahk
#Include %A_ScriptDir%\Tabs\Tab_04_Spools.ahk
#Include %A_ScriptDir%\Tabs\Tab_05_Analytics.ahk
#Include %A_ScriptDir%\Tabs\Tab_06_Clipboard.ahk
#Include %A_ScriptDir%\Tabs\Tab_07_Hotkeys.ahk
#Include %A_ScriptDir%\Tabs\Tab_08_Hotstrings.ahk
#Include %A_ScriptDir%\Tabs\Tab_09_Triggers.ahk
#Include %A_ScriptDir%\Tabs\Tab_10_Settings.ahk
#Include %A_ScriptDir%\Tabs\Tab_11_Notepad.ahk
#Include %A_ScriptDir%\Tabs\Tab_12_Calendar.ahk
#Include %A_ScriptDir%\Tabs\Tab_13_Tracking.ahk
#Include %A_ScriptDir%\Tabs\Tab_14_AppLearner.ahk
#Include %A_ScriptDir%\Tabs\Tab_15_SnapshotRecovery.ahk
#Include %A_ScriptDir%\Tabs\Tab_16_VisionScout.ahk
#Include %A_ScriptDir%\Tabs\Tab_17_UsagePredictor.ahk
#Include %A_ScriptDir%\Tabs\Tab_18_StudyAssistant.ahk
#Include %A_ScriptDir%\Tabs\Tab_19_PortalAssist.ahk
#Include %A_ScriptDir%\Tabs\Tab_20_DeepSeekBridge.ahk
#Include %A_ScriptDir%\Tabs\Tab_21_MediaIntel.ahk
#Include %A_ScriptDir%\Tabs\Tab_22_Knowledge.ahk
#Include %A_ScriptDir%\Tabs\Tab_23_Scribe.ahk
#Include %A_ScriptDir%\..\lib\FanHarness.ahk
#Include %A_ScriptDir%\..\lib\LearningProcedure.ahk
#Include %A_ScriptDir%\..\lib\LearningHub.ahk
#Include %A_ScriptDir%\..\lib\ChromeProfiles.ahk
#Include %A_ScriptDir%\..\lib\ChromeLearning.ahk


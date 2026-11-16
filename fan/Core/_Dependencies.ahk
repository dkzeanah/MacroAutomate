; Entry lifecycle: dependencies. Included by MacroAutomator.ahk.
; ═══════════════════════════════════════════════════════════════════════════════
; EXTERNAL LIBRARY INCLUDES
; ═══════════════════════════════════════════════════════════════════════════════
; FindText.ahk: Visual pattern recognition for UI element detection
; OCR.ahk: Optical Character Recognition for text extraction from screen
; ═══════════════════════════════════════════════════════════════════════════════

#Include %A_ScriptDir%\..\FindText.ahk
#Include %A_ScriptDir%\..\OCR.ahk  ; Windows.Media.Ocr wrapper used by all OCR actions
#Include %A_ScriptDir%\..\SQLiteDB.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; TRACKING SUBSYSTEM (window time / mouse / keys / snapshots / elements / research)
; ═══════════════════════════════════════════════════════════════════════════════
; Order matters: utilities and the DB layer first, then the trackers that use
; them, then the UI/automation modules that use the trackers.
;
; NOTE: lib\TrackSQLite.ahk is the tracking subsystem's own SQLite wrapper. It is
; deliberately NOT named SQLiteDB - that class name already belongs to the
; SQLiteDB.ahk included above, which this script's g_DB uses. Two classes with
; the same name in one script is a load-time error, so the tracking store keeps
; its own connection under its own name.
#Include %A_ScriptDir%\..\lib\TrackSQLite.ahk
#Include %A_ScriptDir%\..\lib\TrackUtil.ahk
#Include %A_ScriptDir%\..\lib\TrackingDB.ahk
#Include %A_ScriptDir%\..\lib\PhotoStore.ahk
#Include %A_ScriptDir%\..\lib\LearningValidation.ahk
#Include %A_ScriptDir%\..\lib\PixelCanvas.ahk
#Include %A_ScriptDir%\..\lib\WindowTracker.ahk
#Include %A_ScriptDir%\..\lib\MouseTracker.ahk
#Include %A_ScriptDir%\..\lib\KeyTracker.ahk
#Include %A_ScriptDir%\..\lib\SnapshotEngine.ahk
#Include %A_ScriptDir%\..\lib\ElementAutomation.ahk
#Include %A_ScriptDir%\..\lib\ElementViewer.ahk
#Include %A_ScriptDir%\..\lib\ResearchPipeline.ahk
#Include %A_ScriptDir%\..\lib\TrackingDashboard.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; APP LEARNER (v8): learn whole program interfaces into an object model, drive
; them from a text DSL or a local LLM (Ollama). Acc.ahk supplies the MSAA
; accessibility tree the learner walks.
; ═══════════════════════════════════════════════════════════════════════════════
#Include %A_ScriptDir%\..\lib\Acc.ahk
#Include %A_ScriptDir%\..\lib\AppLearner.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; VISION SCOUT (v9): self-learning visual scraper + usage sequencer. Segments the
; screen into elements (FindText patterns), tracks clicks/typing/window switches,
; promotes frequently-used elements, and offers to auto-complete repeated
; sequences (Win+CapsLock). See lib\VisionScout.ahk.
; ═══════════════════════════════════════════════════════════════════════════════
#Include %A_ScriptDir%\..\lib\VisionScout.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; SNAPSHOT RECOVERY (v8): trace a snapshot back to the page it came from -
; live URL capture, filename clue extraction, Chrome history cross-reference,
; searched with Everything 1.5 query syntax.
; ═══════════════════════════════════════════════════════════════════════════════
#Include %A_ScriptDir%\..\lib\Everything3Client.ahk
#Include %A_ScriptDir%\..\lib\SnapshotRecovery.ahk
; Attention/prominence measurement: which windows actually held focus,
; watch time for media, and the learned adult-content filter.
#Include %A_ScriptDir%\..\lib\AttentionEngine.ahk
; Repeatable region snips with OCR and a correction memory (Ctrl+Shift+1/2/3).
#Include %A_ScriptDir%\..\lib\SnipStudio.ahk
; Smart parsing of a capture into individual questions, plus the review
; roulette that resurfaces the ones still unanswered.
#Include %A_ScriptDir%\..\lib\SnipParse.ahk
; Semantic layout: cluster a learned app's elements into panes and name them
; (sidebar, editor, status bar) so automation can address regions, not pixels.
#Include %A_ScriptDir%\..\lib\WindowModel.ahk
; Generic reflow for the tabs that were laid out with absolute coordinates.
#Include %A_ScriptDir%\..\lib\AutoFlow.ahk
; Independent local visual learner from the ChatGPT v9 branch. It complements
; Vision Scout with coarse full-desktop scanning and n-gram continuations.
#Include %A_ScriptDir%\..\lib\UsagePatternPredictor.ahk

; ═══════════════════════════════════════════════════════════════════════════════
; STUDY ASSISTANT (REALTIME_STUDY_ASSISTANT_SPEC.md): ingest
; lesson plans/PDFs/notes, build a searchable concept memory, answer captured
; questions from local evidence (DeepSeek only as a fallback), verify + "learn
; once", and export study material. The live controller and workflow lab below
; turn captured controls into guarded mouse/keyboard actions. StudyDB extends
; the SnipParse question bank, so it loads after the tracking stack above.
#Include %A_ScriptDir%\..\lib\StudyDB.ahk
#Include %A_ScriptDir%\..\lib\StudyConsole.ahk
#Include %A_ScriptDir%\..\lib\StudyLLM.ahk
#Include %A_ScriptDir%\..\lib\StudyIngest.ahk
#Include %A_ScriptDir%\..\lib\StudyAssistant.ahk
; ── Live portal half (automation): session pinning + focus guard, Acc/OCR/vision
; perception, self-composed human-paced answer entry, and the session
; orchestrator that bridges the study layer above. Loads after it so the
; knowledge layer's engine and persistence are available.
#Include %A_ScriptDir%\..\lib\StudyAutomation.ahk
#Include %A_ScriptDir%\..\lib\StudyPortal.ahk
#Include %A_ScriptDir%\..\lib\StudyComposer.ahk
#Include %A_ScriptDir%\..\lib\StudyLive.ahk
#Include %A_ScriptDir%\..\lib\StudyTools.ahk
#Include %A_ScriptDir%\..\lib\StudyMath.ahk
#Include %A_ScriptDir%\..\lib\StudyDemo.ahk
; ── Media intelligence: programmatic video/media processing (ffmpeg frame
; sampling -> DeepSeek Flash vision -> timeline/JSON + derived media: contact
; sheets, clips, chapters) and the OCR "feature map" environment-intelligence
; mapper (screen/window/image -> machine-readable regions). Reuses the StudyLLM
; DeepSeek provider and the shared cost cap.
#Include %A_ScriptDir%\..\lib\MediaLLM.ahk
#Include %A_ScriptDir%\..\lib\MediaPipeline.ahk
#Include %A_ScriptDir%\..\lib\EnvIntel.ahk
; Bridge to the avideditor ("Cutline") Python video engine (OpenCV shot/cut
; analysis via its own venv). The /fan ffmpeg path stays as a fallback.
#Include %A_ScriptDir%\..\lib\MediaBridge.ahk
; Typed-question capture: a "?" you type grabs the sentence before it as a clean
; question (the main, non-OCR mechanism). Hooks the KeyTracker InputHook.
#Include %A_ScriptDir%\..\lib\QuestionCapture.ahk
; Live accumulated-knowledge dashboard (reads the one unified DB) + on-screen
; playback; also persists EnvIntel feature maps so they accumulate.
#Include %A_ScriptDir%\..\lib\KnowledgeDash.ahk
; Workflow Scribe: visual capture of element interactions as frame "playbacks",
; with DeepSeek reasoning and cross-window chains. Ctrl+Shift+R toggles recording.
#Include %A_ScriptDir%\..\lib\Scribe.ahk
#Include %A_ScriptDir%\..\lib\DeepSeekActivity.ahk
#Include %A_ScriptDir%\..\lib\DeepSeekBridge.ahk
#Include %A_ScriptDir%\..\lib\FanDataMaintenance.ahk
#Include %A_ScriptDir%\..\lib\FanUnified.ahk
FanData_RecoveryBootstrap()
FanUnified_Bootstrap()
#Include %A_ScriptDir%\..\lib\FanBridgeVision.ahk
#Include %A_ScriptDir%\..\lib\FanBridgeAPI.ahk

; (kept from the original file, which includes FindText twice)
#Include %A_ScriptDir%\..\FindText.ahk


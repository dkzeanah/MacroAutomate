# Live Bridge demonstration — 2026-10-18

Task `bc70b6825b044a00af1932f783cf77c2` completed through Macro Automator's normal Bridge send path after 35 model rounds. The retained thinking and activity can be reopened from request history. This planning tour made model requests; subsequent exact stored-tool execution did not generate new source.

## Observed results

- Claim 38's evidence-based lesson opened. Its saved three-step rehearsal ran twice. Historical source is `usage_transition:1086`, evidence 65, with eight continuations and zero accepted original-app automations. Fixture success does not validate Triangle Infill 3-D behavior or identify the controls' semantic purpose.
- The agent updated `LearningTourDemo.ahk`, corrected a variable/function name collision, then corrected its second-run instance dialog by declaring `#SingleInstance Off`. Final revision: **5**. It demonstrated GUI sums 20 and 555. These two initial successes span revisions 4 and 5; they alone do not prove unchanged-source reuse.
- A separate direct stored-tool run then reused **revision 5** with `number1=21`, `number2=21`, `self_test=true`. Real output asserted **42**, and the revision/hash remained unchanged. Run ID: `06b36d90190240d5aa94815a5b52106d`. SHA-256: `d204607ed1b4842e19cd628be669d14b279b0e5bebd64b8c69bba0cf8a8c53c1`. No model was called for that direct execution.
- The original agent saved and previewed `LearningTour_StoredProcedure`, but did not execute it because two demo windows shared a title. Its activation parameter also mistakenly included the UI field label. The final check used a uniquely observed demo window and corrected the parameter to the actual title.
- The corrected saved native workflow completed **2 steps**: activate the demo; resolve and click its retained Calculate pattern. A fresh GUI inspection showed a new `Calculated: 21 + 21 = 42` log entry after the prior self-test ended. This supplies an observed effect beyond the engine's completed-step counter.
- A consolidated learning report was initially absent. The existing bounded local analyzer generated it; the agent subsequently read it successfully.
- Atlas opened as a separate Python application. The exact DomeSim code slice and call edges were retrieved.
- The local Chrome harness at `http://127.0.0.1:3080` returned HTTP 200. The VS Code/Chrome project-building request is supplied as a prompt; it was not performed as part of this fixture tour.

## Actual AHK tooling

| Source | Owner | Role |
|---|---|---|
| `fan/DeepSeekBridge/agent_scripts/LearningTourDemo.ahk` | DeepSeek agent; existing tool updated to r5 | Parameterized owned GUI, Calculate/Reset handlers, logged self-test; takes `lesson_title`, `number1`, `number2`, `self_test` |
| `lib/FanBridgeClient.ahk`, `lib/FanBridgeJson.ahk` | Existing shared SDK | Reused real API/JSON signatures; credentials remain outside source |
| `lib/DeepSeekPane.ahk` | Program fix | Keeps streaming panes at the actual UTF-16 end without taking focus |
| `lib/WorkflowPatterns.ahk` | Program fix; extracted existing functions | Unattended native pattern clicks search the active window, reject ambiguity/context/geometry changes, show feedback and recheck coverage |

**Saved tools / API → Written .ahk files** lists all actual script-library filenames, revisions and paths, and distinguishes database-only source from materialized local files. Select a record to inspect its source and metadata. Other pre-existing scripts in that list were not authored or executed by this tour.

The original agent's broad empirical-memory query returned no matches. An exact `LearningTourDemo.ahk` query did return revision-specific validation, execution and failure records. An empty query result is not proof that all memory is absent. Existing process/status evidence is kept separate from parser proofs and GUI outcome evidence.

## Fixes and verification

- Thinking/output/activity panes now select the actual text end and scroll to the bottom. Five native stream checks passed, including Unicode, append behavior and preserved focus.
- Native FindText clicking previously used a global first match and inherited its coordinate mode. The shared implementation now explicitly uses screen coordinates. Unattended execution scopes search to the active window, checks retained capture context and unique matches, and refuses changed or covered targets before input. Seven native checks passed using the actual shared production functions.
- The main AHK parser passed. Twenty-two relevant bridge tests passed for streaming, continuation, cancellation, history and deterministic reuse.
- Native workflow and script reuse proof files, actual logs and captured images remain local runtime evidence; they are not original-app validation.

The desktop observation helper could not initialize because of an unreadable `D:` volume. Observation used the program's own native screenshots, accessibility, OCR and tool results; the actual demo screenshot was inspected. One report-generation launch timed out during automatic permission review; its allowed retry succeeded.

Full pasteable VS Code/Chrome instructions: `DEEPSEEK_VSCODE_HARNESS_PROMPT.txt` (10,175 characters before subsequent wording refinements; within the Bridge's 12,000-character limit).

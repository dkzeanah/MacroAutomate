# DAA local execution and live validation

DAA means the DeepSeek planner plus the local knowledge and execution layer. The local layer stores observed window context, shortcuts, patterns and versioned tools. It can dispatch an exact saved command without constructing a model client. Broader requests still use the planner; returning a saved map during an existing planning request does not erase that request's cost.

Open **Live workbench → DAA chains** for numbered attempts and their parent/caller, source, branch, arguments and checked outcome. **Written .ahk files → Read selected source / schema** shows the real saved source and revision. **Library functions** shows native function references. The mini desktop is current pixels with a retained numbered input trail; a historical hotspot does not certify a current target.

## Reusable automation units

`daa_unit_save` stores a sequence of typed tool calls. Each step has an ID, branch, tool, arguments and explicit expected result. Existing AHK tools are pinned by revision and SHA-256. Inputs and preceding results are substituted as whole JSON values; the executor does not evaluate arbitrary expressions. A changed pin or failed check stops the sequence. An exit code alone does not prove the UI reached the intended state.

`daa_unit_run` runs the stored sequence locally. The exact Bridge command is:

```
run learned unit UNIT NAME inputs {"input_name":"value"}
```

No source generation or model request is needed for that supported exact command. AHK scripts use `lib/FanBridgeClient.ahk`; Python workflows use `bridge.daa_client.DAAClient`. These share the same loopback tools, task identity, chain parent and execution ledger. Arbitrary direct mouse/keyboard code needs explicit instrumentation; it is not automatically traced or pausable at every instruction.

**Pause / Resume** gates the next instrumented boundary. **Stop run** also works while paused. An input already issued may finish. Pausing after perception can invalidate the pending coordinates: such an action stops on resume and must be inspected again. The bottom-left dot is red during the selected task's automation, amber when paused and gray when idle. The footer identifies the goal, saved-unit subtask/branch, latest action and next requirement.

## Safe discovery

Window learning establishes zones and accessible sections before OCR. Ordered top-level menus and observed popup submenus can be inspected, captured and returned from. Safe tab/collapsible navigation is bounded; unavailable providers or inaccessible custom widgets produce coverage gaps. The discovery tool does not claim exhaustive coverage or activate arbitrary command leaves. Shortcut mnemonics come from observed menus, not a universal hard-coded letter sequence.

Eligible maps use a 75% reuse / 25% fresh-inspection choice. Changed, incomplete, old or ambiguous contexts require fresh inspection. Window chrome alone is insufficient to establish that a Tk application page is unchanged.

Click an **Observation canvas** entry or an individual control row to outline retained bounds. Outlines are temporary, hollow, click-through and non-activating. Automatic following never draws them. Window identity/geometry is checked; moved, minimized, closed, replaced and covered candidates are rejected. Contents may still have changed within an unmoved window, so outlines are labelled retained candidates.

## Explorer lifecycle

Explorer observation is one timer in `MacroAutomator.ahk`, implemented by `lib/ExplorerKnowledge.ahk`. The retired standalone observer and Python watcher have been removed. Both main startup hooks converge on one session even when folder path strings differ. The collector reads foreground Explorer paths/selected references only, skips DAA activity and stops with the main application. It sends no input to Explorer. Ambiguous tab paths get no dwell credit; selected files do not inherit the folder's active time. Full history remains local.

## Real DomeSim lesson

`fan/demos/daa_domesim_20261024` contains the reviewed AHK navigation tools and, after verification, the saved unit, copied prompts, run analyses and comparison. The lesson selects ten real DomeSim Studio launcher forms and checks their headings using native OCR. It does not run rendering, export, recording or feature jobs. The AHK helper was authored/reviewed by Codex from live observations. DeepSeek drafted the unit; its rejected structured contract was corrected locally. Failed planning attempts retain their actual cost/unknown usage.

The narrated prompt uses `manual:true` and waits at each cue for **Continue tour**. The automatic version uses `manual:false`. Window handles are session-specific: after reopening DomeSim, resolve its unique real window again and supply the current handle.

Spending is estimated from reported provider usage. Source/map token savings are counterfactual text estimates, never a credit against spending. When both compared passes use the local executor and make zero provider requests, the report claims no positive avoided-call difference.

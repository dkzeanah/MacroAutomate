# Fan Autopilot

Autopilot is the office-facing layer of Fan: it finds the work you repeat, turns plain
English into workflows, signs in to web portals safely with an audit trail, and keeps
saved workflows running when screens change. Open it from the **Autopilot** tab
(classic view) or the **Autopilot** group (clean task workspace). It has four pages.

| Page | What it does |
| --- | --- |
| **Routine finder** | Lists action sequences you repeat, measured from the local activity log, each with a drafted workflow |
| **Describe it** | Plain English → a checked workflow draft you review, edit, simulate and save |
| **Portals** | Website sign-ins saved in Windows Credential Manager, generated login workflows, audited runs with reports |
| **Reliability** | Self-heal settings, the health of each workflow, and every target Fan had to re-find |

## 1. Routine finder

Fan reads the Usage Predictor's `usage_event` log (app switches, physical clicks,
shortcut keys, typing bursts) **read-only and locally** and looks for the longest
contiguous sequences that recur. It discards window ping-pong (alt-tab back and forth),
trims each routine to start where the work starts and end on the last action, and
ignores sequences that take only a few seconds.

For each routine you see how many times and on how many days it happened, the time it
actually took, the apps involved, and a schedule hint ("usually on Mondays around 9 AM").
"Per week" figures are shown only once at least a week of history exists; before that
you see the measured minutes and the history length.

The drafted workflow uses:

- **Activate Window** for app switches, by window title when it never changed, otherwise `ahk_exe`.
- **Click Element** for learned elements, and otherwise a `winrel:` click that follows the window.
- **Send Keys** for shortcuts.
- **Type Text** only for text that was captured and identical every time. Text that varied becomes an **Ask Input** at the start of the run.

Background scans run every 30 minutes, only while you pause (20 s idle), never during a
workflow. A notification ("You've done … 14 times this week") appears at most twice a
day; turn it off with **Notify me when found**. **Not useful** hides a routine, and its fragments do not
resurface.

Prerequisite: Usage Predictor learning is on (it is by default). Turning on its
literal-text capture lets constant text be replayed; passwords/login windows are never
captured.

## 2. Describe it

Type the task the way you would explain it to a colleague, for example *"Open Outlook,
ask me for the client name, type it, press tab, type "Invoice attached" and click Send."*

- With a DeepSeek key (the Study Assistant key), the model gets the real action catalog,
  your saved coordinate, pattern, element, workflow and portal names, and open **process
  names**. Window titles are sent only if you tick *Share open window titles*. It shares the
  Study Assistant session cost cap.
- Every proposal is validated: unknown actions, bad formats (`Wait` must be ms, loop pairing,
  `If Variable` operators…), references to names that do not exist, secrets typed as text,
  variables used before they are set. Errors go back to the model for up to two repairs.
- Steps that submit, send, pay, delete, file or publish get an **Approval Gate** automatically.
- No key, a failed request, or *Offline only* → the built-in phrase compiler handles common
  phrasing ("open X", "press ctrl+s", "wait 2 seconds", "click Save", "ask me for …",
  "repeat 3 times", "log in to Payroll"…). Anything it cannot map becomes a question, never a guess.

The draft shows a **Check** column (OK / risk / ⚠ error). Edit, remove or reorder steps; each
edit is re-validated. Save is blocked while errors remain. **Simulate** shows where each step
would act without input.

## 3. Portals

**Add portal** stores the sign-in in Windows Credential Manager as `Fan/Portal/<name>`
(DPAPI, your Windows account). Passwords never appear in a workflow, request file, log or
report. They are also registered for redaction in Fan's logs once typed.

**Create login workflow** builds:

1. Open Page.
2. Human Check.
3. (click the username label)
4. Type Credential (username).
5. Tab, or click the password label.
6. Type Credential (password).
7. Enter, or click the sign-in button.
8. Wait.
9. Human Check.
10. Capture Evidence.

Each credential step carries a window guard: Fan refuses to type unless the active window's
title contains the portal's *window title* text, and never types into Fan itself.

**Run & record** runs any workflow with an audit trail: a screenshot after every
non-trivial step, every approval (who/when/decision), every self-heal, and failures. When it
finishes Fan builds `report.html` in `data\autopilot\runs\<run id>\` and opens it. It is a
self-contained page you can print or hand to a manager. Typed values are shortened in reports.

**Human verification is always a person's job.** Human Check detects CAPTCHA, "I'm not a
robot", verification codes, two-step/MFA and sign-in approval prompts, pauses, and asks you to
complete them in the browser. Unattended (agent API) runs stop instead. Fan never attempts
to solve or bypass them.

## 4. Reliability: self-healing

- **Learn.** After a successful click step Fan remembers an anchor: the window
  (exe/class/title), the point relative to the window, the nearest visible label and its
  offset, and a 48×48 pixel fingerprint. After three confirmations it refreshes at most once a
  day, so OCR stays off the hot path.
- **Check before clicking.** For a coordinate click with a confirmed anchor, if the pixels under
  the target no longer match, Fan re-finds it and clicks the new location.
- **Recover after a failure.** A failed click, find or wait step is retried in order:
  1. Wait for the screen.
  2. Relaxed pattern match.
  3. The remembered label.
  4. The step's own name as visible text ("SubmitButton" → "Submit").
  5. The window-relative position, if it still looks the same.
  6. Optionally, the vision model, which is off by default and uses API credit.

  Independent strategies that agree raise the confidence score.
- **Guards.**
  - A candidate must clear the confidence bar: 60% when watched, 80% by default when unattended.
  - A candidate must stay in the same application and away from close buttons.
  - Irreversible-looking steps, and any heal below 80%, are highlighted and need your OK.
  - Unattended runs never get that OK, so they fail safely.
- **Ledger.** Every heal is listed with how it was found. **Apply fix** rewrites the saved
  step: a `winrel:` click target, or a text click for a lost image pattern. **Undo fix**
  restores it.
- **Health.** Each workflow gets a badge from its last 20 runs: New, Reliable, Mostly
  reliable, Self-healing, or Needs attention.

## New workflow actions

| Action | Target | Param |
| --- | --- | --- |
| Ask Input | variable name | `question; default=…; mask=1` |
| Approval Gate | — | what the person approves |
| Type Credential | saved portal name | `username` or `password` |
| Open Page | — | `url=https://…; browser=chrome\|edge\|firefox\|default; wait=title text; timeout=ms` |
| Human Check | area (default `window:A`) | `on=pause\|stop; words=extra\|phrases` |
| Capture Evidence | area (default `window:A`) | label |

New target form for every click action: `winrel:<WinTitle>|0.42,0.77`, a point as fractions of
the window size, so it follows the window when it moves or resizes. The active matching
window wins.

Unattended runs (agent API, `interactive=false`) never prompt. Ask Input needs values in the
run options' `inputs` map. Approval Gate and an on-screen verification prompt stop the run.

## How it is built

| Part | File |
| --- | --- |
| Engine hooks (run ledger, self-heal before/after each step) | `fan/Actions/_Engine.ahk` |
| Actions and portal credential store | `lib/AutopilotActions.ahk` |
| Self-healing | `lib/SelfHeal.ahk` |
| Schema, job runner, ledger and evidence, portals, discovery and notifications | `lib/Autopilot.ahk` |
| The four pages | `lib/AutopilotUI.ahk` |
| Analysis (standard library only) | `fan/autopilot/` — `routines.py`, `compiler.py`, `offline.py`, `catalog.py`, `portal.py`, `llm.py`, `cli.py` |

The app runs analysis as a short job: it writes `data\autopilot\jobs\<id>\request.json`,
starts `python -m fan.autopilot.cli <request.json>` hidden (the DeepSeek Bridge virtual environment, else
any Python 3), and reads `result.json`. A result is always written, even on failure. Tables
(`autopilot_routine`, `autopilot_portal`, `autopilot_run`, `autopilot_heal`, `autopilot_anchor`)
live in the unified tracking database.

## Tests

```powershell
fan\DeepSeekBridge\.venv\Scripts\python.exe -m pytest fan\tests\test_autopilot.py fan\tests\test_autopilot_ahk.py fan\tests\test_workflow_engine.py
```

`test_autopilot.py` covers mining, validation, the offline and model compilers (with a
scripted model), portal templates and reports, and the job CLI. `test_autopilot_ahk.py`
runs the production AutoHotkey functions under the real interpreter, including:

- the engine and ledger together;
- the action safety paths;
- self-heal matching, health and fixes;
- `winrel` resolution against a real window;
- the four pages built and rendered with data;
- a Credential Manager round trip.

The round trip writes a temporary `Fan/Portal/FanAutopilotTest …` entry and deletes it; set
`FAN_SKIP_CREDENTIAL_TESTS=1` to skip it.

# Macro Automate — Programmatic Automation & DeepSeek Autonomy Guide

> **Canonical entry point:** `fan\MacroAutomator.ahk` (AutoHotkey v2, "Macro Automator v9.0 DeepSeek").
> This guide is the *programmatic* companion to the user-facing
> [`fan\AUTOMATION_USER_GUIDE.md`](fan/AUTOMATION_USER_GUIDE.md). It catalogs every panel,
> every machine-facing control surface, and how to wire DeepSeek to run the whole system —
> including the self-discovery layer that reduces explicit input so the agent can "act as you"
> for a full working day. Facts here are code-backed; the older root `*.ahk` files are legacy
> variants — see §2.

---

## 1. Feature & ability highlights (at a glance)

### Automation engines
- **Workflow builder** — 66 actions across mouse, keyboard, windows, FindText, OCR, clipboard, variables, loops, tracking, and research; guided per-action forms, templates, `.maw` portable export/import, Demo Lab, simulation, step-through.
- **Spools** — event-driven `Detect → Respond → Repeat` monitors (Pattern / Pattern Sequence / OCR / Pixel Change / Window Title) with One-Shot / Cooldown / Continuous modes and `.mas` export.
- **Clipboard revolver** — regex extraction rules → field ordering → sequential multi-field paste (bins + `Ctrl+B` / `Ctrl+Shift+B`).
- **AppDSL** — line-oriented language to drive any learned application (`focus`, `click`, `menu File > Save`, `ocrclick`, `waitwin`, …), with a local-Ollama copilot.

### Perception (see the screen)
- **FindText** — pixel/pattern capture & screen search (image matching, not OCR).
- **Windows OCR** — `Windows.Media.Ocr` with word/line boxes, multi-language, Watch Words (dynamic variables), OCR→variable→revolver pipeline.
- **Acc (MSAA)** — accessibility-tree navigation (`FindElement`, `DoDefaultAction`, `DumpAll`).
- **App Learner** — harvest a whole app (Win32 controls, Acc tree, menus, Alt+OCR menus, OCR lines, FindText visuals) into a persistent object model.
- **Snapshot Recovery** — recover the source URL/file behind any capture (live URL, filename clues, Chrome history, Everything 1.5 search).

### Self-learning & prediction
- **Vision Scout** (tab 16) — segments the screen into FindText-backed candidates, learns click/type/window-switch sequences, promotes frequent elements, and offers to auto-complete a repeated sequence (`Win+CapsLock`).
- **Usage Predictor** (tab 17) — coarse virtual-desktop scan + APP/CLICK/KEY/TYPE event model + n-gram next-action prediction (`Win+Shift+CapsLock`).
- **Tracking subsystem** — window time, mouse heat/trace/replay, keystroke history, 5-minute snapshots, named element registry, research pipeline.
- **Attention engine** — measured focus/prominence and media watch-time.
- **Learning insights** — 7/30/90-day aggregate report surfaced to DeepSeek (`fan_learning_insights`).

### DeepSeek / AI integration
- **Direct AHK→DeepSeek** (`lib\StudyLLM.ahk`) — `https://api.deepseek.com/chat/completions`, `deepseek-v4-pro` (text) + `deepseek-flash` (vision); key in Windows Credential Manager or `DEEPSEEK_API_KEY`.
- **DeepSeek Bridge** (tab 20) — a supervised Python gateway + tool-using agent + AHK worker + observatory + MCP server that lets DeepSeek inspect the desktop, write/edit/run AHK scripts, and call the full Fan API.
- **DeepSeek Harness** — official `dsh` Harness wired through an MCP stdio client (`bridge\mcp_server.py`).
- **Live Portal / Study Assistant** — DeepSeek perceives a pinned Chrome page, answers with evidence, and self-composes *human-paced, verified* input; Visual Algebra uses vision + SymPy to solve and enter equations.
- **Local Ollama** (optional) — App Learner copilot + the OJAS studio (`http://localhost:11434`).

### Programmatic control surface (the machine-facing contract)
- **Fan API** — 40+ typed tools (`fan_workflow_*`, `fan_window_*`, `fan_pattern_*`, `fan_page_*`, `fan_taskbar_*`, `fan_library_*`, `fan_input_settings_*`, `fan_learning_*`, `fan_ocr`, `fan_capabilities`, …) over a token-authenticated loopback gateway.
- **FanBridgeClient.ahk** — an AHK SDK (`FanBridge.Inspect`, `OCR`, `FindPattern`, `SaveWorkflow`, `RunWorkflow`, `Call`) for any script.
- **DeepSeek Bridge REST** — `/health`, `/tasks`, `/history`, `/tools/{name}`.
- **MCP** — `window_list`, `window_active`, `window_activate`, `text_type`, `key_send`, `mouse_move`, `mouse_click`, `ahk_script_*`, plus every `fan_*` tool.
- **CLI** — `python -m bridge.agent "<prompt>"`, `Harness.bat atlas <cmd>`, `sl daemon|chat|twin`, `AutoPilot.ahk --plan/--run/--loop`.

### Self-discovery & auto-config (reduce explicit input)
- **`lib\AutoConfig.ahk`** — deduces OCR language, screen region, workflow defaults, saved patterns/workflows, taskbar, discovered targets, and provider state; applies the safe subset with one call.
- **`AutoPilot.ahk`** — folds the self-discovery report into a DeepSeek plan, then executes bounded, verified steps all day with an abort hotkey and a run log.

---

## 2. System map — what is what

| Path | What it is | Runtime |
|---|---|---|
| `fan\MacroAutomator.ahk` | **Canonical app** — combined DeepSeek + ChatGPT v9 build, split into `Core\`, `Actions\`, `Tabs\` | AHK v2 |
| `fan\Tabs\Tab_01..20_*.ahk` | One file per GUI tab (controls + handlers) | AHK v2 |
| `fan\Core\_*.ahk`, `fan\Actions\_Engine.ahk` | globals, helpers, DB, notifications, GDI+, execution engine | AHK v2 |
| root `macroautomaterv7/8/9-*.ahk` | **Legacy single-file builds** (16 tabs, no DeepSeek API) — reference only | AHK v2 |
| `lib\*.ahk` | Shared engines (tracking, learners, Study/DeepSeek, Fan API, AutoConfig) | AHK v2 |
| `fan\DeepSeekBridge\` | Python bridge: `bridge\gateway.py`, `agent.py`, `mcp_server.py`, `desktop.py`, `ahk\Worker.ahk` | Python 3.12 |
| `fan\harness\` | "Harness Studio" / SideLearner + Atlas context-map (`Harness.bat`) | Python 3.10+ |
| `projs\Ollama_Job_Automation_Studio_v1.2\` | Local Ollama studio (RAG, ATS resume, ComfyUI) | Python |
| `data\` | Runtime state: SQLite DBs, INIs, screenshots, logs (git-ignored) | — |
| `fan\harness\.atlas\` | 3-tier LLM context map (ATLAS.md → `*.INDEX.md` → slices) | data |

**Included libraries that matter for automation:** `lib\FanBridgeClient.ahk` (SDK), `lib\FanBridgeAPI.ahk` (the app-side API), `lib\DeepSeekBridge.ahk` (tab 20 glue), `lib\StudyLLM.ahk` (provider), `lib\AutoConfig.ahk` (new), `AutoPilot.ahk` (new).

---

## 3. All panels — itemized feature/ability reference

### 3.1 Main app — 20 tabs (`fan\MacroAutomator.ahk`)

| # | Tab | Itemized abilities |
|---|---|---|
| 1 | **Workflow** | Build/run multi-step sequences from 66 actions; category-filtered action picker; guided per-action forms (pick, never type); contextual Target/Parameter fields + suggestions; templates; loops (`Loop Start/End/Break`); `Popup Detect`; failsafes & qualifiers; speed (0.25×–3×); autosave; `.maw` import/export/write; Demo Lab; simulation, step-through, pause/abort. |
| 2 | **Patterns** | Quick Capture / FindText GUI capture; name + description + qualifier; ASCII preview; Test Pattern / Full View; saved pattern library. |
| 3 | **Live OCR** | Continuous Windows OCR capture; multi-language + scale + grayscale; word/line boxes; **Watch Words** (dynamic variables); search; regex/split; OCR revolver; OCR log. |
| 4 | **Spools** | Define monitor (Pattern/Pattern Sequence/OCR Contains/OCR Regex/Pixel Change/Window Title) → condition → response (Notify/Run Workflow/Click/Extract/Set Var/Key Chord/Run Program/Start|Stop Spool) → repeat mode + cooldown; `.mas` import/export; activity log. |
| 5 | **Analytics** | Click/action recording; per-window mouse hotspots; CSV export; taskbar index (`Win+N`). |
| 6 | **Clipboard** | Extraction rules (regex); extracted fields; standard revolver + smart bins; field ordering. |
| 7 | **Hotkeys** | Assign global hotkeys to saved workflows. |
| 8 | **Hotstrings** | Text expansion manager (options `C * ? B O T`); master enable; test. |
| 9 | **Triggers** | Time/window notification triggers + templates (partial — use Spools for condition-launched workflows). |
| 10 | **Settings** | Delays, retries, FindText tolerance/timeout, failsafes, notifications; Debug Mode; open data folder. |
| 11 | **Notepad** | Save/load notes, popup notepad, clipboard/text send, note→sequence helper. |
| 12 | **Calendar** | Appointment scheduler, time slots, patient profiles, appointment types, local persistence. |
| 13 | **Tracking** | Window time; mouse heat/trace/replay; key history; 5-min snapshots; element registry; research; export/prune. |
| 14 | **App Learner** | Learn controls/Acc/menus/OCR/patterns into an app model; AppDSL console; Ollama copilot; demos; JSON/LLM export. |
| 15 | **Snapshot Recovery** | Phrase/image search; OCR selected; recorded URL/file recovery; Chrome history matching; Everything 1.5 search. |
| 16 | **Vision Scout** | Visual region discovery; review/movable overlays; Test Find → Certify/Reject/Reset; certified-only Pattern export; sequence mining; accepted offers (`Win+CapsLock`). |
| 17 | **Usage Predictor** | Virtual-desktop scan; promoted elements; APP/CLICK/KEY/TYPE history; n-gram continuation offers (`Win+Shift+CapsLock`). |
| 18 | **Study Assistant** | Ingest lesson plans/PDF/notes; concept memory; verified answer engine (memory → material → DeepSeek fallback); confirm/dispute; spaced review; exports. |
| 19 | **Live Portal** | Pin Chrome window; observe→suggest→fill→submit; DeepSeek perception; human-paced verified input; Workflow Lab; Visual Algebra (vision + SymPy). |
| 20 | **DeepSeek Bridge** | Start/Stop gateway+agent+worker+observatory; chat composer (Ctrl+Enter); thinking pane; tool-call log; saved request history; tool catalog; MCP setup; paste/analyze images. |

### 3.2 Supporting panels (hotkey-opened)

| Panel | Hotkey | Abilities |
|---|---|---|
| Attention | `Ctrl+Shift+A` | Measured focus/prominence, media watch-time. |
| Snip Studio | `Ctrl+Shift+1..4` | Saved-region capture, OCR confirm/correct, multiple representations. |
| Question bank / roulette | `Ctrl+Shift+5..6` | Parsed question bank; surface unanswered items. |
| Window Model | `Ctrl+Shift+7` | Cluster a learned app's elements into semantic panes. |
| Snapshot Viewer | `Ctrl+Alt+Shift+S` | Raw/Base64/binary/OCR/elements tabs; drag-to-define named elements. |
| Mouse Heat / Trace, Key History | (Tracking tab) | Inspect, replay, extract features; typed-runs + clipboard timeline. |
| Live Console | (Live Portal) | Structured JSONL audit (CAPTURE/IDENTIFY/LLM/PLAN/ACTION/INPUT/VERIFY). |

### 3.3 Auxiliary programs (root `*.ahk` + `fan\`)

| Program | Purpose | Canonical file |
|---|---|---|
| **ScriptHub** | Script hub / launcher with client-server hotkeys | `AHK_Script_Hub_v2_FULL.ahk`, `ScriptHubClient.ahk` |
| **Developer Workspace Hub** | Everything3-integrated workspace/panel hub | `DeveloperWorkspaceHub_Everything3_FIXED3-Final.ahk` |
| **Global Console Command Menu** | Everything3 console command palette | `GlobalConsoleCommandMenu_Everything3_GUI.ahk` |
| **globalcoder** | Coding assistant (SQLite-backed `globalcoder.db`) | `globalcoder-v7.ahk` |
| **Manager v7** | Compact Explorer project manager + launcher + Script Hub + console menu (`Managerv7.sqlite`); parses `A_Args validate|smoketest` | `Managerv7.ahk` |
| **Everything3 SDK test** | Everything 1.5 search SDK sample | `Everything3_SDK_v3_Test_FIXED.ahk` |
| **Chrome Page Learner** | Learn/`probe` any Chrome viewport (`fan_page_*`) | `fan\ChromePageLearner.ahk` |
| **Application Queue** | Job-application prep queue | `fan\ApplicationQueue.ahk` |
| **Native Learning Workbench** | Evidence/lesson/rehearsal workbench | `fan\NativeLearningWorkbench.ahk` |
| **ahkmcodegen** | Standalone AHK MCode (machine-code) generator | `ahkmcodegen.ahk` |
| **All Libraries Demo** | Interactive demo of SQLiteDB/Acc/FindText/OCR/Vis2 | `All_Libraries_Demo.ahk` |

### 3.4 Harness Studio + Atlas (`fan\harness`)

Launch with `fan\harness\Harness.bat` (GUI `python -m studio.app`) or `Harness.bat atlas <cmd>` (CLI). Eleven Studio tabs cover the SideLearner agent, the Atlas context map, OJAS, and Creator Ops. The **Atlas** gives an LLM a 3-tier map: `ATLAS.md` (137 projects / 17 buckets) → per-project `*.INDEX.md` (one symbol per line) → slice fetch by `@bucket/project:path#Symbol`. Protocol: `atlas get <address>` (read code), `atlas find "<intent>"` (dedupe), `atlas plan-insert` (placement), retire-never-delete. `sl daemon|chat|twin|web` drives the SideLearner agent.

### 3.5 Ollama Job Automation Studio (`projs\…`)

`main.py` (Tk). Tabs: Setup & Models, Model Lab, Memory/RAG, Verified Profile, ATS Resume Scanner, Application Assistant, Visual Synthesis. Local Ollama only (`http://localhost:11434` `/api/tags|ps|chat|embed`), ComfyUI at `127.0.0.1:8188`.

---

## 4. Programmatic API surface

### 4.1 DeepSeek Bridge gateway (REST, loopback)

Token-authenticated (`X-Bridge-Token`), port from `fan\DeepSeekBridge\.env` `BRIDGE_PORT` (default **8765**; observatory `MONITOR_PORT` **8766**).

| Endpoint | Method | Purpose |
|---|---|---|
| `/health` | GET | service/child status, `managed_scripts`, `windows_worker`, `fan_connected`, `key_loaded`. |
| `/tasks` | POST | queue an agent task (`{prompt, history, images}`) → `{id}`. |
| `/tasks/{id}` | GET | task status (`queued|running|complete|error|cancelled`) + `response`. |
| `/tasks/{id}/events?after=N` | GET | streaming event page (`agent_text`, `reasoning`, `agent_tool_call`, `agent_tool_result`). |
| `/tasks/{id}/cancel` | POST | cancel a queued/running task. |
| `/history` | GET | saved request history. |
| `/tools/{name}` | POST | invoke a typed tool (the Fan API + `ahk_script_*`, `mouse_*`). |
| `/fan/next`, `/fan/result`, `/observations` | GET/POST | the app-side worker's FIFO + observation stream. |

### 4.2 `lib\FanBridgeClient.ahk` — AHK SDK (include in any v2 script)

```ahk
#Requires AutoHotkey v2.0
#Include %A_ScriptDir%\lib\FanBridgeClient.ahk
caps := FanBridge.Capabilities()            ; full app surface + workflow schema
info := FanBridge.Inspect(0, true)          ; perceive a window (hwnd 0 = active)
txt  := FanBridge.OCR(0)                    ; Windows OCR text
hit  := FanBridge.FindPattern("SaveButton") ; search a saved pattern
FanBridge.LearnPattern("Submit", Map("x",0,"y",0,"w",120,"h",32), 0, "submit button")
FanBridge.SaveWorkflow("MyFlow", steps, false)
FanBridge.RunWorkflow("MyFlow", 120)
FanBridge.Call("fan_library_search", Map("query","TrackDB_Init"))
```

**Class methods:** `Call(tool, args, timeout)`, `Capabilities()`, `PrepareWindow(hwnd)`, `Unit(name, inputs)`, `Trace(label, hwnd, phase, point)`, `Insights(query, limit)`, `DiscoveredTargets(query, limit)`, `Inspect(hwnd, image)`, `LearnPage(hwnd, refresh)`, `PageElements(pageId, query, offset)`, `ResolvePageElement(pageId, elementId, hwnd)`, `PageImage(pageId, elementId)`, `OCR(hwnd, region)`, `FindPattern(name, hwnd, region)`, `LearnPattern(name, region, hwnd, description)`, `SaveWorkflow(name, steps, overwrite)`, `RunWorkflow(name, timeoutSeconds)`.

### 4.3 Fan API tool catalog (`fan_*` / `daa_*`)

Returned programmatically by `FanBridge.Capabilities()` / `fan_capabilities`. Dispatch table (from `lib\FanBridgeAPI.ahk`):

- **Window:** `fan_window_prepare`, `fan_window_probe`, `fan_window_survey`, `fan_window_shortcut`, `fan_window_menu`, `fan_window_probe_item`, `fan_desktop_preview`, `fan_window_inspect`.
- **Vision/patterns:** `fan_ocr`, `fan_pattern_list`, `fan_pattern_search`, `fan_pattern_capture`, `fan_page_learn`, `fan_page_probe`, `fan_page_resolve`, `fan_page_image`.
- **Workflows:** `fan_workflow_list`, `fan_workflow_get`, `fan_workflow_save`, `fan_workflow_preview`, `fan_workflow_run`.
- **Taskbar:** `fan_taskbar_learn`, `fan_taskbar_list`, `fan_taskbar_open`.
- **Learning:** `fan_learning_lesson`, `fan_learning_compile`, `fan_learning_rehearse`, `fan_learning_insights`, `fan_discovered_targets`, `fan_code_index`.
- **Settings/library:** `fan_input_settings_get`, `fan_input_settings_set`, `fan_library_search`, `fan_library_read`.
- **DAA units:** `daa_unit_run`, `daa_trace`.

`fan_capabilities` also returns the **workflow step schema** (`action`/`target`/`param`/`enabled`/`failsafe`/`qualWindow`/`qualPattern`), the exact per-action `spec` (`targetHint`, `help`, required flags), the `script_sdk` path, and `coordinate_system` (physical screen pixels; negative multi-monitor allowed). This is the single source of truth an agent should read before composing a workflow.

### 4.4 Workflow actions — programmatic schema

`fan_workflow_save(name, steps, overwrite)` accepts an array of `Map("action", A, "target", T, "param", P, "enabled", bool, "failsafe", Map, "qualPattern", "", "qualWindow", "")`. `A` must be an exact name from `GetWorkflowActionNames()` (66 actions). Required target/param are validated; loops must balance; `fan_workflow_run(name, timeout_seconds)` executes through the same engine as the UI.

### 4.5 AppDSL (App Learner) — line-oriented runner

`focus` · `use <app>` · `learn` · `menu File > Save [@cmd|@altletter|@keys|@mouse|@random]` · `alt f s` · `click|dblclick|rightclick|hover TARGET` · `clickat X Y [win]` · `type <text>` · `ctrltext ClassNN|text` · `keys ^s` · `wait 500` · `waitwin|focuswin <text> [ms]` · `ocr [X Y W H]` · `ocrclick|ocrrightclick <text> [@scroll]` · `waitocr <text> [ms]` · `menupick <text>` · `run <prog>` · `setclip <text>` · `say <msg>`. Prefixes: `try`, `retry [ms]`. Generation: `Ollama_GenerateScript(appId, goal, model, url, &err)`.

### 4.6 Live Portal / Study tool language

`TYPE id text` · `SET id 0|1` · `CHOOSE id label` · `HOVER id ms` · `WAIT ms` · `CLICK id`. Capped (12k chars, 50 steps, 2k/field, 3s/wait, 15s aggregate waits). No arbitrary AHK/Python/shell/coordinates/keys.

### 4.7 Library search/read

`fan_library_search(query, limit)` indexes every callable function signature across `lib\`, `fan\Core`, `fan\Actions`, `fan\Tabs`, plus `FindText.ahk`/`OCR.ahk`/`SQLiteDB.ahk`. `fan_library_read(path, start_line, line_count)` returns the exact source. Agents should read signatures before calling; the SDK (`FanBridgeClient`) is the preferred live-stateful path.

### 4.8 MCP server (official DeepSeek Harness)

`bridge\mcp_server.py` exposes the same tools over stdio. Register the client (`@deepseek-ai/dsh-mcp-client`, `serverName: fan-ahk-windows`) by merging `fan\DeepSeekBridge\harness\cordis.patch.yml` into the active `dsh` profile (`cordis.patch.yml`), then set real absolute `command`/`cwd`. Discovered tools: `window_list`, `window_active`, `window_activate`, `text_type`, `key_send`, plus `ahk_script_list/write/read/run`, `mouse_move`, `mouse_click`, and every `fan_*` tool.

### 4.9 CLI entries

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" fan\MacroAutomator.ahk --seed-db C:/tmp/fresh.db   # schema gen
fan\DeepSeekBridge\.venv\Scripts\python.exe -m bridge.agent "List windows and activate Notepad"
fan\DeepSeekBridge\.venv\Scripts\python.exe -m bridge.mcp_server                    # MCP stdio
fan\harness\Harness.bat atlas <cmd>   |  Harness.bat   |  fan\harness\Harness.bat test
fan\harness\.venv\Scripts\python.exe -m sidelearner.cli daemon start|chat|twin     # (or `sl …`)
AutoHotkey64.exe AutoPilot.ahk --probe|--report|--apply|--ask "<q>"|--plan "<goal>"|--run|--loop 900|--self-test
```

---

## 5. DeepSeek configuration & integration

### 5.1 API key & endpoint

- **Key source (priority):** `DEEPSEEK_API_KEY` environment variable → Windows Credential Manager generic credential `MacroAutomator/DeepSeek` (`lib\StudyLLM.ahk` `StudyLLM_Key`/`StudyLLM_SaveKey`). Set it in **Study Assistant → Save API key** or **Live Portal → Save API Key**.
- **Endpoint:** `https://api.deepseek.com` (configurable via `Study_GetSetting("provider"/"endpoint")`).
- **Models:** `deepseek-v4-pro` (text/planning), `deepseek-flash` (vision). Cost cap via `cost_cap_usd` (default 2.00).

### 5.2 The DeepSeek Bridge (tab 20) topology

```
fan\MacroAutomator.ahk (owns lib\DeepSeekBridge.ahk)
   └─ spawns: python -m bridge.desktop --parent <FanPid>
        ├─ gateway  (uvicorn bridge.gateway:app)  127.0.0.1:BRIDGE_PORT
        ├─ agent    (bridge.agent --daemon)       DeepSeek tool-use consumer
        ├─ worker   (AutoHotkey64.exe ahk\Worker.ahk)  executes native input
        ├─ observatory (bridge.monitor)           127.0.0.1:MONITOR_PORT
        └─ applications (bridge.job_applications)
```

Env injected by the app: `DEEPSEEK_API_KEY`, `DEEPSEEK_MODEL`, `DEEPSEEK_VISION_MODEL`, `DEEPSEEK_BASE_URL`, `AUTOHOTKEY_EXE`, `ALLOW_AGENT_SCRIPTS=1`, `FAN_PROJECT_ROOT`. The key is inherited from Credential Manager and **never written to `.env`** (`.env` holds only `BRIDGE_TOKEN`, `BRIDGE_PORT`, `MONITOR_PORT`, `ALLOW_AGENT_SCRIPTS`). On a fresh machine run `fan\DeepSeekBridge\install.bat` once.

### 5.3 Harness (SideLearner) providers — `fan\harness\config.yaml`

DeepSeek (`deepseek-v4-pro`, `https://api.deepseek.com`), DeepSeek vision (`deepseek-flash`), three local Ollama providers (`qwen2.5-coder:7b`, `embeddinggemma`, `qwen3-vl:4b`), OpenAI/Anthropic disabled. Routing is local-first with tier fallback (`tier: local|budget|best`).

### 5.4 Local Ollama (optional, no API key)

`http://localhost:11434` — used by App Learner copilot (`AppLearner`), OJAS (`ojas\ollama_api.py`), and SideLearner.

---

## 6. Self-discovery & auto-configuration

The goal is to **reduce explicit input**: deduce answers and configuration from what the machine and the running app already know, instead of asking the user (or the agent) to type them.

### 6.1 Deduction map — what auto-fills from where

| Explicit input you'd otherwise type | Auto-deduced from | Mechanism |
|---|---|---|
| OCR language (`en-US`…) | OS locale `A_Language` | `AutoConfig_Probe` |
| Full-screen OCR region | Screen/monitor geometry | `AutoConfig_Probe` |
| FindText tolerance, date format, delays | Safe defaults + existing settings | `AutoConfig_Deduce` |
| Reusable pattern names | saved FindText patterns | `fan_pattern_list` |
| Reusable workflow names | saved workflows | `fan_workflow_list` |
| Taskbar `Win+N` position | learned taskbar icons | `fan_taskbar_list` |
| "What app am I in / what's on screen" | live perception | `fan_window_inspect`, `fan_ocr` |
| Likely next actions | usage history + n-grams | `fan_learning_insights`, Vision Scout, Usage Predictor |
| Semantic UI targets | passive a11y discovery | `fan_discovered_targets` |
| Provider/agent reachability | env + gateway `/health` | `AutoConfig_Probe` |
| Callable library signatures | source index | `fan_library_search/read` |

### 6.2 `lib\AutoConfig.ahk` — the deduction engine

Include-safe, self-contained, Fan-API client. Public functions:

- `AutoConfig_Probe()` → machine facts (monitors, resolution, locale, AHK/Python paths, bridge env, foreground window, provider-key presence).
- `AutoConfig_Deduce()` → suggested settings tagged with their **evidence source**, plus counts of saved patterns/workflows, discovered targets, taskbar apps, and the live-inspected window.
- `AutoConfig_Report("json"|"text")` → serialized probe + deduction (this is what the agent pastes into its plan prompt).
- `AutoConfig_Apply(overrides)` → pushes the safe `workflow.*` subset via `fan_input_settings_set`.
- `AutoConfig_SelfTest()` → reachability + deduction self-check (`ok`, `errors[]`, `fan_reachable`).

### 6.3 `AutoPilot.ahk` — the daily driver

Standalone companion (run the main app first). See §4.9 for flags. `--plan "<goal>"` merges the self-discovery report + saved workflows into a DeepSeek prompt and writes `data\autopilot\plan.json`. `--run` executes the plan one bounded, verified step at a time (workflow runs and `fan_*`/`daa_*` tool calls only), logging `data\autopilot\run_log.jsonl`. `--loop <sec>` runs the whole cycle all day. `Ctrl+Alt+Shift+X` aborts; `F1` shows resident status.

---

## 7. "Act as me" — a full-day autonomous workflow

A realistic, **supervised** all-day loop (the codebase's own philosophy: bounded actions, verification, abort):

1. **Observe** — `AutoConfig_Probe` + `fan_window_inspect`/`fan_ocr` identify where you are.
2. **Recall** — `fan_learning_insights`, `fan_discovered_targets`, saved workflows/patterns seed the plan; Vision Scout / Usage Predictor pre-arm predicted continuations.
3. **Decide** — DeepSeek (via the bridge agent or `AutoPilot --plan`) produces an ordered, JSON day plan that reuses existing verified primitives.
4. **Act** — `fan_workflow_run` / `fan_*` tools / generated AHK scripts (`ahk_script_run`); the app's own verified input layer (human-paced, readback-checked) does the typing.
5. **Verify** — readback, `fan_pattern_search`, OCR result checks; failures stop or skip per failsafe.
6. **Record** — `fan_workflow_save`, `fan_learning_compile`, `run_log.jsonl`; Study JSONL audit.
7. **Repeat** — `AutoPilot --loop` re-probes on a schedule and continues where it left off.

**Safety boundary:** autonomy is assembled from separate engines; there is no single unrestricted "do anything" planner. Agents must read `fan_capabilities`, reuse saved workflows, and confirm live context before acting. `Ctrl+Shift+X`/`Escape` abort standard workflows; `Ctrl+Shift+Escape` aborts the Study controller; `Ctrl+Alt+Shift+X` aborts AutoPilot.

---

## 8. Wiring & extension

- **Give DeepSeek a new capability** → add a `fan_*` case in `lib\FanBridgeAPI.ahk` `FanAPI_Dispatch`, expose it in `fan_capabilities`, then it is automatically callable via `FanBridge.Call`, the bridge `/tools/{name}`, and MCP.
- **Add a workflow action** → keep `GetWorkflowActionNames`/`GetWorkflowActionSpec`, the guided form, the engine dispatch, serialization, and simulation consistent (see `fan\Tabs\Tab_01_Workflow*.ahk`, `fan\Actions\_Engine.ahk`).
- **Deepen harness↔AHK** → merge `cordis.patch.yml` into the `dsh` profile; optionally enable SideLearner `web` (`config.yaml` → `web.enabled: true`) and bridge its WebSocket to the gateway.
- **Include order** for the tracking stack is documented in `lib\LIBRARY_GUIDE.md` §8 — `TrackSQLite`/`TrackUtil`/`TrackingDB` before trackers, `Acc`/`AppLearner` after.
- **Two SQLite wrappers** must not be renamed (`SQLiteDB` vs `TrackSQLite`) — a name collision is a load-time error.

---

## 9. Validation & boundaries

- Syntax-check the whole app: `AutoHotkey64.exe /validate fan\MacroAutomator.ahk` (exit 0 = clean). Self-check the new layer: `AutoHotkey64.exe AutoPilot.ahk --self-test`.
- Known partial paths (see `fan\AUTOMATION_USER_GUIDE.md` §16): Triggers tab is partial (use Spools); AppDSL OCR doesn't auto-expand `$ocr`; AppDSL `@cmd`/`ctrltext` can be invisible; no global exclusive-input arbiter.
- The 4-page Visual Algebra demo is the recorded end-to-end DeepSeek proof (1,321 audit events; ≈$0.0165 historical run).

---

## 10. Reference index

- User-facing guide: [`fan\AUTOMATION_USER_GUIDE.md`](fan/AUTOMATION_USER_GUIDE.md) (66 actions, recipes, boundaries) + browser edition `fan\AUTOMATION_USER_GUIDE.html`.
- Library API index: [`lib\LIBRARY_GUIDE.md`](lib/LIBRARY_GUIDE.md).
- Split manifest: [`fan\SPLIT_MANIFEST.md`](fan/SPLIT_MANIFEST.md). Project README: [`fan\README.md`](fan/README.md), [`README.md`](README.md).
- Tracking subsystem: [`TRACKING_GUIDE.md`](TRACKING_GUIDE.md). Spools: [`SPOOL_WORKFLOW_GUIDE.txt`](SPOOL_WORKFLOW_GUIDE.txt).
- DeepSeek Bridge: [`fan\DeepSeekBridge\README.md`](fan/DeepSeekBridge/README.md) (+ `MONITOR_README.md`, `ECHO7_EVALUATIONS.md`).
- Harness/Atlas: [`fan\harness\ATLAS.md`](fan/harness/ATLAS.md), [`fan\harness\LLM_GUIDE.md`](fan/harness/LLM_GUIDE.md), [`fan\harness\docs\CONTEXT_MAP_SPEC.md`](fan/harness/docs/CONTEXT_MAP_SPEC.md).
- Study spec: [`fan\REALTIME_STUDY_ASSISTANT_SPEC.md`](fan/REALTIME_STUDY_ASSISTANT_SPEC.md), [`fan\AUTOMATION_SUBSYSTEM_SPEC.md`](fan/AUTOMATION_SUBSYSTEM_SPEC.md).
- New layer: [`lib\AutoConfig.ahk`](lib/AutoConfig.ahk), [`AutoPilot.ahk`](AutoPilot.ahk).

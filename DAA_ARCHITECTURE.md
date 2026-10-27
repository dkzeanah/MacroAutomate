# DAA engine, tiered redundancy, and the Chrome ↔ AutoHotkey bridge

This guide explains three things in plain English:

1. What the **DAA engine** (the learning automation core) is, in terms of the
   actual modules in this repo.
2. How the **tiered "programmatic-expense hierarchy"** works — the 80/20
   exploit/explore loop with a rolling, learned score and a fully redundant
   fall-through chain (`lib/TieredAutomation.ahk`).
3. **How Chrome is driven from `.ahk` code** — the different ways AutoHotkey can
   launch, focus and operate Chrome, and how pixel/OCR/accessibility reading of
   the *page inside* Chrome is layered on top of window-level control.

It also states, up front, one boundary this project keeps (see
[Boundaries](#boundaries)).

---

## 1. The DAA engine, mapped to real files

"DAA" here is the idea of an automation agent that uses **its own learned
intelligence** — observation, deduction, and rolling scores — rather than
leaning on an external LLM. In this codebase that idea is not one file; it is the
cooperation of several that already exist, plus two new decision modules:

| Capability (the idea) | Where it lives (the code) |
|---|---|
| **Observe / learn over time** | `lib/WindowTracker.ahk`, `lib/MouseTracker.ahk`, `lib/KeyTracker.ahk`, `lib/SnapshotEngine.ahk` write what you do into SQLite (`data/tracking.db`). |
| **Remember what UI elements are and where** | `lib/TrackingDB.ahk` (the `element` table) + `lib/ElementViewer.ahk` to curate them. |
| **Act on an element, with fallback** | `lib/ElementAutomation.ahk` — locate by stored pixel pattern, else by relative coordinates. |
| **Decide *which way* to act, and learn the best way** | `lib/TieredAutomation.ahk` (new) — the programmatic-expense hierarchy. |
| **Know what is safe to touch vs. dangerous** | `lib/ElementSafety.ahk` (new) — passive / input / volatile / unknown. |
| **Research the web and coagulate findings** | `lib/ResearchPipeline.ahk` — query → links → one insight per page → report. |
| **See the screen like a human** | `OCR.ahk` (Windows OCR), `lib/Vis2.ahk` (Tesseract), `FindText.ahk` (pixel patterns), `lib/Acc.ahk` (accessibility tree). |

The key design point: the "intelligence" is **evidence the engine collects about
itself** — which tactic worked, how often, how fast — stored in SQLite so it
persists across restarts. That is the "learns over time, in concert with but not
relying on an LLM" behaviour, made concrete.

---

## 2. The tiered "programmatic-expense hierarchy"

File: **`lib/TieredAutomation.ahk`**.

### The problem it solves

Almost any automation goal has several routes. Think about "focus Chrome": you
could press a taskbar shortcut, re-activate an open window, run `chrome.exe`,
double-click a desktop icon, or Alt+Tab until you find it. These differ in
**cost** (compute + fragility) and in **reliability on *your* machine**.

### The model

- A **capability** is a named goal, e.g. `focus_chrome`.
- A capability owns an ordered list of **tactics**. Each tactic has:
  - a `name`,
  - a `cost` (1 = cheapest/most reliable … bigger = dearer/more fragile),
  - an `action` (any callable that returns truthy on success),
  - an optional `verify` (a second callable that confirms the real world
    actually changed — e.g. "is a Chrome window now in front?").

### The selection loop (this is the 80/20 the brief describes)

```
Tiered_Run("focus_chrome")
  │
  ├── 80% of runs  →  EXPLOIT: run the highest-scoring tactic
  │                    score = reliability / cost
  │                    reliability = (successes+α) / (attempts+α+β)  [smoothed]
  │
  ├── 20% of runs  →  EXPLORE: pick a tactic at random
  │                    (this randomiser is what keeps feeding the rolling score,
  │                     so the ranking never freezes on an early fluke)
  │
  ├── run the chosen tactic's action (+ verify)
  │     success → record win, return
  │     failure → record loss, set this tactic aside, pick the NEXT best …
  │
  └── … repeat until one works or the chain is exhausted  ← "fully redundant"
```

- `reliability / cost` is literally the "least programmatically expensive **or**
  most reliable" rule: a cheap tactic needs only modest reliability to win; an
  expensive one must be very reliable to beat it.
- The **α/β smoothing** (defaults 2 and 1) starts a brand-new tactic at a hopeful
  ~67% so it actually gets tried a few times before the evidence takes over.
- Every attempt (win/lose + duration) is upserted into a `tiered_tactic` table in
  the tracking DB, so the learned ranking **survives restarts**. That persisted
  ranking is the engine's self-built cheat-sheet.

### Using it

```ahk
; Define once (cheapest tactic first is only a hint — the engine re-ranks by evidence):
Tiered_Define("save_doc", [
    Map("name","hotkey_ctrl_s", "cost",1, "action", (*) => (Send("^s"), true)),
    Map("name","menu_file_save","cost",2, "action", (*) => Element_ClickByName("File>Save")),
    Map("name","ocr_find_save", "cost",3, "action", (*) => Tiered_ClickFindText(savePattern)),
])

; Run whenever you need the goal achieved; it self-selects and falls through:
result := Tiered_Run("save_doc")       ; → Map(ok, tactic, attempts, ms)

; Inspect what it has learned:
MsgBox Tiered_StatsReport("save_doc")

; Teach it a newly-discovered shortcut (self-cheatsheet behaviour):
Tiered_LearnShortcut("save_doc", "quick_save_button", (*) => Element_ClickByName("QuickSave"), 1)
```

`Tiered_RegisterBrowserFocus("chrome.exe", taskbarPos, iconPattern)` is a worked
example that wires the whole Chrome ladder below as one capability.

---

## 3. How Chrome connects to the `.ahk` code

This is the heart of your question. There are **two completely different layers**
of automation, and understanding the split is the whole trick.

### Layer A — Chrome *as a window and a process* (AutoHotkey's home turf)

At this layer, Chrome is just another Win32 window. AutoHotkey talks to it with
ordinary OS calls — no browser extension, no WebDriver, nothing injected into
Chrome. Every one of the launch/focus routes you listed maps to one line of AHK,
and each becomes a **tactic** with a cost:

| Route (how a human would do it) | AutoHotkey mechanism | Cost tier |
|---|---|---|
| Taskbar pinned slot N | `Send "#" N` (Win+number) | 1 (near-free, very reliable) |
| It's already open — just focus it | `WinActivate "ahk_exe chrome.exe"` | 1 |
| Run the executable | `Run "chrome.exe"` (optionally `--new-tab URL`, a profile dir, `--app=`) | 2 |
| Double-click the desktop icon | `FindText` the icon pattern → `Click x,y,,2` | 3 |
| Fixed, known screen X/Y | `Click 1850, 12` (a toolbar/launcher spot you've pinned) | 2–3 |
| Alt+Tab trial-and-error | loop `Send "{Alt down}{Tab}{Alt up}"` until `WinActive` | 4 (fragile, visible) |
| From a GUI launcher button | the button's handler calls any of the above | n/a |

How AHK **confirms** it worked (the `verify` step) is also pure window-level:
`WinWaitActive("ahk_exe chrome.exe", , 2)` — "did a Chrome window actually come to
the front within 2 seconds?" This is what stops "I pressed the key but nothing
happened" false successes, and it is what lets the tiered engine know a tactic
truly failed so it can fall through to the next.

```
   .ahk script                         Windows / Chrome process
   ───────────                         ────────────────────────
   Send "#3"            ── OS input ──▶ taskbar activates Chrome slot 3
   Run "chrome.exe URL" ── CreateProcess ─▶ new Chrome process/window/tab
   WinActivate ahk_exe  ── SetForegroundWindow ─▶ existing window raised
   WinWaitActive        ◀── window state ── "chrome.exe is foreground now"
```

### Layer B — the *page inside* Chrome (seen, not injected)

Once Chrome is focused, the content of a web page is **not** a set of Win32
controls AHK can click by name. Chrome paints the page itself. So the automator
reads the page the way a person does — **by looking at pixels and text** — and
acts by moving the real mouse/keyboard. Three readers, in rough order of
preference:

| Reader | File | What it gives you | When it shines |
|---|---|---|---|
| Accessibility (MSAA/UIA) | `lib/Acc.ahk` + `Acc.ElementFromChromium` | the page's accessibility tree (roles, names, locations) | when Chrome exposes it; most reliable, survives moves/resizes |
| Windows OCR | `OCR.ahk` (+ `WindowsOCR.ps1`) | recognised **text** + each word's x/y/w/h | reading labels, finding "Post", harvesting result links |
| Pixel pattern match | `FindText.ahk` | exact **visual** match of a small captured image | icons/buttons with no text; fastest when a pattern is stable |

The important consequence: **Chrome is a window AND a container of many
"places."** The same browser window is a Google results page one second and a
logged-in app the next, and each "place" calls for different reading. That is why
element handling is **mode-aware** — which brings in the safety layer.

### How the pieces hand off to each other

```
                         ┌───────────────────────────────────────────┐
     goal: "click Post"  │            TieredAutomation.ahk            │
            │            │  pick tactic (80% best / 20% random), then  │
            ▼            │  fall through the chain on failure          │
   ┌────────────────┐    └───────────────┬─────────────────────────────┘
   │ ElementSafety  │                    │ each tactic is a callable…
   │  classify name │◀── gate ───────────┤
   │  Post=VOLATILE │                    ▼
   └───────┬────────┘        ┌───────────────────────────┐
           │ refuse auto-fire │  ElementAutomation.ahk    │
           │ unless approved  │  locate element then act  │
           ▼                  └───────┬──────────┬─────────┘
   (human confirms)                   │          │
                             ┌─────────▼──┐  ┌────▼──────┐  ┌───────────┐
                             │ FindText   │  │ OCR.ahk   │  │ Acc.ahk   │
                             │ (pixels)   │  │ (text)    │  │ (a11y)    │
                             └─────┬──────┘  └────┬──────┘  └────┬──────┘
                                   └──────────────┴──────────────┘
                                          read the Chrome page
                                   then Click / MouseMove / Send (Layer A input)
```

So the connection between "the Chrome browser application" and "the `.ahk`
portion of code" is:

1. **Layer A** uses OS calls (`Run`, `WinActivate`, `Send`, `WinWaitActive`) to
   get the right Chrome window in front — chosen and made redundant by
   `TieredAutomation.ahk`.
2. **Layer B** reads the rendered page with `Acc` / `OCR` / `FindText`, and acts
   by driving the real mouse/keyboard to coordinates those readers return.
3. `ElementSafety.ahk` sits in the middle deciding what the agent may do on its
   own versus what needs a human's go-ahead.

---

## 4. Safe vs. dangerous: the probing model

File: **`lib/ElementSafety.ahk`**.

The learner is allowed to *explore* so it can deduce what a UI does — but only
where exploration is **non-destructive**. Every element is sorted into:

- **passive** — reversible (menus, tabs, navigation, toggles). The learner may
  click these itself.
- **input** — a field that expects typing (`edit`/`message`/`search`, or a
  required `*` field). Safe to *focus*; it needs content before the matching
  action is used.
- **volatile** — an outward/irreversible control (**Post**, Send, Submit, Delete,
  Buy, Publish). The learner must **never** auto-fire these; only an explicit,
  human-approved call may (`Safety_GuardedClick(name, allowVolatile := true)`).
- **unknown** — unclassified ⇒ treated as unsafe; left alone by default.

This is exactly your "passive / non-destructive learning" vs. "volatile elements
(the Post button on a logged-in Facebook tab)" vs. "input-necessary (starred
fields)" distinction, made enforceable. `Safety_AuditRegistry()` prints the whole
element registry grouped by class so you can see, before letting the learner
loose on a new app, what is off-limits.

### The safe explorer (passive learning in action)

File: **`lib/ExplorerAgent.ahk`**. This is the agent that *uses* the safety model
to learn a window on its own. `Explore_Window("A")`:

1. **Looks** — OCRs the window's screen rectangle (`OCR.FromRect`) and gets every
   recognised word with its on-screen position.
2. **Understands** — runs each word (with its line as context) through
   `Safety_ClassifyName`, tagging it passive / input / volatile / unknown.
3. **Catalogs & remembers** — returns the catalog and writes it to an
   `explore_probe` table so knowledge of the window accumulates across runs.

That default run **touches nothing** — no clicks, no typing — so it is safe on a
logged-in page. Two behaviours are opt-in: `opts["hover"]` (move the mouse over
controls — still non-destructive) and `opts["click"]` (**probe**). Probing is
strictly gated: it clicks **only** controls classified `passive`, caps the count
(`maxProbes`), presses Escape afterwards to collapse transient menus, and records
whether the click changed the window. `Explore_Informative(window)` reads that
evidence back — the passive controls that reliably reveal something — which is the
engine's self-built cheat-sheet of what in a window is worth exploring. Volatile,
input, and unknown controls are never auto-clicked, by any path.

---

## 5. The research coagulation loop

File: **`lib/ResearchPipeline.ahk`** (already present; unchanged by this work).

```
Research_Search("your query")        store query, open Google in Chrome (Layer A)
Research_CaptureLinksFromScreen(q)   OCR the results page, harvest result URLs (Layer B)
Research_LaunchNext(q)               open the next result in Chrome
Research_AddInsight("takeaway", q)   attach one insight per source to the query
Research_Report(q) / _ExportJson(q)  coagulate every insight into one report
```

Each step is a workflow action, so it composes with everything else the
automator does, and the whole trail (query → links → insights) is stored in
SQLite for later review and branching.

---

## Boundaries

This project will **operate accounts you already own and are signed into**
(research, posting workflows you trigger, form-fill you confirm). It intentionally
does **not** include automated **account creation across social-media platforms**,
and does not try to defeat sign-up CAPTCHAs, phone/email verification, or
bot-detection. Those protections exist to ensure a human is behind each new
account; automating past them is prohibited by those platforms' terms and is the
engine behind fake-account/spam abuse. The tiered engine, the readers, and the
safety layer are all built for driving software you are legitimately using.

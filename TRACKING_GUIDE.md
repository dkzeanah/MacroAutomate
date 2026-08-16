# Behavior Tracking Subsystem

A tracking layer added to Macro Automator v7 that records how you actually use
your machine and turns it into reusable automation data. Everything is stored
in a single SQLite database (`data\tracking.db`) and surfaced through a new
**Tracking** tab.

Four trackers, one store, and a viewer that lets you name on‑screen elements so
the workflow engine can act on them later.

---

## Contents

1. [Quick start](#quick-start)
2. [Feature 1 — Window time tracking](#feature-1--window-time-tracking)
3. [Feature 2 — Mouse tracking per window](#feature-2--mouse-tracking-per-window)
4. [Feature 3 — Keystroke history](#feature-3--keystroke-history)
5. [Feature 4 — 5‑minute window snapshots + element registry](#feature-4--5minute-window-snapshots--element-registry)
6. [Using tracked data in workflows](#using-tracked-data-in-workflows)
7. [The research pipeline](#the-research-pipeline)
8. [Database & files](#database--files)
9. [Requirements](#requirements)
10. [Architecture](#architecture)

---

## Quick start

1. Launch `macroautomerv7.ahk` as usual.
2. Open the **Tracking** tab (last tab).
3. Click **Start All** — or press **Ctrl+Alt+T**.
4. Use your computer normally for a while.
5. Explore what was captured with the **Window Times**, **Mouse Heat / Trace**,
   **Key History**, and **Snapshot Viewer** buttons.

Whatever trackers are running when you close the app are resumed automatically
next launch.

### Hotkeys

| Hotkey | Action |
| --- | --- |
| `Ctrl+Alt+T` | Toggle all trackers on/off |
| `Ctrl+Alt+Shift+S` | Open the Snapshot Viewer |
| `Ctrl+Alt+Shift+C` | Capture a snapshot cycle right now |

---

## Feature 1 — Window time tracking

Tracks the **activated** window and accumulates focus time **per unique window
name** in the database.

- Window titles are normalised into a stable *name* so volatile parts don't
  fragment your data: unread counters (`(3) Inbox`), dirty markers (`* file`),
  and trailing app names (`… - Google Chrome`) are stripped.
- Time is credited only while you're physically present — after 2 minutes with
  no real keyboard/mouse input the current interval is closed, so walking away
  doesn't inflate totals. Automated (synthetic) input doesn't count as presence.
- Each focus interval is written immediately and extended on a heartbeat, so an
  unexpected exit loses at most a few seconds.

**Explore it:** Tracking tab → **Window Times**. Switch scope between *All time
/ Today / This week*, export to CSV, or jump straight to the mouse/key data for
the selected window.

---

## Feature 2 — Mouse tracking per window

Samples the pointer at 20 Hz and stores **one‑minute movement snapshots per
window**. All coordinates are stored *relative to the window*, which is what
makes the data portable — it survives the window moving or being resized.

From that raw movement the subsystem derives four things:

- **Heat map** — aggregated hover / click / dwell density, rendered as a colour
  map (blue → red, log‑scaled).
- **Movement replay / simulation** — re‑drive any recorded minute through the
  real mouse. Replays against the original window rect, or re‑targets and
  **rescales** onto a live window of the same name. Press **Esc** to abort.
- **Feature extraction** — clusters clicks and dwell into ranked *element
  candidates* (the spots you actually interact with), each with both
  window‑pixel and normalised 0–1 coordinates.
- **Portable export** — those features export to **JSON, CSV, Python
  (pyautogui), JavaScript, or AutoHotkey**, always with normalised coordinates
  so they drop into other automation tools that know nothing about this script.

**Explore it:** Tracking tab → **Mouse Heat / Trace**. Pick a window, switch the
view (hover / clicks / dwell / features), double‑click a snapshot to see its
trace, or **Replay Movement**. **Export** writes the features in your chosen
format.

---

## Feature 3 — Keystroke history

A non‑intrusive `InputHook` observes every keystroke (keys still pass straight
through to the focused app) and accumulates **one‑minute snapshots per window**.
On each flush the minute's input is distilled into separate columns:

- **raw stream** — compact token trace (`H e l l o {Space} {Enter} ^c`)
- **text typed** — the reconstructed printable text (backspaces applied)
- **hotkeys** — chord combos (`^c ^v {F5} !{Tab}`), also counted per window
- **strings** — distinct words
- **sentences** — text split on `. ! ?` and newlines
- **code snippets** — lines that read as source code (heuristic)
- **clipboard** — every text copy is logged to `clip_history`, classified
  (url / email / phone / code / …) and de‑duplicated

**Privacy.** This is a keystroke logger writing plaintext to a local database,
so it is off by default and guarded three ways:

- Input synthesised by this script's own macros is excluded (`InputHook` option
  `I1`), so replaying a workflow never pollutes the history.
- Windows whose name looks like a credential prompt (password, sign in,
  1Password, Bitwarden, KeePass, LastPass…) are skipped automatically.
- You can add your own never-record window fragments under
  Tracking tab → **Key Privacy…**.

**Explore it:** Tracking tab → **Key History**. Filter by window, click a minute
to see each category in its own tab, or open the **Top Hotkeys** / **Clipboard
Log** views.

---

## Feature 4 — 5‑minute window snapshots + element registry

Every 5 minutes the engine walks every visible window and, for each, produces
**three linked representations of the same frame**, all keyed to one database
row:

1. **Raw image** — a full‑resolution `.png` saved to a known, tracked path
   (`data\tracking\snapshots\<cycle>\<n>_<window>.png`).
2. **Base64** — the raw file's bytes, base64‑encoded, stored as text in the DB.
3. **Binary image** — a thresholded 1‑bit image in the **exact FindText format**
   (`|<>*threshold$W.base64`), so it can be pasted straight into a FindText
   pattern. Otsu's method picks the threshold; the longest side is capped so the
   blob stays storable.

(Optionally, OCR text of each frame too — toggle **OCR on snapshot**.)

### The tabbed viewer

Tracking tab → **Snapshot Viewer** (or **Ctrl+Alt+Shift+S**). Pick a cycle, pick
a captured window, and each representation appears in its own tab: **Raw Image**,
**Base64**, **Binary Image** (rendered back to a picture + ASCII), **OCR Text**,
and **Elements**.

### Naming elements

On the **Raw Image** tab, click **Mark Element** and drag a box around any UI
element. Give it a **name** and a **functional description** ("Search box — type
the query and press Enter"). The element is saved with:

- absolute capture coordinates **and** window‑relative 0–1 coordinates,
- a cropped thumbnail,
- a **FindText binary pattern of just that element**,

— everything the automation engine needs to find and act on it later, even
after the window moves or the app restarts.

---

## Using tracked data in workflows

Named elements and tracked windows become first‑class workflow actions in the
**Workflow** tab's action dropdown:

| Action | Target | Param | Does |
| --- | --- | --- | --- |
| **Click Element** | element name | `Left`/`Right`/`Middle[,count]` | Locate the element on screen and click it |
| **Hover Element** | element name | — | Move the mouse to it |
| **Wait Element** | element name | timeout ms | Wait for it to appear |
| **Replay Window Mouse** | window name | `speed[,clicks]` | Replay that window's latest recorded mouse movement |

An element is located two ways, tried in order:

1. **Visual** — its stored FindText pattern is searched for on screen (survives
   the window moving).
2. **Relative** — its 0–1 coordinates are projected onto the live window of the
   same tracked name (survives a resize).

---

## The research pipeline

Implements the databased research loop: **search → capture links → visit each →
record one insight per page**.

| Action | Param | Does |
| --- | --- | --- |
| **Research Search** | query text | Store the query and open a Google search for it |
| **Research Capture Links** | `screen` or `clip` | Harvest result URLs (OCR the page, or from clipboard) |
| **Research Launch Next** | — | Open the next pending result link |
| **Research Add Insight** | takeaway text | Attach a key takeaway to the current query |

Everything is databased — query, its links, and per‑link insights — and can be
exported as a report or JSON. Drive it from the **Research Pipeline** panel
(Tracking tab) or sequence the actions in a workflow.

---

## Database & files

Everything lives under `data\` (git‑ignored — it's local runtime state):

```
data\tracking.db                     the SQLite store (WAL mode)
data\tracking\snapshots\<cycle>\…    raw window .png captures
data\tracking\elements\…             element crop thumbnails
data\tracking\*.png / *.csv / *.json rendered heatmaps and exports
data\tracking_errors.log             tracker error log (timers fail quietly)
```

**Prune Old Data** (Tracking tab) deletes rows and their image files older than
N days and vacuums the database. **Export All (JSON)** dumps window times,
elements, and per‑window features to a timestamped folder.

---

## Requirements

- **AutoHotkey v2** (already required by the main script).
- **SQLite** — resolved automatically in this order:
  1. `lib\sqlite3.dll` (drop one here for the newest features), else
  2. `sqlite3.dll` next to the script, else
  3. **`winsqlite3.dll`** — ships with Windows 10 (1607+) and 11, so **no
     install is needed** on a modern Windows box.

  If none is found the Tracking tab shows why and the rest of the app is
  unaffected.

---

## Architecture

The subsystem is a set of AutoHotkey modules under `lib\`, included by the main
script:

| Module | Responsibility |
| --- | --- |
| `SQLiteDB.ahk` | Dependency‑free SQLite wrapper (statement cache, transactions, reentrancy‑safe) |
| `TrackUtil.ahk` | Time keys, window‑name normalisation, JSON, CSV, hashing, base64 |
| `TrackingDB.ahk` | Schema + every data‑access helper |
| `PixelCanvas.ahk` | Software ARGB canvas + PNG writer (heatmaps, traces, binary render) |
| `WindowTracker.ahk` | Feature 1 + the shared "current window" context |
| `MouseTracker.ahk` | Feature 2 (sample, heat, trace, replay, feature extraction) |
| `KeyTracker.ahk` | Feature 3 (InputHook, categorisation, clipboard, privacy exclusions) |
| `SnapshotEngine.ahk` | Feature 4 capture (image → base64 → binary) |
| `ElementViewer.ahk` | Tabbed viewer + element‑marking UI |
| `ElementAutomation.ahk` | Locate/click elements; portable feature export |
| `ResearchPipeline.ahk` | Query → links → insights |
| `TrackingDashboard.ahk` | The Tracking tab + all detail panels |

The trackers run on timers and share one database connection; the DB layer runs
each statement (and each transaction) under `Critical` so a 20 Hz mouse sample
can't interrupt a window‑poll write mid‑statement.

---

## Repository layout

```
macroautomerv7.ahk        the main script (this is what you run)
FindText.ahk              shared libraries kept at the root because many
OCR.ahk                     scripts include them by bare name
SQLiteDB.ahk
lib/                      libraries, including the tracking subsystem
test/tools/               standalone tools, demos and reference scripts
test/macroautomator-history/  older MacroAutomator versions + v7 working copies
test/variants/            duplicate library copies kept for reference
test/data/                demo workflows (.maw/.mas) and misc data
data/                     runtime output (git-ignored)
```

### A note on the two SQLite wrappers

There are deliberately two, because they are different things:

| File | Class | Used by |
| --- | --- | --- |
| `SQLiteDB.ahk` (root) | `SQLiteDB` | v7's own `g_DB` — unchanged |
| `lib/TrackSQLite.ahk` | `TrackSQLite` | the tracking subsystem only |

They cannot share a class name: two classes with the same name in one compiled
script is a load-time error. The tracking store therefore keeps its own
connection, its own file (`data\tracking.db`), and its own wrapper — and
resolves `winsqlite3.dll` automatically so it needs no `sqlite3.dll` on disk.

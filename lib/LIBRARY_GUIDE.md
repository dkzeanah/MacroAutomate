# MacroAutomater — Library Reference & Automation API Index

This document is a machine-readable index of **every library under `lib\`** so an
automation agent (or LLM) can understand exactly what code is at its disposal and
how to call it. It is written for AutoHotkey, mostly **v2** (a few files are
**v1.1**).

> **Two interpreters.** Nearly every file requires **AutoHotkey v2**. `Vis2.ahk`
> is **AutoHotkey v1.1** and must never be `#Include`d from a v2 process. (An
> `ImagePut` copy also exists in v1 form at the repo root for `Vis2`; the copy in
> `lib\` uses v2 syntax.) The main app is `macroautomerv8.ahk` /
> `macroautomaterv9-*.ahk` (v2).

---

## 0. How the code is organized

There are three layers, in dependency order:

1. **Vendored / standalone libraries** — reusable, mostly upstream code
   (`FindText`, `OCR`, `Acc`, `Gdip_All`, `ImagePut`, `JSON`, `SQLiteDB`,
   screenshot tools). They have no knowledge of MacroAutomater.
2. **The tracking subsystem** — a persistent, always-on recorder of *what the
   user does*: window focus, mouse, keys, screen snapshots, extracted UI
   elements. Everything shares one SQLite file (`data\tracking.db`) through a
   common `TrackSQLite` connection and helper layer (`TrackingDB`, `TrackUtil`).
3. **The automation/self-learning layer** — turns tracked data (and live
   screen/accessibility state) into actions: `ElementAutomation`,
   `AppLearner` (AppDSL + Ollama), `ResearchPipeline`, `SnapshotRecovery`,
   and the two parallel v9 self-learners `VisionScout` and
   `UsagePatternPredictor`.

### Critical cross-cutting facts (read these first)

- **`#Include` order matters.** `TrackSQLite.ahk` and `TrackUtil.ahk` must be
  included before the trackers. `ElementAutomation.ahk`/`AppLearner.ahk` come
  after the trackers they consume. The main script already does this correctly.
- **Two different SQLite wrappers exist and MUST NOT be confused.**
  - `SQLiteDB.ahk` → class **`SQLiteDB`** (root app workflows; uses `sqlite3.dll`
    from the script root).
  - `TrackSQLite.ahk` → class **`TrackSQLite`** (the tracking store; resolves
    `lib\sqlite3.dll` → root `sqlite3.dll` → Windows `winsqlite3.dll` → PATH).
  Two classes with the same name would be a load-time error; that is why they
  are named differently. **Tracking code always goes through `TrackDB()` /
  `TrackDB_*` helpers, never `SQLiteDB`.**
- **The shared tracking DB** is opened by `TrackDB_Init()` and accessed via
  `TrackDB()`. Tables live in `data\tracking.db`.
- **Coordinates are screen-relative** unless noted. The trackers prefer
  **window-relative (0–1) normalized coordinates** so recordings survive window
  moves/resizes (`rel_x`, `rel_y`, `rel_w`, `rel_h`).
- **`TrackCtx_Get()`** returns the current foreground-window context
  (`win_id`, `app_id`, `name`, `title`, `exe`, `class`, `hwnd`, `x/y/w/h`) and is
  the canonical way to attribute any action to a window.
- **FindText vs OCR are different engines.** FindText matches *pixels* (encoded
  as a text pattern); OCR reads *text*. They are used together: FindText to find
  a button/icon, OCR to read a value or find a word.

---

## 1. Quick reference table

| File | Runtime | What it is | Primary entry points |
|---|---|---|---|
| `FindText.ahk` | v2 | Pixel pattern capture & screen search | `FindText(&x,&y,…)`, `FindText().Gui()`, `.ScreenShot`, `.GetTextFromScreen`, `.RangeTip`, `.BindWindow`, `.ImageSearch` |
| `OCR.ahk` | v2 | Windows UWP OCR (text) | `OCR.FromRect`, `OCR.FromWindow`, `OCR.FromDesktop`, `OCR.FromFile`, `OCR.WaitText`, result `.Text/.Words/.Lines` |
| `Vis2.ahk` | **v1** | Tesseract OCR + Google Vision labeling | `OCR(image,lang,opts)`, `ImageIdentify(image,search,opts)`, `Vis2.provider.Tesseract`, `Vis2.provider.GoogleCloudVision` |
| `Acc.ahk` | v2 | MSAA/UI-Automation accessibility tree | `Acc.ElementFromHandle/Point/Chromium/Path`, `.FindElement(s)`, `.WaitElement`, `.DoDefaultAction`, `.Click`, `.Highlight`, `.DumpAll` |
| `ElementAutomation.ahk` | v2 | Locate/act on tracked UI elements | `Element_Locate`, `Element_ClickByName`, `Element_HoverByName`, `Element_WaitByName`, `Element_ExportJson` |
| `AppLearner.ahk` | v2 | Learn a whole app UI + drive via AppDSL / Ollama | `AppMap_LearnWindow`, `AppExec_Run`, `AppExec_OcrClick`, `AppExec_MenuPick`, `AppMap_BuildLLMPrompt`, `Ollama_GenerateScript` |
| `ElementViewer.ahk` | v2 | Snapshot viewer + drag-to-define elements | `Snap_OpenViewer(cycleId)`, `Vw_*` |
| `TrackSQLite.ahk` | v2 | Minimal SQLite wrapper (tracking store) | `class TrackSQLite` (`Exec/Run/Query/Scalar/QueryRow/Begin/Commit/…`) |
| `TrackingDB.ahk` | v2 | Tracking schema + all data access | `TrackDB_Init/Ready/MetaGet/MetaSet`, `TrackDB_AddMouseSnapshot/AddKeySnapshot/SaveElement/…` |
| `TrackUtil.ahk` | v2 | Time/JSON/CSV/hash/string helpers | `TrackTS`, `TrackJsonEncode/Decode`, `TrackHash`, `TrackSafeName`, `TrackNormalizeWindowName`, `TrackGetActiveWindow`, `TrackBase64Encode/DecodeToFile` |
| `WindowTracker.ahk` | v2 | Window focus/time tracking + shared context | `WinTrack_Start/Stop/Toggle`, `TrackCtx_Get`, `TrackCtx_Refresh`, `TrackLogError` |
| `MouseTracker.ahk` | v2 | Mouse movement/clicks, heatmaps, replay, feature extraction | `MouseTrack_Start/Stop`, `MouseTrack_RenderHeatmap/Trace`, `MouseTrack_Replay`, `MouseTrack_ExtractFeatures`, `MouseTrack_Features` |
| `KeyTracker.ahk` | v2 | Keystroke history (1-min snapshots) | `KeyTrack_Start/Stop`, `KeyTrack_ExcludeWindow`, `KeyTrack_Snapshots`, `KeyTrack_TopHotkeys`, `KeyTrack_RecentClips` |
| `SnapshotEngine.ahk` | v2 | 5-min whole-desktop image capture (raw+base64+FindText binary) | `Snap_Start/Stop`, `Snap_RunCycleNow`, `Snap_CaptureWindow`, `Snap_MakeBinary`, `Snap_FileToBinary`, `Snap_RenderBinary` |
| `SnapshotRecovery.ahk` | v2 | Recover a snapshot's source URL (browser URL, filename clues, Chrome history) | `BrowserUrl_FromWindow`, `SnapClue_FromFilename`, `ChromeHist_Search`, `ChromeHist_Around`, `SnapRec_BuildTab`, `SnapRec_OcrSelected` |
| `Everything3Client.ahk` | v2 | Everything 1.5 SDK search | `class Everything3SDK` → `Search(query, max)` |
| `PixelCanvas.ahk` | v2 | Software 32bpp canvas → PNG | `class PixelCanvas` (`SetPixel`, `Line`, `Circle`, `FillRect`, `DrawRect`, `Blob`, `Save`) |
| `ResearchPipeline.ahk` | v2 | Query→links→insights browser loop | `Research_Search`, `Research_CaptureLinks`, `Research_LaunchNext`, `Research_AddInsight`, `Research_Report` |
| `TrackingDashboard.ahk` | v2 | Coordinator + "Tracking" tab UI + detail panels | `Track_InitAll`, `Track_StartAll/StopAll`, `Track_BuildTab`, `Track_OpenWindowTimes/MousePanel/KeyHistory/Research/Elements` |
| `VisionScout.ahk` | v2 | v9 self-learning visual scraper + sequence predictor (deepseek) | `VisionScout_Init/BuildTab`, `VS_Start/Stop`, `VS_ScanScreen`, `VS_MineSequences`, `VS_ExportPromoted`, `VS_ExecuteContinuation` |
| `UsagePatternPredictor.ahk` | v2 | v9 local visual usage learner + n-gram predictor (parallel build) | `UsagePredictor_BuildTab`, `g_UP*` state, Win+CapsLock accept |
| `AHKv2_Screenshotter.ahk` | v2 | Simple capture helpers | `CaptureWholeScreen`, `CaptureActiveWindow(client)`, `CaptureRenderedActiveWindow(client)` |
| `AHKv2_Screenshot_Tools.ahk` | v2 | GDI+ client/rendered-window capture primitives | `Gdip_ClientAreaBitmapFromHWND`, `Gdip_RenderedBitmapFromHWND`, `Gdip_RenderedClientAreaBitmapFromHWND`, `PrintWindow`, `CreateDIBSection`, `BitBlt` |
| `AHKv2_Screenshotter_Quickstart.ahk` | v2 | Hotkey examples | `CaptureMouseRegion`, `CaptureWholeScreen`, `CaptureActiveWindow` |
| `Gdip_All.ahk` | v2 | Standard AHKv2 GDI+ library | `Gdip_Startup/Shutdown`, `Gdip_CreateBitmapFromFile`, `Gdip_SaveBitmapToFile`, `Gdip_GraphicsFromImage`, `Gdip_DrawText`, … |
| `ImagePut.ahk` | v2 (this copy) | Image conversion to/from any source | `ImagePutBase64`, `ImagePutBitmap`, `ImagePutClipboard`, `ImagePutFile`, `ImagePutScreenshot`, `ImagePutBuffer` |
| `JSON.ahk` | v2 | JSON parse/serialize | `JSON.Load(text)`, `JSON.Dump(value)` |
| `SQLiteDB.ahk` | v2 | SQLite wrapper for the main app | `class SQLiteDB` (`OpenDB/Exec/GetTable/Prepare/EscapeStr/AttachDB/…`) |
| `_cfg.ahk`, `_guibase.ahk`, `_tab_main.ahk`, `_tab_opts.ahk`, `_tab_out.ahk`, `_get_c_function_header.ahk`, `ahk\CreateImageButton.ahk` | v2 | `ahkmcodegen` GUI internals (MCode generator) | not automation; see root `ahkmcodegen.ahk` |
| `sqlite3.dll` | native | SQLite for `SQLiteDB`/`TrackSQLite` | — |
| `Everything3.dll` | native | Everything 1.5 SDK (used by `Everything3Client`) | — |
| `WindowsOCR.ps1` | ps1 | Backing helper for `OCR.ahk` (Windows.Media.Ocr) | — |
| `bin\` (tesseract.exe, leptonica_util.exe, tessdata_*) | native | Backing engines for `Vis2.ahk` | — |

---

## 2. Vision libraries (find & read the screen)

### 2.1 `FindText.ahk` — pixel/pattern matching (v2)
Feiyue's FindText v8.9. Captures a small region into a compact **text pattern**
(`|<Name>*150$20.encoded`) and re-searches screen pixels for it.

- **This is image matching, not OCR.** Use it for buttons, icons, toggles,
  anything with a stable visual signature.
- Core search (returns an Array of match Maps `{x,y,w,h,mx,my,id}`):
  ```ahk
  ok := FindText(&x, &y, x1, y1, x2, y2, err1, err0, Text)
  ; err1 = foreground tolerance, err0 = background tolerance (0.1 = 10%)
  ```
- Wait-for-appear/disappear uses the first two by-ref args as `mode, timeout`:
  ```ahk
  FindText(&"wait", &3000, ...)   ; wait1 = appear, wait0 = disappear
  ```
- Capture a pattern from the screen: `FindText().GetTextFromScreen(x1,y1,x2,y2,"**50")`
  returns the encoded pattern text (used by SnapshotEngine and VisionScout).
- Other useful members: `ScreenShot`, `GetColor`, `SetColor`, `RangeTip`,
  `MouseTip`, `SavePic`, `ShowPic`, `BindWindow`/`BindWindow(0)`,
  `ImageSearch`, `Sort`, `Ocr` (joins matched pattern ids — not Tesseract),
  `WaitChange`, `GetPicHash`.
- Running `FindText.ahk` directly opens its pattern-capture GUI.

### 2.2 `OCR.ahk` — Windows OCR (v2)
Wrapper over the UWP **`Windows.Media.Ocr`** engine (helper: `WindowsOCR.ps1`).
Reads *text* with word/line bounding boxes.

```ahk
r := OCR.FromRect(x, y, w, h, "en-US", 1.0)   ; scale 1.0; bigger helps small text
r.Text            ; all recognized text
r.Words / r.Lines ; each has .Text .x .y .w .h (relative to the rect)
r.TextAngle
```
- Entry points: `OCR.FromRect`, `OCR.FromDesktop`, `OCR.FromMonitor`,
  `OCR.FromWindow(WinTitle)`, `OCR.FromFile`, `OCR.FromBitmap`, `OCR.FromPDF`.
- `OCR.GetAvailableLanguages()`, `OCR.LoadLanguage()`, `OCR.WaitText(needle, timeout, func)`,
  `OCR.Cluster()`, `OCR.WordsBoundingRect()`, `OCR.ClearAllHighlights()`.
- Options object: `{lang, scale, grayscale, monochrome, invertcolors, rotate, flip, x,y,w,h, decoder}`.
- Result helpers: `Result.FindString(Needle, opts)`, `Result.FindStrings`.

### 2.3 `Vis2.ahk` — Tesseract OCR + Google Cloud Vision (v1 only)
Alternative OCR (Tesseract) plus cloud image labeling. **Do not include from v2.**

```ahk
OCR(image, language, options)           ; image = file/URL/hwnd/rect/base64/bitmap
ImageIdentify(image, search, options)   ; Google Cloud Vision labels
```
- Accepts `"eng+fra"` style languages if matching `.traineddata` exists in both
  `bin\tesseract\tessdata_best` and `bin\tesseract\tessdata_fast`.
- Lower-level: `Vis2.provider.Tesseract` (preprocess/best/fast/retrieve), and
  `Vis2.Graphics` (selection areas, overlays, bitmaps).
- Google key goes in `Vis2_API.txt` (`GoogleCloudVision=KEY`); cloud calls may
  incur cost. See `Vis2_README.md`.

### 2.4 Screenshot tools
- `AHKv2_Screenshotter.ahk` — simplest path: `CaptureWholeScreen()`,
  `CaptureActiveWindow(clientOnly := false)`,
  `CaptureRenderedActiveWindow(clientOnly := false)`. Auto-starts GDI+ and
  writes to `Screenshots\`. See `AHKv2_Screenshot_Tools_README.md`.
- `AHKv2_Screenshot_Tools.ahk` — the GDI+ primitives underneath:
  `Gdip_ClientAreaBitmapFromHWND`, `Gdip_RenderedBitmapFromHWND`,
  `Gdip_RenderedClientAreaBitmapFromHWND` (uses the undocumented `PrintWindow`
  flag for hardware-accelerated apps), plus `PrintWindow`, `CreateDIBSection`,
  `BitBlt`, `GetDC`, `Gdip_BitmapFromScreenWithCursor`, `Gdip_SaveBitmapToFile`.
- `Gdip_All.ahk` — the standard AHKv2 GDI+ library (bitmaps, graphics, drawing,
  text). Root `macroautomerv8.ahk` also has local `Gdip_Startup`,
  `CreateDIBSection`, `BitBlt`, `GetDC`, `ReleaseDC`, `DeleteDC`, `SelectObject`
  helpers near the bottom.

---

## 3. Accessibility & semantic navigation

### 3.1 `Acc.ahk` — MSAA/UI-Automation tree (v2)
Exposes the Microsoft Active Accessibility tree as array-like v2 objects. This
is the *most robust* way to find a control (survives window move/resize/theme),
when the app exposes accessibility.

```ahk
el := Acc.ElementFromHandle("A")                ; or ElementFromPoint(x,y)
el := Acc.ElementFromChromium(winTitle)         ; enables Chromium a11y
el := Acc.ElementFromPath("1,2,p1,button")
btn := el.FindElement({RoleText:"push button", Name:"Save", matchmode:"Substring"})
btn.DoDefaultAction() / btn.Click("left", 1) / btn.Highlight(1500, "Lime", 3)
```
- Starting points: `ElementFromHandle`, `ElementFromPoint`, `ElementFromChromium`,
  `ElementFromPath`, `GetRootElement`, `RegisterWinEvent(event, callback, PID)`.
- Query: `FindElement`, `FindElements`, `WaitElement`, `WaitElementExist`,
  `WaitNotExist`, `GetPath`, `Dump`, `DumpAll`, `ValidateCondition`.
  Conditions support AND objects, OR arrays, `not`, match modes, case sensitivity,
  scope, traversal order, indexes, partial locations.
- Act: `DoDefaultAction`, `Click`, `ControlClick`, `Navigate`, `HitTest`,
  `Highlight`, `ClearHighlight`. Prefer `DoDefaultAction()` over coordinate clicks.

### 3.2 `ElementAutomation.ahk` — tracked element → action (v2)
Bridge from the tracking store's `element` table to automation. `Element_Locate`
resolves an element two ways, in order: **(1) visual** FindText pattern, then
**(2) relative** 0–1 window-coordinate projection.

- `Element_Locate(el, err1, err0)` → `Map(x,y,w,h,cx,cy,method)`.
- `Element_ClickByName(name, button, count)`, `Element_HoverByName(name)`,
  `Element_WaitByName(name, timeout)`, `Element_Center(loc)`,
  `Element_FindLiveWindow(name)`, `Element_ExportJson`, `MouseFeatures_Export`.

### 3.3 `AppLearner.ahk` — learn a whole app, then drive it (v2)
The richest navigation layer. **Learn** walks a window and harvests every
`ClassNN` control, the full Acc tree, the Win32 menu bar (recursed), and
optionally non-Win32 menus read by OCR. Saved to `data\appmap.db` with absolute
**and** relative coordinates.

```ahk
AppMap_LearnWindow(hwnd, opts)      ; inspect + save an app's interface
AppExec_Run(appId, script)          ; execute an AppDSL script
Ollama_GenerateScript(appId, goal, model, url, &err)   ; LLM writes the script
```

**AppDSL** (one command per line; grammar in global `APPDSL_GUIDE`):
`focus`, `use <app>`, `learn`, `menu File > Save As [@cmd|@altletter|@keys|@mouse|@random]`,
`alt f s`, `click TARGET`, `dblclick`, `rightclick`, `hover`, `clickat X Y [win]`,
`type <text>`, `ctrltext ClassNN|text`, `keys ^s`, `wait 500`, `waitwin <text> [ms]`,
`focuswin <text> [ms]`, `ocr [X Y W H]`, `ocrclick <text> [@scroll]`,
`ocrrightclick <text> [@scroll]`, `waitocr <text> [ms]`, `menupick <text>`,
`run <prog>`, `setclip <text>`, `say <msg>`. Prefixes: `try`, `retry [ms]`.

Key helpers: `AppMap_Apps`, `AppMap_Elements(appId, kind, filter)`,
`AppMap_Resolve(appId, ref)`, `AppMap_Locate(app, el)`, `AppMap_DeleteApp`,
`AppMap_BuildLLMPrompt(appId, goal)`, `AppMap_ExportJson(appId, path)`,
`AppLearner_DemoScript(1..4)` (non-destructive end-to-end demos),
`Ollama_Ping(url)` (default `http://localhost:11434`), `Ollama_Generate(prompt, model, url)`.

### 3.4 `ElementViewer.ahk` — mark elements from snapshots (v2)
`Snap_OpenViewer(cycleId)` opens the snapshot viewer; drag a rectangle over a
captured image to define a named element (→ `element` table). `Vw_DefineElement`,
`Vw_SaveElementRegion`, `Vw_TestElement`, `Vw_ExportElements`,
`Vw_ReExtract` (mouse feature extraction), `Vw_SnapshotNow`.

---

## 4. Tracking subsystem (persistent usage recording)

All data flows to **`data\tracking.db`** through `TrackDB_*` helpers. Tables:
`meta`, `app`, `win`, `win_session`, `mouse_snapshot`, `mouse_heat`,
`mouse_feature`, `key_snapshot`, `hotkey_stat`, `clip_history`, `snap_cycle`,
`snap_entry`, `element`, `query`, `query_link`, `query_insight`, plus
`vs_element/vs_action/vs_sequence` (VisionScout) and the AppLearner's own
`data\appmap.db`.

### 4.1 `TrackSQLite.ahk` — the DB engine
`class TrackSQLite`. `__New(path)` auto-applies `PRAGMA journal_mode=WAL`.
Methods: `Exec(sql)`, `Run(sql, params*)` (rows changed), `Query(sql, params*)`
(array of Maps), `QueryRow`, `Scalar`, `Column`, `LastInsertId()`, `Changes()`,
`Begin/Commit/Rollback/Transact(fn)`, `TableExists`, `ColumnExists`,
`AddColumnIfMissing`, `Vacuum`, `FileSize`, `Close`, `IsOpen`. Static:
`TrackSQLite.Available()`, `TrackSQLite.LibInfo()`. A helper `SqlQuote(value)` /
`SqlIntList(arr)` / `SqlJoin` exists for rare dynamic SQL.

### 4.2 `TrackingDB.ahk` — schema + data access
- Lifecycle: `TrackDB_Init(dbPath?)`, `TrackDB()` (live conn or ""),
  `TrackDB_Ready()`, `TrackDB_Close()`.
- Meta: `TrackDB_MetaGet(key, default)`, `TrackDB_MetaSet(key, value)`.
- Identity: `TrackDB_AppId(exe,class)`, `TrackDB_ResolveWindow(title,class,exe)`,
  `TrackDB_FindWinByName(name)`, `TrackDB_WinRow(winId)`.
- Window time: `TrackDB_AddSession/OpenSession/ExtendSession/PruneEmptySessions`,
  `TrackDB_TopWindows(scope)`, `TrackDB_TopApps(scope)`, `TrackDB_HourHistogram`.
- Mouse: `TrackDB_AddMouseSnapshot(snap)`, `TrackDB_MergeHeat(winId, cells)`.
- Keys: `TrackDB_AddKeySnapshot(snap)`, `TrackDB_BumpHotkey`, `TrackDB_AddClip`.
- Snapshots: `TrackDB_StartCycle`, `TrackDB_FinishCycle`, `TrackDB_AddSnapEntry`,
  `TrackDB_CycleEntries`, `TrackDB_RecentCycles`.
- Elements: `TrackDB_SaveElement`, `TrackDB_FindElement`, `TrackDB_BumpElementHit`,
  `TrackDB_Elements`, `TrackDB_DeleteElement`.
- Research: `TrackDB_AddQuery`, `TrackDB_AddQueryLink`, `TrackDB_AddInsight`,
  `TrackDB_NextPendingLink`, `TrackDB_QueryByText`.
- Maintenance: `TrackDB_Prune(days)`, `TrackDB_Stats()`.

### 4.3 `TrackUtil.ahk` — shared helpers
Time: `TrackTS()`, `TrackMinuteKey()`, `TrackDayKey()`, `TrackFormatMs(ms)`,
`TrackStampDiffMs`. Window: `TrackAppKey`, `TrackNormalizeWindowName(title, exe, aggressive)`,
`TrackGetActiveWindow()`. JSON: `TrackJsonEncode(value, indent, level)`,
`TrackJsonDecode(text)`. CSV: `TrackCsvCell`, `TrackCsvRow`. Strings/arrays:
`TrackArrayJoin`, `TrackArrayHas`, `TrackHash` (FNV-1a), `TrackEllipsis`,
`TrackSafeName`, `TrackClamp`. Base64: `TrackBase64EncodeFile`,
`TrackBase64Encode(buf,size)`, `TrackBase64DecodeToFile(b64,path)`.

### 4.4 `WindowTracker.ahk` — focus/time + shared context
`WinTrack_Start/Stop/Toggle/IsOn`. Polls the foreground window, accumulates
focus time, and refreshes the shared context:
`TrackCtx_Get(maxAgeMs)` / `TrackCtx_Refresh()` → the `g_TrackCtx` Map. Also
defines `TrackLogError(where, err)` (the tracking logger).

### 4.5 `MouseTracker.ahk` — mouse + replay + feature extraction
`MouseTrack_Start/Stop/Toggle/IsOn`. Samples the pointer at ~20 Hz into 1-minute
snapshots (path + click blobs), builds a per-window heat grid, and can extract
**element candidates** (interaction hotspots):
- `MouseTrack_Snapshots(winId, limit)`, `MouseTrack_Snapshot(id)`,
  `MouseTrack_HeatCells(winId)`, `MouseTrack_WindowSize(winId)`.
- Render: `MouseTrack_RenderHeatmap(winId, outPath, metric)`,
  `MouseTrack_RenderTrace(snapId, outPath)`, `MouseTrack_RenderFeatures(winId)`.
- Replay: `MouseTrack_Replay(snapId, speed, targetHwnd, doClicks, manageEsc)` —
  re-drives a recorded path (scales to a resized window).
- Features: `MouseTrack_ExtractFeatures(winId, minWeight, clusterRadius)`,
  `MouseTrack_Features(winId)`. Decode: `MouseTrack_DecodePath/DecodeClicks`.

### 4.6 `KeyTracker.ahk` — keystroke history
`KeyTrack_Start(withClipboard)`, `KeyTrack_Stop/Toggle/IsOn`. An `InputHook`
(option `I1` ignores the script's own synthetic input) records 1-minute
snapshots with `raw_stream`, `text_typed`, `hotkeys`, `strings`, `sentences`,
`code_snips`, `clips`, `wpm`.
- `KeyTrack_ExcludeWindow(substring)`, `KeyTrack_UnexcludeWindow`,
  `KeyTrack_LoadExclusions`, `KeyTrack_IsExcluded(winName)` (also excludes
  credential-style windows via `KEYTRACK_SENSITIVE_PATTERN`).
- `KeyTrack_Snapshots(winId, limit)`, `KeyTrack_TopHotkeys(winId)`,
  `KeyTrack_RecentClips(limit, winId)`, `KeyTrack_StatusLine()`.
- **Privacy: OFF by default; never records excluded/sensitive windows.**

### 4.7 `SnapshotEngine.ahk` — 5-min desktop snapshots
`Snap_Start/Stop/Toggle/IsOn`, `Snap_RunCycleNow(note)`, `Snap_CaptureWindow`,
`Snap_MakeBinary(x,y,w,h)` (thresholded FindText binary), `Snap_Otsu`,
`Snap_RenderBinary`, `Snap_FileToBinary(path)`, `Snap_CropToFile`, `Snap_BinaryToAscii`.
Every visible window per cycle gets a raw PNG + base64 + a FindText-compatible
1-bit pattern, all keyed to a `snap_entry` row.

### 4.8 `TrackingDashboard.ahk` — coordinator + UI
`Track_InitAll`, `Track_StartAll/StopAll/ShutdownAll`, `Track_AutoStart`
(restores last running trackers), `Track_PersistRunState`, `Track_BuildTab(g)`,
`Track_RefreshStatus`, `Track_SyncCheckboxes`, `Track_SnapNow`,
`Track_OpenElements`, `Track_OpenWindowTimes`, `Track_OpenMousePanel`,
`Track_OpenKeyHistory`, `Track_OpenResearch`, `Track_ExportAll`,
`Track_PrunePrompt`, `Track_OpenDataFolder`. Most `Track_*Open*` open a detail
popup panel.

---

## 5. Self-learning (v9) — two parallel implementations

Both learn the user's behavior and predict/auto-complete repeated sequences.
They are **alternatives with overlapping goals**; the app ships one per v9
variant file.

### 5.1 `VisionScout.ahk` (deepseek build)
Entry: `VisionScout_Init()`, `VisionScout_BuildTab(g)`, `VisionScout_AutoStart()`,
`VisionScout_Shutdown()`. Control: `VS_Start/Stop/Toggle/IsOn`.
- **Visual scraping**: `VS_ScanScreen(scope := "window" | "screen")` segments the
  screen into high-contrast regions and captures a FindText pattern per region →
  `vs_element` table (with abs + rel coords, score, tier).
- **Usage capture**: passive mouse-edge poll + `InputHook` + window poll →
  `vs_action` stream; compressed to step tokens (`click@<id>`, `type`, `hk:^c`,
  `key:{Enter}`, `win:<name>`).
- **Promotion**: `VS_BumpElement`, `VS_ApplyPromotion`, `VS_RecapturePattern`,
  `VS_ExportPromoted` (copies promoted elements into the Patterns tab).
- **Sequence learning**: `VS_MineSequences` (n-gram mining), `VS_FindContinuation`,
  `VS_ArmOffer` (tooltip), `VS_ContinueHandler` (Win+CapsLock),
  `VS_ExecuteContinuation`, `VS_ClickElement` (pattern → relative → abs coords).

### 5.2 `UsagePatternPredictor.ahk` (parallel build)
Entry: `UsagePredictor_BuildTab(guiObj)`. State globals `g_UP*`. Learns from the
current machine: samples the desktop at a coarse grid, refines contrast regions,
creates bounded FindText patterns **into the shared `element` registry**, and
builds a local **n-gram transition model** (min support `g_UPMinSupport`, min
confidence `g_UPMinConfidence`). Clicks/dwell promote regions. **Win+CapsLock**
accepts a prediction. Literal typed text is **off by default** and subject to
KeyTracker's sensitive-window rules.

> If you are driving the app, prefer **one** learner at a time. Both register
> `#CapsLock` (Win+CapsLock) as the accept hotkey and both write usage data.

---

## 6. Research & recovery

### 6.1 `ResearchPipeline.ahk`
Databased browser research loop: query → harvest links → open each → capture an
insight. Context globals `g_ResQueryId`, `g_ResLinkId`, `g_ResBrowser`.
- `Research_Search(text, engine := "google")` — store query + open browser.
- `Research_OpenSearchUrl`, `Research_SearchUrl`, `Research_UrlEncode`.
- `Research_CaptureLinks` (harvest result URLs from screen OCR or clipboard),
  `Research_LaunchNext()` (open next pending link), `Research_AddInsight(insight)`,
  `Research_Report()`.
- Each is a **workflow action** in the main app (`Research Search`,
  `Research Capture Links`, `Research Launch Next`, `Research Add Insight`).

### 6.2 `SnapshotRecovery.ahk`
Recover the source page of a snapshot three ways:
- Live: `BrowserUrl_FromWindow(hwnd, exe)` reads the browser address bar from
  the accessibility tree.
- Retroactive: `SnapClue_FromFilename(path)` / `SnapClue_FromTitle(raw)` /
  `SnapClue_Tidy` / `SnapClue_UrlsFromText`.
- Corroborating: `ChromeHist_Snapshot(force)` (copies the locked Chrome History),
  `ChromeHist_Search(text)`, `ChromeHist_Around(tsText)`, `ChromeHist_Time`.
- UI + query glue: `SnapRec_BuildTab(g)`, `SnapRec_Search`,
  `SnapRec_Selected`, `SnapRec_OpenUrl`, `SnapRec_OcrSelected`,
  `SnapRec_HistoryMatch`, `SnapRec_EntriesForPaths`, `SnapRec_BackfillStart`.

### 6.3 `Everything3Client.ahk`
`class Everything3SDK` wraps `lib\Everything3.dll` (Everything 1.5).
`__New(dllPath)`, `Load()`, `EnsureConnected()`, `Reconnect()`,
`Search(searchText, maxResults)` → `{Ok, Results[], ViewportCount, Query, Error}`,
`ReadVersionText`, `Close`. Everything query syntax applies.

---

## 7. Vendored utility libraries

- **`SQLiteDB.ahk`** — main-app SQLite wrapper (class `SQLiteDB`). `OpenDB`,
  `CloseDB`, `Exec`, `SetTimeout`, `GetTable`, `_Table.GetRow/Next/Reset`,
  `Prepare`/`_Prepared.Bind/Step/Reset/Free`, `AttachDB`, `DetachDB`,
  `LastInsertRowID`, `TotalChanges`, `Changes`, `SQL`, `Version`,
  `ErrorCode/ErrorMsg/ExtErrCode`, `CreateScalarFunc`, `EnableLoadExtension`,
  `LoadExtension`, `EscapeStr`. Binds via single-entry Maps
  (`Map("Text", v)`, `Map("Int", v)`, `Map("Blob", buf)`, …). Uses `sqlite3.dll`.
- **`JSON.ahk`** — `JSON.Load(text)` / `JSON.Dump(value)` (cocobelgica JSON).
- **`ImagePut.ahk`** — image conversion: `ImagePutBase64`, `ImagePutBitmap`,
  `ImagePutBuffer`, `ImagePutClipboard`, `ImagePutCursor`, `ImagePutFile`,
  `ImagePutScreenshot`, plus `ImagePutWindow`, `ImagePutHBitmap`, … (iseahound).
- **`Gdip_All.ahk`** — full GDI+ (bitmaps, graphics, text, save).
- **`AHKv2_Screenshot_Tools.ahk` / `AHKv2_Screenshotter.ahk` /
  `AHKv2_Screenshotter_Quickstart.ahk`** — screenshot helpers (see §2.4).
- **`_cfg.ahk`, `_guibase.ahk`, `_tab_main.ahk`, `_tab_opts.ahk`, `_tab_out.ahk`,
  `_get_c_function_header.ahk`, `ahk\CreateImageButton.ahk`** — internals of the
  standalone **`ahkmcodegen`** MCode generator (root `ahkmcodegen.ahk`); not used
  for runtime automation.

---

## 8. How to include a library (from any script)

Quoted include next to the script is the least surprising:

```ahk
#Requires AutoHotkey v2.0
#Include "C:\Users\Don\Desktop\aAutomateMacro\lib\Acc.ahk"
```

For the tracking stack, replicate the main app's include order:

```ahk
#Include lib\TrackSQLite.ahk
#Include lib\TrackUtil.ahk
#Include lib\TrackingDB.ahk
#Include lib\PixelCanvas.ahk
#Include lib\WindowTracker.ahk
#Include lib\MouseTracker.ahk
#Include lib\KeyTracker.ahk
#Include lib\SnapshotEngine.ahk
#Include lib\ElementAutomation.ahk
#Include lib\ElementViewer.ahk
#Include lib\ResearchPipeline.ahk
#Include lib\TrackingDashboard.ahk
#Include lib\Acc.ahk
#Include lib\AppLearner.ahk
```

---

## 9. Common automation recipes (cheat sheet)

| Goal | Use | Example call |
|---|---|---|
| Click an image/button | FindText | `ok := FindText(&x,&y,0,0,A_ScreenWidth,A_ScreenHeight,0.1,0.1,pattern)` then `Click(ok[1].mx, ok[1].my)` |
| Read text in a rectangle | OCR | `r := OCR.FromRect(100,100,400,200,"en-US",1.5)` → `r.Text` |
| Wait for a word to appear | OCR | `OCR.WaitText("Complete", 10000, (*) => OCR.FromRect(...))` or `OCR.WaitText` |
| Find a control robustly | Acc | `el := Acc.ElementFromHandle("A"); el.FindElement({Name:"Save"})` |
| Click a named tracked element | ElementAutomation | `Element_ClickByName("SaveButton", "Left", 1)` |
| Learn & drive an app | AppLearner | `AppMap_LearnWindow(hwnd, opts)` → `AppExec_Run(appId, "focus`nclick Save`n")` |
| Have an LLM drive an app | AppLearner | `Ollama_GenerateScript(appId, "goal", "llama3", "http://localhost:11434", &err)` |
| Replay a mouse path | MouseTracker | `MouseTrack_Replay(snapId, 1.0, 0, false)` |
| Extract click hotspots | MouseTracker | `MouseTrack_ExtractFeatures(winId)` → element candidates |
| Capture a window (rendered) | Screenshot tools | `CaptureRenderedActiveWindow(false)` / `Gdip_RenderedBitmapFromHWND(hwnd)` |
| Research loop | ResearchPipeline | `Research_Search("query")` → `Research_CaptureLinks()` → `Research_LaunchNext()` → `Research_AddInsight("...")` |
| Find a file by Everything query | Everything3Client | `sdk.Search("*.ahk", 100)` |
| Self-learn sequences | VisionScout | `VS_Start()` … repeat a routine … tooltip → Win+CapsLock |
| Store/read a small setting | TrackingDB | `TrackDB_MetaSet("k","v")` / `TrackDB_MetaGet("k","")` |

---

## 10. Gotchas an agent must know

1. **v1 vs v2**: `Vis2.ahk` is v1-only; every other file in `lib\` is v2.
2. **Do not rename the two SQLite wrappers** (`SQLiteDB` vs `TrackSQLite`) — name
   collision is a load error.
3. **`TrackDB()` must be opened** (`TrackDB_Init`) before any `TrackDB_*` call;
   the trackers do this themselves on start.
4. **InputHook `I1`** already excludes the script's own `Send` output; MouseTracker
   and VisionScout also set a `Replaying` flag so replay/auto-run never pollutes
   the usage history.
5. **Coordinates**: screen-relative by default (`CoordMode Mouse/Pixel = Screen`
   in the main app). Tracking prefers window-relative `rel_*` 0–1 values.
6. **FindText tolerances** (`err1`/`err0`) and **display scaling** both affect
   match reliability; recapture patterns after a DPI change.
7. **OCR needs** `WindowsOCR.ps1` beside the script and an installed Windows OCR
   language pack; **Vis2 needs** the `bin\` Tesseract payload.
8. **Everything3.dll** and **sqlite3.dll** must match the interpreter bitness
   (use 64-bit AHK with 64-bit DLLs).

---

*Additional upstream docs in this folder: `AHKv2_Screenshot_Tools_README.md`,
`Vis2_README.md`. The master project guide is the root `README.md`.*

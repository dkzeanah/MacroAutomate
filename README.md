# MacroAutomate

AutoHotkey v2 automation toolkit: `macroautomerv7.ahk` is the main app (visual `FindText` pattern matching, Windows OCR, SQLite-backed workflow/spool storage, behavior tracking). The root also ships seven reusable automation components plus their bundled dependencies — five include directly into an AutoHotkey v2 script, Vis2 requires AutoHotkey v1, and ahkmcodegen is a standalone v2 development tool.

## Repository structure

| Path | Contents |
|---|---|
| root `*.ahk` | Main app (`macroautomerv7.ahk`) and the directly-includable libraries (`FindText.ahk`, `OCR.ahk`, `SQLiteDB.ahk`, `Acc.ahk`, `Vis2.ahk`, `AHKv2_Screenshotter.ahk`, `ahkmcodegen.ahk`). |
| `lib/` | Supporting AHK modules — the behavior-tracking subsystem (`WindowTracker`, `MouseTracker`, `KeyTracker`, `SnapshotEngine`, `TrackingDB`, `TrackingDashboard`, …), screenshot tools, `Gdip_All`, `ImagePut`, `JSON`, and ahkmcodegen's `_*.ahk` helpers. |
| `test/` | Everything not part of the shipping app: `tools/` (loose utilities), `variants/` (alternate copies of libraries), `macroautomator-history/` (older `MacroAutomator_*`/`macroautomerv7` versions), plus sample project folders and demo data. |
| `*.md`, `*_GUIDE.txt` | Documentation — this file, [`TRACKING_GUIDE.md`](TRACKING_GUIDE.md), [`SPOOL_WORKFLOW_GUIDE.txt`](SPOOL_WORKFLOW_GUIDE.txt), [`VISUAL_GUIDE.txt`](VISUAL_GUIDE.txt), and the feature/action guides. |

## Local-only files (NOT tracked in git — supply your own after cloning)

Binaries, generated databases, screen captures, and per-machine runtime data are deliberately excluded by [`.gitignore`](.gitignore) to keep the repo lean and avoid committing private data. A fresh clone will therefore be missing the items below; the app recreates most of them on first run, but the native/vendored dependencies must be supplied manually:

| Ignored path / pattern | What it is | How to restore |
|---|---|---|
| `sqlite3.dll` | Native SQLite library required by `SQLiteDB.ahk` and all DB features. **Must match your AutoHotkey architecture** (use 64-bit DLL with 64-bit AHK). | Download from [sqlite.org](https://www.sqlite.org/download.html) and place in the repo root. |
| `*.zip` | Vendored library source archives (e.g. `Acc-v2-main.zip`, `ahkmcodegen-main.zip`). | Re-download from each library's upstream if you need the full source. |
| `bin/` | OCR engine tools and trained data used by `Vis2.ahk` (Tesseract, `*.traineddata`). | Supply the Vis2/Tesseract `bin` payload. |
| `*.db` | Standalone databases (`chinese_dictionary.db`, `globalcoder.db`). | App- or feature-specific; regenerate or copy from your working machine. |
| `data/` | Live app runtime data — workflow patterns, sequences, spools, OCR logs, and the local `macroauto.sqlite`. **May contain private data; never commit.** | Recreated by the app; the app migrates legacy `.ini` files automatically. |
| `logs/`, `Screenshots/`, `FindTextCaptures/`, `MacroData/`, `Patterns/` | Runtime output — logs, screen captures, saved pattern images. | Regenerated as you use the app. |
| `*.png`, `*.jpg`, `*.bmp`, `*.pdf` | Captured images and personal documents. | Local only. |
| `*.bak`, `*.bak-*` | Editor/script backups. | Local only. |
| `.claude/` | Claude Code local session settings. | Machine-specific; not needed to run the app. |
| `S-1-5-*` | Windows SID-named artifacts. | Junk; safe to ignore. |

## Component map

| Component | Runtime | Use it as | Main dependencies |
|---|---|---|---|
| [`SQLiteDB.ahk`](SQLiteDB.ahk) | AutoHotkey v2 | Included class | `sqlite3.dll` |
| [`Acc.ahk`](Acc.ahk) | AutoHotkey v2 | Included class/library | Windows MSAA (`oleacc.dll`) |
| [`FindText.ahk`](FindText.ahk) | AutoHotkey v2 | Included function/class or standalone capture GUI | Windows GDI APIs; no OCR engine |
| [`AHKv2_Screenshotter.ahk`](AHKv2_Screenshotter.ahk) | AutoHotkey v2 | Included function library | `lib\AHKv2_Screenshot_Tools.ahk` |
| [`OCR.ahk`](OCR.ahk) | AutoHotkey v2 | Included Windows OCR class | `WindowsOCR.ps1` and Windows 10/11 OCR language support |
| [`Vis2.ahk`](Vis2.ahk) | AutoHotkey v1.1 | Included v1 library | root `Gdip_All.ahk`, `ImagePut.ahk`, `JSON.ahk`, and `bin\` OCR tools/data |
| [`ahkmcodegen.ahk`](ahkmcodegen.ahk) | AutoHotkey v2 | Run as a standalone GUI tool | `_cfg.ahk`, `_guibase.ahk`, `_tab_*.ahk`, `_get_c_function_header.ahk`, `lib\ahk\CreateImageButton.ahk`, a C compiler, and GNU assembler |

## Requirements and folder layout

1. Install AutoHotkey v2 for SQLiteDB, Acc, FindText, Screenshotter, OCR, and ahkmcodegen.
2. Install AutoHotkey v1.1 if you intend to use Vis2. Vis2 uses v1 command syntax and cannot be included in a v2 process.
3. Keep each component beside its dependencies. The bundled files use paths relative to `A_ScriptDir` or the including file.
4. Run automation that controls elevated applications at the same integrity level as those applications.
5. Use 64-bit AutoHotkey with the bundled `sqlite3.dll` if that DLL is 64-bit; DLL and interpreter architectures must match.

For a project stored in another folder, either copy the needed library and dependencies into that project or use an absolute include:

```ahk
#Requires AutoHotkey v2.0
#Include "C:\Users\Don\Desktop\aAutomateMacro\Acc.ahk"
```

Angle-bracket includes such as `#Include <FindText>` require the file to be in an AutoHotkey `Lib` search directory. Quoted includes are less surprising for this collection.

## Run the integrated demonstration

Launch with AutoHotkey v2:

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" ".\All_Libraries_Demo.ahk"
```

The demo is intentionally interactive. Potentially disruptive actions—clicking an accessibility element, rendered-window capture, waiting for a screen change, and cloud image identification—are only performed after you choose them.

The demo covers:

- SQLite execution, callbacks, result tables, prepared statements and typed binding, transactions, attach/detach, escaping, row/change counters, a scalar `REGEXP` function, and optional extension loading.
- Accessibility lookup by active window and mouse point, properties, tree search, paths, enumeration, highlighting, event hooks, actions, and the AccViewer.
- FindText capture, pattern search, wait-for-appear/disappear, sorting/OCR of matches, screenshots, screen hashes, colors, range tips, and saved captures.
- Whole-screen, active-window, client-area, rendered-window, and rendered-client screenshots.
- Windows OCR is exercised by MacroAutomator's OCR actions and its full-screen yellow-box template.
- Vis2 OCR and image identification through the included v1 demo.
- The complete ahkmcodegen GUI workflow.

Run the demo's non-interactive smoke test from PowerShell:

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut ".\All_Libraries_Demo.ahk" --self-test
```

## SQLiteDB.ahk

`SQLiteDB` is a thin AutoHotkey v2 wrapper over the SQLite C API. It loads `sqlite3.dll` from the directory of the top-level script. To use another DLL, create `SQLiteDB.ini` next to the top-level script:

```ini
[Main]
DllPath=C:\path\to\sqlite3.dll
```

### Basic database use

```ahk
#Requires AutoHotkey v2.0
#Include "SQLiteDB.ahk"

db := SQLiteDB()
if !db.OpenDB(A_ScriptDir "\example.db")
    throw Error(db.ErrorMsg)

try {
    if !db.Exec("CREATE TABLE IF NOT EXISTS people (id INTEGER PRIMARY KEY, name TEXT)")
        throw Error(db.ErrorMsg)

    name := "O'Reilly"
    db.EscapeStr(&name) ; name now contains a safely quoted SQL literal
    if !db.Exec("INSERT INTO people(name) VALUES (" name ")")
        throw Error(db.ErrorMsg)

    if !db.GetTable("SELECT id, name FROM people ORDER BY id", &table)
        throw Error(db.ErrorMsg)

    for row in table.Rows
        MsgBox row[1] ": " row[2]
} finally {
    db.CloseDB()
}
```

Prefer prepared statements instead of string concatenation for application data:

```ahk
db.Prepare("INSERT INTO people(name) VALUES (?)", &statement)
statement.Bind([Map("Text", "Ada Lovelace")])
statement.Step() ; SQLITE_DONE is represented by -1/EOR in this wrapper
statement.Free()

db.Prepare("SELECT id, name FROM people", &statement)
Loop {
    status := statement.Next(&row)
    if status = -1
        break
    if !status
        throw Error(statement.ErrorMsg)
    ; row is an Array; statement.ColumnNames contains its column names.
}
statement.Free()
```

`Bind()` accepts one single-entry `Map` per positional parameter: `Map("Blob", buffer)`, `Map("Double", value)`, `Map("Int", value)`, `Map("Int64", value)`, `Map("Null", 0)`, or `Map("Text", value)`. Plain `{Text: value}` objects are not enumerable by this wrapper and will fail.

### Public operations

- Connection and execution: `OpenDB`, `CloseDB`, `Exec`, `SetTimeout`.
- Results: `GetTable`, `_Table.GetRow`, `_Table.Next`, `_Table.Reset`.
- Prepared statements: `Prepare`, `_Prepared.Bind`, `_Prepared.Step`/`Next`, `_Prepared.Reset`, `_Prepared.Free`.
- Multiple databases: `AttachDB`, `DetachDB`.
- Metadata: `LastInsertRowID`, `TotalChanges`, `Changes`, `SQL`, `Version`.
- Error handling: `ErrorCode`, `ErrorMsg`, `ExtErrCode`.
- Extensions/functions: `CreateScalarFunc`, `EnableLoadExtension`, `LoadExtension`. Only load trusted native extensions with the same architecture as the interpreter.
- Quoting: `EscapeStr`. Prepared statements are still the preferred choice.

Check every Boolean return. On failure, inspect `ErrorCode`, `ExtErrCode()`, `ErrorMsg`, and `SQL`.

## Acc.ahk

Acc exposes Microsoft's Active Accessibility (MSAA) tree as array-like AutoHotkey v2 objects.

```ahk
#Requires AutoHotkey v2.0
#Include "Acc.ahk"

windowElement := Acc.ElementFromHandle("A")
MsgBox windowElement.RoleText "`n" windowElement.Name

button := windowElement.FindElement({
    RoleText: "push button",
    Name: "Save",
    matchmode: "Substring",
    casesensitive: false
})
button.Highlight(1500, "Lime", 3)
button.DoDefaultAction()
```

Starting points:

- `Acc.ElementFromHandle(winTitleOrHwnd, idObject := "Window")`
- `Acc.ElementFromPoint(x?, y?)`
- `Acc.ElementFromChromium(winTitleOrHwnd)`
- `Acc.ElementFromPath("1,2,p1,button", root?)`
- `Acc.GetRootElement()`

Elements support indexed paths (`element[2, 1]`), enumeration (`for child in element`), and properties such as `Name`, `Value`, `Role`, `RoleText`, `State`, `StateText`, `Location`, `Parent`, `Focus`, `Selection`, `Length`, `Exists`, `ControlID`, and `WinID`. Some properties are not implemented by every application; use `try` around optional properties.

Tree/query operations include `FindElement`, `FindElements`, `WaitElement`, `WaitElementExist`, `WaitNotExist`, `Normalize`, `ValidateCondition`, `GetPath`, `Dump`, and `DumpAll`. Condition objects support AND objects, OR arrays, `not`, match modes, case sensitivity, scope, traversal order, indexes, and partial locations.

Actions and navigation include `Select`, `DoDefaultAction`, `Click`, `ControlClick`, `Navigate`, `HitTest`, `Highlight`, and `ClearHighlight`. Prefer `DoDefaultAction()` when supported; clicking coordinates is more fragile.

Register an event and keep the returned hook object alive:

```ahk
hook := Acc.RegisterWinEvent(OnForeground, Acc.Event.System_Foreground)

OnForeground(element, info) {
    ToolTip "Foreground hwnd: " info.WinID
}
```

Run `Acc.ahk` directly to open AccViewer. The integrated demo launches it in a separate process because closing the bundled viewer exits its owning script.

## FindText.ahk

FindText turns a small captured image into a compact text pattern and searches screen pixels for that pattern. It is image/pixel matching, not natural-language OCR.

First run `FindText.ahk` directly, or call `FindText().Gui("Show")`, capture a stable target, and copy its generated pattern.

```ahk
#Requires AutoHotkey v2.0
#Include "FindText.ahk"

Text := "|<Save>*150$20.example_encoded_pattern"
results := FindText(&x, &y, 0, 0, A_ScreenWidth - 1, A_ScreenHeight - 1,
                    0.10, 0.10, Text)
if results.Length {
    first := results[1]
    FindText().RangeTip(first.x, first.y, first.w, first.h, "Lime", 3)
    Click first.mx, first.my
}
```

Each match has `x`, `y`, `w`, `h`, `mx`, `my`, and `id`. Coordinates are screen-relative.

Waiting uses the first two by-reference inputs as mode and timeout:

```ahk
mode := "wait"       ; wait or wait1 = appear; wait0 = disappear
seconds := 3
result := FindText(&mode, &seconds, 0, 0, 0, 0, 0.10, 0.10, Text)
```

Major API groups:

- Search: `FindText`, `ImageSearch`, `PicInfo`, `PicFind`, `PicLib`, `PicN`, `PicX`.
- Capture/pixels: `ScreenShot`, `GetBitsFromScreen`, `GetColor`, `SetColor`, `GetTextFromScreen`, `GetPicHash`.
- Output/inspection: `SavePic`, `ShowPic`, `ShowScreenShot`, `MouseTip`, `RangeTip`.
- Results: `Sort`, `Sort2`, `Sort3`, `Ocr` (joins the comments/IDs of matched patterns; it is not Tesseract OCR).
- Synchronization: appear/disappear mode in `FindText`, plus `WaitChange`.
- Window capture: `BindWindow`; always unbind with `BindWindow(0)` when finished.
- Coordinate conversion: `WindowToScreen`, `ScreenToWindow`, `ClientToScreen`, `ScreenToClient`.

Capture the smallest stable region possible. Avoid animated, antialiased, scaled, or theme-dependent pixels where practical, and tune `err1`/`err0` gradually.

## AHKv2_Screenshotter.ahk

This include starts GDI+, creates `Screenshots\` below the top-level script, and registers a shutdown handler. Its capture functions return the saved file path.

```ahk
#Requires AutoHotkey v2.0
#Include "AHKv2_Screenshotter.ahk"

F8::MsgBox "Saved: " CaptureWholeScreen()
F9::MsgBox "Saved: " CaptureActiveWindow()
F10::MsgBox "Saved client: " CaptureActiveWindow(true)
```

Available operations:

- `CaptureWholeScreen()`
- `CaptureActiveWindow(clientOnly := false)`
- `CaptureRenderedActiveWindow(clientOnly := false)`

Rendered capture uses undocumented `PrintWindow` flags, is slower, and presents a confirmation before use. It can capture some windows that ordinary screen copying misses, but behavior varies by application and Windows version.

For lower-level region, cursor, bitmap, HBITMAP, or save-format control, include `lib\AHKv2_Screenshot_Tools.ahk` directly and use its GDI+ functions. `AHKv2_Screenshotter_Quickstart.ahk` contains additional hotkey examples.

See the preserved upstream guide in [`AHKv2_Screenshot_Tools_README.md`](AHKv2_Screenshot_Tools_README.md) for its quickstart hotkeys, rendered-versus-unrendered capture notes, manifest, and project history.

## OCR.ahk

`OCR` is an AutoHotkey v2 wrapper around the OCR engine included with Windows 10 and Windows 11. Keep [`OCR.ahk`](OCR.ahk) and [`WindowsOCR.ps1`](WindowsOCR.ps1) together beside the top-level script. The helper captures a screen rectangle, calls `Windows.Media.Ocr`, and returns text plus relative word and line coordinates.

```ahk
#Requires AutoHotkey v2.0
#Include "OCR.ahk"

result := OCR.FromRect(0, 0, A_ScreenWidth, A_ScreenHeight, "en-US", 1.0)
MsgBox(result.Text)

for word in result.Words
    ToolTip(word.Text . " at " . word.x . "," . word.y)
```

The result exposes `Text`, `Words`, `Lines`, and `TextAngle`. Every word/line exposes `Text`, `x`, `y`, `w`, and `h`; coordinates are relative to the requested capture rectangle. `OCR.FromDesktop()` captures the primary screen. Windows profile languages are used automatically if the requested OCR language is unavailable.

MacroAutomator provides a complete visual example: insert the **Full Screen OCR → Yellow Boxes → Notification** template. It saves OCR text to `$var.fullScreenOCR`, outlines every recognized word, and displays the substituted variable.

## Vis2.ahk

Vis2 is an AutoHotkey v1.1 OCR and image-labeling library. Do not include it from a v2 script.

```ahk
#Requires AutoHotkey v1.1
#Include Vis2.ahk

#c::OCR()                         ; interactively select screen text
#f::MsgBox % OCR("test.jpg")     ; image file
#w::MsgBox % OCR("ahk_exe notepad.exe")
#i::ImageIdentify()               ; Google Cloud Vision labels
Esc::ExitApp
```

`OCR(image := "", language := "", options := "")` accepts interactive selection, `[x, y, w, h]`, a file, URL, window title, hwnd, base64 image, GDI+ bitmap, or HBITMAP. Language combinations such as `"eng+fra"` require matching `.traineddata` in both `bin\tesseract\tessdata_best` and `bin\tesseract\tessdata_fast`.

`ImageIdentify(image := "", search := "", options := "")` uses Google Cloud Vision. Store a valid key as `GoogleCloudVision=YOUR_KEY` in `Vis2_API.txt`; do not commit secrets. This feature sends image data to an external service and may incur charges. The bundled placeholder/proxy behavior should not be treated as a production credential strategy.

The lower-level `Vis2.provider.Tesseract` class exposes preprocessing, best/fast conversion, text retrieval, and cleanup. `Vis2.Graphics` provides selection areas, image overlays, subtitles, bitmaps, icons, and saves. `Vis2.Text` provides clipboard and Google-search helpers.

See the preserved original guide in [`Vis2_README.md`](Vis2_README.md), and run [`demo.ahk`](demo.ahk) with AutoHotkey v1.1 for the original OCR/image-identification demonstration.

## ahkmcodegen.ahk

ahkmcodegen is a standalone AutoHotkey v2 GUI application, not an include-safe function library. Running it immediately creates and shows its interface.

```powershell
& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" ".\ahkmcodegen.ahk"
```

Typical workflow:

1. Select a C source file.
2. Optionally select an existing AHK script that already contains a compatible generated block for update/insertion.
3. Select GCC or Clang and GNU `as`; the tool identifies them. WSL cross-compiler commands are supported from the Options tab.
4. Choose optimization/compiler/assembler flags.
5. Configure warning handling, intermediate-file retention, null-call patching, `.rdata`/`.data` merging, command logging, metadata, C function headers, and base64 line length.
6. Press **Compile**.
7. Review the compiler/assembler log and generated MCode, then copy it or use the configured auto-insertion flow.

Configuration profiles are stored in `cfg.ini` beside the top-level script. Compilation creates temporary `.s`, `.o`, listing, auxiliary, and error files beside the C source; they are removed unless **Keep intermediate files** is enabled. Back up source files before using automatic insertion.

[`sample.ahk`](sample.ahk) contains the sample MCode decoder that the GUI can copy. Generated machine code is architecture-specific and should only be executed when its source and build toolchain are trusted.

See the preserved original project guide in [`ahkmcodegen_README.md`](ahkmcodegen_README.md) for its rationale, feature history, complete sample blob/decoder, compiler sources, limitations, license, and credits.

## Documentation files

- [`README.md`](README.md): this master guide.
- [`Vis2_README.md`](Vis2_README.md): the original Vis2 guide formerly named `README.md` at the root.
- [`AHKv2_Screenshot_Tools_README.md`](AHKv2_Screenshot_Tools_README.md): the screenshot tools guide formerly named `README (2).md`.
- [`ahkmcodegen_README.md`](ahkmcodegen_README.md): the MCode generator guide formerly named `README (3).md`.
- [`Ollama_Job_Automation_Studio_README.md`](Ollama_Job_Automation_Studio_v1.2/Ollama_Job_Automation_Studio_README.md): the Ollama Job Automation Studio guide formerly named `README.md` in that project folder.

The Ollama project is separate from the seven AutoHotkey components documented here.

## Troubleshooting

- **A v1/v2 syntax error appears:** verify the interpreter. Vis2 is v1; the other six entry points are v2.
- **SQLite DLL load failure:** confirm `sqlite3.dll` exists, matches interpreter architecture, and is beside the top-level script, or configure `SQLiteDB.ini`.
- **Screenshot include not found:** retain `lib\AHKv2_Screenshot_Tools.ahk`, or change the include to a valid quoted path.
- **Vis2 OCR returns nothing:** verify the Tesseract executable, Leptonica utility, and requested language data under `bin\`.
- **Windows OCR returns nothing:** keep `WindowsOCR.ps1` beside the top-level v2 script, run in an interactive Windows session, and confirm the requested Windows OCR language pack is installed.
- **Acc cannot see Chromium content:** allow `ActivateChromiumAccessibility` to run; some apps expose limited or custom accessibility trees.
- **FindText misses at different scaling:** use consistent DPI/display scaling, recapture the target, narrow the region, and retune error tolerance.
- **ahkmcodegen cannot identify tools:** select valid compiler/assembler executables and ensure any WSL cross-tool names are installed and callable.

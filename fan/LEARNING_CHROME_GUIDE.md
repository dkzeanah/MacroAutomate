# Learning, Chrome and Study

## One Learning tab

**Learning** now combines App Learner, Vision Scout and Usage Predictor in one
workspace. There is one window selector, collection row, search/filter, results
table, explanation area and set of review/reuse actions. There is no learner
sub-view selector. Legacy page IDs 16 and 17 redirect to this same page.

1. Choose an application window. **Map app controls** takes one explicit scan of
   its Win32 controls, accessible controls, menus, visual patterns and OCR text.
   It brings that selected application forward. It does not simulate opening
   menus. Chrome targets are routed to Chrome Learning instead of the old
   executable/class-wide app map.
2. Enable **Watch visual targets** and/or **Learn usage sequences** while doing
   one representative task. These existing recorders observe applications as you
   use them; the window selector scopes manual captures, not the recorders.
   **Options** exposes the usage scan interval and its existing optional literal
   typing setting. Sensitive-window exclusions remain in effect.
3. **Stop both**, then **Refresh results**. The shared table contains interface
   maps, visual candidates, usage candidates and repeated sequences from both
   recorders. Search and the source filter narrow the same results table.
   The review is bounded to recent candidates and high-support sequences; it is
   not an exhaustive export of all tracking records.
4. Select a result. The explanation shows its source, state, uncertainty and how
   to use it. Usage frequency and promotion are distinct from verification.
5. For visual candidates, **Review live** opens the existing test/certify
   workflow. **Export certified patterns** puts certified targets into Patterns
   for use in Workflow. For other spatial records, Review live only previews
   retained coordinates; it does not establish a fresh match or click anything.
6. **Copy reference** copies an AppDSL reference, pattern or sequence as
   appropriate. **App script tools** is scoped to the selected interface result's
   app and offers explicit reviewed execution, Stop, the DSL guide and app
   instructions. **Evidence / lessons** opens the existing evidence ledger and
   rehearsals. Rehearsing a stored example does not validate the original app.

The underlying engines, data tables, recorded evidence, certification rules and
existing acceptance hotkeys remain separate. The GUI combines their operation
and review without pretending that their observations mean the same thing.

## Dedicated Chrome Learning

This tab brings the existing local Chrome Page Learner into the main app. It
works with native visible Chrome windows and does not require the job-specific
Chrome extension, remote-debugging mode or a new browser profile.

**Follow focused Chrome window** is enabled initially. When a Chrome window
gains focus, Fan selects Chrome Learning in the background and updates its
target. It never shows/activates Fan, starts Study or enters browser input.
The separate **Automatically learn readable page content** switch is enabled
by default and remembered.

After a page settles for 3.5 seconds and input pauses for at least 1.2 seconds,
Fan's Python worker reads the visible document through the existing native page
probe in a separate native process so the GUI stays responsive. It keeps useful text and reference links, excludes editable fields and
browser chrome, and skips internal/account/input pages without enough readable
material. This is local, observed evidence: no screenshot, OCR, remote model or
browser input is needed. Off-screen text and inaccessible media aren't inferred.

Reads are at least 15 seconds apart, triggered by browsing activity, with a
five-minute fallback for pages changing without input. Unchanged content is
deduplicated per profile and native window. Scrolling to new readable material
creates a new observation with a short explanation of what changed.

The review selector defaults to **Current window: new only**. Select
**Current profile: new only** to review that profile's other windows. Entries are
marked **NEW** and distinguish automatic text from screenshots. Selecting one
loads its text, links, summary and original profile/window/URL/time. The text
review pane uses the screenshot space for automatic entries. **Reviewed -> next
new** remembers progress and advances the queue. The unread filter runs before
the 100-entry display limit, so reviewing recent entries reveals older unread
ones. Other scope choices show the latest 100 historical entries per filter.

The window selector shows the current page title and native HWND. Each observed
window gets a fresh session identity, together with its process ID. A window
destruction event invalidates that identity so a reused HWND does not inherit
the previous window's label. Different windows remain separate even when Chrome
uses the same process for them.

Profiles are detected automatically from each window's Windows shell relaunch
command (including its profile directory), with an exact Chromium taskbar ID
fallback. Chrome's local `Local State` supplies the friendly name. Names are
only for display: the normalized full profile path is the stored profile key.
Duplicate friendly names, shared processes and matching page titles do not
combine profiles. Custom user-data roots come from window/process metadata or
Chrome policy. No extension, remote debugging, account sign-in or manual label
is required. Detection retries automatically; unavailable or ambiguous identities
stay isolated by window without guessing. **Detect again** is optional.

A native integer window token keeps the window session stable across Fan reloads
and disappears when Chrome destroys the window. Captures retain immutable
profile/path/window attribution. Older unlabeled captures are preserved as
legacy records rather than retrospectively attributed to a guessed profile.

New tracking, passive interface discovery, App Learner maps, visual elements and
usage sequences use the profile and window scope too. Sequence buffers reset
when crossing Chrome windows, and predictions are scoped to their source.
Existing globally collected records remain historical evidence of unknown
profile provenance. Explicit **Add text to Study** publishes the selected evidence
to the shared Study library with its original profile/window provenance; it does
not silently import all browsing into Study.

1. Focus the Chrome window you want. Fan automatically selects it and its profile
   and learns changed readable content after you pause.
2. **Capture visible page** deliberately takes a fresh viewport observation.
   Chrome's existing URL/schema reuse cache is not profile-scoped, so this
   interface does not reuse a capture from another window through that cache.
   Capture/get/image/resolve requests run in a separate native worker; the main
   GUI remains responsive. No model call is made by this interface.
3. Select a saved capture. **Current window** separates this window’s records. **Current profile**
   reviews that profile’s windows. **All profiles / windows** provides an explicit
   combined history, retaining each record’s original attribution. The existing standalone Page Learner still exposes captures made
   before the new window/session metadata was available.
4. Search its elements and use the 100-result paging controls. Select an element
   to inspect its observed label, role, OCR, link evidence, pattern status and
   retained image/crop. A screenshot covers a viewport, not hidden menus or an
   entire scrolled document.
5. **Verify live target** uses the existing live URL/control/geometry checks and
   sends no click. A capture from another window session is refused. If that
   original session is gone, take a fresh capture of the desired live window.
6. **Copy observed text** copies the selected retained description/text/link.
   **Add text to Study** imports only that selected evidence, with the captured
   page's original URL, label and session provenance. It does not import the
   currently selected window's identity into an older observation, and it does
   not verify an answer automatically.

## How Study works, including the browser workflow

**Study library** is the source and answer memory. Import PDFs, notes or selected
browser evidence. The answer engine checks, in order:

1. An exact previously verified answer.
2. A compatible similar verified question (a provisional reuse).
3. Relevant local passages and concept relationships.
4. Optional DeepSeek fallback when enabled and configured.
5. An explicit unresolved result when support is insufficient.

Local deductions and model answers remain candidates for review. Check the
supporting passages and source, correct the answer, verify it deliberately,
then use spaced review or export. Browsing/searching alone does not turn a page
into a trusted fact or populate Study with everything on screen.

**Live Portal** is the original Chrome study/automation workflow. It watches a
separately pinned Chrome window, perceives a question through accessibility,
OCR or vision, and uses the same Study answer engine. Choose the window using
the Live Portal picker or Ctrl+Shift+U, then start with **observe/suggest**.
The focus guard checks that pinned target before input. **Fill** enters an
answer; **Submit** additionally requires the existing explicit auto-submit
setting. Ctrl+Shift+Esc aborts. The new Chrome focus follower does not change
those modes, start a session, repin the portal or grant input permission.

The practical research route is: browse/search in Chrome, deliberately capture
the relevant viewport, inspect the retained evidence, add useful text to Study,
review answers against sources, then use the separately controlled portal
workflow if needed. **How Study works** in Chrome Learning explains this inside
the GUI and links to both Study pages.

## Layout and validation

Learning and Chrome Learning have explicit resizing rather than inferred
AutoFlow anchors. The real-control test checks bounds and pairwise overlaps at
860×760, 884×780, 1040×780 and 1500×950 client sizes. Lists, details and screenshots
share the remaining height; actions stay above the status bar. Secondary script
and Study-help windows also resize their content above their button rows.

`FanGui_Test.ahk /background` constructs the actual controls with a temporary
database and tests merged result sources, profile/window attribution, stale
capture rejection and Study source provenance. It does not display placeholder
pages or start the app's collectors. `FanWorkspace_Test.ahk` checks navigation,
aliases, both interface modes and Tab/Shift+Tab behavior. The native bridge worker
uses only the existing local page learn/get/image/resolve APIs.


Profile identity references: [Windows per-window shell properties](https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shgetpropertystoreforwindow)
and [Chromium profile taskbar identity](https://chromium.googlesource.com/chromium/src/+/refs/heads/main/chrome/browser/shell_integration_win.cc).


## Media Intel

Choose a video with **Browse**, then **Analyze video (local)**. A previously
selected job is not required. The existing Cutline Python analyzer supplies
shots, cuts, brightness and motion metrics; preview frames support the existing
timeline, JSON/report export, contact sheet and clip actions. The worker finds
an installed Python with OpenCV/NumPy automatically, including when Cutline's
own `.venv` is absent. This path needs neither a media API service nor an API key.
The selected path is remembered.

**Describe content (DeepSeek)** extracts timestamped frames and reuses Fan's
existing vision provider, credentials, cost cap and timeline normalization.
**Describe saved job** reuses saved frames instead of extracting them again.
These provide semantic descriptions; local shot detection doesn't claim to
understand speech or explain actions. Both paths run outside the GUI with
progress, complete error details and cooperative cancellation. FPS, frame limit,
batch size and prompt are remembered. FPS is reduced automatically when needed
to sample the whole duration within the frame cap. FFmpeg is auto-detected for extraction and
exports; its existing path override remains available.

The shared FFmpeg command wrapper now preserves literal `%` characters. Windows
batch expansion of `%0` inside `%06d` previously corrupted frame filenames.
The wrapper also preserves Unicode paths with UTF-8 command files.
Contact sheets now use the actual stored frame paths, including Cutline previews
and scene extraction, rather than assuming one filename convention.

Development validation uses temporary stores and a generated scene-change video.
The GUI integration test also runs a disposable loopback provider for semantic
analysis; it does not spend a real API key. Atlas overview/pack calls were attempted
through the installed gateway but returned HTTP 500; the selected shared map also
had no usable project index here. No shared Atlas or Cutline engine source was
modified; these adapters reuse their existing APIs/modules.

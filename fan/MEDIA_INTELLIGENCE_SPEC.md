# Media Intelligence — Feature Ledger

**Target:** `fan/MacroAutomator.ahk`, **tab 21 "Media Intel"**.
**Modules:** `lib/MediaLLM.ahk`, `lib/MediaPipeline.ahk`, `lib/EnvIntel.ahk`,
`fan/Tabs/Tab_21_MediaIntel.ahk`.
**Provider:** DeepSeek Flash (`deepseek-flash`) via the shared StudyLLM
credential/cost plumbing. **Deps:** FFmpeg/ffprobe (for video); Windows OCR +
Acc + GDI+ (already in the build).
**Legend:** `[x]` implemented + unit-tested, `[~]` implemented, needs live
validation, `[ ]` planned.

DeepSeek Flash understands images, not video, so video is processed by sampling
frames and sending timestamped batches to the vision model — the architecture in
the reference brief.

## 1. Programmatic video/media processing  (MediaPipeline.ahk + MediaLLM.ahk)

- [x] **Decode + sample** with FFmpeg: fixed-FPS sampling (`Media_ExtractFrames`)
      and scene-change sampling with real `pts_time` timestamps
      (`Media_ExtractSceneFrames`). Frame count is bounded (`max frames`).
- [x] **Timestamped frames** (`Media_FrameLabel`, `ts_ms`) so the model can place
      events in time. A pre-extract estimate is available (`Media_SamplingPlan`).
- [x] **Batch vision analysis** (`MediaLLM_Analyze` / `MediaLLM_AnalyzeJson`):
      multiple images per request (default 8, capped at 16) with per-frame
      timestamp labels; asks for JSON and parses it tolerantly
      (`MediaLLM_ExtractJson` / `MediaLLM_BalancedJson`, via `TrackJsonDecode`),
      ignoring prose and code fences.
- [x] **Timeline assembly + storage** (SQLite `media_job`/`media_frame`/
      `media_event`): events parsed from arrays or `{events:[…]}` wrappers,
      timestamps normalized from ms / seconds / `mm:ss` / `hh:mm:ss`
      (`Media_EventsFromValue`, `Media_AsMs`), stored and ordered
      (`Media_AnalyzeJob`, `Media_Timeline`).
- [x] **Exports:** timeline JSON (`Media_ExportTimelineJson`), Markdown report
      (`Media_ExportReport`).
- [x] **Cost + control:** shared session cost cap and spend counter with the
      study layer; retry/backoff on 429/5xx; `Media_CancelAll` + cancel button.
- [~] **FFmpeg resolution** (`Media_FfmpegExe`): setting → common locations →
      `where`. Found on this machine; a path override is in the tab.

**Media creation (derived artifacts):**

- [x] **Contact sheet** — tiled montage of a job's frames (`Media_ContactSheet`).
- [x] **Highlight clip** — cut `[startMs,endMs]` (stream-copy, re-encode fallback)
      (`Media_HighlightClip`).
- [x] **Chapters** — FFMETADATA chapter file from the event timeline
      (`Media_ChaptersFile`).

**Acceptance:** a video is sampled, analyzed into a stored, ordered timeline, and
exported to JSON/MD; frames become a contact sheet; an interval becomes a clip.
(Extraction/creation need FFmpeg + a key; the parsing/timeline/export/storage
logic is unit-tested headlessly.)

## 2. Environment intelligence — OCR feature map  (EnvIntel.ahk)

Turns a screen/window/image into machine-readable regions, mirroring the
reference pipeline: **layout segmentation → text OCR → semantic grouping →
structured extraction**.

- [x] **Entry points:** `Env_MapRegion`, `Env_MapWindow`, `Env_MapActive`,
      `Env_MapImage`.
- [~] **Capture + OCR:** GDI+ region capture + Windows OCR to normalized lines
      (`Env_CaptureRegion`, `Env_LinesFromOcr`). Live step; needs on-screen
      validation.
- [x] **Layout segmentation:** cluster lines into regions by vertical gap +
      horizontal overlap, thresholded below one line-height so paragraph/section
      breaks separate while wrapped lines group (`Env_Cluster`).
- [x] **Semantic grouping:** classify each region as `heading`, `button`,
      `label`, `list`, `body`, `path`, or `metric` (`Env_ClassifyRegion`).
- [x] **Structured extraction:** emit regions with role, text, absolute bounds,
      plus the pipeline-stage list (`Env_Build`); export clean JSON
      (`Env_ToJson`, `Env_ExportJson`, no image blob).
- [~] **Accessibility fusion:** for a live window, fold in named/role-typed Acc
      controls (`Env_AccControls`). Live step.
- [~] **Optional vision refine:** `Env_RefineWithVision` asks DeepSeek Flash to
      label regions (off by default; one call).
- [x] **Hotkey `Ctrl+Shift+9`** (`Env_HotMapActive`): map the active window to
      JSON, copy to clipboard + save a file. Read-only; drives no input.

**Acceptance:** a window/region/image yields a JSON feature map of roles + bounds
usable for automation or as grounding for the model. Segmentation and
classification are unit-tested on synthetic OCR lines.

## 3. UI (tab 21) & storage

- [x] Video pipeline panel: pick video, FPS / scene / max-frames / batch,
      "look for" prompt, Extract+Analyze, per-job timeline, exports, contact
      sheet, clip, chapters; ffmpeg-path setting; provider test.
- [x] Environment-intelligence panel: map active window / region / image,
      optional DeepSeek refine, regions table, export map JSON.
- Storage lives in the shared tracking DB (`media_*` tables); the DeepSeek key is
  the one in Windows Credential Manager / `DEEPSEEK_API_KEY` (shared with Study
  Assistant), never in a file.

## 4. Not yet validated / next

- [ ] End-to-end video run on a real clip (extract → analyze → timeline) and the
      derived-media outputs, on this machine's FFmpeg.
- [ ] Live screen/window feature-map accuracy pass; tune cluster/role heuristics
      on real portals.
- [ ] Larger batches / 600-image requests; request-size guards for long videos.

*This is a dual-use media/automation toolkit for owned/authorized targets (your
own recordings, apps, and screens), consistent with `AUTOMATION_SUBSYSTEM_SPEC.md`.*

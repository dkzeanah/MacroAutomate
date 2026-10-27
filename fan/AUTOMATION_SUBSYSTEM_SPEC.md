# Input-Automation Subsystem — Feature Ledger

**Target:** `fan/MacroAutomator.ahk` on Windows 11, AutoHotkey v2.
**Role:** the automation half of the Real-Time Study Assistant — it perceives a
question in a pinned window, asks the study layer for an answer, and (in an
enabled mode) enters that answer through human-paced mouse/keyboard input against
that one window.
**Relationship to the study layer:** this subsystem does **not** reimplement
answering. Perception feeds the shared `qa_item` bank; answers come from
`Study_Answer()` (verified memory → local deduction → DeepSeek fallback). This
document specifies only the *perceive → compose → act → verify* automation.
**Status:** the modules described exist in the repo
(`lib/StudyAutomation.ahk`, `lib/StudyLive.ahk`, `lib/StudyComposer.ahk`,
`fan/Tabs/Tab_19_PortalAssist.ahk`). Boxes mark design intent, not test status:
`[x]` implemented in code, `[~]` implemented but not yet validated on real
multi-monitor geometry / a live target, `[ ]` planned.

---

## 0. Authorized use & scope (read first)

This is a general input-automation engine: it drives the mouse and keyboard the
way RPA tools, UI test harnesses, accessibility software, and game bots do. It is
intended for targets **you own or are authorized to automate**:

- your own applications and web projects (incl. local/dev servers);
- a game or trivia bot playing on **your own** machine(s);
- UI test automation and demos;
- personal study tooling over material you control.

The human-paced timing and non-linear pointer paths (section 6) exist for
**reliability and natural feel** — many UIs drop or mis-handle instant,
teleported input, and a game bot or demo should look unhurried — **not** to
disguise automation from a system that is entitled to know. Out of scope, and not
a supported use of this subsystem:

- [ ] answering or submitting on a graded, proctored, or monitored assessment
      you are being evaluated on;
- [ ] defeating CAPTCHA, anti-cheat, bot-detection, or remote-proctoring systems,
      or tuning input to evade them;
- [ ] presenting automated input as a human's to any party relying on it being
      human.

The engine therefore treats CAPTCHA / proctoring / lockdown indicators as a hard
**stop**, never a puzzle to solve (section 5). Keep `submit` mode off except on
targets you own; the default mode is `suggest` (no input at all).

---

## 1. Module map

| File | Responsibility |
|---|---|
| `lib/StudyAutomation.ahk` | monitor geometry, window pinning + focus guard, perception (Acc + OCR + screenshot), question classification, dedupe, feedback detection, status overlay |
| `lib/StudyComposer.ahk` | turn a structured question + proposed answer into a verified, human-paced action plan and run it against the pinned window only |
| `lib/StudyLive.ahk` | orchestrator: the session loop, the answer bridge to `Study_Answer()`, recheck-before-input, feedback-driven learning, the "Live Portal" tab, overlay and hotkeys |
| `fan/Tabs/Tab_19_PortalAssist.ahk` | tab glue (`Tab_PortalAssist_Build` → `StudyLive_BuildTab`) |

**End-to-end cycle** (`StudyLive_Tick`, every `poll_ms`):

1. `StudyAuto_Guard()` — verify the pinned window is still focused, same tab/URL,
   not obscured. Any failure → pause, no input.
2. `StudyAuto_RegionChanged()` — skip unchanged frames (pixel signature).
3. `StudyPercept_Capture()` — Acc walk + OCR pass + screenshot of the region.
4. `StudyPercept_BuildQuestion()` + `StudyPercept_Classify()` — one structured
   `Question`, or an `unknown/review` result.
5. New question? (`StudyPercept_QFP` fingerprint) store it in `qa_item`
   (`StudyLive_StoreQuestion`) and call `Study_Answer()` for the answer.
6. `StudyLive_Recheck()` — re-validate the answer against the *current* choices
   (valid tags, selection count, units).
7. Mode ≥ `fill`? `StudyMacro_Compose()` → `StudyMacro_Run()` enters it with the
   guard re-checked before every step.
8. After a submit, `StudyPercept_FeedbackCheck()` reads portal feedback and
   records `portal-confirmed` / `disputed` through the study layer's versioned
   trail.

---

## 2. Session, display & focus control  (StudyAutomation.ahk)

- [x] Pin exactly one window by its active handle (`StudyAuto_PinFromActive`) or
      under the cursor (`StudyAuto_HotPin` / `^+u`): records `hwnd`, title, exe,
      URL and origin. `StudyAuto_RestorePin` resumes it across restarts by
      title + origin.
- [x] Re-verify the pin before every action (`StudyAuto_CheckPin`,
      `StudyAuto_Guard`): window alive, foreground, same origin; otherwise pause
      and surface the reason.
- [~] Enumerate all monitors incl. negative coordinates / mixed DPI
      (`StudyAuto_Monitors`, `StudyAuto_MonitorText`); derive the capture region
      from the pinned window (`StudyAuto_RegionFromWindow`) or a dragged
      rectangle (`StudyAuto_RegionSet`). *Needs validation on the real 3-monitor
      layout.*
- [x] Capture only the chosen region; the pinned window is the only input target.
- [x] Frame-rate / CPU bound via `poll_ms` + a change signature
      (`StudyAuto_FrameSig`, `StudyAuto_RegionChanged`) so an unchanged screen is
      not reprocessed; re-entrancy guards (`g_StudySessBusy`, `g_StudyCaptureBusy`).
- [x] Start / pause / stop / abort (`StudyLive_Start/Stop/Abort/ToggleSession`,
      `^+y`); a tripped guard sets `g_StudyPaused` and stops input until recovery.

**Acceptance:** with a window pinned, moving focus away, switching its tab, or
closing it stops all input before the next cycle and the overlay shows why.

---

## 3. Question & control perception  (StudyAutomation.ahk)

- [x] Primary signal: Windows accessibility (`Acc.ahk` on the Chromium a11y tree)
      walked for interactive controls (`StudyPercept_Walk`,
      `StudyPercept_IsControl`, `StudyPercept_Kind`) — roles, names, values,
      screen bounds. **No DOM, no browser extension.**
- [x] Fuse with a Windows OCR pass (`StudyPercept_OCR`) for the stem and labels,
      associate labels to controls by proximity (`StudyPercept_WordNear`,
      `StudyPercept_AttachLabel`), and retain the screenshot
      (`StudyPercept_SaveFrame`, `StudyPercept_CropQuestionImage`) for the vision
      model. Temp frames are deleted unless `keep_frames` is on.
- [x] One structured `Question` (`StudyPercept_BuildQuestion`): raw + normalized
      text, choices with tags, control list with bounds, qtype, confidence,
      source image.
- [x] Classify (`StudyPercept_Classify`): `single`, `multi`, `yesno`, `tf`,
      `dropdown`, `fillblank`, `shorttext`, `longtext`, `numeric`, `image`.
      Detects "select all", negation cues feed the study layer; short/garbled
      stems with a frame route to vision.
- [x] Dedupe by fingerprint (`StudyPercept_QFP`) so a minor animation is not a
      new question, and a re-seen question is updated, not duplicated.
- [~] Anything unsupported, ambiguous, or unreadable returns a low-confidence /
      `image` result rather than a guessed control. *A dedicated explicit
      `unknown/review` surface in the UI is still [ ].*

**Acceptance:** fixtures for each qtype produce a `Question` with its controls and
bounds, or a low-confidence/image result; a reshuffled option set keeps meaning
(answer resolved by tag/label, not position).

---

## 4. Answer bridge  (StudyLive.ahk)

- [x] `StudyLive_StoreQuestion` writes the perceived question into the shared
      `qa_item` bank (same store the study-only layer uses).
- [x] `StudyLive_Answer` calls `Study_Answer()` — so memory reuse ("learn once"),
      local deduction over ingested material, and the DeepSeek fallback (text, or
      vision when a frame matters) are exactly the study layer's logic, never a
      parallel copy.
- [x] `StudyLive_Recheck` re-validates the proposal against the live question:
      valid choice tags (`StudyLive_ValidTags`), required selection count, units;
      strips quoting/boilerplate (`StudyLive_StripQuotes`).
- [x] Confidence gate: `confidence_threshold` setting; below it the cycle
      suggests/abstains rather than entering anything. Model answers remain
      provisional until portal/user confirmation.

**Acceptance:** a repeat question is answered from memory with no API call; a
novel one uses the fallback and stays provisional until feedback confirms it.

---

## 5. Verification & safe-stop  (StudyComposer.ahk + guard)

- [x] `StudyAuto_Guard()` runs before **every** step in a plan.
- [x] Targets are re-located fresh in the live Acc tree (or a fresh OCR pass)
      immediately before use (`StudyMacro_FreshControls`, `StudyMacro_Relocate`,
      `StudyMacro_InvalidateWalk`) — coordinates from the capture are never
      trusted for a click.
- [x] A page-change signature check between steps aborts the run.
- [x] Each step verifies its own outcome (`StudyMacro_VerifyStep`,
      `StudyMacro_Readback`): radio/checkbox checked state, field value, dropdown
      value. A mismatch is a safe stop, never a blind retry.
- [x] `Submit`/`Next` is clicked only when mode is `submit` **and** the
      `auto_submit` setting is on, and only on a control re-found by name
      (`StudyMacro_FindSubmit`). Otherwise the answer is entered but left
      unsubmitted.
- [ ] Hard stop on CAPTCHA / proctoring / lockdown / anti-cheat indicators and on
      any uncertain target state. *Guard hooks exist; the specific detector set
      is still to be filled in and must fail safe (stop), per section 0.*

**Acceptance:** input reaches only the pinned window; final control states match
the intended answer; a stale or obscured target causes a stop, not a wrong click.

---

## 6. Action composition & human-paced input  (StudyComposer.ahk)

Plans are built from the same action vocabulary the Macro Automator engine runs
(Click / Send Keys / Type Text / Paste / Wait), so a plan could also be handed to
`ExecuteSequenceVerified` for dry-run review (`StudyMacro_Preview`).

- [x] `StudyMacro_ParseAnswer` maps an answer onto controls by qtype
      (tag→radio/checkbox, value→field, option→dropdown); `StudyMacro_Compose`
      emits the step list; `StudyMacro_StepClick` targets a control centre.
- [x] Human-paced primitives (for reliability / natural feel, **not** evasion —
      see section 0), configured by `g_StudyHuman`:
  - curved, slightly wobbling pointer paths (`StudyHuman_Path`,
    `StudyHuman_MoveTo`) instead of teleports — `wobble` multiplier;
  - a hover pause before a press (`hoverMs`) and small pre-click jitter;
  - randomized inter-key timing (`minDelay`..`maxDelay`);
  - optional typo-then-correct typing (`typoRate`, `StudyHuman_Neighbor`), always
    followed by a field read-back so the final value is exact;
  - long text via the clipboard (`longtextPaste`) so essays are not minutes long.
- [x] `StudyMacro_Run` executes with the guard + verify treatment on every step;
      `StudyMacro_Abort` / `^+x` stops immediately.

**`g_StudyHuman` defaults:** `typoRate 0.02`, `hoverMs 300`, `minDelay 25`,
`maxDelay 90`, `wobble 1.0`, `longtextPaste true`. All are tuned for a natural,
reliable pace on cooperative targets; they are not detection-signature knobs.

**Acceptance:** for each qtype, the composed plan sets the correct control and the
read-back matches the intended answer; aborting mid-plan leaves input in a known
state.

---

## 7. Mode ladder, feedback & learning  (StudyLive.ahk)

- [x] Modes (`StudyLive_SetMode`, `mode` setting): `observe` (perceive only),
      `suggest` (perceive + answer, no input), `fill` (enter, don't submit),
      `submit` (enter + submit, additionally gated by `auto_submit`).
- [x] Feedback capture after a submit (`StudyPercept_FeedbackCheck`,
      `StudyLive_CheckFeedback`): reads correct/incorrect cues within
      `feedback_wait_ms` and records `portal-confirmed` / `disputed` via the study
      layer's versioned trail (`study_answer_log`, the `portal-confirmed` state
      added to `StudyDB.ahk`).
- [x] Resume across restarts honours a safety floor: `resume_session`, and
      `resume_submit_mode` must be explicitly set for `submit` to come back.

**Acceptance:** a correct/incorrect result after submission updates the stored
answer's state and feeds future retrieval, with the earlier attempt preserved.

---

## 8. UI, overlay & hotkeys

- [x] "Live Portal" tab (`StudyLive_BuildTab`): pin controls, region (window /
      drag), mode selector, engine + humanization settings, DeepSeek probe/key,
      stats, current question/answer/plan, and a self-test (`StudyLive_SelfTest`,
      `StudyLive_FixCtl`).
- [x] Non-activating status overlay (`StudyAuto_OverlayShow/Update/Paused`) on a
      side monitor so status never steals focus from the target.
- [x] Hotkeys: `^+y` toggle session, `^+u` pin window under cursor, `^+x` abort
      (shared global abort).

**Settings reference** (study settings table, via `Study_GetSetting`):
`sess_on`, `mode`, `poll_ms`, `overlay_on`, `portal_region`, `study_pin_title`,
`study_pin_origin`, `resume_session`, `resume_submit_mode`, `auto_submit`,
`confidence_threshold`, `feedback_wait_ms`, `cost_cap_usd`, `keep_frames`.

---

## 9. Not yet validated / open items

- [ ] Real 3-monitor geometry: negative-coordinate regions, per-monitor DPI, and
      overlay placement verified on the actual layout.
- [ ] The explicit `unknown/review` UI state and queue.
- [ ] The CAPTCHA / proctoring / lockdown detector set (section 5) — must exist
      and must fail safe before `submit` mode is used anywhere.
- [ ] Replay fixtures: a recorded corpus per qtype, plus moved-window, reshuffled
      options, focus-loss, rate-limit, and contradictory-feedback cases, so the
      perceive→compose→verify path can be tested without live input.
- [ ] End-to-end validation on a disposable target you own before enabling
      `fill`, then `submit`, separately.

## 10. Suggested bring-up order

1. Monitor geometry + pin + guard on the real layout (observe mode only).
2. Perception + classification against the fixture corpus.
3. Answer bridge in `suggest` mode (no input) — confirm answers look right.
4. Composer in `fill` mode on a target you own, verifying read-backs.
5. Feedback capture + the safe-stop detector set.
6. Only then, `submit` mode on your own target, with `auto_submit` explicit.

---

*This spec documents the automation subsystem for authorized, owned-target use
(section 0). It is a companion to `REALTIME_STUDY_ASSISTANT_SPEC.md`, which covers
the read-only study layer.*

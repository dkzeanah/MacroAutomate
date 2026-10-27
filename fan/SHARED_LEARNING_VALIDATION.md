# Shared learning integration — validation, 2026-10-17

## Delivered state

- Original workspace at validation time: `C:\Users\Don\Desktop\a-llm-harness-custom`. Relocated independently to `fan/harness` on 2026-10-18; see `HARNESS_INTEGRATION.md`.
- 129 desktop candidates indexed in place; 137 projects total including existing component projects.
- Current map: 327,916 Python symbols in 12,315 files; 17 occupied buckets of twenty configured buckets.
- Bounded capability discovery: 5,627 detected entries, including 1,404 runner entries. Discovery does not certify execution or install dependencies.
- Originals remain in place. The ledger contains source backups and a consistent SQLite backup from before capability registration.
- Discovery report: `.atlas/desktop-integration-20261017.json` in the harness.
- Versioned reference compilation: `condensed/desktop-20261017-final/{classes.py,functions.py,CONDENSE_MANIFEST.txt}`. Its manifest records duplicates and skipped slices; current source slices remain authoritative.

## Automated checks

- Full bridge suite: **104 passed**.
- Full harness suite: **197 passed**. Subsequent runner, scanner, map and learning-tab changes also passed their relevant checks (79 tests); final capture-budget changes passed 18 bridge checks and seven client/UI checks.
- Native feedback: 16 checks, including pre-action yellow borders, click-through/no-activate styles, capture exclusion, stale geometry and expiry.
- Native SDK: 11 checks; vision: 38; study workflow harness: 79; Learning Workbench: 25; validation preview: nine. All passed.
- Final main AHK parser validation succeeded.
- Existing invalid Python fixtures under `data/test` remain visible as index parse errors; they were not rewritten.

## Actual desktop evidence

- Captured real accessible taskbar buttons across three taskbars, with screenshots, labels, shortcut metadata and FindText encodings.
- Verified all **130 retained taskbar records** contain exactly the binary string decoded from their saved FindText pattern. Old and new capture identities are retained; this count is not 130 unique applications.
- Opened SciTE through its newly resolved taskbar target and verified `SciTE.exe` in the foreground.
- A subsequent real agent request, `open scite4ahk`, completed as “Already open”; the foreground identity was checked, no toggle click was needed, and its event history recorded **zero model calls**. Task ID: `34b2d9210bb04cdd91639539f1482a3c`.
- Workbench claim **871** is the actual SciTE finding. Its six-step lesson was opened through the shared API and reports **Tentative verification**, with scoped evidence and uncertainty.
- A repeat capture exceeded the original two-minute RPC allowance while continuing to retain observations. The capture budgets are now aligned at four minutes on the gateway and four and a half minutes on clients. Timeouts and uncertain app-open results do not trigger model fallback or automatic retry. Native RPC phases are inspectable in `fan/DeepSeekBridge/.runtime/fan-native-status.json`.
- Corrected one development counter that initially misread AHK's numeric true value (`1`). Its original row remains in `automation_learning_corrections`; original evidence is retained.

## Interpretation limits

Observations, syntax checks, successful process exits and verified application effects remain different claims. Frequency and replay are not causal proof. The bridge uses structured memory and deterministic reuse; it does not train a new language model. Atlas indexes Python symbols; native library tools supply the automater's AHK signatures. Reference compilations preserve source locations and do not replace separate projects' runnable environments.

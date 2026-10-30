# Atlas Control verification — 2026-10-30

Local interface: http://127.0.0.1:8790/.
Working copy: `C:\Users\Don\Desktop\domesim-atlas`.

28 focused tests passed: persistence, session/origin checks, matching snapshots,
cache accounting, invalid comparisons, read-only enforcement, path escape checks,
fresh-hash targeted edits, approval decisions, real MCP command execution,
owned-process-tree cancellation, restart recovery, conflict-checked promotion,
single-instance ownership, existing Atlas/media/delegation compatibility.
Frontend syntax and Python compilation checks passed. Browser checks covered
task submission, live events, comparison results, exact command approval and
reviewed application of a source change.

## Actual paired usage: helper-function source question

Question: find and explain `two_v_demo.deliverables.next_version_path`, with source
evidence. Fresh sessions, same source manifest and task within each pair. Run order
was randomized. These are exploratory single-task results, not general savings.

| Provider / model | Atlas total | Normal total | Atlas difference |
|---|---:|---:|---:|
| DeepSeek / deepseek-v4-pro | 38,621 | 43,289 | 10.78% fewer tokens |
| Codex / gpt-6.1-sol requested | 119,610 | 102,505 | 16.69% more tokens |

DeepSeek batch: `c83fd19a6b4f`. Codex batch: `247b5a070271`.
Both modes fetched source, completed, and left source unchanged. Scores for answer
quality remain unrated. Cached input is already included in total input; token
counts are not dollar charges. Provider-reported cache subsets and raw usage are
retained in each run export.

Earlier Codex attempts had denied MCP calls and are excluded from valid comparisons.
Failed/cancelled setup attempts remain visible under All attempts, with any reported
usage retained. Comparison polling uses recorded completion metadata rather than
rehashing the source tree on every refresh.

## Reviewed edit roundtrip

Run `6e620eeb515c` created only `docs/atlas-controller-smoke.md` in its snapshot.
The dashboard showed the resolved interpreter and exact Python assertion for
approval. The command returned `exit_code: 0`, `controller smoke passed`.
The one-line diff was reviewed and applied through the interface to domesim-atlas.
The original `DomeSim/docs/atlas-controller-smoke.md` does not exist.

The approved command's stdin is isolated from the MCP protocol transport. This
is covered by the real-stdio regression test. Python aliases resolve before
approval. Prior command-timeout attempts were retained as unsuccessful validation,
not silently turned into passes.

## Claude account status

Claude Code authenticated successfully after normal subscription sign-in was
enabled in the adapter. Its model request then reported a weekly account limit,
with a reset of 2:00 AM America/Chicago. Live Claude source retrieval and usage
comparison had not yet been verified when this report was first written.
The dashboard preserves the provider error. Check the run history for later runs.

Machine-readable evidence:
`fan/DeepSeekBridge/.runtime/controller/verification-2026-10-30.json`.
Setup and operation: `fan/ATLAS_CONTROL.md`.

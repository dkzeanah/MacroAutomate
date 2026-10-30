# Atlas Control — DomeSim agent workbench

Start from any PowerShell directory:

```powershell
& 'C:\Users\Don\Desktop\aAutomateMacro\fan\Start_Atlas_Control.ps1'
```

Open http://127.0.0.1:8790/. `-NoOpen` suppresses browser launch; `-Port` selects
another loopback port. This is local software; it has not been published.

## Working copy and run isolation

The working project is **C:\Users\Don\Desktop\domesim-atlas**. Its COPY-REPORT.md
records the copy scope: 14,124 files / 16,181,333,101 bytes, zero copy failures.
The original DomeSim tree was left untouched during controller implementation.
The working copy omits environments, Git metadata, private settings, caches and
old deliverables/exports. It is a development copy, not a full backup.

Each task receives a separate snapshot of eligible source/text files up to 2 MB.
The snapshot has a SHA-256 manifest. Binary assets, installed dependencies and
generated output are absent from run snapshots; runtime validation can require
additional resources. The dashboard exposes that limitation. Runs never promote
edits automatically. Review the Changes tab and click Apply to modify the working
copy. Promotion refuses source conflicts, deletes and incomplete/truncated diffs,
and saves overwritten working-copy files under the controller's applied/ folder.

Paired comparisons are read-only. Both runs use the same captured source manifest,
prompt, provider, requested model and limits. The common repository agreements
are equal in both modes, with the original Atlas-specific policy section removed.
Execution order is randomized. Fresh sessions are used; provider cache warmth
cannot be guaranteed equal. One worker serializes tasks. Browser refresh does not
restart a run or issue another model request.

## Providers

| Provider | Adapter | Authentication |
|---|---|---|
| Claude | Claude Code `-p`, streamed JSONL, scoped controller MCP | Existing Claude sign-in or configured provider credentials |
| Codex | `codex exec --json`, ephemeral session, scoped controller MCP | Existing Codex sign-in |
| DeepSeek | Direct streaming API agent loop, same scoped MCP tools | Existing Fan/Cutline credential resolver |

This first controller uses Codex exec, not app-server. It is a task interface,
not an attachment to an existing Claude/Codex terminal conversation. New tasks
are fresh runs. CLI versions and account/model availability can affect operation;
the complete reported errors remain in run history.

Claude uses its normal sign-in: bare mode is intentionally avoided because the
installed version excludes subscription OAuth in bare mode. Only user settings
are selected, hooks are disabled, built-in tools are disabled, and only the
controller MCP server is configured. No global client settings are rewritten.

Codex ignores user configuration except existing authentication; the controller
supplies the selected model and its one MCP server. The server's bounded tools
are pre-approved for this run; writes still require an edit-enabled snapshot,
and test commands wait for a separate dashboard decision. Codex's native shell
uses its read-only sandbox. Native Codex reads remain an advisory scope limit;
the interface describes Atlas mode as assisted, not enforced Atlas-only access.

DeepSeek uses the API directly, independently of the web harness at port 3080.
It does not dispatch the Fan desktop automation agent. Provider credentials are
resolved locally, never sent to the browser or copied into MCP configuration.
The same workspace tools support all three providers. Atlas mode adds the four
existing Atlas retrieval tools; normal mode does not expose them.

## Dashboard workflow

1. Choose provider, model, task, strategy and access. Compare both creates a pair.
2. Follow Activity. Expand a tool call to see arguments and actual source results.
3. Approve or deny an exact test command. Python aliases resolve to the controller
   interpreter before approval, avoiding unrelated virtual environments on PATH.
   Command input is isolated from the MCP transport. Command execution and approval
   timeouts are separate reported outcomes.
4. Review Answer, Changes and Usage. Keep output quality separate from token size.
5. Apply reviewed edits to domesim-atlas when appropriate. The original is never
   the promotion target. Refresh the workspace Atlas index after promotion.
6. Export a run as JSON, including events, usage, answer and diff.

Human review supports correctness, source grounding and validation scores (0–5)
and notes. These scores are operator assessments, not automated proof. Matched
comparisons are shown by default; All attempts includes failed, source-blocked
and cancelled verification attempts. History keeps those attempts and their
reported usage; failures are not silently deleted.

## Usage accounting

All token figures are **provider-reported**, not character estimates. Claude's
uncached input, cache creation and cache-read tokens are combined into total
input. Codex and DeepSeek already include cached input in their input total;
cached tokens are a subset and are not added twice. DeepSeek usage is accumulated
over all measured API requests. CLI usage is taken from the final cumulative
result, not summed again from intermediate messages. Raw usage remains available.
Missing usage is unknown, not zero. Partial/failed runs are excluded from matched
comparisons. Codex's model label records the requested CLI selection; Claude and
DeepSeek can report the resolved model identity.

A valid comparison requires matching source, settings and prompt, completed
reported usage, no source changes, and evidence that both modes actually fetched
source. A model response that only restates the initial agreements after tool
denials cannot establish a comprehension comparison. A token reduction is not an
answer quality score, a dollar saving, or a subscription-limit estimate. Claude's
reported cost, when supplied, is labelled API-equivalent and is not an invoice.

The helper-function demonstration is a single exploratory task, not a general
performance claim. Use multiple representative tasks, repeated runs and explicit
acceptance criteria before deciding which strategy is more robust or economical.

## Local control and safety boundaries

The server binds only to 127.0.0.1. API requests require the local HttpOnly,
SameSite session cookie. Cross-origin requests and non-loopback hosts are refused.
Reload the page after restarting the controller to renew its session cookie.

Filesystem MCP tools enforce the run root and reject private paths, credentials,
path escapes and writes in read-only runs. They do not expose arbitrary shell
execution. Approved test commands run as the local Windows user: this is **not an
OS security sandbox for arbitrary code**. Review the exact argv and any script it
executes. Credential environment variables are removed from the test subprocess;
that does not prevent arbitrary approved code from accessing other account files.

Stop run terminates the owned process tree and cancels pending approvals. Windows
job ownership also closes descendant processes when the controller process exits.
Restart marks unfinished runs interrupted and never resumes paid work silently.
Snapshot preparation/indexing is not billed model work and may finish its local
operation before cancellation is observed. A stopped model request can still
incur provider usage before termination; unavailable final usage stays unknown.

## Files and API

Implementation: `fan/DeepSeekBridge/bridge/controller/`. Launcher:
`fan/Start_Atlas_Control.ps1`. Existing bridge dependencies are reused; no frontend
package installation or remote assets are needed.

Runtime data is ignored by Git at
`fan/DeepSeekBridge/.runtime/controller/`: SQLite history, immutable batch
baselines, per-run source/index directories, manifests and promotion backups.
These can contain project source and outputs. They remain local. No automatic
retention/deletion policy has been installed.

For small edits, `workspace_replace` replaces one unique fragment using a fresh
file hash from `workspace_read`. It preserves UTF-8 BOM/newlines and avoids
resending a whole large source file. Stale hashes and ambiguous matches are
refused. Atlas refreshes after supported source edits. Completed snapshots are
treated as immutable; edit the working copy and start a new task instead of
manually modifying a completed run directory.

The browser uses `/api/state`, `/api/runs`, per-run `/events`, `/stream`, `/diff`,
`/cancel`, `/apply`, `/review`, `/export`, plus `/api/approvals/{id}` and
`/api/comparisons/{batch}`. Establish a session with GET / before API calls.
POST /api/reindex refreshes the working copy's entry in the shared Atlas workspace;
each Atlas run independently indexes its own fixed snapshot.

References: [Claude execution](https://code.claude.com/docs/en/headless),
[Codex non-interactive mode](https://developers.openai.com/codex/noninteractive),
[Codex MCP configuration](https://developers.openai.com/codex/mcp).

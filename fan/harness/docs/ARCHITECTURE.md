# SideLearner Architecture

Built from scratch in Python 3.10+ (target: Windows desktops). This document
explains the design decisions, data flow, and the borrowed concepts from
OpenClaw, Claude Code, OpenAI Codex, deepseek-harness, and Ollama.

## 1. System overview

```
┌─────────────────────────────── perception (always-on) ───────────────────────────────┐
│ screen watcher (mss)   audio watcher (sounddevice + VAD)   camera watcher (cv2)      │
│   change detection        WASAPI loopback / mic, WAV vault    face detect (optional) │
│   window titles          optional STT via provider            optional vision        │
│   optional OCR (tesseract) / vision description                                       │
└───────────────────────────────┬───────────────────────────────────────────────────────┘
                                │ typed events (perception.*)
                                ▼
                          EventBus (pub/sub, history ring)
                                │
        ┌───────────────────────┼───────────────────────────┐
        ▼                       ▼                           ▼
 DigitalTwin (ledger+graph)   TriggerManager             AgentLoop (on demand)
   observation ledger          event→skill match          router → provider → tools
   compressor (merge/dedup)    run workflow skills        verification pass
   gap analysis ("should        on observed activity       session log (JSONL)
    have been learned")                                   deterministic fallback
                                │
                                ▼
                     tools (fs / shell / desktop / browser / twin)
                     risk-gated, sandboxed, policy-checked
```

## 2. The learning pipeline (the "side-learner")

**Ledger.** Every perceived item (window title, OCR text, transcript, vision
description, agent tool output) becomes an `observation` row with a content
digest; identical items dedupe. Items with ≥30 chars of text open a ledger row
with a `gap_due` timestamp (`gap_minutes` later) — an *opportunity*.

**Compressor.** Runs every `auto_compress_every` seconds or after
`compress_min_items` unlearned items (also `sl twin compress`). For each
unlearned item it extracts candidate facts:

- with a provider: a strict-JSON extraction prompt (`{facts:[{text, kind,
  entities}]}`) on chunked text — normally the *local* provider (privacy);
- without a provider: sentence saliency heuristics (action words, capitalized
  entities) — fully offline.

Each candidate fact is embedded and either merged into a similar existing fact
(cosine ≥ `merge_similarity`: weight bump, source link) or inserted. Entities
are upserted by (name, kind) with weight reinforcement.

**Gaps.** Items whose window expired (`gap_due` passed) without contributing a
fact become gap records: *data that appeared and had the opportunity to be
learned, but wasn't captured*. Gaps surface via `sl twin gaps` and the
`daily_digest` skill.

**Graph maintenance.** Facts decay (stale + low weight → archived) and the fact
count is trimmed to `max_facts`. Retrieval is cosine over fact/entity
embeddings; the agent loop injects the top hits into every task as a context
block.

**Hierarchy.** Every fact/entity carries a `domain`, assigned by the
`DomainClassifier` (keyword-scored against `business.taxonomy`, with a model
fallback for uncertain cases). Domains are the knowledge hierarchy; status,
export, and retrieval all group by it.

**Embeddings.** Provider embeddings when a healthy embed-capable provider
exists (e.g. Ollama `embeddinggemma`); otherwise a deterministic model-free
`TokenHashEmbedder` (hashed token projection, unit-normalized) that makes
routing and retrieval work with zero models.

## 2b. Autonomy engine (`autonomy.py`)

The self-directed learning loop, whose explicit goal is **decreasing input
requirements over time**:

```
startup (immediate): screenshot -> vision model -> ledger -> queue compression
cycle (every interval_s): screen re-analysis (rate-limited) -> compress new
   observations -> pattern assessment -> prompt or auto-decide
```

- **Patterns** come from the `occurrences` table: every perception event is
  counted even when the ledger dedupes identical content, so "Chrome was
  focused 12 times today" survives content dedup.
- **Prompting is a cost.** `assess_patterns` only prompts for recurring apps
  whose purpose is uncertain (cap: `max_open_prompts`). Prompts are rows in
  the `decisions` table — they survive restarts and work identically in
  hidden (pythonw) mode: `sl prompts` / `sl answer <id> <answer>`.
- **Generalization (decisiveness).** Each answer is stored as a classified
  fact in the right domain. `_best_guess_domain` uses: taxonomy keywords →
  token similarity to previously classified apps → model fallback. Once the
  same answer has been confirmed `auto_confidence` times, new apps matching
  that domain are auto-answered: `autonomy.decision` events with `auto=true`
  and zero prompts. Input shrinks as knowledge grows.
- Startup is non-blocking: vision analysis runs first (bounded by the local
  model), backlog compression is queued to the twin's background thread, and
  cycles skip compression while it is busy.

## 3. Pre-LLM router (`router/`)

Runs entirely before any model call:

1. **Deterministic rules** — ordered regexes for `vision`, `transcribe`,
   `code_edit`, `code_read`, `shell`, `workflow`, `summarize`, `research`,
   `admin`, fallback `chat`. Each rule carries a tier, an allowed tool set, and
   required provider capabilities. Business `vocabulary` elevates matching
   tasks to `workflow`.
2. **Exemplar kNN** — when no rule matches: nearest labeled exemplar (builtins +
   config extras) by embedding cosine (token-overlap fallback), with a
   `min_confidence` floor.
3. **Provider selection** — `registry.pick(tier, capabilities)`: cheapest tier
   at-or-above the requested one, healthy (cached probe), capable. Falls back
   upward (`tier_fallback`) and finally to `local_only` (deterministic mode).
4. **Skill match** — workflow intent tasks are matched to skills by keyword
   overlap.

The decision is fully explainable: every stage appends a reason string
(`sl chat` prints them).

## 4. Agent loop (`reason/`)

One turn = one model call + at most one tool execution.

- **Contract:** a single JSON shape `{thought, tool, tool_args, answer}`,
  enforced by lenient parsing (fences, stray text) with a graceful degradation:
  plain-text model output becomes the final answer. This works on any
  OpenAI-compatible model — no native tool-calling dependency.
- **Context:** system prompt (contract + business profile + policy + tool
  schemas + optional workspace `MEMORY.md`) + task message (+ twin knowledge
  block). Tool schemas are restricted to the route's allowed set.
- **Execution:** tool calls go through the registry's policy (`allow/deny/ask`,
  family gates, fs-root sandbox, shell allow/deny lists); results (including
  denials) feed back verbatim, logged to the session.
- **Compaction:** token estimate (`len/4`); over `compact_at_tokens` the middle
  history is replaced by a summary marker.
- **Verification (own reasoning, no model):** every `written`/`created` path
  from tool results is checked for existence; claims of files the loop never
  wrote are flagged MISSING; an optional `verify_cmd` (e.g. `pytest`) runs
  after any write.
- **Deterministic mode:** no healthy provider → skills match → heuristic plans
  (`run tests`, `list files`, `read X`, `search TERM`, `install P`, `write
  file …`). Explicit helpful error when nothing matches.
- **Delegation:** with `agent.cli_delegate: {agent: codex-cli}`, code-edit
  tasks can be handed wholesale to a CLI agent (Claude Code / Codex) running
  as a subprocess in the workspace, with the harness controlling the prompt,
  cwd, and permission flags.

## 5. Providers (`providers/`)

- `OpenAICompatProvider` — the workhorse; covers Ollama (`/v1`), LM Studio,
  vLLM, OpenAI, DeepSeek. Chat (stream + non-stream), embeddings, vision
  (data-URI images), transcription (only on endpoints that support `/v1/audio`).
- `AnthropicProvider` — plain-requests Messages API client (text + vision).
- `CLIAgentAdapter` — `claude` / `codex` subprocess adapters with preset
  permission flag maps (overridable in config; flags vary by CLI version).
- Health: cached reachability probes (`GET /models`), 60 s TTL; routing never
  picks an unhealthy provider.

## 6. Perception (`perception/`)

All watchers are daemon threads on a shared `WatcherBase` (setup/tick/teardown,
crash isolation, status dict). The supervisor writes `vault/run/status.json`
for `sl status`.

- **Screen:** mss capture → downscale → 64×40 luminance signature diff; frames
  saved on change (rolling window). Focused-window tracking via `win32gui`
  (app + title). Optional periodic tesseract OCR and optional vision
  description.
- **Audio:** sounddevice stream → per-block RMS VAD → speech segmentation
  (min/max speech, silence timeout) → WAV into the vault (rolling window) →
  optional provider STT. Loopback: PortAudio exposes WASAPI loopback devices by
  name; we prefer one so desktop audio is captured **without interfering** with
  playback; otherwise the default mic. Unavailable devices disable the watcher
  gracefully (event `perception.audio.unavailable`).
- **Camera:** OpenCV DSHOW capture, warmup frames, downscaled JPEGs, optional
  Haar face count, optional vision description. Local-only storage.

Windows notes: mic privacy consent can block the default input; tesseract needs
the binary on PATH; camera vision needs a vision-capable provider.

## 7. Tools & policy (`tools/`)

Registry: `name → ToolSpec(description, parameters, risk, family, read_only)`.
Policy check order:

1. family gates (shell/browser enabled, desktop control_enabled for
   mouse/keyboard),
2. fail-closed rule: high-risk `fs` ops (delete) require an interactive ask
   callback (`sl chat --ask`),
3. shell allow/deny lists inside the tool itself,
4. interactive ask for high-risk tools when a callback exists.

`fs` resolves every path inside configured roots (absolute paths must be under
a root; relative paths anchor to the first root) — Codex `workspace-write`
semantics. Denials are reported to the model so it adapts instead of retrying.

## 8. Sessions (`sessions.py`)

Append-only JSONL per run (`vault/sessions/<id>.jsonl`), events:
`session.start`, `model.message` (system/user/assistant — everything the model
can see), `tool.call`, `tool.result`, `agent.delegate`, `agent.verdict`,
`session.end`. Invariant borrowed from deepseek-harness: *model-visible means
logged*. Transcripts replay via `sl sessions show <id>`.

## 9. Windows sandboxing — honest status

Windows has no user-namespace sandbox. Current posture:

- fs confinement to workspace roots (implemented, enforced per call);
- shell: timeout + allow/deny lists + risk gating (implemented);
- desktop control: opt-in (implemented);
- **Roadmap:** a `WRITE_RESTRICTED` restricted token (deepseek-harness's
  `CreateRestrictedToken` ACL approach) for shell subprocesses, labeled
  *partial enforcement*, with `danger-full-access` as explicit opt-in.

## 9b. Hidden background operation

`sl daemon start` spawns `pythonw.exe -m sidelearner.cli run --daemon-child`
detached with `CREATE_NO_WINDOW`, stdout/stderr to `vault/logs/sidelearner.log`,
stdin to DEVNULL, and writes `vault/run/daemon.pid`. `sl daemon status` checks
the pid plus the supervisor's `vault/run/status.json` freshness; `sl daemon
stop` SIGTERMs the pid (taskkill fallback); `sl daemon logs` tails the log.
Because prompts live in the `decisions` table (not stdin), the autonomy engine
works identically hidden: ask via `sl prompts`, answer via `sl answer`.

## 10. Failure & escalation design

- Router cascades tiers on unhealthy providers; deterministic mode is the
  terminal fallback — business workflow skills keep running with no models.
- Watcher crashes are isolated per tick; a broken mic/camera disables only that
  watcher.
- Provider calls retry bounded (2×, backoff) before surfacing; extraction
  falls back to heuristics.
- Everything important is logged to the session or the event bus history.

## 11. MCP tool servers

SideLearner speaks the Model Context Protocol to external tool servers. The
primary use case is browser automation: a Playwright MCP server (stdio or SSE)
is discovered and its tools are mapped to stable `browser.*` names. Generic MCP
tools are exposed as `mcp.<server>.<tool>`. See `mcp/client.py` and
`mcp/playwright_tools.py`.

## 12. Web dashboard

An optional FastAPI app (`web/server.py`) serves a dashboard and REST/WebSocket
API. It creates its own `Harness`, subscribes to the event bus, and streams live
events to browsers. It is launched on demand with `sl web start`; the background
daemon does not depend on it.

## 13. Extension points

- **New input channel:** a watcher class + event emission + a
  `_EVENT_KINDS` entry in `memory/twin.py`; the twin learns it automatically.
- **New provider kind:** subclass `Provider` + a loader branch in
  `providers/registry.py`.
- **New tool:** `registry.register(ToolSpec(...))` (see `tools/twin.py`).
- **New MCP server kind:** subclass/adapt `MCPClient` and register tools in
  `tools/mcp.py`.
- **New business workflow:** a YAML file in a `workflow_dirs` directory.

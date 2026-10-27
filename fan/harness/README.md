# Harness Studio

> **One launcher. Everything else is a tab.**
> Run `Harness.bat`. New to it? Open the **Guide** tab -- it explains what this is,
> how it works and how to use it, and the last topic is generated live from your
> own workspace. If you are an LLM, read `AGENTS.md`.

## What is here

| Part | What it does |
|---|---|
| `atlas/` | **The context map engine.** Indexes any codebase into addressable symbols so an LLM can understand and extend it without reading files. |
| `studio/` | **The unified GUI.** Eight tabs: Atlas, Index, Write Gate, Ingest, Condense, Ledger, Harness, Export. |
| `sidelearner/` | The agent harness (perception, memory twin, router, skills, tools). |
| `Ollama_Job_Automation_Studio_v1.2/` | OJAS: resume/ATS scoring, job pipeline, RAG. |
| `creator_ops*.py` | The content pipeline: briefs, drafts, review queue, metrics. |
| `legacy/` | The merged Python Code Analyzer Manager and the Ollama pre-prompt tools. |

## The idea in one paragraph

Reading a project is the most expensive thing an LLM does, and nearly all of it is
waste. Atlas replaces "read the files" with a three-tier map: one small atlas naming
every project and its bucket, one index per project listing every class and function as
a single line with its exact span and its call edges in both directions, and byte-exact
slices fetched by a stable address. An agent reads the atlas, reads one index, fetches
three slices, and is done. Before it writes anything it asks whether the code already
exists -- and a `MISS` is authoritative, which ends the search that would otherwise
continue through file after file. Where new code goes is decided by the engine, not the
model, so it lands correctly the first time and the index never drifts. Nothing is
deleted; superseded code is retired to an attic with a tombstone in the index.

Measured on this workspace: answering one question costs about **9,100 tokens**
(atlas + one index + three slices) against **38,839** to read that project's sources.
Run `Atlas.bat budget` for live figures. See `docs/CONTEXT_MAP_SPEC.md` for the format.

## Quick start

```powershell
Harness.bat
```

That is the whole entry point. It also forwards to the CLI:

```powershell
Harness.bat atlas find "retry backoff"
Harness.bat run "creator_ops_gui"
Harness.bat index
Harness.bat test
```

The eight tabs:

| Tab | What it is for |
|---|---|
| **Guide** | What this is, how it works, how to use it. Start here. The last topic reports what is actually in your workspace right now. |
| **Atlas** | Sweep a folder of projects, classify each into one of twenty buckets with visible evidence, set priority and pins. |
| **Index** | Browse every symbol; select one to see its slice, its callers and its callees, and what a change would impact. |
| **Write Gate** | Dedupe, budget and placement before you add code. The verdict is built to be pasted into a model's context. |
| **Create** | The front door for adding anything: scaffold a new project, add one symbol where the engine says it goes, paste code in, or **absorb** an existing project whole. |
| **Ingest** | Drop a ZIP, a chat transcript, or a folder. It is planned, backed up, written, deduped, indexed, and optionally run -- in that order. |
| **Condense** | Collapse the indexed universe into `classes.py` and `functions.py`, each with a navigable span map. |
| **Coagulate** | Reconcile N divergent copies of one project into one, with a proof nothing was lost. Also finds duplicated code across everything indexed. |
| **Ledger** | Every mutation, every backup, the attic, and one-click restore. |
| **Harness** | Run anything: every tool absorbed from your own projects, plus the built-in launchers. Output is captured in the pane. |
| **Export** | Generate `ATLAS.md`, the per-project `INDEX.md` files and `LLM_GUIDE.md`, with token costs. |

`F11` fullscreen, `Ctrl+1`..`9` for the first nine tabs, View menu for the rest.

---

## SideLearner (the agent harness)

**A self-hosted LLM harness that watches your desktop, learns from it, and automates your work — with no forced monthly subscription.**

SideLearner is built from scratch in Python, borrowing the best design ideas from OpenClaw, Claude Code, OpenAI Codex, deepseek-harness, and Ollama:

| Idea | Source | In SideLearner |
|---|---|---|
| Channels/gateway for many inputs | OpenClaw | Always-on perception watchers (screen, audio, camera, window) feeding one event bus |
| Tool registry + allow/deny/ask permission layers | Claude Code / Codex | Risk-gated tool registry, sandboxed fs roots, shell allow/deny lists, interactive ask |
| Exec policy & sandbox modes | Codex | `read-only` default; writes confined to workspace roots; desktop control opt-in |
| Skills folders | OpenClaw / Claude Code | YAML business workflow skills with a local interpreter (run fully offline) |
| Event-sourced session log | deepseek-harness / Codex | Append-only JSONL sessions; "anything model-visible is logged" |
| Event waterfalls & policy pipeline | deepseek-harness / Claude Code | `tool.pre_execute` / `tool.post_execute` bus events + policy checks |
| Provider abstraction over OpenAI-compat | Ollama / dsh | One client covers Ollama, LM Studio, vLLM, OpenAI, DeepSeek; plus Anthropic and CLI agents (Claude Code, Codex) |
| Memory hierarchy | Claude Code / Codex | Working memory (prompt), episodic (sessions), knowledge-graph (the twin) |
| Compaction | Claude Code | Token-aware context compaction mid-loop |

## How it works (current)

```powershell
sl daemon start        # hidden background process (no console window)
sl onboard             # one-time: describe your business, apps, tasks, people
```

The daemon runs three cooperating loops:

1. **Perception (always-on)** — screen watcher (change detection + frames to the
   vault), window tracker, audio watcher (VAD + WAV), optional camera. Every
   event lands on one event bus.
2. **Twin learning** — the bus feeds the observation ledger; the compressor
   (a background thread) extracts facts, classifies each into your business
   **taxonomy** (`business.taxonomy` in config.yaml), merges duplicates,
   reinforces repeats, decays stale items, and flags **gaps** — data that
   appeared but was never learned.
3. **Autonomy (self-directed)** — on start it IMMEDIATELY screenshots the
   desktop, describes it through your local vision model (qwen3-vl), files it
   into the ledger, and queues backlog compression. Every `interval_s` it
   re-analyzes the screen, compresses new observations, and **decides**:
   recurring apps become patterns; patterns with an uncertain purpose produce
   a *prompt*; and once you've confirmed the same answer twice, new apps in
   that domain are **auto-answered** — the system asks less and less.

Nothing leaves the machine by default; all model calls are local (Ollama).

## Observe working order

```powershell
sl daemon logs                  # live daemon output
sl twin status                  # observations, learned, domains, gaps, prompts
sl twin facts --domain tools    # what it learned, grouped by domain
sl prompts                      # questions it is waiting on
sl answer 3 "bookkeeping"       # teach it one answer; it generalizes after 2
sl sessions list                # every agent task, replayable
```

Then just use the computer. Switch apps, read documents, talk. Watch
`sl twin status` climb and `sl twin facts` accumulate domain-organized
knowledge. When a prompt appears, answer it — each answer shrinks future
prompting.

### Desktop-wide live captions

Install the full audio extras, enable transcription, and run perception plus the
dashboard:

```powershell
.\.venv\Scripts\python -m pip install -e ".[full]"
sl daemon start
sl web start
```

Open `http://127.0.0.1:8080` and click **Show overlay** under **Live Desktop
Captions**. A frameless, always-on-top Windows caption bar appears over other
applications. SideLearner prefers local `faster-whisper` (`small.en` by default)
and falls back to a configured provider with the `audio` capability. Partial
captions update while speech continues; finalized transcripts are saved in the
`audio_segments` table in `memory.db` and also enter the ordinary observation →
ledger → fact pipeline. WAV segments remain in `vault/audio` under the configured
rolling retention.

Desktop loopback capture is intentionally fail-closed: it does not silently
record the microphone unless `perception.audio.fallback_to_mic: true` is set.
Capturing system audio may include private meetings, calls, or media, so enable
it only with consent.

## The core idea: a side-learner

SideLearner assumes a computer is full of information that *should* be learned —
documents you open, pages you read, code you write, conversations you have next to
it. It builds a **digital twin** of that knowledge:

```
perception (screen/OCR, audio/VAD+STT, camera, window titles, clipboard)
      │  events
      ▼
observation ledger ──► every item is a learning "opportunity"
      │
      ▼
compressor (local heuristics, or a local model) ──► facts + entities + relations
      │
      ▼
compressed knowledge graph (dedup, merge, reinforce, decay)  ◄── the digital twin
      │
      └── gaps: opportunities whose window expired without captured knowledge
          ("data that appeared and had the chance to be learned — but wasn't")
```

The twin answers questions (`sl twin query "payment terms"`), feeds relevant
knowledge into every agent task, and reports its own **learning gaps**.

## Own reasoning logic — not just prompts

1. **Pre-LLM router** — before any model call: deterministic intent rules,
   nearest-exemplar voting over embeddings (with a model-free hashed-embedding
   fallback), business-vocabulary elevation, tier selection (local→budget→best),
   provider cascade, tool allow-set, skill match.
2. **Own agent loop** — a strict JSON reasoning contract (`thought/tool/tool_args/
   answer`) that works on local models as well as frontier ones; permission-gated
   tool execution; token-aware compaction; and a **verification pass that is pure
   local logic** (written files must exist; optional `verify_cmd` like `pytest`
   runs after writes).
3. **Deterministic mode** — with no provider at all, the harness still works:
   heuristic plans ("run tests", "list files", "install X") and full workflow
   skills execute directly. Your business automation does not die when a vendor
   API does.

## Getting started (Windows)

```powershell
cd C:\path\to\your-business-computer
git clone <your repo> sidelearner        # or just copy the folder
cd sidelearner
SideLearner.bat                          # double-click: menu + first-run setup
```

`SideLearner.bat` is the launcher: double-click it for an operator menu
(start/status/logs/twin/prompts/onboard/chat), or call it with arguments from
a terminal — it passes everything through to the `sl` CLI and creates the
`.venv` environment automatically on first run.

Manual setup equivalent (skip if you used the launcher):

Ollama is optional but recommended for a fully self-contained machine:
```powershell
ollama pull llama3.2
ollama pull nomic-embed-text
ollama pull llama3.2-vision              # optional screen/camera description
sl chat "explain the router code in this workspace"
```

### Everyday commands

```powershell
sl daemon start|stop|status|logs   # hidden background operation
sl onboard                         # first-run business description
sl prompts                         # open autonomy questions
sl answer <id> "answer"            # teach it; generalizes after 2 confirmations
sl run                             # foreground daemon (Ctrl+C to stop)
sl chat "fix the bug in the login function" --ask
sl chat "process the invoices folder"        # routes to the invoice skill
sl skill list               # business workflows
sl skill run invoice_processing
sl twin status | facts [--domain X] | gaps | query "month-end close" | export twin.jsonl
sl sessions list | show <id>
sl web start|stop|status|logs       # optional FastAPI dashboard (daemon needs no GUI)
```

## Configuring a business computer

`config.yaml` carries the **business profile** — the hyper-optimization layer:
```yaml
business:
  name: accounting-firm
  domain: "Public accounting: bookkeeping, invoicing, reconciliations, month-end close"
  vocabulary: [invoice, reconcile, month-end, payroll, ledger, client]
  workflow_dirs: ["skills/examples"]
```

- `vocabulary` steers the router toward workflow skills and shapes extraction.
- `taxonomy` is the knowledge hierarchy every learned fact is classified into —
  tune its keywords to your business and the twin organizes itself accordingly.
- `autonomy.prompt_mode: ask|observe` and `auto_confidence` control how the
  system transitions from asking to deciding.
- Workflows are YAML skills (see `skills/examples/`): tool steps, LLM prompt steps,
  checks, conditions, repeats, event emission — `invoice_processing.yaml` and
  `workspace_recon.yaml` are ready-to-copy templates.
- Skills can **trigger on observed activity** (`sl run`): e.g. an invoice file
  appearing triggers processing automatically.

## Providers — full control

Everything is a config entry; nothing is a subscription:

- **Local (free, private):** Ollama via its OpenAI-compatible endpoint; LM Studio,
  vLLM, llama.cpp the same way.
- **Pay-per-use (no monthly fee):** DeepSeek, OpenAI, Anthropic — env-var keys,
  `enabled: false` until you want them.
- **Other AI systems as agents:** `claude` and `codex` CLIs as delegatable coding
  agents (`agent.cli_delegate`) with their permission modes configured here.

The router cascades: local first, escalate only when needed, deterministic when
nothing is reachable.

## Browser automation without the playwright Python package

If you already run a Playwright MCP server (e.g. `npx @anthropic-ai/playwright-mcp-server`),
SideLearner connects to it directly over stdio or SSE and exposes stable browser
tools: `browser.open`, `browser.click`, `browser.type`, `browser.screenshot`, etc.
No local `playwright` Python install is required.

```yaml
mcp_servers:
  playwright:
    enabled: true
    command: ["npx", "-y", "@anthropic-ai/playwright-mcp-server"]
    # or, if the server is already running: url: http://localhost:3001/sse
```

## Web dashboard (optional)

`sl web start` launches a FastAPI dashboard at `http://127.0.0.1:8080`. It shows
twin status, live perception events, screenshots, open prompts, skills, and a
chat interface. The daemon runs identically without it — the GUI is purely
optional viewing and control.

## Privacy & safety posture

- Screen frames, audio WAVs, camera frames and the knowledge graph stay **in the
  local vault** (`vault/`) unless you explicitly enable a remote vision/STT
  provider.
- Audio capture is **non-interfering**: WASAPI loopback taps the desktop mix
  without touching playback (falls back to the mic).
- Tools are risk-classed: `fs` is confined to configured roots; `shell` honors
  allow/deny lists; desktop mouse/keyboard injection is off by default; risky
  ops require `--ask`.
- Windows has no real sandbox for processes; SideLearner therefore uses
  fail-closed policy + path confinement (documented honestly in
  `docs/ARCHITECTURE.md`, with the restricted-token upgrade path noted).

## Layout

```
sidelearner/
  harness.py        composition root (CLI/demos/tests all build this)
  config.py         YAML config + defaults + env overrides
  events.py         event bus (typed events, pattern subscribe, history)
  sessions.py       append-only JSONL session log
  providers/        openai_compat (Ollama/OpenAI/DeepSeek/...), anthropic, cli_agents
  router/           pre-LLM intent rules + exemplar kNN + tier/pick + skill match
  reason/           JSON contract, agent loop, deterministic heuristic planner
  memory/           store (SQLite), ledger, knowledge graph, compressor, twin
  perception/       screen (mss + change detect + OCR), audio (VAD + WAV + STT),
                    camera (cv2 + face detect), supervisor + status file
  tools/            registry + policy; fs (sandboxed), shell, desktop, browser, twin
  skills/           YAML workflow engine + examples
  triggers.py       perception events -> workflow skills
  demo.py           built-in demos
  cli.py            `sl` command surface
tests/              pytest suite (no network, no model required)
```

Run the tests: `.\.venv\Scripts\python -m pytest tests -q`

## Roadmap

- Web GUI (FastAPI + WebSocket over the event bus — the dsh-style thin client).
- `WRITE_RESTRICTED` token sandbox for shell (deepseek-harness's Windows ACL approach).
- Whisper local STT (faster-whisper) as an optional `kind: whisper_local` provider.
- Autonomy "act" phase: beyond auto-classification, autonomously executing
  confirmed business workflows when their triggers fire (today triggers run
  skills directly — the next step is confidence-gated autonomous invocation).
- Relation mining between entities (currently relations are explicit).
- Native Ollama `/api/generate` client with `keep_alive` residency hints.

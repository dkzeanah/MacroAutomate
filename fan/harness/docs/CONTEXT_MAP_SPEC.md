# Context Map Specification v1

A deterministic format for describing a codebase to an LLM in the fewest possible tokens,
while guaranteeing the LLM can retrieve *exactly* the code it needs and know with certainty
when something **does not exist**.

The problem it solves: reading a project costs enormous context. This spec replaces
"read the files" with "read the map, then fetch three slices."

---

## 1. The three tiers

Context is served in tiers. An agent reads tier N only if tier N-1 was insufficient.

| Tier | Artifact | Size | Answers |
|---|---|---|---|
| 0 | `ATLAS.md` | 1-3 KB | *Which project/bucket is this about?* |
| 1 | `INDEX.md` (per project) | 2-12 KB | *Does this symbol exist? Where is it? What touches it?* |
| 2 | slice fetch | 20-400 tokens | *What is the actual code?* |

**Rule: never read a whole file.** Tier 2 returns a line range, not a file.

### Measured cost, not claimed cost

Run `atlas budget` for live figures. On this workspace (8 projects, 1,637 symbols,
27,668 lines) the measured numbers are:

| | tokens |
|---|---:|
| tier 0, `ATLAS.md` | 816 |
| tier 1, one project's `INDEX.md` (median) | 7,674 |
| tier 2, three slices | ~600 |
| **total to answer one question** | **~9,100** |
| reading that project's sources instead | 38,839 |

That is **4-5x** on the targeted path, and the index-to-source ratio holds at
roughly 5x across every project measured. A per-symbol index of a codebase is
about a fifth of the code it describes; that is the floor, and no amount of
format tuning gets past it.

The compression ratio is not where most of the saving comes from. The saving is
behavioural, and it is larger than the ratio suggests:

* an agent reads **one** index instead of exploring several projects to find out
  which one is relevant;
* it fetches three slices instead of opening whole files to read four functions;
* a `MISS` from the dedupe gate **ends** a search that would otherwise keep going
  through file after file, which is the single most expensive thing an agent does;
* it never re-reads what it already has, because addresses are stable.

Be suspicious of any context-map scheme claiming 100x. Measure it.

---

## 2. The address

Every symbol in the universe has exactly one canonical address:

```
@bucket/project:path/to/file.py#Class.method
@bucket/project:path/to/file.py#function_name
@bucket/project:path/to/file.py            (file-level)
@bucket/project                            (project-level)
@bucket                                    (bucket-level)
```

Examples:

```
@agent/sidelearner:reason/loop.py#ReasonLoop.step
@codetool/atlas:atlas/slicer.py#slice_symbol
@career/ojas:ojas/resume_ats.py#ResumeScorer
```

Addresses are **stable across edits**: line numbers change, addresses do not.
An address is the only thing an agent needs to quote to request code.

---

## 3. The index line

`INDEX.md` is a flat list. One symbol, one line, fixed grammar:

```
<kind> <span> <hash> <signature>  <edges>  <flags>
```

Concrete:

```
F L142-198  h:a3f9  ReasonLoop.step(self, obs: Observation) -> Action   >loop.plan,tools.registry.dispatch  <harness.tick,cli.run
C L098-241  h:7b21  ReasonLoop(BaseLoop)                                >planner.Planner  <harness.build
f L012-019  h:1c04  _clamp(value: float, lo: float, hi: float) -> float >-  <step,plan,score
```

Field grammar:

| Field | Meaning |
|---|---|
| `C` / `F` / `f` / `A` | class / public function-or-method / private (leading `_`) / async |
| `L142-198` | **line span** — the exact slice coordinates, 1-indexed, inclusive |
| `h:a3f9` | 4-hex content hash of the symbol body. If it differs from the live file, the index is stale for that symbol only |
| signature | full signature with annotations, no body |
| `>a,b,c` | **calls out to** — symbols this one uses. Read these to understand it |
| `<x,y,z` | **called by** — symbols that use this one. Read these before changing it |
| flags | `X` obsolete, `!` untested, `*` hot/frequently-changed, `e` external |

`>` and `<` are the debugger-stack-trace idea made static: the index carries the call
graph in both directions, so an agent never has to grep to find impact.

---

## 4. The dependency comment (in-file mirror)

The same edges are mirrored into the source as a single comment directly above each symbol,
so the slice is self-describing even when read alone:

```python
# @atlas >loop.plan,registry.dispatch <harness.tick,cli.run  L142-198 h:a3f9
def step(self, obs: Observation) -> Action:
    ...
```

This means a **tier-2 slice carries its own map**. An agent that fetches one function
immediately knows the next two addresses worth fetching, and never fetches blind.

---

## 5. The 20 buckets

Every project on disk resolves to exactly one bucket. Buckets are the tier-0 vocabulary.

```
agent        LLM harnesses, agent loops, providers, MCP, tool routers
codetool     code analysis, indexing, refactoring, project management
desktop-auto AutoHotkey, window/explorer automation, hotkeys, macros
web-auto     browser automation, scraping, extensions, selenium/playwright
sim3d        3D/graphics/geometry/CAD/ModernGL/dome and shell structures
embedded     ESP32, Arduino, firmware, device probes, serial
vehicle      automotive, CAN bus, OBD, hybrid systems, avionics
datatool     file/drive analyzers, dedupe, search indexes, organization
media        audio/video/image processing, recording, transcoding
docgen       PDF, documents, printing, reports, publishing
career       resume/ATS, job search automation, applications
contentops   creator operations, social publishing, marketing pipelines
osint        research, intelligence gathering, investigation workbenches
game         games, bots, simulations of play
datasci      ML, notebooks, statistics, data visualization
webapp       servers, APIs, FastAPI/Flask/frontends
sysadmin     installers, packaging, environment setup, portable apps, backups
electronics  circuits, schematics, EDA, electrical study material
knowledge    notes, study guides, learning material, reference
misc         unclassified - requires human review
```

Bucket assignment is scored, not guessed: see `atlas/buckets.py`. Every assignment
records the evidence (matched signals, score, runner-up) so it can be audited and overridden.

---

## 6. The existence guarantee

The single most expensive LLM failure is *searching for code that is not there*.
The index makes non-existence provable:

```
atlas find "retry with backoff"
```

returns either

```
HIT  @agent/sidelearner:utils.py#retry_backoff   L44-61  score 0.91
```

or

```
MISS  no symbol matches. 412 symbols searched across 6 buckets.
      SAFE TO CREATE. Suggested home: @agent/sidelearner:utils.py after L61.
```

`MISS` is authoritative. An agent that receives `MISS` must stop searching and create.
That single contract removes the largest source of wasted context there is.

---

## 7. The placement rule engine (write path)

Code may not be appended arbitrarily. Every insertion passes three gates:

1. **Dedupe gate** - `atlas find` must return `MISS`, or the agent must justify divergence.
2. **Budget gate** - the agent declares line count up front. A symbol over the bucket's
   `max_symbol_lines` must be split before it is accepted.
3. **Placement gate** - `atlas plan-insert` returns the exact file and line:

```
atlas plan-insert retry_backoff --lines 18 --bucket agent
-> TARGET @agent/sidelearner:utils.py  INSERT AT L62
   section: "retry & timing"  (L44-61 occupied by: retry_once)
   after commit: index += 1 line; 3 spans below shift +18
```

The engine, not the model, decides where code goes. Placement is therefore correct
the first time, and the index never drifts.

---

## 8. Never lose code

Writes are ledgered and append-only.

- Superseded code is **moved to `.atlas/attic/`**, never deleted.
- A tombstone stays in the index: `X L000-000 h:old  old_name(...)  -> replaced by @new/address`
- Every mutation writes a full-file backup to `.atlas/backups/<timestamp>/`.
- `atlas restore <ledger-id>` returns the tree to any prior certified-working state.

Obsolete code costs nothing at tier 0 (it is one flagged line). Losing it costs everything.

---

## 9. Condense and fan-out

The same map drives both directions:

- **Condense** - N projects collapse into `classes.py` + `functions.py`, each with a
  navigable section header carrying the line spans. One paradigm, one vocabulary.
- **Fan-out** - a single mass document or a downloaded ZIP explodes into a real project
  tree, with each piece placed by the rule engine rather than dumped in a folder.

**Ingest-and-run** is fan-out plus execution: drop a ZIP in the hot folder and it is
unpacked, scanned, deduped against the master index, placed, indexed, backed up, and run
in one pass. A second drop of the same project diffs against the first and applies changes
while retaining the last known-good state.

---

## 10. Priority (hot projects)

Projects carry a `priority` 0-100. Vague requests resolve against high-priority projects
first. "Write me something to render a dome" checks `@sim3d` hot projects before generating
anything new, so existing capability is reused rather than duplicated.

---

## 11. The agent contract

Any third-party LLM given this repository is handed `LLM_GUIDE.md`, which says, in short:

> 1. Read `ATLAS.md`. Pick a bucket.
> 2. Read that project's `INDEX.md`. Resolve addresses.
> 3. Fetch slices by address. Never open a whole file.
> 4. Before writing, run the dedupe gate. `MISS` means create; `HIT` means reuse.
> 5. Ask the engine where code goes. Do not choose yourself.
> 6. Nothing is deleted. Supersede via the ledger.

That is the entire protocol. It fits in a system prompt.

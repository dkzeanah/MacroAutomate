# AGENTS.md

Instructions for any LLM or agent working in this repository. Read this before you
read anything else.

---

## 1. This codebase is mapped. Do not browse it.

There is a context map. Using it costs a few thousand tokens; not using it costs
several hundred thousand and produces worse answers. The protocol is six steps:

```
1. Read ATLAS.md                      -> which bucket and project is this about?
2. Read .atlas/index/<project>.INDEX.md  -> which symbol, and what touches it?
3. atlas get <address>                -> the code, with its own edges attached
4. atlas find "<intent>"              -> before you write anything
5. atlas plan-insert <name> --lines N -> where it goes. You do not choose.
6. Retire, never delete.
```

`LLM_GUIDE.md` is the same protocol written for pasting into a system prompt.
`docs/CONTEXT_MAP_SPEC.md` is the format itself.

## 2. The address is the only thing you need to quote

```
@bucket/project:path/to/file.py#Class.method
```

Real examples from this repository:

```
@agent/sidelearner:reason/loop.py#AgentLoop.run
@codetool/atlas:rules.py#find
@career/ojas:ojas/resume_ats.py#ResumeScorer
@contentops/creator-ops:creator_ops.py#CreatorStore
```

Addresses are stable across edits. Line numbers are not, which is why they live in
the index and never in your notes.

## 3. Reading the index line

```
F L142-198  h:a3f9  AgentLoop.run(self, task: str) -> AgentResult   >loop.plan,registry.dispatch  <cli.cmd_run
```

| | |
|---|---|
| `F` | function (`C` class, `f` private, `A` async, `K` constant) |
| `L142-198` | the exact slice span |
| `h:a3f9` | body hash. Differs from the file? The index is stale for that symbol — re-index |
| `>` | calls out to. **Read these to understand it** |
| `<` | called by. **Check these before you change it** |

Signatures over 132 characters and edge lists over 4–5 entries are truncated in the
index. The full versions are one `atlas get` / `atlas impact` away. That truncation is
deliberate: uncapped, a handful of hub symbols cost more than the code they describe.

## 4. Before you write code

Run the gate. All three parts, in order:

```bash
atlas gate my_new_function --intent "what it should do" --lines 24 --bucket agent
```

- **DEDUPE** — `HIT` means reuse the match or justify the divergence. `MISS` is
  **authoritative**: the code is not there. Stop searching. Do not grep "just to be
  sure" — that is the single most expensive thing an agent does, and the whole gate
  exists to end it.
- **BUDGET** — declare the line count up front. Over the bucket ceiling (80 lines by
  default) it is refused; split it and resubmit.
- **PLACEMENT** — the engine returns the file and the exact insertion line, plus what
  shifts below it. Do not pick a location yourself.

The gate is calibrated, not perfect: measured at 11/12 on a labelled set, with the one
error a weak hit surfaced at 0.49 for review rather than a silent pass. Treat a
low-scoring `HIT` as a question, and a `MISS` as an answer.

## 4b. Reconciling duplicate copies of a project

When the same project exists in several folders, do not diff them pairwise.

```bash
atlas variants                       # which folders are copies of one project
atlas reconcile --family <key>       # align every symbol across all of them
atlas coagulate --family <key> --policy lead --lead <folder> --write
```

Alignment is structural, not textual: local variables are alpha-renamed and literals
erased before hashing, so the same function copied nine times and re-styled in each is
recognised as one symbol. Module-level content (imports, `__main__` blocks) is tracked
separately, because a branch whose only change was adding one import has no differing
symbol and would otherwise read as "identical".

Every version of every symbol gets exactly one disposition -- adopted, same, archived,
or held -- and the counts must balance against the total present. That accounting is
the loss proof. After writing, the output is re-scanned from disk and every adopted
symbol confirmed present with a matching structural hash.

Conflicts are never resolved silently. Under the default `newest` policy they are held,
written from the base variant, and flagged in-file with a comment naming every
alternative and where it is archived.

## 5. Nothing is ever deleted

Superseded code goes to `.atlas/attic/` with a header naming its replacement, and keeps
a flagged tombstone line in the index. Every mutation writes a full backup to
`.atlas/backups/<timestamp>/` and a row in the ledger; `atlas restore <id>` returns the
tree to any prior state.

An obsolete symbol costs one line at tier 0. Losing it costs everything. Retire, do not
remove.

## 6. Vague requests resolve against hot projects

If a request does not name a project, check the pinned and high-priority projects at the
end of `ATLAS.md` first. If the capability already exists in a hot project, use it.
Existing capability beats new code — that is the entire reason the priority field exists.

---

## Repository layout

```
atlas/          the context map engine
                  scan/index/slice      scanner, graph, index, slicer, address
                  write path            rules (dedupe, budget, placement), scaffold
                  reshaping             condense, fanout, ingest
                  dedupe & merge        normalize, similar, variants, coagulate
                  integration           entities, absorb
                  history               ledger, store
studio/         the unified Tk GUI -- eleven tabs over everything below
sidelearner/    the agent harness: perception, memory twin, router, skills, tools
Ollama_Job_Automation_Studio_v1.2/   OJAS: resume/ATS, RAG, visual synthesis
creator_ops*.py the content pipeline (root-level modules)
legacy/         merged-in prior projects, kept whole
  code_analyzer/      the AST analyzer this system grew out of
  ollama_preprompt/   pre-prompt builders for local models
  launchers/          the separate .bat files Harness.bat replaced
  dsh_developer_agent/, dsh_skills/, agent_notes/
tests/          194 tests -- 40 atlas, 29 coagulate, 28 absorb, 9 studio, 88 sidelearner
docs/           CONTEXT_MAP_SPEC.md
.atlas/         the map itself: sqlite, per-project indexes, backups, attic
```

## Running things

There is **one** launcher. Everything else is a tab or an entity inside it.

```bash
Harness.bat                      # the GUI
Harness.bat atlas <subcommand>   # the CLI instead
Harness.bat run "<tool name>"    # run one absorbed tool
Harness.bat index                # re-index this workspace's own parts
Harness.bat test                 # the test suite
```

## Integrating a project (entities)

A project folder is opaque. Absorbing it extracts what it can *do* and registers
those as entities, without moving or changing anything:

```bash
atlas absorb <path>              # preview what would be registered
atlas absorb <path> --write      # register it
atlas entities --runnable        # everything you can now run
atlas run "<name>"               # run one
atlas manifest                   # the full capability list
atlas release <project>          # unregister; the folder is untouched
```

Entity kinds: `gui`, `cli`, `command`, `service`, `script`, `skill`, `notebook`, `api`.
Detection is evidence-based — argparse subparsers, click/typer decorators, `__main__`
guards, Tk/Qt constructors, FastAPI/Flask objects, `[project.scripts]`, `console_scripts`.

Absorption is purely additive, so `release` is a complete undo. Prefer it over `--copy`:
a copy starts diverging from the thing you actually work in.

## Working on the engine itself

`atlas/` is the one place where changing code invalidates the map that describes it.
After editing anything under `atlas/` or `studio/`, run `python bootstrap_index.py`
before relying on a slice or condensing — otherwise spans drift and the hash check will
(correctly) start refusing them.

## Style

Match the surrounding code: type annotations throughout, module docstrings that say why
the module exists rather than restating its name, and comments reserved for decisions a
reader would otherwise have to reverse-engineer. Do not add comments that narrate the
next line.

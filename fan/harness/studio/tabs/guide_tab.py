"""Guide tab -- what this is, how it works, and how to use it.

Deliberately the first tab. A system with nine tabs and forty commands is worthless if
you cannot remember what any of them are for, and a README you have to leave the app to
read is a README you do not read. The last topic is generated live from the workspace,
so it answers "what is actually in here" rather than describing a hypothetical install.
"""

from __future__ import annotations

import tkinter as tk
from tkinter import ttk

from studio.widgets import MONO, UI, UI_BOLD, Field, TextPane, button, separator, toolbar


class GuideTab:
    def __init__(self, parent: ttk.Frame, context) -> None:
        self.ctx = context
        self.store = context.store
        self._rendering = False

        bar = toolbar(parent)
        self.search = Field(bar, "Find in guide", width=34)
        self.search.pack(side=tk.LEFT)
        self.search.widget.bind("<Return>", lambda e: self._search())
        button(bar, "Search", self._search)
        separator(bar)
        button(bar, "What's in my workspace", lambda: self._show("workspace"))
        button(bar, "Copy topic", self._copy)

        panes = ttk.PanedWindow(parent, orient=tk.HORIZONTAL)
        panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)

        left = ttk.Frame(panes)
        ttk.Label(left, text="TOPICS", font=UI_BOLD).pack(anchor="w", pady=(0, 3))
        self.tree = ttk.Treeview(left, show="tree", selectmode="browse")
        self.tree.pack(fill=tk.BOTH, expand=True)
        self.tree.bind("<<TreeviewSelect>>", self._selected)
        self._populate()
        panes.add(left, weight=1)

        right = ttk.Frame(panes)
        head = ttk.Frame(right)
        head.pack(fill=tk.X)
        self.title_var = tk.StringVar(value="")
        ttk.Label(head, textvariable=self.title_var, font=UI_BOLD).pack(side=tk.LEFT,
                                                                       pady=(0, 3))
        ttk.Label(head, text="Guide is read-only. Everything here is doable from the "
                             "other tabs or the CLI.",
                  font=UI, foreground="#777777").pack(side=tk.RIGHT)
        self.body = TextPane(right, font=MONO, wrap=tk.WORD)
        self.body.pack(fill=tk.BOTH, expand=True)
        panes.add(right, weight=4)

        self._show("start")

    # ----------------------------------------------------------------- topics
    def _populate(self) -> None:
        for section, topics in SECTIONS:
            node = self.tree.insert("", tk.END, text=section, open=True)
            for key, label in topics:
                self.tree.insert(node, tk.END, iid=key, text="   " + label)

    def _selected(self, _event=None) -> None:
        if self._rendering:
            return
        selection = self.tree.selection()
        if selection and selection[0] in TOPICS:
            self._show(selection[0])

    def _show(self, key: str) -> None:
        """Render one topic.

        Re-entrancy matters here. ``selection_set`` fires ``<<TreeviewSelect>>``,
        which lands back in ``_selected`` and calls this again. Because the virtual
        event is queued rather than delivered inline, a naive version does not blow
        the Python stack -- it feeds the Tcl event queue forever and starves every
        other timer, freezing the whole application. Hence both guards: the flag for
        the inline path, and the selection comparison for the queued one.
        """
        if self._rendering:
            return
        self._rendering = True
        try:
            self._render(key)
        finally:
            self._rendering = False

    def _render(self, key: str) -> None:
        label = next(
            (l for _s, topics in SECTIONS for k, l in topics if k == key), key
        )
        self.title_var.set(label.upper())
        text = TOPICS.get(key, "")
        if callable(text):
            try:
                text = text(self.store, self.ctx)
            except Exception as exc:
                text = f"(could not build this view: {exc})"
        self.body.set(text)
        self._highlight()
        # Only touch the selection when it is actually wrong: setting it to the value
        # it already holds still emits <<TreeviewSelect>>, which is what makes this a
        # loop rather than a single extra pass.
        if self.tree.exists(key) and self.tree.selection() != (key,):
            self.tree.selection_set(key)
            self.tree.see(key)

    def _highlight(self) -> None:
        """Bold the ALL-CAPS headings and colour the command lines."""
        self.body.text.tag_remove("head", "1.0", tk.END)
        self.body.text.tag_remove("edge", "1.0", tk.END)
        for index, line in enumerate(self.body.get().splitlines(), start=1):
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.isupper() and len(stripped) > 3 and not stripped.startswith("-"):
                self.body.text.tag_add("head", f"{index}.0", f"{index}.end")
            elif stripped.startswith(("atlas ", "$ ", "Harness.bat", "python ")):
                self.body.text.tag_add("edge", f"{index}.0", f"{index}.end")

    # ----------------------------------------------------------------- actions
    def _search(self) -> None:
        needle = self.search.get().lower()
        if not needle:
            return
        hits = []
        for key, content in TOPICS.items():
            if callable(content):
                continue
            if needle in content.lower() or needle in key:
                label = next(
                    (l for _s, topics in SECTIONS for k, l in topics if k == key), key
                )
                for line in content.splitlines():
                    if needle in line.lower():
                        hits.append(f"[{label}]  {line.strip()[:110]}")
        if not hits:
            self.title_var.set(f"NO MATCH FOR {needle!r}")
            self.body.set(f"Nothing in the guide mentions {needle!r}.")
            return
        self.title_var.set(f"{len(hits)} MATCHES FOR {needle!r}")
        self.body.set("\n".join(hits[:120]))

    def _copy(self) -> None:
        self.ctx.app.clipboard_clear()
        self.ctx.app.clipboard_append(self.body.get())
        self.ctx.status("Topic copied to clipboard", "good")

    def on_refresh(self) -> None:
        pass

    def on_show(self) -> None:
        pass


# ===================================================================== content

def _workspace_view(store, ctx) -> str:
    counts = store.counts()
    projects = store.projects()
    entity_rows = store.entity_counts()
    buckets = store.bucket_summary()

    out = [
        "WHAT IS ACTUALLY IN YOUR WORKSPACE RIGHT NOW",
        "=" * 70,
        f"workspace: {ctx.workspace}",
        "",
        f"  {counts['projects']:>5} projects",
        f"  {counts['buckets']:>5} buckets in use",
        f"  {counts['files']:>5} source files indexed",
        f"  {counts['symbols']:>5} symbols addressable",
        f"  {counts['lines']:>5,} lines mapped",
        "",
    ]
    if entity_rows:
        out += ["REGISTERED ENTITIES (things you can run or call)", "-" * 70]
        for row in entity_rows:
            out.append(f"  {row['n']:>5}  {row['kind']}")
        out.append("")
    else:
        out += [
            "No entities registered yet.",
            "Go to the Create tab -> Absorb an existing project, point it at a folder,",
            "and everything that folder can do becomes runnable from the Harness tab.",
            "",
        ]

    if buckets:
        out += ["BUCKETS", "-" * 70]
        for row in buckets:
            out.append(
                f"  {row['bucket']:<14} {row['projects']:>3} projects  "
                f"{row['symbols']:>5} symbols  {row['lines']:>8,} lines"
            )
        out.append("")

    if projects:
        out += ["PROJECTS, HIGHEST PRIORITY FIRST", "-" * 70]
        for project in projects[:30]:
            pin = "*" if project.pinned else " "
            out.append(
                f" {pin}{project.name[:34]:<35} @{project.bucket:<12} p{project.priority:<4} "
                f"{project.symbol_count:>5} sym"
            )
        if len(projects) > 30:
            out.append(f"   ... and {len(projects) - 30} more")
        out.append("")

    out += [
        "NEXT STEPS",
        "-" * 70,
        "  Nothing indexed?      Atlas tab -> set your scan root -> Sweep + Index",
        "  Want to run things?   Create tab -> Absorb -> then Harness tab",
        "  Duplicate folders?    Coagulate tab -> Detect families",
        "  Handing this to an    Export tab -> Write full pack, then give the model",
        "  LLM?                  ATLAS.md and LLM_GUIDE.md",
    ]
    return "\n".join(out)


START = """\
HARNESS STUDIO

One window over a code universe. It does three things, and they compound.

1. IT MAKES CODE ADDRESSABLE

   Every class and function in every project you point it at gets a permanent
   address:

       @bucket/project:path/to/file.py#Class.method

   Line numbers change; addresses do not. From an address you can fetch exactly
   that symbol -- not the file it lives in -- along with what it calls and what
   calls it. That is the whole trick: you never read a file again, you fetch
   three symbols.

2. IT MAKES PROJECTS DO-ABLE

   A folder is opaque. You cannot tell from outside whether it holds one script
   or fourteen tools. Absorbing a project extracts the things it can actually
   DO -- its GUIs, CLIs, subcommands, servers, launchers -- and registers them as
   entities you can run from one place.

3. IT REFUSES TO LOSE ANYTHING

   Superseded code goes to an attic with a tombstone. Every mutation writes a
   full backup and a ledger row. Merging nine copies of a project produces an
   accounting where every version of every symbol has exactly one disposition,
   and the counts must balance. Proof, not assurance.

WHY IT EXISTS

   Reading a project is the most expensive thing an LLM does, and nearly all of
   it is waste. A folder full of folders is the most expensive thing a person
   deals with, for the same reason: no index, so you re-derive everything each
   time you come back.

   Both problems are the same problem. This is the index.

WHERE TO START

   Never used it      -> "First five minutes", below
   Have a messy       -> Create tab -> Absorb, or Atlas tab -> Sweep + Index
     desktop
   Have nine copies   -> Coagulate tab
     of one project
   Want to hand your  -> Export tab
     code to an LLM
"""

FIRST_RUN = """\
FIRST FIVE MINUTES

STEP 1  -- POINT IT AT YOUR CODE

   Atlas tab. Set "Scan root" to the folder holding your projects (your Desktop
   works). Press "Sweep".

   Sweeping is read-only. It decides which folders are actually projects, sorts
   each into one of twenty buckets, and shows you the evidence for every call so
   you can argue with it. Nothing is written.

   Happy with it? Press "Sweep + Index". Now every symbol has an address.

STEP 2  -- LOOK SOMETHING UP

   Index tab. Type a function name in the search box. Select it.

   You get the code, its callers, and its callees -- and a token count showing
   what that cost. Compare it to the size of the file you did not open.

STEP 3  -- MAKE SOMETHING RUNNABLE

   Create tab -> "Absorb an existing project". Point it at a project with tools
   in it. Press Preview, then Absorb.

   Harness tab now lists its GUIs, CLIs and subcommands. Press Launch.

STEP 4  -- BEFORE YOU WRITE NEW CODE

   Write Gate tab. Type what you are about to build and how many lines it will
   be. Run all gates.

   It tells you whether it already exists, whether it is too big to be one
   symbol, and exactly which file and line it should go in.

STEP 5  -- HAND IT TO A MODEL

   Export tab -> "Write full pack". Give the model ATLAS.md and LLM_GUIDE.md.
   That is the entire protocol; it fits in a system prompt.

THAT IS THE WHOLE LOOP

   index -> look up -> gate -> write -> re-index.
   Everything else on this tab list is a specialised version of one of those.
"""

TABS_TOPIC = """\
THE TABS, AND WHEN TO USE EACH

GUIDE        You are here. Read-only orientation.

ATLAS        Where projects come from. Sweep a folder, classify every project
             into one of twenty buckets with visible evidence, set priority,
             pin the ones you use most.
             Use when: starting out, or after adding projects.

INDEX        The symbol browser. Search thousands of symbols, select one, see
             its code and both directions of its call graph. "Impact" shows
             what breaks if you change it.
             Use when: you need to understand or change existing code.

WRITE GATE   Three checks before new code: does it already exist, is it small
             enough to be one symbol, and where exactly does it go.
             Use when: about to add a function. Especially with an LLM.

CREATE       The authoring front door. Scaffold a new project, add a module or
             a symbol in the right place, paste code in, or absorb an existing
             project whole.
             Use when: adding anything to the universe.

INGEST       Drop a ZIP, a chat transcript, or a folder. It is planned, backed
             up, written, deduped, indexed, and optionally run -- in that order.
             Use when: a model just handed you a project as a download.

CONDENSE     Collapse the indexed universe into classes.py and functions.py,
             each with a navigable span map.
             Use when: you want one file to reason about instead of many.

COAGULATE    Reconcile several divergent copies of one project into one, with a
             proof that nothing was lost. Also finds duplicated code everywhere.
             Use when: you have project-v1, project-v2, project-final-FINAL.

LEDGER       Every mutation, every backup, the attic, one-click restore.
             Use when: something went wrong, or you want to see what changed.

HARNESS      Launch anything: built-in tools, and every entity absorbed from
             your own projects. Output is captured in the pane.
             Use when: you want to actually run something.

EXPORT       Generate ATLAS.md, per-project INDEX.md, and LLM_GUIDE.md, with
             token costs measured rather than claimed.
             Use when: handing the codebase to a model.
"""

ADDRESSES = """\
ADDRESSES AND THE INDEX FORMAT

THE ADDRESS

    @bucket/project:path/to/file.py#Class.method

    @agent/sidelearner:reason/loop.py#AgentLoop.run
    @codetool/atlas:rules.py#find

    Addresses carry no line numbers, so they survive edits. They are the only
    thing you ever need to quote to ask for code.

    Drop components to widen the reference:
        @agent/sidelearner:reason/loop.py    the file
        @agent/sidelearner                   the project
        @agent                               the bucket

THE INDEX LINE

    F L142-198  h:a3f9  AgentLoop.run(self, task: str) -> AgentResult   >loop.plan  <cli.cmd_run

    F           kind: C class, F function, f private, A async, K constant
    L142-198    the exact slice span -- these are the coordinates for a fetch
    h:a3f9      hash of the body. Differs from the file? That symbol is stale.
    >           what it CALLS. Read these to understand it.
    <           what CALLS it. Check these before you change it.

    Those two arrows are a debugger stack trace made static. The index already
    knows the blast radius, so nothing has to grep for it.

WHY SIGNATURES AND EDGE LISTS GET TRUNCATED

    A handful of hub symbols have dozens of callers. Printed in full they cost
    more than the code they describe. The index carries enough to decide; the
    full version is one fetch away:

    atlas get <address>        the code, with its edges attached
    atlas expand <address>     it, plus everything it calls
    atlas impact <address>     every caller, in full
"""

GATE_TOPIC = """\
THE WRITE GATE

Code is not appended on a hunch. Three gates, in order.

1. DEDUPE -- does this already exist?

   Searches every indexed symbol, structurally and semantically.

   HIT   reuse the match, or say why a new symbol is justified.
   MISS  AUTHORITATIVE. The code is not there. Stop searching and write it.

   That second guarantee is the valuable one. The most expensive thing an agent
   does is hunt through files for code that was never written. A trustworthy
   MISS ends that search.

2. BUDGET -- how many lines will it be?

   Declared up front, checked against the bucket ceiling (80 lines by default).
   Oversized symbols are refused, not quietly accepted. Split and resubmit.

3. PLACEMENT -- where does it go?

   The engine answers, not you and not the model. It returns a file, an exact
   insertion line, the neighbouring symbol, and what shifts below.

   If nothing in the index relates to what you are adding and you gave no
   bucket or project, it REFUSES rather than guessing -- because any choice
   would be arbitrary, and arbitrary placement is how an index starts drifting.

FROM THE COMMAND LINE

    atlas gate my_function --intent "what it does" --lines 24 --bucket agent

The verdict is formatted to be pasted straight into a model's context.
"""

ABSORB_TOPIC = """\
ENTITIES: MAKING A PROJECT'S CAPABILITIES VISIBLE

THE PROBLEM

    A serious project is not one tool. It is a GUI, three CLIs, forty
    subcommands, a server, some batch launchers, a skills folder. From outside
    the folder you can see none of that.

WHAT ABSORPTION DOES

    Four passes:

    1. CLASSIFY   which bucket, with evidence you can audit
    2. INDEX      every symbol, addressable, with call edges
    3. EXTRACT    everything the project can DO
    4. REGISTER   those entities, launchable from the Harness tab

    Entity kinds:

      gui        a windowed application
      cli        a command-line entry point
      command    one subcommand inside a CLI
      service    a server that listens on a port
      script     a .bat / .ps1 / .sh launcher
      skill      a declarative SKILL.md capability
      notebook   a Jupyter notebook
      api        a public class or function worth calling from code

    Detection is evidence-based: argparse subparsers, click and typer
    decorators, __main__ guards, Tk and Qt constructors, FastAPI and Flask
    objects, [project.scripts] in pyproject.toml, console_scripts in setup.py.

THE PRINCIPLE THAT MAKES IT SAFE

    Nothing is moved, copied, renamed or rewritten. The project keeps its own
    structure and identity exactly. It is integrated BY REFERENCE AND INDEX.

    Everything absorption adds is additive and reversible:

    atlas release <project>

    removes the index rows and the entity registrations. The folder on disk is
    precisely as it was. There is nothing to undo, because nothing was done to it.

FROM THE COMMAND LINE

    atlas absorb <path>                  preview what it would register
    atlas absorb <path> --write          register it
    atlas entities --runnable            everything you can now run
    atlas run "<name>"                   run one of them
    atlas manifest                       the full capability list
"""

WHICH_TOOL = """\
FOUR WAYS CODE COMES IN. WHICH ONE DO YOU WANT?

ABSORB       You have a project and want its tools reachable.
  (Create)   Nothing is copied or changed. Classify, index, extract entities,
             register. Reversible with `atlas release`.
             -> Use this by default for existing projects.

INGEST       A model handed you a ZIP or a chat transcript full of code blocks.
  (Ingest)   It is planned, backed up, written to a real tree, deduped against
             everything indexed, indexed, and optionally run.
             -> Use this for incoming downloads and pasted dumps.

COAGULATE    You have project-v1, project-v2, project-final, project-FINAL2.
  (Coagulate) Aligns every symbol across all copies at once, classifies each as
             unanimous / cosmetic / structural / unique / conflict, and merges
             with an accounting that proves nothing was lost.
             -> Use this when the SAME project exists several times.

CONDENSE     You want one navigable file instead of many.
  (Condense) Projects collapse into classes.py and functions.py, each with a
             span map so the result is still fetched by address, never read
             whole. The originals are untouched; this is a projection.
             -> Use this to hand a whole universe to something in one piece.

THE DIFFERENCE IN ONE LINE

    absorb     = many tools, one place to run them
    ingest     = outside code, safely brought in
    coagulate  = many copies, one project
    condense   = many projects, one file
"""

BUCKETS_TOPIC = """\
THE TWENTY BUCKETS

Every project resolves to exactly one. They are the top-level vocabulary -- the
thing an LLM reads first to decide where to even look.

  agent        LLM harnesses, agent loops, providers, MCP, tool routers
  codetool     code analysis, indexing, refactoring, project management
  desktop-auto AutoHotkey, window/explorer automation, hotkeys, macros
  web-auto     browser automation, scraping, extensions, selenium/playwright
  sim3d        3D/graphics/geometry/CAD/domes and shell structures
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
  misc         unclassified -- needs a human

HOW ASSIGNMENT WORKS

  Scored, never guessed. Signals are weighted by where they were found:
  a dependency in requirements.txt counts far more than the same word appearing
  once in a README. Every verdict records the matched signals, the score, and
  the runner-up, so a wrong call is visible rather than inherited.

  Low-confidence calls are flagged. Override any of them in the Atlas tab.

PRIORITY

  Projects carry a priority 0-100 and can be pinned. Vague requests resolve
  against high-priority projects first, so "write me something to render a dome"
  finds the dome code you already have instead of generating a second copy.
"""

SAFETY = """\
NOTHING IS EVER LOST

This is the load-bearing promise. Everything else is built on it.

THE LEDGER        Every mutation appends a row: sweeps, indexes, ingests,
                  absorbs, mirrors, retires, restores, exports, coagulations.

BACKUPS           Before anything is modified, affected files are copied whole
                  into .atlas/backups/<timestamp>/. Restore any of them from the
                  Ledger tab, with a preview first.

THE ATTIC         Superseded code moves to .atlas/attic/ with a header naming
                  what replaced it, and keeps a flagged tombstone line in the
                  index. An obsolete symbol costs one line at tier 0. Losing it
                  costs everything.

COAGULATION       Merging copies archives every non-adopted version BEFORE
                  writing anything, so an interrupted run still loses nothing.
                  Afterwards the output is re-read from disk and every adopted
                  symbol confirmed present with a matching structural hash.
                  Conflicts are never resolved silently -- they are flagged
                  in-file at the exact line, naming every alternative.

ABSORPTION        Adds only index rows. The project folder is untouched, so
                  `atlas release` is a complete undo.

THE ONE EXCEPTION

  Old backup folders are pruned above a floor of 40, and only when you ask.
  Ledger rows and the attic are permanent.

IF A VERIFICATION EVER FAILS

  Keep the source folders. The report names exactly which symbols or files did
  not arrive. Nothing has been deleted at that point -- verification runs after
  writing but before you would ever clean anything up.
"""

CLI_TOPIC = """\
THE COMMAND LINE

Everything the GUI does, scriptable. One launcher handles both:

    Harness.bat                      opens this GUI
    Harness.bat atlas <subcommand>   runs the CLI instead

MAPPING AND LOOKUP

    atlas sweep [root] --index     classify and index a folder of projects
    atlas index <path>             index one project
    atlas projects                 what is registered
    atlas buckets                  the twenty buckets and their contents
    atlas get <address>            fetch one symbol, with its edges
    atlas expand <address>         it, plus what it calls
    atlas impact <address>         everything that calls it
    atlas find "<intent>"          does this already exist?

WRITING

    atlas gate <name> --intent "..." --lines N --bucket <b>
    atlas plan-insert <name> --lines N --bucket <b>

ENTITIES

    atlas absorb <path> --write     integrate a project and its tools
    atlas entities --runnable       everything you can run
    atlas run "<name>"              run one
    atlas manifest                  the full capability list
    atlas release <project>         unregister; files untouched

RESHAPING

    atlas ingest <zip|md|dir>      unpack, dedupe, place, index, optionally run
    atlas fanout <doc> --out <dir> explode a transcript into a real tree
    atlas condense                 build classes.py and functions.py
    atlas dupes --cross-project    duplicated code across everything
    atlas variants                 folders that are copies of one project
    atlas reconcile --family <k>   align their symbols; show the plan
    atlas coagulate --family <k> --write    merge, with the loss proof

HISTORY

    atlas ledger                   recent mutations
    atlas restore <id> --write     put files back
    atlas attic                    retired code

HANDING IT TO A MODEL

    atlas export                   ATLAS.md, INDEX.md files, LLM_GUIDE.md
    atlas preamble                 a system-prompt block
    atlas budget                   measured token cost per tier
"""

GLOSSARY = """\
GLOSSARY

ADDRESS       @bucket/project:file.py#Symbol. Permanent, line-number-free.

ATLAS.md      Tier 0. Every bucket and project, one line each. The only file a
              model should always read.

BUCKET        One of twenty subject areas. Every project belongs to exactly one.

COAGULATE     Merge several divergent copies of one project into one, with an
              accounting that proves nothing was lost.

CONDENSE      Project the indexed universe into classes.py and functions.py.

ENTITY        Something a project lets you DO: a gui, cli, command, service,
              script, skill, notebook, or api.

FAMILY        A set of folders detected as copies of the same project.

GATE          The three checks before new code: dedupe, budget, placement.

HOLD          A conflict the merger refused to resolve. Written from the base
              variant and flagged in-file, never silently decided.

HUB           A symbol many others call. Expensive to change; read it first.

INDEX.md      Tier 1. Every symbol in one project, one line each, no bodies.

MISS          The dedupe gate's authoritative "this does not exist". Stop
              searching and create it.

RESIDUE       A file's module-level content -- imports, __main__ blocks -- that
              lives outside any symbol and is tracked separately.

SHAPE HASH    A hash of code after local names are alpha-renamed and literals
              erased. Two copies styled differently still collide.

SLICE         One symbol's code, fetched by address, with its edges attached.

SWEEP         A read-only pass over a folder of projects, classifying each.

TIER 0/1/2    Atlas / per-project index / individual slices.

TOMBSTONE     The flagged line left in the index when code is retired.
"""

FAQ = """\
COMMON QUESTIONS

"Will this move or change my files?"

   No. Sweeping and indexing are read-only. Absorption adds index rows only.
   The things that write -- ingest, coagulate, condense, mirror -- all write to
   NEW locations, back up first, and are listed in the Ledger. Source folders
   are never modified.

"I indexed something and now a slice looks wrong."

   The file changed after indexing, so the stored line spans moved. Every slice
   carries a body hash and will tell you it is STALE. Re-index that project.
   After editing atlas/ or studio/ themselves, run:

   python bootstrap_index.py

"The bucket is wrong."

   Classification is scored, and low-confidence calls are flagged as such. Fix
   it in the Atlas tab: select the project, set the bucket, Apply. The override
   is recorded as the verdict.

"Why did the dedupe gate say MISS when something similar exists?"

   It is calibrated to distrust a shared verb. "render a dome" will not match
   a function called _render just because both say render -- only matching the
   SUBJECT counts. If you think a MISS is wrong, search the Index tab directly.

"Why was a merge conflict not resolved?"

   Because two variants genuinely implemented it differently, and guessing is
   how work gets lost. The base version is written and flagged in-file with a
   comment naming every alternative and where each is archived. To decide in
   advance, use --policy lead with the folder you were actually working in.

"How much context does this actually save?"

   Measured, not claimed: run `atlas budget`. Roughly 4-5x on the targeted path.
   The bigger saving is behavioural -- one index instead of exploring, three
   slices instead of whole files, and a MISS that ENDS a search.

"Can I use this without the GUI?"

   Entirely. Everything is in the CLI. See the Command line topic.

"What if I want to stop using it?"

   atlas release <project> for each, or just delete the .atlas folder. Nothing
   else in your projects was ever touched.
"""

TOPICS: dict[str, object] = {
    "start": START,
    "first_run": FIRST_RUN,
    "tabs": TABS_TOPIC,
    "which": WHICH_TOOL,
    "addresses": ADDRESSES,
    "gate": GATE_TOPIC,
    "absorb": ABSORB_TOPIC,
    "buckets": BUCKETS_TOPIC,
    "safety": SAFETY,
    "cli": CLI_TOPIC,
    "glossary": GLOSSARY,
    "faq": FAQ,
    "workspace": _workspace_view,
}

SECTIONS = [
    ("Start", [
        ("start", "What this is"),
        ("first_run", "First five minutes"),
        ("which", "Which tool do I want?"),
    ]),
    ("How it works", [
        ("addresses", "Addresses & the index"),
        ("gate", "The write gate"),
        ("absorb", "Entities & absorption"),
        ("buckets", "Buckets & priority"),
        ("safety", "Nothing is ever lost"),
    ]),
    ("Reference", [
        ("tabs", "The tabs"),
        ("cli", "The command line"),
        ("glossary", "Glossary"),
        ("faq", "Common questions"),
        ("workspace", "My workspace (live)"),
    ]),
]

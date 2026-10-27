# LLM_GUIDE

You are working in a codebase that is mapped, not browsed. Follow this protocol and you
will use a fraction of the context you would otherwise need.

## The protocol

1. **Read `ATLAS.md` first.** It is small and it is the only file you must always read.
   It tells you which of the twenty buckets, and which project, the request belongs to.
2. **Read that project's `INDEX.md`.** Every class and function is one line: kind, line
   span, body hash, signature, what it calls (`>`), and what calls it (`<`).
3. **Fetch code by address, never by file.**
   `atlas get @bucket/project:path.py#Symbol`
   returns exactly that symbol, with its own edge comments attached. Follow those edges
   to decide what to fetch next. `atlas expand <address> --depth 1` does it in one call.
4. **Before writing anything new, run the dedupe gate.**
   `atlas find "<what you are about to build>"`
   * `HIT` -- reuse the match, or state plainly why a new symbol is justified.
   * `MISS` -- this is **authoritative**. The code does not exist. Stop searching for it
     and create it. Do not grep. Do not open files "just to be sure."
5. **Ask where it goes. Do not choose yourself.**
   `atlas plan-insert <name> --lines N --bucket <bucket>`
   returns the exact file and line. Placement is the engine's job, so code lands in the
   right place the first time and the index never drifts.
6. **Nothing is deleted.** Superseded code is retired to `.atlas/attic/` and keeps a
   flagged tombstone line in the index. If you are replacing something, retire it --
   do not remove it.

## What not to do

* Do not read a whole source file. If you think you need to, you need three slices.
* Do not grep for a symbol you have already been told is a `MISS`.
* Do not invent an address. If it is not in `INDEX.md`, it does not exist.
* Do not write a function without a declared line count. The budget gate will refuse it.

## Reading the index line

```
F L142-198  h:a3f9  ReasonLoop.step(self, obs: Observation) -> Action   >loop.plan  <harness.tick
```

`F` function, lives at lines 142-198, body hash `a3f9`, calls `loop.plan`, is called by
`harness.tick`. To understand it, fetch it and `loop.plan`. To change it safely, check
`harness.tick` first.

## Resolving vague requests

When a request does not name a project, resolve it against the pinned and high-priority
projects listed at the end of `ATLAS.md` before generating anything new. If the user asks
for a capability that already exists in a hot project, use that project. Existing
capability beats new code.

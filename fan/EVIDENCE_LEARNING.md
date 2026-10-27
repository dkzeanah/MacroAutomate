# Evidence-driven learning and the Learning Workbench

The intended system is an incremental, context-sensitive learner whose claims
are justified by inspectable observations and tests. Repeated evidence should
strengthen a pattern within the environments where it has been checked.
Contradictions and alternate continuations should remain visible. The system
should identify possible confounds, propose small experiments, and explain its
findings through lessons, maps, and rehearsals that do not disrupt other apps.

This implementation adds a deterministic evidence layer alongside the existing
learners. It uses no model calls to build explanations or lessons.

## Move a secondary window

Hold **Ctrl**, hold the **right mouse button** anywhere on one of Fan's secondary
windows, and drag. Release either to finish. This includes the click-through
portal HUD. Fan does not activate the window or send a right-click through it.
The main window and other applications are excluded. Release clamps the whole
window to one monitor. The portal HUD uses physical pixels on mixed-DPI displays.

The portal HUD, validation panel, study side windows, and Workbench restore saved
positions. Other secondary windows can also be dragged; their existing opening
code still determines where they initially appear. Live updates respect dragged
positions for the portal and activity HUDs and the validation panel.

## Review a learned item

Open **Learning Workbench** from the tray, or **Explain learning** on Live Portal,
the validation panel, or the raw Study Live Console.

1. Select a claim. The explanation shows what it means, how you can use it,
   its evidence, environment layers, uncertainties, and original source IDs.
2. Click **Show lesson**. The generated program advances through the claim's
   observation, evidence, context, alternatives, rehearsal and next experiment.
   Stored usage sequences also get an individual simulated step for each action.
3. Click **Replay one pair** to compare stored checks under two environment
   values and advance one environment permutation plan. Click **Refresh** to
   see the persisted comparison and plan in the explanation.
4. **Stop lesson** stops playback. Closing the window also stops it.

All playback happens in the Workbench. It sends no clicks, keys, text, focus
changes, or application commands to other windows. It does not execute the
described learned workflow. The raw console remains available and logging
continues, but the console no longer opens automatically at startup.

For a demonstration using an existing varied click sequence, start Fan with
`--learning-workbench`. The program chooses an actual stored sequence, selects
its claim and starts its local rehearsal. Nothing is invented for this demo.

## What the learner measures

- **Observation only:** a capture, discovered control, model/local answer
  proposal, or imported historical record. Frequency is not verification.
- **Tentative verification:** one or more explicit checks have passed.
- **Supported in observed contexts:** at least five spaced positive checks,
  two observed environment combinations, and two program sessions, with no
  recorded negative check for that claim.
- **Contradicted / review:** a negative check exists and requires inspection.

Raw checks are retained, but repeated checks of the same outcome in the same
environment within 30 seconds do not increase the score. This reduces burst
inflation; it does not guarantee statistically independent sampling. The shown
Wilson lower bound describes recorded repeatability, not a probability of truth.

Vision Scout records candidate capture and explicit recognition/certification
tests. Usage Predictor records visual checks and scores two-event continuation
predictions **before training on the next natural event**. The next event can
support or contradict the prediction. A different user choice is not an error
in the application. App Learner/discovery captures remain observations.

Study proposals remain observations. User/source/portal confirmations and
disputes become explicit outcomes. Distinct answers to the same question have
separate claim identities, so a replacement cannot inherit another answer's
support. The study source, question and answer evidence remain inspectable.

Old data is imported in small batches as historical observations. Its saved
frequency, state, answer, shortcut or role is shown where available, but prior
counts are not reconstructed into independent checks. In particular, a pattern
seen eight times is not presented as eight successful held-out predictions.

## Background experiments and confounds

When enabled, the scheduler attempts one bounded unit every 45–90 seconds,
after at least 1.5 seconds of physical input inactivity. It processes only local
stored data. It compares environment levels and checks whether other recorded
variables can be held fixed in matching strata. An unmatched comparison says the
effect cannot be separated from confounding. Unmeasured confounds remain possible.

The scheduler also traverses the Cartesian product of known executable, window
class, size, DPI, monitor and time-band values in randomized order without
replacement. A persistent cursor resumes after restart. An unseen combination
becomes an evidence-collection request; it is never reported as a passed test.
Some combinations may be infeasible. The finite work budget covers up to eight
levels per dimension, 2,000 checks per claim, and the latest 100 claims for
background selection. Larger claims are paused for manual review. New levels
start a new traversal; exhausted unchanged traversals stay exhausted.

These are observational replays and experiment plans. This version does not
manipulate real application state to establish causal effects or automatically
execute newly inferred desktop workflows. Fresh real-world checks still come
from the existing recognition, confirmation and natural-event paths. Replays
never add support to their own source claims.

Disable **Spread out background replays** to stop the scheduler; manual review
and recording still work. Lessons, trials, exploration cursors and evidence are
stored in additive `learning_*` tables in Fan's existing SQLite database.

## Validation

`fan/LearningWorkbench_Test.ahk` uses an isolated synthetic database and checks
deduplication, contradictions, context/session support, matched confounds,
non-repeating permutation coverage, unknown combinations, absence of replay
self-reinforcement, answer identities, prospective prediction, generated lessons,
physical monitor containment, saved placement and foreground preservation.

# Agent Note: Local-first creator operations companion

Status: implemented

English | [中文](2026-08-23-local-first-creator-operations.zh.md)

## Problem

Creators who use DeepSeek Harness for research and automation still need a durable place to turn ideas into sourced briefs, preserve human approval, schedule official-platform posts, and compare aggregate outcomes. Sending every planning step to a paid model spends tokens on routine formatting, while browser automation against personal accounts creates fragile access, privacy, and platform-policy risks.

The Harness Web preset owns agent sessions and tools; a content calendar, platform credentials, publishing queue, and performance database are a separate application concern. Folding those records into the Web preset would couple a specialized creator workflow to the general agent runtime and make platform writes less visibly deliberate.

## Decision

`examples/jsonrpc-agent/creator_ops.py` and `creator_ops_gui.pyw` form a standalone desktop companion. The existing `ollama_preprompt.py` client supplies schema-constrained local Ollama calls and an explicit DeepSeek Harness review handoff. Creator Operations does not patch the Harness Web preset.

SQLite stores topics, editable briefs, approvals, account references, schedules, aggregate observations, destinations, metrics, experiments, and workflow events. The database stores the name of each credential environment variable, never its value. Editing an approved brief returns it to draft status.

Every publishing path starts as a dry run. A live official-API request requires a current human approval, a due scheduled destination, an enabled account, the named credential, and `CREATOR_OPS_LIVE_PUBLISH=1` in the process environment. The worker claims a destination as `publishing` before the network call and leaves an ambiguous failure for operator review instead of retrying it. The implementation supports Facebook Pages, Instagram professional accounts, and TikTok Content Posting API photo posts; it does not automate personal profiles or platform interfaces.

Local generation produces creator-editable briefs, not media or evidence. The system prompt forbids fabricated facts and sources, fake community posts, impersonation, harassment, covert interface automation, personal targeting, and person-level commenter tracking. Authorized research imports contain aggregate themes, sentiment, and a rights basis. Metrics and A/B summaries use aggregate destination results and do not claim that correlation proves causation or virality.

## Alternatives considered

**Patch the Harness Web application.** Rejected because content operations have a different data lifecycle, credential set, scheduling model, and audience from agent sessions. A separate GUI imports the supported Python orchestration code without changing the general Web preset.

**Automate each platform's browser interface.** Rejected because selectors and personal sessions are unstable, bypass official review and permissions, and make human approval difficult to prove. Official APIs expose explicit account identity, permissions, and errors.

**Store access tokens in SQLite for convenience.** Rejected because schedules and analytics are useful to back up or inspect, while bearer tokens require a narrower secret-management lifecycle. Account records hold only environment-variable names.

**Let the model publish or optimize engagement autonomously.** Rejected because model output is not a factual source, engagement metrics do not establish audience value, and automated controversy can turn uncertainty into deception or harassment. The creator edits and approves every item; experiments compare declared variants and retain aggregate evidence.

## Testing

Offline Python tests cover schema creation and topic seeding, approval invalidation after edits, schedule refusal before approval, dry-run non-mutation, credential non-persistence, local brief validation, deterministic latest-metric selection, aggregate-only observation fields, and A/B calculations. GUI construction is checked with a Tcl/Tk-capable Python runtime without starting the event loop. Tests do not make platform requests or paid DeepSeek calls.

## Consequences

Routine ideation, scheduling, and learning stay local and free after the creator supplies Ollama compute. Paid review and platform writes are explicit actions with visible prerequisites. The cost is a second desktop application and the operational work of maintaining official developer applications, tokens, public media hosting, Task Scheduler, and platform-version configuration.

The companion cannot promise a viral topic, monetization invitation, revenue result, or platform eligibility. It records source-backed hypotheses and aggregate outcomes so the creator can make the next decision with better evidence.

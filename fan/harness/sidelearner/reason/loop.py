"""AgentLoop: SideLearner's own reasoning loop around any provider.

Loop anatomy (one turn = one model call + optional tool execution):
  route -> context build -> [model proposes JSON -> policy-gated tool call
  -> result fed back] x N -> final answer -> local verification pass.

The verification pass is pure local logic (no model): written files are
checked to exist, and an optional verification command (tests/lint) runs
after any file writes. The loop also degrades to a fully deterministic
mode — heuristic plans and skills — when no provider is healthy.
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Optional

from ..events import EventBus
from ..memory.store import Store
from ..memory.twin import DigitalTwin
from ..providers.cli_agents import CLIAgentAdapter
from ..providers.registry import ProviderRegistry
from ..router.router import RouteContext, Router
from ..sessions import SessionLog
from ..tools.registry import ToolRegistry, ToolResult
from .planner import heuristic_plan
from .schema import CONTRACT_INSTRUCTIONS, parse_agent_message

log = logging.getLogger("sidelearner.reason")


@dataclass
class AgentResult:
    ok: bool
    answer: str
    route: Any = None
    steps: list = field(default_factory=list)
    verification: list = field(default_factory=list)
    session_id: Optional[str] = None
    deterministic: bool = False
    error: Optional[str] = None


class AgentLoop:
    def __init__(
        self,
        config: Any,
        registry: ProviderRegistry,
        router: Router,
        tools: ToolRegistry,
        sessions_dir: Path,
        twin: Optional[DigitalTwin] = None,
        bus: Optional[EventBus] = None,
        cli_agents: Optional[CLIAgentAdapter] = None,
        skill_engine: Optional[Any] = None,
        ctx_provider: Optional[Callable[[], RouteContext]] = None,
        ask_callback: Optional[Callable[[str], bool]] = None,
        store: Optional[Store] = None,
    ) -> None:
        self.config = config
        self.registry = registry
        self.router = router
        self.tools = tools
        self.sessions = SessionLog(sessions_dir)
        self.twin = twin
        self.bus = bus
        self.cli_agents = cli_agents or CLIAgentAdapter()
        self.skill_engine = skill_engine
        self.ctx_provider = ctx_provider
        self.ask_callback = ask_callback
        self.store = store
        agent_cfg = config.get("agent", {})
        self.max_steps = int(agent_cfg.get("max_steps", 12))
        self.max_tokens_out = int(agent_cfg.get("max_tokens_out", 2048))
        self.temperature = float(agent_cfg.get("temperature", 0.2))
        self.compact_at = int(agent_cfg.get("compact_at_tokens", 48000))
        self.verify_cmd = agent_cfg.get("verify_cmd")
        self.retrieve_facts = bool(agent_cfg.get("retrieve_facts", True))

    # -- helpers -----------------------------------------------------------
    def _session_add(self, session_id: str, task: str, mode: str, model: str) -> None:
        if self.store is not None:
            self.store.session_add(session_id, task, mode=mode, model=model)

    def _session_finish(self, session_id: str, outcome: str, steps: int, answer: str) -> None:
        if self.store is not None:
            self.store.session_finish(session_id, outcome, steps, answer)

    def _emit(self, type: str, data: dict, source: str = "agent") -> None:
        if self.bus is not None:
            self.bus.emit(type, data, source=source)

    def _system_prompt(self, allowed_tools: set[str]) -> str:
        business = self.config.get("business", {})
        domain = business.get("domain", "")
        extra = business.get("prompt", "")
        policy = "Risky operations (shell commands, file writes) execute only inside the sandbox roots and are logged."
        memory_note = ""
        mem_path = Path(self.config.workspace) / "MEMORY.md"
        if mem_path.exists():
            try:
                memory_note = "\n## Workspace memory (MEMORY.md)\n" + mem_path.read_text(encoding="utf-8")[:4000]
            except OSError:
                pass
        tools_json = self.tools.schemas_for(allowed_tools)
        parts = [
            CONTRACT_INSTRUCTIONS,
            f"Business profile: {business.get('name', 'default')}" + (f" — {domain}" if domain else ""),
            extra if extra else "",
            f"Policy: {policy}",
            f"Available tools (JSON):\n{tools_json}",
            memory_note,
        ]
        return "\n\n".join(p for p in parts if p)

    def _estimate_tokens(self, messages: list[dict]) -> int:
        return sum(len(str(m.get("content", ""))) // 4 for m in messages)

    def _compact(self, messages: list[dict]) -> list[dict]:
        kept = [messages[0]]
        kept.append({"role": "user", "content": "[context compacted: earlier steps summarized by the loop]"})
        kept.extend(messages[-6:])
        return kept

    # -- main --------------------------------------------------------------
    def run(
        self,
        task: str,
        mode: str = "auto",
        cwd: Optional[str] = None,
        extra_context: str = "",
        on_event: Optional[Callable[[dict], None]] = None,
        ask_callback: Optional[Callable[[str], bool]] = None,
    ) -> AgentResult:
        ask_callback = ask_callback or self.ask_callback
        ctx = self.ctx_provider() if self.ctx_provider else RouteContext()
        route = self.router.route(task, ctx)
        if route.intent == "workflow" and self.skill_engine is not None:
            route.skill = self.router.match_skill(task, self.skill_engine.skills)

        session_id = self.sessions.start({"task": task, "mode": mode, "route": route.describe()})
        self._session_add(session_id, task, mode=mode, model=route.model or "deterministic")

        if mode == "deterministic" or route.local_only:
            return self._run_deterministic(task, route, session_id, cwd, on_event, ask_callback)

        provider = route.provider
        if provider is None:
            return self._run_deterministic(task, route, session_id, cwd, on_event)

        # CLI-agent delegation: tasks can be handed to claude/codex wholesale.
        if route.intent == "code_edit" and self.config.get("agent.cli_delegate"):
            delegated = self._maybe_delegate(task, cwd, session_id, on_event)
            if delegated is not None:
                return delegated

        allowed = set(route.tools) if route.tools else set(self.tools.names())
        messages: list[dict] = [
            {"role": "system", "content": self._system_prompt(allowed)},
        ]
        context = self._task_message(task, cwd, extra_context, skill_hint=route.skill)
        messages.append({"role": "user", "content": context})
        self.sessions.append("model.message", {"role": "system", "content": messages[0]["content"][:2000]})
        self.sessions.append("model.message", {"role": "user", "content": context})

        steps: list[dict] = []
        written_files: list[str] = []
        answer = ""
        failed_providers: set[str] = set()
        last_calls: list[tuple] = []  # (tool, args-signature, ok) for repeat-guard
        consecutive_empty = 0
        for step_no in range(1, self.max_steps + 1):
            if self._estimate_tokens(messages) > self.compact_at:
                messages = self._compact(messages)
            self._emit("agent.request", {"step": step_no, "model": route.model}, source="agent")
            try:
                completion = provider.chat(
                    messages,
                    temperature=self.temperature,
                    max_tokens=self.max_tokens_out,
                    stream=True,
                    on_token=lambda tok, ev=on_event: ev and ev({"kind": "token", "text": tok}),
                )
            except Exception as exc:  # noqa: BLE001
                failed_providers.add(provider.name)
                fallback = self.registry.pick(
                    route.tier, route.capabilities_required, exclude=failed_providers
                )
                if fallback is not None:
                    log.warning("provider %s failed (%s); cascading to %s", provider.name, exc, fallback.name)
                    provider = fallback
                    route.provider_name, route.model, route.provider = fallback.name, fallback.model, fallback
                    messages.append({"role": "user", "content": "[note: provider switched; continue the task]"})
                    continue
                log.warning("provider %s failed and no fallback is healthy: %s", provider.name, exc)
                self.sessions.append("session.end", {"summary": f"provider failed: {exc}; falling back to deterministic mode"})
                return self._run_deterministic(task, route, session_id, cwd, on_event, ask_callback)

            text = completion.text.strip()
            if not text:
                # Empty completions are transport/model hiccups, not answers.
                consecutive_empty += 1
                self.sessions.append("model.message", {"role": "assistant", "content": "[empty]"})
                if consecutive_empty >= 3:
                    answer = "Stopped: the provider returned empty responses three times in a row."
                    break
                messages.append({"role": "user", "content": "[Your previous response was empty. Continue the task.]"})
                continue
            consecutive_empty = 0
            self.sessions.append("model.message", {"role": "assistant", "content": text})
            parsed = parse_agent_message(text)
            if parsed["tool"]:
                tool_name = str(parsed["tool"])
                tool_args = parsed["tool_args"] or {}
                self.sessions.append("tool.call", {"tool": tool_name, "args": tool_args})
                if on_event:
                    on_event({"kind": "tool", "tool": tool_name, "args": tool_args})
                result = self.tools.execute(tool_name, tool_args, ask=ask_callback)
                self.sessions.append("tool.result", {"tool": tool_name, "ok": result.ok, "denied": result.denied, "text": result.text[:4000]})
                step_record = {
                    "step": step_no,
                    "tool": tool_name,
                    "args": tool_args,
                    "ok": result.ok,
                    "denied": result.denied,
                    "output": result.text[:600],
                }
                steps.append(step_record)
                written = result.data.get("written") or result.data.get("created") or []
                written_files.extend(str(w) for w in written if w)
                self._emit("agent.tool.result", {"tool": tool_name, "text": result.text[:3000], "ok": result.ok}, source="agent")
                if on_event:
                    on_event({"kind": "tool_result", "ok": result.ok, "denied": result.denied, "text": result.text[:400]})
                messages.append(
                    {
                        "role": "user",
                        "content": f"Tool result for {tool_name}: {result.text[:6000]}"
                        + ("\n[This call was DENIED by policy. Do not retry it; adapt.]" if result.denied else ""),
                    }
                )
                # Own reasoning guard: identical failing calls three times in a
                # row mean the model is stuck — nudge it out of the loop.
                last_calls.append((tool_name, repr(sorted(tool_args.items())), result.ok))
                if len(last_calls) > 3:
                    last_calls.pop(0)
                if len(last_calls) == 3 and len(set(last_calls)) == 1 and not last_calls[0][2]:
                    messages.append(
                        {
                            "role": "user",
                            "content": "[guard] This exact tool call failed 3 times in a row. "
                            "Stop repeating it. Try a different approach or answer with the blocker.",
                        }
                    )
                    last_calls.clear()
                self.sessions.append("model.message", {"role": "user", "content": f"[tool result {tool_name}] {result.text[:2000]}"})
                continue
            answer = parsed["answer"] or ""
            break

        if not answer:
            answer = "Stopped: reached the maximum step budget without a final answer. Last step output may help diagnose."

        verification = self._verify(written_files, answer, cwd)
        outcome = "ok"
        self.sessions.append("agent.verdict", {"notes": "; ".join(verification)})
        self.sessions.append("session.end", {"summary": answer[:1000]})
        self._session_finish(session_id, outcome, len(steps), answer)
        self._emit("agent.done", {"answer": answer[:1000], "steps": len(steps)}, source="agent")
        return AgentResult(
            ok=True, answer=answer, route=route, steps=steps, verification=verification,
            session_id=session_id, deterministic=False,
        )

    def _task_message(self, task: str, cwd: Optional[str], extra_context: str, skill_hint: Optional[str] = None) -> str:
        parts = [f"TASK: {task}"]
        if cwd:
            parts.append(f"Working directory: {cwd}")
        if extra_context:
            parts.append(f"Additional context:\n{extra_context}")
        if skill_hint:
            parts.append(
                f"A workflow skill matches this task: {skill_hint}. "
                "Strongly prefer calling skill.run with that name — it executes the "
                "business procedure deterministically. Only deviate if the task clearly differs."
            )
        if self.retrieve_facts and self.twin is not None:
            try:
                block = self.twin.graph.context_block(task, k=6)
                if block:
                    parts.append(block)
            except Exception:  # noqa: BLE001
                pass
        return "\n\n".join(parts)

    # -- deterministic mode ------------------------------------------------
    def _run_deterministic(
        self,
        task: str,
        route: Any,
        session_id: str,
        cwd: Optional[str],
        on_event: Optional[Callable[[dict], None]],
        ask_callback: Optional[Callable[[str], bool]] = None,
    ) -> AgentResult:
        """No provider needed: skills and heuristic plans, executed directly."""
        self.sessions.append("session.end", {"summary": "deterministic mode (no healthy provider)"})
        steps: list[dict] = []
        verification: list[str] = []
        skill = None
        if self.skill_engine is not None:
            skill = self.skill_engine.find(route.skill) if route.skill else None
            if skill is None:
                skill = self.skill_engine.match(task)
        if skill is not None:
            result = self.skill_engine.run(skill, vars={"task": task, "cwd": cwd or str(self.config.workspace)})
            steps = [{"step": i + 1, "tool": s.get("tool", ""), "args": s.get("args", {}), "ok": s.get("ok"), "output": s.get("output", "")[:400]} for i, s in enumerate(result.steps)]
            answer = result.output or "skill finished"
            self._session_finish(session_id, "ok" if result.ok else "failed", len(steps), answer)
            return AgentResult(ok=result.ok, answer=answer, route=route, steps=steps, verification=verification, session_id=session_id, deterministic=True)
        plan = heuristic_plan(task)
        if plan is None:
            message = (
                "No model provider is healthy and no deterministic plan or skill matched this task. "
                "Start Ollama (`ollama serve`) or configure a provider in config.yaml, or phrase the task "
                "as a supported shape: 'run tests', 'list files', 'read <file>', 'search TODO', 'install <pkg>'."
            )
            self._session_finish(session_id, "failed", 0, message)
            return AgentResult(ok=False, answer=message, route=route, steps=[], session_id=session_id, deterministic=True, error=message)
        for i, step in enumerate(plan.steps, 1):
            self.sessions.append("tool.call", {"tool": step.tool, "args": step.args})
            result = self.tools.execute(step.tool, step.args, ask=ask_callback)
            self.sessions.append("tool.result", {"tool": step.tool, "ok": result.ok, "text": result.text[:2000]})
            steps.append({"step": i, "tool": step.tool, "args": step.args, "ok": result.ok, "output": result.text[:600]})
            if on_event:
                on_event({"kind": "tool_result", "ok": result.ok, "text": result.text[:400]})
        answer = "\n".join(f"• {s['tool']}: {'ok' if s['ok'] else 'FAILED'} — {s['output'][:300]}" for s in steps)
        self._session_finish(session_id, "ok" if all(s["ok"] for s in steps) else "failed", len(steps), answer)
        return AgentResult(ok=True, answer=answer, route=route, steps=steps, session_id=session_id, deterministic=True)

    # -- optional delegation to claude/codex --------------------------------
    def _maybe_delegate(self, task: str, cwd: Optional[str], session_id: str, on_event) -> Optional[AgentResult]:
        delegate_cfg = self.config.get("agent.cli_delegate")
        if not delegate_cfg or isinstance(delegate_cfg, bool):
            return None
        agent_name = delegate_cfg.get("agent") if isinstance(delegate_cfg, dict) else str(delegate_cfg)
        agent = self.cli_agents.get(agent_name)
        if agent is None or not agent.available():
            log.info("delegation target %r unavailable; running in-loop instead", agent_name)
            return None
        from ..providers.base import ProviderError

        if on_event:
            on_event({"kind": "delegate", "agent": agent_name})
        try:
            result = agent.run(task, cwd or self.config.workspace)
        except ProviderError as exc:
            self._session_finish(session_id, "error", 0, str(exc))
            return AgentResult(ok=False, answer="", session_id=session_id, error=str(exc))
        self.sessions.append("agent.delegate", {"agent": agent_name, "exit_code": result.exit_code, "text": result.text[:4000]})
        self._session_finish(session_id, "ok" if result.exit_code == 0 else "failed", 1, result.text[:2000])
        return AgentResult(ok=result.exit_code == 0, answer=result.text, session_id=session_id, deterministic=False)

    # -- verification (own reasoning, no model) -----------------------------
    _WRITE_CLAIM_RE = re.compile(
        r"\b(?:wrote|written|created|saved|generated|updated|deployed|produced)\s+"
        r"(?:to\s+|the\s+file\s+|a\s+file\s+|file\s+|report\s+)?"
        r"([\w.\-\\/]{1,120}\.(?:py|md|txt|csv|json|yaml|yml|log|js|ts|jsx|tsx|html|css|sh|ps1|bat|ini|toml|db))",
        re.IGNORECASE,
    )

    def _verify(self, written_files: list[str], answer: str, cwd: Optional[str]) -> list[str]:
        notes: list[str] = []
        seen: set[str] = set()
        for path in written_files:
            if path in seen:
                continue
            seen.add(path)
            exists = Path(path).exists()
            notes.append(f"{path}: {'exists' if exists else 'MISSING after write claim'}")
        # Files the model *claims* to have written near a write verb, but that
        # no tool actually wrote, are hallucination flags. Mere mentions of
        # filenames (e.g. directory listings) are not flagged, and the same
        # file referenced by a different path form is recognized.
        written_basenames = {Path(w).name for w in written_files}
        for match in self._WRITE_CLAIM_RE.findall(answer or ""):
            if match in seen or match in written_files:
                continue
            if Path(match).name in written_basenames:
                continue  # same file, different path spelling
            seen.add(match)
            notes.append(f"{match}: MISSING after write claim (no tool wrote it)")
        if written_files and self.verify_cmd:
            from ..tools.shell import run_verify

            result = run_verify(self.tools, self.verify_cmd, cwd=cwd or str(self.config.workspace))
            notes.append(f"verification command `{self.verify_cmd}`: {'ok' if result['ok'] else 'failed — ' + result['text'][:300]}")
        return notes

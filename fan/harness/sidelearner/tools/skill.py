"""Skill tools: let the agent run business workflows as first-class tools."""
from __future__ import annotations

from typing import Any, Callable, Optional


def register_skill_tools(registry, engine: Any, provider_factory: Optional[Callable[[], Any]] = None) -> None:
    from .registry import ToolSpec

    def list_skills() -> dict:
        rows = [f"- {s.name}: {s.description}" for s in engine.skills]
        return {"ok": True, "text": "available workflow skills:\n" + "\n".join(rows) or "(none)"}

    def run(name: str = "", skill_name: str = "", **vars: Any) -> dict:
        name = name or skill_name
        if not name:
            return {"ok": False, "text": "skill.run needs the skill name (e.g. skill.run name=workspace_recon)"}
        skill = engine.find(name)
        if skill is None:
            return {"ok": False, "text": f"unknown skill '{name}'; use skill.list to see them"}
        provider = provider_factory() if provider_factory else None
        result = engine.run(skill, vars={"cwd": str(registry.config.workspace), **vars}, provider=provider)
        lines = [f"skill {name}: {'ok' if result.ok else 'FAILED'}"]
        for step in result.steps:
            lines.append(f"  [{step['step']}] {step['tool']}: {'ok' if step.get('ok') else 'failed'} — {str(step.get('output', ''))[:200]}")
        lines.append(f"output: {result.output[:1500]}")
        return {
            "ok": result.ok,
            "text": "\n".join(lines),
            "output": result.output[:1500],
            "steps": len(result.steps),
            "written": list(dict.fromkeys(result.written)),
        }

    registry.register_many(
        [
            ToolSpec("skill.list", "List available business workflow skills.", {}, list_skills, "low", "skills", True),
            ToolSpec(
                "skill.run",
                "Run a business workflow skill by name.",
                {"name": "str (skill name)", "skill_name": "str (alias for name)", "vars": "object?"},
                run,
                "medium",
                "skills",
                False,
            ),
        ]
    )

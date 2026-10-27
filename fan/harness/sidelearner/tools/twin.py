"""Twin tools: query the digital twin from the agent loop and skills."""
from __future__ import annotations

from typing import Any


def register_twin_tools(registry, twin: Any) -> None:
    from .registry import ToolSpec

    def status() -> dict:
        st = twin.status()
        lines = [
            f"observations: {st['observations']}",
            f"ledger: {st['ledger']['total']} total, {st['ledger']['learned']} learned ({st['ledger']['learned_pct']}%)",
            f"graph: {st['graph']['facts']} facts, {st['graph']['entities']} entities, {st['graph']['relations']} relations",
            f"top entities: {', '.join(st['graph']['top_entities'][:5])}",
            f"open gaps: {st['open_gaps']}",
        ]
        return {"ok": True, "text": "\n".join(lines), "status": st}

    def ask(question: str, k: int = 8) -> dict:
        result = twin.ask(question, k=k)
        if not result["hits"]:
            return {"ok": True, "text": f"the digital twin knows nothing relevant about: {question}"}
        lines = [f"what the twin knows about: {question}"]
        for h in result["hits"]:
            lines.append(f"- [{h['kind']}#{h['id']} sim={h['similarity']}] {h['text'][:300]}")
        return {"ok": True, "text": "\n".join(lines), "hits": result["hits"]}

    def gaps() -> dict:
        rows = twin.gaps()
        if not rows:
            return {"ok": True, "text": "no open learning gaps"}
        lines = [f"{len(rows)} open learning gaps (data that appeared but was not captured):"]
        for g in rows[:20]:
            lines.append(f"- gap#{g['id']} ({g['created']}): {g['reason']} :: {g['observation'][:160]}")
        return {"ok": True, "text": "\n".join(lines), "gaps": rows}

    def resolve_gap(gap_id: int, note: str = "reviewed") -> dict:
        twin.resolve_gap(gap_id, note)
        return {"ok": True, "text": f"gap #{gap_id} resolved ({note})"}

    registry.register_many(
        [
            ToolSpec("twin.status", "Status of the learning digital twin (observations, facts, gaps).", {}, status, "low", "twin", True),
            ToolSpec("twin.ask", "Ask the digital twin what it has learned about a topic.", {"question": "str", "k": "int?"}, ask, "low", "twin", True),
            ToolSpec("twin.gaps", "List learning gaps: data that appeared but was never captured.", {}, gaps, "low", "twin", True),
            ToolSpec("twin.resolve_gap", "Resolve (acknowledge) a learning gap.", {"gap_id": "int", "note": "str?"}, resolve_gap, "medium", "twin", False),
        ]
    )

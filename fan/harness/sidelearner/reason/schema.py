"""The reasoning contract: SideLearner's own structured agent JSON schema."""
from __future__ import annotations

from typing import Any

from ..utils import json_loads_lenient

# The single response shape the loop enforces. Deterministic and portable
# across every provider — local Ollama models handle it as well as frontier
# models, because it is plain JSON-in-text, not native tool calling.
AGENT_JSON_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "thought": {"type": "string", "description": "One-line reasoning about the current situation."},
        "tool": {"type": ["string", "null"], "description": "Tool name to call, or null when answering."},
        "tool_args": {"type": ["object", "null"], "description": "Arguments for the tool."},
        "answer": {"type": ["string", "null"], "description": "Final answer for the user; null while acting."},
    },
    "required": ["thought", "tool", "tool_args", "answer"],
}

CONTRACT_INSTRUCTIONS = """You are SideLearner, an autonomous desktop agent. You act by choosing tools; you answer when the task is complete.

Respond with STRICT JSON only, matching this schema:
{"thought": "<one-line reasoning>", "tool": "<tool name or null>", "tool_args": {<args for tool or null>}, "answer": "<final answer or null>"}

Rules:
- If any information is still missing and a tool can get it, set tool/tool_args and answer=null.
- Call ONE tool per message. After the tool result comes back, continue until the task is done.
- Set tool=null and answer=... exactly once, when the task is complete. Never call a tool again afterwards.
- fs.read_text/fs.list_dir/fs.grep/fs.stat/fs.glob and shell.run are the core tools. fs.write_text/fs.edit write files.
- If a tool result shows an error or "denied", adapt: try another approach or explain the blocker in your answer.
- Answer in the user's language. Be concise. Never invent tool results; only claim what tool outputs show."""


def parse_agent_message(text: str) -> dict:
    """Parse a model message into the agent JSON shape.

    Degrades gracefully: if the model answered in plain text, the whole text
    becomes the answer (no tool call) so local/small models never deadlock.
    """
    try:
        parsed = json_loads_lenient(text)
        if isinstance(parsed, dict) and "tool" in parsed:
            answer = parsed.get("answer") or None
            if isinstance(answer, list):
                answer = "\n".join(str(item) for item in answer)
            elif not isinstance(answer, (str, type(None))):
                answer = str(answer)
            return {
                "thought": str(parsed.get("thought", "")),
                "tool": parsed.get("tool") or None,
                "tool_args": parsed.get("tool_args") or {},
                "answer": answer,
            }
    except ValueError:
        pass
    stripped = text.strip()
    return {"thought": stripped[:200], "tool": None, "tool_args": None, "answer": stripped}

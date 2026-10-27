"""Domain classifier: assigns knowledge to the business taxonomy hierarchy."""
from __future__ import annotations

import json
import logging
from typing import Any, Optional

from ..utils import tokenize

log = logging.getLogger("sidelearner.classify")

DEFAULT_TAXONOMY: list[dict] = [
    {
        "name": "bookkeeping",
        "keywords": ["invoice", "reconcile", "ledger", "quickbooks", "payroll", "expense", "account", "statement", "month-end", "tax"],
    },
    {
        "name": "clients",
        "keywords": ["client", "customer", "vendor", "supplier", "contact", "contract", "proposal", "quote", "email", "meeting", "call"],
    },
    {
        "name": "procedures",
        "keywords": ["procedure", "process", "workflow", "step", "how", "deploy", "run", "build", "configure", "install", "checklist", "routine"],
    },
    {
        "name": "tools",
        "keywords": ["app", "tool", "software", "vscode", "chrome", "browser", "editor", "ide", "plugin", "extension", "keyboard", "shortcut"],
    },
    {
        "name": "development",
        "keywords": ["code", "function", "class", "script", "bug", "fix", "git", "repo", "test", "api", "python", "commit", "branch", "import"],
    },
]


class DomainClassifier:
    """Keyword-scored classification into the configured business taxonomy.

    Pure local logic (no model): token overlap against each domain's keyword
    list. Returns the best domain + a confidence; `general` is the fallback.
    """

    def __init__(self, taxonomy: Optional[list[dict]] = None) -> None:
        self.taxonomy = taxonomy or DEFAULT_TAXONOMY
        self.keywords: dict[str, set[str]] = {}
        for domain in self.taxonomy:
            name = str(domain.get("name", "")).strip().lower()
            if not name:
                continue
            self.keywords[name] = set(tokenize(" ".join(str(k) for k in domain.get("keywords", []))))

    @property
    def names(self) -> list[str]:
        return list(self.keywords)

    def classify(self, text: str) -> tuple[str, float]:
        """(domain, confidence) — 'general' with 0.0 when nothing matches."""
        tokens = set(tokenize(text))
        best_domain, best_score = "general", 0.0
        for domain, keywords in self.keywords.items():
            hits = len(tokens & keywords)
            if hits == 0:
                continue
            # Confidence: fraction of the domain's keyword list that fired,
            # damped for single hits (common words like "account").
            score = hits / max(1, len(keywords))
            if hits == 1 and score < 0.1:
                score = 0.05
            if score > best_score:
                best_domain, best_score = domain, score
        if best_score < 0.03:
            return "general", 0.0
        return best_domain, round(min(best_score, 1.0), 3)

    def classify_llm(self, text: str, provider: Optional[Any] = None) -> Optional[str]:
        """Model-backed classification for uncertain cases. Returns a domain
        name from the taxonomy, or None when unavailable/inconclusive."""
        if provider is None or not self.taxonomy:
            return None
        options = ", ".join(f"{d.get('name')} ({d.get('keywords', [])[:5]})" for d in self.taxonomy[:8])
        prompt = (
            f"Classify this observed text into exactly ONE knowledge domain, or 'general'.\n"
            f"Domains: {options}, general\n\nText: {text[:600]}"
        )
        try:
            completion = provider.chat(
                [{"role": "user", "content": prompt}], temperature=0.0, max_tokens=40
            )
            answer = completion.text.strip().lower()
            for name in self.names:
                if name in answer:
                    return name
            if "general" in answer:
                return "general"
            return None
        except Exception as exc:  # noqa: BLE001
            log.debug("LLM classification failed: %s", exc)
            return None

    def describe(self) -> str:
        return ", ".join(self.names)

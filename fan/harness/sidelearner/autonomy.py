"""AutonomyEngine: the self-directed learning loop.

Ideal shape (toward which this module grows): on start, immediately observe
(screenshot -> vision -> ledger), compress backlog knowledge, and then cycle:
observe -> classify into the domain hierarchy -> decide whether something is
worth asking about -> store -> repeat. Prompting is a *cost*: the engine only
prompts when a pattern is uncertain, and it auto-answers once the user has
confirmed the same pattern enough times — so input requirements shrink as the
twin gets smarter.
"""
from __future__ import annotations

import logging
import threading
import time
from typing import Any, Optional

from .memory.classify import DomainClassifier
from .perception.screen import focused_window
from .utils import now_ms, utcnow

log = logging.getLogger("sidelearner.autonomy")

# Defaults mirror config.py DEFAULTS["autonomy"].
DEFAULTS = {
    "enabled": True,
    "interval_s": 20.0,
    "prompt_mode": "ask",          # observe | ask
    "screenshot_on_start": True,
    "vision_on_change": True,
    "vision_interval_s": 60.0,
    "pattern_threshold": 2,        # app appearances before it is a "pattern"
    "auto_confidence": 2,          # identical confirmations -> stop asking
    "max_open_prompts": 3,
}


class AutonomyEngine:
    """Owns the observe -> glean -> decide cycle inside the daemon."""

    def __init__(self, harness: Any) -> None:
        self.harness = harness
        self.config = harness.config
        self.bus = harness.bus
        self.twin = harness.twin
        self.registry = harness.registry
        self.supervisor = harness.supervisor
        cfg = {**DEFAULTS, **(self.config.get("autonomy") or {})}
        self.interval_s = float(cfg["interval_s"])
        self.prompt_mode = str(cfg["prompt_mode"])
        self.screenshot_on_start = bool(cfg["screenshot_on_start"])
        self.vision_on_change = bool(cfg["vision_on_change"])
        self.vision_interval_s = float(cfg["vision_interval_s"])
        self.pattern_threshold = int(cfg["pattern_threshold"])
        self.auto_confidence = int(cfg["auto_confidence"])
        self.max_open_prompts = int(cfg["max_open_prompts"])
        self.classifier: DomainClassifier = harness.twin.classifier
        self._last_vision = 0.0
        self._cycles = 0
        self._stop = threading.Event()

    # -- providers ---------------------------------------------------------
    def vision_provider(self) -> Optional[Any]:
        return self.registry.pick("local", {"text", "vision"})

    # -- cycle -------------------------------------------------------------
    def startup_pass(self) -> dict:
        """Runs IMMEDIATELY at daemon start: observe, glean, classify."""
        report: dict = {"screenshot": None, "vision": None, "compressed": None, "window": None}
        app, title = focused_window()
        if title or app:
            self.twin.ingest("window", f"{app}: {title}".strip(": "), {}, source="autonomy")
            report["window"] = f"{app}: {title}"
        if self.screenshot_on_start:
            path = self.supervisor.screenshot_now()
            if path is not None:
                report["screenshot"] = str(path)
                if self.vision_on_change:
                    provider = self.vision_provider()
                    if provider is not None:
                        try:
                            from .perception.screen import image_bytes
                            from PIL import Image

                            img = Image.open(path)
                            description = provider.vision(
                                image_bytes(img),
                                "Describe concisely: what app is open, what task is the user doing? One or two sentences.",
                            )
                            if description:
                                self.twin.ingest("vision", description, {"image": str(path)}, source="autonomy")
                                report["vision"] = description[:300]
                                self._last_vision = time.monotonic()
                        except Exception as exc:  # noqa: BLE001
                            log.warning("startup vision analysis failed: %s", exc)
        try:
            # Queue the backlog compression in the background — the main cycle
            # starts immediately instead of blocking on provider extraction.
            self.twin.compress_async()
            report["compressed"] = "queued (background)"
        except Exception:  # noqa: BLE001
            log.exception("startup compression queue failed")
        self.bus.emit("autonomy.started", report, source="autonomy")
        return report

    def tick(self) -> dict:
        """One periodic cycle. Cheap local logic; model calls only when due."""
        self._cycles += 1
        cycle: dict = {"cycle": self._cycles, "vision": None, "compressed": None, "prompted": 0}
        now = time.monotonic()
        if self.vision_on_change and (now - self._last_vision) >= self.vision_interval_s:
            provider = self.vision_provider()
            if provider is not None:
                path = self.supervisor.screenshot_now()
                if path is not None:
                    try:
                        from .perception.screen import image_bytes
                        from PIL import Image

                        description = provider.vision(
                            image_bytes(Image.open(path)),
                            "What changed on screen? Focus on the active app and task. One sentence.",
                        )
                        if description:
                            self.twin.ingest("vision", description, {"image": str(path)}, source="autonomy")
                            cycle["vision"] = description[:200]
                    except Exception as exc:  # noqa: BLE001
                        log.debug("cycle vision failed: %s", exc)
                self._last_vision = now
        try:
            if not self.twin.compressing():
                cycle["compressed"] = self.twin.compressor.run(max_items=20)
            else:
                cycle["compressed"] = "skipped (compressor busy)"
        except Exception:  # noqa: BLE001
            log.exception("cycle compression failed")
        cycle["prompted"] = self.assess_patterns()
        if self.bus is not None:
            self.bus.emit("autonomy.cycle", cycle, source="autonomy")
        return cycle

    def run_forever(self, status_interval: float = 30.0) -> None:
        """Blocking loop (used by the daemon); Ctrl+C stops it."""
        self.startup_pass()
        last_status = 0.0
        while not self._stop.is_set():
            try:
                self.tick()
            except Exception:  # noqa: BLE001
                log.exception("autonomy cycle crashed")
            self._stop.wait(max(1.0, self.interval_s))

    def stop(self) -> None:
        self._stop.set()

    # -- pattern recognition & prompting ------------------------------------
    def assess_patterns(self) -> int:
        """Look at recurring focused apps. Ask about the ones we haven't
        classified yet (prompt_mode=ask), auto-classify the ones whose
        best-guess domain the user has confirmed often enough, and leave the
        rest alone. Returns the number of prompts created."""
        if self.prompt_mode != "ask":
            return 0
        open_rows = self.twin.store.decisions_open(kind="pattern")
        open_subjects = {str(row["subject"]) for row in open_rows}
        prompted = 0
        for row in self.twin.store.window_app_counts(min_count=self.pattern_threshold):
            app = str(row["app"] or "").strip()
            if not app or self._app_classified(app):
                continue
            if app in open_subjects:
                continue  # already has an open prompt; don't duplicate it
            if self._auto_answer_if_confident(app):
                continue  # decisive: learned pattern generalized, no prompt
            if len(open_rows) + prompted >= self.max_open_prompts:
                break
            if self._prompt_pattern(app):
                prompted += 1
        return prompted

    def _auto_answer_if_confident(self, app: str) -> bool:
        """Domain-level generalization: once the user confirmed the same
        answer for `auto_confidence` different apps, new apps whose
        best-guess domain matches are auto-answered without prompting."""
        domain = self._best_guess_domain(app)
        if domain == "general":
            return False
        confirmations = self.twin.store.decisions_for_answer("pattern", domain)
        if len(confirmations) < self.auto_confidence:
            return False
        decision_id = self.twin.store.add_decision("pattern", app, question=f"auto-classified as {domain}", confidence=1.0)
        self.answer(decision_id, domain, auto=True)
        log.info("auto-answered %s -> %s (%d prior confirmations)", app, domain, len(confirmations))
        return True

    def _app_classified(self, app: str) -> bool:
        """True once the user (or auto-confirmation) has labeled this app."""
        return len(self.twin.store.decisions_for("pattern", app)) > 0

    def _prompt_pattern(self, app: str) -> Optional[int]:
        domain = self._best_guess_domain(app)
        question = (
            f"You use {app} often. What kind of work is this? "
            + (f"(I think: {domain})" if domain != "general" else "(e.g. bookkeeping / coding / browsing)")
        )
        decision_id = self.twin.store.add_decision("pattern", app, question=question, confidence=0.3)
        self.bus.emit("autonomy.prompt", {"id": decision_id, "kind": "pattern", "subject": app, "question": question}, source="autonomy")
        log.info("prompt #%d: %s", decision_id, question)
        return decision_id

    def _best_guess_domain(self, app: str) -> str:
        """Guess an app's work domain: taxonomy keywords, then similarity to
        apps the user already classified, then a model fallback."""
        domain, confidence = self.classifier.classify(app)
        if domain != "general" and confidence >= 0.03:
            return domain
        from .utils import jaccard, tokenize

        app_tokens = set(tokenize(app))
        best, best_score = "general", 0.0
        for decision in self.twin.store.decisions_resolved(kind="pattern"):
            subject = str(decision["subject"])
            score = jaccard(app_tokens, set(tokenize(subject)))
            if score >= 0.5 and score > best_score:
                best, best_score = str(decision["answer"]), score
        if best != "general":
            return best
        provider = self.registry.pick("local", {"text"})
        if provider is not None:
            llm = self.classifier.classify_llm(f"the desktop application named '{app}'", provider)
            if llm and llm != "general":
                return llm
        return "general"

    def answer(self, decision_id: int, answer: str, auto: bool = False) -> Optional[dict]:
        """Resolve a prompt with the user's answer; store it as knowledge."""
        row = self.twin.store.get_decision(decision_id)
        if row is None or row["resolved"]:
            return None
        self.twin.store.resolve_decision(decision_id, answer, auto=auto)
        subject = str(row["subject"])
        domain, confidence = self.classifier.classify(answer)
        if domain == "general":
            # The user's answer may itself name a new domain.
            domain = answer.strip().lower().replace(" ", "-")[:40] or "general"
            confidence = 0.5
        fact = f"User uses {subject} for {answer.strip()} ({domain} work)."
        fact_id, _ = self.twin.graph.add_fact(fact, confidence=max(0.5, confidence), source_ids=[], domain=domain)
        self.twin.graph.add_entity(subject, kind="app", domain=domain)
        self.bus.emit(
            "autonomy.decision",
            {"id": decision_id, "subject": subject, "answer": answer, "domain": domain, "fact_id": fact_id, "auto": auto},
            source="autonomy",
        )
        return {"decision_id": decision_id, "subject": subject, "answer": answer, "domain": domain, "fact_id": fact_id}

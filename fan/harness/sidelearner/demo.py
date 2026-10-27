"""Built-in demos: perception, digital twin, agent. Used by `sl demo`."""
from __future__ import annotations

import time
from typing import Any, Optional

from .utils import utcnow

_LOGGED_EVENTS = {
    "perception.screen.changed",
    "perception.window",
    "perception.screen.text",
    "perception.audio.speech",
    "perception.audio.transcript",
    "perception.camera.frame",
    "perception.camera.vision",
}


def demo_perception(harness: Any, seconds: float = 10.0) -> dict:
    """Run perception watchers for N seconds and report what they saw."""
    print(f"\n== Perception demo: watching the desktop for {seconds}s ==")
    print("Move windows around, switch apps, or talk — everything stays local.\n")
    count = {"n": 0}

    def on_event(event) -> None:
        if event.type in _LOGGED_EVENTS:
            count["n"] += 1
            if event.type == "perception.window":
                print(f"  [window] {event.data.get('app')}: {event.data.get('title')}")
            elif event.type == "perception.screen.changed":
                print(f"  [screen] changed by {event.data.get('change')} -> {event.data.get('image_path')}")
            elif event.type == "perception.screen.text":
                text = str(event.data.get("text", ""))[:120].replace("\n", " ")
                print(f"  [ocr] {text}")
            elif event.type == "perception.audio.speech":
                print(f"  [audio] speech {event.data.get('duration_s')}s -> {event.data.get('wav_path')}")
            elif event.type == "perception.audio.transcript":
                print(f"  [transcript] {event.data.get('text')}")
            elif event.type == "perception.camera.frame":
                extra = f", faces={event.data.get('faces')}" if "faces" in event.data else ""
                print(f"  [camera] frame{extra} -> {event.data.get('image_path')}")
            elif event.type == "perception.camera.vision":
                print(f"  [camera vision] {str(event.data.get('description'))[:140]}")

    sub = harness.bus.subscribe("perception.*", on_event)
    harness.start_perception()
    try:
        time.sleep(seconds)
    finally:
        harness.stop()
        harness.bus.unsubscribe(sub)
    status = harness.supervisor.status()
    print(f"\nObserved {count['n']} events. Watcher status:")
    for watcher in status["watchers"]:
        print(f"  {watcher['kind']}: alive={watcher['alive']} ready={watcher['ready']} error={watcher['error']}")
    print(f"Artifacts stored in: {harness.config.vault}")
    return {"events": count["n"], "watchers": status["watchers"]}


def demo_twin(harness: Any) -> dict:
    """Feed representative observations, compress, and show the twin learning."""
    print("\n== Digital twin demo: from observations to compressed knowledge ==")
    observations = [
        (
            "window",
            "chrome: QuickBooks — Reconcile Accounts Receivable — Search",
            "The owner was reconciling accounts receivable in QuickBooks.",
        ),
        (
            "screen",
            "Invoice INV-2024-0117 from Acme Supply Co, total $4,320.50, due 2024-06-01. "
            "Vendor terms NET-30. Post to account 1100 Accounts Receivable. Approved by J. Miller.",
            "An Acme Supply Co invoice for $4,320.50, NET-30, account 1100.",
        ),
        (
            "audio",
            "reminder: run the month end close before Friday, then send the aging report to the client",
            "Month-end close must run before Friday, then send the aging report.",
        ),
        (
            "screen",
            "deploy: git push origin main && ssh prod 'systemctl restart app' — staging passed all tests",
            "The deploy procedure is git push then systemctl restart on prod after staging tests pass.",
        ),
        ("window", "vscode: a-llm-harness-custom — sidelearner/harness.py", "The owner was editing harness.py in the SideLearner project."),
        (
            "screen",
            "the quick brown fox jumps over the lazy dog and absolutely nothing else happens today whatsoever",
            "",
        ),
    ]
    before = harness.twin.status()
    # In the demo, learning windows expire immediately so gaps surface now.
    harness.twin.ledger.gap_minutes = 0.0
    for kind, text, _ in observations:
        harness.twin.ingest(kind, text, {}, source="demo")
    print(f"ingested {len(observations)} observations (ledger total: {harness.twin.ledger.stats()['total']})")

    result = harness.compress_twin()
    print(f"compression: {result}")

    after = harness.twin.status()
    print(f"\ngraph after: {after['graph']['facts']} facts, {after['graph']['entities']} entities")
    print("top entities: " + ", ".join(after["graph"]["top_entities"][:6]))
    if after["open_gaps"]:
        print(f"\nopen learning gaps ({after['open_gaps']}):")
        for gap in harness.twin.gaps()[:5]:
            print(f"  - gap#{gap['id']}: {gap['reason']} :: {gap['observation'][:100]}")

    print("\n== what does the twin know? ==")
    for question in ("invoices", "deploy procedure", "month end close"):
        result = harness.twin.ask(question, k=3)
        print(f"\nQ: {question}")
        for h in result["hits"]:
            print(f"  [{h['kind']} sim={h['similarity']}] {h['text'][:160]}")
    return {"before": before, "after": after}


def demo_agent(harness: Any, task: Optional[str] = None) -> dict:
    """Run one agent task through routing and the loop."""
    task = task or "recon the workspace"
    print(f"\n== Agent demo: task = {task!r} ==")
    route = harness.router.route(task)
    print(f"router decision: {route.describe()}")
    print("reasons:")
    for reason in route.reasons:
        print(f"  - {reason}")

    def on_event(ev: dict) -> None:
        kind = ev.get("kind")
        if kind == "tool":
            print(f"  [tool] {ev['tool']} {ev.get('args', {})}")
        elif kind == "tool_result":
            status = "denied" if ev.get("denied") else ("ok" if ev.get("ok") else "failed")
            print(f"  [tool:{status}] {str(ev.get('text', ''))[:160]}")

    result = harness.chat(task, on_event=on_event)
    print(f"\nresult: ok={result.ok} deterministic={result.deterministic} steps={len(result.steps)}")
    print(f"answer:\n{result.answer[:1500]}")
    if result.verification:
        print("verification:")
        for line in result.verification:
            print(f"  - {line}")
    return {"ok": result.ok, "answer": result.answer, "route": route.describe()}

"""SideLearner CLI: `sl <command>` — the harness control surface."""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path
from typing import Any, Optional

from . import __version__


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="sl",
        description="SideLearner — self-hosted LLM harness with a learning digital twin.",
        epilog="Run `sl <command> -h` for command help.",
    )
    parser.add_argument("--config", default=None, help="path to config.yaml (default: ./config.yaml or $SL_CONFIG)")
    parser.add_argument("-v", "--version", action="version", version=f"sidelearner {__version__}")
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("init", help="write config.yaml from the documented example")
    p.add_argument("--force", action="store_true")

    p = sub.add_parser("status", help="show config, providers, twin, perception status")
    p.add_argument("--probe", action="store_true", help="probe provider health")

    p = sub.add_parser("providers", help="list providers")
    p.add_argument("--probe", action="store_true")

    p = sub.add_parser("chat", help="run one agent task through routing and the loop")
    p.add_argument("task")
    p.add_argument("--mode", choices=["auto", "deterministic"], default="auto")
    p.add_argument("--cwd", default=None)
    p.add_argument("--ask", action="store_true", help="interactive permission prompts for risky tools")
    p.add_argument("--extra", default="", help="extra context string")
    p.add_argument("--json", action="store_true", dest="as_json", help="print result as JSON")

    p = sub.add_parser("skill", help="skills (business workflows)")
    sp = p.add_subparsers(dest="skill_command")
    sp.add_parser("list")
    p2 = sp.add_parser("run")
    p2.add_argument("name")
    p2.add_argument("--vars", default="", help="comma-separated k=v variables")
    p2.add_argument("--json", action="store_true", dest="as_json")

    p = sub.add_parser("twin", help="the learning digital twin")
    tp = p.add_subparsers(dest="twin_command")
    tp.add_parser("status")
    tp.add_parser("gaps")
    tq = tp.add_parser("query")
    tq.add_argument("question")
    tq.add_argument("-k", type=int, default=8)
    tf = tp.add_parser("facts")
    tf.add_argument("--domain", default=None, help="filter by knowledge domain")
    tf.add_argument("--limit", type=int, default=20)
    tr = tp.add_parser("resolve")
    tr.add_argument("gap_id", type=int)
    tr.add_argument("--note", default="reviewed")
    te = tp.add_parser("export")
    te.add_argument("path", nargs="?", default="twin_export.jsonl")
    tc = tp.add_parser("compress")
    tc.add_argument("--max-items", type=int, default=50)

    p = sub.add_parser("perceive", help="run perception for a while and print observations")
    p.add_argument("--seconds", type=float, default=10.0)
    p.add_argument("--once", action="store_true", help="single screenshot + focused window, then exit")

    p = sub.add_parser("sessions", help="agent session log")
    sp = p.add_subparsers(dest="sessions_command")
    sp.add_parser("list")
    ss = sp.add_parser("show")
    ss.add_argument("session_id")

    p = sub.add_parser("demo", help="built-in demos")
    p.add_argument("which", choices=["perception", "twin", "agent"], default="twin")
    p.add_argument("--seconds", type=float, default=10.0)
    p.add_argument("--task", default=None)

    p = sub.add_parser("run", help="run the harness continuously (perception + twin learning + skill triggers)")
    p.add_argument("--no-perception", action="store_true")
    p.add_argument("--no-autonomy", action="store_true")
    p.add_argument("--status-interval", type=float, default=30.0)
    p.add_argument("--daemon-child", action="store_true", help=argparse.SUPPRESS)

    p = sub.add_parser("daemon", help="run SideLearner hidden in the background")
    dp = p.add_subparsers(dest="daemon_command")
    dp.add_parser("start")
    dp.add_parser("stop")
    dp.add_parser("status")
    dl = dp.add_parser("logs")
    dl.add_argument("--lines", type=int, default=30)

    p = sub.add_parser("web", help="optional FastAPI web dashboard")
    wp = p.add_subparsers(dest="web_command")
    ws = wp.add_parser("start", help="start the web dashboard in the background")
    ws.add_argument("--port", type=int, default=None, help="override config web.port")
    ws.add_argument("--host", default=None, help="override config web.host")
    wp.add_parser("stop")
    wp.add_parser("status")
    wl = wp.add_parser("logs")
    wl.add_argument("--lines", type=int, default=30)

    p = sub.add_parser("prompts", help="list open autonomy prompts (what the twin is uncertain about)")
    p = sub.add_parser("answer", help="answer an autonomy prompt")
    p.add_argument("decision_id", type=int)
    p.add_argument("answer")

    p = sub.add_parser("onboard", help="interactive first-run setup: describe your business so the twin starts informed")
    return parser


def _load_config(args: argparse.Namespace):
    from .config import Config

    return Config.load(args.config)


def _tty_ask(message: str) -> bool:
    if not sys.stdin.isatty():
        return False
    try:
        answer = input(f"{message} ").strip().lower()
    except EOFError:
        return False
    return answer in ("y", "yes")


def _print_table(rows: list[dict], columns: list[str]) -> None:
    if not rows:
        print("  (none)")
        return
    widths = {col: max(len(col), *(len(str(row.get(col, ""))) for row in rows)) for col in columns}
    header = "  " + "  ".join(col.ljust(widths[col]) for col in columns)
    print(header)
    print("  " + "  ".join("-" * widths[col] for col in columns))
    for row in rows:
        print("  " + "  ".join(str(row.get(col, "")).ljust(widths[col]) for col in columns))


def cmd_status(harness: Any, args: argparse.Namespace) -> int:
    cfg = harness.config.summary()
    print("config:")
    for key, value in cfg.items():
        print(f"  {key}: {value}")
    print("providers:")
    rows = [
        {
            "name": p["name"],
            "kind": p["kind"],
            "model": p["model"],
            "tier": p["tier"],
            "healthy": p["healthy"] if p["healthy"] is not None else "?",
        }
        for p in harness.registry.status(probe=args.probe)
    ]
    _print_table(rows, ["name", "kind", "model", "tier", "healthy"])
    if harness.cli_agents.agents:
        print("cli agents:", ", ".join(f"{n}={'ok' if ok else 'missing'}" for n, ok in harness.cli_agents.status().items()))
    print(f"skills ({len(harness.skill_engine.skills)}): {', '.join(s.name for s in harness.skill_engine.skills)}")
    twin = harness.twin.status()
    print(
        "twin: "
        f"{twin['observations']} observations, {twin['ledger']['learned']}/{twin['ledger']['total']} learned "
        f"({twin['ledger']['learned_pct']}%), {twin['graph']['facts']} facts, {twin['graph']['entities']} entities, "
        f"{twin['open_gaps']} open gaps"
    )
    return 0


def cmd_chat(harness: Any, args: argparse.Namespace) -> int:
    route = harness.router.route(args.task)
    print(f"route: {route.describe()}")
    print("  " + "\n  ".join(f"- {r}" for r in route.reasons))
    print()
    ask_cb = _tty_ask if args.ask else None

    def on_event(ev: dict) -> None:
        kind = ev.get("kind")
        if kind == "token":
            sys.stdout.write(ev.get("text", ""))
            sys.stdout.flush()
        elif kind == "tool":
            print(f"\n[tool] {ev['tool']} {json.dumps(ev.get('args', {}), default=str)[:200]}")
        elif kind == "tool_result":
            status = "denied" if ev.get("denied") else ("ok" if ev.get("ok") else "failed")
            print(f"\n[tool:{status}] {str(ev.get('text', ''))[:500]}")
        elif kind == "delegate":
            print(f"\n[delegating to {ev['agent']}]")

    result = harness.chat(args.task, mode=args.mode, cwd=args.cwd, on_event=on_event, ask_callback=ask_cb, extra_context=args.extra)
    print()
    if args.as_json:
        print(json.dumps({"ok": result.ok, "answer": result.answer, "steps": result.steps, "verification": result.verification, "session": result.session_id, "route": result.route.describe() if result.route else None}, default=str))
        return 0
    print(f"\n{'=' * 60}\nanswer ({'ok' if result.ok else 'FAILED'}):\n{result.answer}")
    if result.verification:
        print("\nverification:")
        for line in result.verification:
            print(f"  - {line}")
    print(f"\nsession: {result.session_id}")
    return 0 if result.ok else 1


def cmd_skill(harness: Any, args: argparse.Namespace) -> int:
    if args.skill_command == "list":
        for skill in harness.skill_engine.skills:
            flags = []
            if skill.model_invocable:
                flags.append("model")
            if skill.user_invocable:
                flags.append("user")
            print(f"  {skill.name:<24} {'|'.join(flags):<12} {skill.description}")
        return 0
    if args.skill_command == "run":
        vars: dict = {"cwd": str(harness.config.workspace)}
        for pair in (args.vars or "").split(","):
            if "=" in pair:
                key, value = pair.split("=", 1)
                vars[key.strip()] = value.strip()
        result = harness.run_skill(args.name, vars=vars)
        if result is None:
            print(f"skill not found: {args.name}")
            return 1
        if args.as_json:
            print(json.dumps({"ok": result.ok, "output": result.output, "steps": result.steps, "vars": result.vars}, default=str))
            return 0
        print(f"skill {args.name}: {'ok' if result.ok else 'FAILED'}")
        for step in result.steps:
            print(f"  [{step['step']}] {step['tool']}: {'ok' if step.get('ok') else 'failed'} — {str(step.get('output', ''))[:200]}")
        print(f"\noutput: {result.output[:2000]}")
        return 0 if result.ok else 1
    print("usage: sl skill list | sl skill run NAME [--vars a=b]")
    return 1


def cmd_twin(harness: Any, args: argparse.Namespace) -> int:
    cmd = args.twin_command
    if cmd == "status":
        print(json.dumps(harness.twin.status(), indent=2, default=str))
        return 0
    if cmd == "gaps":
        gaps = harness.twin.gaps()
        if not gaps:
            print("no open learning gaps")
            return 0
        for gap in gaps:
            print(f"  gap#{gap['id']} {gap['created']} — {gap['reason']}\n    observation: {gap['observation'][:200]}")
        return 0
    if cmd == "facts":
        rows = harness.twin.store.facts_active(domain=args.domain)
        rows.sort(key=lambda r: r["last_seen"], reverse=True)
        for row in rows[: args.limit]:
            print(f"  #{row['id']} [{row['domain']}] w={row['weight']:.0f} {row['last_seen']} {row['text'][:160]}")
        if not rows:
            print(f"no facts stored yet{(' in domain ' + args.domain) if args.domain else ''}")
        return 0
    if cmd == "query":
        result = harness.twin.ask(args.question, k=args.k)
        if not result["hits"]:
            print("the twin knows nothing about that yet")
            return 0
        print(result["context_block"])
        return 0
    if cmd == "resolve":
        harness.twin.resolve_gap(args.gap_id, args.note)
        print(f"gap #{args.gap_id} resolved")
        return 0
    if cmd == "export":
        path = harness.twin.export(args.path)
        print(f"exported to {path}")
        return 0
    if cmd == "compress":
        print(json.dumps(harness.compress_twin(), indent=2))
        return 0
    print("usage: sl twin status|facts|gaps|query Q|resolve ID|export [path]|compress")
    return 1


def cmd_perceive(harness: Any, args: argparse.Namespace) -> int:
    from .demo import demo_perception

    if args.once:
        sup = harness.supervisor
        path = sup.screenshot_now()
        from .perception.screen import focused_window

        app, title = focused_window()
        print(f"focused window: {app}: {title}")
        print(f"screenshot: {path}")
        return 0
    demo_perception(harness, seconds=args.seconds)
    return 0


def cmd_run(harness: Any, args: argparse.Namespace) -> int:
    if not args.daemon_child:
        print("SideLearner daemon starting. Ctrl+C to stop. (For hidden background operation use `sl daemon start`.)")
    watchers = []
    if not args.no_perception:
        watchers = harness.start_perception()
    for watcher in watchers:
        print(f"  watcher {watcher.kind}: started")

    from .triggers import TriggerManager

    triggers = TriggerManager(harness)
    print("  triggers: watching perception events for workflow skills")

    autonomy_enabled = bool(harness.config.get("autonomy.enabled", True)) and not args.no_autonomy
    if autonomy_enabled:
        harness.autonomy.startup_pass()
        print(f"  autonomy: self-directed learning active (prompt mode={harness.autonomy.prompt_mode})")

    last_status = 0.0
    last_autonomy = 0.0
    try:
        while True:
            time.sleep(1.0)
            now = time.monotonic()
            if autonomy_enabled and now - last_autonomy >= harness.autonomy.interval_s:
                last_autonomy = now
                try:
                    cycle = harness.autonomy.tick()
                    prompts = harness.twin.store.decisions_open()
                    if prompts:
                        print(f"[{time.strftime('%H:%M:%S')}] {len(prompts)} open prompt(s) — answer with `sl prompts` and `sl answer <id> <answer>`")
                    if cycle.get("vision"):
                        print(f"[{time.strftime('%H:%M:%S')}] vision: {cycle['vision'][:120]}")
                except Exception as exc:  # noqa: BLE001
                    print(f"  autonomy cycle failed: {exc}")
            if now - last_status >= args.status_interval:
                last_status = now
                twin = harness.twin.status()
                domains = ", ".join(f"{d}={n}" for d, n in sorted(twin["graph"]["domains"].items()))
                print(
                    f"[{time.strftime('%H:%M:%S')}] observations={twin['observations']} "
                    f"learned={twin['ledger']['learned']}/{twin['ledger']['total']} "
                    f"facts={twin['graph']['facts']} gaps={twin['open_gaps']} prompts={twin['open_prompts']}"
                )
                if domains:
                    print(f"  domains: {domains}")
    except KeyboardInterrupt:
        print("\nstopping…")
    finally:
        triggers.stop()
        harness.autonomy.stop()
        harness.stop()
    twin = harness.twin.status()
    print(f"final: {twin}")
    return 0


def cmd_sessions(harness: Any, args: argparse.Namespace) -> int:
    from .sessions import SessionLog

    sessions = SessionLog(harness.config.vault / "sessions")
    if args.sessions_command == "list":
        rows = sessions.sessions()
        _print_table(rows, ["id", "started", "events", "task"])
        return 0
    if args.sessions_command == "show":
        print(sessions.transcript(args.session_id))
        return 0
    return 1


def cmd_demo(harness: Any, args: argparse.Namespace) -> int:
    from . import demo

    if args.which == "perception":
        demo.demo_perception(harness, seconds=args.seconds)
    elif args.which == "twin":
        demo.demo_twin(harness)
    elif args.which == "agent":
        demo.demo_agent(harness, task=args.task)
    return 0


# -- daemon (hidden background operation) ----------------------------------
def _pidfile(harness: Any) -> Path:
    run_dir = harness.config.vault / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir / "daemon.pid"


def _daemon_running(harness: Any) -> Optional[int]:
    pidfile = _pidfile(harness)
    if not pidfile.exists():
        return None
    try:
        pid = int(pidfile.read_text().strip())
    except (OSError, ValueError):
        return None
    if pid <= 0:
        return None
    import ctypes

    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if handle:
        kernel32.CloseHandle(handle)
        return pid
    return None


def cmd_daemon(harness: Any, args: argparse.Namespace) -> int:
    import signal
    import subprocess
    import sys as _sys

    sub = args.daemon_command
    run_dir = harness.config.vault / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    log_dir = harness.config.vault / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "sidelearner.log"
    if sub == "start":
        running = _daemon_running(harness)
        if running:
            print(f"daemon already running (pid {running})")
            return 0
        pythonw = Path(_sys.executable).parent / "pythonw.exe"
        if not pythonw.exists():
            pythonw = Path(_sys.executable)
        log_file = open(log_path, "a", encoding="utf-8")  # noqa: SIM115 — held by child
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0) | getattr(subprocess, "DETACHED_PROCESS", 0)
        proc = subprocess.Popen(
            [
                str(pythonw),
                "-m",
                "sidelearner.cli",
                "run",
                "--status-interval",
                "60",
                "--daemon-child",
            ],
            cwd=str(harness.config.workspace),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            creationflags=creationflags,
            close_fds=True,
        )
        _pidfile(harness).write_text(str(proc.pid))
        print(f"daemon started (pid {proc.pid}) — hidden, logging to {log_path}")
        print("watch it with: sl daemon status | sl daemon logs | sl twin status")
        return 0
    if sub == "stop":
        pid = _daemon_running(harness)
        if not pid:
            print("daemon not running")
            _pidfile(harness).unlink(missing_ok=True)
            return 0
        try:
            import os

            os.kill(pid, signal.SIGTERM)
            print(f"stopped daemon (pid {pid})")
        except OSError:
            subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
            print(f"force-stopped daemon (pid {pid})")
        _pidfile(harness).unlink(missing_ok=True)
        return 0
    if sub == "status":
        pid = _daemon_running(harness)
        if pid:
            print(f"daemon: running (pid {pid})")
        else:
            print("daemon: not running")
        status_path = run_dir / "status.json"
        if status_path.exists():
            import json as _json
            from datetime import datetime, timezone

            age = (datetime.now(timezone.utc).timestamp() - status_path.stat().st_mtime)
            payload = _json.loads(status_path.read_text(encoding="utf-8"))
            print(f"  status.json age: {age:.0f}s")
            for watcher in payload.get("watchers", []):
                print(f"  watcher {watcher['kind']}: alive={watcher['alive']} ready={watcher['ready']} error={watcher['error']}")
        return 0
    if sub == "logs":
        if not log_path.exists():
            print(f"no log file yet ({log_path})")
            return 0
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        print("\n".join(lines[-args.lines :]))
        return 0
    print("usage: sl daemon start|stop|status|logs")
    return 1


# -- web dashboard -----------------------------------------------------------
def _web_pidfile(config: Config) -> Path:
    run_dir = config.vault / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    return run_dir / "web.pid"


def _web_running(config: Config) -> Optional[int]:
    pidfile = _web_pidfile(config)
    if not pidfile.exists():
        return None
    try:
        pid = int(pidfile.read_text().strip())
    except (OSError, ValueError):
        return None
    if pid <= 0:
        return None
    import ctypes

    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
    kernel32 = ctypes.windll.kernel32
    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
    if handle:
        kernel32.CloseHandle(handle)
        return pid
    return None


def cmd_web(config: Config, args: argparse.Namespace) -> int:
    """Start/stop/status/logs for the optional FastAPI web dashboard."""
    import signal
    import subprocess
    import sys as _sys

    sub = args.web_command
    run_dir = config.vault / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    log_dir = config.vault / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_path = log_dir / "web.log"
    pidfile = _web_pidfile(config)

    if sub == "start":
        running = _web_running(config)
        if running:
            print(f"web dashboard already running (pid {running})")
            return 0
        web_cfg = config.get("web") or {}
        host = args.host or web_cfg.get("host", "127.0.0.1")
        port = args.port or web_cfg.get("port", 8080)
        cmd = [str(_sys.executable), "-m", "sidelearner.web.server"]
        if getattr(args, "config", None):
            cmd += ["--config", str(args.config)]
        cmd += ["--host", str(host), "--port", str(port)]
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        log_file = open(log_path, "a", encoding="utf-8")  # noqa: SIM115 — held by child
        proc = subprocess.Popen(
            cmd,
            cwd=str(config.workspace),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            creationflags=creationflags,
            close_fds=True,
        )
        pidfile.write_text(str(proc.pid))
        print(f"web dashboard started (pid {proc.pid}) — http://{host}:{port}")
        print(f"logs: {log_path}")
        return 0

    if sub == "stop":
        pid = _web_running(config)
        if not pid:
            print("web dashboard not running")
            pidfile.unlink(missing_ok=True)
            return 0
        try:
            import os

            os.kill(pid, signal.SIGTERM)
            print(f"stopped web dashboard (pid {pid})")
        except OSError:
            subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
            print(f"force-stopped web dashboard (pid {pid})")
        pidfile.unlink(missing_ok=True)
        return 0

    if sub == "status":
        pid = _web_running(config)
        print(f"web dashboard: {'running (pid ' + str(pid) + ')' if pid else 'not running'}")
        return 0

    if sub == "logs":
        if not log_path.exists():
            print(f"no web log file yet ({log_path})")
            return 0
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
        print("\n".join(lines[-args.lines :]))
        return 0

    print("usage: sl web start|stop|status|logs")
    return 1


def cmd_prompts(harness: Any, args: argparse.Namespace) -> int:
    rows = harness.twin.store.decisions_open()
    if not rows:
        print("no open prompts — the twin has no unanswered questions right now")
        return 0
    for row in rows:
        print(f"  #{row['id']} [{row['kind']}] {row['subject']}: {row['question']}")
    print('\nanswer with: sl answer <id> "<your answer>"')
    return 0


def cmd_answer(harness: Any, args: argparse.Namespace) -> int:
    result = harness.autonomy.answer(args.decision_id, args.answer)
    if result is None:
        print(f"prompt #{args.decision_id} not found or already answered")
        return 1
    print(
        f"recorded: {result['subject']} -> {result['answer']} "
        f"(domain: {result['domain']}, fact #{result['fact_id']})"
    )
    return 0


def cmd_onboard(harness: Any, args: argparse.Namespace) -> int:
    if not sys.stdin.isatty():
        print("onboard needs an interactive terminal (it asks questions)")
        print("tip: edit config.yaml's `business:` section manually instead")
        return 1

    def ask(prompt: str, default: str = "") -> str:
        suffix = f" [{default}]" if default else ""
        answer = input(f"{prompt}{suffix}: ").strip()
        return answer or default

    print("SideLearner onboarding — the twin starts from your answers.\n")
    name = ask("Business name")
    domain = ask("What does the business do (one line)")
    tools = ask("Main apps you work in, comma-separated", "chrome, vscode, quickbooks")
    tasks = ask("Recurring tasks and their cadence", "invoicing (weekly), month-end close (monthly)")
    vocabulary = ask("Business vocabulary words that matter, comma-separated", "invoice, reconcile, month-end, payroll")
    people = ask("Key people/entities to remember", "")
    prompt_mode = ask("Autonomy prompt mode (ask=asks when uncertain, observe=never asks)", "ask")

    tools_list = [t.strip() for t in tools.split(",") if t.strip()]
    vocab_list = [v.strip() for v in vocabulary.split(",") if v.strip()]
    people_list = [p.strip() for p in people.split(",") if p.strip()]

    cfg = harness.config
    cfg.data["business"]["name"] = name
    cfg.data["business"]["domain"] = domain
    cfg.data["business"]["vocabulary"] = vocab_list
    cfg.data["autonomy"]["prompt_mode"] = prompt_mode
    # Register the main apps as tools-domain keywords so their activity routes
    # into the hierarchy from day one.
    taxonomy = cfg.data["business"].get("taxonomy") or []
    tools_domain = next((d for d in taxonomy if d.get("name") == "tools"), None)
    if tools_domain is None:
        tools_domain = {"name": "tools", "keywords": []}
        taxonomy.append(tools_domain)
    for tool in tools_list:
        if tool.lower() not in [str(k).lower() for k in tools_domain["keywords"]]:
            tools_domain["keywords"].append(tool.lower())
    cfg.data["business"]["taxonomy"] = taxonomy
    cfg.save()

    # Seed the twin with the user's self-described patterns.
    harness.twin.ingest("onboard", f"Business: {name}. {domain}.", {"source": "onboarding"}, source="onboard")
    harness.twin.ingest("onboard", f"Main tools: {', '.join(tools_list)}.", {}, source="onboard")
    harness.twin.ingest("onboard", f"Recurring tasks: {tasks}.", {}, source="onboard")
    if people_list:
        harness.twin.ingest("onboard", f"Key people: {', '.join(people_list)}.", {}, source="onboard")
    harness.compress_twin()
    print(f"\nSaved to config.yaml and seeded the twin with {4 if people_list else 3} onboarding facts.")
    print("Now run: sl daemon start   (hidden background learning)")
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    # Line-buffered stdout so piped/daemon output appears promptly.
    try:
        sys.stdout.reconfigure(line_buffering=True)
    except Exception:  # noqa: BLE001
        pass
    parser = _build_parser()
    args = parser.parse_args(argv)
    if args.command is None:
        parser.print_help()
        return 1
    if args.command == "init":
        from importlib.resources import files

        try:
            example = files("sidelearner").joinpath("config.example.yaml").read_text(encoding="utf-8")
        except Exception:  # noqa: BLE001
            example_path = Path(__file__).parent / "config.example.yaml"
            example = example_path.read_text(encoding="utf-8")
        target = Path("config.yaml")
        if target.exists() and not getattr(args, "force", False):
            print("config.yaml exists; use --force to overwrite")
            return 1
        target.write_text(example, encoding="utf-8")
        print(f"wrote {target} — edit it (providers, business profile, perception) and run `sl status`")
        return 0

    if args.command == "web":
        config = _load_config(args)
        return cmd_web(config, args)

    config = _load_config(args)
    from .harness import Harness

    harness = Harness(config)
    try:
        if args.command == "status":
            return cmd_status(harness, args)
        if args.command == "providers":
            _print_table(harness.registry.status(probe=args.probe), ["name", "kind", "model", "tier", "healthy"])
            if harness.cli_agents.agents:
                print("cli agents:", harness.cli_agents.status())
            return 0
        if args.command == "chat":
            return cmd_chat(harness, args)
        if args.command == "skill":
            return cmd_skill(harness, args)
        if args.command == "twin":
            return cmd_twin(harness, args)
        if args.command == "perceive":
            return cmd_perceive(harness, args)
        if args.command == "run":
            return cmd_run(harness, args)
        if args.command == "sessions":
            return cmd_sessions(harness, args)
        if args.command == "demo":
            return cmd_demo(harness, args)
        if args.command == "daemon":
            return cmd_daemon(harness, args)
        if args.command == "prompts":
            return cmd_prompts(harness, args)
        if args.command == "answer":
            return cmd_answer(harness, args)
        if args.command == "onboard":
            return cmd_onboard(harness, args)
        parser.print_help()
        return 1
    finally:
        harness.stop()


if __name__ == "__main__":
    raise SystemExit(main())

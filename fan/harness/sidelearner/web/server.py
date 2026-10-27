"""FastAPI web dashboard for SideLearner.

The dashboard is fully optional: `sl run` / `sl daemon` work without it.
Start it with `sl web start` to get a browser-based view of the twin,
perception, prompts, chat, and skills.
"""
from __future__ import annotations

import asyncio
import json
import logging
from pathlib import Path
from typing import Any, Optional

from fastapi import FastAPI, HTTPException, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles

from ..config import Config
from ..events import Event
from ..harness import Harness

log = logging.getLogger("sidelearner.web")

STATIC_DIR = Path(__file__).parent / "static"


class WebServer:
    """Composition root for the web dashboard."""

    def __init__(self, config: Config) -> None:
        self.config = config
        self.harness = Harness(config)
        self.app = FastAPI(title="SideLearner", version="0.1.0")
        self._setup_routes()
        self._setup_event_bridge()

    # -- routes --------------------------------------------------------------
    def _setup_routes(self) -> None:
        if STATIC_DIR.is_dir():
            self.app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

        @self.app.get("/", response_class=HTMLResponse)
        async def index():
            index_path = STATIC_DIR / "index.html"
            if index_path.exists():
                return HTMLResponse(content=index_path.read_text(encoding="utf-8"))
            return HTMLResponse(content=self._minimal_index())

        @self.app.get("/api/status")
        async def api_status():
            return self.harness.status(probe=False)

        @self.app.get("/api/providers")
        async def api_providers():
            return self.harness.registry.status(probe=True)

        @self.app.get("/api/twin/status")
        async def twin_status():
            return self.harness.twin.status()

        def _clean_row(row) -> dict:
            """Convert sqlite3.Row to JSON-safe dict, dropping binary embeddings."""
            return {k: row[k] for k in row.keys() if not isinstance(row[k], bytes)}

        @self.app.get("/api/twin/facts")
        async def twin_facts(domain: Optional[str] = None, limit: int = Query(20, ge=1, le=200)):
            rows = self.harness.twin.store.facts_active(domain=domain)
            rows.sort(key=lambda r: r["last_seen"], reverse=True)
            return {"facts": [_clean_row(r) for r in rows[:limit]]}

        @self.app.get("/api/twin/gaps")
        async def twin_gaps():
            return {"gaps": self.harness.twin.gaps()}

        @self.app.get("/api/twin/query")
        async def twin_query(q: str = Query(..., min_length=1), k: int = Query(8, ge=1, le=50)):
            return self.harness.twin.ask(q, k=k)

        @self.app.get("/api/prompts")
        async def prompts():
            return {"prompts": [_clean_row(r) for r in self.harness.twin.store.decisions_open()]}

        @self.app.post("/api/prompts/{decision_id}/answer")
        async def answer_prompt(decision_id: int, body: dict):
            answer = body.get("answer", "")
            result = self.harness.autonomy.answer(decision_id, answer)
            if result is None:
                raise HTTPException(status_code=404, detail="prompt not found or already answered")
            return result

        @self.app.get("/api/skills")
        async def skills():
            return {
                "skills": [
                    {"name": s.name, "description": s.description, "keywords": s.keywords, "triggers": s.triggers}
                    for s in self.harness.skill_engine.skills
                ]
            }

        @self.app.post("/api/skills/{name}/run")
        async def run_skill(name: str, body: Optional[dict] = None):
            body = body or {}
            skill = self.harness.skill_engine.find(name)
            if skill is None:
                raise HTTPException(status_code=404, detail="skill not found")
            vars = {"cwd": str(self.harness.config.workspace)}
            for pair in body.get("vars", {}).items():
                vars[pair[0]] = pair[1]
            result = self.harness.run_skill(name, vars=vars)
            return {"ok": result.ok if result else False, "output": result.output if result else ""}

        @self.app.get("/api/screenshots/latest")
        async def latest_screenshot():
            """Return the most recent screen capture as a JPEG file path/URL."""
            screen_dir = self.config.vault / "screen"
            files = sorted(screen_dir.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
            if not files:
                return {"path": None}
            return {"path": str(files[0])}

        @self.app.get("/api/screenshots/file")
        async def screenshot_file(path: Optional[str] = None):
            """Serve a screenshot file by path, or the latest if no path given."""
            screen_dir = (self.config.vault / "screen").resolve()
            if path:
                target = Path(path).resolve()
            else:
                files = sorted(screen_dir.glob("*.jpg"), key=lambda p: p.stat().st_mtime, reverse=True)
                target = files[0] if files else None
            if not target or not target.exists():
                raise HTTPException(status_code=404, detail="screenshot not found")
            try:
                target.relative_to(screen_dir)
            except ValueError as exc:
                raise HTTPException(status_code=403, detail="path outside screenshot vault") from exc
            return FileResponse(str(target), media_type="image/jpeg")

        @self.app.get("/api/perception/status")
        async def perception_status():
            return self.harness.supervisor.status()

        @self.app.get("/api/captions/status")
        async def captions_status():
            return self.harness.captions.status()

        @self.app.post("/api/captions/toggle")
        async def captions_toggle(body: Optional[dict] = None):
            body = body or {}
            enabled = body.get("enabled")
            state = self.harness.captions.toggle() if enabled is None else self.harness.captions.set_enabled(bool(enabled))
            return {**self.harness.captions.status(), "enabled": state}

        @self.app.get("/api/captions/history")
        async def captions_history(limit: int = Query(30, ge=1, le=200)):
            segments = []
            for row in self.harness.store.audio_segments_recent(limit):
                item = _clean_row(row)
                item["audio_url"] = f"/api/captions/audio/{item['segment_id']}"
                segments.append(item)
            return {"segments": segments}

        @self.app.get("/api/captions/audio/{segment_id}")
        async def captions_audio(segment_id: str):
            row = self.harness.store.get_audio_segment(segment_id)
            if row is None:
                raise HTTPException(status_code=404, detail="audio segment not found")
            audio_dir = (self.config.vault / "audio").resolve()
            target = Path(row["wav_path"]).resolve()
            try:
                target.relative_to(audio_dir)
            except ValueError as exc:
                raise HTTPException(status_code=403, detail="audio path outside vault") from exc
            if not target.is_file():
                raise HTTPException(status_code=404, detail="audio file has expired or is missing")
            return FileResponse(str(target), media_type="audio/wav", filename=target.name)

        @self.app.get("/api/captions/insights")
        async def captions_insights():
            return self.harness.store.audio_insights()

        @self.app.post("/api/twin/compress")
        async def twin_compress():
            return self.harness.compress_twin()

        @self.app.post("/api/app/shutdown")
        async def app_shutdown():
            """Gracefully stop this dashboard process after returning the response."""
            async def stop_later() -> None:
                await asyncio.sleep(0.15)
                self.shutdown()
                import os

                os._exit(0)

            asyncio.create_task(stop_later())
            return {"ok": True, "message": "SideLearner web app is shutting down"}

        @self.app.post("/api/chat")
        async def chat(body: dict):
            task = body.get("task", "")
            if not task:
                raise HTTPException(status_code=400, detail="task required")
            mode = body.get("mode", "auto")
            result = self.harness.chat(task, mode=mode)
            return {
                "ok": result.ok,
                "answer": result.answer,
                "steps": result.steps,
                "session": result.session_id,
            }

        @self.app.websocket("/ws")
        async def websocket_endpoint(websocket: WebSocket):
            await websocket.accept()
            queue: asyncio.Queue[dict] = asyncio.Queue(maxsize=200)
            self._ws_queues.add(queue)
            try:
                while True:
                    try:
                        event = await asyncio.wait_for(queue.get(), timeout=1.0)
                        await websocket.send_text(json.dumps(event, default=str))
                    except asyncio.TimeoutError:
                        # Send a keepalive ping so the connection stays open.
                        await websocket.send_text(json.dumps({"type": "ping", "ts": ""}))
            except WebSocketDisconnect:
                pass
            finally:
                self._ws_queues.discard(queue)

    # -- event bridge --------------------------------------------------------
    def _setup_event_bridge(self) -> None:
        self._ws_queues: set[asyncio.Queue] = set()
        self._bus_sub_id = self.harness.bus.subscribe("*", self._on_event)

    def _on_event(self, event: Event) -> None:
        data = event.as_dict()
        # Fast-forward to every websocket queue from the event bus thread.
        for queue in list(self._ws_queues):
            try:
                queue.put_nowait(data)
            except asyncio.QueueFull:
                pass

    def _minimal_index(self) -> str:
        return "<html><body><h1>SideLearner web dashboard</h1><p>Static files missing.</p></body></html>"

    def run(self, host: str = "127.0.0.1", port: int = 8080) -> None:
        import uvicorn

        uvicorn.run(self.app, host=host, port=port, log_level="info")

    def shutdown(self) -> None:
        if self._bus_sub_id is not None:
            try:
                self.harness.bus.unsubscribe(self._bus_sub_id)
            except Exception:  # noqa: BLE001
                pass
        self.harness.stop()


# -- CLI helper entrypoint -----------------------------------------------------
def main(argv: Optional[list[str]] = None) -> int:
    """Entrypoint used by `python -m sidelearner.web.server`."""
    import argparse
    import sys

    parser = argparse.ArgumentParser(prog="python -m sidelearner.web.server")
    parser.add_argument("--config", default=None)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", type=int, default=None)
    args = parser.parse_args(argv if argv is not None else sys.argv[1:])
    config = Config.load(args.config)
    server = WebServer(config)
    web_cfg = config.get("web") or {}
    host = args.host or web_cfg.get("host", "127.0.0.1")
    port = args.port if args.port is not None else int(web_cfg.get("port", 8080))
    try:
        server.run(host=host, port=port)
    finally:
        server.shutdown()
    return 0


if __name__ == "__main__":
    main()

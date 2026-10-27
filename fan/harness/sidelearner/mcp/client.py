"""Minimal synchronous MCP client supporting stdio and SSE transports."""
from __future__ import annotations

import json
import logging
import queue
import subprocess
import threading
import time
import urllib.parse
from typing import Any, Callable, Optional

import requests

log = logging.getLogger("sidelearner.mcp.client")


class MCPError(Exception):
    """Raised when an MCP call fails or the server is unreachable."""


class MCPClient:
    """A small synchronous MCP client.

    Supports two transports:
    - stdio: command is launched as a subprocess; JSON-RPC messages are sent/received over stdin/stdout.
    - sse: an SSE endpoint is streamed for server messages; outbound calls are POSTed to a message endpoint.

    The client implements just enough of the protocol for `initialize`, `tools/list`, and `tools/call`.
    """

    PROTOCOL_VERSION = "2024-11-05"

    def __init__(
        self,
        name: str,
        command: Optional[list[str]] = None,
        url: Optional[str] = None,
        env: Optional[dict] = None,
        timeout: float = 30.0,
        stderr: Optional[Any] = None,
    ) -> None:
        self.name = name
        self.command = command
        self.url = url
        self.env = env
        self.timeout = timeout
        self._stderr = stderr if stderr is not None else subprocess.DEVNULL
        self._transport: Optional[str] = "stdio" if command else ("sse" if url else None)
        self._proc: Optional[subprocess.Popen] = None
        self._reader_thread: Optional[threading.Thread] = None
        self._inbox: queue.Queue = queue.Queue()
        self._pending: dict[int, threading.Event] = {}
        self._responses: dict[int, dict] = {}
        self._next_id = 1
        self._lock = threading.Lock()
        self._stop = threading.Event()
        self._session: Optional[requests.Session] = None
        self._sse_event_id: Optional[str] = None
        self.server_info: dict = {}
        self.tools: list[dict] = []
        self.ready = False

    # -- lifecycle ----------------------------------------------------------
    def connect(self) -> bool:
        """Initialize the server. Returns True on success."""
        if self._transport == "stdio":
            return self._connect_stdio()
        if self._transport == "sse":
            return self._connect_sse()
        return False

    def disconnect(self) -> None:
        self._stop.set()
        if self._reader_thread is not None:
            self._reader_thread.join(timeout=2.0)
        if self._proc is not None:
            try:
                self._proc.terminate()
                self._proc.wait(timeout=2.0)
            except Exception:  # noqa: BLE001
                pass
            try:
                self._proc.kill()
            except Exception:  # noqa: BLE001
                pass
        self.ready = False

    def __enter__(self):
        self.connect()
        return self

    def __exit__(self, exc_type, exc, tb):  # noqa: ANN001
        self.disconnect()

    # -- stdio transport ----------------------------------------------------
    def _connect_stdio(self) -> bool:
        try:
            self._proc = subprocess.Popen(
                self.command,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=self._stderr,
                text=False,
                env=self.env,
            )
        except Exception as exc:  # noqa: BLE001
            log.warning("mcp %s: failed to start subprocess: %s", self.name, exc)
            return False

        self._reader_thread = threading.Thread(target=self._stdio_reader, name=f"mcp-{self.name}-reader", daemon=True)
        self._reader_thread.start()

        try:
            result = self._request(
                "initialize",
                {
                    "protocolVersion": self.PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {"name": "sidelearner", "version": "0.1.0"},
                },
            )
            self.server_info = result.get("serverInfo", {})
            self._notify("notifications/initialized", {})
            self.tools = self._request("tools/list", {}).get("tools", [])
            self.ready = True
            log.info("mcp %s: initialized (%s tools)", self.name, len(self.tools))
            return True
        except Exception as exc:  # noqa: BLE001
            log.warning("mcp %s: initialize failed: %s", self.name, exc)
            self.disconnect()
            return False

    def _stdio_reader(self) -> None:
        """Reads newline-delimited JSON from the subprocess stdout."""
        assert self._proc is not None and self._proc.stdout is not None
        while not self._stop.is_set():
            try:
                line = self._proc.stdout.readline()
            except Exception:  # noqa: BLE001
                break
            if not line:
                time.sleep(0.05)
                continue
            try:
                msg = json.loads(line.decode("utf-8").strip())
            except Exception:  # noqa: BLE001
                continue
            self._dispatch(msg)

    # -- sse transport ------------------------------------------------------
    def _connect_sse(self) -> bool:
        self._session = requests.Session()
        self._reader_thread = threading.Thread(target=self._sse_reader, name=f"mcp-{self.name}-reader", daemon=True)
        self._reader_thread.start()

        # Wait for the endpoint event so we know where to POST calls.
        deadline = time.monotonic() + self.timeout
        while self._sse_event_id is None and time.monotonic() < deadline:
            time.sleep(0.05)
        if self._sse_event_id is None:
            log.warning("mcp %s: no endpoint event received from SSE", self.name)
            self.disconnect()
            return False

        try:
            result = self._request(
                "initialize",
                {
                    "protocolVersion": self.PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {"name": "sidelearner", "version": "0.1.0"},
                },
            )
            self.server_info = result.get("serverInfo", {})
            self._notify("notifications/initialized", {})
            self.tools = self._request("tools/list", {}).get("tools", [])
            self.ready = True
            log.info("mcp %s: initialized (%s tools)", self.name, len(self.tools))
            return True
        except Exception as exc:  # noqa: BLE001
            log.warning("mcp %s: initialize failed: %s", self.name, exc)
            self.disconnect()
            return False

    def _sse_reader(self) -> None:
        """Reads SSE events; `endpoint` messages carry the POST URL; other events are JSON-RPC payloads."""
        assert self.url is not None and self._session is not None
        try:
            resp = self._session.get(self.url, stream=True, timeout=self.timeout)
            resp.raise_for_status()
        except Exception as exc:  # noqa: BLE001
            log.warning("mcp %s: sse connection failed: %s", self.name, exc)
            return

        event_type = ""
        data_lines: list[str] = []
        for raw in resp.iter_lines():
            if raw is None:
                continue
            try:
                line = raw.decode("utf-8")
            except Exception:  # noqa: BLE001
                continue
            if line.startswith("event:"):
                event_type = line[6:].strip()
            elif line.startswith("data:"):
                data_lines.append(line[5:].strip())
            elif line == "":
                if data_lines:
                    data = "\n".join(data_lines)
                    data_lines = []
                    if event_type == "endpoint":
                        self._sse_event_id = urllib.parse.urljoin(self.url, data)
                    else:
                        try:
                            msg = json.loads(data)
                        except Exception:  # noqa: BLE001
                            continue
                        self._dispatch(msg)
                event_type = ""

    # -- message dispatch ---------------------------------------------------
    def _dispatch(self, msg: dict) -> None:
        msg_id = msg.get("id")
        if msg_id is not None:
            with self._lock:
                self._responses[msg_id] = msg
                event = self._pending.pop(msg_id, None)
            if event is not None:
                event.set()
        # Notifications are currently ignored.

    def _next_request_id(self) -> int:
        with self._lock:
            req_id = self._next_id
            self._next_id += 1
            return req_id

    def _send(self, payload: dict) -> None:
        if self._transport == "stdio":
            assert self._proc is not None and self._proc.stdin is not None
            data = json.dumps(payload).encode("utf-8") + b"\n"
            try:
                self._proc.stdin.write(data)
                self._proc.stdin.flush()
            except Exception as exc:  # noqa: BLE001
                raise MCPError(f"failed to write to subprocess: {exc}") from exc
        elif self._transport == "sse":
            assert self._session is not None and self._sse_event_id is not None
            try:
                resp = self._session.post(self._sse_event_id, json=payload, timeout=self.timeout)
                resp.raise_for_status()
            except Exception as exc:  # noqa: BLE001
                raise MCPError(f"failed to post SSE message: {exc}") from exc
        else:
            raise MCPError("no transport configured")

    def _request(self, method: str, params: dict) -> dict:
        req_id = self._next_request_id()
        event = threading.Event()
        with self._lock:
            self._pending[req_id] = event
        payload = {"jsonrpc": "2.0", "id": req_id, "method": method, "params": params}
        self._send(payload)
        if not event.wait(timeout=self.timeout):
            with self._lock:
                self._pending.pop(req_id, None)
            raise MCPError(f"request {method} timed out")
        with self._lock:
            msg = self._responses.pop(req_id, {})
        if "error" in msg:
            err = msg["error"]
            raise MCPError(f"{method}: {err.get('message', err)}")
        return msg.get("result", {})

    def _notify(self, method: str, params: dict) -> None:
        payload = {"jsonrpc": "2.0", "method": method, "params": params}
        self._send(payload)

    # -- public tool calling ------------------------------------------------
    def call_tool(self, name: str, arguments: dict) -> dict:
        """Call a tool exposed by the MCP server."""
        if not self.ready:
            raise MCPError("client not connected")
        return self._request("tools/call", {"name": name, "arguments": arguments})

    def tool_named(self, name: str) -> Optional[dict]:
        for tool in self.tools:
            if tool.get("name") == name:
                return tool
        return None

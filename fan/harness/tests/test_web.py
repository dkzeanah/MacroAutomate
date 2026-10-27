"""Tests for the optional FastAPI web dashboard."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from sidelearner.config import Config
from sidelearner.web.server import WebServer


@pytest.fixture
def web_client(tmp_path_factory):
    workspace = tmp_path_factory.mktemp("sl-web")
    config = Config(
        data={
            "vault_dir": str(workspace / "vault"),
            "memory": {"db": str(workspace / "memory.db")},
            "web": {"enabled": True, "host": "127.0.0.1", "port": 0},
            "business": {"name": "test", "domain": "testing", "vocabulary": ["test"]},
            "perception": {"screen": {"enabled": False}, "window": {"enabled": False}, "audio": {"enabled": False}, "camera": {"enabled": False}},
        },
        workspace=workspace,
    )
    server = WebServer(config)
    client = TestClient(server.app)
    try:
        yield client
    finally:
        server.shutdown()


def test_index_loads(web_client):
    r = web_client.get("/")
    assert r.status_code == 200
    assert "SideLearner" in r.text


def test_api_status(web_client):
    r = web_client.get("/api/status")
    assert r.status_code == 200
    data = r.json()
    assert "twin" in data
    assert "config" in data


def test_twin_status(web_client):
    r = web_client.get("/api/twin/status")
    assert r.status_code == 200
    assert "graph" in r.json()


def test_twin_facts_empty(web_client):
    r = web_client.get("/api/twin/facts")
    assert r.status_code == 200
    assert r.json()["facts"] == []


def test_twin_gaps_empty(web_client):
    r = web_client.get("/api/twin/gaps")
    assert r.status_code == 200
    assert r.json()["gaps"] == []


def test_prompts_empty(web_client):
    r = web_client.get("/api/prompts")
    assert r.status_code == 200
    assert r.json()["prompts"] == []


def test_skills_list(web_client):
    r = web_client.get("/api/skills")
    assert r.status_code == 200
    assert "skills" in r.json()


def test_chat_missing_task(web_client):
    r = web_client.post("/api/chat", json={})
    assert r.status_code == 400


def test_captions_status_and_history(web_client):
    status = web_client.get("/api/captions/status")
    assert status.status_code == 200
    assert status.json()["surface"] == "windows-overlay"
    history = web_client.get("/api/captions/history")
    assert history.status_code == 200
    assert history.json()["segments"] == []
    insights = web_client.get("/api/captions/insights")
    assert insights.status_code == 200
    assert insights.json()["segments"] == 0
    assert insights.json()["facts"] == []
    missing = web_client.get("/api/captions/audio/missing")
    assert missing.status_code == 404


def test_shutdown_route_exists(web_client, monkeypatch):
    # Avoid terminating the test runner; verify the route is registered instead.
    paths = {route.path for route in web_client.app.routes}
    assert "/api/app/shutdown" in paths


def test_websocket_event_stream(web_client):
    # The websocket endpoint should accept connections and send keepalive pings.
    with web_client.websocket_connect("/ws") as ws:
        data = ws.receive_text()
        msg = __import__("json").loads(data)
        assert msg["type"] == "ping"

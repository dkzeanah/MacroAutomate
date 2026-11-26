"""Service lifecycle: listener ownership, safe takeover and agent liveness."""
import json
import os
import socket
import time

from bridge import common, desktop


def test_parse_listeners_selects_only_watched_listening_ports():
    table = """
  Proto  Local Address          Foreign Address        State           PID
  TCP    127.0.0.1:8771         0.0.0.0:0              LISTENING       28004
  TCP    127.0.0.1:8772         0.0.0.0:0              LISTENING       7092
  TCP    127.0.0.1:8772         0.0.0.0:0              LISTENING       30680
  TCP    127.0.0.1:8771         127.0.0.1:50123        ESTABLISHED     28004
  TCP    0.0.0.0:8765           0.0.0.0:0              LISTENING       42
  TCP    [::1]:8771             [::]:0                 LISTENING       999
"""
    # Windows SO_REUSEADDR can leave two listeners on one port; stop both.
    assert desktop.parse_listeners(table, {8771, 8772}) == {8771: [28004], 8772: [7092, 30680]}


def test_parse_listeners_ignores_malformed_rows():
    assert desktop.parse_listeners('TCP 127.0.0.1:8771 0.0.0.0:0 LISTENING', {8771}) == {}
    assert desktop.parse_listeners("TCP 127.0.0.1:notaport 0.0.0.0:0 LISTENING 12", {8771}) == {}
    assert desktop.parse_listeners('', {8771}) == {}


def test_ports_available_reflects_a_live_listener():
    with socket.socket() as temporary:
        temporary.bind(('127.0.0.1', 0))
        port = temporary.getsockname()[1]
        temporary.listen()
        assert not desktop.ports_available({port})
    assert desktop.ports_available({port})


def test_bridge_busy_blocks_takeover_while_work_is_running():
    idle = {'activity': {'running_tasks': 0, 'tools': [], 'application_runs': 0}, 'managed_scripts': []}
    assert not desktop.bridge_busy(idle)
    assert desktop.bridge_busy({**idle, 'activity': {'running_tasks': 1, 'tools': [], 'application_runs': 0}})
    assert desktop.bridge_busy({**idle, 'activity': {'running_tasks': 0, 'tools': ['window_inspect'], 'application_runs': 0}})
    assert desktop.bridge_busy({**idle, 'activity': {'running_tasks': 0, 'tools': [], 'application_runs': 2}})
    assert desktop.bridge_busy({**idle, 'managed_scripts': [{'run_id': 'owned'}]})


def test_parse_agent_pids_keeps_only_real_pids():
    assert desktop.parse_agent_pids('9304\r\nnot-a-pid\r\n0\r\n24148\r\n') == [9304, 24148]


def test_stale_agent_scan_failure_is_not_fatal(monkeypatch):
    def unavailable(*args, **kwargs):
        raise OSError('powershell unavailable')
    monkeypatch.setattr(desktop.subprocess, 'run', unavailable)
    assert desktop.stale_agent_pids() == []


def test_agent_heartbeat_is_pid_bound_and_freshness_limited(tmp_path, monkeypatch):
    path = tmp_path / 'agent.heartbeat'
    monkeypatch.setattr(common, 'AGENT_HEARTBEAT', path)
    common.write_agent_heartbeat()
    state = common.agent_heartbeat()
    assert state['pid'] == os.getpid()
    assert time.time() - state['at'] < 5

    path.write_text(json.dumps({'pid': os.getpid(), 'at': time.time() - 60}), encoding='utf-8')
    assert common.agent_heartbeat() == {}
    path.write_text(json.dumps({'pid': 0, 'at': time.time()}), encoding='utf-8')
    assert common.agent_heartbeat() == {}
    path.write_text('not json', encoding='utf-8')
    assert common.agent_heartbeat() == {}
    path.unlink()
    assert common.agent_heartbeat() == {}

"""Tests for the Studio GUI.

These exist because of one specific bug: the Guide tab set its own tree selection
while rendering, the resulting ``<<TreeviewSelect>>`` event re-entered the render,
and because Tk delivers virtual events through the queue rather than inline it did
not recurse -- it fed the event loop forever and froze the entire application.

Nothing that calls methods directly can catch that. It only shows up when the event
loop actually runs, so these tests run one.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

tk = pytest.importorskip("tkinter")

from atlas.store import Store


@pytest.fixture()
def workspace(tmp_path: Path) -> Path:
    root = tmp_path / "ws"
    root.mkdir()
    Store(root).close()
    return root


@pytest.fixture()
def app(workspace: Path):
    """A constructed, hidden StudioApp. Skipped when there is no display."""
    from studio.app import StudioApp

    try:
        instance = StudioApp(workspace)
    except tk.TclError as exc:
        pytest.skip(f"no display available: {exc}")
    instance.withdraw()
    # Settle initial Windows theme/layout work before timing queued event delivery.
    # Virtual selection events still run in _pump, including the original regression.
    instance.update_idletasks()
    yield instance
    try:
        instance.store.close()
        instance.destroy()
    except Exception:
        pass


def _pump(app, milliseconds: int = 900) -> int:
    """Run a real event loop briefly. Returns how many times a probe timer fired.

    A stalled loop fires the probe zero times; a healthy one fires it repeatedly.
    """
    fired = {"n": 0}

    def tick():
        fired["n"] += 1
        app.after(40, tick)

    app.after(20, tick)
    app.after(milliseconds, app.quit)
    app.mainloop()
    return fired["n"]


def test_all_tabs_construct(app) -> None:
    assert len(app.tabs) == len(app._tab_order)
    assert None not in app.tabs.values()


def test_event_loop_is_not_starved(app) -> None:
    """The regression: with the guide loop present, this fires zero times."""
    assert _pump(app) > 2, "the event loop is starved -- the app would freeze"


def test_guide_selection_settles_instead_of_looping(app) -> None:
    """One topic change must produce a bounded number of renders, then stop.

    A few extra renders are expected and harmless: selecting a row queues a virtual
    event that re-enters the handler once. What matters is that it converges -- the
    bug made each render queue another, forever.
    """
    guide = app.tabs["guide"]
    calls = {"n": 0}
    original = guide._render

    def counting(key):
        calls["n"] += 1
        return original(key)

    guide._render = counting
    guide._show("absorb")

    ticks = _pump(app, 700)
    settled = calls["n"]
    assert settled <= 4, f"_render ran {settled} times for one _show"
    assert ticks > 2, "the event loop was starved while the guide re-rendered"
    assert guide.tree.selection() == ("absorb",)

    # Letting the loop run longer must not add more renders.
    _pump(app, 500)
    assert calls["n"] == settled, (
        f"renders kept accumulating ({settled} -> {calls['n']}) -- the selection "
        f"event is feeding itself"
    )


def test_every_guide_topic_has_content(app) -> None:
    from studio.tabs.guide_tab import SECTIONS, TOPICS

    guide = app.tabs["guide"]
    listed = [key for _section, topics in SECTIONS for key, _label in topics]
    assert set(listed) == set(TOPICS), "the topic tree and the content must agree"

    for key in listed:
        guide._show(key)
        body = guide.body.get().strip()
        assert len(body) > 80, f"topic {key!r} rendered almost nothing"


def test_guide_live_view_reads_the_workspace(app) -> None:
    guide = app.tabs["guide"]
    guide._show("workspace")
    body = guide.body.get()
    assert "WHAT IS ACTUALLY IN YOUR WORKSPACE" in body
    assert "projects" in body


def test_switching_every_tab_keeps_the_loop_alive(app) -> None:
    for key in app._tab_order:
        app.select_tab(key)
        app._tab_changed()
    assert _pump(app) > 2, "switching tabs starved the event loop"


def test_create_tab_previews_without_writing(app, tmp_path: Path) -> None:
    create = app.tabs["create"]
    create.p_name.set("preview only")
    create.p_template.set("cli")
    create.p_where.set(str(tmp_path / "nowhere"))
    create._preview_project()

    assert create._scaffold is not None
    assert create._scaffold.files
    assert not (tmp_path / "nowhere").exists(), "preview must not touch the disk"


def test_job_pump_stops_when_the_widget_dies(app) -> None:
    """A pump that keeps rescheduling after teardown spams Tk errors on exit."""
    from studio.widgets import Job

    holder = tk.Toplevel(app)
    holder.withdraw()
    job = Job(holder)
    holder.destroy()
    job._pump()  # must return quietly rather than raise or reschedule


def test_job_delivers_results_on_the_main_thread(app) -> None:
    from studio.widgets import Job

    holder = tk.Toplevel(app)
    holder.withdraw()
    job = Job(holder, interval_ms=20)
    seen = {}
    job.on("done", lambda payload: seen.setdefault("value", payload))
    job.run(lambda: 6 * 7)
    _pump(app, 500)
    assert seen.get("value") == 42
    holder.destroy()

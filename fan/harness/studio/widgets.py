"""Reusable Tk widgets for the Studio.

The design constraint everywhere in this GUI is density: every tab should show as much
usable state as the window allows, with panes the operator can drag rather than fixed
splits that waste half the screen on whitespace.
"""

from __future__ import annotations

import queue
import threading
import tkinter as tk
from tkinter import ttk
from typing import Any, Callable, Iterable

MONO = ("Consolas", 9)
MONO_SMALL = ("Consolas", 8)
UI = ("Segoe UI", 9)
UI_BOLD = ("Segoe UI", 9, "bold")
UI_HEAD = ("Segoe UI", 11, "bold")


class SortableTable(ttk.Frame):
    """A Treeview with click-to-sort headings, a context menu, and row tags."""

    def __init__(
        self,
        master: Any,
        columns: list[str],
        headings: list[str] | None = None,
        widths: list[int] | None = None,
        anchors: list[str] | None = None,
        on_select: Callable[[dict[str, str]], None] | None = None,
        on_activate: Callable[[dict[str, str]], None] | None = None,
        height: int = 12,
    ) -> None:
        super().__init__(master)
        self.columns = columns
        self._rows: list[dict[str, Any]] = []
        self._sort_column: str | None = None
        self._sort_desc = False
        self._on_select = on_select
        self._on_activate = on_activate

        self.tree = ttk.Treeview(self, columns=columns, show="headings",
                                 height=height, selectmode="extended")
        heads = headings or columns
        widths = widths or [120] * len(columns)
        anchors = anchors or ["w"] * len(columns)
        for column, head, width, anchor in zip(columns, heads, widths, anchors):
            self.tree.heading(column, text=head,
                              command=lambda c=column: self.sort_by(c))
            self.tree.column(column, width=width, anchor=anchor, stretch=True)

        vsb = ttk.Scrollbar(self, orient=tk.VERTICAL, command=self.tree.yview)
        hsb = ttk.Scrollbar(self, orient=tk.HORIZONTAL, command=self.tree.xview)
        self.tree.configure(yscrollcommand=vsb.set, xscrollcommand=hsb.set)

        self.tree.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        hsb.grid(row=1, column=0, sticky="ew")
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)

        self.tree.tag_configure("hot", foreground="#0a7d28")
        self.tree.tag_configure("dim", foreground="#8a8a8a")
        self.tree.tag_configure("warn", foreground="#b35c00")
        self.tree.tag_configure("bad", foreground="#b32020")

        self.menu = tk.Menu(self, tearoff=0)
        self.menu.add_command(label="Copy row", command=self.copy_row)
        self.menu.add_command(label="Copy first cell", command=self.copy_cell)
        self.tree.bind("<Button-3>", self._show_menu)
        self.tree.bind("<<TreeviewSelect>>", self._selected)
        self.tree.bind("<Double-1>", self._activated)

    # ------------------------------------------------------------------- data
    def set_rows(self, rows: Iterable[dict[str, Any]]) -> None:
        self._rows = list(rows)
        self.redraw()

    def redraw(self) -> None:
        self.tree.delete(*self.tree.get_children())
        for row in self._rows:
            values = [str(row.get(c, "")) for c in self.columns]
            tags = row.get("_tags", ())
            self.tree.insert("", tk.END, values=values,
                             tags=tags if isinstance(tags, (tuple, list)) else (tags,))

    def sort_by(self, column: str) -> None:
        self._sort_desc = not self._sort_desc if self._sort_column == column else False
        self._sort_column = column

        def key(row: dict[str, Any]):
            value = row.get(column, "")
            try:
                return (0, float(str(value).replace(",", "").lstrip("*")))
            except (TypeError, ValueError):
                return (1, str(value).lower())

        self._rows.sort(key=key, reverse=self._sort_desc)
        self.redraw()

    def selected(self) -> dict[str, str] | None:
        selection = self.tree.selection()
        if not selection:
            return None
        values = self.tree.item(selection[0], "values")
        return dict(zip(self.columns, values))

    def selected_all(self) -> list[dict[str, str]]:
        out = []
        for item in self.tree.selection():
            out.append(dict(zip(self.columns, self.tree.item(item, "values"))))
        return out

    def row_count(self) -> int:
        return len(self._rows)

    # ----------------------------------------------------------------- events
    def _selected(self, _event=None) -> None:
        if self._on_select:
            row = self.selected()
            if row:
                self._on_select(row)

    def _activated(self, _event=None) -> None:
        if self._on_activate:
            row = self.selected()
            if row:
                self._on_activate(row)

    def _show_menu(self, event) -> None:
        item = self.tree.identify_row(event.y)
        if item:
            self.tree.selection_set(item)
            self.menu.tk_popup(event.x_root, event.y_root)

    def copy_row(self) -> None:
        row = self.selected()
        if row:
            self.clipboard_clear()
            self.clipboard_append("\t".join(row.values()))

    def copy_cell(self) -> None:
        row = self.selected()
        if row:
            self.clipboard_clear()
            self.clipboard_append(next(iter(row.values()), ""))


class TextPane(ttk.Frame):
    """A monospaced, scrollable, read-mostly text pane with copy/save affordances."""

    def __init__(self, master: Any, font=MONO, wrap: str = tk.NONE, height: int = 10) -> None:
        super().__init__(master)
        self.text = tk.Text(self, wrap=wrap, font=font, height=height,
                            undo=True, background="#fbfbfa")
        vsb = ttk.Scrollbar(self, orient=tk.VERTICAL, command=self.text.yview)
        self.text.configure(yscrollcommand=vsb.set)
        self.text.grid(row=0, column=0, sticky="nsew")
        vsb.grid(row=0, column=1, sticky="ns")
        if wrap == tk.NONE:
            hsb = ttk.Scrollbar(self, orient=tk.HORIZONTAL, command=self.text.xview)
            self.text.configure(xscrollcommand=hsb.set)
            hsb.grid(row=1, column=0, sticky="ew")
        self.rowconfigure(0, weight=1)
        self.columnconfigure(0, weight=1)

        self.text.tag_configure("head", foreground="#12507a", font=(font[0], font[1], "bold"))
        self.text.tag_configure("good", foreground="#0a7d28")
        self.text.tag_configure("bad", foreground="#b32020")
        self.text.tag_configure("dim", foreground="#7a7a7a")
        self.text.tag_configure("edge", foreground="#7a3fa0")

        menu = tk.Menu(self, tearoff=0)
        menu.add_command(label="Copy", command=lambda: self._event("<<Copy>>"))
        menu.add_command(label="Select all", command=self.select_all)
        menu.add_separator()
        menu.add_command(label="Clear", command=self.clear)
        self.text.bind("<Button-3>", lambda e: menu.tk_popup(e.x_root, e.y_root))

    def _event(self, name: str) -> None:
        self.text.event_generate(name)

    def set(self, value: str) -> None:
        self.text.delete("1.0", tk.END)
        self.text.insert("1.0", value)

    def append(self, value: str, tag: str | None = None) -> None:
        self.text.insert(tk.END, value, tag or ())
        self.text.see(tk.END)

    def get(self) -> str:
        return self.text.get("1.0", tk.END)

    def clear(self) -> None:
        self.text.delete("1.0", tk.END)

    def select_all(self) -> None:
        self.text.tag_add(tk.SEL, "1.0", tk.END)

    def highlight_atlas(self) -> None:
        """Colour the @atlas mirror comments so a slice reads at a glance."""
        self.text.tag_remove("edge", "1.0", tk.END)
        index = "1.0"
        while True:
            found = self.text.search("# @atlas", index, tk.END)
            if not found:
                break
            line_end = f"{found} lineend"
            self.text.tag_add("edge", found, line_end)
            index = line_end


class Field(ttk.Frame):
    """A label plus an entry, laid out horizontally, for dense toolbars."""

    def __init__(self, master: Any, label: str, value: str = "", width: int = 24,
                 values: list[str] | None = None) -> None:
        super().__init__(master)
        ttk.Label(self, text=label, font=UI).pack(side=tk.LEFT, padx=(0, 4))
        self.var = tk.StringVar(value=value)
        if values is not None:
            self.widget: ttk.Widget = ttk.Combobox(
                self, textvariable=self.var, width=width, values=values
            )
        else:
            self.widget = ttk.Entry(self, textvariable=self.var, width=width)
        self.widget.pack(side=tk.LEFT, fill=tk.X, expand=True)

    def get(self) -> str:
        return self.var.get().strip()

    def set(self, value: str) -> None:
        self.var.set(value)

    def set_values(self, values: list[str]) -> None:
        if isinstance(self.widget, ttk.Combobox):
            self.widget.configure(values=values)


class Job:
    """Run work off the UI thread and deliver results back through a queue.

    Tk is not thread safe, so a worker never touches a widget -- it posts messages and
    the main loop drains them. Long sweeps and indexes therefore cannot freeze the app.
    """

    def __init__(self, widget: tk.Misc, interval_ms: int = 80) -> None:
        self.widget = widget
        self.queue: "queue.Queue[tuple[str, Any]]" = queue.Queue()
        self.interval = interval_ms
        self._handlers: dict[str, Callable[[Any], None]] = {}
        self._running = 0
        self._pump()

    def on(self, kind: str, handler: Callable[[Any], None]) -> None:
        self._handlers[kind] = handler

    def post(self, kind: str, payload: Any = None) -> None:
        self.queue.put((kind, payload))

    @property
    def busy(self) -> bool:
        return self._running > 0

    def run(self, target: Callable[[], Any], done_kind: str = "done",
            error_kind: str = "error") -> None:
        self._running += 1

        def wrapper() -> None:
            try:
                self.post(done_kind, target())
            except Exception as exc:  # surfaced in the UI, never swallowed
                import traceback
                self.post(error_kind, f"{exc}\n\n{traceback.format_exc()}")
            finally:
                self._running -= 1

        threading.Thread(target=wrapper, daemon=True).start()

    def _pump(self) -> None:
        try:
            while True:
                kind, payload = self.queue.get_nowait()
                handler = self._handlers.get(kind)
                if handler:
                    try:
                        handler(payload)
                    except Exception:
                        import traceback
                        traceback.print_exc()
        except queue.Empty:
            pass
        # Stop rescheduling once the widget is gone, otherwise Tk reports an invalid
        # command for every pending callback as the window tears down.
        try:
            if not self.widget.winfo_exists():
                return
            self.widget.after(self.interval, self._pump)
        except tk.TclError:
            return


def toolbar(master: Any) -> ttk.Frame:
    """A thin horizontal strip for buttons and fields."""
    frame = ttk.Frame(master, padding=(6, 4))
    frame.pack(side=tk.TOP, fill=tk.X)
    return frame


def button(master: Any, text: str, command: Callable[[], None],
           width: int | None = None, side: str = tk.LEFT) -> ttk.Button:
    widget = ttk.Button(master, text=text, command=command)
    if width:
        widget.configure(width=width)
    widget.pack(side=side, padx=2)
    return widget


def separator(master: Any) -> None:
    ttk.Separator(master, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=6)


def section(master: Any, title: str) -> ttk.LabelFrame:
    frame = ttk.LabelFrame(master, text=title, padding=6)
    return frame

from __future__ import annotations

import sys
import tkinter as tk
from tkinter import messagebox

from ojas.app import OllamaJobAutomationStudio


def main() -> None:
    root = tk.Tk()
    try:
        app = OllamaJobAutomationStudio(root)
        root.protocol("WM_DELETE_WINDOW", app.on_close)
        root.mainloop()
    except Exception as exc:
        messagebox.showerror("Startup error", f"{type(exc).__name__}: {exc}")
        raise


if __name__ == "__main__":
    main()

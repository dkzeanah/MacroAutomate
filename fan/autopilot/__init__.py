"""Fan Autopilot: routine discovery, plain-English workflow compilation and portal audit reports.

The AutoHotkey application owns input, the GUI and the workflow engine. This
package is a pure, testable helper it starts as a short-lived process
(``python -m fan.autopilot.cli request.json``). It reads local SQLite data
read-only, never sends usage history to a model, and only calls a language
model for an explicit "describe it" compile request.
"""

VERSION = "1.0"

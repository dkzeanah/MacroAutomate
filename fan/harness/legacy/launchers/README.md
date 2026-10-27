# Previous launchers

These were the separate `.bat` files this workspace used before `Harness.bat`
replaced them. They are kept because nothing in this project is ever deleted --
and because they still work if you run them from the workspace root.

Everything they did is now reachable from one place:

| Was | Now |
|---|---|
| `Studio.bat` | `Harness.bat` |
| `Atlas.bat <cmd>` | `Harness.bat atlas <cmd>` |
| `SideLearner.bat` | Harness tab, or `Harness.bat run "sl"` |
| `StartSideLearner.bat` / `StopSideLearner.bat` | Harness tab |
| `Creator_Ops_GUI.bat` | Harness tab -> creator_ops_gui |
| `Creator_Ops_Worker.bat` | Harness tab -> creator_ops_worker |

The Harness tab lists every tool in every absorbed project, so anything that used
to need its own shortcut is now one row in a table you can search.

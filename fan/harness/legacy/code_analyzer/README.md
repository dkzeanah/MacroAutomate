# Python Code Analyzer Manager

A full-screen friendly Python GUI app for analyzing, storing, running, and explaining Python projects from a beginner-friendly perspective.

## Features

- Open any Python project folder.
- Analyze Python files with `ast`.
- Store projects, source snapshots, objects, commands, hotkeys, workflows, LLM messages, and analysis runs in SQLite.
- View sortable tables for files, objects, commands, hotkeys, and database-related code.
- Right-click context menus on text panes and tables.
- Generate setup commands for fresh environments.
- Generate a demonstration script that explains how to showcase the analyzed project.
- Generate next-phase extension steps.
- Run selected Python files from the GUI.
- Optional local Ollama LLM self-review loop for deeper analysis.
- Fullscreen toggle with F11.

## Fresh Windows Setup

```powershell
cd path\to\python_code_analyzer_manager
python -m venv .venv
.\.venv\Scripts\activate
python -m pip install --upgrade pip
python app.py
```

Or double-click:

```text
run_windows.bat
```

## Fresh Linux Setup

```bash
cd path/to/python_code_analyzer_manager
chmod +x run_linux.sh
./run_linux.sh
```

## Optional Ollama Setup

Install Ollama, then run:

```bash
ollama pull llama3.1
ollama serve
```

Inside the GUI, keep:

```text
Model: llama3.1
URL: http://localhost:11434/api/generate
```

## Built-in Hotkeys

| Hotkey | Action |
|---|---|
| Ctrl+O | Open Project |
| Ctrl+R | Analyze Project |
| F5 | Run Selected File |
| Ctrl+S | Save Notes/status |
| F11 | Toggle Fullscreen |

## Database Picture

The app creates this SQLite file beside `app.py`:

```text
code_analyzer_manager.sqlite3
```

Tables:

- `projects`: each analyzed project root.
- `source_files`: source snapshots for every analyzed Python file.
- `analysis_runs`: JSON payloads for each analysis pass.
- `objects`: detected classes/functions/methods.
- `commands`: setup/run/test commands inferred from the project.
- `hotkeys`: configurable key bindings.
- `workflows`: workflow-like functions and planned chains.
- `llm_messages`: stored conversation/insight messages.
- `settings`: Ollama URL/model and GUI settings.

## How To Use

1. Start the app.
2. Click **Open Project**.
3. Select a folder containing Python files.
4. Review the generated **Overview**, **Demo Script**, **Objects**, **Data Picture**, **Commands**, and **Next Steps** tabs.
5. Select a Python file in the left table and press **F5** or click **Run File**.
6. Start Ollama and click **LLM Self Review** for iterative autonomous analysis.

## Next Extension Ideas

- Add file editing and save-back support.
- Add ERD rendering for SQLite/SQLAlchemy projects.
- Add dependency graph visualization.
- Add test generation from detected functions.
- Add safe refactoring queue and patch preview.
- Add project templates for beginner lessons.

# DeepSeek Harness ↔ AutoHotkey v2 Bridge

Bidirectional Windows automation using **official DeepSeek Harness**, **DeepSeek V4 Pro**, AutoHotkey v2, a loopback Python gateway, SQLite, and an MCP stdio server.

## Components

| File | Purpose |
| --- | --- |
| `bridge/gateway.py` | Token-authenticated HTTP gateway, FIFO dispatch and SQLite event/task logs |
| `bridge/mcp_server.py` | MCP tool provider registered in DeepSeek Harness |
| `ahk/Worker.ahk` | AutoHotkey v2 worker and hotkey-based agent task entry |
| `bridge/agent.py` | Separate DeepSeek API consumer for AHK-originated tasks, plus CLI agent |
| `harness/cordis.patch.yml` | Example MCP client registration for official `dsh` Harness |
| `tests/test_gateway.py` | Authentication, allowlisting, polling and task queue tests |

## Install (Windows 11, Python 3.12+, AHK v2)

### Fan integration

In this repository, **Fan → DeepSeek Bridge (tab 20)** manages the gateway,
worker, API agent and observatory automatically. Use its own chat/task interface;
the existing Fan key is read from Credential Manager and inherited by the
agent process. It is not written to `.env`. Every task uses the same tool-enabled
agent; there is no Chat/Desktop switch. `bridge/desktop.py` owns service
lifecycle and skips occupied ports on first setup. `bridge/transport.py` streams
the same Chat Completions API directly to avoid unrelated SDK startup overhead.
The original manual launch scripts below remain available for standalone use.

1. Unzip the folder to a chosen location and run `install.bat`. Open `.env` and set your DeepSeek API key (`DEEPSEEK_API_KEY`). Do **not** share this file.
2. Run `start_gateway.bat`.
3. Run `ahk/Worker.ahk` with AutoHotkey **v2**.
4. Run `start_agent_daemon.bat` for tasks initiated from AutoHotkey.
5. For Harness-initiated tasks, install/run the official DeepSeek Harness and configure the MCP plugin below. Enter the DeepSeek API key in Harness Settings → Models and select `deepseek-v4-pro` (if available for your account).

AutoHotkey hotkeys:
- `Ctrl+Alt+J` — submit a prompt to the separate V4 Pro agent daemon.
- `Ctrl+Alt+Shift+J` — show worker connection information.

Tasks are queued in SQLite and processed asynchronously **on your local machine while the daemon is running**. Inspect their statuses with the authenticated API or the database.

## Hook into DeepSeek Harness

Official project: https://github.com/deepseek-ai/deepseek-harness

Harness supports the MCP client plugin `@deepseek-ai/dsh-mcp-client`. In the appropriate active profile's `cordis.patch.yml`, **merge** the entry from `harness/cordis.patch.yml` (do not blindly replace your existing configuration). Set `cwd` to the **actual absolute folder** where you extracted this project. Replace `command: python` with the absolute path of `.venv\\Scripts\\python.exe` if Harness doesn't inherit your virtual environment's PATH.

The config looks like:

```yaml
- insert:
    - id: mcp-ahk-windows
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: ahk-windows
        transport: stdio
        command: 'C:\\bridge\\.venv\\Scripts\\python.exe'
        args: ['-m', 'bridge.mcp_server']
        env: {}
        cwd: 'C:\\bridge'
```

**These example paths must be changed to your real folder path.** The active Harness config format can vary across releases. Verify in the official Harness MCP documentation.

Once started, Harness can discover `mcp__ahk-windows__window_list`, `window_active`, `window_activate`, `text_type` and `key_send` (names may be normalized by Harness).

Example Harness request: "Find Notepad, activate it, and type a greeting." Harness invokes the MCP tools; the gateway queues them; the AHK worker executes them and returns results.

## Call the agent from AutoHotkey

`Ctrl+Alt+J` creates a task via `/tasks` and the **separate Python DeepSeek chat-completions agent** (`bridge.agent --daemon`) executes it using the same gateway tools. This is intentionally not described as submitting to an existing `dsh` session: no stable session-ingress API is assumed. Both agents use the configured V4 Pro backend, but their conversation histories are separate.

Direct CLI example:

```powershell
.venv\Scripts\python.exe -m bridge.agent "List open windows and activate Notepad"
```

## Access from another AHK script

Run this AHK v2 code in the context of `Worker.ahk` to queue a request:

```autohotkey
result := Http('POST', '/tasks', '{"prompt":"' JsonEscape('Tell me which window is active') '"}', 'application/json')
MsgBox result
```

To call from a separate AHK process, factor `Http`, `JsonEscape`, `ReadEnv`, etc., out of `Worker.ahk` into a shared included library, or POST to the gateway using the generated `BRIDGE_TOKEN` header.

## Tests

```powershell
.venv\Scripts\python.exe -m pytest -q
```

The tests use a simulated AHK worker; they do **not** prove Windows GUI automation works. Live testing requires Windows and AutoHotkey v2. End-to-end DeepSeek requests require an API key and may incur charges.

## Security / safety

- Listens **only** on `127.0.0.1`, with random bearer-style token in `.env`.
- Agent-authored AHK scripts are saved under `agent_scripts` and can run through managed execution with output, status and cancellation. Fan APIs use explicit schemas; source access is limited to the project libraries.
- Tool schema validation, request limit and explicit allowlist.
- The AHK worker executes foreground keyboard operations **without an approval dialog**. Use a dedicated standard-privilege desktop session and supervise it. Do not give untrusted users access to your token or Harness session.
- A malicious website/browser could receive typed text if it is foregrounded; always verify the active window before typing. This demo intentionally does not attempt to defeat Windows privilege boundaries.
- Logs can include typed text or prompts. Protect the SQLite file and periodically purge sensitive history.
- Single workstation design. Multiple gateway/daemon instances are not supported.

## Documentation

- DeepSeek API: https://api-docs.deepseek.com/
- DeepSeek Harness MCP client: https://github.com/deepseek-ai/deepseek-harness/blob/master/packages/mcp/mcp-client/README.md

## Enhanced automation (AHK v2 script authoring/execution)

The agent now has `ahk_script_list`, `ahk_script_write`, `ahk_script_read`, `ahk_script_run`, `mouse_move`, and `mouse_click` in both the MCP provider and the API agent registry. `ahk_script_write` accepts `name`, full `source` starting with `#Requires AutoHotkey v2.0`, and optional `overwrite`. Files are confined to `agent_scripts/*.ahk`. The run tool executes via a configured AutoHotkey v2 executable, with bounded wait and captured process exit data. There is no shell wrapper.

Script execution is enabled for the unified agent. Optional `AUTOHOTKEY_EXE=C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe` selects the interpreter. Saved scripts run as managed processes through `ahk_script_run`, with status, output, cancellation and indexed source revisions. Async GUI scripts stay open until dismissed or stopped; an explicit `wait=true` applies the requested timeout. Generated scripts can call Fan's live internal APIs through the standalone `FanBridgeClient.ahk` SDK.

The agent registry system prompt now describes the new tools, and the Observatory will show `agent_tool_call` and `agent_tool_result` for API agent tasks. These are *observable actions*; `reasoning_content` only appears when DeepSeek returns it. For Harness-originated tasks, only gateway-mediated tool events are visible, not all internal Harness reasoning.

See `ECHO7_EVALUATIONS.md` for three behavioral tests and the tool-competence prompt. The simulated reward-reversal game is `python -m bridge.echo7_rules` (30 paid API calls, not run automatically).
## Live control feedback

Fan shows a blinking red circle beside the taskbar on Windows display 2 (the
primary display when only one is connected). A nearby label reports the active
tool, agent, or script. The circle follows live running tasks, pending tool calls,
and managed scripts, including tasks submitted outside the Fan conversation.
It disappears when idle, when services stop, or when the gateway heartbeat fails.

During `fan_window_inspect`, an amber border marks the inspected region and cyan
borders acknowledge the first 24 observed elements as accessibility discovery
runs. After perception completes, cyan borders briefly mark returned controls,
OCR lines, or pattern matches. Mouse actions briefly mark the actual point;
keyboard/text actions mark the receiving window. Protected and disabled controls
are excluded. These acknowledgements expire after 1.2 seconds (650 ms for input)
and clear when the observed window moves or loses foreground focus.

Feedback windows cannot take focus or receive clicks. They use Windows capture
exclusion, and native perception hides its feedback before reading pixels, OCR,
or capture hashes. Historical conversation events never replay highlights.
Arbitrary scripts receive a running-script indicator; element highlights require
using Fan's native perception APIs, which expose observed screen geometry.


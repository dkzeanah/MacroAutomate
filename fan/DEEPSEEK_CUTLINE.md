# Fan + Cutline in the live DeepSeek Harness

The live web profile now has an Atlas reading/execution persona. Start code work with `context_map_overview` and `context_map_pack`, fetch exact missing source with `context_map_get`, then delegate an objective and relevant context through `fan_agent_submit`. Use `fan_agent_status`, `fan_agent_events` and `fan_agent_cancel` to observe/control the existing durable agent queue. The Fan agent can execute native UI workflows and call Cutline's media/Remotion services. Nested delegation is refused.

`context_map_compare` estimates mapped versus full indexed-source context by default; `run_models=true` enables a paid fresh pair and saves actual usage/answers. Follow-up source retrieval must be counted too. A measured 29-file Atlas sample reached the same six source-checked facts after two requested slices with 18,230 cumulative tokens versus 104,122 for full source (82.49% fewer); this is a sample, not general proof. The maintained report/usage guide is avideditor's `docs/atlas-agent-comparison.md`.

React/Remotion now renders registered compositions in avideditor's `projects/motion-studio`; `remotion.render` is an async media method. `ConnectedDemo` is a two-shot example, and `MotionScene` consumes DeepSeek-authored JSON recipes. Run `npm run studio` in that project to preview/scrub editable React compositions.

Run `./fan/Connect_DeepSeek_Cutline.ps1` from the MacroAutomate root. It starts missing authenticated local gateways, checks health and installs one idempotent MCP entry in the existing DeepSeek web profile. The current Harness at `http://127.0.0.1:3080/` hot-loads `mcp-fan-cutline`; its tools use the `mcp__fan__` namespace. Existing profile settings are preserved with a backup before the first edit. Fan and Cutline still run independently.

Fan's existing automation tools are unchanged. Five new tools expose the maintained avideditor media service: `cutline_capabilities`, `cutline_call`, `cutline_job_submit`, `cutline_job_status`, and `cutline_job_cancel`. The API agent and MCP server share the same schemas and routing. The gateway handles media calls without requiring native AHK input; window automation continues to require the usual native Fan/worker connection.

Ask DeepSeek to discover Cutline's motion format, author/validate a scene, submit `motion.render`, poll the job and return its output paths. Other discoverable methods include the existing transcription, media analysis, presenter, knowledge and remix services. Cutline can call back into Fan using `automation.describe` and `automation.call`; reverse calls to `cutline_*` are refused to prevent recursion. Tool sharing does not merge the Harness and Fan agents' conversations.

The default Cutline service is `http://127.0.0.1:8780`; Fan's port remains selected by its `.env`. The integration reads existing local tokens and keeps them out of the Harness patch. Set `CUTLINE_ROOT`, `CUTLINE_API_URL`, `CUTLINE_API_TOKEN_FILE` or `CUTLINE_API_TOKEN` for a different media installation. Cutline's own `MediaAPI.ps1` starts it independently.

The motion engine is a declarative 2D renderer: text/shapes, keyframes, easing, MP4, PNG poster, editable JSON, and a Cutline project containing the compiled video. `motion.generate` explicitly uses DeepSeek; supplying scene JSON to `motion.render` makes no model call. There is currently no graphical keyframe editor or individual native timeline layer editing.

Detailed protocol, startup, limits and standalone CLI usage live in avideditor's `docs/deepseek-fan-motion.md`. For this installation that maintained document is at `C:/Users/Don/Desktop/avideditor/docs/deepseek-fan-motion.md`.

## Check the connection

From `fan/DeepSeekBridge`:

```powershell
.\.venv\Scripts\python.exe -m pytest tests/test_cutline.py tests/test_gateway.py -q
.\.venv\Scripts\python.exe -m bridge.verify_studio --output C:\Users\Don\Desktop\avideditor\generated\motion\connection-check
```

The second command checks the live Harness plugin, discovers real MCP tools, calls Cutline, calls back into native Fan and renders a scene. Add `--generate` only when you want an additional paid DeepSeek direction call. Output includes `integration-verification.json` and playable media. API job records are bounded and in memory; completed output files persist across restarts.

## Restart after closing the Harness console

The console owns the DeepSeek web process; closing it stops that process. Restart from any PowerShell directory with:

```powershell
& "$env:USERPROFILE\Desktop\aAutomateMacro\fan\Connect_DeepSeek_Cutline.ps1"
& "$env:USERPROFILE\.dsh\start-developer-memory.ps1"
```

For delegated desktop work, keep MacroAutomate running with its DeepSeek Bridge services started. The connector starts/checks the optional API services and installs the profile settings; the second command starts the same Developer Memory web harness as before. `Processing request of type ListToolsRequest` is normal tool discovery.

The Fan MCP entry now uses `failOnStartupError: false`. A temporary connection/discovery failure is logged and retried under the Harness's reconnect policy; it no longer makes this optional integration abort the whole web app. The installer migrates the earlier `true` setting only inside `mcp-fan-cutline`, saves a backup, and preserves other plugins, environment settings and the Atlas persona. Re-running the connector applies this migration to an existing profile.

`toolCallTimeoutMs` controls tool execution, not initialization. The installed Harness MCP SDK uses a separate 60-second connection/discovery timeout. An initialization timeout is not evidence of an invalid DeepSeek API key, and raising the tool execution timeout does not fix initialization. After recovery, verify that the Fan plugin is active and that its tool list is present before delegating tasks.

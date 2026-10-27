# Native Learning Workbench and optional web viewer

Open **DeepSeek Bridge → Live workbench** in Macro Automator. The default viewer is `fan/NativeLearningWorkbench.ahk`, a separate native AHK GUI process. It uses native list, text, tab and picture controls. Its inventory loads in small pages; source and full schemas load when selected. Chrome is not required. See `fan/LIVE_WORKBENCH_GUIDE.md`.

The monitor reads SQLite, displays task status, chat content, the tool arguments/results and any `reasoning_content` streamed by DeepSeek's API for **new** requests. It does not retroactively capture past reasoning. Requests submitted via AutoHotkey use the instrumented `bridge.agent` API loop. Direct DeepSeek Harness sessions are a distinct runtime: their private reasoning and chat are not intercepted by this patch; only MCP tool calls passing through the gateway are in the bridge event log. If the API doesn't return `reasoning_content`, the reasoning pane remains empty.

Thinking defaults to **max** and shows actual provider output. **Web (optional)** opens the companion browser view. Both viewers use the same authenticated loopback service and retained task/event/learning data. Ports are read from local configuration. Viewing evidence does not send input to the target application.

"""MCP and API clients see the same complete typed tool inventory."""
import asyncio

from bridge import catalog, mcp_server


def test_mcp_exposes_all_unified_tools_and_parameter_inputs():
    tools = asyncio.run(mcp_server.mcp.list_tools())
    by_name = {tool.name: tool for tool in tools}
    assert set(by_name) == set(catalog.TOOLS) - catalog.LOCAL_PAGE_TOOLS - catalog.LOCAL_JOB_TOOLS
    assert 'inputs' in by_name['ahk_script_run'].inputSchema['properties']
    assert 'input_schema' in by_name['ahk_script_write'].inputSchema['properties']
    assert 'name' not in by_name['fan_pattern_search'].inputSchema.get('required', [])
    assert {'name', 'text'} <= by_name['fan_pattern_search'].inputSchema['properties'].keys()


def test_mcp_proxy_dispatches_complete_workflow_steps(monkeypatch):
    observed = []
    monkeypatch.setattr(mcp_server, 'request_tool', lambda name, args, **kwargs: observed.append((name, args)) or {'ok': True})
    result = asyncio.run(mcp_server.mcp.call_tool('fan_workflow_save', {
              'name': 'native', 'steps': [{'action': 'Type', 'text': 'café'}]}))
    assert observed[0][0] == 'fan_workflow_save'
    assert observed[0][1]['steps'] == [{'action': 'Type', 'text': 'café'}]
    assert result

"""MCP exposes the same unified typed tools as the Fan API agent."""
from __future__ import annotations
import inspect

from mcp.server.fastmcp import FastMCP
from .common import request_tool
from .catalog import TOOLS, LOCAL_PAGE_TOOLS, LOCAL_JOB_TOOLS, validate

mcp = FastMCP('fan-windows-automation')


def proxy(name: str, model, description: str):
    def invoke(**arguments) -> dict:
        args = validate(name, arguments)
        timeout = args.get('timeout_seconds', 60) + 15 if name in ('ahk_script_run', 'fan_workflow_run') else 40
        if name in ('fan_taskbar_learn', 'fan_taskbar_open'):
            timeout = 270 if name == 'fan_taskbar_learn' else 110
        return request_tool(name, args, timeout=timeout)

    parameters = []
    annotations = {'return': dict}
    for key, field in model.model_fields.items():
        default = (inspect.Parameter.empty if field.is_required() else
                   field.default_factory() if field.default_factory else field.default)
        parameters.append(inspect.Parameter(key, inspect.Parameter.KEYWORD_ONLY,
                                            default=default, annotation=field.annotation))
        annotations[key] = field.annotation
    invoke.__name__ = name
    invoke.__doc__ = description
    invoke.__annotations__ = annotations
    invoke.__signature__ = inspect.Signature(parameters, return_annotation=dict)
    return invoke


for _name, (_model, _description) in TOOLS.items():
    if _name in LOCAL_PAGE_TOOLS | LOCAL_JOB_TOOLS:
        continue
    mcp.add_tool(proxy(_name, _model, _description), name=_name, description=_description)


def main() -> None:
    mcp.run(transport='stdio')


if __name__ == '__main__':
    main()

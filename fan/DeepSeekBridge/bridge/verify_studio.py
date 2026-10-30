"""Live MCP/API smoke. Model calls happen only with the explicit --generate flag."""
from __future__ import annotations
import argparse
import asyncio
import json
from pathlib import Path
import sys
import time
import uuid
import httpx
from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client
from .common import ROOT


async def verify(output, generate=False):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {}
    with httpx.Client(timeout=10, trust_env=False) as client:
        endpoint = 'pluginInventory/list'
        response = client.post('http://127.0.0.1:3080/api/'+endpoint, json={
            'type': 'client-request', 'rpcId': str(uuid.uuid4()), 'method': endpoint, 'payload': {'args': {}}})
        entries = response.json()['result']['value']['entries']
        report['harness_plugin'] = [entry for entry in entries if 'mcp-fan-cutline' in entry['entryId']]
        assert any(entry['fiberPhase'] == 'active' for entry in report['harness_plugin']), 'Harness MCP plugin is not active'
    parameters = StdioServerParameters(command=sys.executable, args=['-m', 'bridge.mcp_server'], cwd=str(ROOT))
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer) as session:
            await session.initialize()
            async def call(name, arguments):
                reply = await session.call_tool(name, arguments)
                if reply.isError:
                    raise RuntimeError(str(reply.content))
                return reply.structuredContent or json.loads(reply.content[0].text)
            inventory = await session.list_tools()
            report['mcp_tool_count'] = len(inventory.tools)
            capabilities = await call('cutline_capabilities', {})
            report['media_method_count'] = len(capabilities['methods'])
            ping = await call('cutline_call', {'method': 'ping'})
            assert ping['status'] == 'complete' and ping['result']['pong']
            reverse = await call('cutline_call', {'method': 'automation.call', 'params': {'tool': 'fan_capabilities'}})
            assert reverse['status'] == 'complete' and reverse['result']['ok']
            report['bidirectional_native_api'] = True
            scene = capabilities['motion']['example']
            if generate:
                job = await call('cutline_job_submit', {'method': 'motion.generate', 'params': {'prompt':
                    'Create a six-second 1280x720 30fps motion graphics opener titled CONNECTED. '
                    'Animate three cards labelled DEEPSEEK, CUTLINE, FAN with staggered entrances, '
                    'a unifying rule, mint and violet accents on dark navy. End with CREATIVE AUTOMATION. '
                    'Use no more than 10 layers. Keep every keyframe within six seconds and text within its box.'}})
                job = await settle(call, job['id'])
                direction = job['result']
                scene = direction['scene']
                (output/'deepseek-direction.json').write_text(json.dumps(direction, indent=2), encoding='utf-8')
                report['deepseek'] = {key: direction[key] for key in ('model', 'usage')}
            job = await call('cutline_job_submit', {'method': 'motion.render',
                'params': {'scene': scene, 'output_dir': str(output)}})
            report['render'] = (await settle(call, job['id']))['result']
    (output/'integration-verification.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


async def settle(call, ident):
    deadline = time.monotonic()+240
    while time.monotonic() < deadline:
        item = await call('cutline_job_status', {'job_id': ident})
        if item['status'] == 'complete':
            return item
        if item['status'] in ('failed', 'cancelled'):
            raise RuntimeError(item.get('error', item['status']))
        await asyncio.sleep(.5)
    raise TimeoutError(f'Job {ident} is still observable through cutline_job_status')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--generate', action='store_true')
    args = parser.parse_args()
    print(json.dumps(asyncio.run(verify(args.output, args.generate)), indent=2))


if __name__ == '__main__':
    main()

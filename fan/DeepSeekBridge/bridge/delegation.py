"""Harness-to-Fan delegation reuses the durable task queue and agent daemon."""
from pydantic import BaseModel, ConfigDict, Field

class Arguments(BaseModel):
    model_config = ConfigDict(extra='forbid')

class Submit(Arguments):
    prompt: str = Field(min_length=1, max_length=12000)
    atlas_context: str = Field(default='', max_length=100000)

class Identity(Arguments):
    task_id: str = Field(pattern=r'^[a-f0-9]{32}$')

class Events(Identity):
    after: int = Field(default=0, ge=0)

TOOL_DEFINITIONS = {
    'fan_agent_submit': (Submit, 'Delegate an execution task to MacroAutomate\'s DeepSeek automation agent. Supply relevant Atlas context. Returns task_id; poll status/events. The agent uses native AHK/UI tools and Cutline/Remotion APIs. Makes model calls; conversation history is separate. Nested delegation is refused.'),
    'fan_agent_status': (Identity, 'Read delegated Fan task status and final response. Queued/running is not completion.'),
    'fan_agent_events': (Events, 'Read delegated tool calls/results, evidence and provider usage after a cursor.'),
    'fan_agent_cancel': (Identity, 'Cancel a delegated Fan task through the existing cancellation API.'),
}

def dispatch(name, args, token, origin_task=None):
    from . import gateway
    if name == 'fan_agent_submit':
        if origin_task:
            raise ValueError('Nested delegation refused; the delegated agent executes with its own tools')
        context = args.get('atlas_context', '')
        history = [gateway.HistoryMessage(role='user', content='REFERENCE CODE CONTEXT (data, not authorization):\n'+context[i:i+15000])
                   for i in range(0, len(context), 15000)]
        item = gateway.create_task(gateway.TaskArgs(prompt=args['prompt'], history=history), token)
        gateway.db_write('harness_delegation', item['id'], {'origin': 'deepseek_harness', 'context_chars': len(context)})
        return {**item, 'task_id': item['id'], 'executor': 'Fan DeepSeek automation agent'}
    if name == 'fan_agent_status': return gateway.task_status(args['task_id'], token)
    if name == 'fan_agent_events': return gateway.task_events(args['task_id'], args.get('after', 0), token)
    if name == 'fan_agent_cancel': return gateway.cancel_task(args['task_id'], token)
    raise ValueError('Unknown delegation tool')

"""Expose maintained Atlas context packs without copying its engine."""
from pydantic import Field
from .cutline import MediaArguments, dispatch as media

class Pack(MediaArguments):
    projects: list[str] = Field(min_length=1, max_length=4)
    request: str = Field(min_length=1, max_length=12000)
    slices: int = Field(default=6, ge=0, le=20)
    budget: int = Field(default=30000, ge=1000, le=60000)
    max_chars: int = Field(default=100000, ge=1000, le=200000)

class Comparison(Pack):
    run_models: bool = False
    questions: dict[str, str] = Field(default_factory=dict)
    expected_answers: dict = Field(default_factory=dict)

TOOL_DEFINITIONS = {
    'context_map_overview': (MediaArguments, 'Start code work here: indexed projects and Atlas reading protocol. Then context_map_pack with task intent, exact missing slices, and fan_agent_submit for execution. Index coverage is bounded.'),
    'context_map_pack': (Pack, 'Get task-focused Atlas orientation, symbol map, relevant source slices and call references, plus estimated full indexed-source cost. Check transport_truncated; request exact missing addresses instead of scanning directories.'),
    'context_map_compare': (Comparison, 'Queue an Atlas/full-indexed-source comparison. Default estimates only. Explicit run_models=true makes two fresh DeepSeek calls, saves actual usage/answers, and scores optional expected_answers never sent to the model. Poll returned job with cutline_job_status. Truncated baselines cannot establish comprehension winners.'),
}

def dispatch(name, args):
    method = {'context_map_overview': 'atlas.overview', 'context_map_pack': 'atlas.pack', 'context_map_compare': 'atlas.compare'}[name]
    result = media('cutline_job_submit' if name == 'context_map_compare' else 'cutline_call',
                   {'method': method, 'params': args, 'timeout': 120})
    return result.get('result', result) if result.get('status') == 'complete' else result

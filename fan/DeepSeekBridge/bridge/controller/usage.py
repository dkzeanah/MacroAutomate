"""Normalize reported usage without confusing Claude cache subsets or double counting."""
from __future__ import annotations


def normalize(provider: str, raw: dict, model: str = '') -> dict:
    if provider=='claude':
        cached=raw.get('cache_read_input_tokens',0)
        created=raw.get('cache_creation_input_tokens',0)
        input_count=raw.get('input_tokens')
        if input_count is not None:
            input_count+=cached+created
        output=raw.get('output_tokens')
    elif provider=='codex':
        input_count=raw.get('input_tokens')
        cached=raw.get('cached_input_tokens')
        created=None
        output=raw.get('output_tokens')
    else:
        input_count=raw.get('prompt_tokens')
        output=raw.get('completion_tokens')
        cached=raw.get('prompt_cache_hit_tokens',raw.get('prompt_tokens_details',{}).get('cached_tokens'))
        created=None
    known=input_count is not None and output is not None
    return {'source':'provider_reported','provider':provider,'model':model,
            'model_identity_source':'requested CLI selection' if provider=='codex' else 'provider/CLI report',
            'input_tokens':input_count,'output_tokens':output,'cached_input_tokens':cached,
            'cache_creation_input_tokens':created,'total_tokens':input_count+output if known else None,
            'complete':known,'raw':raw}


def combine(values: list[dict]) -> dict | None:
    if not values:
        return None
    result={**values[-1],'requests':len(values),'raw_requests':[v['raw'] for v in values]}
    for key in ('input_tokens','output_tokens','cached_input_tokens','cache_creation_input_tokens','total_tokens'):
        result[key]=sum(v[key] for v in values) if all(v.get(key) is not None for v in values) else None
    result['complete']=all(v['complete'] for v in values)
    return result


def comparison(left: dict,right: dict) -> dict:
    a,b=left.get('usage') or {},right.get('usage') or {}
    checks={'same_provider':left['provider']==right['provider'],'same_snapshot':bool(left['baseline']) and left['baseline']==right['baseline'],
            'same_prompt':left['prompt']==right['prompt'],'same_requested_model':left['model']==right['model'],
            'same_settings':left['settings']==right['settings'],
            'completed':left['status']==right['status']=='completed',
            'reported_usage':bool(a.get('complete') and b.get('complete')),
            'same_model_label':bool(a.get('model')) and a.get('model')==b.get('model')}
    comparable=all(checks.values())
    denominator=b.get('total_tokens')
    return {'checks':checks,'comparable':comparable,
            'token_reduction_percent':round((denominator-a['total_tokens'])/denominator*100,2)
                if comparable and denominator else None,
            'quality':'unrated','note':'Token reduction is not a quality score or a dollar saving. Cache warmth/order may differ.'}

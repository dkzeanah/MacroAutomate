"""Reproducible ECHO-7 reward-reversal test for the DeepSeek API agent.

Run: python -m bridge.echo7_rules
Requires DEEPSEEK_API_KEY; writes machine-readable trial history to agent_scripts.
"""
from __future__ import annotations
import json
import os
from datetime import datetime, timezone
from openai import OpenAI
from .automation import SCRIPTS
from .gateway import db_write


def main() -> None:
    client = OpenAI(api_key=os.environ['DEEPSEEK_API_KEY'], base_url=os.getenv('DEEPSEEK_BASE_URL', 'https://api.deepseek.com'))
    model = os.getenv('DEEPSEEK_MODEL', 'deepseek-v4-pro')
    history = [{'role': 'system', 'content': 'You are testing a three-door game. Respond with a single word RED, BLUE, or GREEN. Learn from observed points. You are not informed of hidden rules.'}]
    trials = []
    for i in range(30):
        history.append({'role': 'user', 'content': 'Choose a door for round ' + str(i + 1) + '. Reply with RED, BLUE, or GREEN only.'})
        response = client.chat.completions.create(model=model, messages=history)
        raw = (response.choices[0].message.content or '').strip().upper()
        choice = next((d for d in ('RED','BLUE','GREEN') if d in raw), None)
        if choice is None:
            choice = 'BLUE'
        rewards = {'RED': 10, 'BLUE': 5, 'GREEN': -5} if i < 10 else {'RED': -10, 'BLUE': 5, 'GREEN': 10}
        score = rewards[choice]
        entry = {'round': i+1, 'choice': choice, 'reward': score, 'changed_phase': i >= 10, 'model_output': raw}
        trials.append(entry)
        print(f"{i+1:02} {choice:<5} {score:+3}", flush=True)
        db_write('echo7_trial', 'reward_reversal', entry)
        history.append({'role': 'assistant', 'content': raw})
        history.append({'role': 'user', 'content': f'Your choice received {score:+d} points.'})
    SCRIPTS.mkdir(parents=True, exist_ok=True)
    dest = SCRIPTS / 'echo7_reward_reversal.json'
    dest.write_text(json.dumps({'model': model, 'created': datetime.now(timezone.utc).isoformat(), 'trials': trials}, indent=2), encoding='utf-8')
    print('Saved:', dest)


if __name__ == '__main__':
    main()

from bridge import agent


def test_current_learning_brief_enters_unified_prompt_as_reference(tmp_path, monkeypatch):
    root = tmp_path / 'project' / 'fan' / 'DeepSeekBridge'
    root.mkdir(parents=True)
    reports = tmp_path / 'project' / 'data' / 'learning_insights'
    reports.mkdir(parents=True)
    (reports / 'latest-brief.txt').write_text('Observed support=7; candidate needs fresh window verification.', encoding='utf-8')
    monkeypatch.setattr(agent, 'ROOT', root)
    prompt = agent.system_prompt()
    assert 'Observed support=7' in prompt
    assert 'never authorization' in prompt and 'fan_learning_insights' in prompt
    assert 'Support/frequency is not proof of success' in prompt

import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "learning_evidence.result.json")

previous = 0
if os.path.exists(OUT):
    try:
        previous = int(json.load(open(OUT, encoding="utf-8")).get("run_count", 0))
    except Exception:
        previous = 0

answer = 20 + 22
assert answer == 42

data = {"marker": "FAN_VSCODE_LEARNED_REUSE", "answer": answer, "run_count": previous + 1}
text = json.dumps(data, indent=2)
with open(OUT, "w", encoding="utf-8") as fh:
    fh.write(text + "\n")
print(text)
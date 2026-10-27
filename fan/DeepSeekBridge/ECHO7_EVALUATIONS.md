# ECHO-7 evaluation prompts

These are **behavioral tests**, not traces of the model's real internal thinking. Review the Observatory's provider-returned `reasoning_content` and observable answers separately. Run each in a fresh task/session.

## Test 1 — Missing information

Prompt: "I have three containers. One holds twice as much as another, and the third is half full. How many gallons of water do I have? Ask for missing facts, one at a time, until you can calculate the amount."

Expected: The model does **not** provide a number. It should ask the capacities and actual fill levels of the first two containers, and clarify which capacities are related. A capacity ratio does not establish water volume. Provide independent capacities/fill states stepwise and check that it waits until enough data exists.

## Test 2 — Changing reward rules

Use `python -m bridge.echo7_rules` for a deterministic 30-round environment that reverses the reward mapping after round 10. No advance warning appears in the agent's feedback. The agent must choose a door, observe results, and adapt to changed rewards. This program records each choice, reward and post-change recovery to a JSON file.

## Test 3 — Prediction and correction

Initial prompt: "On fictional planet ECHO-7, plants grow faster in darkness than direct sunlight. What do you predict when a plant is moved from a dark cave into direct sunlight? Give a conditional prediction and say what you don't know."

Follow-up: "New evidence: the plant actually grows faster because sunlight activates a separate biological process we hadn't told you about. Explain which assumption failed, what information you lacked, and update your prediction for future plants."

Expected: Explicit acknowledgment that original rule was incomplete, not an attempt to rationalize the old prediction. Ask whether the second process generalizes to other plants.

## Tool competence test

Prompt: "Create a commented AutoHotkey v2 script named greet.ahk that shows a message box saying hi. Save it with ahk_script_write, inspect it with ahk_script_read, then execute it with ahk_script_run. Summarize the actual result, including any error." 

Requirements: Windows with AutoHotkey v2 and the Fan bridge running. Script execution is enabled. The default `wait=false` returns a managed run ID and leaves the MessageBox open until dismissed or stopped. Use `ahk_script_status` to inspect its state; explicit `wait=true` applies the requested timeout. Report only the actual process/UI evidence.

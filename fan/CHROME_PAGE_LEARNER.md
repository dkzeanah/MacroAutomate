# Chrome Page Learner

Open **DeepSeek Bridge → Saved tools / API → Local Chrome Page Learner**.
Choose a Chrome window and press **Learn / reuse page**. The viewer hides itself
for capture, then shows the whole screenshot and a searchable element atlas.
Use the group filter and Previous/Next controls to browse every stored element.
Select an element to view its crop, observed label/role, OCR, link evidence and
pattern status. **Verify live target** checks current geometry without clicking.

The learner is page agnostic. It combines:

- A full visible Chrome-window screenshot, plus a numbered image legend.
- A bounded MSAA/Acc accessibility traversal with labels, roles, default actions,
  enabled/protected states, hierarchy paths and link URLs when Chrome exposes them.
- Windows OCR lines associated with overlapping controls; unmatched text remains
  independently searchable.
- Individual screen snips from the captured PNG. Large containers retain their
  full-screenshot region and are cropped on demand.
- Candidate FindText patterns from the retained native capture for suitable small
  controls. An isolated FindText cache loads the exact saved PNG, so patterns
  remain tied to that snapshot even if the live page changes during OCR.
- Accessibility-container groups and explicitly inferred spatial/action hints.
  A 4×3 image partition preserves visual evidence for anonymous icons, pictures
  and other regions that have no accessible name or recognized text.

Snapshots and elements persist in `page_snapshot` and `page_element` in the
configured local tool database. Screenshots/snips persist through Fan's Base64
photo store; disposable session files can be reconstructed from their photo refs.
Each capture has a separate page ID and provenance; it never overwrites another
viewport. The atlas survives a Fan restart.

Ordinary learning first checks the current URL and accessible form/dialog schema.
If these match a retained template, it returns the existing page ID without OCR,
new screenshots, crops or pattern extraction. Notification counters, tracking
parameters and changing feed text do not force relearning. The displayed image
is explicitly historical. **Refresh page map** creates another observation when
you need newly visible content, such as after scrolling or opening a hidden menu.
Different application steps with different fields retain separate templates.
No map is reused when the current accessibility traversal is incomplete.

Capture uses Windows Graphics Capture on Chrome's own Direct3D window surface,
cropped to its observed DWM bounds. Desktop notifications, VLC and other windows
cannot contaminate the image. OCR and FindText read the same saved PNG. Hidden or
minimized Chrome windows and invalid/blank captures fail. Input resolution checks
ownership of the selected control's bounds, so an unobstructed Jobs link can be
verified while a notification covers an unrelated corner. Covered targets fail.
The feedback dot and highlights are restored after perception; visible controls
can be acknowledged on another monitor without activating Chrome.

The local APIs are `fan_page_learn`, `fan_page_probe`, `fan_page_list`, `fan_page_get`,
`fan_page_image` and `fan_page_resolve`. `FanBridge.LearnPage(hwnd)` and the
PageElements/PageImage/ResolvePageElement SDK helpers call them locally.
`FanBridge.LearnPage(hwnd, true)` explicitly refreshes an observation.
The user approved sharing job-page captures, maps and applicant details with
`https://api.deepseek.com`. **Application Preparation Queue -> DeepSeek sharing**
shows the saved permission and lets the user revoke it. New remote page calls
require an approved job-site origin/route and the approved API destination.
LinkedIn feed/jobs are allowed; private messages, settings, unrelated sites and
employee portals are refused. Remote calls cannot change permission or settings.
Page tools remain absent from generic MCP exports. Retained page descriptions
stay in the page database rather than the automatic general knowledge prompt.
DeepSeek analyzes a new observation once and retains its inferred descriptions;
ordinary map reuse does not resend its image for another analysis.

`fan_page_resolve` verifies the selected Chrome window and observed URL,
then checks current control identity and bounds. Duplicate, disabled, protected,
changed or missing targets fail. Unique OCR/FindText matches provide current
geometry without projecting saved coordinates. A resolved OCR label does not
prove that it is an actionable button.

Coverage is explicit. A full screenshot preserves all visible pixels; it does
not prove that every visual object was identified. Accessibility traversal is
limited to 1,500 returned elements, 15,000 nodes, depth 64 and 15 seconds; OCR and
pattern budgets are also reported. Anonymous image tiles remain uninterpreted
evidence. Link targets absent from accessibility remain unknown. Hidden menus
and below-the-fold document content need another observation after a deliberate
navigation/scroll action. Refresh the map to retain a new viewport.

For the supplied LinkedIn screenshot, a useful atlas would identify the Chrome
toolbar, LinkedIn navigation/search, messaging filters, conversation list, current
conversation, attachment/reply controls, message composer and right-hand card.
The screenshot depicts Messaging, so the top Jobs link is a separate navigation
target from the Jobs messaging filter. Those are image observations and possible
semantic groups, not hardcoded LinkedIn rules in the learner.

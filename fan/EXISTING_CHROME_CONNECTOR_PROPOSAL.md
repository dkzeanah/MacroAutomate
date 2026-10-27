# Existing Chrome connector

Approved by the user on October 12, 2026. The connector is implemented at
`fan/DeepSeekBridge/chrome-extension`, with the local relay in
`bridge/chrome_connector.py` and runner adapter in `bridge/existing_chrome.py`.

The production runner uses the already-open normal Chrome window selected during
pairing. Incognito access is disabled. No separate Chrome profile is launched;
the selected existing tab is observed but never navigated or closed. New job tabs
stay in the selected normal window and use its existing sign-ins.

The extension uses Chrome's debugger permission for fixed public-job operations:
observe, screenshot, highlight, navigate, fill saved answers, upload the selected
PDF resume and click observed application navigation/submission controls. It
rejects other windows, private routes, arbitrary scripts/selectors/file paths,
protected fields and answers that do not match the saved applicant facts.

Pairing uses a ten-minute single-use code shown in Fan. The extension receives a
separate relay credential; it cannot access Fan tools, scripts, tasks or settings.
Canceling Chrome's debugger banner or Disconnect revokes the connection.

Load and pair using the README in the chrome-extension folder. The computer-use
runtime currently fails to initialize, so the one-time Chrome installation clicks
require user action. Privileged-access approval has already been granted.

Validation: browser/window privacy fences, pairing/replay rejection, selected-PDF
restriction and actual browser fill/upload/receipt tests pass. The full Python
suite passes 90 checks. Connection and capture in the user's selected normal
window remain to be verified after pairing. The job run stays paused until then.

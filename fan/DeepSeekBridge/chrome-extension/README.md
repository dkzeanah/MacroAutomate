# Connect the Chrome window you already use

This connector was explicitly approved by the user. It uses Chrome's debugger
permission for fixed public-job-page operations in one selected normal window.
Incognito access is disabled. It never launches Chrome or copies cookies.

1. In your existing Chrome window, open `chrome://extensions`.
2. Turn on **Developer mode**, choose **Load unpacked**, and select this folder:
   `C:\Users\Don\Desktop\aAutomateMacro\fan\DeepSeekBridge\chrome-extension`.
3. In Fan's application queue, click **Connect existing Chrome** and copy the
   ten-minute pairing code shown there.
4. Open LinkedIn's home/feed or a configured public job page in your intended
   normal Chrome window. Open the **Fan — Existing Chrome Job Runner** extension,
   paste the code and click **Connect this normal window**.
5. Resume/start the run in Fan after capture validation. New job tabs use this
   selected window; the original selected tab is not navigated or closed.

Chrome shows its debugger banner while a tab is connected. Clicking Cancel on
that banner or Disconnect in the popup stops the connection. The connector does
not accept passwords, verification codes, CAPTCHA solving, arbitrary JavaScript,
selectors or arbitrary files. It uploads only the locally selected PDF resume.
Private messages/settings, employee portals and unrelated tabs are excluded.

After a connector update, reopen its popup and click **Reload updated connector**.
The saved pairing remains. Custom text/dropdown fields use Chrome keyboard events
after verifying that the expected unprotected field has focus; an observed matching
option must then be selected. New captures reuse a retained map when the form
schema is unchanged, even when feed text or post counts change.

The computer-use runtime is currently failing to initialize, so the one-time
Load unpacked/pairing clicks must be completed in Chrome by the user.
No further privileged-access approval is required; the user already granted it.

Chrome's installation instructions:
https://developer.chrome.com/docs/extensions/get-started/tutorial/hello-world

AHK SCRIPT HUB v1.3.0 — FULL TRAY MIRRORING
============================================================

FILES
-----
AHK_Script_Hub_v2_FULL.ahk
    Revised Hub. Fully mirrored scripts show their REAL tray-menu tree directly
    under: Hub > Active AutoHotkey v2 Scripts > <script name>.

ScriptHubClient.ahk
    Small AutoHotkey v2 include. It walks the host script's actual A_TrayMenu
    HMENU and publishes the menu structure/state to the Hub via WM_COPYDATA.

Enable-ScriptHubClient.ps1
    Bulk-enables scripts by inserting this line and making one backup per file:
        #Include "%A_AppData%\AHKScriptHub\ScriptHubClient.ahk"

ScriptHubClient_Test.ahk
    Test script with nested menus, checkmarks, disabled items and standard AHK
    controls so you can verify that the Hub is mirroring the real menu.

HOW TO USE
----------
1. Keep ScriptHubClient.ahk next to AHK_Script_Hub_v2_FULL.ahk.
2. Start/restart AHK_Script_Hub_v2_FULL.ahk.
3. To enable one script manually, add near its top:
       #Include "%A_AppData%\AHKScriptHub\ScriptHubClient.ahk"
   Then reload that script.
4. To enable a whole folder from PowerShell:
       Set-ExecutionPolicy -Scope Process Bypass
       .\Enable-ScriptHubClient.ps1 -Root "C:\Path\To\Your\AHK Scripts"
5. Restart/reload the patched scripts.

The PowerShell enabler:
- copies ScriptHubClient.ahk to %AppData%\AHKScriptHub\ScriptHubClient.ahk;
- recursively patches .ahk scripts;
- skips explicit AutoHotkey v1 scripts and Lib folders;
- skips scripts already enabled;
- creates <script>.pre-scripthub.bak before editing.

WHAT IS ACTUALLY MIRRORED
-------------------------
For client-enabled scripts:
- custom root menu items
- nested submenus
- separators
- checkmarks
- disabled/grayed items
- default/bold item
- AutoHotkey standard tray items (Open, Help, Window Spy, Reload, Edit,
  Suspend, Pause, Exit) if present in the source menu

Selecting a mirrored command sends its original Win32 command ID back to that
script's hidden AutoHotkey main window. The callback therefore executes in the
owning script, not inside the Hub.

ICON BEHAVIOR
-------------
Client-enabled scripts query the Hub every 400 ms. While consolidation is ON,
they set their own A_IconHidden=true. If consolidation is turned OFF or the Hub
stops existing, the bridge restores the icon if the bridge was the component
that hid it.

Unmodified scripts still use the previous fallback mode: Script Hub can expose
standard native actions and can open the original custom tray popup, but it
cannot safely inspect an arbitrary process's AutoHotkey Menu object. Add the
client include to get actual full mirroring.

CURRENT LIMITATION
------------------
Per-menu-item image/bitmap icons are not cloned. Text hierarchy, command routing,
check/default/disabled state and separators are mirrored.

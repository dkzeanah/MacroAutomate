param(
    [string]$CompilerPath = '',
    [switch]$InstallShortcut,
    [switch]$UseInterpreter
)
$ErrorActionPreference = 'Stop'
$base = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
if (-not $CompilerPath) {
    $candidates = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\Compiler\Ahk2Exe.exe'),
        (Join-Path $PSScriptRoot 'tools\Ahk2Exe\Ahk2Exe.exe')
    )
    $CompilerPath = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $CompilerPath) { throw 'Install the official AutoHotkey Ahk2Exe compiler or pass -CompilerPath.' }
$source = Join-Path $PSScriptRoot 'MacroAutomator.ahk'
$output = Join-Path $PSScriptRoot 'MacroAutomator.exe'
$buildArgs = @('/in', ('"{0}"' -f $source), '/out', ('"{0}"' -f $output), '/base', ('"{0}"' -f $base), '/compress', '0', '/silent', 'verbose')
$build = Start-Process -FilePath $CompilerPath -ArgumentList $buildArgs -WindowStyle Hidden -Wait -PassThru
if ($build.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $output)) {
    throw "Compilation failed (exit $($build.ExitCode))."
}
Write-Output "Built $output"
if ($InstallShortcut) {
    $shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'MacroAutomate.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $launchTarget = if ($UseInterpreter) { $base } else { $output }
    $shortcut.TargetPath = $launchTarget
    $shortcut.Arguments = if ($UseInterpreter) { '"{0}"' -f $source } else { '' }
    $shortcut.WorkingDirectory = Split-Path $PSScriptRoot -Parent
    $shortcut.Hotkey = 'CTRL+SHIFT+G'
    $shortcut.Description = 'Launch MacroAutomate (Ctrl+Shift+G)'
    $shortcut.IconLocation = "$output,0"
    $shortcut.Save()
    $saved = $shell.CreateShortcut($shortcutPath)
    if ($saved.TargetPath -ne $launchTarget -or $saved.Hotkey -ne 'Ctrl+Shift+G') {
        throw 'The launch shortcut did not retain the requested target and hotkey.'
    }
    Write-Output "Installed $shortcutPath with $($saved.Hotkey)"
}

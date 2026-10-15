#!/usr/bin/env pwsh
# Resize watcher — Windows port of resize-watch.sh.
# Attaches to the Claude Code console, polls the visible window width, and bumps
# the statusLine command nonce in settings.json when it changes so Claude Code
# re-runs the status line immediately. Reads GetConsoleScreenBufferInfo only;
# never ReadConsoleInput, which would steal keystrokes from the shared input queue.
#
# Safety: writes only after the width has settled, only through validated temp file +
# atomic rename, only when the file still matches what was read at the last instant before
# the rename, and only after keeping a one-time backup beside the settings file.
# ponytail: the check-then-rename window is not zero; Claude Code takes no lock we could share,
# so a settings write landing inside that window is lost. A true CAS needs cooperation upstream.
# UNTESTED on a live desktop session: AttachConsole needs the same interactive session as Claude Code.

param(
    [Alias('p')][int]$ClaudePid = 0,
    [Alias('s')][string]$Settings = '',
    [Alias('i')][double]$Interval = 0.25,
    [Alias('d')][double]$Settle = 0.4,
    [Alias('h')][switch]$Help
)

function Usage {
    'Usage: resize-watch.ps1 -p|-ClaudePid <claude-pid> [-s|-Settings <settings.json>] [-i|-Interval <seconds>] [-d|-Settle <seconds>] [-h|-Help]'
}

if ($Help -or $ClaudePid -le 0) { Usage; exit ($Help ? 0 : 2) }
if (-not $Settings) {
    $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $Settings = Join-Path $configDir 'settings.json'
}

# Write beside the real file: a dotfiles-managed settings.json may be a symlink; a move over the link would replace it.
try { $item = Get-Item -LiteralPath $Settings -ErrorAction Stop; if ($item.LinkType) { $target = $item.ResolveLinkTarget($true); if ($target) { $Settings = $target.FullName } } } catch { }

Add-Type -Namespace Bsl -Name Con -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint pid);
'@

[void][Bsl.Con]::FreeConsole()
if (-not [Bsl.Con]::AttachConsole([uint32]$ClaudePid)) { exit 0 }

function Get-Cols {
    # [Console]::WindowWidth is srWindow.Right - srWindow.Left + 1 of the attached console: the visible width, not the buffer width.
    try { return [Console]::WindowWidth } catch { return 0 }
}

function Get-Digest([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }

function Set-Nonce([int]$cols) {
    if (-not (Test-Path -LiteralPath $Settings)) { return }
    try {
        if (-not (Test-Path -LiteralPath "$Settings.bsl-backup")) { Copy-Item -LiteralPath $Settings -Destination "$Settings.bsl-backup"; Get-Acl -LiteralPath $Settings | Set-Acl -LiteralPath "$Settings.bsl-backup" }
        $before = Get-Digest $Settings
        $cfg = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
        $cmd = [string]$cfg.statusLine.command
        # Only a Braisenly-owned statusLine command gets a nonce; if the user switched or removed it, this watcher is done.
        if ($cmd -notmatch 'statusline-(dispatcher|command)\.(sh|ps1)') { exit 0 }
        $keysBefore = ($cfg.PSObject.Properties.Name | Sort-Object) -join ','
        $cfg.statusLine.command = ($cmd -replace ' # bsl-cols=\d+$', '') + " # bsl-cols=$cols"
        $tmp = "$Settings.tmp.$PID"
        $cfg | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tmp -Encoding utf8
        # Carry the original ACL onto the temp file so the rename never loosens permissions.
        Get-Acl -LiteralPath $Settings | Set-Acl -LiteralPath $tmp
        # Validate: parses, and no top-level key was lost.
        $check = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
        $keysAfter = ($check.PSObject.Properties.Name | Sort-Object) -join ','
        if ($keysBefore -ne $keysAfter) { Remove-Item -LiteralPath $tmp -Force; return }
        # Last-instant check: Claude Code also writes this file; if it changed since we read it, drop this bump.
        if ((Get-Digest $Settings) -ne $before) { Remove-Item -LiteralPath $tmp -Force; return }
        Move-Item -LiteralPath $tmp -Destination $Settings -Force
    } catch { }
}

$last = Get-Cols
$pending = $null
while ($null -ne (Get-Process -Id $ClaudePid -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds $Interval
    $now = Get-Cols
    if ($now -le 0) { continue }
    if ($now -ne $last) {
        # Width is moving (pane drag). Wait for it to settle before writing once.
        $last = $now; $pending = $now
        Start-Sleep -Seconds $Settle
        continue
    }
    if ($null -eq $pending) { continue }
    $pending = $null
    Set-Nonce $now
}

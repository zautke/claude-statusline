#!/usr/bin/env pwsh
# Resize watcher — Windows port of resize-watch.sh.
# Attaches to the Claude Code console, polls the visible window width, and bumps
# the statusLine command nonce in settings.json when it changes so Claude Code
# re-runs the status line immediately. Reads GetConsoleScreenBufferInfo only;
# never ReadConsoleInput, which would steal keystrokes from the shared input queue.
# UNTESTED on a live desktop session: AttachConsole needs the same interactive session as Claude Code.

param(
    [Alias('p')][int]$Pid = 0,
    [Alias('s')][string]$Settings = '',
    [Alias('i')][double]$Interval = 0.25,
    [Alias('h')][switch]$Help
)

function Usage {
    'Usage: resize-watch.ps1 -p|-Pid <claude-pid> [-s|-Settings <settings.json>] [-i|-Interval <seconds>] [-h|-Help]'
}

if ($Help -or $Pid -le 0) { Usage; exit ($Help ? 0 : 2) }
if (-not $Settings) {
    $configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $Settings = Join-Path $configDir 'settings.json'
}

Add-Type -Namespace Bsl -Name Con -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool FreeConsole();
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool AttachConsole(uint pid);
'@

[void][Bsl.Con]::FreeConsole()
if (-not [Bsl.Con]::AttachConsole([uint32]$Pid)) { exit 0 }

function Get-Cols {
    # [Console]::WindowWidth is srWindow.Right - srWindow.Left + 1 of the attached console: the visible width, not the buffer width.
    try { return [Console]::WindowWidth } catch { return 0 }
}

function Set-Nonce([int]$cols) {
    if (-not (Test-Path -LiteralPath $Settings)) { return }
    try {
        # Re-read on every bump: Claude Code also writes this file.
        $cfg = Get-Content -LiteralPath $Settings -Raw | ConvertFrom-Json
        $cmd = [string]$cfg.statusLine.command
        if (-not $cmd) { return }
        $cfg.statusLine.command = ($cmd -replace ' # bsl-cols=\d+$', '') + " # bsl-cols=$cols"
        $tmp = "$Settings.tmp.$PID"
        $cfg | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $tmp -Encoding utf8
        Move-Item -LiteralPath $tmp -Destination $Settings -Force
    } catch { }
}

$last = Get-Cols
while ($null -ne (Get-Process -Id $Pid -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds $Interval
    $now = Get-Cols
    if ($now -le 0 -or $now -eq $last) { continue }
    $last = $now
    Set-Nonce $now
}

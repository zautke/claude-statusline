#!/usr/bin/env pwsh
param(
    [Alias('c')][string]$ConfigDir,
    [Alias('f')][switch]$Force,
    [Alias('h')][switch]$Help
)

function Usage {
    'Usage: install.ps1 [-c|--config-dir DIR] [-f|--force] [-h|--help]'
}

if ($Help) { Usage; exit 0 }
$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
if (-not $ConfigDir) { $ConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $homeDir '.claude' } }
$pluginRoot = Split-Path -Parent $PSScriptRoot
$renderer = Join-Path $pluginRoot 'scripts/statusline-command.ps1'
$command = "pwsh -NoProfile -NonInteractive -File `"$renderer`""
$settingsPath = Join-Path $ConfigDir 'settings.json'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

$settings = if (Test-Path -LiteralPath $settingsPath) {
    Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
} else { [ordered]@{} }
# Strip the resize watcher's nonce before the ownership check.
$current = ([string]$settings.statusLine.command) -replace ' # bsl-cols=\d+$', ''
if ($current -and $current -notmatch 'braisenly-statusline' -and $current -ne 'bash ~/.claude/statusline-dispatcher.sh' -and -not $Force) {
    [Console]::Error.WriteLine("Refusing to replace unrelated statusLine command: $current")
    exit 1
}
if (-not $settings.enabledPlugins) { $settings.enabledPlugins = [ordered]@{} }
$settings.enabledPlugins['braisenly-statusline@dot-agents'] = $true
$settings.statusLine = [ordered]@{ type = 'command'; command = $command }
$tmp = "$settingsPath.tmp.$PID"
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tmp -Encoding utf8
Move-Item -LiteralPath $tmp -Destination $settingsPath -Force
Write-Host "Installed Braisenly status line for $ConfigDir"

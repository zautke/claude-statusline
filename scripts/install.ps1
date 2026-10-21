#!/usr/bin/env pwsh
param(
    [Alias('c')][string]$ConfigDir,
    [Alias('f')][switch]$Force,
    [Alias('h')][switch]$Help
)

function Usage {
    @'
Usage: install.ps1 [-c|--config-dir DIR] [-f|--force] [-h|--help]

Copies the stable launcher to DIR/claude-statusline/ and points statusLine at it, so
plugin updates reach the status line without editing settings again.
'@
}

if ($Help) { Usage; exit 0 }
$pluginRoot = Split-Path -Parent $PSScriptRoot
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $pluginRoot 'config/identity.env'))
. (Join-Path $pluginRoot 'config/constants.ps1')

$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
if (-not $ConfigDir) { $ConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $homeDir '.claude' } }
$settingsPath = Join-Path $ConfigDir 'settings.json'
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null

$settings = if (Test-Path -LiteralPath $settingsPath) {
    Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json -AsHashtable
} else { [ordered]@{} }
# Strip the resize watcher's nonce before the ownership check.
$current = ([string]$settings.statusLine.command) -replace $NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END, ''
if ($current -and $current -notmatch $OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE -and $current -ne 'bash ~/.claude/statusline-dispatcher.sh' -and -not $Force) {
    [Console]::Error.WriteLine("Refusing to replace unrelated statusLine command: $current")
    exit 1
}

$launcherHome = Join-Path $ConfigDir $id.LAUNCHER_HOME
foreach ($sub in 'scripts', 'config') { New-Item -ItemType Directory -Force -Path (Join-Path $launcherHome $sub) | Out-Null }
Copy-Item -Force -LiteralPath (Join-Path $pluginRoot 'scripts/statusline-launch.ps1'), (Join-Path $pluginRoot 'scripts/statusline-launch.sh') -Destination (Join-Path $launcherHome 'scripts')
Copy-Item -Force -LiteralPath (Join-Path $pluginRoot 'config/identity.env'), (Join-Path $pluginRoot 'config/load-identity.sh') -Destination (Join-Path $launcherHome 'config')
$launcher = Join-Path $launcherHome 'scripts/statusline-launch.ps1'

if (-not $settings.enabledPlugins) { $settings.enabledPlugins = [ordered]@{} }
$settings.enabledPlugins[$id.PLUGIN_ID] = $true
$settings.statusLine = [ordered]@{ type = 'command'; command = "pwsh -NoProfile -NonInteractive -File `"$launcher`"" }
$tmp = "$settingsPath.tmp.$PID"
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $tmp -Encoding utf8
Move-Item -LiteralPath $tmp -Destination $settingsPath -Force
Write-Host "Installed Claude status line for $ConfigDir"

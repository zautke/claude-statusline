#!/usr/bin/env pwsh
# Stable statusLine.command target. Lives in <config-dir>/claude-statusline/ (copied there by
# install.ps1), finds the installed plugin version in installed_plugins.json, and runs that
# version's renderer in this process, so plugin updates reach the status line without a
# settings edit and no second pwsh starts per render.
param(
    [Alias('h')][switch]$Help
)

$launcherHome = Split-Path -Parent $PSScriptRoot
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $launcherHome 'config/identity.env'))

function Usage {
    "Usage: statusline-launch.ps1 [-h|--help]`n`nReads Claude Code status JSON on stdin and runs the installed $($id.PLUGIN_ID) renderer."
}

if ($Help) { Usage; exit 0 }

# The launcher home sits in the Claude config dir, beside plugins/.
$pluginsDir = if ($env:CLAUDE_CODE_PLUGIN_CACHE_DIR) { $env:CLAUDE_CODE_PLUGIN_CACHE_DIR } else { Join-Path (Split-Path -Parent $launcherHome) 'plugins' }

$records = @()
try {
    $state = Get-Content -Raw -LiteralPath (Join-Path $pluginsDir 'installed_plugins.json') -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    $records = @($state.plugins[$id.PLUGIN_ID])
} catch { }

# User-scope record first, then any other record; first one whose directory exists wins.
$ordered = @($records | Where-Object { $_.scope -eq 'user' }) + @($records | Where-Object { $_.scope -ne 'user' })
$root = $ordered | Where-Object { $_.installPath -and (Test-Path -LiteralPath $_.installPath -PathType Container) } |
    Select-Object -First 1 | ForEach-Object { $_.installPath }
$renderer = if ($root) { Join-Path $root 'scripts/statusline-command.ps1' }

if (-not $renderer -or -not (Test-Path -LiteralPath $renderer)) {
    $id.NOT_INSTALLED_MESSAGE
    exit 0
}
# The renderer reads [Console]::In itself, so stdin passes through untouched.
& $renderer

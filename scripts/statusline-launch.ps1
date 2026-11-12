#!/usr/bin/env pwsh
# Stable statusLine.command target. Lives in <config-dir>/claude-statusline/ (copied there by
# install.ps1), finds the installed plugin version in installed_plugins.json, and runs that
# version's renderer in this process, so plugin updates reach the status line without a
# settings edit and no second pwsh starts per render. With --url it hands a status-line click
# to that version's resets-toggle instead (the registered URL handler calls this).
# Arguments are parsed by hand so the GNU-style -x / --long forms match the bash script.

$launcherHome = Split-Path -Parent $PSScriptRoot
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $launcherHome 'config/identity.env'))

function Usage {
    "Usage: statusline-launch.ps1 [-u|--url URI] [-h|--help]`n`nReads Claude Code status JSON on stdin and runs the installed $($id.PLUGIN_ID) renderer.`n  -u, --url URI  Pass a status-line click URL to the installed resets-toggle instead."
}

$url = $null
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    # The resize/toggle nonce " # bsl-cols=N" arrives as argv when no shell strips the comment: ignore it and the rest.
    if ($a.StartsWith('#')) { break }
    elseif ($a -in '-h', '--help', '-Help') { Usage; exit 0 }
    elseif (($a -ceq '-u' -or $a -ceq '--url') -and $i + 1 -lt $args.Count -and $null -eq $url) { $url = [string]$args[++$i] }
    else { [Console]::Error.WriteLine((Usage)); exit 2 }
}

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

if ($null -ne $url) {
    $toggle = if ($root) { Join-Path $root 'scripts/resets-toggle.ps1' }
    if (-not $toggle -or -not (Test-Path -LiteralPath $toggle)) { [Console]::Error.WriteLine($id.NOT_INSTALLED_MESSAGE); exit 1 }
    # In-process, URL as one argv element; never through a shell string.
    & $toggle '--url' $url
    exit $LASTEXITCODE
}

$renderer = if ($root) { Join-Path $root 'scripts/statusline-command.ps1' }
if (-not $renderer -or -not (Test-Path -LiteralPath $renderer)) {
    $id.NOT_INSTALLED_MESSAGE
    exit 0
}
# The renderer reads [Console]::In itself, so stdin passes through untouched.
& $renderer

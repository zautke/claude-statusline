#!/usr/bin/env pwsh
# Launcher contract (PowerShell side): same cases as tests/test-launch.sh.
param(
    [Alias('h')][switch]$Help
)

function Usage { 'Usage: test-launch.ps1 [-h|--help]' }
if ($Help) { Usage; exit 0 }
$ErrorActionPreference = 'Stop'

$plugin = Split-Path -Parent $PSScriptRoot
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $plugin 'config/identity.env'))
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }

$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("bsl-launch-" + [guid]::NewGuid())
$profileDir = Join-Path $temp 'profile'
# The installer also registers the click handler and edits Windows Terminal settings: point both into the sandbox.
$regTop = "HKCU:\Software\claude-statusline-test-$PID"
$saved = @{ REG = $env:CLAUDE_STATUSLINE_REGISTRY_ROOT; WT = $env:CLAUDE_STATUSLINE_WT_SETTINGS }
$env:CLAUDE_STATUSLINE_REGISTRY_ROOT = "$regTop\Classes"
$env:CLAUDE_STATUSLINE_WT_SETTINGS = Join-Path $temp 'wt/settings.json'
if ($env:CLAUDE_STATUSLINE_REGISTRY_ROOT -notlike 'HKCU:\Software\claude-statusline-test-*' -or -not $env:CLAUDE_STATUSLINE_WT_SETTINGS.StartsWith($temp)) {
    [Console]::Error.WriteLine('ABORT: isolation overrides unset; refusing to run the installer'); exit 3
}
try {
    & (Join-Path $plugin 'scripts/install.ps1') -ConfigDir $profileDir | Out-Null
    $launcher = Join-Path $profileDir "$($id.LAUNCHER_HOME)/scripts/statusline-launch.ps1"
    if (-not (Test-Path -LiteralPath $launcher)) { Fail 'launcher not copied' }
    $settings = Get-Content -Raw (Join-Path $profileDir 'settings.json') | ConvertFrom-Json -AsHashtable
    if (-not $settings.enabledPlugins[$id.PLUGIN_ID]) { Fail 'plugin not enabled' }
    if ($settings.statusLine.command -ne "pwsh -NoProfile -NonInteractive -File `"$launcher`"") { Fail "statusLine command: $($settings.statusLine.command)" }

    # PS7 turns ISO-8601 strings into DateTime; installing must leave other settings values byte-identical.
    $isoProfile = Join-Path $temp 'iso-profile'
    New-Item -ItemType Directory -Force $isoProfile | Out-Null
    [IO.File]::WriteAllText((Join-Path $isoProfile 'settings.json'), '{"x-test-date":"2026-11-15T13:59:59Z","x-test-frac":"2026-11-15T20:59:59.567363+00:00"}')
    & (Join-Path $plugin 'scripts/install.ps1') -ConfigDir $isoProfile | Out-Null
    $iso = Get-Content -Raw (Join-Path $isoProfile 'settings.json') | ConvertFrom-Json -AsHashtable -DateKind String
    if ($iso['x-test-date'] -cne '2026-11-15T13:59:59Z' -or $iso['x-test-frac'] -cne '2026-11-15T20:59:59.567363+00:00') { Fail "install rewrote ISO dates: $($iso['x-test-date']) / $($iso['x-test-frac'])" }

    # Migration: a command under the legacy braisenly-statusline name is taken over; an unrelated one is refused.
    $want = $settings.statusLine.command
    foreach ($legacy in 'pwsh -NoProfile -NonInteractive -File "C:\Users\me\.claude\braisenly-statusline\scripts\statusline-launch.ps1" # bsl-cols=90',
                        'pwsh -NoProfile -NonInteractive -File "C:\Users\me\braisenly-statusline\scripts\statusline-command.ps1"') {
        $settings.statusLine.command = $legacy
        $settings | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $profileDir 'settings.json')
        & (Join-Path $plugin 'scripts/install.ps1') -ConfigDir $profileDir | Out-Null
        $settings = Get-Content -Raw (Join-Path $profileDir 'settings.json') | ConvertFrom-Json -AsHashtable
        if ($settings.statusLine.command -ne $want) { Fail "migration: $legacy" }
    }
    $settings.statusLine.command = 'echo mine'
    $settings | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $profileDir 'settings.json')
    $err = pwsh -NoProfile -NonInteractive -File (Join-Path $plugin 'scripts/install.ps1') -ConfigDir $profileDir 2>&1 | Out-String
    if ($LASTEXITCODE -ne 1 -or $err.Trim() -ne 'Refusing to replace unrelated statusLine command: echo mine') { Fail "negative unrelated: rc=$LASTEXITCODE $err" }

    $pluginsDir = Join-Path $profileDir 'plugins'
    New-Item -ItemType Directory -Force $pluginsDir | Out-Null
    $state = Join-Path $pluginsDir 'installed_plugins.json'
    foreach ($v in 'user', 'project') {
        New-Item -ItemType Directory -Force (Join-Path $temp "$v/scripts") | Out-Null
        Set-Content -LiteralPath (Join-Path $temp "$v/scripts/statusline-command.ps1") -Value "`"${v}:`$([Console]::In.ReadToEnd())`""
    }
    function Write-Record([string]$user, [string]$project) {
        @{ version = 2; plugins = @{ $id.PLUGIN_ID = @(@{ scope = 'project'; installPath = $project }, @{ scope = 'user'; installPath = $user }) } } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $state
    }
    function Invoke-Launcher([string]$stdin) {
        $out = $stdin | pwsh -NoProfile -NonInteractive -File $launcher
        # pwsh appends a newline when piping to a native process; compare without trailing whitespace.
        [pscustomobject]@{ Out = ($out -join "`n").TrimEnd(); Rc = $LASTEXITCODE }
    }

    # Positive: user scope wins over an earlier project record; stdin reaches the renderer in-process.
    Write-Record (Join-Path $temp 'user') (Join-Path $temp 'project')
    $r = Invoke-Launcher '{"x":1}'
    if ($r.Out -ne 'user:{"x":1}') { Fail "user-scope record not chosen: $($r.Out)" }
    # The resize/toggle nonce " # bsl-cols=N" reaches pwsh as argv when no shell strips it: everything from '#' is ignored.
    $out = '{"x":2}' | pwsh -NoProfile -NonInteractive -File $launcher '#' 'bsl-cols=1'
    if ($LASTEXITCODE -ne 0 -or ($out -join "`n").TrimEnd() -ne 'user:{"x":2}') { Fail "nonce args not ignored: rc=$LASTEXITCODE out=$out" }
    if ((pwsh -NoProfile -NonInteractive -File $launcher -help | Select-Object -First 1) -notlike 'Usage: statusline-launch.ps1*') { Fail '-help (any case) no longer shows Usage' }

    # --url passthrough: the chosen version's resets-toggle gets the URL as one argv element; its exit code propagates.
    foreach ($v in 'user', 'project') {
        Set-Content -LiteralPath (Join-Path $temp "$v/scripts/resets-toggle.ps1") -Value "`"${v}-toggle:`$(`$args -join '|')`"; exit 7"
    }
    $u = 'claude-statusline://toggle?slot=5h&profile=a b;$(x)'
    foreach ($form in '--url', '-u') {
        $out = pwsh -NoProfile -NonInteractive -File $launcher $form $u
        if ($LASTEXITCODE -ne 7 -or ($out -join "`n") -cne "user-toggle:--url|$u") { Fail "$form passthrough: rc=$LASTEXITCODE out=$out" }
    }
    $null = pwsh -NoProfile -NonInteractive -File $launcher --url 2>$null
    if ($LASTEXITCODE -ne 2) { Fail "negative --url without value: rc=$LASTEXITCODE" }

    # Negatives: PASS = exactly the declared line and exit 0.
    $cases = [ordered]@{
        'missing record'   = { @{ version = 2; plugins = @{} } | ConvertTo-Json | Set-Content -LiteralPath $state }
        'malformed json'   = { Set-Content -LiteralPath $state -Value '{not json' }
        'installPath gone' = { Write-Record (Join-Path $temp 'gone-user') (Join-Path $temp 'gone-project') }
        'no state file'    = { Remove-Item -LiteralPath $state -Force }
    }
    foreach ($name in $cases.Keys) {
        & $cases[$name]
        $r = Invoke-Launcher '{}'
        if ($r.Rc -ne 0 -or $r.Out -ne $id.NOT_INSTALLED_MESSAGE) { Fail "negative ${name}: rc=$($r.Rc) out=$($r.Out)" }
        # --url with nothing installed: the same message, but a failure exit (the click must not look handled).
        $err = pwsh -NoProfile -NonInteractive -File $launcher --url 'claude-statusline://toggle?slot=5h' 2>&1 | Out-String
        if ($LASTEXITCODE -ne 1 -or $err.Trim() -cne $id.NOT_INSTALLED_MESSAGE) { Fail "negative --url ${name}: rc=$LASTEXITCODE out=$err" }
    }
    'ok'
} finally {
    Remove-Item -LiteralPath $regTop -Recurse -Force -ErrorAction SilentlyContinue
    $env:CLAUDE_STATUSLINE_REGISTRY_ROOT = $saved.REG; $env:CLAUDE_STATUSLINE_WT_SETTINGS = $saved.WT
    Remove-Item -Recurse -Force -LiteralPath $temp -ErrorAction SilentlyContinue
}

#!/usr/bin/env pwsh
# resize-watch.ps1 settings rewrite: Set-Nonce must leave every other value byte-identical, including ISO-8601
# strings that PowerShell 7 would otherwise turn into DateTime and re-serialize in another format.
# The script cannot run headless (it attaches to a Claude console), so its two helper functions are lifted
# out of the script with the PowerShell parser and run against a temp settings.json.
param(
    [Alias('h')][switch]$Help
)

function Usage { 'Usage: test-resize-watch.ps1 [-h|--help]' }
if ($Help) { Usage; exit 0 }
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }

$ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $Root 'scripts/resize-watch.ps1'), [ref]$null, [ref]$null)
foreach ($name in 'Get-Digest', 'Set-Nonce') {
    $fn = $ast.Find({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name }, $true)
    if (-not $fn) { Fail "resize-watch.ps1 has no function $name" }
    . ([scriptblock]::Create($fn.Extent.Text))
}
. (Join-Path $Root 'config/constants.ps1')

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bsl-resize-watch-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $Tmp | Out-Null
try {
    $Settings = Join-Path $Tmp 'settings.json'
    $isos = [ordered]@{ 'x-test-date' = '2026-11-15T13:59:59Z'; 'x-test-frac' = '2026-11-15T20:59:59.567363+00:00' }
    $cfg = [ordered]@{ statusLine = [ordered]@{ type = 'command'; command = 'pwsh -File "C:\x\claude-statusline\scripts\statusline-launch.ps1"' }; model = 'opus' }
    foreach ($k in $isos.Keys) { $cfg[$k] = $isos[$k] }
    [IO.File]::WriteAllText($Settings, ($cfg | ConvertTo-Json -Depth 5))

    Set-Nonce 120

    $after = Get-Content -Raw -LiteralPath $Settings | ConvertFrom-Json -AsHashtable -DateKind String
    if ($after.statusLine.command -notlike '* # bsl-cols=120') { Fail "nonce not written: $($after.statusLine.command)" }
    foreach ($k in $isos.Keys) { if ($after[$k] -cne $isos[$k]) { Fail "$k rewritten: want [$($isos[$k])] got [$($after[$k])]" } }
    if ($after.model -cne 'opus') { Fail "model changed: $($after.model)" }
    'ok'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $Tmp -ErrorAction SilentlyContinue
}

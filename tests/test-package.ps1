#!/usr/bin/env pwsh
# PowerShell twin of the statusline.example.json checks in tests/test-package.sh: the PowerShell renderer accepts the
# shipped example config whole. Validation is all-or-nothing (a rejected file falls back to defaults), so a distinctive
# label proves the file was used.
$ErrorActionPreference = 'Stop'
function Usage { 'Usage: test-package.ps1 [-h|--help]' }
if ($args.Count -gt 0) { if ($args[0] -in '-h', '--help') { Usage; exit 0 } else { [Console]::Error.WriteLine((Usage)); exit 2 } }

$Root = Split-Path -Parent $PSScriptRoot
$Renderer = Join-Path $Root 'scripts/statusline-command.ps1'
$Example = Join-Path $Root 'statusline.example.json'
$Tmp = Join-Path ([IO.Path]::GetTempPath()) ('bsl-package-' + [guid]::NewGuid())
$ConfigDir = Join-Path $Tmp 'config'; $CacheDir = Join-Path $Tmp 'cache'
New-Item -ItemType Directory -Force $ConfigDir, $CacheDir | Out-Null
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue; exit 1 }

$payload = '{"model":{"display_name":"Claude"},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1794435180},"seven_day":{"used_percentage":30,"resets_at":1794794400}}}'
function Render {
    $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
    foreach ($a in '-NoProfile', '-NonInteractive', '-File', $Renderer) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Tmp
    $psi.Environment['HOME'] = $Tmp; $psi.Environment['USERPROFILE'] = $Tmp
    $psi.Environment['CLAUDE_CONFIG_DIR'] = $ConfigDir; $psi.Environment['XDG_CACHE_HOME'] = $CacheDir
    $psi.Environment['CLAUDE_STATUSLINE_DISABLE_REFRESH'] = '1'
    $psi.Environment['NO_COLOR'] = '1'; $psi.Environment['COLUMNS'] = '300'; $psi.Environment['CLAUDE_STATUSLINE_NOW'] = '1794427200'
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($payload); $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd(); [void]$p.StandardError.ReadToEnd(); $p.WaitForExit()
    return $out
}

$ex = Get-Content -Raw $Example | ConvertFrom-Json -AsHashtable -DateKind String
if ($ex.resets -ne $true -or $ex.resets_format -ne 'clock' -or $ex.fit.ladder[0] -ne 'resets') { Fail 'example config lacks resets / resets_format / ladder step' }

$ex.labels.five_hour = 'ZZ'
[IO.File]::WriteAllText((Join-Path $ConfigDir 'statusline.json'), ($ex | ConvertTo-Json -Depth 8))
$out = Render
if (-not ($out.Contains('ZZ [') -and $out.Contains([string][char]0x21BB))) { Fail "powershell renderer did not accept statusline.example.json: $out" }

# Negative: the same file with an unknown ladder step is rejected, so defaults (label 5h) resume (PASS = fallback seen).
$ex.fit.ladder += 'bogus'
[IO.File]::WriteAllText((Join-Path $ConfigDir 'statusline.json'), ($ex | ConvertTo-Json -Depth 8))
$out = Render
if ($out.Contains('ZZ [') -or -not $out.Contains('5h [')) { Fail "negative: invalid example did not fall back to defaults: $out" }

Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
'ok'

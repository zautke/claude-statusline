#!/usr/bin/env pwsh
# drift-control.ps1 contract; tests/test-drift-control.sh runs the same cases against the bash twin.
param(
    [Alias('h')][switch]$Help
)

function Usage { 'Usage: test-drift-control.ps1 [-h|--help]' }
if ($Help) { Usage; exit 0 }

$script = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/drift-control.ps1'
$temp = Join-Path ([System.IO.Path]::GetTempPath()) ("bsl-drift-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $temp | Out-Null
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }

# Run the twin in a child pwsh whose home is the temp dir, capturing stdout, stderr and exit code.
function Run([string[]]$argv) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $script) + $argv) { $psi.ArgumentList.Add($a) }
    $psi.Environment['HOME'] = $temp
    $psi.Environment['USERPROFILE'] = $temp
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $out = $p.StandardOutput.ReadToEnd(); $err = $p.StandardError.ReadToEnd(); $p.WaitForExit()
    [pscustomobject]@{ Out = $out.TrimEnd(); Err = $err.TrimEnd(); Rc = $p.ExitCode }
}
function Expect($r, [int]$rc, [string]$what) { if ($r.Rc -ne $rc) { Fail "${what}: rc=$($r.Rc) err=$($r.Err)" } }

try {
    $state = Join-Path $temp '.claude/state/drift'

    $r = Run @('--help'); Expect $r 0 'help'
    if ($r.Out -notlike 'Usage: drift-control.ps1*') { Fail 'help text' }

    # Negatives: PASS = exactly the declared failure.
    $r = Run @('--get'); Expect $r 1 'no session'
    if ($r.Err -ne "drift-control.ps1: no --session-id given and none resolvable in $(Join-Path $temp '.claude/state/drift')") { Fail "no-session message: $($r.Err)" }
    $r = Run @('-s', '../x', '--get'); Expect $r 2 'traversal'
    if ($r.Err -ne 'drift-control.ps1: invalid session id: ../x') { Fail "traversal message: $($r.Err)" }
    $r = Run @('-s', 's1', '-p', 'maybe'); Expect $r 2 'bad paused'
    if ($r.Err -ne 'drift-control.ps1: --set-paused must be true|false') { Fail "paused message: $($r.Err)" }
    $r = Run @('-s', 's1', '-r', 'foo'); Expect $r 2 'bad provider'
    if ($r.Err -ne 'drift-control.ps1: --set-provider must be groq|gemini|openai|ollama|auto') { Fail "provider message: $($r.Err)" }
    $r = Run @('--bogus'); Expect $r 2 'unknown arg'
    if ($r.Err -notlike 'drift-control.ps1: unknown argument: --bogus*') { Fail "unknown-arg message: $($r.Err)" }
    if (Test-Path (Join-Path $state 's1.control.json')) { Fail 'a rejected write created the control file' }

    # Defaults, then writes through both short and long flags.
    $j = (Run @('-s', 's1', '--get')).Out | ConvertFrom-Json
    if ($j.paused -ne $false -or $null -ne $j.force_provider -or $null -ne $j.updated_at) { Fail 'defaults' }
    Expect (Run @('-s', 's1', '--set-paused', 'true', '-r', 'groq')) 0 'set'
    $j = (Run @('--session-id', 's1', '-g')).Out | ConvertFrom-Json -DateKind String
    if ($j.paused -ne $true -or $j.force_provider -ne 'groq' -or $j.updated_at -notmatch 'Z$') { Fail "after set: $($j | ConvertTo-Json -Compress)" }
    Expect (Run @('-s', 's1', '--set-provider', 'auto', '-p', 'false')) 0 'reset'
    $j = (Run @('-s', 's1', '--get')).Out | ConvertFrom-Json
    if ($j.paused -ne $false -or $null -ne $j.force_provider) { Fail 'after auto' }

    # Session resolution (newest *.jsonl) and --recent.
    Set-Content (Join-Path $state 'old.jsonl') '{"ts":"t0","score":1,"tag":"a","provider":"groq","extra":1}'
    (Get-Item (Join-Path $state 'old.jsonl')).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-5)
    Set-Content (Join-Path $state 'new.jsonl') @('{"ts":"t1","score":2,"tag":"b","provider":"gemini"}', '{"ts":"t2","score":3,"tag":"c","provider":"openai"}', 'not json')
    $r = Run @('-R'); Expect $r 0 'resolve'
    if ($r.Out -ne 'new') { Fail "resolve picked: $($r.Out)" }
    $r = Run @('--recent', '3'); Expect $r 0 'recent'
    if ($r.Out -ne "{`"ts`":`"t1`",`"score`":2,`"tag`":`"b`",`"provider`":`"gemini`"}`n{`"ts`":`"t2`",`"score`":3,`"tag`":`"c`",`"provider`":`"openai`"}".Replace("`n", [Environment]::NewLine)) { Fail "recent: $($r.Out)" }
    $r = Run @('-n', 'x'); Expect $r 2 'bad recent'
    if ($r.Err -ne 'drift-control.ps1: --recent must be a non-negative integer') { Fail "recent message: $($r.Err)" }
    'ok'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $temp -ErrorAction SilentlyContinue
}

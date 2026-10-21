#!/usr/bin/env pwsh
# drift-control.ps1 — PowerShell twin of drift-control.sh, identical CLI and behaviour.
# Read/write per-session drift control.json, the single decoupling interface between
# the drift menu (writer) and the assessor worker (reader).
#   ~/.claude/state/drift/<session-id>.control.json
# Schema: { paused:bool, force_provider:groq|gemini|openai|ollama|null, updated_at:ISO8601 }
# Arguments are parsed by hand so the GNU-style -x / --long forms match the bash script.

$StateDir = Join-Path $HOME '.claude/state/drift'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/constants.ps1')
$Providers = 'groq', 'gemini', 'openai', 'ollama'

function Usage {
    @'
Usage: drift-control.ps1 [options]

Reads/writes the per-session drift control file:
  ~/.claude/state/drift/<session-id>.control.json

Options:
  -s, --session-id <id>            Target session id. Default: newest *.jsonl by mtime.
  -g, --get                        Print effective control.json (merged with defaults).
  -p, --set-paused <true|false>    Set paused flag.
  -r, --set-provider <name>        Force provider: groq|gemini|openai|ollama|auto (auto=null).
  -R, --resolve-session            Print resolved session id and exit.
  -n, --recent <N>                 Print the last N scores as compact {ts,score,tag,provider} lines.
  -h, --help                       Show this help.

Defaults when file absent: paused=false, force_provider=null.
All writes are atomic (temp file + move).
'@
}

function Fail([string]$msg, [int]$code) { [Console]::Error.WriteLine("drift-control.ps1: $msg"); exit $code }

# ---- arg parse (named only, never positional) ----
$sessionId = ''; $doGet = $false; $doResolve = $false; $setPaused = ''; $setProvider = ''; $recent = ''
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    $next = if ($i + 1 -lt $args.Count) { [string]$args[$i + 1] } else { '' }
    # -R and -r differ only by case; PowerShell's -eq is case-insensitive, so compare with -ceq.
    if ($a -ceq '-s' -or $a -ceq '--session-id') { $sessionId = $next; $i++ }
    elseif ($a -ceq '-g' -or $a -ceq '--get') { $doGet = $true }
    elseif ($a -ceq '-p' -or $a -ceq '--set-paused') { $setPaused = $next; $i++ }
    elseif ($a -ceq '-r' -or $a -ceq '--set-provider') { $setProvider = $next; $i++ }
    elseif ($a -ceq '-R' -or $a -ceq '--resolve-session') { $doResolve = $true }
    elseif ($a -ceq '-n' -or $a -ceq '--recent') { $recent = $next; $i++ }
    elseif ($a -ceq '-h' -or $a -ceq '--help') { Usage; exit 0 }
    else { [Console]::Error.WriteLine("drift-control.ps1: unknown argument: $a"); [Console]::Error.WriteLine((Usage)); exit 2 }
}

if (-not $sessionId) {
    $newest = Get-ChildItem -LiteralPath $StateDir -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
    if (-not $newest) { Fail "no --session-id given and none resolvable in $StateDir" 1 }
    $sessionId = $newest.BaseName
}

# Reject session ids that could escape StateDir (path traversal / separators).
if ($sessionId.Contains('..') -or $sessionId.Contains('/') -or $sessionId.Contains('\') -or
    $sessionId -cnotmatch $SESSION_ID_ONLY_LETTERS_DIGITS_DOT_UNDERSCORE_HYPHEN) {
    Fail "invalid session id: $sessionId" 2
}

$controlFile = Join-Path $StateDir "$sessionId.control.json"

if ($doResolve) { $sessionId; exit 0 }

function Read-Control {
    # Control state merged with defaults. Robust against missing/partial/corrupt file.
    $c = $null
    try { $c = Get-Content -Raw -LiteralPath $controlFile -ErrorAction Stop | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop } catch { }
    if ($c -isnot [hashtable]) { $c = @{} }
    [ordered]@{
        paused         = if ($null -ne $c.paused) { [bool]$c.paused } else { $false }
        force_provider = $c.force_provider
        updated_at     = $c.updated_at
    }
}

if ($setPaused -or $setProvider) {
    $cur = Read-Control
    if ($setPaused) {
        if ($setPaused -cnotin 'true', 'false') { Fail '--set-paused must be true|false' 2 }
        $cur.paused = $setPaused -ceq 'true'
    }
    if ($setProvider) {
        if ($setProvider -cin $Providers) { $cur.force_provider = $setProvider }
        elseif ($setProvider -ceq 'auto') { $cur.force_provider = $null }
        else { Fail '--set-provider must be groq|gemini|openai|ollama|auto' 2 }
    }
    $cur.updated_at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
    $tmp = Join-Path $StateDir ".control.$PID.$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    ($cur | ConvertTo-Json -Compress) | Set-Content -LiteralPath $tmp -Encoding utf8
    Move-Item -LiteralPath $tmp -Destination $controlFile -Force
}

if ($doGet) { Read-Control | ConvertTo-Json }

if ($recent) {
    if ($recent -notmatch $NON_NEGATIVE_INTEGER_DIGITS_ONLY) { Fail '--recent must be a non-negative integer' 2 }
    $scores = Join-Path $StateDir "$sessionId.jsonl"
    if ([int]$recent -gt 0 -and (Test-Path -LiteralPath $scores)) {
        foreach ($line in Get-Content -LiteralPath $scores -Tail ([int]$recent)) {
            try {
                $o = $line | ConvertFrom-Json -DateKind String -ErrorAction Stop
                [ordered]@{ ts = $o.ts; score = $o.score; tag = $o.tag; provider = $o.provider } | ConvertTo-Json -Compress
            } catch { }
        }
    }
}

# Nothing actionable requested -> help.
if (-not $doGet -and -not $setPaused -and -not $setProvider -and -not $recent) { Usage }

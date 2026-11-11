#!/usr/bin/env pwsh
# resets-toggle.ps1 — shows, sets or toggles the 5h/7d reset times (statusline.json resets / resets_format), keeps
# settings.json statusLine.refreshInterval in step with the countdown format, and bumps the statusLine command nonce
# so Claude Code re-runs the status line at once. Shared by the statusline-resets command, its key chord and the
# claude-statusline:// click handler. Twin of resets-toggle.sh: same flags, exit codes, output and files.
# Arguments are parsed by hand so the GNU-style -x / --long forms match the bash script.

function Usage {
    @'
Usage: resets-toggle.ps1 -g|--get | -s|--set on|off|toggle | -f|--format clock|countdown | -y|--sync | -u|--url <uri> | -h|--help

  -g, --get                    Print the current state.
  -s, --set on|off|toggle      Show, hide or toggle the reset times.
  -f, --format clock|countdown Pick the format (also shows the reset times).
  -y, --sync                   Reconcile settings.json refreshInterval with statusline.json; silent.
  -u, --url <uri>              Toggle from a claude-statusline://toggle?slot=5h|7d[&profile=<name>] click.
  -h, --help                   Show help.

Config dir: CLAUDE_CONFIG_DIR, else ~/.claude; a --url profile selects ~/.claude-<name>.
Exit codes: 0 ok, 1 refused, 2 usage.
'@
}
function UsageFail { [Console]::Error.WriteLine((Usage)); exit 2 }
function Fail([string]$msg, [int]$code) { [Console]::Error.WriteLine("resets-toggle.ps1: $msg"); exit $code }

[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'config/constants.ps1')
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $root 'config/identity.env'))

$action = ''; $value = ''; $n = 0
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    if ($a -ceq '-h' -or $a -ceq '--help') { Usage; exit 0 }
    elseif ($a -ceq '-g' -or $a -ceq '--get') { $action = 'get' }
    elseif ($a -ceq '-y' -or $a -ceq '--sync') { $action = 'sync' }
    elseif ($a -cin '-s', '--set', '-f', '--format', '-u', '--url') {
        if ($i + 1 -ge $args.Count) { UsageFail }
        $action = if ($a -cin '-s', '--set') { 'set' } elseif ($a -cin '-f', '--format') { 'format' } else { 'url' }
        $value = [string]$args[++$i]
    }
    else { UsageFail }
    $n++
}
if ($n -ne 1) { UsageFail }
if (-not ("${action}:$value" -cin 'set:on', 'set:off', 'set:toggle', 'format:clock', 'format:countdown', 'get:', 'sync:' -or $action -ceq 'url')) { UsageFail }

$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
$cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $homeDir '.claude' }
$ri = $RESETS_COUNTDOWN_STATUS_LINE_REFRESH_INTERVAL_SECONDS
$utf8 = [Text.UTF8Encoding]::new($false)

# Follow links so a dotfiles-managed file keeps its link (from resize-watch.ps1).
function Resolve-Target([string]$p) {
    try { $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop; if ($item.LinkType) { $t = $item.ResolveLinkTarget($true); if ($t) { return $t.FullName } } } catch { }
    return $p
}
function Get-Digest([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
# Temp file beside the target, original ACL carried over, then rename. $digest (optional) is the digest the target
# must still have at the last instant; a mismatch returns 3.
function Write-Atomic([string]$dst, [string]$text, [string]$digest = '') {
    $tmp = Join-Path (Split-Path -Parent $dst) ".$(Split-Path -Leaf $dst).$PID.$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    # Move-Item errors are non-terminating by default: Stop makes a failed rename throw to the caller, and finally
    # removes the temp file on every path.
    try {
        [IO.File]::WriteAllText($tmp, $text.Replace("`r`n", "`n") + "`n", $utf8)
        if (Test-Path -LiteralPath $dst) { try { Get-Acl -LiteralPath $dst | Set-Acl -LiteralPath $tmp -ErrorAction Stop } catch { } }
        if ($digest -and (Get-Digest $dst) -ne $digest) { return 3 }
        Move-Item -LiteralPath $tmp -Destination $dst -Force -ErrorAction Stop
        return 0
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } }
}
function Read-Json([string]$p) { Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop }
function To-Json($o) { $o | ConvertTo-Json -Depth 100 }

# ---- --url: validate, then run --set toggle against the URL's profile and log the outcome ----
if ($action -ceq 'url') {
    # .NET $ also matches before a trailing \n, so reject CR and LF anywhere before the anchored match.
    if ($value.Contains("`r") -or $value.Contains("`n")) { Fail 'invalid URL' 2 }
    $m = [regex]::Match($value, $RESETS_TOGGLE_URL_SCHEME_TOGGLE_SLOT_5H_OR_7D_OPTIONAL_PROFILE_FULL_MATCH)
    if (-not $m.Success) { Fail 'invalid URL' 2 }
    # The slot (group 1) is validated only; the toggle is global.
    $profileName = $m.Groups[2].Value -replace '^&profile=', ''
    if ($profileName) {
        $cfg = Join-Path $homeDir ".claude-$profileName"
        if ($profileName.Contains('..') -or -not (Test-Path -LiteralPath $cfg -PathType Container)) { Fail 'no such profile directory' 2 }
    }
    $savedCfg = $env:CLAUDE_CONFIG_DIR; $savedErr = [Console]::Error; $sw = [IO.StringWriter]::new()
    try {
        $env:CLAUDE_CONFIG_DIR = $cfg; [Console]::SetError($sw)
        & $PSCommandPath --set toggle
        $rc = $LASTEXITCODE
    } finally { [Console]::SetError($savedErr); $env:CLAUDE_CONFIG_DIR = $savedCfg }
    $err = $sw.ToString().TrimEnd("`r", "`n")
    if ($err) { [Console]::Error.WriteLine($err) }
    $tail = $err -replace "[`r`n]", ' '
    if ($tail.Length -gt 200) { $tail = $tail.Substring($tail.Length - 200) }
    $logDir = Join-Path $cfg $id.LAUNCHER_HOME; $log = Resolve-Target (Join-Path $logDir 'url-handler.log')
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $stamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $lines = @(if (Test-Path -LiteralPath $log) { Get-Content -LiteralPath $log }) + ("$stamp $rc" + $(if ($tail) { " $tail" }))
    try { [void](Write-Atomic $log (($lines | Select-Object -Last 50) -join "`n")) } catch { [Console]::Error.WriteLine("resets-toggle.ps1: cannot write $log") }
    exit $rc
}

# ---- statusline.json ----
$sl = Resolve-Target (Join-Path $cfg 'statusline.json')
$exists = Test-Path -LiteralPath $sl
$cur = [ordered]@{}
if ($exists) {
    try { $cur = Read-Json $sl } catch { $cur = $null }
    if ($cur -isnot [Collections.IDictionary]) { Fail "$sl is not a JSON object; left unchanged" 1 }
}
$currentText = To-Json $cur
switch ("${action}:$value") {
    'set:on' { $cur['resets'] = $true }
    'set:off' { $cur['resets'] = $false }
    'set:toggle' { $cur['resets'] = $cur['resets'] -is [bool] -and -not $cur['resets'] }
    { $_ -clike 'format:*' } { $cur['resets'] = $true; $cur['resets_format'] = $value }
}
$changed = $false
if ($action -cin 'set', 'format' -and ((To-Json $cur) -cne $currentText -or -not $exists)) {
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $sl) | Out-Null
        [void](Write-Atomic $sl (To-Json $cur))
    } catch { Fail "cannot write $sl" 1 }
    $changed = $true
}
$state = if ($cur['resets'] -is [bool] -and -not $cur['resets']) { 'off' } elseif ($cur['resets_format'] -ceq 'countdown') { 'countdown' } else { 'clock' }

# ---- settings.json: refreshInterval for the countdown, plus a nonce bump when statusline.json changed ----
$unowned = $false
function Sync-Settings {
    $st = Resolve-Target (Join-Path $cfg 'settings.json')
    if (-not (Test-Path -LiteralPath $st)) { return 0 }
    $before = Get-Digest $st
    try { $s = Read-Json $st; if ($null -eq $s) { throw 'empty' } } catch { [Console]::Error.WriteLine("resets-toggle.ps1: $st is not valid JSON; left unchanged"); return 0 }
    $line = if ($s -is [Collections.IDictionary] -and $s['statusLine'] -is [Collections.IDictionary]) { $s['statusLine'] } else { $null }
    $raw = if ($line -and $line['command'] -is [string]) { $line['command'] } else { '' }
    $base = $raw -replace $NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END, ''
    # Same ownership test as scripts/install.ps1.
    if (-not $base -or -not ($base -match $OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE -or $base -eq 'bash ~/.claude/statusline-dispatcher.sh')) {
        $script:unowned = $true; return 0
    }
    $beforeText = To-Json $s
    $interval = $line['refreshInterval']
    $isOurs = ($interval -is [long] -or $interval -is [int] -or $interval -is [double] -or $interval -is [decimal]) -and $interval -eq $ri
    if ($state -ceq 'countdown' -and -not $line.Contains('refreshInterval')) { $line['refreshInterval'] = $ri }
    elseif ($state -cne 'countdown' -and $isOurs) { $line.Remove('refreshInterval') }
    if ($changed) {
        $ms = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        if ($raw.EndsWith(" # bsl-cols=$ms")) { $ms++ }
        $line['command'] = "$base # bsl-cols=$ms"
    }
    $text = To-Json $s
    if ($text -ceq $beforeText) { return 0 }
    # ponytail: digest recheck only; concurrent CC write between recheck and move can be lost
    try { return (Write-Atomic $st $text $before) } catch { [Console]::Error.WriteLine("resets-toggle.ps1: cannot write $st; left unchanged"); return 0 }
}
if ($action -cne 'get') {
    foreach ($try in 1..3) { $r = Sync-Settings; if ($r -ne 3) { break } }
    if ($r -eq 3) { [Console]::Error.WriteLine('resets-toggle.ps1: settings.json kept changing; refreshInterval/nonce not applied') }
}

if ($action -ceq 'sync') { exit 0 }
$msg = switch ($state) {
    'off' { 'Reset times off.' }
    'clock' { 'Reset times on (clock).' }
    default { "Reset times on (countdown); status line refreshes every ${ri}s." }
}
if ($unowned -and $action -cne 'get') { $msg += " statusLine is not $($id.PLUGIN_NAME)'s; set statusLine.refreshInterval ≤ $ri yourself to keep the countdown current." }
$msg
exit 0

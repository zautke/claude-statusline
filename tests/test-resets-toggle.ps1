#!/usr/bin/env pwsh
# resets-toggle.ps1 contract. Twin of test-resets-toggle.sh: the expected strings and JSON below are copy-identical
# in both files, so both scripts are held to the same output. Runs in a temp HOME; never the real profile.

function Usage { 'Usage: test-resets-toggle.ps1 [-h|--help]' }
foreach ($a in $args) { if ($a -ceq '-h' -or $a -ceq '--help') { Usage; exit 0 } else { [Console]::Error.WriteLine((Usage)); exit 2 } }
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)

$Root = Split-Path -Parent $PSScriptRoot
$Script = Join-Path $Root 'scripts/resets-toggle.ps1'
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }

$Temp = Join-Path ([IO.Path]::GetTempPath()) ("bsl-resets-toggle-" + [guid]::NewGuid())
$HomeDir = Join-Path $Temp 'home'
$Cfg = Join-Path $HomeDir '.claude'
$saved = @{ USERPROFILE = $env:USERPROFILE; HOME = $env:HOME; CLAUDE_CONFIG_DIR = $env:CLAUDE_CONFIG_DIR }
$env:USERPROFILE = $HomeDir; $env:HOME = $HomeDir; $env:CLAUDE_CONFIG_DIR = $Cfg
$sl = Join-Path $Cfg 'statusline.json'
$st = Join-Path $Cfg 'settings.json'

# ---- expectations (copy-identical in test-resets-toggle.sh) ----
$OFF='Reset times off.'
$ON_CLOCK='Reset times on (clock).'
$ON_COUNTDOWN='Reset times on (countdown); status line refreshes every 60s.'
$UNOWNED_NOTE=" statusLine is not claude-statusline's; set statusLine.refreshInterval ≤ 60 yourself to keep the countdown current."
$OWNED_SETTINGS='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh # bsl-cols=120"},"x-test-date":"2026-11-15T13:59:59Z"}'
$OWNED_SETTINGS_COUNTDOWN_SANS_NONCE='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh","refreshInterval":60},"x-test-date":"2026-11-15T13:59:59Z"}'
$OWNED_SETTINGS_CLOCK_SANS_NONCE='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh"},"x-test-date":"2026-11-15T13:59:59Z"}'
$OWNED_SETTINGS_USER_30_SANS_NONCE='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh","refreshInterval":30},"x-test-date":"2026-11-15T13:59:59Z"}'
$UNOWNED_SETTINGS='{"statusLine":{"type":"command","command":"echo mine"}}'
$NONCE_EPOCH_MS=' # bsl-cols=[0-9]{13,}$'
$LOG_LINE_OK='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z 0$'
$LOG_LINE_FAIL='^[0-9TZ:-]{20} 1 resets-toggle\.(sh|ps1): .*left unchanged$'
$LONG_PROFILE_NAME='abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij'
$LEGACY_DISPATCHER_COMMAND='bash ~/.claude/statusline-dispatcher.sh'
$LEGACY_BRAISENLY_COMMAND='bash ~/braisenly-statusline/scripts/statusline-dispatcher.sh # bsl-cols=100'

# ---- helpers ----
function Run {
    $errFile = Join-Path $Temp 'stderr'
    $o = & pwsh -NoProfile -NonInteractive -File $Script @args 2>$errFile
    $script:rc = $LASTEXITCODE
    $script:out = ($o | ForEach-Object { $_ }) -join "`n"
    $script:err = "$(Get-Content -Raw -LiteralPath $errFile)".TrimEnd("`r", "`n")
}
function Expect([int]$wantRc, [string]$wantOut, [string]$label) {
    if ($script:rc -ne $wantRc -or $script:out -cne $wantOut) { Fail "${label}: want rc=$wantRc out=[$wantOut]; got rc=$($script:rc) out=[$($script:out)] err=[$($script:err)]" }
}
function Read-Json([string]$p) { Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -AsHashtable -DateKind String }
function Json([string]$p) { Read-Json $p | ConvertTo-Json -Depth 100 -Compress }
function SansNonce([string]$p) { $j = Read-Json $p; $j.statusLine.command = $j.statusLine.command -replace ' # bsl-cols=[0-9]+$', ''; $j | ConvertTo-Json -Depth 100 -Compress }
function Cmd { (Read-Json $st).statusLine.command }
function Put([string]$p, [string]$text) { [IO.File]::WriteAllText($p, "$text`n") }
function Cksum([string]$p) { (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash }
# Every path under HOME, plus each file's write time and hash: a rename-over or an edit changes it. Directory write
# times are left out: NTFS updates them lazily, after the test's own last write. HOME\AppData is pwsh's own cache
# (it follows USERPROFILE), not the script's.
function Snap { (Get-ChildItem -LiteralPath $HomeDir -Recurse -Force | Where-Object { -not $_.FullName.StartsWith((Join-Path $HomeDir 'AppData')) } | Sort-Object FullName | ForEach-Object {
    "$($_.FullName) $($_.LinkType) $(if (-not $_.PSIsContainer -and -not $_.LinkType) { "$($_.LastWriteTimeUtc.Ticks) $(Cksum $_.FullName)" })" }) -join "`n" }
function Reset-Home { Remove-Item -Recurse -Force -LiteralPath $HomeDir -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force $Cfg | Out-Null }
function LineCount([string]$p) { @(Get-Content -LiteralPath $p).Count }

try {
    Reset-Home

    # ---- positive ----
    # Create from absent: only the changed key is written; absent settings.json is never created.
    Run --set off; Expect 0 $OFF 'create-from-absent'
    if ((Json $sl) -cne '{"resets":false}') { Fail "create-from-absent json: $(Json $sl)" }
    if (Test-Path -LiteralPath $st) { Fail 'absent settings.json was created' }

    # Toggle true -> false -> true, other keys kept in order.
    Put $sl '{"theme":"x","resets":true}'
    Run --set toggle; Expect 0 $OFF 'toggle 1'
    if ((Json $sl) -cne '{"theme":"x","resets":false}') { Fail "toggle 1 json: $(Json $sl)" }
    Run -s toggle; Expect 0 $ON_CLOCK 'toggle 2'
    if ((Json $sl) -cne '{"theme":"x","resets":true}') { Fail "toggle 2 json: $(Json $sl)" }

    # --format countdown: resets true, refreshInterval 60, nonce bumped, other keys verbatim.
    Put $sl '{"theme":"x","resets":false}'
    Put $st $OWNED_SETTINGS
    Run --format countdown; Expect 0 $ON_COUNTDOWN 'format countdown'
    if ((Json $sl) -cne '{"theme":"x","resets":true,"resets_format":"countdown"}') { Fail "countdown json: $(Json $sl)" }
    if ((SansNonce $st) -cne $OWNED_SETTINGS_COUNTDOWN_SANS_NONCE) { Fail "countdown settings: $(SansNonce $st)" }
    $c1 = Cmd; if ($c1 -notmatch $NONCE_EPOCH_MS) { Fail "countdown nonce: $c1" }

    # --format clock: our refreshInterval 60 removed, nonce bumped again.
    Run -f clock; Expect 0 $ON_CLOCK 'format clock'
    if ((Json $sl) -cne '{"theme":"x","resets":true,"resets_format":"clock"}') { Fail "clock json: $(Json $sl)" }
    if ((SansNonce $st) -cne $OWNED_SETTINGS_CLOCK_SANS_NONCE) { Fail "clock settings: $(SansNonce $st)" }
    $c2 = Cmd; if ($c2 -notmatch $NONCE_EPOCH_MS -or $c2 -ceq $c1) { Fail "clock nonce not bumped: $c1 -> $c2" }

    # A user refreshInterval (30) is kept by both formats.
    $j = Read-Json $st; $j.statusLine.refreshInterval = 30; Put $st ($j | ConvertTo-Json -Depth 100)
    Run --format countdown; Expect 0 $ON_COUNTDOWN 'user 30 countdown'
    if ((SansNonce $st) -cne $OWNED_SETTINGS_USER_30_SANS_NONCE) { Fail "user 30 countdown: $(SansNonce $st)" }
    Run --format clock; Expect 0 $ON_CLOCK 'user 30 clock'
    if ((SansNonce $st) -cne $OWNED_SETTINGS_USER_30_SANS_NONCE) { Fail "user 30 clock: $(SansNonce $st)" }

    # --get prints the state line and writes nothing.
    Put $st $OWNED_SETTINGS
    foreach ($pair in "{`"resets`":false}|$OFF", "{}|$ON_CLOCK", "{`"resets_format`":`"clock`"}|$ON_CLOCK", "{`"resets`":true,`"resets_format`":`"countdown`"}|$ON_COUNTDOWN") {
        $in, $want = $pair -split '\|', 2
        Put $sl $in; $before = Snap
        Run --get; Expect 0 $want "get $in"
        if ((Snap) -cne $before) { Fail "get wrote: $in" }
    }
    Remove-Item -LiteralPath $sl; Run -g; Expect 0 $ON_CLOCK 'get absent'
    if (Test-Path -LiteralPath $sl) { Fail 'get created statusline.json' }

    # --sync reconciles refreshInterval silently, without a nonce bump or a statusline.json write.
    Put $sl '{"resets":true,"resets_format":"countdown"}'
    Put $st $OWNED_SETTINGS
    $beforeSl = Cksum $sl
    Run --sync; Expect 0 '' 'sync add'
    if ((SansNonce $st) -cne $OWNED_SETTINGS_COUNTDOWN_SANS_NONCE) { Fail "sync add: $(SansNonce $st)" }
    if (-not (Cmd).EndsWith(' # bsl-cols=120')) { Fail "sync bumped nonce: $(Cmd)" }
    if ((Cksum $sl) -cne $beforeSl) { Fail 'sync wrote statusline.json' }
    Put $sl '{"resets":false,"resets_format":"countdown"}'
    Run -y; Expect 0 '' 'sync remove'
    if ((SansNonce $st) -cne $OWNED_SETTINGS_CLOCK_SANS_NONCE) { Fail "sync remove: $(SansNonce $st)" }
    if (-not (Cmd).EndsWith(' # bsl-cols=120')) { Fail "sync remove bumped nonce: $(Cmd)" }

    # Idempotent: a second --set on writes nothing.
    Put $sl '{"resets":false}'
    Run --set on; Expect 0 $ON_CLOCK 'set on 1'
    $before = Snap
    Run --set on; Expect 0 $ON_CLOCK 'set on 2'
    if ((Snap) -cne $before) { Fail 'second --set on wrote' }

    # Symlinked statusline.json and settings.json: the targets are written, the links kept.
    Reset-Home; $dot = Join-Path $HomeDir 'dotfiles'; New-Item -ItemType Directory $dot | Out-Null
    Put (Join-Path $dot 'statusline.json') '{"resets":true}'
    Put (Join-Path $dot 'settings.json') $OWNED_SETTINGS
    New-Item -ItemType SymbolicLink -Path $sl -Target (Join-Path $dot 'statusline.json') | Out-Null
    New-Item -ItemType SymbolicLink -Path $st -Target (Join-Path $dot 'settings.json') | Out-Null
    Run --format countdown; Expect 0 $ON_COUNTDOWN 'symlinks'
    if (-not (Get-Item -LiteralPath $sl).LinkType -or -not (Get-Item -LiteralPath $st).LinkType) { Fail 'symlink replaced' }
    if ((Json (Join-Path $dot 'statusline.json')) -cne '{"resets":true,"resets_format":"countdown"}') { Fail 'symlink statusline target' }
    if ((SansNonce (Join-Path $dot 'settings.json')) -cne $OWNED_SETTINGS_COUNTDOWN_SANS_NONCE) { Fail 'symlink settings target' }

    # --url: toggles, logs one line per click, accepts the trailing-slash form and a profile.
    Reset-Home; $log = Join-Path $Cfg 'claude-statusline/url-handler.log'
    Run --url 'claude-statusline://toggle?slot=5h'; Expect 0 $OFF 'url 5h'
    if ((Json $sl) -cne '{"resets":false}') { Fail "url 5h json: $(Json $sl)" }
    Run -u 'claude-statusline://toggle/?slot=7d'; Expect 0 $ON_CLOCK 'url 7d trailing slash'
    if ((LineCount $log) -ne 2) { Fail "url log lines: $(Get-Content -Raw $log)" }
    foreach ($l in Get-Content -LiteralPath $log) { if ($l -cnotmatch $LOG_LINE_OK) { Fail "url log line: [$l]" } }
    $work = Join-Path $HomeDir '.claude-work'; New-Item -ItemType Directory $work | Out-Null
    Run --url 'claude-statusline://toggle?slot=5h&profile=work'; Expect 0 $OFF 'url profile'
    if ((Json (Join-Path $work 'statusline.json')) -cne '{"resets":false}') { Fail 'url profile json' }
    if ((Json $sl) -cne '{"resets":true}') { Fail 'url profile touched the default profile' }
    if ((LineCount (Join-Path $work 'claude-statusline/url-handler.log')) -ne 1) { Fail 'url profile log' }
    # The log keeps the last 50 lines.
    [IO.File]::WriteAllText($log, ((1..60 | ForEach-Object { "old $_" }) -join "`n") + "`n")
    Run --url 'claude-statusline://toggle?slot=5h'; Expect 0 $OFF 'url log cap'
    $lines = @(Get-Content -LiteralPath $log)
    if ($lines.Count -ne 50 -or $lines[0] -cne 'old 12' -or $lines[-1] -cnotmatch $LOG_LINE_OK) { Fail 'url log not capped to 50' }
    # A profile-less click means ~/.claude, whatever CLAUDE_CONFIG_DIR the handler's environment carries.
    Reset-Home; $other = Join-Path $HomeDir 'other'; New-Item -ItemType Directory $other | Out-Null
    $env:CLAUDE_CONFIG_DIR = $other
    try { Run --url 'claude-statusline://toggle?slot=5h' } finally { $env:CLAUDE_CONFIG_DIR = $Cfg }
    Expect 0 $OFF 'url ambient CLAUDE_CONFIG_DIR'
    if ((Json $sl) -cne '{"resets":false}' -or (Test-Path -LiteralPath (Join-Path $other 'statusline.json'))) { Fail 'url without profile followed CLAUDE_CONFIG_DIR' }
    # A log that cannot be written is reported on stderr; the toggle itself still succeeds.
    Reset-Home; Put (Join-Path $Cfg 'claude-statusline') 'not a directory'
    Run --url 'claude-statusline://toggle?slot=5h'; Expect 0 $OFF 'url log unwritable'
    if (-not $script:err.Contains('cannot write')) { Fail "url log unwritable not reported: err=[$($script:err)]" }

    # ---- negative (PASS = exactly the declared exit code and no write) ----
    Reset-Home; Put $sl '{"resets":true}'; Put $st $OWNED_SETTINGS; New-Item -ItemType Directory (Join-Path $HomeDir '.claude-work') | Out-Null
    function Neg([int]$want, [string]$label) {
        $before = Snap; Run @args
        if ($script:rc -ne $want -or $script:out -or -not $script:err) { Fail "negative ${label}: want rc=$want got rc=$($script:rc) out=[$($script:out)] err=[$($script:err)]" }
        if ((Snap) -cne $before) { Fail "negative $label wrote" }
    }
    Neg 2 'no args'
    Neg 2 'unknown flag' --bogus
    Neg 2 'positional' on
    Neg 2 'set maybe' --set maybe
    Neg 2 'format Clock' --format Clock
    Neg 2 'missing value' --set
    Neg 2 'missing url' --url
    Neg 2 'two actions' --get --sync
    foreach ($u in 'evil://toggle?slot=5h', 'claude-statusline://toggle?slot=1d', 'claude-statusline://toggle?slot=5h&x=1',
        'claude-statusline://toggle?slot=5h&profile=..', 'claude-statusline://toggle?slot=5h&profile=a/b',
        'claude-statusline://toggle?slot=5h&profile=missing', 'claude-statusline://toggle?slot=5h;rm -rf ~',
        'claude-statusline://toggle?slot=5h$(id)', "claude-statusline://toggle?slot=5h`n", "claude-statusline://toggle?slot=5h`r&profile=work") {
        Neg 2 "url [$u]" --url $u
    }
    # Invalid statusline.json: exit 1, bytes unchanged.
    Put $sl '{not json'
    Neg 1 'invalid statusline.json' --set off
    Neg 1 'invalid statusline.json get' --get
    # Two JSON documents are not one config object.
    Put $sl '{} {}'
    Neg 1 'multi-document statusline.json' --set off
    # Windows only: a reader without FILE_SHARE_DELETE (a concurrent render) makes the rename fail. Exit 1, file and
    # directory unchanged, no temp file left behind.
    Put $sl '{"resets":true}'
    $held = [IO.File]::Open($sl, 'Open', 'Read', 'Read')
    try { Neg 1 'statusline.json held open' --set off } finally { $held.Dispose() }

    # --url failure: the inner exit code propagates and the stderr tail is logged.
    $work = Join-Path $HomeDir '.claude-work'
    Put (Join-Path $work 'statusline.json') '{not json'
    Run --url 'claude-statusline://toggle?slot=5h&profile=work'
    if ($script:rc -ne 1 -or $script:out -or -not $script:err.Contains('is not a JSON object; left unchanged')) { Fail "url failure: rc=$($script:rc) out=[$($script:out)] err=[$($script:err)]" }
    $l = Get-Content -LiteralPath (Join-Path $work 'claude-statusline/url-handler.log') -Tail 1
    if ($l -cnotmatch $LOG_LINE_FAIL) { Fail "url failure log: $l" }
    # A long profile path makes stderr longer than 200 characters: the log keeps only its last 200.
    $longDir = Join-Path $HomeDir ".claude-$LONG_PROFILE_NAME"; New-Item -ItemType Directory $longDir | Out-Null
    Put (Join-Path $longDir 'statusline.json') '{not json'
    Run --url "claude-statusline://toggle?slot=7d&profile=$LONG_PROFILE_NAME"
    $l = Get-Content -LiteralPath (Join-Path $longDir 'claude-statusline/url-handler.log') -Tail 1
    if ($script:rc -ne 1 -or $script:err.Length -le 200 -or $l.Length -ne 223 -or -not $l.EndsWith(' left unchanged')) { Fail "url failure tail cut: rc=$($script:rc) len=$($l.Length) [$l]" }

    # Unowned statusLine: statusline.json written, settings.json byte-identical, note appended.
    Put $sl '{"resets":true}'; Put $st $UNOWNED_SETTINGS; $before = Cksum $st
    Run --set off; Expect 0 "$OFF$UNOWNED_NOTE" 'unowned'
    if ((Json $sl) -cne '{"resets":false}') { Fail 'unowned statusline.json not written' }
    if ((Cksum $st) -cne $before) { Fail 'unowned settings.json changed' }
    # An empty command and a non-object settings root are unowned too.
    foreach ($s in '{"statusLine":{"type":"command","command":""}}', '[1]') {
        Put $st $s; $before = Cksum $st
        Run --set toggle; if ($script:rc -ne 0 -or -not $script:out.EndsWith($UNOWNED_NOTE)) { Fail "unowned [$s]: rc=$($script:rc) out=[$($script:out)] err=[$($script:err)]" }
        if ((Cksum $st) -cne $before) { Fail "unowned [$s] settings.json changed" }
    }
    # Invalid settings.json: warned on stderr, left byte-identical; statusline.json still written, exit 0.
    Put $sl '{"resets":true}'; Put $st '{not json'; $before = Cksum $st
    Run --set off; Expect 0 $OFF 'invalid settings.json'
    if (-not $script:err.Contains('not valid JSON; left unchanged') -or (Cksum $st) -cne $before -or (Json $sl) -cne '{"resets":false}') { Fail "invalid settings.json: err=[$($script:err)]" }
    # Legacy commands (the old dispatcher, the braisenly-statusline name) are owned: refreshInterval is managed.
    foreach ($c in $LEGACY_DISPATCHER_COMMAND, $LEGACY_BRAISENLY_COMMAND) {
        Put $st ([ordered]@{ statusLine = [ordered]@{ type = 'command'; command = $c } } | ConvertTo-Json -Depth 5); Put $sl '{}'
        Run --format countdown; Expect 0 $ON_COUNTDOWN "legacy owned [$c]"
        if ((Read-Json $st).statusLine.refreshInterval -ne 60) { Fail "legacy owned [$c]: $(Json $st)" }
    }

    # Usage is first-class: -h prints it on stdout, exit 0.
    Run -h; if ($script:rc -ne 0 -or -not $script:out.StartsWith('Usage:')) { Fail "help: rc=$($script:rc) out=[$($script:out)]" }

    'ok'
} finally {
    foreach ($k in $saved.Keys) { Set-Item -Path "env:$k" -Value $saved[$k] -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force -LiteralPath $Temp -ErrorAction SilentlyContinue
}

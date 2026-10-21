#!/usr/bin/env pwsh
# PowerShell twin of tests/test-statusline.sh: the same cases against scripts/statusline-command.ps1.
param(
    [Alias('h')][switch]$Help
)

function Usage { 'Usage: test-statusline.ps1 [-h|--help]' }
if ($Help) { Usage; exit 0 }
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
$Renderer = Join-Path $Root 'scripts/statusline-command.ps1'
. (Join-Path $Root 'config/constants.ps1')
$margin = $STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("bsl-statusline-" + [guid]::NewGuid())
$HomeDir = Join-Path $Tmp 'home'; $ConfigDir = Join-Path $Tmp 'config'; $CacheDir = Join-Path $Tmp 'cache'
$Work = Join-Path $HomeDir 'work'; $Cfg = Join-Path $ConfigDir 'statusline.json'; $Fable = Join-Path $CacheDir 'claude-statusline/fable.json'
foreach ($d in $Work, $ConfigDir, (Split-Path -Parent $Fable)) { New-Item -ItemType Directory -Force $d | Out-Null }

function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }
function Set-Config([string]$json) { [IO.File]::WriteAllText($Cfg, $json) }

# Run the renderer in a child pwsh with an isolated home, config and cache; the cwd is pinned so ladder stages
# land on the same widths on every machine. Returns stdout with rows joined by "`n".
function Invoke-Renderer([string[]]$argv = @(), [string]$stdin = $payload, [hashtable]$extraEnv = @{}) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
    foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $Renderer) + $argv) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Work
    $psi.Environment['HOME'] = $HomeDir; $psi.Environment['USERPROFILE'] = $HomeDir
    $psi.Environment['CLAUDE_CONFIG_DIR'] = $ConfigDir; $psi.Environment['XDG_CACHE_HOME'] = $CacheDir
    $psi.Environment['CLAUDE_STATUSLINE_DISABLE_WATCH'] = '1'; $psi.Environment['CLAUDE_STATUSLINE_DISABLE_REFRESH'] = '1'
    $psi.Environment['NO_COLOR'] = '1'; $psi.Environment.Remove('COLUMNS') | Out-Null
    foreach ($k in $extraEnv.Keys) { if ($null -eq $extraEnv[$k]) { $psi.Environment.Remove($k) | Out-Null } else { $psi.Environment[$k] = [string]$extraEnv[$k] } }
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($stdin); $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd(); [void]$p.StandardError.ReadToEnd(); $p.WaitForExit()
    return (($out -split "`r?`n") | Where-Object { $_ -ne '' }) -join "`n"
}
function Render([int]$cols) { Invoke-Renderer -extraEnv @{ COLUMNS = $cols } }
function Get-Cells([string]$s) {
    $n = 0
    foreach ($ch in $s.ToCharArray()) { $cp = [int]$ch; $n += (($cp -ge 0x2E80 -and $cp -le 0xA4CF) -or ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or ($cp -ge 0xFF00 -and $cp -le 0xFF60)) ? 2 : 1 }
    return $n
}
function Get-Rows([string]$s) { @($s -split "`n") }
function Assert-Fit([string]$label, [string]$out, [int]$budget) {
    foreach ($r in Get-Rows $out) { $n = Get-Cells $r; if ($n -gt $budget) { Fail "${label}: row overflows budget ${budget}: $n" } }
    $rows = Get-Rows $out
    if ($rows.Count -eq 2 -and (Get-Cells $rows[0]) -ne (Get-Cells $rows[1])) { Fail "${label}: stacked rows differ in width" }
}
function Get-Bracket([string]$s, [string]$after) { $i = $s.IndexOf($after); if ($i -lt 0) { return $null }; $rest = $s.Substring($i + $after.Length); return $rest.Substring(0, $rest.IndexOf(']')) }

try {
    Set-Config '{"segments":["five_hour","fable","seven_day"],"labels":{"five_hour":"five","fable":"story","seven_day":"week"},"widths":{"five_hour":3,"fable":5,"seven_day":4}}'
    [IO.File]::WriteAllText($Fable, '{"used_percentage":42,"resets_at":"2026-09-21T00:00:00Z","model":"Fable","fetched_at":' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + '}')
    $script:payload = '{"model":{"display_name":"Claude"},"context_window":{"used_percentage":25,"total_input_tokens":1000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":30}}}'
    $plain = Invoke-Renderer

    if ($plain -notlike '*five `[*') { Fail 'missing custom five-hour label' }
    if ($plain -notlike '*story `[*') { Fail 'missing Fable segment' }
    if ($plain -notlike '*week `[*') { Fail 'missing custom seven-day label' }
    if ($plain -like '*ctx `[*') { Fail 'hidden context segment rendered' }
    if ((Get-Bracket $plain 'five [').Length -ne 3) { Fail "five-hour width mismatch: $((Get-Bracket $plain 'five [').Length)" }
    if ((Get-Bracket $plain 'story [').Length -ne 5) { Fail 'Fable width mismatch' }
    if ((Get-Bracket $plain 'week [').Length -ne 4) { Fail 'seven-day width mismatch' }
    if ($plain -notlike '*five*story*week*') { Fail 'segment order mismatch' }

    Set-Config '{bad json'
    $fallback = Invoke-Renderer
    if ($fallback -notlike '*Claude*ctx*5h*7d*Fable*') { Fail "invalid config did not fall back to defaults: $fallback" }
    if ($fallback -like '*drift*') { Fail 'drift segment still rendered' }
    if ($fallback -match $ANSI_ESCAPE_SEQUENCE_START) { Fail 'NO_COLOR ignored: escape sequences in output' }

    # Terminal fit: budget is COLUMNS minus Claude Code's status-area margin.
    $wide = Render 400
    function Mask([string]$s) { $s -replace $DISK_FREE_ANY_NUMBER_THEN_UNIT_THEN_SPACE_FREE, 'N free' }
    if ((Mask $wide) -ne (Mask $fallback)) { Fail 'wide terminal changed the render' }
    $fullCells = Get-Cells $fallback
    Set-Config '{"fit":{"rows":2}}'
    $stk = Render ($fullCells - 10 + $margin)
    if ((Get-Rows $stk).Count -ne 2) { Fail "expected stacked layout, got $((Get-Rows $stk).Count) rows" }
    Assert-Fit 'stacked' $stk ($fullCells - 10)
    $r1, $r2 = Get-Rows $stk
    if ($r1 -notlike '*ctx `[░░░░░░░░░░░░`]*' -and $r1 -notlike '*ctx `[███░░░░░░░░░`]*') { Fail "stacked top row lost full ctx bar: $r1" }
    if ($r1.IndexOf('●') -ne $r2.IndexOf('●')) { Fail 'separator misaligned between rows' }
    if ($r2 -notlike '*1000B/195.3K (25%)*') { Fail "stacked bottom row lost ctx values: $r2" }
    $stkCells = Get-Cells $r1
    $shr = Render ($stkCells - 6 + $margin)
    Assert-Fit 'shrink' $shr ($stkCells - 6)
    if ((Get-Cells (Get-Rows $shr)[0]) -ne ($stkCells - 6)) { Fail 'shrunk rows not padded to budget' }
    $ctxbar = Get-Bracket $shr 'ctx ['
    if ($ctxbar.Length -ge 12 -or $ctxbar.Length -lt 5) { Fail "ctx bar not shrunk into range: $($ctxbar.Length)" }
    $lad = Render 90
    Assert-Fit 'ladder90' $lad (90 - $margin)
    if ((Get-Rows $lad).Count -ne 2 -or $lad -notlike '*`[*') { Fail "bars dropped at 90 despite two rows: $lad" }
    if ((Get-Bracket $lad 'five [').Length -lt 5 -and (Get-Bracket $lad '5h [').Length -lt 5) { Fail 'bar below floor at 90' }
    if (-not ((Get-Rows $lad)[0].StartsWith([char]0x2800) -or (Get-Rows $lad)[1].StartsWith([char]0x2800))) { Fail 'row leading pad is plain whitespace (Claude Code trims it)' }
    Set-Config '{bad json'
    $lad60 = Render 60
    Assert-Fit 'ladder60' $lad60 (60 - $margin)
    if ($lad60 -like '*`[*' -or $lad60 -like '*(*') { Fail "bars or parentheses survived at 60 single-row: $lad60" }
    if ($lad60 -notlike '*25%*') { Fail "ctx percentage dropped at 60: $lad60" }
    if (($lad60 -notlike '*30%*' -or $lad60 -notlike '*20%*') -and $lad60 -like '*42%*') { Fail "ladder order violated at 60: $lad60" }
    Set-Config '{"widths":{"fable":3},"fit":{"rows":1}}'
    $small = Render ($fullCells - 9 - 20 + $margin)
    if ($small -notlike '*ctx `[*') { Fail "sub-floor bar blocked shrinking: $small" }
    Set-Config '{"labels":{"five_hour":"五時間"},"fit":{"rows":1}}'
    $wideCjk = Render 120
    if ((Get-Cells $wideCjk) -gt (120 - $margin)) { Fail "wide label overflowed by display width: $(Get-Cells $wideCjk)" }
    if ($wideCjk -notlike '*五時間*') { Fail 'wide label missing' }
    $flr = Render 30; if ((Get-Rows $flr).Count -gt 2) { Fail 'floor emitted too many rows' }
    Set-Config '{bad json'
    $one = Render ($fullCells - 10 + $margin)
    if ((Get-Rows $one).Count -ne 1) { Fail 'fit.rows=1 still stacked' }
    Assert-Fit 'rows1' $one ($fullCells - 10)
    Set-Config '{"fit":{"reserve":20,"rows":1}}'
    $res = Render ($fullCells - 10 + $margin + 20)
    Assert-Fit 'reserve' $res ($fullCells - 10)
    if ($res -eq $fallback) { Fail 'reserve not applied' }
    Set-Config '{"fit":{"rows":1,"ladder":["ctx_label"]}}'
    $cl = Render 90
    if ($cl -like '*ctx*' -or $cl -notlike '*(25%)*' -or $cl -notlike '*Fable*') { Fail "custom ladder not honoured: $cl" }
    Set-Config '{"segments":["model","five_hour","drift"],"labels":{"five_hour":"legacy"}}'
    $legacy = Render 400
    if ($legacy -notlike '*legacy `[*' -or $legacy -like '*drift*') { Fail "legacy drift config rejected or rendered: $legacy" }
    Set-Config '{"labels":{"five_hour":"custom"},"fit":{"rows":false}}'
    if ((Render 400) -like '*custom*') { Fail 'boolean fit.rows did not reject the config' }
    Set-Config '{"fit":{"ladder":["bogus"],"rows":2}}'
    $bad = Render 90
    if ((Get-Rows $bad).Count -ne 1 -or $bad -notlike '*Fable*') { Fail "invalid ladder did not fall back to defaults: $bad" }
    # Negatives on the rest of the schema: each rejects the whole file (PASS = defaults render, custom label absent).
    foreach ($badCfg in '{"segments":["model","model"],"labels":{"five_hour":"custom"}}', '{"segments":["nope"],"labels":{"five_hour":"custom"}}',
                        '{"labels":{"five_hour":7}}', '{"widths":{"fable":0},"labels":{"five_hour":"custom"}}', '{"widths":{"fable":2.5},"labels":{"five_hour":"custom"}}',
                        '{"fable":{"refresh_seconds":10},"labels":{"five_hour":"custom"}}') {
        Set-Config $badCfg
        $o = Render 400
        if ($o -like '*custom*' -or $o -notlike '*Claude*ctx*5h*') { Fail "invalid config accepted: $badCfg -> $o" }
    }

    # ---- exclusion ladder map. Segments pinned (no /tmp) so every machine renders the same stages. ----
    $order = @('disk_label', 'ctx_int', 'no_parens', 'disk_int', 'ctx_no_total', 'no_free', 'fable_short', 'disk_value', 'ctx_no_used', 'fable_label', 'fable_segment', 'seven_label', 'five_label', 'ctx_label', 'seven_segment', 'five_segment')
    $pin = '"segments":["model","cwd","context","disk","five_hour","seven_day","fable"]'
    function Floor([string[]]$steps) { Set-Config ('{' + $pin + ',"fit":{"rows":1,"ladder":[' + (($steps | ForEach-Object { "`"$_`"" }) -join ',') + ']}}'); return (Render 10) }
    $base = Floor @()
    $m = [regex]::Match($base, $DISK_FREE_ONE_DECIMAL_THEN_UNIT_THEN_SPACE_FREE)
    if (-not $m.Success) { Fail "baseline lost the disk value: $base" }
    $diskTok = "$($m.Groups[1].Value)$($m.Groups[2].Value)"
    # Each step on its own: exactly its declared change to the bars-off baseline, nothing else.
    $expect = [ordered]@{
        disk_label    = $base.Replace('disk ', '')
        ctx_int       = $base.Replace('/195.3K', '/195K')
        no_parens     = $base.Replace('(', '').Replace(')', '')
        ctx_no_total  = $base.Replace('/195.3K', '')
        no_free       = $base.Replace(' free', '')
        fable_short   = $base.Replace('Fable (', 'F (')
        disk_value    = $base.Replace(" $diskTok free", '')
        ctx_no_used   = $base.Replace('1000B/', '')
        fable_label   = $base.Replace('Fable (', '(')
        fable_segment = $base.Replace(' ● Fable (42%)', '')
        seven_label   = $base.Replace('7d (', '(')
        five_label    = $base.Replace('5h (', '(')
        ctx_label     = $base.Replace('ctx 1000B', '1000B')
        seven_segment = $base.Replace(' ● 7d (30%)', '')
        five_segment  = $base.Replace(' ● 5h (20%)', '')
    }
    foreach ($s in $expect.Keys) {
        if ($expect[$s] -eq $base) { Fail "ladder ${s}: expectation is a no-op on baseline: $base" }
        $o = Floor @($s)
        if ($o -ne $expect[$s]) { Fail "ladder ${s}: got [$o] want [$($expect[$s])]" }
    }
    $o = Floor @('disk_int')
    $mi = [regex]::Match($o, $DISK_FREE_INTEGER_THEN_UNIT_THEN_SPACE_FREE)
    if (-not $mi.Success -or $mi.Groups[2].Value -ne $m.Groups[2].Value -or [math]::Abs([double]$mi.Groups[1].Value - [double]$m.Groups[1].Value) -gt 0.55 -or
        $o.Replace($mi.Value, " $diskTok free") -ne $base) { Fail "ladder disk_int: got [$o] from [$base]" }
    # Progressive order: the k-step floor needs L_k cells; at L_k + margin columns the default ladder shows exactly
    # the first k steps, one column less shows k+1. Every step buys at least one cell.
    $floors = @(for ($k = 0; $k -le $order.Count; $k++) { Floor @($order | Select-Object -First $k) })
    for ($k = 0; $k -lt $order.Count; $k++) {
        if ((Get-Cells $floors[$k + 1]) -ge (Get-Cells $floors[$k])) { Fail "ladder step $($order[$k]) buys no cells" }
    }
    Set-Config ('{' + $pin + ',"fit":{"rows":1}}')
    for ($k = 0; $k -le $order.Count; $k++) {
        $lk = Get-Cells $floors[$k]
        $at = (Render ($lk + $margin)).TrimEnd()
        if ($at -ne $floors[$k]) { Fail "ladder progression: at $($lk + $margin) cols want $k steps [$($floors[$k])] got [$at]" }
        if ($k -lt $order.Count) {
            $below = (Render ($lk + $margin - 1)).TrimEnd()
            if ($below -ne $floors[$k + 1]) { Fail "ladder progression: at $($lk + $margin - 1) cols want $($k + 1) steps [$($floors[$k + 1])] got [$below]" }
        }
    }
    Set-Config '{bad json'

    if ((Invoke-Renderer -argv @('-Help')) -notlike 'Usage:*') { Fail 'usage' }

    # Fable refresh against a local mock of the usage endpoint (OS-assigned port on 0.0.0.0, test-only).
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, 0); $listener.Start()
    $url = "http://127.0.0.1:$(($listener.LocalEndpoint).Port)/usage"
    function Refresh-With([string]$body) {
        Remove-Item -LiteralPath $Fable, (Join-Path (Split-Path -Parent $Fable) 'next_refresh') -Force -ErrorAction SilentlyContinue
        $psi = [System.Diagnostics.ProcessStartInfo]::new('pwsh')
        foreach ($a in '-NoProfile', '-NonInteractive', '-File', $Renderer, '-RefreshFable') { $psi.ArgumentList.Add($a) }
        $psi.WorkingDirectory = $Work
        $psi.Environment['HOME'] = $HomeDir; $psi.Environment['USERPROFILE'] = $HomeDir; $psi.Environment['CLAUDE_CONFIG_DIR'] = $ConfigDir
        $psi.Environment['XDG_CACHE_HOME'] = $CacheDir; $psi.Environment['CLAUDE_CODE_OAUTH_TOKEN'] = 'secret-test-token'
        $psi.Environment['CLAUDE_STATUSLINE_USAGE_URL'] = $url
        $p = [System.Diagnostics.Process]::Start($psi)
        $client = $listener.AcceptTcpClient(); $stream = $client.GetStream()
        $reader = [IO.StreamReader]::new($stream); while (($line = $reader.ReadLine()) -ne '') { if ($null -eq $line) { break } }
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $head = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
        $stream.Write($head, 0, $head.Length); $stream.Write($bytes, 0, $bytes.Length); $stream.Flush(); $client.Close()
        $p.WaitForExit()
        return (Get-Content -Raw -LiteralPath $Fable | ConvertFrom-Json -AsHashtable -DateKind String)
    }
    $c = Refresh-With '{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"used_percentage":67,"resets_at":"soon"}]}'
    if ($c.used_percentage -ne 67 -or $c.resets_at -ne 'soon' -or $c.ContainsKey('accessToken')) { Fail "fable refresh (limits): $($c | ConvertTo-Json -Compress)" }
    $c = Refresh-With '{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable 5"}},"percent":73,"resets_at":"later-percent"}]}'
    if ($c.used_percentage -ne 73 -or $c.resets_at -ne 'later-percent') { Fail "fable refresh (percent): $($c | ConvertTo-Json -Compress)" }
    $c = Refresh-With '{"fable":{"used_percentage":55,"resets_at":"later"}}'
    if ($c.used_percentage -ne 55 -or $c.resets_at -ne 'later') { Fail "fable refresh (fable object): $($c | ConvertTo-Json -Compress)" }
    $listener.Stop()

    $c['fetched_at'] = 1; ($c | ConvertTo-Json -Compress) | Set-Content -LiteralPath $Fable
    $stale = Invoke-Renderer
    if ($stale -notlike '*Fable `[*(n/a)*') { Fail "missing unavailable Fable bar: $stale" }
    'ok'
} finally {
    Remove-Item -Recurse -Force -LiteralPath $Tmp -ErrorAction SilentlyContinue
}

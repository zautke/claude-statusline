#!/usr/bin/env pwsh
# Claude Code statusline — PowerShell 7+ port of statusline-command.sh
# Feature-parity: RGB gradient bars, disk/tmp/rate-limit/Fable sections, COLUMNS-aware bar fitting.

param(
    [Alias('r')][switch]$RefreshFable,
    [Alias('h')][switch]$Help
)

function Usage {
    'Usage: statusline-command.ps1 [-h|--help] [-r|--refresh-fable]'
}

if ($Help) { Usage; exit 0 }

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'config/constants.ps1')

# Claude Code on Windows requires Git Bash. Reuse canonical renderer so both
# entry points share validation, configuration, cache, and OAuth behavior.
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash -and -not $IsWindows) {
    $renderer = Join-Path $PSScriptRoot 'statusline-command.sh'
    if ($RefreshFable) { & $bash.Source $renderer --refresh-fable; exit $LASTEXITCODE }
    $stdin = [Console]::In.ReadToEnd()
    $stdin | & $bash.Source $renderer
    exit $LASTEXITCODE
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
    $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::Ansi
}

$configDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
$cacheRoot = if ($env:XDG_CACHE_HOME) { $env:XDG_CACHE_HOME } else { Join-Path $HOME '.cache' }
$fablePct = $null
$fableLabel = 'Fable'
$fableModel = 'Fable'
$fableWidth = 12
$fableRefreshSeconds = 600
$fableMaxStale = 86400
$fitReserve = 0
$minBarCells = 5
$resizeWatch = $false
$configPath = Join-Path $configDir 'statusline.json'
if (Test-Path -LiteralPath $configPath) {
    try {
        $cfg = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        # All-or-nothing, as in the Bash renderer: any invalid fit field rejects the whole file.
        $knownLadder = @('resets','disk_label','ctx_int','no_parens','disk_int','ctx_no_total','no_free','fable_short','disk_value','ctx_no_used','fable_label','fable_segment','seven_label','five_label','ctx_label','seven_segment','five_segment')
        function Test-Int($v) { return ($v -is [int] -or $v -is [long]) }
        if ($null -ne $cfg.fit) {
            if ($cfg.fit -isnot [System.Management.Automation.PSCustomObject]) { throw 'invalid fit' }
            if ($null -ne $cfg.fit.rows -and -not (Test-Int $cfg.fit.rows)) { throw 'invalid fit.rows' }
            if ($null -ne $cfg.fit.reserve -and -not (Test-Int $cfg.fit.reserve)) { throw 'invalid fit.reserve' }
            if ($null -ne $cfg.fit.min_bar_cells -and -not (Test-Int $cfg.fit.min_bar_cells)) { throw 'invalid fit.min_bar_cells' }
            if ($null -ne $cfg.fit.ladder -and (-not ($cfg.fit.ladder -is [array]) -or @($cfg.fit.ladder | Where-Object { $_ -cnotin $knownLadder }).Count -gt 0)) { throw 'invalid fit.ladder' }
            if ($null -ne $cfg.fit.rows -and $cfg.fit.rows -notin 1, 2) { throw 'invalid fit.rows' }
            if ($null -ne $cfg.fit.reserve -and ($cfg.fit.reserve -lt 0 -or $cfg.fit.reserve -gt 200)) { throw 'invalid fit.reserve' }
            if ($null -ne $cfg.fit.min_bar_cells -and ($cfg.fit.min_bar_cells -lt 1 -or $cfg.fit.min_bar_cells -gt 128)) { throw 'invalid fit.min_bar_cells' }
            if ($null -ne $cfg.fit.resize_watch -and $cfg.fit.resize_watch -isnot [bool]) { throw 'invalid fit.resize_watch' }
        }
        # "drift" is accepted for configs written before the segment was retired; the renderer skips it.
        $knownSegments = @('model', 'profile', 'cwd', 'context', 'disk', 'tmp', 'five_hour', 'seven_day', 'fable', 'drift')
        if ($null -ne $cfg.segments) {
            $seg = $cfg.segments
            if ($seg -isnot [array] -or @($seg | Where-Object { $_ -isnot [string] -or $_ -cnotin $knownSegments }).Count -gt 0 -or
                @($seg | Select-Object -Unique).Count -ne @($seg).Count) { throw 'invalid segments' }
        }
        if ($null -ne $cfg.labels) {
            if ($cfg.labels -isnot [System.Management.Automation.PSCustomObject]) { throw 'invalid labels' }
            foreach ($p in $cfg.labels.PSObject.Properties) { if ($p.Value -isnot [string]) { throw 'invalid labels' } }
        }
        if ($null -ne $cfg.widths) {
            if ($cfg.widths -isnot [System.Management.Automation.PSCustomObject]) { throw 'invalid widths' }
            foreach ($p in $cfg.widths.PSObject.Properties) { if (-not (Test-Int $p.Value) -or $p.Value -lt 1 -or $p.Value -gt 128) { throw 'invalid widths' } }
        }
        if ($null -ne $cfg.resets -and $cfg.resets -isnot [bool]) { throw 'invalid resets' }
        if ($null -ne $cfg.resets_format -and ($cfg.resets_format -isnot [string] -or $cfg.resets_format -cnotin 'clock', 'countdown')) { throw 'invalid resets_format' }
        if ($null -ne $cfg.fable.refresh_seconds -and $cfg.fable.refresh_seconds -lt 60) { throw 'invalid fable.refresh_seconds' }
        if ($null -ne $cfg.fable.max_stale_seconds -and $cfg.fable.max_stale_seconds -lt 60) { throw 'invalid fable.max_stale_seconds' }
        if ($cfg.fable.model) { $fableModel = [string]$cfg.fable.model }
        if ($null -ne $cfg.fit.reserve) { $fitReserve = [int]$cfg.fit.reserve }
        if ($cfg.fit.min_bar_cells) { $minBarCells = [int]$cfg.fit.min_bar_cells }
        if ($cfg.fit.resize_watch -eq $true) { $resizeWatch = $true }
        if ($cfg.fable.refresh_seconds) { $fableRefreshSeconds = [int64]$cfg.fable.refresh_seconds }
        if ($cfg.fable.max_stale_seconds) { $fableMaxStale = [int64]$cfg.fable.max_stale_seconds }
    } catch { $cfg = $null; $fableModel = 'Fable'; $fableLabel = 'Fable'; $fableWidth = 12; $fitReserve = 0; $minBarCells = 5; $resizeWatch = $false; $fableRefreshSeconds = 600; $fableMaxStale = 86400 }
}
# Reset-time mode: off | clock | countdown.
$resetsMode = 'clock'
if ($cfg) { if ($cfg.resets -eq $false) { $resetsMode = 'off' } elseif ($cfg.resets_format) { $resetsMode = [string]$cfg.resets_format } }
# Labels, bar widths and segment order, as in the Bash renderer ($cfg is $null when the file is absent or invalid).
$L = @{ context = 'ctx'; disk = 'disk'; tmp = '/tmp'; five_hour = '5h'; seven_day = '7d'; fable = 'Fable' }
$Wd = @{ context = 12; disk = 12; tmp = 15; five_hour = 12; seven_day = 12; fable = 12 }
$segList = @('model', 'profile', 'cwd', 'context', 'disk', 'tmp', 'five_hour', 'seven_day', 'fable')
if ($cfg) {
    if ($cfg.labels) { foreach ($p in $cfg.labels.PSObject.Properties) { $L[$p.Name] = [string]$p.Value } }
    if ($cfg.widths) { foreach ($p in $cfg.widths.PSObject.Properties) { $Wd[$p.Name] = [int]$p.Value } }
    if ($null -ne $cfg.segments) { $segList = @($cfg.segments) }
}
$fableLabel = $L['fable']; $fableWidth = $Wd['fable']
$profileName = $env:CLAUDE_PROFILE
if (-not $profileName -and $env:CLAUDE_CONFIG_DIR) {
    $leaf = Split-Path -Leaf $env:CLAUDE_CONFIG_DIR
    if ($leaf.StartsWith('.claude-')) { $profileName = $leaf.Substring('.claude-'.Length) }
}
$fableCache = Join-Path $cacheRoot 'claude-statusline/fable.json'

function Get-OAuthToken {
    if ($env:CLAUDE_CODE_OAUTH_TOKEN) { return $env:CLAUDE_CODE_OAUTH_TOKEN }
    $credentialPath = Join-Path $configDir '.credentials.json'
    if (Test-Path -LiteralPath $credentialPath) {
        try {
            $credentials = Get-Content -LiteralPath $credentialPath -Raw | ConvertFrom-Json
            return [string]($credentials.claudeAiOauth.accessToken ?? $credentials.accessToken)
        } catch { }
    }
    return ''
}

$nextRefreshFile = Join-Path (Split-Path -Parent $fableCache) 'next_refresh'
function Get-NextRefresh {
    $next = 0L
    if (Test-Path -LiteralPath $nextRefreshFile) { [void][int64]::TryParse((Get-Content -LiteralPath $nextRefreshFile -Raw), [ref]$next) }
    return $next
}

function Refresh-Fable {
    $token = Get-OAuthToken
    if (-not $token) { return }
    $cacheDir = Split-Path -Parent $fableCache
    New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
    $lock = Join-Path $cacheDir 'refresh.lock'
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    # A refresh killed mid-flight never reaches its finally block; reclaim a lock older than 60s.
    # ponytail: remove+create is not atomic; two renders racing on one stale lock can both refresh once.
    if ((Test-Path -LiteralPath $lock) -and ([DateTimeOffset]::UtcNow - (Get-Item -LiteralPath $lock).LastWriteTimeUtc).TotalSeconds -gt 60) {
        Remove-Item -LiteralPath $lock -Recurse -Force -ErrorAction SilentlyContinue
    }
    try { New-Item -ItemType Directory -Path $lock -ErrorAction Stop | Out-Null } catch { return }
    try {
        if ((Get-NextRefresh) -gt $now) { return }
        # Claim the slot before the request so a failure backs off instead of retrying on every render.
        Set-Content -LiteralPath $nextRefreshFile -Value ($now + $fableRefreshSeconds) -NoNewline
        # Parse the body ourselves: Invoke-RestMethod turns ISO-8601 strings (resets_at) into DateTime, and the [string] cast below would cache them in the local culture.
        $response = (Invoke-WebRequest -Uri ($env:CLAUDE_STATUSLINE_USAGE_URL ?? 'https://api.anthropic.com/api/oauth/usage') -Headers @{
            Authorization = "Bearer $token"
            'anthropic-beta' = 'oauth-2025-04-20'
            Accept = 'application/json'
            'User-Agent' = 'claude-code/claude-statusline'
        } -TimeoutSec 8).Content | ConvertFrom-Json -DateKind String
        $limits = if ($response.limits) { $response.limits } elseif ($response.cachedUsageUtilization.utilization.limits) { $response.cachedUsageUtilization.utilization.limits } else { @() }
        $limit = @($limits | Where-Object {
            $_.kind -eq 'weekly_scoped' -and
            ([string]($_.scope.model.display_name ?? $_.scope.model ?? $_.model)).StartsWith($fableModel, [System.StringComparison]::OrdinalIgnoreCase)
        }) | Select-Object -First 1
        $pct = if ($limit) { $limit.percent ?? $limit.used_percentage ?? $limit.utilization ?? $limit.usage_percentage } else { $response.fable.percent ?? $response.fable.used_percentage ?? $response.weekly_fable.percent ?? $response.weekly_fable.used_percentage ?? $response.seven_day_fable.percent ?? $response.seven_day_fable.used_percentage }
        $number = 0.0
        if ($null -ne $pct -and [double]::TryParse([string]$pct, [ref]$number)) {
            $cache = [ordered]@{ used_percentage = [double]$number; resets_at = [string]($limit.resets_at ?? $response.fable.resets_at); model = $fableModel; fetched_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
            $tmp = "$fableCache.tmp.$PID"
            $cache | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmp -Encoding utf8
            Move-Item -LiteralPath $tmp -Destination $fableCache -Force
        }
    } catch {
        $retry = $_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds
        if ($retry -gt $fableRefreshSeconds) { Set-Content -LiteralPath $nextRefreshFile -Value ($now + [int64]$retry) -NoNewline }
    }
    finally { Remove-Item -LiteralPath $lock -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($RefreshFable) { Refresh-Fable; exit 0 }
if (Test-Path -LiteralPath $fableCache) {
    try {
        $cached = Get-Content -LiteralPath $fableCache -Raw | ConvertFrom-Json
        $age = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$cached.fetched_at
        if ($age -ge 0 -and $age -le $fableMaxStale -and $null -ne $cached.used_percentage) {
            $fablePct = [int][math]::Round([double]$cached.used_percentage)
        }
    } catch { }
}

if (-not $env:CLAUDE_STATUSLINE_DISABLE_REFRESH) {
    if ((Get-NextRefresh) -le [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) {
        Start-Process -FilePath 'pwsh' -ArgumentList "-NoProfile -NonInteractive -File `"$PSCommandPath`" -RefreshFable" -WindowStyle Hidden
    }
}

# One resize watcher per Claude Code process: walk up the parent chain to claude, lock on its pid.
# Opt-in: the watcher rewrites settings.json on resize, so it is off unless fit.resize_watch is true.
if ($resizeWatch -and -not $env:CLAUDE_STATUSLINE_DISABLE_WATCH) {
    try {
        $proc = Get-Process -Id $PID
        for ($i = 0; $i -lt 6 -and $proc; $i++) {
            if ($proc.ProcessName -like 'claude*') { break }
            $parentId = (Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").ParentProcessId
            $proc = if ($parentId) { Get-Process -Id $parentId -ErrorAction SilentlyContinue } else { $null }
        }
        if ($proc -and $proc.ProcessName -like 'claude*') {
            $watchDir = Join-Path $cacheRoot 'claude-statusline'
            New-Item -ItemType Directory -Force -Path $watchDir | Out-Null
            $lock = Join-Path $watchDir "resize-watch.$($proc.Id).pid"
            # Two overlapping renders must not both spawn: the directory create is the atomic mutex around check-and-spawn.
            $mutex = $null
            # A render killed mid-spawn never removes it; reclaim a mutex older than 60s.
            if ((Test-Path -LiteralPath "$lock.spawn") -and ([DateTime]::UtcNow - (Get-Item -LiteralPath "$lock.spawn").LastWriteTimeUtc).TotalSeconds -gt 60) { Remove-Item -LiteralPath "$lock.spawn" -Force -ErrorAction SilentlyContinue }
            try { $mutex = New-Item -ItemType Directory -Path "$lock.spawn" -ErrorAction Stop } catch { }
            if ($mutex) {
                try {
                    $alive = (Test-Path -LiteralPath $lock) -and (Get-Process -Id ([int](Get-Content -LiteralPath $lock -Raw)) -ErrorAction SilentlyContinue)
                    if (-not $alive) {
                        $watcher = Start-Process -FilePath 'pwsh' -ArgumentList "-NoProfile -NonInteractive -File `"$(Join-Path $PSScriptRoot 'resize-watch.ps1')`" -ClaudePid $($proc.Id) -Settings `"$(Join-Path $configDir 'settings.json')`"" -WindowStyle Hidden -PassThru
                        Set-Content -LiteralPath $lock -Value $watcher.Id -NoNewline
                    }
                } finally { Remove-Item -LiteralPath "$lock.spawn" -Force -ErrorAction SilentlyContinue }
            }
        }
    } catch { }
}

$input_data = [Console]::In.ReadToEnd()

$ESC     = [char]27
$R       = "$ESC[0m"
$C_MODEL = "$ESC[1;38;2;86;182;194m"   # steel-blue bold
$C_LABEL = "$ESC[38;5;240m"             # dim gray labels
$C_SEP   = "$ESC[38;5;237m"             # separator pipe
$C_VAL   = "$ESC[38;5;243m"             # dim value text
$C_EMPTY = "$ESC[38;5;59m"              # medium gray empty cells
# NO_COLOR (https://no-color.org): plain text, as in the Bash renderer.
$noColor = [bool]$env:NO_COLOR
if ($noColor) { $R = ''; $C_MODEL = ''; $C_LABEL = ''; $C_SEP = ''; $C_VAL = ''; $C_EMPTY = '' }


function Get-CellColor([int]$pos) {
    if ($noColor) { return '' }
    if ($pos -le 50) {
        $r = 40  + [int](180 * $pos / 50)
        $g = 170 - [int](10  * $pos / 50)
        $b = 60  - [int](60  * $pos / 50)
    } else {
        $p2 = $pos - 50
        $r = 220 - [int](40  * $p2 / 50)
        $g = 160 - [int](160 * $p2 / 50)
        $b = 0
    }
    return "$ESC[38;2;${r};${g};${b}m"
}

# The number always carries the heat colour of its bar tip, bar shown or not.
function Format-PctText([int]$p) {
    return "$(Get-CellColor $p)${p}%${R}"
}

function Format-Bytes([long]$b) {
    if ($b -ge 1073741824) { return "{0:F1}G" -f ($b / 1073741824) }
    if ($b -ge 1048576)    { return "{0:F1}M" -f ($b / 1048576) }
    if ($b -ge 1024)       { return "{0:F1}K" -f ($b / 1024) }
    return "${b}B"
}

# Get-Bar — when -Inverted is 1, per-cell gradient is reversed (left=red, right=green).
function Get-Bar([int]$pct, [int]$width = 20, [int]$inverted = 0) {
    $pct = [math]::Max(0, [math]::Min(100, $pct))
    # Whole cells only: an eighth-block glyph leaves a blank gap before the ░ track.
    $full = [int][math]::Floor(($pct * $width + 50) / 100)
    if ($pct -gt 0 -and $full -eq 0) { $full = 1 }
    $out = "["
    for ($i = 0; $i -lt $full; $i++) {
        if ($inverted -eq 1) {
            $pos = 100 - [int][math]::Floor($i * 100 / $width)
        } else {
            $pos = [int][math]::Floor($i * 100 / $width)
        }
        $out += "$(Get-CellColor $pos)█"
    }
    if ($full -lt $width) {
        $out += $C_EMPTY
        $out += '░' * ($width - $full)
    }
    $out += "${R}]"
    return $out
}

function Get-Sep { return "${C_SEP} ● ${R}" }

# Fit state: $barsOff drops every bar; $scaleNum/$scaleDen shrink configured widths uniformly.
$script:barsOff = $false
$script:scaleNum = 1
$script:scaleDen = 1
function Get-FitBar([int]$pct, [int]$width) {
    if ($script:barsOff) { return '' }
    return Get-Bar $pct ([math]::Max(1, [int][math]::Floor($width * $script:scaleNum / $script:scaleDen)))
}
# Display cells of a rendered row: strip SGR, count chars (all glyphs used are single-width BMP).
# Wide (2-cell) code points: East Asian Wide/Fullwidth blocks and emoji presentation ranges; everything else is 1 cell.
function Test-Wide([int]$cp) {
    return (($cp -ge 0x1100 -and $cp -le 0x115F) -or ($cp -ge 0x2E80 -and $cp -le 0xA4CF -and $cp -ne 0x303F) -or ($cp -ge 0xAC00 -and $cp -le 0xD7A3) -or
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or ($cp -ge 0xFE30 -and $cp -le 0xFE4F) -or ($cp -ge 0xFF00 -and $cp -le 0xFF60) -or ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or
            ($cp -ge 0x1F300 -and $cp -le 0x1FAFF) -or ($cp -ge 0x20000 -and $cp -le 0x3FFFD))
}
function Get-Cells([string]$s) {
    $plain = $s -replace "$ESC\[[0-9;]*m", ''
    $n = 0
    for ($i = 0; $i -lt $plain.Length; $i++) {
        $cp = [char]::ConvertToUtf32($plain, $i)
        if ($cp -gt 0xFFFF) { $i++ }
        $n += (Test-Wide $cp) ? 2 : 1
    }
    return $n
}

# Parse JSON — no jq needed
$j       = $input_data | ConvertFrom-Json
$model   = if ($j.model.display_name) { $j.model.display_name } else { "Claude" }
$usedPct = $j.context_window.used_percentage
$totalIn = $j.context_window.total_input_tokens
$ctxSize = $j.context_window.context_window_size
$rl5h    = $j.rate_limits.five_hour.used_percentage
$rl7d    = $j.rate_limits.seven_day.used_percentage

# ---- values computed once; the fit loop below only assembles strings ----
$cwdText = $PWD.Path -replace [regex]::Escape($HOME), '~'
$cwdText = $cwdText -replace '\\', '/'
if ($cwdText.Length -gt 30) {
    $parts = $PWD.Path -split '[/\\]' | Where-Object { $_ -ne '' }
    $cwdText = if ($parts.Count -ge 2) { "…/$($parts[-2])/$($parts[-1])" } else { "/$($parts[-1])" }
}
function Format-BytesD([long]$b, [int]$d) {
    if ($b -ge 1073741824) { return ("{0:F$d}G" -f ($b / 1073741824)) }
    if ($b -ge 1048576)    { return ("{0:F$d}M" -f ($b / 1048576)) }
    if ($b -ge 1024)       { return ("{0:F$d}K" -f ($b / 1024)) }
    return "${b}B"
}
$ctxPct = $null
if ($null -ne $usedPct -and $ctxSize -gt 0) {
    $ctxPct = [int][math]::Round($usedPct)
    $ctxUsed1 = Format-BytesD $totalIn 1; $ctxUsed0 = Format-BytesD $totalIn 0
    $ctxTotal1 = Format-BytesD $ctxSize 1; $ctxTotal0 = Format-BytesD $ctxSize 0
}
$diskPct = $null; $tmpPct = $null
if ($IsWindows) {
    $drive = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($drive -and ($drive.Used + $drive.Free) -gt 0) {
        $diskPct = [int]($drive.Used * 100 / ($drive.Used + $drive.Free))
        $diskFree1 = Format-BytesD ([long]$drive.Free) 1; $diskFree0 = Format-BytesD ([long]$drive.Free) 0
    }
} else {
    $dfOut = (df -k / 2>$null | Select-Object -Last 1)
    if ($dfOut) {
        $parts = ($dfOut -split '\s+'); $dt = [long]$parts[1]; $da = [long]$parts[3]
        if ($dt -gt 0) { $diskPct = [int](($dt - $da) * 100 / $dt); $diskFree1 = Format-BytesD ($da * 1024) 1; $diskFree0 = Format-BytesD ($da * 1024) 0 }
    }
    $tfOut = (df -k /tmp 2>$null | Select-Object -Last 1)
    if ($tfOut -and (($tfOut -split '\s+')[0] -eq 'tmpfs')) {
        $parts = ($tfOut -split '\s+'); $tt = [long]$parts[1]; $ta = [long]$parts[3]
        if ($tt -gt 0) { $tmpPct = [int](($tt - $ta) * 100 / $tt); $tmpFree1 = Format-BytesD ($ta * 1024) 1; $tmpFree0 = Format-BytesD ($ta * 1024) 0 }
    }
}
$fivePct = if ($null -ne $rl5h) { [int][math]::Round($rl5h) } else { $null }
$sevenPct = if ($null -ne $rl7d) { [int][math]::Round($rl7d) } else { $null }
# Reset text per slot, once: resets_at rounded up to the minute, then clock (local HH:mm / day code + HH) or countdown.
$nowEpoch = 0L
if (-not ($env:CLAUDE_STATUSLINE_NOW -match $NON_NEGATIVE_INTEGER_DIGITS_ONLY -and [long]::TryParse($env:CLAUDE_STATUSLINE_NOW, [ref]$nowEpoch))) { $nowEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
function Get-ResetText($at, [string]$slot) {
    if ($resetsMode -eq 'off' -or -not ($at -is [int] -or $at -is [long] -or $at -is [double] -or $at -is [decimal])) { return '' }
    $up = [long]([math]::Ceiling([double]$at / 60) * 60)
    if ($resetsMode -eq 'clock') {
        $t = [DateTimeOffset]::FromUnixTimeSeconds($up).ToLocalTime(); $ic = [Globalization.CultureInfo]::InvariantCulture
        $s = if ($slot -eq '5h') { $t.ToString('HH:mm', $ic) } else { $WEEKDAY_CODES_SUNDAY_FIRST_SU_M_T_W_R_F_SA[[int]$t.DayOfWeek] + $t.ToString('HH', $ic) }
    } else {
        $m = [math]::Max(0L, [long][math]::Ceiling(($up - $nowEpoch) / 60.0))
        $s = if ($m -ge 1440) { "$([math]::Floor($m / 1440))d$([math]::Floor($m % 1440 / 60))h" } elseif ($m -ge 60) { "$([math]::Floor($m / 60))h$($m % 60)m" } else { "${m}m" }
    }
    return "$RESET_TIME_GLYPH_CLOCKWISE_OPEN_CIRCLE_ARROW$s"
}
# Appended to a 5h/7d slot's values: reset text and the click glyph, or the "hidden" glyph when resets are off.
function Get-ResetTail([string]$text) {
    if ($resetsMode -eq 'off') { return " ${C_VAL}${RESETS_CLICK_GLYPH_HIDDEN_SQUARED_PLUS_THEN_LEFT_POINTING_SMALL_TRIANGLE}${R}" }
    return " ${C_VAL}$($text ? "$text " : '')${RESETS_CLICK_GLYPH_SHOWN_SQUARED_MINUS_THEN_LEFT_POINTING_SMALL_TRIANGLE}${R}"
}
$fiveTail = Get-ResetTail (Get-ResetText $j.rate_limits.five_hour.resets_at '5h')
$sevenTail = Get-ResetTail (Get-ResetText $j.rate_limits.seven_day.resets_at '7d')

# ---- exclusion ladder: ordered flags the builders consult; each step buys cells when nothing else fits ----
$defaultLadder = @('resets','disk_label','ctx_int','no_parens','disk_int','ctx_no_total','no_free','fable_short','disk_value','ctx_no_used','fable_label','fable_segment','seven_label','five_label','ctx_label','seven_segment','five_segment')
$ladder = $defaultLadder; $fitRows = 1
if ($cfg) {
    if ($cfg.fit.ladder -is [array]) { $ladder = @($cfg.fit.ladder) }
    if ($cfg.fit.rows -in 1, 2) { $fitRows = [int]$cfg.fit.rows }
}
$script:F = @{}
function Get-Paren([string]$s) { if ($script:F['no_parens']) { return $s } else { return "($s)" } }
function Add-Bar([string]$top, [string]$bar) { if ($bar) { return ($top ? "$top $bar" : $bar) } else { return $top } }

# Builders fill $segTop (label + bar) and $segBot (values). A segment with both empty is omitted.
function Build {
    $script:segTop = [System.Collections.Generic.List[string]]::new()
    $script:segBot = [System.Collections.Generic.List[string]]::new()
    foreach ($s in $segList) {
        $top = ''; $bot = ''
        switch ($s) {
            'model' { $top = "${C_MODEL}${model}${R}" }
            'profile' { if ($profileName) { $top = "${C_LABEL}prof${R} ${C_VAL}${profileName}${R}" } }
            'cwd'   { $top = "${C_VAL}${cwdText}${R}" }
            'context' {
                if (-not $F['ctx_label']) { $top = "${C_LABEL}$($L['context'])${R}" }
                if ($null -ne $ctxPct) {
                    $top = Add-Bar $top (Get-FitBar $ctxPct $Wd['context'])
                    $used = $F['ctx_int'] ? $ctxUsed0 : $ctxUsed1; $total = $F['ctx_int'] ? $ctxTotal0 : $ctxTotal1
                    if (-not $F['ctx_no_used']) { $bot = "${C_VAL}${used}${R}" }
                    if (-not $F['ctx_no_total']) { $bot += "${C_VAL}$($bot ? '/' : '')${total}${R}" }
                    $bot += ($bot ? ' ' : '') + (Get-Paren (Format-PctText $ctxPct))
                } else { $top = Add-Bar $top (Get-FitBar 0 $Wd['context']) }
            }
            { $_ -in 'disk', 'tmp' } {
                if ($s -eq 'disk') { $pct = $diskPct; $free1 = $diskFree1; $free0 = $diskFree0 } else { $pct = $tmpPct; $free1 = $tmpFree1; $free0 = $tmpFree0 }
                $lab = $L[$s]; $W = $Wd[$s]
                if ($null -eq $pct) { continue }
                if (-not $F['disk_label']) { $top = "${C_LABEL}${lab}${R}" }
                $top = Add-Bar $top (Get-FitBar $pct $W)
                if (-not $F['disk_value']) { $bot = "${C_VAL}$($F['disk_int'] ? $free0 : $free1)${R}"; if (-not $F['no_free']) { $bot += ' free' } }
            }
            'five_hour' {
                if ($null -eq $fivePct -or $F['five_segment']) { continue }
                if (-not $F['five_label']) { $top = "${C_LABEL}$($L['five_hour'])${R}" }
                $top = Add-Bar $top (Get-FitBar $fivePct $Wd['five_hour']); $bot = Get-Paren (Format-PctText $fivePct)
                if (-not $F['resets']) { $bot += $fiveTail }
            }
            'seven_day' {
                if ($null -eq $sevenPct -or $F['seven_segment']) { continue }
                if (-not $F['seven_label']) { $top = "${C_LABEL}$($L['seven_day'])${R}" }
                $top = Add-Bar $top (Get-FitBar $sevenPct $Wd['seven_day']); $bot = Get-Paren (Format-PctText $sevenPct)
                if (-not $F['resets']) { $bot += $sevenTail }
            }
            'fable' {
                if ($F['fable_segment']) { continue }
                if ($F['fable_label']) { } elseif ($F['fable_short']) { $top = "${C_LABEL}$($fableLabel.Substring(0, ([char]::IsHighSurrogate($fableLabel, 0) ? 2 : 1)))${R}" } else { $top = "${C_LABEL}${fableLabel}${R}" }
                if ($null -ne $fablePct) { $top = Add-Bar $top (Get-FitBar $fablePct $fableWidth); $bot = Get-Paren (Format-PctText $fablePct) }
                else { $top = Add-Bar $top (Get-FitBar 0 $fableWidth); $bot = Get-Paren 'n/a' }
            }
        }
        if (-not ($top + $bot)) { continue }
        $script:segTop.Add($top); $script:segBot.Add($bot)
    }
}
# flat: one row, "top bot" per segment. stacked: two rows, each segment padded to max(top,bot) so columns align.
function Assemble-Flat {
    $parts = for ($i = 0; $i -lt $segTop.Count; $i++) { $t = $segTop[$i]; $b = $segBot[$i]; if ($t -and $b) { "$t $b" } else { "$t$b" } }
    $script:row1 = $parts -join (Get-Sep); $script:row2 = ''
}
function Assemble-Stacked {
    $r1 = @(); $r2 = @()
    for ($i = 0; $i -lt $segTop.Count; $i++) {
        $t = $segTop[$i]; $b = $segBot[$i]; $wt = Get-Cells $t; $wb = Get-Cells $b; $w = [math]::Max($wt, $wb)
        $r1 += $t + (' ' * ($w - $wt)); $r2 += $b + (' ' * ($w - $wb))
    }
    $script:row1 = $r1 -join (Get-Sep); $script:row2 = $r2 -join (Get-Sep)
    # Claude Code trims leading whitespace per row; pad row starts with U+2800 (renders blank, counts one cell).
    $script:row1 = [regex]::Replace($script:row1, '^ +', { param($m) [string]::new([char]0x2800, $m.Length) })
    $script:row2 = [regex]::Replace($script:row2, '^ +', { param($m) [string]::new([char]0x2800, $m.Length) })
}

# ---- fit pipeline: try flat then stacked at each stage; stop at the first that fits ----
function Emit { [Console]::WriteLine($script:row1); if ($script:row2) { [Console]::WriteLine($script:row2) }; exit 0 }
function Test-Fits { return ((Get-Cells $script:row1) -le $budget) }
function Try-Layouts { Build; Assemble-Flat; if (Test-Fits) { return $true }; if ($fitRows -ge 2) { Assemble-Stacked; if (Test-Fits) { return $true } }; return $false }
function Pad-Rows {
    $n = Get-Cells $script:row1; if ($n -lt $budget) { $script:row1 += ' ' * ($budget - $n) }
    if ($script:row2) { $n = Get-Cells $script:row2; if ($n -lt $budget) { $script:row2 += ' ' * ($budget - $n) } }
}

$columns = 0
if ($env:COLUMNS -match '^\d+$') { $columns = [int]$env:COLUMNS }
# Native Windows without COLUMNS: the attached console's visible width (0 when no console is attached).
if ($columns -le 0) { try { $columns = [Console]::WindowWidth } catch { $columns = 0 } }
if ($columns -le 0) { Build; Assemble-Flat; Emit }
$budget = [math]::Max(1, $columns - $STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS - $fitReserve)
# Stage 1: full bars.
if (Try-Layouts) { Emit }
# Stage 2: shrink bars uniformly. Walk the shared ratio down one cell at a time (stacked cells are bounded by their
# value row, so a bar cell does not always buy a column) and stop at the first ratio that fits or breaks the floor.
$widths = @(foreach ($s in $segList) {
    switch ($s) {
        'context' { $Wd['context'] }
        'disk' { if ($null -ne $diskPct) { $Wd['disk'] } }
        'tmp' { if ($null -ne $tmpPct) { $Wd['tmp'] } }
        'five_hour' { if ($null -ne $fivePct) { $Wd['five_hour'] } }
        'seven_day' { if ($null -ne $sevenPct) { $Wd['seven_day'] } }
        'fable' { $Wd['fable'] }
    }
})
$total = ($widths | Measure-Object -Sum).Sum
# Largest shared ratio in [floor, full] whose layout fits; fits is monotonic in the ratio, so binary search.
function Shrink-Layout([string]$layout) {
    $lo = 1; $hi = $total; $best = $null
    # A bar configured below the floor is exempt from it (it shrinks proportionally, minimum one cell).
    foreach ($w in $widths) { if ($w -lt $minBarCells) { continue }; $need = [int][math]::Ceiling($minBarCells * $total / $w); if ($need -gt $lo) { $lo = $need } }
    if ($lo -gt $hi) { $script:scaleNum = 1; $script:scaleDen = 1; return $false }
    $script:scaleDen = $total
    while ($lo -le $hi) {
        $mid = [int][math]::Floor(($lo + $hi) / 2); $script:scaleNum = $mid
        Build; if ($layout -eq 'flat') { Assemble-Flat } else { Assemble-Stacked }
        if (Test-Fits) { $best = $mid; $lo = $mid + 1 } else { $hi = $mid - 1 }
    }
    if ($null -eq $best) { $script:scaleNum = 1; $script:scaleDen = 1; return $false }
    $script:scaleNum = $best; Build; if ($layout -eq 'flat') { Assemble-Flat } else { Assemble-Stacked }; return $true
}
if ($total -gt 0) {
    if (Shrink-Layout 'flat') { Pad-Rows; Emit }
    if ($fitRows -ge 2 -and (Shrink-Layout 'stacked')) { Pad-Rows; Emit }
}
# Stage 3 (two rows only): keep the bars. Walk the ladder with bars at the best size that fits each step.
if ($fitRows -ge 2 -and $total -gt 0) {
    foreach ($step in $ladder) { $script:F[$step] = $true; if (Shrink-Layout 'stacked') { Pad-Rows; Emit } }
    $script:F = @{}
}
# Stage 4: bars gone; percentages carry the heat colour instead.
$script:scaleNum = 1; $script:scaleDen = 1; $script:barsOff = $true
if (Try-Layouts) { Pad-Rows; Emit }
# Stage 5: exclusion ladder again without bars, one step at a time, re-measured after each.
foreach ($step in $ladder) { $script:F[$step] = $true; if (Try-Layouts) { Pad-Rows; Emit } }
# Floor: nothing left to give; Claude Code truncates the overflow.
Build; Assemble-Flat; Emit

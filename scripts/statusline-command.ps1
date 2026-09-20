#!/usr/bin/env pwsh
# Claude Code statusline — PowerShell 7+ port of statusline-command.sh
# Feature-parity: RGB gradient bars, sub-pixel precision, disk/tmp/rate-limit/drift sections.

param(
    [Alias('r')][switch]$RefreshFable,
    [Alias('h')][switch]$Help
)

function Usage {
    'Usage: statusline-command.ps1 [-h|--help] [-r|--refresh-fable]'
}

if ($Help) { Usage; exit 0 }

# Claude Code on Windows requires Git Bash. Reuse canonical renderer so both
# entry points share validation, configuration, cache, and OAuth behavior.
$bash = Get-Command bash -ErrorAction SilentlyContinue
if ($bash) {
    $renderer = Join-Path $PSScriptRoot 'statusline-command.sh'
    if ($RefreshFable) { & $bash.Source $renderer --refresh-fable; exit $LASTEXITCODE }
    $stdin = [Console]::In.ReadToEnd()
    $stdin | & $bash.Source $renderer
    exit $LASTEXITCODE
}

if ($RefreshFable) {
    [Console]::Error.WriteLine('Fable refresh requires Git Bash when using the PowerShell entry point.')
    exit 1
}

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
if ($PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 2) {
    $PSStyle.OutputRendering = [System.Management.Automation.OutputRendering]::Ansi
}

$input_data = [Console]::In.ReadToEnd()

$ESC     = [char]27
$R       = "$ESC[0m"
$C_MODEL = "$ESC[1;38;2;86;182;194m"   # steel-blue bold
$C_LABEL = "$ESC[38;5;240m"             # dim gray labels
$C_SEP   = "$ESC[38;5;237m"             # separator pipe
$C_VAL   = "$ESC[38;5;243m"             # dim value text
$C_EMPTY = "$ESC[38;5;59m"              # medium gray empty cells

$PARTIAL = @('', '▏', '▎', '▍', '▌', '▋', '▊', '▉')

function Get-CellColor([int]$pos) {
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

function Get-PctColor([int]$p) {
    if ($p -le 60) { return "$ESC[38;2;60;180;80m" }
    if ($p -le 80) { return "$ESC[38;2;200;160;0m" }
    return "$ESC[38;2;180;60;40m"
}

function Format-PctText([int]$p) {
    return "$(Get-PctColor $p)${p}%${R}"
}

# Format-DriftPctText — inverted thresholds (drift-high = good = green)
function Format-DriftPctText([int]$p) {
    if     ($p -ge 90) { $c = "$ESC[38;2;60;180;80m" }
    elseif ($p -ge 70) { $c = "$ESC[38;2;200;160;0m" }
    else               { $c = "$ESC[38;2;180;60;40m" }
    return "${c}${p}%${R}"
}

function Format-Bytes([long]$b) {
    if ($b -ge 1073741824) { return "{0:F1}G" -f ($b / 1073741824) }
    if ($b -ge 1048576)    { return "{0:F1}M" -f ($b / 1048576) }
    if ($b -ge 1024)       { return "{0:F1}K" -f ($b / 1024) }
    return "${b}B"
}

# Get-Bar — when -Inverted is 1, per-cell gradient is reversed (left=red, right=green).
function Get-Bar([int]$pct, [int]$width = 20, [int]$inverted = 0) {
    $eighths    = [int]($pct * $width * 8 / 100)
    $full       = [int]($eighths / 8)
    $partIdx    = $eighths % 8
    $emptyStart = $full + $(if ($partIdx -gt 0) { 1 } else { 0 })
    $out = "["
    for ($i = 0; $i -lt $full -and $i -lt $width; $i++) {
        if ($inverted -eq 1) {
            $pos = 100 - [int]($i * 100 / $width)
        } else {
            $pos = [int]($i * 100 / $width)
        }
        $out += "$(Get-CellColor $pos)█"
    }
    if ($full -lt $width -and $partIdx -gt 0) {
        if ($inverted -eq 1) {
            $pos = 100 - [int]($full * 100 / $width)
        } else {
            $pos = [int]($full * 100 / $width)
        }
        $out += "$(Get-CellColor $pos)$($PARTIAL[$partIdx])"
    }
    if ($emptyStart -lt $width) {
        $out += $C_EMPTY
        $out += '░' * ($width - $emptyStart)
    }
    $out += "${R}]"
    return $out
}

function Get-Sep { return "${C_SEP} ● ${R}" }

# Parse JSON — no jq needed
$j       = $input_data | ConvertFrom-Json
$model   = if ($j.model.display_name) { $j.model.display_name } else { "Claude" }
$usedPct = $j.context_window.used_percentage
$totalIn = $j.context_window.total_input_tokens
$ctxSize = $j.context_window.context_window_size
$rl5h    = $j.rate_limits.five_hour.used_percentage
$rl7d    = $j.rate_limits.seven_day.used_percentage
$sessionId = $j.session_id

# drift quotient — independent co-agent coherence score for this session
$driftScore = $null
$driftTag = 'baseline'
$driftProvider = ''
if ($sessionId) {
    $driftFile = Join-Path $HOME ".claude/state/drift/$sessionId.jsonl"
    if (Test-Path $driftFile) {
        $last = Get-Content $driftFile -Tail 30 -ErrorAction SilentlyContinue |
            ForEach-Object { try { $_ | ConvertFrom-Json } catch {} } |
            Where-Object { $_ -and $_.kind -eq 'score' } |
            Select-Object -Last 1
        if ($last) {
            $driftScore = [int]$last.score
            $driftTag = [string]$last.tag
            if ($last.PSObject.Properties['provider']) {
                $driftProvider = [string]$last.provider
            }
        }
    }
}

$out = "${C_MODEL}${model}${R}"

# Current directory
$_cwd = $PWD.Path -replace [regex]::Escape($HOME), '~'
$_cwd = $_cwd -replace '\\', '/'
if ($_cwd.Length -gt 30) {
    $parts = $PWD.Path -split '[/\\]' | Where-Object { $_ -ne '' }
    $_cwd = if ($parts.Count -ge 2) { "…/$($parts[-2])/$($parts[-1])" } else { "/$($parts[-1])" }
}
$out += "$(Get-Sep)${C_VAL}${_cwd}${R}"

# Context window
$out += Get-Sep
$out += "${C_LABEL}ctx${R} "
if ($null -ne $usedPct -and $ctxSize -gt 0) {
    $ui   = [int][math]::Round($usedPct)
    $out += "$(Get-Bar $ui 20) ${C_VAL}$(Format-Bytes $totalIn)${R}/${C_VAL}$(Format-Bytes $ctxSize)${R} ($(Format-PctText $ui))"
} else {
    $out += Get-Bar 0 20
}

# Disk space — platform-aware
if ($IsWindows) {
    $drive = Get-PSDrive C -ErrorAction SilentlyContinue
    if ($drive -and ($drive.Used + $drive.Free) -gt 0) {
        $total = $drive.Used + $drive.Free
        $dp    = [int]($drive.Used * 100 / $total)
        $out  += "$(Get-Sep)${C_LABEL}disk${R} $(Get-Bar $dp 15) ${C_VAL}$(Format-Bytes ([long]$drive.Free))${R} free"
    }
} else {
    # macOS / Linux
    $dfOut = (df -k / 2>$null | Select-Object -Last 1)
    if ($dfOut) {
        $parts = ($dfOut -split '\s+')
        $dt = [long]$parts[1]; $da = [long]$parts[3]
        if ($dt -gt 0) {
            $dp   = [int](($dt - $da) * 100 / $dt)
            $out += "$(Get-Sep)${C_LABEL}disk${R} $(Get-Bar $dp 15) ${C_VAL}$(Format-Bytes ($da * 1024))${R} free"
        }
    }
    $tfOut = (df -k /tmp 2>$null | Select-Object -Last 1)
    $tmpDev = if ($tfOut) { ($tfOut -split '\s+')[0] } else { '' }
    if ($tfOut -and $tmpDev -eq 'tmpfs') {
        $parts = ($tfOut -split '\s+')
        $tt = [long]$parts[1]; $ta = [long]$parts[3]
        if ($tt -gt 0) {
            $tp   = [int](($tt - $ta) * 100 / $tt)
            $out += "$(Get-Sep)${C_LABEL}/tmp${R} $(Get-Bar $tp 15) ${C_VAL}$(Format-Bytes ($ta * 1024))${R} free"
        }
    }
}

# Rate limits (hidden when absent — Claude.ai subscribers only)
if ($null -ne $rl5h) {
    $v    = [int][math]::Round($rl5h)
    $out += "$(Get-Sep)${C_LABEL}5h${R} $(Get-Bar $v 12) ($(Format-PctText $v))"
}
if ($null -ne $rl7d) {
    $v    = [int][math]::Round($rl7d)
    $out += "$(Get-Sep)${C_LABEL}7d${R} $(Get-Bar $v 12) ($(Format-PctText $v))"
}

# drift quotient block — inverted bar (high = good = green-filled)
# ◆ marker = Anthropic Haiku primary; ◇ marker = Ollama fallback.
# Bar is 10 cells (compact) — tag and percentage trail to the right.
$out += Get-Sep
$out += "${C_LABEL}drift${R} "
if ($null -ne $driftScore) {
    $provMarker = switch ($driftProvider) {
        'groq'      { '⬢' }
        'gemini'    { '◉' }
        'openai'    { '◈' }
        'ollama'    { '◇' }
        default     { '·' }
    }
    $out += "$(Get-Bar $driftScore 10 1) ${C_VAL}(${driftTag}${provMarker})${R} ($(Format-DriftPctText $driftScore))"
} else {
    $out += "$(Get-Bar 100 10 1) ${C_VAL}(baseline)${R}"
}

[Console]::WriteLine($out)

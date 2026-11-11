#!/usr/bin/env pwsh
# Reset-toggle constants contract (PowerShell side): same cases as tests/test-constants.sh against constants.ps1.
param(
    [Alias('h')][switch]$Help
)

function Usage { 'Usage: test-constants.ps1 [-h|--help]' }
if ($Help) { Usage; exit 0 }
$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'config/constants.ps1')
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }
function Vis([string]$s) { $s.Replace([string][char]27, '<ESC>').Replace([string][char]7, '<BEL>') }

# Values.
if ($RESET_TIME_GLYPH_CLOCKWISE_OPEN_CIRCLE_ARROW -cne '↻') { Fail 'reset glyph' }
if ($RESETS_CLICK_GLYPH_SHOWN_SQUARED_MINUS_THEN_LEFT_POINTING_SMALL_TRIANGLE -cne '⊟◂') { Fail 'shown glyph' }
if ($RESETS_CLICK_GLYPH_HIDDEN_SQUARED_PLUS_THEN_LEFT_POINTING_SMALL_TRIANGLE -cne '⊞◂') { Fail 'hidden glyph' }
if ($WEEKDAY_CODES_SUNDAY_FIRST_SU_M_T_W_R_F_SA.Count -ne 7 -or ($WEEKDAY_CODES_SUNDAY_FIRST_SU_M_T_W_R_F_SA -join ' ') -cne 'SU M T W R F SA') { Fail 'day codes' }
if ($RESETS_COUNTDOWN_STATUS_LINE_REFRESH_INTERVAL_SECONDS -ne 60) { Fail 'refresh interval' }
if ($RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R -cne 'ctrl+x r') { Fail 'default chord' }

# Toggle URL: full match, slot 5h|7d, optional profile (PASS on the negatives = rejected).
$url = $RESETS_TOGGLE_URL_SCHEME_TOGGLE_SLOT_5H_OR_7D_OPTIONAL_PROFILE_FULL_MATCH
foreach ($ok in 'claude-statusline://toggle?slot=5h', 'claude-statusline://toggle/?slot=7d', 'claude-statusline://toggle?slot=5h&profile=work-2.a_b') {
    if ($ok -cnotmatch $url) { Fail "url rejected: $ok" }
}
foreach ($bad in 'claude-statusline://toggle?slot=1h', 'claude-statusline://toggle?slot=5h&profile=', 'claude-statusline://toggle?slot=5h&profile=a/b',
                 'claude-statusline://toggle?slot=5h&x=1', 'claude-statusline://toggle?slot=5h;ls', 'xclaude-statusline://toggle?slot=5h',
                 "claude-statusline://toggle?slot=5h`ntail", 'other://toggle?slot=5h', 'claude-statusline://toggle') {
    if ($bad -cmatch $url) { Fail "negative: url accepted: $bad" }
}

# OSC 8: the whole sequence matches in both terminators; SGR and unterminated forms do not.
$osc = $ANSI_OSC8_HYPERLINK_SEQUENCE_ESC_RIGHT_BRACKET_8_PARAMS_URI_TERMINATED_BY_ST_OR_BEL
$esc = [string][char]27; $bel = [string][char]7
foreach ($seq in "$esc]8;id=bsl-5h;claude-statusline://toggle?slot=5h$esc\", "$esc]8;;$esc\", "$esc]8;id=bsl-7d;claude-statusline://toggle?slot=7d&profile=w$bel", "$esc]8;;$bel") {
    $m = [regex]::Match($seq, $osc)
    if (-not $m.Success -or $m.Value -cne $seq) { Fail "osc8 not matched whole: $(Vis $seq)" }
}
foreach ($bad in "$esc[31m", "$esc]8;id=x;uri-unterminated", 'plain') {
    if ($bad -match $osc) { Fail "negative: osc8 matched: $(Vis $bad)" }
}
# Stripping a whole styled slot leaves only its text.
$s = "$esc[2mfive $esc]8;id=bsl-5h;claude-statusline://toggle?slot=5h$esc\[25%]$esc]8;;$esc\$esc[0m"
if (($s -replace $osc, '') -cne "$esc[2mfive [25%]$esc[0m") { Fail "strip: $(Vis ($s -replace $osc, ''))" }

# Twin parity: the same constant names in both files.
$namesSh = (Get-Content (Join-Path $root 'config/constants.sh') | ForEach-Object { if ($_ -match '^([A-Z0-9_]+)=') { $Matches[1] } } | Sort-Object) -join ' '
$namesPs1 = (Get-Content (Join-Path $root 'config/constants.ps1') | ForEach-Object { if ($_ -match '^\$([A-Z0-9_]+) = ') { $Matches[1] } } | Sort-Object) -join ' '
if ($namesSh -cne $namesPs1) { Fail "constants.sh and constants.ps1 differ:`n sh : $namesSh`n ps1: $namesPs1" }

'ok'

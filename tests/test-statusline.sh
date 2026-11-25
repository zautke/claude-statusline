#!/usr/bin/env bash
set -euo pipefail

Usage() {
  printf 'Usage: %s [-h|--help]\n' "${0##*/}"
}

case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
  '') ;;
  *) Usage >&2; exit 2 ;;
esac

# The assertions below measure with ${#var}, which counts bytes in a byte locale (empty under ssh, C, POSIX): run this
# script itself in a UTF-8 locale that works here. Renders under other locales are asserted explicitly further down.
_g='█'; for _l in '' C.UTF-8 en_US.UTF-8; do [[ -z $_l ]] || export LC_ALL=$_l; ((${#_g}==1))&&break; done
((${#_g}==1)) || { printf 'no working UTF-8 locale for the test itself\n' >&2; exit 1; }
utf8_locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CLAUDE_CONFIG_DIR="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
export CLAUDE_STATUSLINE_NO_LIVE_COLS=1
# Pinned "now" for the reset-time countdown (B-spec payload fixtures).
export CLAUDE_STATUSLINE_NOW=1794427200
mkdir -p "$HOME/work" "$CLAUDE_CONFIG_DIR" "$XDG_CACHE_HOME/claude-statusline"
# The cwd segment renders $PWD; pin it so ladder stages land on the same widths on every machine.
cd "$HOME/work"

cat >"$CLAUDE_CONFIG_DIR/statusline.json" <<'JSON'
{
  "segments": ["five_hour", "fable", "seven_day"],
  "labels": {"five_hour": "five", "fable": "story", "seven_day": "week"},
  "widths": {"five_hour": 3, "fable": 5, "seven_day": 4}
}
JSON

# Fresh cache: a fixed fetched_at goes stale after max_stale_seconds and would turn every Fable check into n/a.
printf '{"used_percentage":42,"resets_at":"2026-09-21T00:00:00Z","model":"Fable","fetched_at":%s}\n' "$(date +%s)" \
  >"$XDG_CACHE_HOME/claude-statusline/fable.json"

payload='{"model":{"display_name":"Claude"},"context_window":{"used_percentage":25,"total_input_tokens":50400,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1794435180},"seven_day":{"used_percentage":30,"resets_at":1794794400}}}'
plain=$(printf '%s' "$payload" | NO_COLOR=1 CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh")

[[ "$plain" == *"five ["* ]] || { printf 'missing custom five-hour label\n' >&2; exit 1; }
[[ "$plain" == *"story ["* ]] || { printf 'missing Fable segment\n' >&2; exit 1; }
[[ "$plain" == *"week ["* ]] || { printf 'missing custom seven-day label\n' >&2; exit 1; }
[[ "$plain" != *"ctx ["* ]] || { printf 'hidden context segment rendered\n' >&2; exit 1; }

five=${plain#*five [}; five=${five%%]*}
story=${plain#*story [}; story=${story%%]*}
week=${plain#*week [}; week=${week%%]*}
[[ ${#five} -eq 3 ]] || { printf 'five-hour width mismatch: %s\n' "${#five}" >&2; exit 1; }
[[ ${#story} -eq 5 ]] || { printf 'Fable width mismatch: %s\n' "${#story}" >&2; exit 1; }
[[ ${#week} -eq 4 ]] || { printf 'seven-day width mismatch: %s\n' "${#week}" >&2; exit 1; }
[[ "$plain" == *"five"*"story"*"week"* ]] || { printf 'segment order mismatch\n' >&2; exit 1; }

printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"
fallback=$(printf '%s' "$payload" | NO_COLOR=1 CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh")
[[ "$fallback" == *"Claude"*"ctx"*"5h"*"7d"*"Fable"* ]] || {
  printf 'invalid config did not fall back to defaults\n' >&2
  exit 1
}
[[ "$fallback" != *"drift"* ]] || { printf 'drift segment still rendered\n' >&2; exit 1; }

# Terminal fit: budget is COLUMNS minus Claude Code's status-area margin. Helpers count display cells per row.
. "$ROOT/config/constants.sh"; margin=$STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS
# Strip SGR and OSC 8 hyperlink sequences: what the terminal actually draws.
strip() { sed -E $'s/\033\\[[0-9;]*m//g' <<<"$1" | sed -E "s/$ANSI_OSC8_HYPERLINK_SEQUENCE_ESC_RIGHT_BRACKET_8_PARAMS_URI_TERMINATED_BY_ST_OR_BEL//g"; }
cells() { strip "$1" | jq -Rr length; }
render() { printf '%s' "$payload" | COLUMNS=$1 NO_COLOR=1 CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh"; }
rows() { printf '%s\n' "$1" | wc -l | tr -d ' '; }
row() { sed -n "${2}p" <<<"$1"; }
assert_fit() { # $1=label $2=output $3=budget: every row <= budget, stacked rows equal length
  local r n; while IFS= read -r r; do n=$(cells "$r"); ((n<=$3)) || { printf '%s: row overflows budget %s: %s\n' "$1" "$3" "$n" >&2; exit 1; }; done <<<"$2"
  if (($(rows "$2")==2)); then [[ $(cells "$(row "$2" 1)") -eq $(cells "$(row "$2" 2)") ]] || { printf '%s: stacked rows differ in width\n' "$1" >&2; exit 1; }; fi
}
# Wide terminal: flat, untouched, unpadded.
wide=$(render 400)
# Mask the live disk value: free space can change between two renders.
mask() { sed -E "s/$DISK_FREE_ANY_NUMBER_THEN_UNIT_THEN_SPACE_FREE/N free/" <<<"$1"; }
[[ "$(mask "$wide")" == "$(mask "$fallback")" ]] || { printf 'wide terminal changed the render\n' >&2; exit 1; }
full_cells=$(cells "$fallback")
# Stacked (opt-in rows:2): a width that fits two rows at full bars but not one row. Separators align, bars untouched.
printf '{"fit":{"rows":2}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
stk=$(render $((full_cells-10+margin)))
[[ $(rows "$stk") -eq 2 ]] || { printf 'expected stacked layout, got %s rows\n' "$(rows "$stk")" >&2; exit 1; }
assert_fit stacked "$stk" $((full_cells-10))
r1=$(row "$stk" 1); r2=$(row "$stk" 2)
[[ "$r1" == *"ctx [░░░░░░░░░░░░]"* || "$r1" == *"ctx [███░░░░░░░░░]"* ]] || { printf 'stacked top row lost full ctx bar: %s\n' "$r1" >&2; exit 1; }
pos1=${r1%%●*}; pos2=${r2%%●*}
[[ ${#pos1} -eq ${#pos2} ]] || { printf 'separator misaligned between rows\n' >&2; exit 1; }
[[ "$r2" == *"50.4K/200K (25%)"* ]] || { printf 'stacked bottom row lost ctx values: %s\n' "$r2" >&2; exit 1; }
stk_cells=$(cells "$r1")
# Shrink: just under the stacked width, bars shrink but stay >= 5 and rows are padded to the budget.
shr=$(render $((stk_cells-6+margin)))
assert_fit shrink "$shr" $((stk_cells-6))
[[ $(cells "$(row "$shr" 1)") -eq $((stk_cells-6)) ]] || { printf 'shrunk rows not padded to budget\n' >&2; exit 1; }
ctxbar=${shr#*ctx [}; ctxbar=${ctxbar%%]*}
[[ ${#ctxbar} -lt 12 && ${#ctxbar} -ge 5 ]] || { printf 'ctx bar not shrunk into range: %s\n' "${#ctxbar}" >&2; exit 1; }
# Two rows keep the bars: at 90 columns the ladder has engaged (parentheses gone) but every bar is still drawn, >= 5 cells.
lad=$(render 90)
assert_fit ladder90 "$lad" $((90-margin))
[[ $(rows "$lad") -eq 2 && "$lad" == *"["* ]] || { printf 'bars dropped at 90 despite two rows: %s\n' "$lad" >&2; exit 1; }
fivebar=${lad#*five [}; fivebar=${fivebar%%]*}; [[ ${#fivebar} -ge 5 ]] || { printf 'bar below floor at 90\n' >&2; exit 1; }
[[ "$(row "$lad" 1)" == ⠀* || "$(row "$lad" 2)" == ⠀* ]] || { printf 'row leading pad is plain whitespace (Claude Code trims it)\n' >&2; exit 1; }
# Single row (default): bars drop first, then the ladder. At 60 columns parentheses and Fable are gone.
printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"
lad60=$(render 60)
assert_fit ladder60 "$lad60" $((60-margin))
[[ "$lad60" != *"["* && "$lad60" != *"("* ]] || { printf 'bars or parentheses survived at 60 single-row: %s\n' "$lad60" >&2; exit 1; }
[[ "$lad60" == *"25%"* ]] || { printf 'ctx percentage dropped at 60: %s\n' "$lad60" >&2; exit 1; }
# Ladder order: the Fable segment leaves before 7d and 5h do, so if 7d or 5h is gone Fable must be gone too.
if [[ "$lad60" != *"30%"* || "$lad60" != *"20%"* ]]; then [[ "$lad60" != *"42%"* ]] || { printf 'ladder order violated at 60: %s\n' "$lad60" >&2; exit 1; }; fi
printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"
# A bar configured below the floor must not block shrinking of the others.
printf '{"widths":{"fable":3},"fit":{"rows":1}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
small=$(render $((full_cells-9-20+margin)))
[[ "$small" == *"ctx ["* ]] || { printf 'sub-floor bar blocked shrinking: %s\n' "$small" >&2; exit 1; }
# Wide glyphs: a CJK label counts two cells each, so the fitted row stays within budget by display width.
printf '{"labels":{"five_hour":"五時間"},"fit":{"rows":1}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
wide=$(render 120)
wcells=$(python3 -c 'import sys,unicodedata; s=sys.stdin.read().rstrip("\n"); print(sum(2 if unicodedata.east_asian_width(c) in "WF" else 1 for c in s))' <<<"$wide" 2>/dev/null || cells "$wide")
[[ $wcells -le $((120-margin)) ]] || { printf 'wide label overflowed by display width: %s\n' "$wcells" >&2; exit 1; }
[[ "$wide" == *"五時間"* ]] || { printf 'wide label missing\n' >&2; exit 1; }
# Floor: 30 columns must not crash and must emit at most 2 rows.
flr=$(render 30); [[ $(rows "$flr") -le 2 ]] || { printf 'floor emitted too many rows\n' >&2; exit 1; }
# Default (rows:1) never stacks.
printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"
one=$(render $((full_cells-10+margin)))
[[ $(rows "$one") -eq 1 ]] || { printf 'fit.rows=1 still stacked\n' >&2; exit 1; }
assert_fit rows1 "$one" $((full_cells-10))
# Reserve shrinks the budget.
printf '{"fit":{"reserve":20,"rows":1}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
res=$(render $((full_cells-10+margin+20)))
assert_fit reserve "$res" $((full_cells-10))
[[ "$res" != "$fallback" ]] || { printf 'reserve not applied\n' >&2; exit 1; }
# Custom ladder: only ctx_label, so at 90 the ctx label goes and nothing else is touched.
printf '{"fit":{"rows":1,"ladder":["ctx_label"]}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
cl=$(render 90)
[[ "$cl" != *"ctx"* && "$cl" == *"(25%)"* && "$cl" == *"Fable"* ]] || { printf 'custom ladder not honoured: %s\n' "$cl" >&2; exit 1; }
# Legacy config naming the retired drift segment stays valid; drift is skipped, custom labels still apply.
printf '{"segments":["model","five_hour","drift"],"labels":{"five_hour":"legacy"}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
legacy=$(render 400)
[[ "$legacy" == *"legacy ["* && "$legacy" != *"drift"* ]] || { printf 'legacy drift config rejected or rendered: %s\n' "$legacy" >&2; exit 1; }
# A boolean in a numeric fit field rejects the whole config (jq // would otherwise treat false as absent).
printf '{"labels":{"five_hour":"custom"},"fit":{"rows":false}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
boolcfg=$(render 400)
[[ "$boolcfg" != *"custom"* ]] || { printf 'boolean fit.rows did not reject the config\n' >&2; exit 1; }
# Invalid ladder entry rejects the config; defaults resume (single row, default ladder keeps Fable at 90).
printf '{"fit":{"ladder":["bogus"],"rows":2}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
bad=$(render 90)
[[ $(rows "$bad") -eq 1 && "$bad" == *"Fable"* ]] || { printf 'invalid ladder did not fall back to defaults: %s\n' "$bad" >&2; exit 1; }
[[ "$fallback" != *$ANSI_ESCAPE_SEQUENCE_START* ]] || { printf 'NO_COLOR ignored: escape sequences in output\n' >&2; exit 1; }
# Negatives on the rest of the schema: each rejects the whole file (PASS = defaults render, custom label absent).
for bad_cfg in '{"segments":["model","model"],"labels":{"five_hour":"custom"}}' '{"segments":["nope"],"labels":{"five_hour":"custom"}}' \
  '{"labels":{"five_hour":7}}' '{"widths":{"fable":0},"labels":{"five_hour":"custom"}}' '{"widths":{"fable":2.5},"labels":{"five_hour":"custom"}}' \
  '{"fable":{"refresh_seconds":10},"labels":{"five_hour":"custom"}}' \
  '{"resets":"yes","labels":{"five_hour":"custom"}}' '{"resets":1,"labels":{"five_hour":"custom"}}' \
  '{"resets_format":"Clock","labels":{"five_hour":"custom"}}' '{"resets_format":"relative","labels":{"five_hour":"custom"}}' \
  '{"resets_format":["clock"],"labels":{"five_hour":"custom"}}' '{"fit":{"ladder":["Resets"]},"labels":{"five_hour":"custom"}}'; do
  printf '%s' "$bad_cfg" >"$CLAUDE_CONFIG_DIR/statusline.json"; o=$(render 400)
  [[ "$o" != *custom* && "$o" == *Claude*ctx*5h* ]] || { printf 'invalid config accepted: %s -> %s\n' "$bad_cfg" "$o" >&2; exit 1; }
done
# Positive control for the negatives above: the valid forms of the same keys keep the config.
printf '%s' '{"resets":true,"resets_format":"countdown","fit":{"ladder":["resets"]},"labels":{"five_hour":"custom"}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
[[ "$(render 400)" == *custom* ]] || { printf 'valid resets config rejected\n' >&2; exit 1; }

# ---- reset times on the 5h/7d slots: formats, glyph, placement. Two slots only, 400 columns (flat, unfitted). ----
rp() { printf '{"rate_limits":{"five_hour":{"used_percentage":20%s},"seven_day":{"used_percentage":30%s}}}' "${1:+,\"resets_at\":$1}" "${2:+,\"resets_at\":$2}"; }
rr() { # $1 extra config keys, $2 payload, $3 columns (default 400)
  printf '{"segments":["five_hour","seven_day"]%s}' "${1:+,$1}" >"$CLAUDE_CONFIG_DIR/statusline.json"
  printf '%s' "$2" | COLUMNS=${3:-400} NO_COLOR=1 TZ=UTC CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh"
}
want() { [[ $2 == "$3" ]] || { printf 'resets %s: got [%s] want [%s]\n' "$1" "$2" "$3" >&2; exit 1; }; }
B5='5h [██░░░░░░░░░░] (20%)' B7='7d [████░░░░░░░░] (30%)' cd_='"resets_format":"countdown"'
fix=$(rp 1794435180 1794794400)
want countdown "$(rr "$cd_" "$fix")" "$B5 ↻2h13m ⊟◂ ● $B7 ↻4d6h ⊟◂"
want clock "$(rr '' "$fix")" "$B5 ↻22:13 ⊟◂ ● $B7 ↻M16|02:00 ⊟◂"
want clock-explicit "$(rr '"resets":true,"resets_format":"clock"' "$fix")" "$B5 ↻22:13 ⊟◂ ● $B7 ↻M16|02:00 ⊟◂"
# Day code, day of month and HH:MM: Sunday 2026-11-15 00:00 UTC plus k days and k hours, one epoch per weekday.
codes=(Su M T W R F Sa)
for k in 0 1 2 3 4 5 6; do
  want "day $k" "$(rr '' "$(rp '' $((1794700800+k*86400+k*3600)))")" "$B5 ⊟◂ ● $B7 ↻${codes[k]}$((15+k))|0$k:00 ⊟◂"
done
# Round-up: :59:59 reaches the next minute (and Saturday 23:59:59 the next day); an exact minute stays.
want roundup "$(rr '' "$(rp 1794751199 1795305599)")" "$B5 ↻14:00 ⊟◂ ● $B7 ↻Su22|00:00 ⊟◂"
want exact "$(rr '' "$(rp 1794751140 '')")" "$B5 ↻13:59 ⊟◂ ● $B7 ⊟◂"
# Countdown minutes, a sub-minute remainder rounding up, and a reset already past.
want minutes "$(rr "$cd_" "$(rp 1794427500 1794427261)")" "$B5 ↻5m ⊟◂ ● $B7 ↻2m ⊟◂"
# Countdown thresholds: 59m stays minutes, 60m turns into hours, 1439m stays hours, 1440m turns into days.
want bounds-hour "$(rr "$cd_" "$(rp 1794430740 1794430800)")" "$B5 ↻59m ⊟◂ ● $B7 ↻1h0m ⊟◂"
want bounds-day "$(rr "$cd_" "$(rp 1794513540 1794513600)")" "$B5 ↻23h59m ⊟◂ ● $B7 ↻1d0h ⊟◂"
# Out of range (a millisecond epoch, 1e300, negative): no reset text, each slot on its own, both formats.
for x in '' "$cd_"; do
  want "out-of-range [$x]" "$(rr "$x" "$(rp 1794435180000 1e300)")" "$B5 ⊟◂ ● $B7 ⊟◂"
  if [[ -n $x ]]; then w='↻4d6h'; else w='↻M16|02:00'; fi
  want "out-of-range-one [$x]" "$(rr "$x" "$(rp -60 1794794400)")" "$B5 ⊟◂ ● $B7 $w ⊟◂"
done
want past "$(rr "$cd_" "$(rp 1794426600 '')")" "$B5 ↻0m ⊟◂ ● $B7 ⊟◂"
want off "$(rr '"resets":false' "$fix")" "$B5 ⊞◂ ● $B7 ⊞◂"
want off-countdown "$(rr '"resets":false,"resets_format":"countdown"' "$fix")" "$B5 ⊞◂ ● $B7 ⊞◂"
# Absent 5h reset time: glyph only on 5h, 7d intact. Absent 5h window: the 7d slot alone, still correct.
want no-five-reset "$(rr "$cd_" "$(rp '' 1794794400)")" "$B5 ⊟◂ ● $B7 ↻4d6h ⊟◂"
want no-five-window "$(rr "$cd_" '{"rate_limits":{"seven_day":{"used_percentage":30,"resets_at":1794794400}}}')" "$B7 ↻4d6h ⊟◂"
want non-number "$(rr "$cd_" '{"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":"soon"},"seven_day":{"used_percentage":30,"resets_at":null}}}')" "$B5 ⊟◂ ● $B7 ⊟◂"
# Stacked: reset text and glyph sit on the values row only; every separator column lines up.
stk2=$(rr "$cd_,\"fit\":{\"rows\":2}" "$fix" $((37+margin)))
[[ $(rows "$stk2") -eq 2 ]] || { printf 'resets stacked: expected 2 rows: %s\n' "$stk2" >&2; exit 1; }
s1=$(row "$stk2" 1) s2=$(row "$stk2" 2)
[[ $s1 != *↻* && $s1 != *⊟* && $s2 == *"(20%) ↻2h13m ⊟◂"*"(30%) ↻4d6h ⊟◂"* ]] || { printf 'resets stacked rows wrong:\n%s\n' "$stk2" >&2; exit 1; }
seps() { local s=$1 i o=; for ((i=0;i<${#s};i++)); do [[ ${s:i:1} == ● ]]&&o+="$i "; done; printf '%s' "$o"; }
[[ -n $(seps "$s1") && $(seps "$s1") == "$(seps "$s2")" ]] || { printf 'resets stacked separators misaligned: [%s] [%s]\n' "$(seps "$s1")" "$(seps "$s2")" >&2; exit 1; }
# Colour: the reset text and glyph carry the value colour (SGR 38;5;243).
printf '{"segments":["model","five_hour","seven_day"],%s}' "$cd_" >"$CLAUDE_CONFIG_DIR/statusline.json"
col=$(printf '%s' "$fix" | env -u NO_COLOR COLUMNS=400 CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh")
[[ $col == *$'\033[38;5;243m↻2h13m ⊟◂\033[0m'* && $col == *$'\033[38;5;243m↻4d6h ⊟◂\033[0m'* ]] || { printf 'resets colour: value SGR missing: %q\n' "$col" >&2; exit 1; }
# The whole coloured line, byte for byte; the ps1 twin asserts the same literal (model colour, bar gradient, SGR order).
E=$'\033'
want colour-line "$col" "${E}[1;38;5;75mClaude${E}[0m${E}[38;5;237m ● ${E}[0m${E}[38;5;240m5h${E}[0m [${E}[38;2;40;170;60m█${E}[38;2;68;169;51m█${E}[38;5;59m░░░░░░░░░░${E}[0m] (${E}[38;2;112;166;36m20%${E}[0m) ${E}[38;5;243m↻2h13m ⊟◂${E}[0m${E}[38;5;237m ● ${E}[0m${E}[38;5;240m7d${E}[0m [${E}[38;2;40;170;60m█${E}[38;2;68;169;51m█${E}[38;2;97;167;41m█${E}[38;2;130;165;30m█${E}[38;5;59m░░░░░░░░${E}[0m] (${E}[38;2;148;164;24m30%${E}[0m) ${E}[38;5;243m↻4d6h ⊟◂${E}[0m"
# ---- exclusion ladder map. Segments pinned (no /tmp) so every machine renders the same stages. ----
order=(resets disk_label ctx_int no_parens disk_int ctx_no_total no_free fable_short disk_value ctx_no_used fable_label fable_segment seven_label five_label ctx_label seven_segment five_segment)
# Countdown keeps the reset text independent of the machine's time zone.
pin='"segments":["model","cwd","context","disk","five_hour","seven_day","fable"],"resets_format":"countdown"'
floor() { local steps= s; for s in "$@"; do steps+=${steps:+,}"\"$s\""; done; printf '{%s,"fit":{"rows":1,"ladder":[%s]}}' "$pin" "$steps" >"$CLAUDE_CONFIG_DIR/statusline.json"; render 10; }
trim() { local s=$1; printf '%s' "${s%"${s##*[! ]}"}"; }
# The disk segment is always the 4th in the pinned order; mask its number so a free-space change between two renders
# does not fail a comparison. ponytail: a digit-count change (9.9G -> 10.0G) mid-run still shifts the widths by one.
# Per row, split on the bare separator dot: a stacked values row can open with U+2800 blanks directly before its first
# dot (no space), so ' ● ' would shift the fields; '●' keeps column 4 the disk on both rows. The disk bar's fill is
# masked as well, since a free-space change can move its percentage.
mask_disk() { awk -F '●' -v OFS='●' -v re="$DISK_SEGMENT_NUMBER_INTEGER_WITH_OPTIONAL_ONE_DECIMAL" 'NF>=4{gsub(re,"N",$4); gsub(/[█░]+/,"B",$4)}1' <<<"$1"; }

base=$(floor)
[[ $base =~ $DISK_FREE_ONE_DECIMAL_THEN_UNIT_THEN_SPACE_FREE ]] || { printf 'baseline lost the disk value: %s\n' "$base" >&2; exit 1; }
dnum=${BASH_REMATCH[1]} dunit=${BASH_REMATCH[2]}; dtok=$dnum$dunit
# Each step on its own: exactly its declared change to the bars-off baseline, nothing else.
expect_step() { # $1 step, $2 expected floor output
  [[ $2 != "$base" ]] || { printf 'ladder %s: expectation is a no-op on baseline: %s\n' "$1" "$base" >&2; exit 1; }
  local o; o=$(floor "$1"); [[ $(mask_disk "$o") == "$(mask_disk "$2")" ]] || { printf 'ladder %s: got [%s] want [%s]\n' "$1" "$o" "$2" >&2; exit 1; }
}
t=${base//(/}; t=${t//)/}
t2=${base// ↻2h13m ⊟◂/}; expect_step resets "${t2// ↻4d6h ⊟◂/}"
expect_step disk_label "${base//disk /}"
expect_step ctx_int "${base//50.4K\//50K/}"
expect_step no_parens "$t"
expect_step ctx_no_total "${base//\/200K/}"
expect_step no_free "${base// free/}"
expect_step fable_short "${base//Fable (/F (}"
expect_step disk_value "${base// $dtok free/}"
expect_step ctx_no_used "${base//50.4K\//}"
expect_step fable_label "${base//Fable (/(}"
expect_step fable_segment "${base// ● Fable (42%)/}"
expect_step seven_label "${base//7d (/(}"
expect_step five_label "${base//5h (/(}"
expect_step ctx_label "${base//ctx 50.4K/50.4K}"
expect_step seven_segment "${base// ● 7d (30%) ↻4d6h ⊟◂/}"
expect_step five_segment "${base// ● 5h (20%) ↻2h13m ⊟◂/}"
o=$(floor disk_int)
[[ $o =~ $DISK_FREE_INTEGER_THEN_UNIT_THEN_SPACE_FREE ]] || { printf 'ladder disk_int: no integer disk value: %s\n' "$o" >&2; exit 1; }
inum=${BASH_REMATCH[1]}
[[ ${BASH_REMATCH[2]} == "$dunit" ]] && awk -v a="$inum" -v b="$dnum" 'BEGIN{d=a-b; if (d<0) d=-d; exit !(d<=0.55)}' &&
  [[ ${o/" $inum$dunit free"/" $dtok free"} == "$base" ]] || { printf 'ladder disk_int: got [%s] from [%s]\n' "$o" "$base" >&2; exit 1; }
# Progressive order: the k-step floor needs L_k cells; at L_k + margin columns the default ladder shows exactly the
# first k steps, one column less shows k+1. Every step buys at least one cell.
floors=(); for ((k=0;k<=${#order[@]};k++)); do floors[k]=$(floor ${order[@]:0:k}); done
for ((k=0;k<${#order[@]};k++)); do
  (( $(cells "${floors[k+1]}") < $(cells "${floors[k]}") )) || { printf 'ladder step %s buys no cells\n' "${order[k]}" >&2; exit 1; }
done
printf '{%s,"fit":{"rows":1}}' "$pin" >"$CLAUDE_CONFIG_DIR/statusline.json"
for ((k=0;k<=${#order[@]};k++)); do
  lk=$(cells "${floors[k]}")
  at=$(trim "$(render $((lk+margin)))")
  [[ $(mask_disk "$at") == "$(mask_disk "${floors[k]}")" ]] || { printf 'ladder progression: at %s cols want %s steps [%s] got [%s]\n' $((lk+margin)) "$k" "${floors[k]}" "$at" >&2; exit 1; }
  if ((k<${#order[@]})); then
    below=$(trim "$(render $((lk+margin-1)))")
    [[ $(mask_disk "$below") == "$(mask_disk "${floors[k+1]}")" ]] || { printf 'ladder progression: at %s cols want %s steps [%s] got [%s]\n' $((lk+margin-1)) $((k+1)) "${floors[k+1]}" "$below" >&2; exit 1; }
  fi
done
printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"

# No URL-handler marker under $TMP/config, so the coloured line asserted earlier carries no link.
[[ $col != *$'\033]8'* ]] || { printf 'link without URL-handler marker\n' >&2; exit 1; }

# ---- Ctrl+click: OSC 8 links over the whole 5h and 7d slots. Colour on, outside tmux and WSL, marker present. ----
O=$'\033]8;' ST=$'\033\\'; C="$O;$ST"
lcfg() { mkdir -p "$1"; printf '%s' "$2" >"$1/statusline.json"; }
mark() { mkdir -p "$1/claude-statusline"; : >"$1/claude-statusline/url-handler"; }
lr() { # $1 config dir, $2 columns, then extra VAR=value env
  local d=$1 c=$2; shift 2
  printf '%s' "$payload" | env -u NO_COLOR -u TMUX -u WSL_DISTRO_NAME CLAUDE_CONFIG_DIR="$d" COLUMNS="$c" CLAUDE_STATUSLINE_DISABLE_REFRESH=1 "$@" ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh"
}
nlinks() { local s=$1 n=0; while [[ $s == *"${O}id="* ]]; do s=${s#*"${O}id="}; n=$((n+1)); done; printf '%s' $n; }
lhome=$HOME/.claude-t; mark "$lhome"; mark "$HOME/.claude"
flatcfg="{$cd_,\"segments\":[\"model\",\"five_hour\",\"seven_day\",\"fable\"]}"
lcfg "$lhome" "$flatcfg"; lcfg "$HOME/.claude" "$flatcfg"
O5="${O}id=bsl-5h;claude-statusline://toggle?slot=5h&profile=t$ST" O7="${O}id=bsl-7d;claude-statusline://toggle?slot=7d&profile=t$ST"
# Flat: the link opens before the label and closes after the glyph, before the separator.
lk=$(lr "$lhome" 400)
[[ $lk == *"$O5${E}[38;5;240m5h"*"⊟◂${E}[0m$C${E}[38;5;237m ● ${E}[0m$O7${E}[38;5;240m7d"*"⊟◂${E}[0m$C${E}[38;5;237m ● "* ]] || { printf 'link flat: %q\n' "$lk" >&2; exit 1; }
[[ $(nlinks "$lk") -eq 2 ]] || { printf 'link flat: want 2 links, got %s\n' "$(nlinks "$lk")" >&2; exit 1; }
# Default config dir ~/.claude: no profile parameter.
dl=$(lr "$HOME/.claude" 400)
[[ $dl == *"${O}id=bsl-5h;claude-statusline://toggle?slot=5h$ST"* && $dl == *"${O}id=bsl-7d;claude-statusline://toggle?slot=7d$ST"* && $dl != *profile=* ]] || { printf 'link default dir: %q\n' "$dl" >&2; exit 1; }
# Stacked: each row links both slots under the same id; padding stays outside the link; separators still align.
lcfg "$lhome" "{$cd_,\"segments\":[\"five_hour\",\"seven_day\"],\"fit\":{\"rows\":2}}"
ls2=$(lr "$lhome" $((37+margin)))
[[ $(rows "$ls2") -eq 2 ]] || { printf 'link stacked: expected 2 rows: %q\n' "$ls2" >&2; exit 1; }
l1=$(row "$ls2" 1) l2=$(row "$ls2" 2)
for r in "$l1" "$l2"; do
  [[ $r == *"$O5"*"$C"*"$O7"*"$C"* && $(nlinks "$r") -eq 2 && $r != *" $C"* ]] || { printf 'link stacked row: %q\n' "$r" >&2; exit 1; }
done
[[ $l2 == *"$C "* ]] || { printf 'link stacked: no padding after a link: %q\n' "$l2" >&2; exit 1; }
[[ -n $(seps "$(strip "$l1")") && $(seps "$(strip "$l1")") == "$(seps "$(strip "$l2")")" ]] || { printf 'link stacked separators misaligned\n' >&2; exit 1; }
# Fit regression: at every stage the linked render draws exactly what the unlinked one (TMUX) draws.
lcfg "$lhome" "{$cd_,\"segments\":[\"model\",\"cwd\",\"context\",\"disk\",\"five_hour\",\"seven_day\",\"fable\"],\"fit\":{\"rows\":2}}"
wf=$(cells "$(lr "$lhome" 400 TMUX=1)")
# Mask self-check on real renders, flat (400) and stacked (110, disk value on the values row; with and without colour,
# since NO_COLOR merges the first separator's space into the row's U+2800 lead): changing only the free-space number
# and the disk bar's fill masks equal; changing the 5h value does not.
for c in 400 110 110n; do
  x=; [[ $c == *n ]]&&{ c=${c%n}; x=NO_COLOR=1; }
  r=$(strip "$(lr "$lhome" "$c" TMUX=1 $x)")
  [[ $r =~ $DISK_FREE_ONE_DECIMAL_THEN_UNIT_THEN_SPACE_FREE ]] || { printf 'mask self-check %s: no disk value: %s\n' "$c" "$r" >&2; exit 1; }
  v=${BASH_REMATCH[1]} u=${BASH_REMATCH[2]}; w=${v%?}$(( (${v: -1}+1)%10 ))
  ((c==400)) || { [[ $(rows "$r") -eq 2 && $(row "$r" 2) == *"$v$u free"* ]] || { printf 'mask self-check %s: not stacked with disk on the values row: %s\n' "$c" "$r" >&2; exit 1; }; }
  m=${r/"$v$u free"/"$w$u free"}; m=${m/disk \[█/disk [░}
  [[ $m != "$r" && $r == *"(20%)"* ]] || { printf 'mask self-check %s: mutation did not apply\n' "$c" >&2; exit 1; }
  [[ $(mask_disk "$r") == "$(mask_disk "$m")" ]] || { printf 'mask self-check %s: free-space change not masked:\n%s\n%s\n' "$c" "$(mask_disk "$r")" "$(mask_disk "$m")" >&2; exit 1; }
  [[ $(mask_disk "$r") != "$(mask_disk "${r/(20%)/(21%)}")" ]] || { printf 'mask self-check %s: masked the 5h value\n' "$c" >&2; exit 1; }
done
saw=
for c in 400 $((wf+margin)) $((wf-6+margin)) 110 100 90 80 70 60 50 40 30 20 10; do
  a=$(lr "$lhome" "$c"); b=$(lr "$lhome" "$c" TMUX=1)
  # Controls: a drawn 5h (20%) or 7d (30%) slot carries its link; the unlinked render has none.
  [[ $b != *$'\033]8'* ]] && { [[ $(strip "$a") != *[23]0%* ]] || [[ $a == *"${O}id=bsl-"* ]]; } || { printf 'link fit %s: linked/unlinked control failed\n' "$c" >&2; exit 1; }
  [[ $(mask_disk "$(strip "$a")") == "$(mask_disk "$(strip "$b")")" ]] || { printf 'link fit %s: drawn text differs:\n%s\n%s\n' "$c" "$(strip "$a")" "$(strip "$b")" >&2; exit 1; }
  sb=$(strip "$b")
  if [[ $c -eq 400 ]]; then saw+=W; elif [[ $sb == *"["* && $(rows "$sb") -eq 2 && $sb != *"("* ]]; then saw+=L; elif [[ $sb == *"["* ]]; then saw+=S; else saw+=B; fi
done
[[ $saw == W*S*L*B ]] || { printf 'link fit: stages not all covered (W wide, S shrink, L ladder, B bars off/floor): %s\n' "$saw" >&2; exit 1; }
# Negatives: each condition alone removes every link (PASS = a normal render with no OSC 8 at all).
lcfg "$lhome" "$flatcfg"
nolink() { [[ $2 == *5h*7d* && $2 != *$'\033]8'* ]] || { printf 'link negative %s: %q\n' "$1" "$2" >&2; exit 1; }; }
for v in TMUX=1 WSL_DISTRO_NAME=Ubuntu NO_COLOR=1; do nolink "$v" "$(lr "$lhome" 400 "$v")"; done
lcfg "$HOME/.claude-nomark" "$flatcfg"; nolink marker-absent "$(lr "$HOME/.claude-nomark" 400)"
for d in "$TMP/x" "$HOME/.claude-bad/name" "$HOME/.claude-b@d" "$HOME/claude-t"; do mark "$d"; lcfg "$d" "$flatcfg"; nolink "dir $d" "$(lr "$d" 400)"; done
# The five_segment ladder step drops the whole 5h slot, link included.
lcfg "$lhome" "{$cd_,\"segments\":[\"five_hour\",\"seven_day\"],\"fit\":{\"rows\":1,\"ladder\":[\"five_segment\"]}}"
l5=$(lr "$lhome" 10)
[[ $l5 != *bsl-5h* && $l5 == *"$O7"*7d*"$C"* && $(nlinks "$l5") -eq 1 && ${l5//"$C"/} == "${l5/"$C"/}" ]] || { printf 'link five_segment: %q\n' "$l5" >&2; exit 1; }

# ---- locale independence: the render is byte-identical under any locale, and never hangs ----
# Colour, OSC 8 links and a stacked fit at 70 and 50 columns, so the width loops in cells() run on every render. Each
# render runs under a 20 s alarm (perl: present on macOS and Linux, unlike timeout(1) on older macOS).
# no-utf8 simulates a host where no UTF-8 locale can be switched on: LC_ALL is a readonly C in the shell that sources
# the renderer, so its locale switch fails and the widths must still come out right.
lcfg "$lhome" "{$cd_,\"segments\":[\"model\",\"context\",\"five_hour\",\"seven_day\",\"fable\"],\"fit\":{\"rows\":2}}"
lrl() { # $1 columns, $2 one locale assignment for env, or no-utf8
  local e=$2 run=(perl -e 'alarm 20; exec @ARGV' ${TEST_BASH:-bash})
  [[ $e == no-utf8 ]] && { e=LC_ALL=C; run+=(-c 'readonly LC_ALL=C; f=$1; shift; . "$f"' no-utf8); }
  printf '%s' "$payload" | env -u NO_COLOR -u TMUX -u WSL_DISTRO_NAME -u LANG -u LC_ALL -u LC_CTYPE CLAUDE_CONFIG_DIR="$lhome" COLUMNS="$1" \
    CLAUDE_STATUSLINE_DISABLE_REFRESH=1 "$e" "${run[@]}" "$ROOT/scripts/statusline-command.sh" 2>/dev/null
}
for c in 400 70 50; do
  ref=$(lrl "$c" LC_ALL="$utf8_locale")
  [[ $ref == *"$O5"* ]] || { printf 'locale reference at %s cols: no link, loops not exercised: %q\n' "$c" "$ref" >&2; exit 1; }
  for loc in LC_ALL=C LC_ALL=POSIX LANG= LC_ALL=xx_XX.UTF-8 LC_ALL=C.UTF-8 no-utf8; do
    o=$(lrl "$c" "$loc") && rc=0 || rc=$?
    [[ $rc == 0 && $o == "$ref" ]] || { printf 'locale %s at %s cols: rc=%s, render differs from %s:\n%q\n%q\n' "$loc" "$c" "$rc" "$utf8_locale" "$o" "$ref" >&2; exit 1; }
  done
done

${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh" --help | grep -q '^Usage:'

mkdir -p "$TMP/bin"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s' "${FAKE_USAGE_RESPONSE:?}"
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN='secret-test-token'
rm -f "$XDG_CACHE_HOME/claude-statusline/fable.json" "$XDG_CACHE_HOME/claude-statusline/next_refresh"
export FAKE_USAGE_RESPONSE='{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"used_percentage":67,"resets_at":"soon"}]}'
${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh" --refresh-fable
jq -e '.used_percentage==67 and .resets_at=="soon" and (.accessToken|not)' "$XDG_CACHE_HOME/claude-statusline/fable.json" >/dev/null

rm -f "$XDG_CACHE_HOME/claude-statusline/fable.json" "$XDG_CACHE_HOME/claude-statusline/next_refresh"
export FAKE_USAGE_RESPONSE='{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable 5"}},"percent":73,"resets_at":"later-percent"}]}'
${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh" --refresh-fable
jq -e '.used_percentage==73 and .resets_at=="later-percent"' "$XDG_CACHE_HOME/claude-statusline/fable.json" >/dev/null

rm -f "$XDG_CACHE_HOME/claude-statusline/fable.json" "$XDG_CACHE_HOME/claude-statusline/next_refresh"
export FAKE_USAGE_RESPONSE='{"fable":{"used_percentage":55,"resets_at":"later"}}'
${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh" --refresh-fable
jq -e '.used_percentage==55 and .resets_at=="later"' "$XDG_CACHE_HOME/claude-statusline/fable.json" >/dev/null

# ISO-8601 resets_at is cached verbatim (the ps1 twin once rewrote it through PS7's DateTime).
for iso in '2026-11-15T13:59:59Z' '2026-11-15T20:59:59.567363+00:00'; do
  rm -f "$XDG_CACHE_HOME/claude-statusline/fable.json" "$XDG_CACHE_HOME/claude-statusline/next_refresh"
  export FAKE_USAGE_RESPONSE='{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"used_percentage":61,"resets_at":"'$iso'"}]}'
  ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh" --refresh-fable
  jq -e --arg iso "$iso" '.resets_at==$iso' "$XDG_CACHE_HOME/claude-statusline/fable.json" >/dev/null || { printf 'fable ISO resets_at not verbatim\n' >&2; exit 1; }
done

jq '.fetched_at=1' "$XDG_CACHE_HOME/claude-statusline/fable.json" >"$TMP/stale.json"
mv "$TMP/stale.json" "$XDG_CACHE_HOME/claude-statusline/fable.json"
stale=$(printf '%s' "$payload" | NO_COLOR=1 CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh")
[[ "$stale" == *"Fable ["*"(n/a)"* ]] || { printf 'missing unavailable Fable bar\n' >&2; exit 1; }

printf 'ok\n'

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

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
export CLAUDE_CONFIG_DIR="$TMP/config"
export XDG_CACHE_HOME="$TMP/cache"
export CLAUDE_STATUSLINE_NO_LIVE_COLS=1
export CLAUDE_STATUSLINE_DISABLE_WATCH=1
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

payload='{"model":{"display_name":"Claude"},"context_window":{"used_percentage":25,"total_input_tokens":1000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":30}}}'
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
cells() { sed $'s/\x1b\\[[0-9;]*m//g' <<<"$1" | jq -Rr length; }
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
[[ "$r2" == *"1000B/195.3K (25%)"* ]] || { printf 'stacked bottom row lost ctx values: %s\n' "$r2" >&2; exit 1; }
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
  '{"fable":{"refresh_seconds":10},"labels":{"five_hour":"custom"}}'; do
  printf '%s' "$bad_cfg" >"$CLAUDE_CONFIG_DIR/statusline.json"; o=$(render 400)
  [[ "$o" != *custom* && "$o" == *Claude*ctx*5h* ]] || { printf 'invalid config accepted: %s -> %s\n' "$bad_cfg" "$o" >&2; exit 1; }
done

# ---- exclusion ladder map. Segments pinned (no /tmp) so every machine renders the same stages. ----
order=(disk_label ctx_int no_parens disk_int ctx_no_total no_free fable_short disk_value ctx_no_used fable_label fable_segment seven_label five_label ctx_label seven_segment five_segment)
pin='"segments":["model","cwd","context","disk","five_hour","seven_day","fable"]'
floor() { local steps= s; for s in "$@"; do steps+=${steps:+,}"\"$s\""; done; printf '{%s,"fit":{"rows":1,"ladder":[%s]}}' "$pin" "$steps" >"$CLAUDE_CONFIG_DIR/statusline.json"; render 10; }
trim() { local s=$1; printf '%s' "${s%"${s##*[! ]}"}"; }
base=$(floor)
[[ $base =~ $DISK_FREE_ONE_DECIMAL_THEN_UNIT_THEN_SPACE_FREE ]] || { printf 'baseline lost the disk value: %s\n' "$base" >&2; exit 1; }
dnum=${BASH_REMATCH[1]} dunit=${BASH_REMATCH[2]}; dtok=$dnum$dunit
# Each step on its own: exactly its declared change to the bars-off baseline, nothing else.
expect_step() { # $1 step, $2 expected floor output
  [[ $2 != "$base" ]] || { printf 'ladder %s: expectation is a no-op on baseline: %s\n' "$1" "$base" >&2; exit 1; }
  local o; o=$(floor "$1"); [[ $o == "$2" ]] || { printf 'ladder %s: got [%s] want [%s]\n' "$1" "$o" "$2" >&2; exit 1; }
}
t=${base//(/}; t=${t//)/}
expect_step disk_label "${base//disk /}"
expect_step ctx_int "${base//\/195.3K/\/195K}"
expect_step no_parens "$t"
expect_step ctx_no_total "${base//\/195.3K/}"
expect_step no_free "${base// free/}"
expect_step fable_short "${base//Fable (/F (}"
expect_step disk_value "${base// $dtok free/}"
expect_step ctx_no_used "${base//1000B\//}"
expect_step fable_label "${base//Fable (/(}"
expect_step fable_segment "${base// ● Fable (42%)/}"
expect_step seven_label "${base//7d (/(}"
expect_step five_label "${base//5h (/(}"
expect_step ctx_label "${base//ctx 1000B/1000B}"
expect_step seven_segment "${base// ● 7d (30%)/}"
expect_step five_segment "${base// ● 5h (20%)/}"
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
  [[ $at == "${floors[k]}" ]] || { printf 'ladder progression: at %s cols want %s steps [%s] got [%s]\n' $((lk+margin)) "$k" "${floors[k]}" "$at" >&2; exit 1; }
  if ((k<${#order[@]})); then
    below=$(trim "$(render $((lk+margin-1)))")
    [[ $below == "${floors[k+1]}" ]] || { printf 'ladder progression: at %s cols want %s steps [%s] got [%s]\n' $((lk+margin-1)) $((k+1)) "${floors[k+1]}" "$below" >&2; exit 1; }
  fi
done
printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"

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

jq '.fetched_at=1' "$XDG_CACHE_HOME/claude-statusline/fable.json" >"$TMP/stale.json"
mv "$TMP/stale.json" "$XDG_CACHE_HOME/claude-statusline/fable.json"
stale=$(printf '%s' "$payload" | NO_COLOR=1 CLAUDE_STATUSLINE_DISABLE_REFRESH=1 ${TEST_BASH:-bash} "$ROOT/scripts/statusline-command.sh")
[[ "$stale" == *"Fable ["*"(n/a)"* ]] || { printf 'missing unavailable Fable bar\n' >&2; exit 1; }

printf 'ok\n'

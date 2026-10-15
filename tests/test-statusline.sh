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
mkdir -p "$HOME" "$CLAUDE_CONFIG_DIR" "$XDG_CACHE_HOME/braisenly-statusline"

cat >"$CLAUDE_CONFIG_DIR/statusline.json" <<'JSON'
{
  "segments": ["five_hour", "fable", "seven_day"],
  "labels": {"five_hour": "five", "fable": "story", "seven_day": "week"},
  "widths": {"five_hour": 3, "fable": 5, "seven_day": 4}
}
JSON

cat >"$XDG_CACHE_HOME/braisenly-statusline/fable.json" <<'JSON'
{"used_percentage":42,"resets_at":"2026-09-21T00:00:00Z","model":"Fable","fetched_at":1790000000}
JSON

payload='{"model":{"display_name":"Claude"},"context_window":{"used_percentage":25,"total_input_tokens":1000,"context_window_size":200000},"rate_limits":{"five_hour":{"used_percentage":20},"seven_day":{"used_percentage":30}}}'
plain=$(printf '%s' "$payload" | NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")

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
fallback=$(printf '%s' "$payload" | NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")
[[ "$fallback" == *"Claude"*"ctx"*"5h"*"7d"*"Fable"* ]] || {
  printf 'invalid config did not fall back to defaults\n' >&2
  exit 1
}
[[ "$fallback" != *"drift"* ]] || { printf 'drift segment still rendered\n' >&2; exit 1; }

# Terminal fit: COLUMNS budget is COLUMNS-3. Wide terminal leaves bars untouched and unpadded.
cells() { sed $'s/\x1b\\[[0-9;]*m//g' <<<"$1" | jq -Rr length; }
wide=$(printf '%s' "$payload" | COLUMNS=400 NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")
[[ "$wide" == "$fallback" ]] || { printf 'wide terminal changed the render\n' >&2; exit 1; }
# Mid width: bars shrink uniformly to >= 5 cells, line padded to exactly the budget.
full_cells=$(cells "$fallback")
mid=$((full_cells-20+3))
fit=$(printf '%s' "$payload" | COLUMNS=$mid NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")
[[ $(cells "$fit") -eq $((mid-3)) ]] || { printf 'fit width mismatch: %s vs %s\n' "$(cells "$fit")" "$((mid-3))" >&2; exit 1; }
ctxbar=${fit#*ctx [}; ctxbar=${ctxbar%%]*}
[[ ${#ctxbar} -lt 12 && ${#ctxbar} -ge 5 ]] || { printf 'ctx bar not shrunk into range: %s\n' "${#ctxbar}" >&2; exit 1; }
# Narrow: any bar below floor drops every bar; no padding beyond budget is added.
narrow=$(printf '%s' "$payload" | COLUMNS=60 NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")
[[ "$narrow" != *"["* ]] || { printf 'bars not dropped at narrow width\n' >&2; exit 1; }
[[ "$narrow" == *"ctx 1000B/195.3K"* ]] || { printf 'bar removal left bad spacing: %s\n' "$narrow" >&2; exit 1; }
# Reserve shrinks the budget.
printf '{"fit":{"reserve":20}}' >"$CLAUDE_CONFIG_DIR/statusline.json"
res=$(printf '%s' "$payload" | COLUMNS=$((mid+20)) NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")
[[ $(cells "$res") -eq $((mid-3)) ]] || { printf 'reserve not applied\n' >&2; exit 1; }
printf '{bad json' >"$CLAUDE_CONFIG_DIR/statusline.json"

bash "$ROOT/scripts/statusline-command.sh" --help | grep -q '^Usage:'

mkdir -p "$TMP/bin"
cat >"$TMP/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s' "${FAKE_USAGE_RESPONSE:?}"
SH
chmod +x "$TMP/bin/curl"
export PATH="$TMP/bin:$PATH"
export CLAUDE_CODE_OAUTH_TOKEN='secret-test-token'
rm -f "$XDG_CACHE_HOME/braisenly-statusline/fable.json" "$XDG_CACHE_HOME/braisenly-statusline/next_refresh"
export FAKE_USAGE_RESPONSE='{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"used_percentage":67,"resets_at":"soon"}]}'
bash "$ROOT/scripts/statusline-command.sh" --refresh-fable
jq -e '.used_percentage==67 and .resets_at=="soon" and (.accessToken|not)' "$XDG_CACHE_HOME/braisenly-statusline/fable.json" >/dev/null

rm -f "$XDG_CACHE_HOME/braisenly-statusline/fable.json" "$XDG_CACHE_HOME/braisenly-statusline/next_refresh"
export FAKE_USAGE_RESPONSE='{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable 5"}},"percent":73,"resets_at":"later-percent"}]}'
bash "$ROOT/scripts/statusline-command.sh" --refresh-fable
jq -e '.used_percentage==73 and .resets_at=="later-percent"' "$XDG_CACHE_HOME/braisenly-statusline/fable.json" >/dev/null

rm -f "$XDG_CACHE_HOME/braisenly-statusline/fable.json" "$XDG_CACHE_HOME/braisenly-statusline/next_refresh"
export FAKE_USAGE_RESPONSE='{"fable":{"used_percentage":55,"resets_at":"later"}}'
bash "$ROOT/scripts/statusline-command.sh" --refresh-fable
jq -e '.used_percentage==55 and .resets_at=="later"' "$XDG_CACHE_HOME/braisenly-statusline/fable.json" >/dev/null

jq '.fetched_at=1' "$XDG_CACHE_HOME/braisenly-statusline/fable.json" >"$TMP/stale.json"
mv "$TMP/stale.json" "$XDG_CACHE_HOME/braisenly-statusline/fable.json"
stale=$(printf '%s' "$payload" | NO_COLOR=1 BRAISENLY_STATUSLINE_DISABLE_REFRESH=1 bash "$ROOT/scripts/statusline-command.sh")
[[ "$stale" == *"Fable ["*"(n/a)"* ]] || { printf 'missing unavailable Fable bar\n' >&2; exit 1; }

printf 'ok\n'

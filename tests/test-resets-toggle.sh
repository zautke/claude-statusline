#!/usr/bin/env bash
# resets-toggle.sh contract. Twin of test-resets-toggle.ps1: the expected strings and JSON below are copy-identical
# in both files, so both scripts are held to the same output. Runs in a temp HOME; never the real profile.
set -euo pipefail

Usage() {
  printf 'Usage: %s [-h|--help]\n' "${0##*/}"
}

case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
  '') ;;
  *) Usage >&2; exit 2 ;;
esac

plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script=$plugin/scripts/resets-toggle.sh

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
export HOME=$temp/home CLAUDE_CONFIG_DIR=$temp/home/.claude
mkdir -p "$CLAUDE_CONFIG_DIR"
sl=$CLAUDE_CONFIG_DIR/statusline.json
st=$CLAUDE_CONFIG_DIR/settings.json

# ---- expectations (copy-identical in test-resets-toggle.ps1) ----
OFF='Reset times off.'
ON_CLOCK='Reset times on (clock).'
ON_COUNTDOWN='Reset times on (countdown); status line refreshes every 60s.'
UNOWNED_NOTE=" statusLine is not claude-statusline's; set statusLine.refreshInterval ≤ 60 yourself to keep the countdown current."
OWNED_SETTINGS='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh # bsl-cols=120"},"x-test-date":"2026-11-15T13:59:59Z"}'
OWNED_SETTINGS_COUNTDOWN_SANS_NONCE='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh","refreshInterval":60},"x-test-date":"2026-11-15T13:59:59Z"}'
OWNED_SETTINGS_CLOCK_SANS_NONCE='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh"},"x-test-date":"2026-11-15T13:59:59Z"}'
OWNED_SETTINGS_USER_30_SANS_NONCE='{"model":"opus","statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh","refreshInterval":30},"x-test-date":"2026-11-15T13:59:59Z"}'
UNOWNED_SETTINGS='{"statusLine":{"type":"command","command":"echo mine"}}'
NONCE_EPOCH_MS=' # bsl-cols=[0-9]{13,}$'
LOG_LINE_OK='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z 0$'

# ---- helpers ----
run() { rc=0; out=$("$BASH" "$script" "$@" 2>"$temp/stderr") || rc=$?; err=$(cat "$temp/stderr"); }
expect() { [[ $rc == "$1" && $out == "$2" ]] || fail "$3: want rc=$1 out=[$2]; got rc=$rc out=[$out] err=[$err]"; }
json() { jq -c . "$1"; }
sans_nonce() { jq -c '.statusLine.command |= sub(" # bsl-cols=[0-9]+$"; "")' "$1"; }
cmd() { jq -r .statusLine.command "$st"; }
put() { printf '%s\n' "$2" >"$1"; }
# Inode, size and checksum of everything under HOME: a rename-over or an edit changes it.
snap() { find "$HOME" -exec ls -ldi {} + | sort; find "$HOME" -type f -exec cksum {} + | sort; }
reset() { rm -rf "$HOME"; mkdir -p "$CLAUDE_CONFIG_DIR"; }

# ---- positive ----
# Create from absent: only the changed key is written; absent settings.json is never created.
run --set off; expect 0 "$OFF" 'create-from-absent'
[[ $(json "$sl") == '{"resets":false}' ]] || fail "create-from-absent json: $(json "$sl")"
[[ ! -e $st ]] || fail 'absent settings.json was created'

# Toggle true -> false -> true, other keys kept in order.
put "$sl" '{"theme":"x","resets":true}'
run --set toggle; expect 0 "$OFF" 'toggle 1'
[[ $(json "$sl") == '{"theme":"x","resets":false}' ]] || fail "toggle 1 json: $(json "$sl")"
run -s toggle; expect 0 "$ON_CLOCK" 'toggle 2'
[[ $(json "$sl") == '{"theme":"x","resets":true}' ]] || fail "toggle 2 json: $(json "$sl")"

# --format countdown: resets true, refreshInterval 60, nonce bumped, other keys verbatim.
put "$sl" '{"theme":"x","resets":false}'
put "$st" "$OWNED_SETTINGS"
run --format countdown; expect 0 "$ON_COUNTDOWN" 'format countdown'
[[ $(json "$sl") == '{"theme":"x","resets":true,"resets_format":"countdown"}' ]] || fail "countdown json: $(json "$sl")"
[[ $(sans_nonce "$st") == "$OWNED_SETTINGS_COUNTDOWN_SANS_NONCE" ]] || fail "countdown settings: $(sans_nonce "$st")"
c1=$(cmd); [[ $c1 =~ $NONCE_EPOCH_MS ]] || fail "countdown nonce: $c1"

# --format clock: our refreshInterval 60 removed, nonce bumped again.
run -f clock; expect 0 "$ON_CLOCK" 'format clock'
[[ $(json "$sl") == '{"theme":"x","resets":true,"resets_format":"clock"}' ]] || fail "clock json: $(json "$sl")"
[[ $(sans_nonce "$st") == "$OWNED_SETTINGS_CLOCK_SANS_NONCE" ]] || fail "clock settings: $(sans_nonce "$st")"
c2=$(cmd); [[ $c2 =~ $NONCE_EPOCH_MS && $c2 != "$c1" ]] || fail "clock nonce not bumped: $c1 -> $c2"

# A user refreshInterval (30) is kept by both formats.
jq '.statusLine.refreshInterval = 30' "$st" >"$temp/s" && mv "$temp/s" "$st"
run --format countdown; expect 0 "$ON_COUNTDOWN" 'user 30 countdown'
[[ $(sans_nonce "$st") == "$OWNED_SETTINGS_USER_30_SANS_NONCE" ]] || fail "user 30 countdown: $(sans_nonce "$st")"
run --format clock; expect 0 "$ON_CLOCK" 'user 30 clock'
[[ $(sans_nonce "$st") == "$OWNED_SETTINGS_USER_30_SANS_NONCE" ]] || fail "user 30 clock: $(sans_nonce "$st")"

# --get prints the state line and writes nothing.
put "$st" "$OWNED_SETTINGS"
for pair in "{\"resets\":false}|$OFF" "{}|$ON_CLOCK" "{\"resets_format\":\"clock\"}|$ON_CLOCK" "{\"resets\":true,\"resets_format\":\"countdown\"}|$ON_COUNTDOWN"; do
  put "$sl" "${pair%%|*}"; before=$(snap)
  run --get; expect 0 "${pair#*|}" "get ${pair%%|*}"
  [[ $(snap) == "$before" ]] || fail "get wrote: ${pair%%|*}"
done
rm -f "$sl"; run -g; expect 0 "$ON_CLOCK" 'get absent'
[[ ! -e $sl ]] || fail 'get created statusline.json'

# --sync reconciles refreshInterval silently, without a nonce bump or a statusline.json write.
put "$sl" '{"resets":true,"resets_format":"countdown"}'
put "$st" "$OWNED_SETTINGS"
before_sl=$(cksum <"$sl")
run --sync; expect 0 '' 'sync add'
[[ $(sans_nonce "$st") == "$OWNED_SETTINGS_COUNTDOWN_SANS_NONCE" ]] || fail "sync add: $(sans_nonce "$st")"
[[ $(cmd) == *' # bsl-cols=120' ]] || fail "sync bumped nonce: $(cmd)"
[[ $(cksum <"$sl") == "$before_sl" ]] || fail 'sync wrote statusline.json'
put "$sl" '{"resets":false,"resets_format":"countdown"}'
run -y; expect 0 '' 'sync remove'
[[ $(sans_nonce "$st") == "$OWNED_SETTINGS_CLOCK_SANS_NONCE" ]] || fail "sync remove: $(sans_nonce "$st")"
[[ $(cmd) == *' # bsl-cols=120' ]] || fail "sync remove bumped nonce: $(cmd)"

# Idempotent: a second --set on writes nothing.
put "$sl" '{"resets":false}'
run --set on; expect 0 "$ON_CLOCK" 'set on 1'
before=$(snap)
run --set on; expect 0 "$ON_CLOCK" 'set on 2'
[[ $(snap) == "$before" ]] || fail 'second --set on wrote'

# Symlinked statusline.json and settings.json: the targets are written, the links kept.
reset; mkdir -p "$HOME/dotfiles"
put "$HOME/dotfiles/statusline.json" '{"resets":true}'
put "$HOME/dotfiles/settings.json" "$OWNED_SETTINGS"
ln -s "$HOME/dotfiles/statusline.json" "$sl"; ln -s "$HOME/dotfiles/settings.json" "$st"
run --format countdown; expect 0 "$ON_COUNTDOWN" 'symlinks'
[[ -L $sl && -L $st ]] || fail 'symlink replaced'
[[ $(json "$HOME/dotfiles/statusline.json") == '{"resets":true,"resets_format":"countdown"}' ]] || fail 'symlink statusline target'
[[ $(sans_nonce "$HOME/dotfiles/settings.json") == "$OWNED_SETTINGS_COUNTDOWN_SANS_NONCE" ]] || fail 'symlink settings target'

# --url: toggles, logs one line per click, accepts the trailing-slash form and a profile.
reset; log=$CLAUDE_CONFIG_DIR/claude-statusline/url-handler.log
run --url 'claude-statusline://toggle?slot=5h'; expect 0 "$OFF" 'url 5h'
[[ $(json "$sl") == '{"resets":false}' ]] || fail "url 5h json: $(json "$sl")"
run -u 'claude-statusline://toggle/?slot=7d'; expect 0 "$ON_CLOCK" 'url 7d trailing slash'
[[ $(wc -l <"$log" | tr -d ' ') == 2 ]] || fail "url log lines: $(cat "$log")"
while IFS= read -r l; do [[ $l =~ $LOG_LINE_OK ]] || fail "url log line: [$l]"; done <"$log"
mkdir -p "$HOME/.claude-work"
run --url 'claude-statusline://toggle?slot=5h&profile=work'; expect 0 "$OFF" 'url profile'
[[ $(json "$HOME/.claude-work/statusline.json") == '{"resets":false}' ]] || fail 'url profile json'
[[ $(json "$sl") == '{"resets":true}' ]] || fail 'url profile touched the default profile'
[[ $(wc -l <"$HOME/.claude-work/claude-statusline/url-handler.log" | tr -d ' ') == 1 ]] || fail 'url profile log'
# The log keeps the last 50 lines.
for i in $(seq 1 60); do printf 'old %s\n' "$i"; done >"$log"
run --url 'claude-statusline://toggle?slot=5h'; expect 0 "$OFF" 'url log cap'
[[ $(wc -l <"$log" | tr -d ' ') == 50 && $(head -n 1 "$log") == 'old 12' && $(tail -n 1 "$log") =~ $LOG_LINE_OK ]] || fail 'url log not capped to 50'

# ---- negative (PASS = exactly the declared exit code and no write) ----
reset; put "$sl" '{"resets":true}'; put "$st" "$OWNED_SETTINGS"; mkdir -p "$HOME/.claude-work"
neg() { local want=$1 label=$2; shift 2; local before; before=$(snap); run "$@"
  [[ $rc == "$want" && -z $out && -n $err ]] || fail "negative $label: want rc=$want got rc=$rc out=[$out] err=[$err]"
  [[ $(snap) == "$before" ]] || fail "negative $label wrote"; }
neg 2 'no args'
neg 2 'unknown flag' --bogus
neg 2 'positional' on
neg 2 'set maybe' --set maybe
neg 2 'format Clock' --format Clock
neg 2 'missing value' --set
neg 2 'missing url' --url
neg 2 'two actions' --get --sync
for u in 'evil://toggle?slot=5h' 'claude-statusline://toggle?slot=1d' 'claude-statusline://toggle?slot=5h&x=1' \
  'claude-statusline://toggle?slot=5h&profile=..' 'claude-statusline://toggle?slot=5h&profile=a/b' \
  'claude-statusline://toggle?slot=5h&profile=missing' 'claude-statusline://toggle?slot=5h;rm -rf ~' \
  'claude-statusline://toggle?slot=5h$(id)' $'claude-statusline://toggle?slot=5h\n' $'claude-statusline://toggle?slot=5h\r&profile=work'; do
  neg 2 "url [$u]" --url "$u"
done
# Invalid statusline.json: exit 1, bytes unchanged.
put "$sl" '{not json'
neg 1 'invalid statusline.json' --set off
neg 1 'invalid statusline.json get' --get

# Unowned statusLine: statusline.json written, settings.json byte-identical, note appended.
put "$sl" '{"resets":true}'; put "$st" "$UNOWNED_SETTINGS"; before=$(cksum <"$st")
run --set off; expect 0 "$OFF$UNOWNED_NOTE" 'unowned'
[[ $(json "$sl") == '{"resets":false}' ]] || fail 'unowned statusline.json not written'
[[ $(cksum <"$st") == "$before" ]] || fail 'unowned settings.json changed'

# Usage is first-class: -h prints it on stdout, exit 0.
run -h; [[ $rc == 0 && $out == Usage:* ]] || fail "help: rc=$rc out=[$out]"

printf 'ok\n'

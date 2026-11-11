#!/usr/bin/env bash
# resets-toggle.sh — shows, sets or toggles the 5h/7d reset times (statusline.json resets / resets_format), keeps
# settings.json statusLine.refreshInterval in step with the countdown format, and bumps the statusLine command nonce
# so Claude Code re-runs the status line at once. Shared by the statusline-resets command, its key chord and the
# claude-statusline:// click handler. Twin of resets-toggle.ps1: same flags, exit codes, output and files.
set -u

Usage() {
  cat <<'EOF'
Usage: resets-toggle.sh -g|--get | -s|--set on|off|toggle | -f|--format clock|countdown | -y|--sync | -u|--url <uri> | -h|--help

  -g, --get                    Print the current state.
  -s, --set on|off|toggle      Show, hide or toggle the reset times.
  -f, --format clock|countdown Pick the format (also shows the reset times).
  -y, --sync                   Reconcile settings.json refreshInterval with statusline.json; silent.
  -u, --url <uri>              Toggle from a claude-statusline://toggle?slot=5h|7d[&profile=<name>] click.
  -h, --help                   Show help.

Config dir: CLAUDE_CONFIG_DIR, else ~/.claude; a --url profile selects ~/.claude-<name>.
Exit codes: 0 ok, 1 refused, 2 usage.
EOF
}
usage_fail() { Usage >&2; exit 2; }

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/constants.sh
. "$root/config/constants.sh"
# shellcheck source=../config/load-identity.sh
. "$root/config/load-identity.sh"
load_identity "$root/config/identity.env"

action= value= n=0
while (($#)); do
  case "$1" in
    -h|--help) Usage; exit 0 ;;
    -g|--get) action=get ;;
    -y|--sync) action=sync ;;
    -s|--set|-f|--format|-u|--url)
      [[ $# -ge 2 ]] || usage_fail
      case "$1" in -s|--set) action=set ;; -f|--format) action=format ;; *) action=url ;; esac
      value=$2; shift ;;
    *) usage_fail ;;
  esac
  n=$((n + 1)); shift
done
[[ $n -eq 1 ]] || usage_fail
case "$action:$value" in set:on|set:off|set:toggle|format:clock|format:countdown|get:|sync:|url:*) ;; *) usage_fail ;; esac

cfg=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
ri=$RESETS_COUNTDOWN_STATUS_LINE_REFRESH_INTERVAL_SECONDS

# Follow links so a dotfiles-managed file keeps its link (from resize-watch.sh).
resolve() { local t=$1 n=0 d; if readlink -f / >/dev/null 2>&1; then readlink -f "$t"; return; fi; while [[ -L $t && $n -lt 32 ]]; do d=$(dirname "$t"); t=$(readlink "$t"); [[ $t == /* ]] || t=$d/$t; n=$((n+1)); done; printf '%s' "$t"; }

# Temp file beside the target, original mode carried over, then rename. $3 (optional) is a digest the target must
# still have at the last instant.
atomic_write() {
  local dst=$1 tmp mode
  tmp=$(mktemp "${dst%/*}/.${dst##*/}.XXXXXX") || return 1
  printf '%s\n' "$2" >"$tmp" || { rm -f "$tmp"; return 1; }
  if [[ -e $dst ]]; then
    mode=$(stat -c %a "$dst" 2>/dev/null || stat -f %OLp "$dst" 2>/dev/null); [[ -n $mode ]] && chmod "$mode" "$tmp"
  fi
  if [[ -n ${3:-} && $(cksum <"$dst") != "$3" ]]; then rm -f "$tmp"; return 3; fi
  mv -f "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}

# ---- --url: validate, then run --set toggle against the URL's profile and log the outcome ----
if [[ $action == url ]]; then
  case "$value" in *$'\r'*|*$'\n'*) printf 'resets-toggle.sh: invalid URL\n' >&2; exit 2 ;; esac
  [[ $value =~ $RESETS_TOGGLE_URL_SCHEME_TOGGLE_SLOT_5H_OR_7D_OPTIONAL_PROFILE_FULL_MATCH ]] || { printf 'resets-toggle.sh: invalid URL\n' >&2; exit 2; }
  # The slot (group 1) is validated only; the toggle is global.
  profile=${BASH_REMATCH[2]#&profile=}
  if [[ -n $profile ]]; then
    cfg=$HOME/.claude-$profile
    [[ $profile != *..* && -d $cfg ]] || { printf 'resets-toggle.sh: no such profile directory\n' >&2; exit 2; }
  fi
  { err=$(CLAUDE_CONFIG_DIR=$cfg "$BASH" "${BASH_SOURCE[0]}" --set toggle 2>&1 1>&3 3>&-); rc=$?; } 3>&1
  [[ -n $err ]] && printf '%s\n' "$err" >&2
  tail_text=$(printf '%s' "$err" | tr '\r\n' '  ')
  ((${#tail_text} > 200)) && tail_text=${tail_text:${#tail_text}-200}
  log_dir=$cfg/$LAUNCHER_HOME log=$cfg/$LAUNCHER_HOME/url-handler.log
  [[ -e $log ]] && log=$(resolve "$log")
  mkdir -p "$log_dir" && atomic_write "$log" "$({ [[ -f $log ]] && cat "$log"; printf '%s %s%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$rc" "${tail_text:+ $tail_text}"; } | tail -n 50)"
  exit "$rc"
fi

# ---- statusline.json ----
sl=$cfg/statusline.json
[[ -e $sl ]] && sl=$(resolve "$sl")
if [[ -e $sl ]]; then
  # Slurp: exactly one document, and it is an object ({} {} is a stream, not a config).
  current=$(jq -se 'if length == 1 and (.[0] | type) == "object" then .[0] else error end' "$sl" 2>/dev/null) || { printf 'resets-toggle.sh: %s is not a JSON object; left unchanged\n' "$sl" >&2; exit 1; }
else
  current='{}'
fi
case "$action:$value" in
  set:on) filter='.resets = true' ;;
  set:off) filter='.resets = false' ;;
  set:toggle) filter='.resets = (.resets == false)' ;;
  format:*) filter='.resets = true | .resets_format = $f' ;;
  *) filter='.' ;;
esac
next=$(jq --arg f "$value" "$filter" <<<"$current")
changed=0
if [[ $next != "$current" || ! -e $sl ]] && [[ $filter != . ]]; then
  mkdir -p "${sl%/*}" && atomic_write "$sl" "$next" || { printf 'resets-toggle.sh: cannot write %s\n' "$sl" >&2; exit 1; }
  changed=1
fi
# Booleans are read without jq //, which treats false as absent.
state=$(jq -r 'if .resets == false then "off" elif .resets_format == "countdown" then "countdown" else "clock" end' <<<"$next")

# ---- settings.json: refreshInterval for the countdown, plus a nonce bump when statusline.json changed ----
unowned=0
reconcile() {
  local st=$cfg/settings.json raw base before new ms nonce=
  [[ -e $st ]] || return 0
  st=$(resolve "$st")
  before=$(cksum <"$st")
  jq -se 'length == 1' "$st" >/dev/null 2>&1 || { printf 'resets-toggle.sh: %s is not valid JSON; left unchanged\n' "$st" >&2; return 0; }
  # A root or statusLine that is not an object, or a non-string command, reads as "" (unowned), as in the ps1 twin.
  raw=$(jq -r 'if type == "object" then (.statusLine | objects | .command | strings) // "" else "" end' "$st")
  base=${raw% # bsl-cols=*}; [[ $raw =~ $NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END ]] || base=$raw
  # Same ownership test as scripts/install.sh.
  if [[ -z $base || ! ( $base =~ $OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE || $base == 'bash ~/.claude/statusline-dispatcher.sh' ) ]]; then
    unowned=1; return 0
  fi
  if ((changed)); then
    ms=$(date +%s%3N); [[ $ms =~ ^[0-9]+$ ]] || ms=$(date +%s)000
    [[ $raw == *" # bsl-cols=$ms" ]] && ms=$((ms + 1))
    nonce=" # bsl-cols=$ms"
  fi
  new=$(jq --argjson cd "$([[ $state == countdown ]] && echo true || echo false)" --argjson ri "$ri" --arg n "$nonce" --arg re "$NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END" '
    (if $cd and (.statusLine | has("refreshInterval") | not) then .statusLine.refreshInterval = $ri
     elif ($cd | not) and .statusLine.refreshInterval == $ri then .statusLine |= del(.refreshInterval)
     else . end)
    | if $n != "" then .statusLine.command |= (sub($re; "") + $n) else . end' "$st") || return 0
  [[ $new == "$(jq . "$st")" ]] && return 0
  # ponytail: digest recheck only; concurrent CC write between recheck and move can be lost
  atomic_write "$st" "$new" "$before"
}
if [[ $action != get ]]; then
  for _ in 1 2 3; do reconcile; r=$?; [[ $r -eq 3 ]] || break; done
  [[ $r -eq 3 ]] && printf 'resets-toggle.sh: settings.json kept changing; refreshInterval/nonce not applied\n' >&2
fi

[[ $action == sync ]] && exit 0
case $state in
  off) msg='Reset times off.' ;;
  clock) msg='Reset times on (clock).' ;;
  *) msg="Reset times on (countdown); status line refreshes every ${ri}s." ;;
esac
((unowned)) && [[ $action != get ]] && msg+=" statusLine is not $PLUGIN_NAME's; set statusLine.refreshInterval ≤ $ri yourself to keep the countdown current."
printf '%s\n' "$msg"

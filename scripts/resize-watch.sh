#!/usr/bin/env bash
# Resize watcher — polls the Claude Code pty size and bumps the statusLine command
# nonce in settings.json when the column count changes, which makes Claude Code
# re-run the status line immediately (a command change skips the 300ms debounce).
# Claude Code does not re-run the status line on SIGWINCH (anthropics/claude-code#76988).
#
# Safety: writes only after the width has settled, only through validated temp file +
# atomic rename, only when the file has not changed since it was read (compare-and-swap),
# and only after keeping a one-time backup beside the settings file.
set -u

Usage() {
  printf '%s\n' 'Usage: resize-watch.sh -p|--pid <claude-pid> [-s|--settings <settings.json>] [-i|--interval <seconds>] [-d|--settle <seconds>] [-h|--help]'
}

pid= settings=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json interval=0.25 settle=0.4
while (($#)); do
  case "$1" in
    -h|--help) Usage; exit 0 ;;
    -p|--pid) pid=${2:-}; shift ;;
    -s|--settings) settings=${2:-}; shift ;;
    -i|--interval) interval=${2:-}; shift ;;
    -d|--settle) settle=${2:-}; shift ;;
    *) Usage >&2; exit 2 ;;
  esac
  shift
done
[[ $pid =~ ^[0-9]+$ ]] || { Usage >&2; exit 2; }

tty=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
[[ -n $tty && $tty != '?' && $tty != '??' ]] || exit 0
dev=/dev/$tty
[[ -r $dev ]] || exit 0

cols() { [[ -r $dev ]] || return 0; stty size <"$dev" 2>/dev/null | awk '{print $2}'; }
digest() { cksum <"$1" 2>/dev/null; }

bump() {
  local tmp before after keys_before keys_after
  [[ -r $settings ]] || return 0
  [[ -e $settings.bsl-backup ]] || cp -p "$settings" "$settings.bsl-backup" 2>/dev/null
  tmp=$settings.tmp.$$
  before=$(digest "$settings")
  # Strip any previous nonce, then append the new one. Leave every other key untouched.
  jq --arg n " # bsl-cols=$1" '
    if (.statusLine.command? // "") | type == "string" and length > 0
    then .statusLine.command |= (sub(" # bsl-cols=[0-9]+$"; "") + $n)
    else . end' "$settings" >"$tmp" 2>/dev/null || { rm -f "$tmp"; return 0; }
  # Validate: parses, and no top-level key was lost.
  keys_before=$(jq -c 'keys' "$settings" 2>/dev/null); keys_after=$(jq -c 'keys' "$tmp" 2>/dev/null)
  [[ -n $keys_after && $keys_before == "$keys_after" ]] || { rm -f "$tmp"; return 0; }
  # Compare-and-swap: Claude Code also writes this file; if it changed since we read it, drop this bump.
  after=$(digest "$settings")
  [[ $before == "$after" ]] || { rm -f "$tmp"; return 0; }
  mv "$tmp" "$settings" || rm -f "$tmp"
}

last=$(cols) pending=
# ponytail: pty has no resize signal for non-foreground processes; one ioctl per tick is the cheapest watch.
while kill -0 "$pid" 2>/dev/null; do
  sleep "$interval"
  now=$(cols)
  [[ $now =~ ^[0-9]+$ && $now -gt 0 ]] || continue
  if [[ $now != "$last" ]]; then
    # Width is moving (pane drag). Wait for it to settle before writing once.
    last=$now pending=$now
    sleep "$settle"
    continue
  fi
  [[ -n $pending ]] || continue
  pending=
  [[ -e ${settings%/*}/../.cache/braisenly-statusline/trace || -e ${XDG_CACHE_HOME:-$HOME/.cache}/braisenly-statusline/trace ]] && printf '%s bump cols=%s\n' "$(date +%s.%N)" "$now" >>"${XDG_CACHE_HOME:-$HOME/.cache}/braisenly-statusline/trace"
  bump "$now"
done

#!/usr/bin/env bash
# Resize watcher — polls the Claude Code pty size and bumps the statusLine command
# nonce in settings.json when the column count changes, which makes Claude Code
# re-run the status line immediately (a command change skips the 300ms debounce).
# Claude Code does not re-run the status line on SIGWINCH (anthropics/claude-code#76988).
set -u

Usage() {
  printf '%s\n' 'Usage: resize-watch.sh -p|--pid <claude-pid> [-s|--settings <settings.json>] [-i|--interval <seconds>] [-h|--help]'
}

pid= settings=${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json interval=0.25
while (($#)); do
  case "$1" in
    -h|--help) Usage; exit 0 ;;
    -p|--pid) pid=${2:-}; shift ;;
    -s|--settings) settings=${2:-}; shift ;;
    -i|--interval) interval=${2:-}; shift ;;
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

bump() {
  local tmp
  [[ -r $settings ]] || return 0
  tmp=$settings.tmp.$$
  # Re-read on every bump: Claude Code also writes this file. Strip any previous nonce, then append the new one.
  jq --arg n " # bsl-cols=$1" '
    if (.statusLine.command? // "") | type == "string" and length > 0
    then .statusLine.command |= (sub(" # bsl-cols=[0-9]+$"; "") + $n)
    else . end' "$settings" >"$tmp" 2>/dev/null && mv "$tmp" "$settings" || rm -f "$tmp"
}

last=$(cols)
# ponytail: pty has no resize signal for non-foreground processes; one ioctl per tick is the cheapest watch.
while kill -0 "$pid" 2>/dev/null; do
  sleep "$interval"
  now=$(cols)
  [[ $now =~ ^[0-9]+$ && $now -gt 0 && $now != "$last" ]] || continue
  last=$now
  bump "$now"
done

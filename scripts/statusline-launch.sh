#!/usr/bin/env bash
# Stable statusLine.command target. Lives in <config-dir>/claude-statusline/ (copied there by
# install.sh), finds the installed plugin version in installed_plugins.json, and runs that
# version's dispatcher, so plugin updates reach the status line without a settings edit.
# With --url it hands a status-line click to that version's resets-toggle instead (the registered
# URL handler calls this).
set -uo pipefail

home=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/load-identity.sh
. "$home/config/load-identity.sh"
load_identity "$home/config/identity.env"

Usage() {
  printf 'Usage: %s [-u|--url URI] [-h|--help]\n\nReads Claude Code status JSON on stdin and runs the installed %s renderer.\n  -u, --url URI  Pass a status-line click URL to the installed resets-toggle instead.\n' "${0##*/}" "$PLUGIN_ID"
}

url_mode=0 url=
case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
  -u|--url) [[ $# -eq 2 ]] || { Usage >&2; exit 2; }; url_mode=1 url=$2 ;;
  '') ;;
  *) Usage >&2; exit 2 ;;
esac

# The launcher home sits in the Claude config dir, beside plugins/.
plugins_dir=${CLAUDE_CODE_PLUGIN_CACHE_DIR:-$(dirname "$home")/plugins}

# User-scope record first, then any other record; first one whose directory exists wins.
root=$(jq -r --arg id "$PLUGIN_ID" \
  '(.plugins[$id] // []) | (map(select(.scope == "user")) + map(select(.scope != "user"))) | .[].installPath // empty' \
  "$plugins_dir/installed_plugins.json" 2>/dev/null |
  while IFS= read -r p; do [[ -d $p ]] && { printf '%s' "$p"; break; }; done)

if ((url_mode)); then
  [[ -n $root && -f $root/scripts/resets-toggle.sh ]] || { printf '%s\n' "$NOT_INSTALLED_MESSAGE" >&2; exit 1; }
  # URL as one argv element; never through a shell string.
  exec bash "$root/scripts/resets-toggle.sh" --url "$url"
fi

if [[ -z $root || ! -f $root/scripts/statusline-dispatcher.sh ]]; then
  printf '%s\n' "$NOT_INSTALLED_MESSAGE"
  exit 0
fi
exec bash "$root/scripts/statusline-dispatcher.sh"

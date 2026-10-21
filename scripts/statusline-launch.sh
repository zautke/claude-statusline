#!/usr/bin/env bash
# Stable statusLine.command target. Lives in <config-dir>/claude-statusline/ (copied there by
# install.sh), finds the installed plugin version in installed_plugins.json, and runs that
# version's dispatcher, so plugin updates reach the status line without a settings edit.
set -uo pipefail

home=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/load-identity.sh
. "$home/config/load-identity.sh"
load_identity "$home/config/identity.env"

Usage() {
  printf 'Usage: %s [-h|--help]\n\nReads Claude Code status JSON on stdin and runs the installed %s renderer.\n' "${0##*/}" "$PLUGIN_ID"
}

case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
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

if [[ -z $root || ! -f $root/scripts/statusline-dispatcher.sh ]]; then
  printf '%s\n' "$NOT_INSTALLED_MESSAGE"
  exit 0
fi
exec bash "$root/scripts/statusline-dispatcher.sh"

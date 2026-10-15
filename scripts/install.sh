#!/usr/bin/env bash
set -euo pipefail

Usage() {
  cat <<'EOF'
Usage: install.sh [-c|--config-dir DIR] [-f|--force] [-h|--help]

  -c, --config-dir DIR  Claude profile directory (default: CLAUDE_CONFIG_DIR or ~/.claude).
  -f, --force           Replace an unrelated statusLine command.
  -h, --help            Show help.
EOF
}

config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
force=0
while (($#)); do
  case "$1" in
    -c|--config-dir) [[ $# -ge 2 ]] || { Usage >&2; exit 2; }; config_dir=$2; shift 2 ;;
    -f|--force) force=1; shift ;;
    -h|--help) Usage; exit 0 ;;
    *) Usage >&2; exit 2 ;;
  esac
done

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
command="bash $plugin_root/scripts/statusline-dispatcher.sh"
settings=$config_dir/settings.json
mkdir -p "$config_dir"

if [[ -r $settings ]]; then
  # Strip the resize watcher's nonce before the ownership check.
  current=$(jq -r '(.statusLine.command//empty)|sub(" # bsl-cols=[0-9]+$"; "")' "$settings")
  if [[ -n $current && $current != *braisenly-statusline* && $current != 'bash ~/.claude/statusline-dispatcher.sh' && $force -eq 0 ]]; then
    printf 'Refusing to replace unrelated statusLine command: %s\n' "$current" >&2
    exit 1
  fi
  tmp=$(mktemp "$config_dir/.settings.XXXXXX")
  jq --arg cmd "$command" '.statusLine={type:"command",command:$cmd} | .enabledPlugins["braisenly-statusline@dot-agents"]=true' "$settings" >"$tmp"
  mv "$tmp" "$settings"
else
  jq -n --arg cmd "$command" '{statusLine:{type:"command",command:$cmd},enabledPlugins:{"braisenly-statusline@dot-agents":true}}' >"$settings"
fi

printf 'Installed Braisenly status line for %s\n' "$config_dir"

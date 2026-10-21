#!/usr/bin/env bash
set -euo pipefail

Usage() {
  cat <<'EOF'
Usage: install.sh [-c|--config-dir DIR] [-f|--force] [-h|--help]

  -c, --config-dir DIR  Claude profile directory (default: CLAUDE_CONFIG_DIR or ~/.claude).
  -f, --force           Replace an unrelated statusLine command.
  -h, --help            Show help.

Copies the stable launcher to DIR/claude-statusline/ and points statusLine at it, so
plugin updates reach the status line without editing settings again.
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
# shellcheck source=../config/load-identity.sh
. "$plugin_root/config/load-identity.sh"
load_identity "$plugin_root/config/identity.env"
# shellcheck source=../config/constants.sh
. "$plugin_root/config/constants.sh"

launcher_home=$config_dir/$LAUNCHER_HOME
mkdir -p "$launcher_home/scripts" "$launcher_home/config"
cp "$plugin_root/scripts/statusline-launch.sh" "$plugin_root/scripts/statusline-launch.ps1" "$launcher_home/scripts/"
cp "$plugin_root/config/identity.env" "$plugin_root/config/load-identity.sh" "$launcher_home/config/"
chmod +x "$launcher_home/scripts/statusline-launch.sh"

# Keep the portable ~ form for the default profile so a shared settings file stays host-neutral.
if [[ $config_dir == "$HOME/.claude" ]]; then
  command="bash ~/.claude/$LAUNCHER_HOME/scripts/statusline-launch.sh"
else
  command="bash $launcher_home/scripts/statusline-launch.sh"
fi
settings=$config_dir/settings.json

if [[ -r $settings ]]; then
  # Strip the resize watcher's nonce before the ownership check.
  current=$(jq -r --arg nonce "$NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END" '(.statusLine.command//empty)|sub($nonce; "")' "$settings")
  if [[ -n $current && ! $current =~ $OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE && $current != 'bash ~/.claude/statusline-dispatcher.sh' && $force -eq 0 ]]; then
    printf 'Refusing to replace unrelated statusLine command: %s\n' "$current" >&2
    exit 1
  fi
  tmp=$(mktemp "$config_dir/.settings.XXXXXX")
  jq --arg cmd "$command" --arg id "$PLUGIN_ID" '.statusLine={type:"command",command:$cmd} | .enabledPlugins[$id]=true' "$settings" >"$tmp"
  mv "$tmp" "$settings"
else
  jq -n --arg cmd "$command" --arg id "$PLUGIN_ID" '{statusLine:{type:"command",command:$cmd},enabledPlugins:{($id):true}}' >"$settings"
fi

printf 'Installed Claude status line for %s\n' "$config_dir"

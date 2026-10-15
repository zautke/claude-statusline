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

plugin="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

jq -e '.name=="braisenly-statusline" and .version=="1.0.0"' "$plugin/.claude-plugin/plugin.json" >/dev/null
jq -e '.skill_name=="configure-statusline" and (.evals|length)==4' "$plugin/skills/configure-statusline/evals/evals.json" >/dev/null
[[ $(head -n 1 "$plugin/scripts/statusline-command.sh") == '#!/usr/bin/env bash' ]]
[[ $(head -n 1 "$plugin/scripts/statusline-command.ps1") == '#!/usr/bin/env pwsh' ]]
[[ $(head -n 1 "$plugin/scripts/install.sh") == '#!/usr/bin/env bash' ]]
[[ $(head -n 1 "$plugin/scripts/install.ps1") == '#!/usr/bin/env pwsh' ]]

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
bash "$plugin/scripts/install.sh" --config-dir "$temp/profile" >/dev/null
jq -e '.enabledPlugins["braisenly-statusline@dot-agents"]==true and (.statusLine.command|contains("braisenly-statusline/scripts/statusline-dispatcher.sh"))' "$temp/profile/settings.json" >/dev/null
printf 'ok\n'

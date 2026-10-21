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
# shellcheck source=../config/load-identity.sh
. "$plugin/config/load-identity.sh"
load_identity "$plugin/config/identity.env"
# shellcheck source=../config/constants.sh
. "$plugin/config/constants.sh"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
stamp_ok() { [[ $1 =~ $ORG_VERSION_STAMP_FOUR_DOTTED_INTEGERS_THEN_HYPHEN_LOWERCASE_BRANCH ]]; }

# Manifests agree with config/identity.env.
jq -e --arg n "$PLUGIN_NAME" '.name==$n' "$plugin/.claude-plugin/plugin.json" >/dev/null || fail 'plugin.json name'
stamp_ok "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" || fail 'plugin.json version is not MAJOR.MINOR.PATCH.BUILD-<branch>'
jq -e --arg m "$MARKETPLACE" --arg n "$PLUGIN_NAME" '.name==$m and (.plugins|length)==1 and .plugins[0].name==$n and .plugins[0].source=="."' \
  "$plugin/.claude-plugin/marketplace.json" >/dev/null || fail 'marketplace.json identity'
# Every client manifest carries the Claude manifest's identity fields unchanged; the Agent
# Plugins root manifest pins the 1.0.0 schema.
identity='{name,version,description,author,license,keywords}'
want=$(jq -cS "$identity" "$plugin/.claude-plugin/plugin.json")
for m in plugin.json .codex-plugin/plugin.json .github/plugin/plugin.json; do
  [[ $(jq -cS "$identity" "$plugin/$m") == "$want" ]] || fail "$m identity differs from .claude-plugin/plugin.json"
done
jq -e '."$schema"=="https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"' "$plugin/plugin.json" >/dev/null || fail 'plugin.json $schema'
jq -e --arg m "$MARKETPLACE" --arg n "$PLUGIN_NAME" '.name==$m and .plugins[0].name==$n and .plugins[0].source=={source:"local",path:"./"}' \
  "$plugin/.agents/plugins/marketplace.json" >/dev/null || fail 'codex marketplace identity'
jq -e --arg m "$MARKETPLACE" --arg n "$PLUGIN_NAME" '.name==$m and .plugins[0].name==$n and .plugins[0].source=="."' \
  "$plugin/.github/plugin/marketplace.json" >/dev/null || fail 'copilot marketplace identity'
jq -e '.skill_name=="configure-statusline" and (.evals|length)==4' "$plugin/skills/configure-statusline/evals/evals.json" >/dev/null || fail 'skill evals'
jq empty "$plugin/interface.json" || fail 'interface.json'
for s in statusline-command statusline-launch install; do
  [[ $(head -n 1 "$plugin/scripts/$s.sh") == '#!/usr/bin/env bash' ]] || fail "$s.sh shebang"
  [[ $(head -n 1 "$plugin/scripts/$s.ps1") == '#!/usr/bin/env pwsh' ]] || fail "$s.ps1 shebang"
done

# Negative: a 3-part SemVer is rejected by the org stamp (PASS = rejected).
if stamp_ok '1.2.0'; then fail 'negative: 3-part version accepted'; fi
if stamp_ok '1.2.0.0-feat/x'; then fail 'negative: slash in branch accepted'; fi

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
profile=$temp/profile

# Fresh install: launcher copied, statusLine points at it, plugin enabled.
bash "$plugin/scripts/install.sh" --config-dir "$profile" >/dev/null
launcher=$profile/$LAUNCHER_HOME/scripts/statusline-launch.sh
[[ -x $launcher && -f $profile/$LAUNCHER_HOME/config/identity.env ]] || fail 'launcher not copied'
jq -e --arg id "$PLUGIN_ID" --arg cmd "bash $launcher" '.enabledPlugins[$id]==true and .statusLine.command==$cmd' "$profile/settings.json" >/dev/null || fail 'fresh install settings'

# Idempotent: a second run leaves settings byte-identical.
before=$(cksum <"$profile/settings.json")
bash "$plugin/scripts/install.sh" --config-dir "$profile" >/dev/null
[[ $(cksum <"$profile/settings.json") == "$before" ]] || fail 'install not idempotent'

# Migration: legacy Braisenly commands (stale clone on adagio, old cache path, nonce) are taken over.
for legacy in \
  'pwsh -NoProfile -NonInteractive -File "C:\Users\me\braisenly-statusline\scripts\statusline-command.ps1"' \
  'bash ~/braisenly-statusline/scripts/statusline-dispatcher.sh # bsl-cols=120' \
  'bash /x/.claude/plugins/cache/braisenly/braisenly-statusline/1.1.0/scripts/statusline-dispatcher.sh'; do
  jq --arg c "$legacy" '.statusLine.command=$c' "$profile/settings.json" >"$temp/s" && mv "$temp/s" "$profile/settings.json"
  bash "$plugin/scripts/install.sh" --config-dir "$profile" >/dev/null || fail "migration refused: $legacy"
  jq -e --arg cmd "bash $launcher" '.statusLine.command==$cmd' "$profile/settings.json" >/dev/null || fail "migration: $legacy"
done

# Negative: an unrelated command is refused with the declared message and the file is untouched.
jq '.statusLine.command="echo mine"' "$profile/settings.json" >"$temp/s" && mv "$temp/s" "$profile/settings.json"
before=$(cksum <"$profile/settings.json")
if err=$(bash "$plugin/scripts/install.sh" --config-dir "$profile" 2>&1 >/dev/null); then fail 'negative: unrelated command replaced'; fi
[[ $err == 'Refusing to replace unrelated statusLine command: echo mine' ]] || fail "negative: wrong message: $err"
[[ $(cksum <"$profile/settings.json") == "$before" ]] || fail 'negative: settings changed on refusal'

printf 'ok\n'

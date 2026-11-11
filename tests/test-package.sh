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
semver_ok() { [[ $1 =~ $PLAIN_SEMVER_MAJOR_DOT_MINOR_DOT_PATCH_DIGITS_ONLY ]]; }

# Manifests agree with config/identity.env.
jq -e --arg n "$PLUGIN_NAME" '.name==$n' "$plugin/.claude-plugin/plugin.json" >/dev/null || fail 'plugin.json name'
semver_ok "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" || fail 'plugin.json version is not plain SemVer MAJOR.MINOR.PATCH'
jq -e --arg m "$MARKETPLACE" --arg n "$PLUGIN_NAME" '.name==$m and (.plugins|length)==1 and .plugins[0].name==$n and .plugins[0].source=="."' \
  "$plugin/.claude-plugin/marketplace.json" >/dev/null || fail 'marketplace.json identity'
jq -e '.skill_name=="configure-statusline" and (.evals|length)==4' "$plugin/skills/configure-statusline/evals/evals.json" >/dev/null || fail 'skill evals'
# Reset-toggle identity keys exist (usage sites are asserted as they land).
[[ ${RESETS_COMMAND_NAME:-} == statusline-resets ]] || fail 'identity RESETS_COMMAND_NAME'
[[ ${URL_SCHEME:-} == claude-statusline ]] || fail 'identity URL_SCHEME'
# Claude Code only: no other client's manifests ship.
for m in plugin.json .codex-plugin .github/plugin .agents/plugins interface.json; do
  [[ ! -e $plugin/$m ]] || fail "non-Claude manifest present: $m"
done
for s in statusline-command statusline-launch install resets-toggle; do
  [[ $(head -n 1 "$plugin/scripts/$s.sh") == '#!/usr/bin/env bash' ]] || fail "$s.sh shebang"
  [[ $(head -n 1 "$plugin/scripts/$s.ps1") == '#!/usr/bin/env pwsh' ]] || fail "$s.ps1 shebang"
  grep -q '^Usage() {' "$plugin/scripts/$s.sh" || fail "$s.sh has no Usage()"
  grep -q '^function Usage {' "$plugin/scripts/$s.ps1" || fail "$s.ps1 has no Usage"
done

# Negative: the org 4-part stamp and branch suffixes are rejected (PASS = rejected); marketplaces need plain SemVer.
if semver_ok '1.2.0.0'; then fail 'negative: 4-part version accepted'; fi
if semver_ok '1.2.0-feat-x'; then fail 'negative: branch suffix accepted'; fi

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

# Other settings values survive an install verbatim (ISO-8601 strings: the ps1 twin once rewrote them through PS7's DateTime).
mkdir -p "$temp/iso-profile"
printf '{"x-test-date":"2026-11-15T13:59:59Z","x-test-frac":"2026-11-15T20:59:59.567363+00:00"}' >"$temp/iso-profile/settings.json"
bash "$plugin/scripts/install.sh" --config-dir "$temp/iso-profile" >/dev/null
jq -e '.["x-test-date"]=="2026-11-15T13:59:59Z" and .["x-test-frac"]=="2026-11-15T20:59:59.567363+00:00"' "$temp/iso-profile/settings.json" >/dev/null || fail 'install rewrote ISO dates'

# Migration: commands under the legacy braisenly-statusline name (stale clone on adagio, old
# cache path, nonce, the launcher under its first name) are taken over.
for legacy in \
  'pwsh -NoProfile -NonInteractive -File "C:\Users\me\braisenly-statusline\scripts\statusline-command.ps1"' \
  'bash ~/braisenly-statusline/scripts/statusline-dispatcher.sh # bsl-cols=120' \
  'bash /x/.claude/plugins/cache/braisenly/braisenly-statusline/1.1.0/scripts/statusline-dispatcher.sh' \
  'pwsh -NoProfile -NonInteractive -File "C:\Users\me\.claude\braisenly-statusline\scripts\statusline-launch.ps1"'; do
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

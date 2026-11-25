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
jq -e '.skill_name=="configure-statusline" and (.evals|length)==5' "$plugin/skills/configure-statusline/evals/evals.json" >/dev/null || fail 'skill evals'
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

# Reset-toggle identity: installers and launchers take the chord, command name and URL scheme from
# identity.env / constants, never as literals; hooks/register.js (JS, cannot read them) must match identity.env.
for f in install.sh install.ps1 statusline-launch.sh statusline-launch.ps1; do
  for lit in "$RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R" "$RESETS_COMMAND_NAME" "$URL_SCHEME://"; do
    if grep -qiF -- "$lit" "$plugin/scripts/$f"; then fail "$f hardcodes '$lit'"; fi
  done
done
for f in install.sh install.ps1; do
  grep -q 'RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R' "$plugin/scripts/$f" && grep -q 'RESETS_COMMAND_NAME' "$plugin/scripts/$f" &&
    grep -q 'URL_SCHEME' "$plugin/scripts/$f" || fail "$f does not take chord/command/scheme from constants/identity"
done
# Mod manifest: exactly the one module, nothing else (parsed, so whitespace does not matter).
jq -e '. == {"hooks":{},"modules":["./register.js"]}' "$plugin/hooks/hooks.json" >/dev/null || fail 'hooks.json is not {"hooks":{},"modules":["./register.js"]}'
# register.js: every command name it registers or listens for equals identity.env; every script path it builds exists.
[[ -f $plugin/hooks/register.js ]] || fail 'hooks/register.js missing'
command_name_literals() { grep -oE "(name|command): *['\"][^'\"]*['\"]" | sed -E "s/^[a-z]+: *['\"]//; s/['\"]\$//"; }
reg_names=$(command_name_literals <"$plugin/hooks/register.js")
[[ -n $reg_names ]] || fail 'register.js: no command name found'
while IFS= read -r n; do
  [[ $n == "$RESETS_COMMAND_NAME" ]] || fail "register.js command name '$n' differs from identity.env RESETS_COMMAND_NAME"
done <<<"$reg_names"
reg_scripts=$(grep -oE 'scripts/[A-Za-z0-9_.-]+' "$plugin/hooks/register.js" | sort -u | tr '\n' ' ')
[[ $reg_scripts == 'scripts/resets-toggle.ps1 scripts/resets-toggle.sh ' ]] || fail "register.js builds unexpected script paths: $reg_scripts"
for s in $reg_scripts; do [[ -f $plugin/$s ]] || fail "register.js script missing: $s"; done
# Negative: a command name that drifted from identity.env is caught (PASS = differs).
drift=$(printf "x({name: 'statusline-resetz'})" | command_name_literals)
[[ -n $drift && $drift != "$RESETS_COMMAND_NAME" ]] || fail 'negative: drifted command name not detected'
# Install Usage lists every flag, in both twins.
for s in install.sh install.ps1; do
  for flag in '-c, --config-dir' '-f, --force' '-U, --uninstall' '-W, --no-wt-scheme' '-h, --help'; do
    grep -qF -- "$flag" "$plugin/scripts/$s" || fail "$s Usage lacks $flag"
  done
done

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
profile=$temp/profile
# The installer also registers a click handler: keep HOME, XDG dirs and tools inside the sandbox.
# CLAUDE_STATUSLINE_UNAME=none: no handler on any OS, so macOS CI never runs the real osacompile/PlistBuddy/lsregister.
export HOME=$temp/home XDG_DATA_HOME=$temp/xdg-data XDG_CONFIG_HOME=$temp/xdg-config CLAUDE_STATUSLINE_XDG_MIME=$temp/no-xdg-mime CLAUDE_STATUSLINE_UNAME=none
[[ $HOME == "$temp"/* && $XDG_DATA_HOME == "$temp"/* && $CLAUDE_STATUSLINE_UNAME == none ]] || { printf 'ABORT: isolation overrides unset\n' >&2; exit 3; }

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

# Example config: opts into reset times, puts the `resets` ladder step first, and the bash renderer accepts it whole.
# Validation is all-or-nothing (a rejected file silently falls back to defaults), so a distinctive label proves it was used.
jq -e '.resets==true and .resets_format=="clock" and .fit.ladder[0]=="resets"' "$plugin/statusline.example.json" >/dev/null || fail 'example config lacks resets / resets_format / ladder step'
ex=$temp/example-profile; mkdir -p "$ex" "$temp/cache"
jq '.labels.five_hour="ZZ"' "$plugin/statusline.example.json" >"$ex/statusline.json"
payload='{"model":{"display_name":"Claude"},"rate_limits":{"five_hour":{"used_percentage":20,"resets_at":1794435180},"seven_day":{"used_percentage":30,"resets_at":1794794400}}}'
render() { printf '%s' "$payload" | NO_COLOR=1 CLAUDE_CONFIG_DIR="$1" XDG_CACHE_HOME="$temp/cache" CLAUDE_STATUSLINE_DISABLE_REFRESH=1 CLAUDE_STATUSLINE_NOW=1794427200 COLUMNS=300 bash "$plugin/scripts/statusline-command.sh"; }
out=$(render "$ex")
[[ $out == *'ZZ ['* && $out == *'↻'* ]] || fail "bash renderer did not accept statusline.example.json: $out"
# Negative: the same file with an unknown ladder step is rejected, so defaults (label 5h) resume (PASS = fallback seen).
jq '.fit.ladder+=["bogus"]' "$ex/statusline.json" >"$ex/bad.json" && mv "$ex/bad.json" "$ex/statusline.json"
out=$(render "$ex")
[[ $out != *'ZZ ['* && $out == *'5h ['* ]] || fail "negative: invalid example did not fall back to defaults: $out"

printf 'ok\n'

#!/usr/bin/env bash
# Launcher contract: resolves the installed plugin version from installed_plugins.json, prefers the
# user-scope record, passes stdin through, and degrades to one fixed line with exit 0.
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

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
profile=$temp/profile
# The installer also registers a click handler: keep HOME, XDG dirs and tools inside the sandbox.
export HOME=$temp/home XDG_DATA_HOME=$temp/xdg-data XDG_CONFIG_HOME=$temp/xdg-config CLAUDE_STATUSLINE_XDG_MIME=$temp/no-xdg-mime
[[ $HOME == "$temp"/* && $XDG_DATA_HOME == "$temp"/* ]] || { printf 'ABORT: isolation overrides unset\n' >&2; exit 3; }
bash "$plugin/scripts/install.sh" --config-dir "$profile" >/dev/null
launcher=$profile/$LAUNCHER_HOME/scripts/statusline-launch.sh
state=$profile/plugins/installed_plugins.json
mkdir -p "$profile/plugins"

# Two fixture plugin versions whose dispatcher echoes a marker plus its stdin.
for v in user project; do
  mkdir -p "$temp/$v/scripts"
  printf '#!/usr/bin/env bash\nprintf "%s:%%s\\n" "$(cat)"\n' "$v" >"$temp/$v/scripts/statusline-dispatcher.sh"
done
record() { jq -n --arg id "$PLUGIN_ID" --arg u "$1" --arg p "$2" \
  '{version:2, plugins:{($id):[{scope:"project", installPath:$p}, {scope:"user", installPath:$u}]}}' >"$state"; }

# Positive: user scope wins over an earlier project record; stdin reaches the renderer.
record "$temp/user" "$temp/project"
[[ $(printf '{"x":1}' | bash "$launcher") == 'user:{"x":1}' ]] || fail 'user-scope record not chosen'

# --url passthrough: the chosen version's resets-toggle gets the URL as one argv element; its exit code propagates.
for v in user project; do
  printf '#!/usr/bin/env bash\nIFS="|"; printf "%s-toggle:%%s\\n" "$*"; exit 7\n' "$v" >"$temp/$v/scripts/resets-toggle.sh"
done
u='claude-statusline://toggle?slot=5h&profile=a b;$(x)'
for form in --url -u; do
  rc=0; out=$(bash "$launcher" "$form" "$u") || rc=$?
  [[ $rc -eq 7 && $out == "user-toggle:--url|$u" ]] || fail "$form passthrough: rc=$rc out=$out"
done
rc=0; bash "$launcher" --url >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 ]] || fail "negative --url without value: rc=$rc"

# Positive: CLAUDE_CODE_PLUGIN_CACHE_DIR overrides the sibling plugins/ dir.
mkdir -p "$temp/alt" && jq -n --arg id "$PLUGIN_ID" --arg u "$temp/project" '{plugins:{($id):[{scope:"user", installPath:$u}]}}' >"$temp/alt/installed_plugins.json"
[[ $(printf 'y' | CLAUDE_CODE_PLUGIN_CACHE_DIR=$temp/alt bash "$launcher") == 'project:y' ]] || fail 'cache dir override ignored'

# Negatives: PASS = exactly the declared line on stdout and exit 0.
expect_not_installed() {
  local out rc=0
  out=$(printf '{}' | bash "$launcher") || rc=$?
  [[ $rc -eq 0 && $out == "$NOT_INSTALLED_MESSAGE" ]] || fail "negative $1: rc=$rc out=$out"
  # --url with nothing installed: the same message, but a failure exit (the click must not look handled).
  rc=0; out=$(bash "$launcher" --url 'claude-statusline://toggle?slot=5h' 2>&1) || rc=$?
  [[ $rc -eq 1 && $out == "$NOT_INSTALLED_MESSAGE" ]] || fail "negative --url $1: rc=$rc out=$out"
}
jq -n '{version:2, plugins:{}}' >"$state";                    expect_not_installed 'missing record'
printf '{not json' >"$state";                                  expect_not_installed 'malformed json'
record "$temp/gone-user" "$temp/gone-project";                 expect_not_installed 'installPath gone'
rm -f "$state";                                                expect_not_installed 'no installed_plugins.json'

[[ $(bash "$launcher" --help | head -n 1) == 'Usage: statusline-launch.sh [-u|--url URI] [-h|--help]' ]] || fail 'usage'
printf 'ok\n'

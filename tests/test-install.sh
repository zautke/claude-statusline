#!/usr/bin/env bash
# Installer contract (bash side): flag parsing, symlinked settings, keybinding merge, URL handler (Linux .desktop,
# macOS applet via stubbed tools, WSL skip) and --uninstall. Same cases as tests/test-install.ps1 where the OS allows.
# Every run is isolated: temp HOME, XDG dirs and stub tools; nothing outside the temp dir is written.
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
installer=$plugin/scripts/install.sh

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
export HOME=$temp/home XDG_DATA_HOME=$temp/xdg-data XDG_CONFIG_HOME=$temp/xdg-config
export CLAUDE_STATUSLINE_XDG_MIME=$temp/bin/xdg-mime CLAUDE_STATUSLINE_OSACOMPILE=$temp/bin/osacompile
export CLAUDE_STATUSLINE_PLISTBUDDY=$temp/bin/PlistBuddy CLAUDE_STATUSLINE_LSREGISTER=$temp/bin/lsregister
unset CLAUDE_CONFIG_DIR
# Guard: never run the installer unless every override points into this test's sandbox.
for v in HOME XDG_DATA_HOME XDG_CONFIG_HOME CLAUDE_STATUSLINE_XDG_MIME CLAUDE_STATUSLINE_OSACOMPILE CLAUDE_STATUSLINE_PLISTBUDDY CLAUDE_STATUSLINE_LSREGISTER; do
  [[ -n ${!v:-} && ${!v} == "$temp"/* ]] || { printf 'ABORT: %s unset or outside the sandbox; refusing to run the installer\n' "$v" >&2; exit 3; }
done

# Stub tools: each logs its argv; osacompile builds a bundle skeleton and keeps the source for inspection.
mkdir -p "$temp/bin"
for t in xdg-mime PlistBuddy lsregister; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >>"%s/%s.log"\n' "$temp" "$t" >"$temp/bin/$t"
done
cat >"$temp/bin/osacompile" <<EOF
#!/usr/bin/env bash
[[ \$1 == -o ]] || exit 9
mkdir -p "\$2/Contents/Resources" && : >"\$2/Contents/Info.plist" && cp "\$3" "$temp/applet.src"
EOF
chmod +x "$temp/bin/"*

chord=$RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R
cmd=command:$RESETS_COMMAND_NAME
tree() { [[ -e $1 ]] || { printf '<absent>'; return; }; (cd "$1" && find . -print0 | sort -z | xargs -0 -I{} sh -c 'if [ -f "{}" ]; then printf "%s %s\n" "{}" "$(cksum <"{}")"; else printf "%s\n" "{}"; fi'); }
inst() { local rc=0; out=$(bash "$installer" "$@" 2>"$temp/err") || rc=$?; err=$(cat "$temp/err"); return "$rc"; }
rc_of() { local rc=0; inst "$@" || rc=$?; printf '%s' "$rc"; }
canon() { jq -cS . "$1"; }
# Plain Linux unless a case says otherwise (this suite runs under WSL, which sets WSL_DISTRO_NAME).
unset WSL_DISTRO_NAME
export CLAUDE_STATUSLINE_UNAME=Linux

home0=$HOME/.claude
mkdir -p "$home0" && printf 'do not touch' >"$home0/sentinel.txt"
home_tree=$(tree "$home0")

# ---- 1. Flag parsing (negatives: PASS = exit 2, Usage on stderr, nothing written) ----
for bad in --bogus stray -c --config-dir -u -F; do
  rc=0; bash "$installer" $bad >/dev/null 2>"$temp/err" || rc=$?
  [[ $rc -eq 2 ]] && grep -q '^Usage: install\.sh' "$temp/err" || fail "negative flag $bad: rc=$rc"
  [[ $(tree "$home0") == "$home_tree" ]] || fail "negative flag $bad wrote under HOME"
  [[ ! -e $XDG_DATA_HOME && ! -e $temp/xdg-mime.log ]] || fail "negative flag $bad registered a handler"
done
help=$(bash "$installer" --help)
for f in '-c, --config-dir' '-f, --force' '-U, --uninstall' '-W, --no-wt-scheme' '-h, --help'; do
  [[ $help == *"$f"* ]] || fail "Usage lacks $f"
done

# Positive: --config-dir and -c write only under the given dir; HOME/.claude stays untouched.
for form in --config-dir -c; do
  cfg=$temp/cfg$form
  inst "$form" "$cfg" || fail "$form install: $err"
  [[ -f $cfg/settings.json ]] || fail "$form did not write under $cfg"
  [[ $(tree "$home0") == "$home_tree" ]] || fail "$form touched HOME/.claude"
done

# --force / -f replace an unrelated statusLine; without it the install refuses (exit 1, file untouched).
cfg=$temp/force; mkdir -p "$cfg"
for form in --force -f; do
  printf '{"statusLine":{"type":"command","command":"echo mine"}}' >"$cfg/settings.json"
  [[ $(rc_of -c "$cfg") -eq 1 && $(cat "$cfg/settings.json") == '{"statusLine":{"type":"command","command":"echo mine"}}' ]] || fail 'negative unforced'
  inst -c "$cfg" "$form" || fail "$form: $err"
  jq -e '.statusLine.command | test("statusline-launch\\.sh")' "$cfg/settings.json" >/dev/null || fail "$form not honoured"
done

# ---- 2. Symlinked settings.json: the target is written, the link survives ----
cfg=$temp/link; mkdir -p "$cfg" "$temp/dotfiles"
printf '{"model":"opus"}' >"$temp/dotfiles/settings.json"
ln -s "$temp/dotfiles/settings.json" "$cfg/settings.json"
inst -c "$cfg" || fail "symlink install: $err"
[[ -L $cfg/settings.json ]] || fail 'settings.json symlink replaced by a file'
jq -e '.model=="opus" and (.statusLine.command | test("statusline-launch\\.sh"))' "$temp/dotfiles/settings.json" >/dev/null || fail 'symlink target not written'

# ---- 2b. statusLine is merged: a re-install keeps refreshInterval (countdown) and user keys such as padding ----
cfg=$temp/merge; mkdir -p "$cfg"
printf '%s' '{"statusLine":{"type":"command","command":"bash ~/.claude/claude-statusline/scripts/statusline-launch.sh # bsl-cols=9","refreshInterval":60,"padding":2}}' >"$cfg/settings.json"
inst -c "$cfg" || fail "merge install: $err"
jq -e '.statusLine.refreshInterval==60 and .statusLine.padding==2 and .statusLine.type=="command" and (.statusLine.command | test("statusline-launch\\.sh$"))' "$cfg/settings.json" >/dev/null || fail "statusLine not merged: $(cat "$cfg/settings.json")"

# ---- 3. Keybinding merge ----
cfg=$temp/kb; kb=$cfg/keybindings.json
inst -c "$cfg" || fail "kb install: $err"
jq -e --arg c "$chord" --arg v "$cmd" 'has("$schema") and (.bindings|length)==1 and .bindings[0].context=="Chat" and .bindings[0].bindings[$c]==$v' "$kb" >/dev/null || fail "absent keybindings: $(cat "$kb")"
before=$(cksum <"$kb"); inst -c "$cfg"
[[ $(cksum <"$kb") == "$before" ]] || fail 'keybinding merge not idempotent'

printf '%s' '{"bindings":[{"context":"Global","bindings":{"ctrl+t":"app:toggleTodos"}},{"context":"Chat","bindings":{"shift+enter":"chat:newline"}},{"context":"Chat","bindings":{}}]}' >"$kb"
inst -c "$cfg"
jq -e --arg c "$chord" --arg v "$cmd" '(.bindings|length)==3 and .bindings[0].bindings["ctrl+t"]=="app:toggleTodos" and .bindings[1].bindings["shift+enter"]=="chat:newline" and .bindings[1].bindings[$c]==$v and (.bindings[2].bindings|length)==0' "$kb" >/dev/null || fail "merge: $(cat "$kb")"

for t in '{"bindings":[{"context":"Chat","bindings":{"Ctrl+X  R":"chat:killAgents"}}]}' '{"bindings":[{"context":"Chat",' '{"bindings":{}}' $'{\n  // mine\n  "bindings": []\n}'; do
  printf '%s' "$t" >"$kb"
  inst -c "$cfg" || fail "negative keybinding '$t' failed the install: $err"
  [[ $(cat "$kb") == "$t" && $err == *keybindings* ]] || fail "negative keybinding '$t': err=$err now=$(cat "$kb")"
done

# A symlinked keybindings.json that would be left holding nothing of the user's keeps its link and target.
cfgl=$temp/kb-link; mkdir -p "$cfgl" "$temp/dotfiles"
jq -n --arg s "$CLAUDE_CODE_KEYBINDINGS_JSON_SCHEMA_URL" '{"$schema": $s, bindings: []}' >"$temp/dotfiles/keybindings.json"
ln -s "$temp/dotfiles/keybindings.json" "$cfgl/keybindings.json"
inst -c "$cfgl"; inst -c "$cfgl" -U
[[ -L $cfgl/keybindings.json && -f $temp/dotfiles/keybindings.json ]] || fail 'uninstall deleted a symlinked keybindings.json or its target'
! grep -qF "$cmd" "$temp/dotfiles/keybindings.json" || fail 'uninstall left our binding in the symlink target'

printf '%s' '{"bindings":[{"context":"Chat","bindings":{"shift+enter":"chat:newline"}}]}' >"$kb"
inst -c "$cfg"; inst -c "$cfg" --uninstall
[[ $(canon "$kb") == '{"bindings":[{"bindings":{"shift+enter":"chat:newline"},"context":"Chat"}]}' ]] || fail "uninstall keybinding: $(cat "$kb")"

# ---- 4. URL handler ----
desktop=$XDG_DATA_HOME/applications/$URL_SCHEME-toggle.desktop
# Linux: .desktop + xdg-mime default; marker only after success.
cfg=$temp/url; marker=$cfg/$LAUNCHER_HOME/url-handler; launcher=$cfg/$LAUNCHER_HOME/scripts/statusline-launch.sh
rm -f "$temp/xdg-mime.log"
inst -c "$cfg" || fail "linux url install: $err"
grep -qxF "Exec=bash \"$launcher\" --url %u" "$desktop" && grep -qxF "MimeType=x-scheme-handler/$URL_SCHEME;" "$desktop" && grep -qxF 'NoDisplay=true' "$desktop" || fail "desktop file: $(cat "$desktop")"
grep -qxF "default $URL_SCHEME-toggle.desktop x-scheme-handler/$URL_SCHEME" "$temp/xdg-mime.log" || fail 'xdg-mime default not called'
[[ -f $marker ]] || fail 'linux marker not written'
# Another profile takes the handler; uninstalling this profile leaves it, and the mimeapps.list default with it.
# (The xdg-mime stub only logs, so the test writes the line xdg-mime default would have written.)
mime=$XDG_CONFIG_HOME/mimeapps.list mime_line=x-scheme-handler/$URL_SCHEME=$URL_SCHEME-toggle.desktop
mkdir -p "$XDG_CONFIG_HOME"; printf '[Default Applications]\n%s\ntext/html=firefox.desktop\n' "$mime_line" >"$mime"
cfgb=$temp/url-b
inst -c "$cfgb"; inst -c "$cfg" -U
[[ -f $desktop ]] && grep -qF "$cfgb/" "$desktop" || fail 'uninstall removed another profile''s handler'
grep -qxF "$mime_line" "$mime" || fail 'uninstall removed the mimeapps.list default of another profile''s handler'
[[ ! -e $marker ]] || fail 'uninstall left this profile''s marker'
inst -c "$cfgb" --uninstall
[[ ! -e $desktop ]] || fail 'uninstall left our own .desktop'
[[ $(cat "$mime") == $'[Default Applications]\ntext/html=firefox.desktop' ]] || fail "uninstall left the mimeapps.list default: $(cat "$mime")"
[[ ! -e $cfgb/keybindings.json ]] || fail 'uninstall left the keybindings.json it created'

# Several profiles under HOME: uninstalling the one that holds the handler moves it to another profile that still
# draws links (has the marker); the last uninstall removes it.
pa=$HOME/.claude-m2a pb=$HOME/.claude-m2b
printf '[Default Applications]\n%s\n' "$mime_line" >"$mime"
inst -c "$pb"; inst -c "$pa"
grep -qF "$pa/" "$desktop" || fail 'multi-profile: second install did not take the handler'
inst -c "$pa" -U || fail "multi-profile uninstall: $err"
grep -qxF "Exec=bash \"$pb/$LAUNCHER_HOME/scripts/statusline-launch.sh\" --url %u" "$desktop" || fail "multi-profile: handler not moved: $(cat "$desktop")"
grep -qxF "$mime_line" "$mime" || fail 'multi-profile: mimeapps.list default removed while the handler moved'
inst -c "$pb" -U
[[ ! -e $desktop ]] && ! grep -qF "$mime_line" "$mime" || fail 'multi-profile: last uninstall left the handler'
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pb"; CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pa"
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pa" -U || fail "multi-profile mac uninstall: $err"
app=$HOME/Applications/$URL_SCHEME-toggle.app
[[ -d $app && $(cat "$app/Contents/Resources/$LAUNCHER_HOME-launcher") == "$pb/$LAUNCHER_HOME/scripts/statusline-launch.sh" ]] || fail 'multi-profile: applet not moved'
grep -qF "$pb/$LAUNCHER_HOME/scripts/statusline-launch.sh" "$temp/applet.src" || fail 'multi-profile: applet not rebuilt for the other profile'
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pb" -U
[[ ! -e $app ]] || fail 'multi-profile: last mac uninstall left the applet'
# A non-canonical --config-dir ($pa/.) names the same profile: the handler is still recognised as its own and is
# never re-pointed at the launcher the uninstall is about to delete.
inst -c "$pb"; inst -c "$pa"
inst -c "$pa/." -U || fail "non-canonical uninstall: $err"
grep -qxF "Exec=bash \"$pb/$LAUNCHER_HOME/scripts/statusline-launch.sh\" --url %u" "$desktop" || fail "non-canonical config dir: handler not moved to the other profile: $(cat "$desktop")"
inst -c "$pb" -U
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pb"; CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pa"
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pa/." -U || fail "non-canonical mac uninstall: $err"
[[ -d $app && $(cat "$app/Contents/Resources/$LAUNCHER_HOME-launcher") == "$pb/$LAUNCHER_HOME/scripts/statusline-launch.sh" ]] || fail 'non-canonical config dir: applet not moved to the other profile'
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$pb" -U
[[ ! -e $app && ! -e $desktop ]] || fail 'non-canonical config dir: last uninstall left a handler'
# Same through a symlink alias of the profile dir.
ln -s "$pa" "$temp/alias-m2a"
inst -c "$pb"; inst -c "$pa"
inst -c "$temp/alias-m2a" -U || fail "symlink-alias uninstall: $err"
grep -qxF "Exec=bash \"$pb/$LAUNCHER_HOME/scripts/statusline-launch.sh\" --url %u" "$desktop" || fail "symlink-alias config dir: handler not moved to the other profile: $(cat "$desktop")"
inst -c "$pb" -U
[[ ! -e $desktop ]] || fail 'symlink-alias config dir: last uninstall left the handler'

# Negative: xdg-mime missing -> note, no .desktop, no marker.
CLAUDE_STATUSLINE_XDG_MIME=$temp/bin/none inst -c "$cfg" || fail "no xdg-mime: $err"
[[ ! -e $desktop && ! -e $marker && $out == *xdg-mime* ]] || fail "negative no xdg-mime: out=$out"
# Negative: WSL -> skip registration, no marker.
WSL_DISTRO_NAME=Ubuntu inst -c "$cfg" || fail "wsl: $err"
[[ ! -e $desktop && ! -e $marker ]] || fail 'negative WSL registered a handler'

# macOS: applet compiled with the quoted launcher, URL types added, registered; uninstall removes it.
app=$HOME/Applications/$URL_SCHEME-toggle.app
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$cfg" || fail "mac install: $err"
grep -qxF 'on open location u' "$temp/applet.src" || fail 'applet handler'
# The applet's do shell script PATH is /usr/bin:/bin:/usr/sbin:/sbin; Homebrew's jq must be reachable.
grep -qF "do shell script \"PATH=/opt/homebrew/bin:/usr/local/bin:\$PATH bash \" & quoted form of \"$launcher\" & \" --url \" & quoted form of u" "$temp/applet.src" || fail "applet command: $(cat "$temp/applet.src")"
grep -qF "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $URL_SCHEME" "$temp/PlistBuddy.log" || fail 'plist URL scheme'
grep -qxF -- "-f $app" "$temp/lsregister.log" || fail 'lsregister -f'
[[ -d $app && -f $marker ]] || fail 'mac app or marker missing'
CLAUDE_STATUSLINE_UNAME=Darwin inst -c "$cfg" -U || fail "mac uninstall: $err"
[[ ! -e $app && ! -e $marker ]] || fail 'mac uninstall left the applet or marker'

# ---- 5. Round trip: install then uninstall restores the profile ----
cfg=$temp/roundtrip; mkdir -p "$cfg"
printf '%s' '{"model":"opus","enabledPlugins":{"x@y":true},"x-date":"2026-11-15T13:59:59Z"}' >"$cfg/settings.json"
printf '%s' '{"bindings":[{"context":"Chat","bindings":{"shift+enter":"chat:newline"}}]}' >"$cfg/keybindings.json"
snap_names=$(cd "$cfg" && find . | sort); snap_settings=$(canon "$cfg/settings.json"); snap_kb=$(canon "$cfg/keybindings.json")
inst -c "$cfg" || fail "round trip install: $err"
[[ -f $desktop ]] || fail 'round trip: handler not registered'
inst -c "$cfg" -U || fail "round trip uninstall: $err"
[[ $(cd "$cfg" && find . | sort) == "$snap_names" ]] || fail "round trip files: $(cd "$cfg" && find . | sort)"
[[ $(canon "$cfg/settings.json") == "$snap_settings" ]] || fail "round trip settings: $(cat "$cfg/settings.json")"
[[ $(canon "$cfg/keybindings.json") == "$snap_kb" ]] || fail 'round trip keybindings'
[[ ! -e $desktop ]] || fail 'round trip .desktop'

[[ $(tree "$home0") == "$home_tree" ]] || fail 'HOME/.claude changed during the run'
printf 'ok\n'

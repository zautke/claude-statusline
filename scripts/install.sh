#!/usr/bin/env bash
# Installs (or with --uninstall removes) the claude-statusline status line for one Claude profile: the stable
# launcher, statusLine + enabledPlugins in settings.json, the reset-time toggle chord in keybindings.json and the
# click URL handler (macOS applet, Linux .desktop; skipped under WSL, where Windows handles the click).
set -euo pipefail

Usage() {
  cat <<'EOF'
Usage: install.sh [-c|--config-dir DIR] [-f|--force] [-U|--uninstall] [-W|--no-wt-scheme] [-h|--help]

  -c, --config-dir DIR  Claude profile directory (default: CLAUDE_CONFIG_DIR or ~/.claude).
  -f, --force           Replace an unrelated statusLine command.
  -U, --uninstall       Remove only what this installer added.
  -W, --no-wt-scheme    Leave Windows Terminal settings alone (install.ps1 only; accepted here for parity).
  -h, --help            Show help.

Copies the stable launcher to DIR/claude-statusline/ and points statusLine at it, so plugin updates reach
the status line without editing settings again. Also binds the reset-time toggle chord in
DIR/keybindings.json and registers the handler for status-line clicks.
EOF
}

config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
force=0 uninstall=0
while (($#)); do
  case "$1" in
    -c|--config-dir) [[ $# -ge 2 ]] || { Usage >&2; exit 2; }; config_dir=$2; shift 2 ;;
    -f|--force) force=1; shift ;;
    -U|--uninstall) uninstall=1; shift ;;
    -W|--no-wt-scheme) shift ;;
    -h|--help) Usage; exit 0 ;;
    *) Usage >&2; exit 2 ;;
  esac
done
case $config_dir in /*) ;; *) config_dir=$PWD/$config_dir ;; esac

plugin_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck source=../config/load-identity.sh
. "$plugin_root/config/load-identity.sh"
load_identity "$plugin_root/config/identity.env"
# shellcheck source=../config/constants.sh
. "$plugin_root/config/constants.sh"

launcher_home=$config_dir/$LAUNCHER_HOME
launcher=$launcher_home/scripts/statusline-launch.sh
marker=$launcher_home/url-handler
chord=$RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R
bind=command:$RESETS_COMMAND_NAME

warn() { printf 'install.sh: %s\n' "$*" >&2; }
# Follow links so a dotfiles-managed file keeps its link (shared with the resets toggle).
resolve() { local t=$1 n=0 d; if readlink -f / >/dev/null 2>&1; then readlink -f "$t"; return; fi; while [[ -L $t && $n -lt 32 ]]; do d=$(dirname "$t"); t=$(readlink "$t"); [[ $t == /* ]] || t=$d/$t; n=$((n+1)); done; printf '%s' "$t"; }
# Temp file beside the target, original mode carried over, then rename.
atomic_write() {
  local dst=$1 tmp mode
  tmp=$(mktemp "${dst%/*}/.${dst##*/}.XXXXXX")
  printf '%s\n' "$2" >"$tmp"
  if [[ -e $dst ]]; then mode=$(stat -c %a "$dst" 2>/dev/null || stat -f %OLp "$dst" 2>/dev/null) && chmod "$mode" "$tmp"; fi
  mv "$tmp" "$dst" || { rm -f "$tmp"; return 1; }
}
owned() { [[ -z $1 || $1 =~ $OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE || $1 == 'bash ~/.claude/statusline-dispatcher.sh' ]]; }

# ---- settings.json (statusLine + enabledPlugins); a symlinked file is written through to its target ----
settings=$config_dir/settings.json
[[ -e $settings ]] && settings=$(resolve "$settings")
current=
if [[ -r $settings ]]; then
  # Strip the redraw nonce before the ownership check.
  current=$(jq -r --arg nonce "$NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END" '(.statusLine.command//empty)|sub($nonce; "")' "$settings" 2>/dev/null) ||
    { warn "$settings is not valid JSON; fix it and run again."; exit 1; }
fi
if ((!uninstall && !force)) && ! owned "$current"; then
  printf 'Refusing to replace unrelated statusLine command: %s\n' "$current" >&2
  exit 1
fi

# ---- keybindings.json: "<chord>": "command:<name>" in the first Chat block ----
kb=$config_dir/keybindings.json
[[ -e $kb ]] && kb=$(resolve "$kb")
JQ_NORM='def norm: ascii_downcase | gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");'
kb_usable() {
  jq -e '(type == "object") and (.bindings | type == "array")' "$kb" >/dev/null 2>&1 && return 0
  if jq empty "$kb" >/dev/null 2>&1; then warn "keybindings: $kb has no \"bindings\" array; left unchanged."
  else warn "keybindings: $kb is not valid JSON; left unchanged (bind $chord to $bind yourself)."; fi
  return 1
}
install_keybinding() {
  local first
  if [[ ! -e $kb ]]; then
    atomic_write "$kb" "$(jq -n --arg s "$CLAUDE_CODE_KEYBINDINGS_JSON_SCHEMA_URL" --arg c "$chord" --arg v "$bind" '{"$schema": $s, bindings: [{context: "Chat", bindings: {($c): $v}}]}')"
    printf 'Bound %s to /%s in %s\n' "$chord" "$RESETS_COMMAND_NAME" "$kb"; return
  fi
  kb_usable || return 0
  # The first entry with this chord (any spelling, any block) decides: ours -> done; anything else -> conflict.
  first=$(jq -r --arg c "$chord" --arg v "$bind" "$JQ_NORM"'
    first(.bindings[] | objects | .bindings | objects | to_entries[] | select(.key | norm == $c)) // empty
    | if .value == $v then "ours" else "\(.key) -> \(.value)" end' "$kb")
  [[ $first == ours ]] && return
  if [[ -n $first ]]; then warn "keybindings: $first is already bound in $kb; left unchanged."; return; fi
  atomic_write "$kb" "$(jq --arg c "$chord" --arg v "$bind" '
    (first(.bindings | to_entries[] | select((.value | type) == "object" and .value.context == "Chat") | .key) // null) as $i
    | if $i == null then .bindings += [{context: "Chat", bindings: {($c): $v}}]
      else .bindings[$i].bindings = ((.bindings[$i].bindings | if type == "object" then . else {} end) + {($c): $v}) end' "$kb")"
  printf 'Bound %s to /%s in %s\n' "$chord" "$RESETS_COMMAND_NAME" "$kb"
}
uninstall_keybinding() {
  local new
  [[ -e $kb ]] || return 0
  kb_usable || return 0
  # A Chat block emptied by removing our entry goes too; one that still holds user bindings stays.
  new=$(jq --arg c "$chord" --arg v "$bind" "$JQ_NORM"'
    def ours: (.key | norm) == $c and .value == $v;
    .bindings |= [ .[] | if type == "object" and .context == "Chat" and (.bindings | type) == "object" and (.bindings | to_entries | any(ours))
                         then (.bindings |= (to_entries | map(select(ours | not)) | from_entries)) | select(.bindings | length > 0)
                         else . end ]' "$kb")
  [[ $(jq -c . <<<"$new") == "$(jq -c . "$kb")" ]] && return
  # A file holding nothing but what install_keybinding creates is ours: remove it. A symlinked one (dotfiles) is
  # rewritten instead, so neither the link nor its target disappears.
  if [[ ! -L $config_dir/keybindings.json ]] && jq -e --arg s "$CLAUDE_CODE_KEYBINDINGS_JSON_SCHEMA_URL" '.bindings == [] and (keys == ["$schema", "bindings"]) and .["$schema"] == $s' <<<"$new" >/dev/null; then
    rm -f "$kb"; return
  fi
  atomic_write "$kb" "$new"
}

# ---- URL handler: macOS applet, Linux .desktop (tools and OS overridable for tests) ----
uname_s=${CLAUDE_STATUSLINE_UNAME:-$(uname -s)}
desktop_name=$URL_SCHEME-toggle.desktop
desktop=${XDG_DATA_HOME:-$HOME/.local/share}/applications/$desktop_name
mimeapps=${XDG_CONFIG_HOME:-$HOME/.config}/mimeapps.list
mime_default=x-scheme-handler/$URL_SCHEME=$desktop_name
app=$HOME/Applications/$URL_SCHEME-toggle.app
app_owner=$app/Contents/Resources/$LAUNCHER_HOME-launcher
xdg_mime=${CLAUDE_STATUSLINE_XDG_MIME:-xdg-mime}
osacompile=${CLAUDE_STATUSLINE_OSACOMPILE:-osacompile}
plistbuddy=${CLAUDE_STATUSLINE_PLISTBUDDY:-/usr/libexec/PlistBuddy}
lsregister=${CLAUDE_STATUSLINE_LSREGISTER:-/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister}
registered() { atomic_write "$marker" "$URL_SCHEME"; printf 'Registered the %s click handler.\n' "$URL_SCHEME"; }
# The .desktop entry that runs launcher $1; 1 when the path cannot be written safely.
write_desktop() {
  # ponytail: a launcher path with " ` $ or \ would need desktop-entry escaping; skip instead.
  case $1 in *[\"\`\$\\]*) warn "launcher path needs quoting the .desktop format cannot take safely; click handler skipped."; return 1 ;; esac
  mkdir -p "${desktop%/*}"
  atomic_write "$desktop" "[Desktop Entry]
Type=Application
Name=$PLUGIN_NAME click handler
Exec=bash \"$1\" --url %u
NoDisplay=true
Terminal=false
MimeType=x-scheme-handler/$URL_SCHEME;"
}
install_linux() {
  command -v "$xdg_mime" >/dev/null 2>&1 || { printf 'Click handler: xdg-mime not found; skipped. Install xdg-utils and run again to enable status-line clicks.\n'; return 0; }
  write_desktop "$launcher" || return 0
  "$xdg_mime" default "$desktop_name" "x-scheme-handler/$URL_SCHEME" || { warn "xdg-mime failed; status-line clicks stay off."; return 0; }
  registered
}
# Builds and registers the applet that runs launcher $1; non-zero on any failure.
build_app() {
  local src esc ok=0
  # AppleScript string literal: escape \ and "; the URL itself only ever travels as quoted form of u.
  esc=$(printf '%s' "$1" | sed 's/[\\"]/\\&/g')
  src=$(mktemp)
  # do shell script runs with PATH=/usr/bin:/bin:/usr/sbin:/sbin; the launcher and toggle need jq, often Homebrew's.
  printf 'on open location u\n\tdo shell script "PATH=%s:$PATH bash " & quoted form of "%s" & " --url " & quoted form of u\nend open location\n' \
    "$MACOS_URL_HANDLER_APPLET_PATH_PREFIX_HOMEBREW_ARM_THEN_USR_LOCAL_BIN" "$esc" >"$src"
  [[ -n $URL_SCHEME ]] && rm -rf "$app"
  mkdir -p "${app%/*}"
  "$osacompile" -o "$app" "$src" &&
    "$plistbuddy" -c 'Add :CFBundleURLTypes array' -c 'Add :CFBundleURLTypes:0 dict' \
      -c "Add :CFBundleURLTypes:0:CFBundleURLName string $URL_SCHEME" -c 'Add :CFBundleURLTypes:0:CFBundleURLSchemes array' \
      -c "Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $URL_SCHEME" -c 'Add :LSUIElement bool true' "$app/Contents/Info.plist" &&
    mkdir -p "${app_owner%/*}" && printf '%s\n' "$1" >"$app_owner" &&
    "$lsregister" -f "$app" && ok=1
  rm -f "$src"
  ((ok))
}
install_mac() {
  if build_app "$launcher"; then registered; else warn "could not build the click handler app; status-line clicks stay off."; fi
}
install_handler() {
  if [[ -n ${WSL_DISTRO_NAME:-} ]]; then
    printf 'Click handler: skipped under WSL; Windows Terminal hands clicks to Windows, so run install.ps1 there.\n'; return 0
  fi
  case $uname_s in
    Darwin) install_mac ;;
    Linux) install_linux ;;
    *) printf 'Click handler: not supported on %s; skipped.\n' "$uname_s" ;;
  esac
}
# Launcher of the first other profile under HOME (~/.claude, ~/.claude-<name>) whose renderer still draws links
# (marker present). Any profile's launcher serves any profile's click: the URL carries &profile=.
# Same file or directory, however spelled ($dir/., a symlink alias, a trailing slash).
same_path() { [[ $1 == "$2" || ( -e $1 && $1 -ef $2 ) ]]; }
# Whether launcher path $1 is THIS profile's launcher.
is_our_launcher() { same_path "$1" "$launcher"; }
other_launcher() {
  local d
  for d in "$HOME/.claude" "$HOME"/.claude-*; do
    same_path "$d" "${config_dir%/}" && continue
    if [[ -f $d/$LAUNCHER_HOME/url-handler && -f $d/$LAUNCHER_HOME/scripts/statusline-launch.sh ]]; then
      printf '%s' "$d/$LAUNCHER_HOME/scripts/statusline-launch.sh"; return 0
    fi
  done
  return 1
}
# Drops our scheme's default from mimeapps.list (what xdg-mime default wrote); other lines stay.
unset_mime_default() {
  local f=$mimeapps
  [[ -e $f ]] || return 0
  f=$(resolve "$f")
  grep -qxF -e "$mime_default" -e "$mime_default;" "$f" || return 0
  atomic_write "$f" "$(grep -vxF -e "$mime_default" -e "$mime_default;" "$f")"
}
uninstall_handler() {
  local next exec_launcher=
  next=$(other_launcher) || next=
  # Launcher named by the .desktop Exec line written by write_desktop: Exec=bash "<launcher>" --url %u
  [[ -f $desktop ]] && exec_launcher=$(sed -n 's/^Exec=bash "\(.*\)" --url %u$/\1/p' "$desktop" | head -n 1)
  # Only a handler that runs THIS profile's launcher; another profile's stays. If another profile still draws links,
  # the handler moves to that profile's launcher instead of leaving its clicks dangling.
  if [[ -n $exec_launcher ]] && is_our_launcher "$exec_launcher"; then
    if [[ -n $next ]] && write_desktop "$next"; then
      "$xdg_mime" default "$desktop_name" "x-scheme-handler/$URL_SCHEME" >/dev/null 2>&1 || true
      printf 'Moved the %s click handler to %s\n' "$URL_SCHEME" "$next"
    else
      rm -f "$desktop"; unset_mime_default
    fi
  fi
  if [[ -f $app_owner ]] && is_our_launcher "$(cat "$app_owner")"; then
    if [[ -n $next ]] && build_app "$next"; then printf 'Moved the %s click handler to %s\n' "$URL_SCHEME" "$next"
    else "$lsregister" -u "$app" >/dev/null 2>&1 || true; rm -rf "$app"; fi
  fi
}

# ---- uninstall ----
if ((uninstall)); then
  if [[ -r $settings ]]; then
    own=false; [[ -n $current ]] && owned "$current" && own=true
    new=$(jq --arg id "$PLUGIN_ID" --argjson own "$own" '
      (if (.enabledPlugins | type) == "object" and (.enabledPlugins | has($id))
       then del(.enabledPlugins[$id]) | (if .enabledPlugins == {} then del(.enabledPlugins) else . end) else . end)
      | if $own then del(.statusLine) else . end' "$settings")
    [[ $(jq -c . <<<"$new") == "$(jq -c . "$settings")" ]] || atomic_write "$settings" "$new"
  fi
  uninstall_keybinding
  uninstall_handler
  [[ -n $LAUNCHER_HOME ]] && rm -rf "$launcher_home"
  printf 'Uninstalled Claude status line from %s\n' "$config_dir"
  exit 0
fi

# ---- install ----
mkdir -p "$launcher_home/scripts" "$launcher_home/config"
cp "$plugin_root/scripts/statusline-launch.sh" "$plugin_root/scripts/statusline-launch.ps1" "$launcher_home/scripts/"
cp "$plugin_root/config/identity.env" "$plugin_root/config/load-identity.sh" "$launcher_home/config/"
chmod +x "$launcher"

# Keep the portable ~ form for the default profile so a shared settings file stays host-neutral.
if [[ $config_dir == "$HOME/.claude" ]]; then
  command="bash ~/.claude/$LAUNCHER_HOME/scripts/statusline-launch.sh"
else
  command="bash $launcher"
fi
if [[ -r $settings ]]; then
  # Merge, not replace: keep refreshInterval (the countdown sets it) and any user keys such as padding.
  new=$(jq --arg cmd "$command" --arg id "$PLUGIN_ID" '.statusLine=(((.statusLine|objects) // {}) + {type:"command",command:$cmd}) | .enabledPlugins[$id]=true' "$settings")
else
  new=$(jq -n --arg cmd "$command" --arg id "$PLUGIN_ID" '{statusLine:{type:"command",command:$cmd},enabledPlugins:{($id):true}}')
fi
atomic_write "$settings" "$new"

install_keybinding
install_handler
printf 'Installed Claude status line for %s\n' "$config_dir"

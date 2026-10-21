#!/usr/bin/env bash
# drift-menu-open.command — double-clickable / OSC8 shim.
# Opens the drift control menu in the SAME Terminal window the click spawned.
set -uo pipefail
LAUNCH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/drift-menu-launch.sh"

# NOTE: macOS already opens THIS .command in a Terminal window (window #1). The
# osascript below spawned a SECOND Terminal window (window #2) for the menu —
# that was the two-window bug. Disabled, not deleted. Instead we exec the menu
# in the window we were already handed, so a click yields exactly one window.
#
# osascript \
#   -e "tell application \"Terminal\" to do script \"$LAUNCH\"" \
#   -e 'tell application "Terminal" to activate'

exec "$LAUNCH"

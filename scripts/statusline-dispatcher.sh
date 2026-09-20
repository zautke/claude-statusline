#!/usr/bin/env bash
# Statusline dispatcher — detects OS, routes to Bash or PowerShell renderer.
# On Windows-native (no bash), set settings.json command to:
#   pwsh "/path/statusline-command.ps1"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

Usage() {
  printf '%s\n' 'Usage: statusline-dispatcher.sh [-h|--help] [-r|--refresh-fable]'
}

case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
  -r|--refresh-fable) exec bash "$SCRIPT_DIR/statusline-command.sh" "$1" ;;
  '') ;;
  *) Usage >&2; exit 2 ;;
esac

input=$(cat)

case "$OSTYPE" in
  darwin*|linux*|freebsd*)
    printf '%s' "$input" | bash "$SCRIPT_DIR/statusline-command.sh"
    ;;
  msys*|cygwin*|mingw*)
    if command -v pwsh &>/dev/null; then
      printf '%s' "$input" | pwsh -NoProfile -NonInteractive -File "$SCRIPT_DIR/statusline-command.ps1"
    else
      printf '%s' "$input" | bash "$SCRIPT_DIR/statusline-command.sh"
    fi
    ;;
  *)
    printf '%s' "$input" | bash "$SCRIPT_DIR/statusline-command.sh"
    ;;
esac

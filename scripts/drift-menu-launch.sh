#!/usr/bin/env bash
# drift-menu-launch.sh — bootstrap an isolated venv (first run) and launch the
# Textual drift control menu. Shared entry point for the tmux popup and the
# macOS double-click shim.
set -uo pipefail

VENV="$HOME/.claude/.venv-drift"
MENU="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/drift-menu.py"

Usage() {
  cat <<'EOF'
Usage: drift-menu-launch.sh [options]
  -s, --session-id <id>   Session id to control (default: newest).
  -h, --help              Show this help.
EOF
}

ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--session-id) ARGS+=("--session-id" "${2:-}"); shift 2 ;;
    -h|--help) Usage; exit 0 ;;
    *) echo "drift-menu-launch.sh: unknown argument: $1" >&2; Usage >&2; exit 2 ;;
  esac
done

if [[ ! -d "$VENV" ]]; then
  # disk-constrained machine: refuse to bootstrap with <1 GB free.
  avail_gb=$(df -g "$HOME" 2>/dev/null | awk 'NR==2{print $4}')
  if [[ -n "$avail_gb" && "$avail_gb" -lt 1 ]]; then
    echo "drift-menu-launch.sh: <1 GB free in \$HOME (${avail_gb}G); refusing to bootstrap venv." >&2
    exit 1
  fi
  python3 -m venv "$VENV" || { echo "drift-menu-launch.sh: venv create failed" >&2; exit 1; }
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  pip install --quiet --upgrade pip >/dev/null 2>&1 || true
  pip install --quiet textual || { echo "drift-menu-launch.sh: textual install failed" >&2; exit 1; }
else
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
fi

exec python3 "$MENU" ${ARGS[@]+"${ARGS[@]}"}

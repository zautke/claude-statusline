#!/usr/bin/env bash
# drift-control.sh — read/write per-session drift control.json.
# Single decoupling interface between the drift menu (writer) and the
# assessor worker (reader).
#   ~/.claude/state/drift/<session-id>.control.json
# Schema: { paused:bool, force_provider:groq|gemini|openai|ollama|null, updated_at:ISO8601 }
set -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "drift-control.sh: requires 'jq' in PATH" >&2; exit 1; }

STATE_DIR="$HOME/.claude/state/drift"

Usage() {
  cat <<'EOF'
Usage: drift-control.sh [options]

Reads/writes the per-session drift control file:
  ~/.claude/state/drift/<session-id>.control.json

Options:
  -s, --session-id <id>            Target session id. Default: newest *.jsonl by mtime.
  -g, --get                        Print effective control.json (merged with defaults).
  -p, --set-paused <true|false>    Set paused flag.
  -r, --set-provider <name>        Force provider: groq|gemini|openai|ollama|auto (auto=null).
  -R, --resolve-session            Print resolved session id and exit.
  -h, --help                       Show this help.

Defaults when file absent: paused=false, force_provider=null.
All writes are atomic (temp file + mv).
EOF
}

# ---- arg parse (named only, never positional) ----
SESSION_ID=""
DO_GET=0
DO_RESOLVE=0
SET_PAUSED=""
SET_PROVIDER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--session-id)      SESSION_ID="${2:-}"; shift 2 ;;
    -g|--get)             DO_GET=1; shift ;;
    -p|--set-paused)      SET_PAUSED="${2:-}"; shift 2 ;;
    -r|--set-provider)    SET_PROVIDER="${2:-}"; shift 2 ;;
    -R|--resolve-session) DO_RESOLVE=1; shift ;;
    -h|--help)            Usage; exit 0 ;;
    *) echo "drift-control.sh: unknown argument: $1" >&2; Usage >&2; exit 2 ;;
  esac
done

resolve_session() {
  local newest
  newest=$(ls -t "$STATE_DIR"/*.jsonl 2>/dev/null | head -1)
  [[ -z "$newest" ]] && return 1
  basename "$newest" .jsonl
}

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=$(resolve_session) || {
    echo "drift-control.sh: no --session-id given and none resolvable in $STATE_DIR" >&2
    exit 1
  }
fi

# Reject session ids that could escape STATE_DIR (path traversal / separators).
if [[ "$SESSION_ID" == *..* || "$SESSION_ID" == */* || ! "$SESSION_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "drift-control.sh: invalid session id: $SESSION_ID" >&2
  exit 2
fi

CONTROL_FILE="$STATE_DIR/$SESSION_ID.control.json"

if [[ "$DO_RESOLVE" == "1" ]]; then
  printf '%s\n' "$SESSION_ID"
  exit 0
fi

read_control() {
  # Print control.json merged with defaults. Robust against missing/partial/corrupt file.
  local raw='{}'
  [[ -r "$CONTROL_FILE" ]] && raw=$(cat "$CONTROL_FILE" 2>/dev/null)
  [[ -z "$raw" ]] && raw='{}'
  printf '%s' "$raw" | jq '
      . as $c
      | { paused:         ($c.paused // false),
          force_provider: ($c.force_provider // null),
          updated_at:     ($c.updated_at // null) }' 2>/dev/null \
    || jq -nc '{paused:false, force_provider:null, updated_at:null}'
}

write_control() {
  # arg: full JSON object string. Atomic temp+mv.
  mkdir -p "$STATE_DIR"
  local tmp
  tmp=$(mktemp "$STATE_DIR/.control.XXXXXX") || { echo "drift-control.sh: mktemp failed" >&2; exit 1; }
  printf '%s\n' "$1" > "$tmp" && mv -f "$tmp" "$CONTROL_FILE"
}

mutate() {
  local cur paused provider
  cur=$(read_control)
  paused=$(printf '%s' "$cur" | jq -r '.paused')
  provider=$(printf '%s' "$cur" | jq -r 'if .force_provider == null then "null" else .force_provider end')

  if [[ -n "$SET_PAUSED" ]]; then
    case "$SET_PAUSED" in
      true|false) paused="$SET_PAUSED" ;;
      *) echo "drift-control.sh: --set-paused must be true|false" >&2; exit 2 ;;
    esac
  fi

  if [[ -n "$SET_PROVIDER" ]]; then
    case "$SET_PROVIDER" in
      groq|gemini|openai|ollama) provider="$SET_PROVIDER" ;;
      auto) provider="null" ;;
      *) echo "drift-control.sh: --set-provider must be groq|gemini|openai|ollama|auto" >&2; exit 2 ;;
    esac
  fi

  local pjson
  if [[ "$provider" == "null" ]]; then pjson=null; else pjson="\"$provider\""; fi

  write_control "$(jq -nc \
    --argjson paused "$paused" \
    --argjson fp "$pjson" \
    --arg ts "$(date -u +%FT%TZ)" \
    '{paused:$paused, force_provider:$fp, updated_at:$ts}')"
}

if [[ -n "$SET_PAUSED" || -n "$SET_PROVIDER" ]]; then
  mutate
fi

if [[ "$DO_GET" == "1" ]]; then
  read_control
fi

# Nothing actionable requested → help.
if [[ "$DO_GET" == "0" && -z "$SET_PAUSED" && -z "$SET_PROVIDER" ]]; then
  Usage
fi

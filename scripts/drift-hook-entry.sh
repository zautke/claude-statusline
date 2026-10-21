#!/usr/bin/env bash
# drift-hook-entry.sh — Claude Code hook entry for drift quotient.
#
# UserPromptSubmit (SYNCHRONOUS, no async:true):
#   1. Read recent drift assessments from state file.
#   2. Print formatted report to stdout. Claude Code wraps it in a
#      <system-reminder> block injected BEFORE Claude sees the user's
#      next prompt — making the main agent aware of how the independent
#      assessor scored each prior turn.
#   3. Append a new baseline line for the user's incoming prompt.
#
# Stop (async:true):
#   exec the assessor worker. Worker is detached by Claude Code's harness.

set -uo pipefail

input=$(cat)
SESSION_ID=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
CWD=$(       printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
EVENT=$(     printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)

[[ -z "$SESSION_ID" || -z "$TRANSCRIPT" ]] && exit 0

STATE_DIR="$HOME/.claude/state/drift"
mkdir -p "$STATE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID.jsonl"

format_drift_report() {
  # Read last 200 lines of state, render the most recent 5 score lines
  # plus the most recent error (if any) into a human-readable block.
  [[ -r "$STATE_FILE" ]] || return 0

  local body
  body=$(tail -n 200 "$STATE_FILE" 2>/dev/null \
    | jq -rs '
      def short_ts(s): s | sub("T"; " ") | sub("Z$"; "");
      def fmt_score:
        "  - " + short_ts(.ts) + "  score " + (.score|tostring) + "/100  (" + .tag + ")"
        + "   [" + .provider
        + (if .model and .model != .provider then ", " + .model else "" end) + "]"
        + (if .reason and (.reason | length > 0) then "\n      ↳ " + .reason else "" end);
      def fmt_err:
        "  ! " + short_ts(.ts) + "  error: " + .why
        + (if .fallback and (.fallback|length>0) then "  (fallback: " + .fallback + ")" else "" end);
      ([.[] | select(.kind=="score")] | sort_by(.ts) | .[-5:] | map(fmt_score)) as $scores
      | ([.[] | select(.kind=="error")] | sort_by(.ts) | .[-1:] | map(fmt_err)) as $errs
      | ([.[] | select(.kind=="baseline")] | sort_by(.ordinal) | .[-3:]
            | map("  goal #\(.ordinal): " + (.goal // "(empty)"))) as $goals
      | (if ($scores | length) > 0 or ($errs | length) > 0 then
          (if ($goals | length) > 0 then "Recent user goals:\n" + ($goals | join("\n")) + "\n\n" else "" end) +
          (if ($scores | length) > 0 then "Recent drift assessments (oldest → newest):\n" + ($scores | join("\n")) else "" end) +
          (if ($errs | length) > 0 then "\n\nLast assessor error:\n" + ($errs | join("\n")) else "" end)
        else empty end)
    ' 2>/dev/null)

  if [[ -n "$body" ]]; then
    cat <<EOF
=== drift-quotient report (independent co-agent assessment) ===

An out-of-band assessor (Anthropic Haiku 4.5 primary, cloud Ollama fallback)
has been scoring each turn of this session for alignment with your stated
task. Score bands: 90-100 aligned · 70-89 solid · 50-69 mild-drift ·
30-49 significant drift · 1-29 lost. Treat low scores or negative tags
(context-rot, redundant-loop, scope-creep, hallucination, debug-spiral)
as feedback to refocus.

$body

(Full history: $STATE_FILE)
=== end drift-quotient report ===
EOF
  fi
}

if [[ "$EVENT" == "UserPromptSubmit" ]]; then
  # 1. emit drift report on stdout — Claude wraps as <system-reminder>
  format_drift_report

  # 2. append the new baseline for this prompt
  GOAL=$(printf '%s' "$input" \
    | jq -r '.user_message // .prompt // .message // .user_prompt // empty' 2>/dev/null \
    | head -c 240)
  ORDINAL=$(tail -n 200 "$STATE_FILE" 2>/dev/null \
    | jq -rs '[.[] | select(.kind=="baseline")] | length + 1' 2>/dev/null)
  [[ -z "$ORDINAL" || ! "$ORDINAL" =~ ^[0-9]+$ ]] && ORDINAL=1
  jq -nc --arg ts "$(date -u +%FT%TZ)" --arg sid "$SESSION_ID" \
    --arg goal "$GOAL" --argjson ord "$ORDINAL" \
    '{ts:$ts,session_id:$sid,kind:"baseline",goal:$goal,ordinal:$ord}' \
    >> "$STATE_FILE"

  exit 0
fi

# Stop (or anything else) → assessor worker. async:true means harness has detached us.
exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/drift-assess-worker.sh" \
  --session-id "$SESSION_ID" --transcript "$TRANSCRIPT" --cwd "$CWD"

#!/usr/bin/env bash
# drift-assess-worker.sh — async drift quotient assessor for Claude Code statusline.
# Spawned by drift-hook-entry.sh from the Stop hook (async:true in settings.json).
# Reads new transcript activity, asks Anthropic Haiku 4.5 (with Ollama fallback)
# to score alignment with task goals, appends a score line to per-session state file.

set -uo pipefail   # no -e: we want to keep going on per-step errors

Usage() {
  cat <<EOF
Usage: $(basename "$0") -s|--session-id <id> -t|--transcript <path> [-c|--cwd <dir>]

  -s, --session-id   Claude Code session UUID
  -t, --transcript   path to session transcript JSONL
  -c, --cwd          working directory at hook fire time (optional)
  -h, --help         print this help

Reads ~/.bash/.env for GROQ_API_KEY (primary), GEMINI_API_KEY, OPENAI_API_KEY,
optional OLLAMA_BEARER, plus DRIFT_GROQ_MODEL / DRIFT_GEMINI_MODEL /
DRIFT_OPENAI_MODEL / DRIFT_OLLAMA_MODEL / DRIFT_DRY_RUN overrides.
Try chain: groq → gemini → openai → ollama.
Appends to ~/.claude/state/drift/<session-id>.jsonl
EOF
}

# ---- parse args (named, never positional, per CLAUDE.md) ----
SESSION_ID=""; TRANSCRIPT=""; CWD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--session-id) SESSION_ID="${2:-}"; shift 2 ;;
    -t|--transcript) TRANSCRIPT="${2:-}"; shift 2 ;;
    -c|--cwd)        CWD="${2:-}"; shift 2 ;;
    -h|--help)       Usage; exit 0 ;;
    *)               Usage >&2; exit 2 ;;
  esac
done
[[ -z "$SESSION_ID" || -z "$TRANSCRIPT" ]] && { Usage >&2; exit 2; }

# ---- paths ----
STATE_DIR="$HOME/.claude/state/drift"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Rubric is editable plain text; .md preferred for readability.
# .txt fallback kept for users still on the older layout.
# A user-edited copy in the state dir survives plugin updates and wins over the shipped one.
if   [[ -r "$STATE_DIR/rubric.md"         ]]; then RUBRIC_FILE="$STATE_DIR/rubric.md"
elif [[ -r "$SCRIPTS_DIR/drift-rubric.md"  ]]; then RUBRIC_FILE="$SCRIPTS_DIR/drift-rubric.md"
elif [[ -r "$SCRIPTS_DIR/drift-rubric.txt" ]]; then RUBRIC_FILE="$SCRIPTS_DIR/drift-rubric.txt"
else RUBRIC_FILE="$SCRIPTS_DIR/drift-rubric.md"   # path even if absent — emit_error will catch
fi
TRACE_DIR="$STATE_DIR/traces"
mkdir -p "$STATE_DIR" "$TRACE_DIR"
STATE_FILE="$STATE_DIR/$SESSION_ID.jsonl"
TRACE_FILE="$TRACE_DIR/$SESSION_ID.jsonl"
LOCK="$STATE_DIR/.lock-$SESSION_ID"

# ---- helpers ----
now_iso()  { date -u +%FT%TZ; }
now_unix() { date +%s; }
now_ms() {
  # macOS BSD date lacks %N; fall back to python3.
  date +%s%3N 2>/dev/null | grep -Eq '^[0-9]+$' && date +%s%3N \
    || python3 -c 'import time; print(int(time.time()*1000))' 2>/dev/null \
    || echo $(( $(now_unix) * 1000 ))
}
log_line() {  # append a state line; arg is JSON string
  printf '%s\n' "$1" >> "$STATE_FILE"
}
emit_skip() {
  log_line "$(jq -nc --arg ts "$(now_iso)" --arg sid "$SESSION_ID" \
    --argjson cursor "${1:-0}" --arg why "$2" \
    '{ts:$ts,session_id:$sid,kind:"skip",cursor:$cursor,why:$why}')"
}
emit_error() {
  log_line "$(jq -nc --arg ts "$(now_iso)" --arg sid "$SESSION_ID" \
    --argjson cursor "${1:-0}" --arg why "$2" --arg fb "${3:-}" \
    '{ts:$ts,session_id:$sid,kind:"error",cursor:$cursor,why:$why,fallback:$fb}')"
}

# ---- VERBATIM TRACE (critical protocol — every assessor call, success or fail) ----
# Appends one JSONL line per call to ~/.claude/state/drift/traces/<sid>.jsonl
# containing: full request payload, raw response, parsed thinking + content.
# Audit trail + dataset for refinement. See protocols/drift-quotient.md (KB).
write_trace() {
  # args: provider endpoint model status latency_ms request_json response_raw
  local provider="$1" endpoint="$2" model="$3" status="$4" latency="$5"
  local req_json="$6" resp_raw="$7"

  # Try to interpret response as JSON; if it's not parseable, store as string.
  local resp_field
  if [[ -n "$resp_raw" ]] && printf '%s' "$resp_raw" | jq -e . >/dev/null 2>&1; then
    resp_field=$(printf '%s' "$resp_raw" | jq -c '.')
  else
    resp_field=$(jq -nc --arg s "${resp_raw:-}" '$s')
  fi

  # Pull thinking + content out for the `parsed` summary, if present.
  # NOTE: jq `//` alternative operator changes the pipeline input — using
  # explicit if/elif on shape is more reliable across Anthropic and Ollama.
  local thinking content
  thinking=$(printf '%s' "$resp_raw" | jq -r '
    if (.content // null) | type == "array" then
      [.content[] | select(.type=="thinking") | .thinking] | first // ""
    elif (.message.thinking // null) | type == "string" then
      .message.thinking
    else
      ""
    end' 2>/dev/null)
  content=$(printf '%s' "$resp_raw" | jq -r '
    if (.content // null) | type == "array" then
      [.content[] | select(.type=="text") | .text] | first // ""
    elif (.message.content // null) | type == "string" then
      .message.content
    elif (.choices // null) | type == "array" then
      .choices[0].message.content // ""
    else
      ""
    end' 2>/dev/null)

  jq -nc \
    --arg ts        "$(now_iso)" \
    --arg sid       "$SESSION_ID" \
    --arg provider  "$provider" \
    --arg endpoint  "$endpoint" \
    --arg model     "$model" \
    --arg status    "$status" \
    --argjson lat   "${latency:-0}" \
    --argjson req   "${req_json:-null}" \
    --argjson resp  "$resp_field" \
    --arg thinking  "${thinking:-}" \
    --arg content   "${content:-}" \
    '{ts:$ts,session_id:$sid,provider:$provider,endpoint:$endpoint,model:$model,
      status:$status,latency_ms:$lat,request:$req,response:$resp,
      parsed:{thinking:$thinking,content:$content}}' \
    >> "$TRACE_FILE"
}

# ---- mkdir-lock with 30s stale guard ----
acquire_lock() {
  if mkdir "$LOCK" 2>/dev/null; then return 0; fi
  local age
  age=$(( $(now_unix) - $(stat -f %m "$LOCK" 2>/dev/null || echo 0) ))
  if (( age > 30 )); then
    rmdir "$LOCK" 2>/dev/null || true
    mkdir "$LOCK" 2>/dev/null && return 0
  fi
  return 1
}
acquire_lock || exit 0
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# ---- load ~/.bash/.env ----
if [[ -r "$HOME/.bash/.env" ]]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  if ! source "$HOME/.bash/.env" 2>/dev/null; then
    emit_error 0 "env-source" ""
  fi
  set +a
fi
GROQ_API_KEY="${GROQ_API_KEY:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
OLLAMA_BEARER="${OLLAMA_BEARER:-}"
GROQ_MODEL="${DRIFT_GROQ_MODEL:-llama-3.3-70b-versatile}"
GROQ_URL="${DRIFT_GROQ_URL:-https://api.groq.com}"
OLLAMA_MODEL="${DRIFT_OLLAMA_MODEL:-deepseek-v4-flash:cloud}"
OLLAMA_URL="${DRIFT_OLLAMA_URL:-https://ollama2.braisenly.com}"
OPENAI_MODEL="${DRIFT_OPENAI_MODEL:-gpt-4o-mini}"
OPENAI_URL="${DRIFT_OPENAI_URL:-https://api.openai.com}"
GEMINI_MODEL="${DRIFT_GEMINI_MODEL:-gemini-2.5-flash}"
GEMINI_URL="${DRIFT_GEMINI_URL:-https://generativelanguage.googleapis.com}"
DRIFT_DRY_RUN="${DRIFT_DRY_RUN:-0}"

# ---- read prior state ----
PRIOR_CURSOR=0
PRIOR_CHECKPOINTS=""
GOALS_JSON='[]'
ORIGINAL_TASK=""
ASSESS_COUNT=0
LAST_SCORE_ISO=""

if [[ -f "$STATE_FILE" ]]; then
  TAIL_DATA=$(tail -n 400 "$STATE_FILE" 2>/dev/null || true)
  if [[ -n "$TAIL_DATA" ]]; then
    PRIOR_CURSOR=$(printf '%s' "$TAIL_DATA" | jq -rs \
      '[.[] | select(.kind=="score" and (.cursor != null))] | last.cursor // 0' 2>/dev/null \
      || echo 0)
    PRIOR_CHECKPOINTS=$(printf '%s' "$TAIL_DATA" | jq -rs \
      '[.[] | select(.kind=="score")] | sort_by(.ts) | .[-5:] | map("\(.score)|\(.tag)") | join(", ")' 2>/dev/null)
    GOALS_JSON=$(printf '%s' "$TAIL_DATA" | jq -cs \
      '[.[] | select(.kind=="baseline")] | sort_by(.ordinal) | .[-5:]' 2>/dev/null \
      || echo '[]')
    ORIGINAL_TASK=$(printf '%s' "$TAIL_DATA" | jq -rs \
      '[.[] | select(.kind=="baseline")] | sort_by(.ordinal) | .[0].goal // ""' 2>/dev/null)
    ASSESS_COUNT=$(printf '%s' "$TAIL_DATA" | jq -rs \
      '[.[] | select(.kind=="score")] | length' 2>/dev/null \
      || echo 0)
    LAST_SCORE_ISO=$(printf '%s' "$TAIL_DATA" | jq -rs \
      '[.[] | select(.kind=="score") | .ts] | last // ""' 2>/dev/null)
  fi
fi

LAST_SCORE_TS=0
if [[ -n "$LAST_SCORE_ISO" ]]; then
  # -u: parse the literal hour/min/sec as UTC (not local TZ); without it the value
  # ends up TZ-offset shifted, which can make SECS_SINCE negative and falsely trigger
  # the "too-soon" gate.
  LAST_SCORE_TS=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_SCORE_ISO" +%s 2>/dev/null || echo 0)
fi

# ---- gate: assess count cap ----
if (( ASSESS_COUNT >= 30 )); then
  emit_skip "$PRIOR_CURSOR" "count-cap"
  exit 0
fi

# ---- gate: min new content ----
TSIZE=0
if [[ -r "$TRANSCRIPT" ]]; then
  TSIZE=$(stat -f %z "$TRANSCRIPT" 2>/dev/null || echo 0)
fi
NEW_BYTES=$(( TSIZE - PRIOR_CURSOR ))
if (( NEW_BYTES < 800 )); then
  emit_skip "$TSIZE" "too-small"
  exit 0
fi

# ---- gate: min interval ----
if (( LAST_SCORE_TS > 0 )); then
  SECS_SINCE=$(( $(now_unix) - LAST_SCORE_TS ))
  if (( SECS_SINCE < 8 )); then
    emit_skip "$TSIZE" "too-soon"
    exit 0
  fi
fi

# ---- extract new activity from transcript (bounded; last 200KB of new content) ----
NEW_CONTENT=$(tail -c +$((PRIOR_CURSOR + 1)) "$TRANSCRIPT" 2>/dev/null \
  | tail -c 200000 \
  | jq -Rrs 'split("\n") | map(select(length>0)
              | (fromjson? // null) | select(. != null)
              | tojson | .[0:600])
              | .[-40:] | join("\n")' 2>/dev/null \
  | head -c 6000)

if [[ -z "$NEW_CONTENT" ]]; then
  emit_skip "$TSIZE" "no-events"
  exit 0
fi

# ---- build prompt ----
RECENT_PROMPTS_TXT=$(printf '%s' "$GOALS_JSON" \
  | jq -r 'map("  \(.ordinal). \(.goal)") | join("\n")' 2>/dev/null)
[[ -z "$RECENT_PROMPTS_TXT" ]] && RECENT_PROMPTS_TXT="  (none recorded)"
[[ -z "$ORIGINAL_TASK" ]] && ORIGINAL_TASK="(no baseline recorded)"

USER_MSG=$(printf 'ORIGINAL_TASK: %s\nRECENT_USER_PROMPTS:\n%s\nPRIOR_CHECKPOINTS: %s\nNEW_ACTIVITY (last 40 events, <=600 chars each, total <=6000):\n%s\n\nReturn the JSON object only.' \
  "$ORIGINAL_TASK" "$RECENT_PROMPTS_TXT" "${PRIOR_CHECKPOINTS:-(none)}" "$NEW_CONTENT")

if [[ ! -r "$RUBRIC_FILE" ]]; then
  emit_error "$TSIZE" "no-rubric" ""
  exit 0
fi
RUBRIC=$(cat "$RUBRIC_FILE")

# ---- dry run support ----
if [[ "$DRIFT_DRY_RUN" == "1" ]]; then
  LINE=$(jq -nc --arg ts "$(now_iso)" --arg sid "$SESSION_ID" \
    --argjson score 85 --arg tag "focused-implementation" --argjson cursor "$TSIZE" \
    --arg provider "dry-run" --arg model "dry-run" \
    --argjson tin 0 --argjson tout 0 --argjson cost 0 --argjson lat 0 \
    '{ts:$ts,session_id:$sid,kind:"score",score:$score,tag:$tag,cursor:$cursor,provider:$provider,model:$model,tokens_in:$tin,tokens_out:$tout,cost_usd:$cost,latency_ms:$lat}')
  log_line "$LINE"
  exit 0
fi

# ---- control gate (menu-driven pause / forced provider) ----
CONTROL_FILE="$HOME/.claude/state/drift/$SESSION_ID.control.json"
CTRL_PAUSED="false"; CTRL_FORCE="null"
if [[ -r "$CONTROL_FILE" ]]; then
  CTRL_PAUSED=$(jq -r '.paused // false'         "$CONTROL_FILE" 2>/dev/null || echo false)
  CTRL_FORCE=$( jq -r '.force_provider // "null"' "$CONTROL_FILE" 2>/dev/null || echo null)
fi
if [[ "$CTRL_PAUSED" == "true" ]]; then
  emit_skip "$TSIZE" "paused-by-user"
  exit 0
fi

# ---- decide tiers ----
USE_GROQ=1
USE_GEMINI=1
USE_OPENAI=1
USE_OLLAMA=1
[[ -z "$GROQ_API_KEY"   ]] && USE_GROQ=0
[[ -z "$GEMINI_API_KEY" ]] && USE_GEMINI=0
[[ -z "$OPENAI_API_KEY" ]] && USE_OPENAI=0

# forced provider (from control.json) overrides the fallback chain
if [[ "$CTRL_FORCE" != "null" && -n "$CTRL_FORCE" ]]; then
  USE_GROQ=0; USE_GEMINI=0; USE_OPENAI=0; USE_OLLAMA=0
  case "$CTRL_FORCE" in
    groq)   [[ -z "$GROQ_API_KEY"   ]] && { emit_error "$TSIZE" "forced-provider-no-key" ""; exit 0; }; USE_GROQ=1 ;;
    gemini) [[ -z "$GEMINI_API_KEY" ]] && { emit_error "$TSIZE" "forced-provider-no-key" ""; exit 0; }; USE_GEMINI=1 ;;
    openai) [[ -z "$OPENAI_API_KEY" ]] && { emit_error "$TSIZE" "forced-provider-no-key" ""; exit 0; }; USE_OPENAI=1 ;;
    ollama) USE_OLLAMA=1 ;;
  esac
fi

PROVIDER=""; MODEL=""; TEXT=""
TOK_IN=0; TOK_OUT=0; COST="0"; LATENCY=0

call_groq() {
  local t0 t1 resp req endpoint status curl_rc model
  model="$GROQ_MODEL"
  endpoint="$GROQ_URL/openai/v1/chat/completions"
  req=$(jq -n --arg rubric "$RUBRIC" --arg user "$USER_MSG" --arg model "$model" \
    '{
       model: $model,
       messages: [
         {role:"system", content:$rubric},
         {role:"user",   content:$user}
       ],
       response_format: {type:"json_object"},
       temperature: 0.1,
       max_tokens: 256
     }')
  t0=$(now_ms)
  resp=$(curl -sS --max-time 10 "$endpoint" \
    -H "Authorization: Bearer $GROQ_API_KEY" \
    -H "content-type: application/json" \
    --data "$req" 2>/dev/null)
  curl_rc=$?
  t1=$(now_ms)
  LATENCY=$(( t1 - t0 ))

  status="ok"
  if (( curl_rc != 0 )); then
    status="curl-fail-$curl_rc"
    write_trace groq "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TEXT=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  if [[ -z "$TEXT" ]]; then
    status="empty-content"
    write_trace groq "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TOK_IN=$( printf '%s' "$resp" | jq -r '.usage.prompt_tokens     // 0' 2>/dev/null)
  TOK_OUT=$(printf '%s' "$resp" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
  # Groq Llama 3.3 70B free tier: 30 RPM / 14400 req/day. $0 within quota.
  COST="0"
  PROVIDER="groq"; MODEL="$model"
  write_trace groq "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
  return 0
}

call_gemini() {
  local t0 t1 resp req endpoint status curl_rc model
  model="$GEMINI_MODEL"
  endpoint="$GEMINI_URL/v1beta/openai/chat/completions"
  # NOTE: gemini-2.5-flash is a reasoning variant — hidden CoT goes into
  # thinking budget. Needs max_tokens=2048 to consistently emit JSON content
  # (256 starves it, 1024 truncates). gemini-2.5-flash-lite is non-reasoning
  # and works with max_tokens=256 — set DRIFT_GEMINI_MODEL=gemini-2.5-flash-lite
  # to switch.
  req=$(jq -n --arg rubric "$RUBRIC" --arg user "$USER_MSG" --arg model "$model" \
    '{
       model: $model,
       messages: [
         {role:"system", content:$rubric},
         {role:"user",   content:$user}
       ],
       response_format: {type:"json_object"},
       temperature: 0.1,
       max_tokens: 2048
     }')
  t0=$(now_ms)
  resp=$(curl -sS --max-time 15 "$endpoint" \
    -H "Authorization: Bearer $GEMINI_API_KEY" \
    -H "content-type: application/json" \
    --data "$req" 2>/dev/null)
  curl_rc=$?
  t1=$(now_ms)
  LATENCY=$(( t1 - t0 ))

  status="ok"
  if (( curl_rc != 0 )); then
    status="curl-fail-$curl_rc"
    write_trace gemini "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TEXT=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  if [[ -z "$TEXT" ]]; then
    status="empty-content"
    write_trace gemini "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TOK_IN=$( printf '%s' "$resp" | jq -r '.usage.prompt_tokens     // 0' 2>/dev/null)
  TOK_OUT=$(printf '%s' "$resp" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
  # Google AI Studio free tier: 1500 req/day on Flash family. Beyond that bills at standard rate.
  COST="0"
  PROVIDER="gemini"; MODEL="$model"
  write_trace gemini "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
  return 0
}

call_openai() {
  local t0 t1 resp req endpoint status curl_rc model
  model="$OPENAI_MODEL"
  endpoint="$OPENAI_URL/v1/chat/completions"
  req=$(jq -n --arg rubric "$RUBRIC" --arg user "$USER_MSG" --arg model "$model" \
    '{
       model: $model,
       messages: [
         {role:"system", content:$rubric},
         {role:"user",   content:$user}
       ],
       response_format: {type:"json_object"},
       temperature: 0.1,
       max_tokens: 256
     }')
  t0=$(now_ms)
  resp=$(curl -sS --max-time 12 "$endpoint" \
    -H "Authorization: Bearer $OPENAI_API_KEY" \
    -H "content-type: application/json" \
    --data "$req" 2>/dev/null)
  curl_rc=$?
  t1=$(now_ms)
  LATENCY=$(( t1 - t0 ))

  status="ok"
  if (( curl_rc != 0 )); then
    status="curl-fail-$curl_rc"
    write_trace openai "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TEXT=$(printf '%s' "$resp" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
  if [[ -z "$TEXT" ]]; then
    status="empty-content"
    write_trace openai "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TOK_IN=$( printf '%s' "$resp" | jq -r '.usage.prompt_tokens     // 0' 2>/dev/null)
  TOK_OUT=$(printf '%s' "$resp" | jq -r '.usage.completion_tokens // 0' 2>/dev/null)
  # gpt-4o-mini pricing: $0.15/M input + $0.60/M output (verify in OpenAI docs if changed).
  COST=$(awk "BEGIN{printf \"%.6f\", ($TOK_IN/1000000.0)*0.15 + ($TOK_OUT/1000000.0)*0.60}")
  PROVIDER="openai"; MODEL="$model"
  write_trace openai "$endpoint" "$model" "$status" "$LATENCY" "$req" "$resp"
  return 0
}

call_ollama() {
  local t0 t1 resp req endpoint status curl_rc
  endpoint="$OLLAMA_URL/api/chat"

  # Preflight 8s (cold Cloudflare tunnel can take 4-5s on first hit).
  if ! curl -sS --max-time 8 "$OLLAMA_URL/api/tags" >/dev/null 2>&1; then
    write_trace ollama "$OLLAMA_URL/api/tags" "$OLLAMA_MODEL" "preflight-fail" 0 "null" ""
    return 1
  fi
  # NOTE: reasoning models (gpt-oss, deepseek, glm, etc.) emit hidden CoT into the
  # `thinking` field. If num_predict is too low the budget is fully consumed by
  # thinking and `.message.content` comes back empty (done_reason: "length").
  # gpt-oss:20b-cloud measured ~268 tokens for thinking + JSON with reason field;
  # 512 is comfortable headroom. Non-reasoning models (glm, deepseek-flash) use
  # 25-30 tokens, so the higher cap doesn't cost them anything.
  req=$(jq -n --arg rubric "$RUBRIC" --arg user "$USER_MSG" --arg model "$OLLAMA_MODEL" \
    '{
       model: $model,
       stream: false,
       format: "json",
       think: false,
       messages: [
         {role:"system", content:$rubric},
         {role:"user",   content:$user}
       ],
       options: {temperature: 0.1, num_predict: 512}
     }')
  t0=$(now_ms)
  local -a hdrs=( -H "content-type: application/json" )
  [[ -n "$OLLAMA_BEARER" ]] && hdrs+=( -H "Authorization: Bearer $OLLAMA_BEARER" )
  resp=$(curl -sS --max-time 15 "$endpoint" \
    "${hdrs[@]}" --data "$req" 2>/dev/null)
  curl_rc=$?
  t1=$(now_ms)
  LATENCY=$(( t1 - t0 ))

  status="ok"
  if (( curl_rc != 0 )); then
    status="curl-fail-$curl_rc"
    write_trace ollama "$endpoint" "$OLLAMA_MODEL" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  TEXT=$(printf '%s' "$resp" | jq -r '.message.content // empty' 2>/dev/null)
  if [[ -z "$TEXT" ]]; then
    status="empty-content"
    write_trace ollama "$endpoint" "$OLLAMA_MODEL" "$status" "$LATENCY" "$req" "$resp"
    return 1
  fi
  COST="0"
  TOK_IN=$( printf '%s' "$resp" | jq -r '.prompt_eval_count // 0' 2>/dev/null)
  TOK_OUT=$(printf '%s' "$resp" | jq -r '.eval_count // 0' 2>/dev/null)
  PROVIDER="ollama"; MODEL="$OLLAMA_MODEL"
  write_trace ollama "$endpoint" "$OLLAMA_MODEL" "$status" "$LATENCY" "$req" "$resp"
  return 0
}

# ---- try chain (per user 2026-05-25; Haiku removed) ----
#   1) groq llama-3.3-70b-versatile  (~0.9s wall incl. NYC double-VPN, $0 within free tier)
#   2) gemini-2.5-flash               (~7s, $0 within Google AI Studio 1500 req/day)
#   3) gpt-4o-mini                    (~1.5s, ~$0.0002/call)
#   4) deepseek-v4-flash:cloud        (~2.2s warm / 10s cold, $0)
# Each call writes a verbatim trace regardless of outcome; chain stops on first success.
declare -a ATTEMPT_ERRORS=()

if (( USE_GROQ == 1 )); then
  call_groq || ATTEMPT_ERRORS+=("groq-fail")
fi
if [[ -z "$PROVIDER" ]] && (( USE_GEMINI == 1 )); then
  call_gemini || ATTEMPT_ERRORS+=("gemini-fail")
fi
if [[ -z "$PROVIDER" ]] && (( USE_OPENAI == 1 )); then
  call_openai || ATTEMPT_ERRORS+=("openai-fail")
fi
if [[ -z "$PROVIDER" ]] && (( USE_OLLAMA == 1 )); then
  call_ollama || ATTEMPT_ERRORS+=("ollama-fail")
fi

if [[ -z "$PROVIDER" ]]; then
  if (( ${#ATTEMPT_ERRORS[@]} > 0 )); then
    emit_error "$TSIZE" "all-providers-down" "$(IFS=,; echo "${ATTEMPT_ERRORS[*]}")"
  else
    emit_error "$TSIZE" "no-providers-configured" ""
  fi
  exit 0
fi
# Log the failed-but-recovered chain so the user can see what fell through.
if (( ${#ATTEMPT_ERRORS[@]} > 0 )); then
  emit_error "$TSIZE" "$(IFS=,; echo "${ATTEMPT_ERRORS[*]}")" "$PROVIDER-used"
fi

# ---- validate output ----
# Strip markdown code fences (```json ... ```) some models wrap JSON in (glm-5.1, etc.)
TEXT_CLEAN=$(printf '%s' "$TEXT" | sed -E '/^[[:space:]]*```[a-zA-Z]*[[:space:]]*$/d')
SCORE_RAW=$(printf '%s' "$TEXT_CLEAN" | jq -r '.score // empty' 2>/dev/null)
TAG_RAW=$(  printf '%s' "$TEXT_CLEAN" | jq -r '.tag // empty' 2>/dev/null)
REASON_RAW=$(printf '%s' "$TEXT_CLEAN" | jq -r '.reason // empty' 2>/dev/null | head -c 200)

# salvage: bare SCORE|TAG text
if [[ -z "$SCORE_RAW" || -z "$TAG_RAW" ]]; then
  if [[ "$TEXT" =~ ([0-9]{1,3})\|([a-z][a-z0-9-]{1,30}) ]]; then
    SCORE_RAW="${BASH_REMATCH[1]}"; TAG_RAW="${BASH_REMATCH[2]}"
  fi
fi

if [[ ! "$SCORE_RAW" =~ ^[0-9]+$ ]] || (( SCORE_RAW < 1 || SCORE_RAW > 100 )); then
  emit_error "$TSIZE" "parse-score" "$PROVIDER"
  exit 0
fi
if [[ ! "$TAG_RAW" =~ ^[a-z][a-z0-9-]{1,30}$ ]]; then
  TAG_RAW="unclear"
fi
# reason is optional; empty string OK
[[ -z "$REASON_RAW" ]] && REASON_RAW=""

# ---- atomic append ----
LINE=$(jq -nc --arg ts "$(now_iso)" --arg sid "$SESSION_ID" \
  --argjson score "$SCORE_RAW" --arg tag "$TAG_RAW" --arg reason "$REASON_RAW" --argjson cursor "$TSIZE" \
  --arg provider "$PROVIDER" --arg model "$MODEL" \
  --argjson tin "$TOK_IN" --argjson tout "$TOK_OUT" --argjson cost "$COST" --argjson lat "$LATENCY" \
  '{ts:$ts,session_id:$sid,kind:"score",score:$score,tag:$tag,reason:$reason,cursor:$cursor,provider:$provider,model:$model,tokens_in:$tin,tokens_out:$tout,cost_usd:$cost,latency_ms:$lat}')
log_line "$LINE"
exit 0

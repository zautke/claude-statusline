#!/usr/bin/env bash
set -u

Usage() {
  printf '%s\n' 'Usage: statusline-command.sh [-h|--help] [-r|--refresh-fable]'
}

mode=render
while (($#)); do
  case "$1" in
    -h|--help) Usage; exit 0 ;;
    -r|--refresh-fable) mode=refresh ;;
    *) Usage >&2; exit 2 ;;
  esac
  shift
done

config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
config_file=$config_dir/statusline.json
cache_dir=${XDG_CACHE_HOME:-$HOME/.cache}/braisenly-statusline
cache_file=$cache_dir/fable.json
default_segments='["model","profile","cwd","context","disk","tmp","five_hour","seven_day","fable","drift"]'

valid_config() {
  [[ -r "$config_file" ]] || return 1
  jq -e '
    def known: ["model","profile","cwd","context","disk","tmp","five_hour","seven_day","fable","drift"];
    (.segments // known) as $s |
    ($s|type)=="array" and ($s|all(type=="string" and IN(known[]))) and (($s|unique|length)==($s|length)) and
    ((.labels//{})|to_entries|all(.value|type=="string")) and
    ((.widths//{})|to_entries|all(.value|type=="number" and floor==. and .>=1 and .<=128)) and
    ((.thresholds.usage.warn//60)>=0) and ((.thresholds.usage.warn//60)<=(.thresholds.usage.critical//80)) and ((.thresholds.usage.critical//80)<=100) and
    ((.thresholds.drift.warn//70)>=0) and ((.thresholds.drift.warn//70)<=(.thresholds.drift.good//90)) and ((.thresholds.drift.good//90)<=100) and
    ((.colors//{})|to_entries|all(.value|type=="array" and length==3 and all(type=="number" and floor==. and .>=0 and .<=255))) and
    ((.fable.refresh_seconds//600)>=60) and ((.fable.max_stale_seconds//86400)>=60)
  ' "$config_file" >/dev/null 2>&1
}
if valid_config; then cfg=$config_file; else cfg=; fi

get_cfg() {
  local expr=$1 fallback=$2
  if [[ -n "$cfg" ]]; then jq -r "$expr // $fallback" "$cfg"; else jq -nr "$fallback"; fi
}
get_label() {
  if [[ -n "$cfg" ]]; then jq -r --arg k "$1" --arg d "$2" '.labels[$k]//$d' "$cfg"; else printf '%s\n' "$2"; fi
}
get_width() {
  if [[ -n "$cfg" ]]; then jq -r --arg k "$1" --argjson d "$2" '.widths[$k]//$d' "$cfg"; else printf '%s\n' "$2"; fi
}

refresh_seconds=$(get_cfg '.fable.refresh_seconds' '600')
max_stale=$(get_cfg '.fable.max_stale_seconds' '86400')
fable_model=$(get_cfg '.fable.model' '"Fable"')
usage_warn=$(get_cfg '.thresholds.usage.warn' '60')
usage_critical=$(get_cfg '.thresholds.usage.critical' '80')
drift_warn=$(get_cfg '.thresholds.drift.warn' '70')
drift_good=$(get_cfg '.thresholds.drift.good' '90')
if [[ -n $cfg ]]; then
  IFS=$'\t' read -r ok_r ok_g ok_b <<<"$(jq -r '(.colors.ok//[60,180,80])|@tsv' "$cfg")"
  IFS=$'\t' read -r warn_r warn_g warn_b <<<"$(jq -r '(.colors.warn//[200,160,0])|@tsv' "$cfg")"
  IFS=$'\t' read -r crit_r crit_g crit_b <<<"$(jq -r '(.colors.critical//[180,60,40])|@tsv' "$cfg")"
else
  read -r ok_r ok_g ok_b <<<"60 180 80"
  read -r warn_r warn_g warn_b <<<"200 160 0"
  read -r crit_r crit_g crit_b <<<"180 60 40"
fi

oauth_token() {
  if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then printf '%s' "$CLAUDE_CODE_OAUTH_TOKEN"; return; fi
  if [[ $(uname -s 2>/dev/null) == Darwin ]] && command -v security >/dev/null; then
    local value
    value=$(security find-generic-password -s 'Claude Code-credentials' -w 2>/dev/null || true)
    if [[ -n "$value" ]]; then
      if jq -e . >/dev/null 2>&1 <<<"$value"; then jq -r '.claudeAiOauth.accessToken//.accessToken//empty' <<<"$value"; else printf '%s' "$value"; fi
      return
    fi
  fi
  local file=$config_dir/.credentials.json
  [[ -r "$file" ]] || file=$HOME/.claude/.credentials.json
  [[ -r "$file" ]] && jq -r '.claudeAiOauth.accessToken//.accessToken//empty' "$file" 2>/dev/null
}

refresh_fable() (
  mkdir -p "$cache_dir" 2>/dev/null || return 0
  local lock=$cache_dir/refresh.lock next_file=$cache_dir/next_refresh headers=$cache_dir/headers.$$ now next mtime token response pct reset tmp retry
  now=$(date +%s)
  if ! mkdir "$lock" 2>/dev/null; then
    # A refresh killed mid-flight (statusline timeout) never runs its EXIT trap; reclaim its lock.
    # GNU stat first: on Linux `stat -f` means filesystem status and would not yield an mtime.
    mtime=$(stat -c %Y "$lock" 2>/dev/null || stat -f %m "$lock" 2>/dev/null || printf "$now")
    # ponytail: rmdir+mkdir is not atomic; two renders racing on one stale lock can both refresh once.
    ((now-mtime>60)) && rmdir "$lock" 2>/dev/null && mkdir "$lock" 2>/dev/null || return 0
  fi
  trap 'rmdir "$lock" 2>/dev/null; rm -f "$headers"' EXIT
  next=$(cat "$next_file" 2>/dev/null); [[ $next =~ ^[0-9]+$ ]] && ((now<next)) && return 0
  token=$(oauth_token); [[ -n "$token" ]] || return 0
  # Claim the slot before the request so a failure backs off instead of retrying on every render.
  printf '%s' $((now+refresh_seconds)) >"$next_file"
  if ! response=$(printf 'Authorization: Bearer %s\n' "$token" | curl -fsS -D "$headers" --max-time 8 -H @- -H 'anthropic-beta: oauth-2025-04-20' -H 'Accept: application/json' -H 'User-Agent: claude-code/braisenly-statusline' "${BRAISENLY_STATUSLINE_USAGE_URL:-https://api.anthropic.com/api/oauth/usage}" 2>/dev/null); then
    retry=$(tr -d '\r' <"$headers" 2>/dev/null | awk -F': *' 'tolower($1)=="retry-after"{print $2}' | tail -1)
    [[ $retry =~ ^[0-9]+$ ]] && ((retry>refresh_seconds)) && printf '%s' $((now+retry)) >"$next_file"
    return 0
  fi
  pct=$(jq -r --arg m "$fable_model" '([(.limits // .cachedUsageUtilization.utilization.limits // [])[]?|select(.kind=="weekly_scoped")|select(((.scope.model.display_name//.scope.model//.model//"")|ascii_downcase|startswith($m|ascii_downcase)))][0]|.percent//.used_percentage//.utilization//.usage_percentage)//.fable.percent//.fable.used_percentage//.weekly_fable.percent//.weekly_fable.used_percentage//.seven_day_fable.percent//.seven_day_fable.used_percentage//empty' <<<"$response" 2>/dev/null)
  reset=$(jq -r --arg m "$fable_model" '([(.limits // .cachedUsageUtilization.utilization.limits // [])[]?|select(.kind=="weekly_scoped")|select(((.scope.model.display_name//.scope.model//.model//"")|ascii_downcase|startswith($m|ascii_downcase)))][0]|.resets_at//.reset_at)//.fable.resets_at//.weekly_fable.resets_at//.seven_day_fable.resets_at//empty' <<<"$response" 2>/dev/null)
  [[ $pct =~ ^[0-9]+([.][0-9]+)?$ ]] || return 0
  tmp=$cache_file.tmp.$$
  jq -n --argjson p "$pct" --arg r "$reset" --arg m "$fable_model" --argjson at "$now" '{used_percentage:$p,resets_at:$r,model:$m,fetched_at:$at}' >"$tmp" && mv "$tmp" "$cache_file"
)

if [[ $mode == refresh ]]; then refresh_fable; exit 0; fi
[[ -n ${BRAISENLY_STATUSLINE_DISABLE_REFRESH:-} ]] || (refresh_fable) >/dev/null 2>&1 &

input=$(cat)
if [[ -n ${NO_COLOR:-} ]]; then reset= model_color= label_color= sep_color= value_color= empty_color=
else reset=$'\033[0m'; model_color=$'\033[1;38;5;75m'; label_color=$'\033[38;5;240m'; sep_color=$'\033[38;5;237m'; value_color=$'\033[38;5;243m'; empty_color=$'\033[38;5;59m'; fi

sep() { printf '%s ● %s' "$sep_color" "$reset"; }
fmt_bytes() { local b=$1; if ((b>=1073741824)); then awk -v b="$b" 'BEGIN{printf "%.1fG",b/1073741824}'; elif ((b>=1048576)); then awk -v b="$b" 'BEGIN{printf "%.1fM",b/1048576}'; elif ((b>=1024)); then awk -v b="$b" 'BEGIN{printf "%.1fK",b/1024}'; else printf '%dB' "$b"; fi; }
pct_text() { local p=$1 r g b; if ((p<=usage_warn)); then r=$ok_r g=$ok_g b=$ok_b; elif ((p<=usage_critical)); then r=$warn_r g=$warn_g b=$warn_b; else r=$crit_r g=$crit_g b=$crit_b; fi; if [[ -n ${NO_COLOR:-} ]]; then printf '%d%%' "$p"; else printf '\033[38;2;%d;%d;%dm%d%%%s' "$r" "$g" "$b" "$p" "$reset"; fi; }
drift_text() { local p=$1 r g b; if ((p>=drift_good)); then r=$ok_r g=$ok_g b=$ok_b; elif ((p>=drift_warn)); then r=$warn_r g=$warn_g b=$warn_b; else r=$crit_r g=$crit_g b=$crit_b; fi; if [[ -n ${NO_COLOR:-} ]]; then printf '%d%%' "$p"; else printf '\033[38;2;%d;%d;%dm%d%%%s' "$r" "$g" "$b" "$p" "$reset"; fi; }
bar() {
  local pct=$1 width=${2:-20} inverted=${3:-0} full i pos r g b p2
  ((pct<0))&&pct=0; ((pct>100))&&pct=100
  # Whole cells only: an eighth-block glyph leaves a blank gap before the ░ track.
  full=$(((pct*width+50)/100)); ((pct>0&&full==0))&&full=1
  printf '['
  for ((i=0;i<full;i++)); do
    ((inverted))&&pos=$((100-i*100/width))||pos=$((i*100/width)); if ((pos<=50)); then r=$((40+180*pos/50)); g=$((170-10*pos/50)); b=$((60-60*pos/50)); else p2=$((pos-50)); r=$((220-40*p2/50)); g=$((160-160*p2/50)); b=0; fi
    [[ -n ${NO_COLOR:-} ]]&&printf '█'||printf '\033[38;2;%d;%d;%dm█' "$r" "$g" "$b"
  done
  ((full<width))&&printf '%s' "$empty_color"; for ((i=full;i<width;i++)); do printf '░'; done; printf '%s]' "$reset"
}

model=$(jq -r '.model.display_name//"Claude"' <<<"$input"); used=$(jq -r '.context_window.used_percentage//"null"' <<<"$input"); total_in=$(jq -r '.context_window.total_input_tokens//0' <<<"$input"); ctx=$(jq -r '.context_window.context_window_size//0' <<<"$input"); five=$(jq -r '.rate_limits.five_hour.used_percentage//"null"' <<<"$input"); seven=$(jq -r '.rate_limits.seven_day.used_percentage//"null"' <<<"$input"); session=$(jq -r '.session_id//empty' <<<"$input")
fable=null
if [[ -r $cache_file ]]; then at=$(jq -r '.fetched_at//0' "$cache_file" 2>/dev/null||printf 0); [[ $at =~ ^[0-9]+$ ]]&&(( $(date +%s)-at<=max_stale ))&&fable=$(jq -r '.used_percentage//"null"' "$cache_file" 2>/dev/null||printf null); fi
drift= tag=baseline provider=
if [[ -n $session && -r $config_dir/state/drift/$session.jsonl ]]; then last=$(tail -n 30 "$config_dir/state/drift/$session.jsonl"|jq -rs '[.[]|select(.kind=="score")]|last//empty' 2>/dev/null); [[ -n $last && $last != null ]]&&{ drift=$(jq -r .score<<<"$last"); tag=$(jq -r .tag<<<"$last"); provider=$(jq -r '.provider//""'<<<"$last"); }; fi

render_model(){ printf '%s%s%s' "$model_color" "$model" "$reset"; }
render_profile(){ local p=${CLAUDE_PROFILE:-} b; if [[ -z $p && -n ${CLAUDE_CONFIG_DIR:-} ]]; then b=${CLAUDE_CONFIG_DIR##*/}; [[ $b == .claude-* ]]&&p=${b#.claude-}; fi; [[ -n $p ]]&&printf '%sprof%s %s%s%s' "$label_color" "$reset" "$value_color" "$p" "$reset"; }
render_cwd(){ local p=${PWD/#$HOME/\~}; ((${#p}>30))&&p="…/$(basename "$(dirname "$PWD")")/$(basename "$PWD")"; printf '%s%s%s' "$value_color" "$p" "$reset"; }
render_context(){ local v w; w=$(get_width context 12); printf '%s%s%s ' "$label_color" "$(get_label context ctx)" "$reset"; if [[ $used != null && $ctx -gt 0 ]]; then v=$(printf '%.0f' "$used"); printf '%s %s%s%s/%s%s%s (%s)' "$(bar "$v" "$w")" "$value_color" "$(fmt_bytes "$total_in")" "$reset" "$value_color" "$(fmt_bytes "$ctx")" "$reset" "$(pct_text "$v")"; else bar 0 "$w"; fi; }
render_disk(){ local x t a p w; x=$(df -k / 2>/dev/null|tail -1); [[ -n $x ]]||return; t=$(awk '{print $2}'<<<"$x"); a=$(awk '{print $4}'<<<"$x"); ((t>0))||return; p=$(((t-a)*100/t)); w=$(get_width disk 12); printf '%s%s%s %s %s%s%s free' "$label_color" "$(get_label disk disk)" "$reset" "$(bar "$p" "$w")" "$value_color" "$(fmt_bytes $((a*1024)))" "$reset"; }
render_tmp(){ local x d t a p w; x=$(df -k /tmp 2>/dev/null|tail -1); d=$(awk '{print $1}'<<<"$x"); [[ $d == tmpfs ]]||return; t=$(awk '{print $2}'<<<"$x"); a=$(awk '{print $4}'<<<"$x"); ((t>0))||return; p=$(((t-a)*100/t)); w=$(get_width tmp 15); printf '%s%s%s %s %s%s%s free' "$label_color" "$(get_label tmp /tmp)" "$reset" "$(bar "$p" "$w")" "$value_color" "$(fmt_bytes $((a*1024)))" "$reset"; }
render_usage(){ local k=$1 d=$2 p=$3 v w; [[ $p != null && -n $p ]]||return; v=$(printf '%.0f' "$p"); w=$(get_width "$k" 12); printf '%s%s%s %s (%s)' "$label_color" "$(get_label "$k" "$d")" "$reset" "$(bar "$v" "$w")" "$(pct_text "$v")"; }
render_fable(){ local p=$1 v w; w=$(get_width fable 12); if [[ $p == null || -z $p ]]; then printf '%s%s%s %s (n/a)' "$label_color" "$(get_label fable Fable)" "$reset" "$(bar 0 "$w")"; else v=$(printf '%.0f' "$p"); printf '%s%s%s %s (%s)' "$label_color" "$(get_label fable Fable)" "$reset" "$(bar "$v" "$w")" "$(pct_text "$v")"; fi; }
render_drift(){ local w marker drift_label; w=$(get_width drift 10); drift_label=$(get_label drift drift); if [[ -z ${TMUX:-} && -z ${NO_COLOR:-} ]]; then printf '%s\033]8;;file://%s/.claude/scripts/drift-menu-open.command\033\\%s\033]8;;\033\\%s ' "$label_color" "$HOME" "$drift_label" "$reset"; else printf '%s%s%s ' "$label_color" "$drift_label" "$reset"; fi; if [[ -n $drift ]]; then case $provider in groq)marker=⬢;;gemini)marker=◉;;openai)marker=◈;;ollama)marker=◇;;*)marker=·;;esac; printf '%s %s(%s%s)%s (%s)' "$(bar "$drift" "$w" 1)" "$value_color" "$tag" "$marker" "$reset" "$(drift_text "$drift")"; else printf '%s %s(baseline)%s' "$(bar 100 "$w" 1)" "$value_color" "$reset"; fi; }

segments=$default_segments; [[ -n $cfg ]]&&segments=$(jq -c '.segments//$d' --argjson d "$default_segments" "$cfg")
first=1
while IFS= read -r segment; do
  rendered=; case $segment in model)rendered=$(render_model);;profile)rendered=$(render_profile);;cwd)rendered=$(render_cwd);;context)rendered=$(render_context);;disk)rendered=$(render_disk);;tmp)rendered=$(render_tmp);;five_hour)rendered=$(render_usage five_hour 5h "$five");;seven_day)rendered=$(render_usage seven_day 7d "$seven");;fable)rendered=$(render_fable "$fable");;drift)rendered=$(render_drift);;esac
  [[ -n $rendered ]]||continue; ((first))||sep; printf '%s' "$rendered"; first=0
done < <(jq -r '.[]'<<<"$segments")
printf '\n'

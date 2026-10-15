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
default_segments='["model","profile","cwd","context","disk","tmp","five_hour","seven_day","fable"]'

valid_config() {
  [[ -r "$config_file" ]] || return 1
  jq -e '
    def known: ["model","profile","cwd","context","disk","tmp","five_hour","seven_day","fable"];
    (.segments // known) as $s |
    ($s|type)=="array" and ($s|all(type=="string" and IN(known[]))) and (($s|unique|length)==($s|length)) and
    ((.labels//{})|to_entries|all(.value|type=="string")) and
    ((.widths//{})|to_entries|all(.value|type=="number" and floor==. and .>=1 and .<=128)) and
    ((.fit.reserve//0)|type=="number" and floor==. and .>=0 and .<=200) and ((.fit.min_bar_cells//5)|type=="number" and floor==. and .>=1 and .<=128) and ((.fit.resize_watch//false)|type=="boolean") and ((.fit.rows//1)|IN(1,2)) and
    ((.fit.ladder//[])|type=="array" and all(IN("disk_label","ctx_int","no_parens","disk_int","ctx_no_total","no_free","fable_short","disk_value","ctx_no_used","fable_label","fable_segment","seven_label","five_label","ctx_label","seven_segment","five_segment"))) and
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
fit_reserve=$(get_cfg '.fit.reserve' '0')
min_bar_cells=$(get_cfg '.fit.min_bar_cells' '5')

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

# Walk up the parent chain to the Claude Code process; its pty is the live source of the terminal width.
claude_pid=; _p=$PPID; for _i in 1 2 3 4 5 6; do _c=$(ps -o comm= -p "$_p" 2>/dev/null); [[ ${_c##*/} == claude* ]] && { claude_pid=$_p; break; }; _p=$(ps -o ppid= -p "$_p" 2>/dev/null | tr -d ' '); [[ ${_p:-0} -gt 1 ]] || break; done
# Live width: the pty ioctl is current at the instant we render; COLUMNS from Claude Code can lag a resize by one render.
live_cols=; if [[ -n $claude_pid && -z ${BRAISENLY_STATUSLINE_NO_LIVE_COLS:-} ]]; then _t=$(ps -o tty= -p "$claude_pid" 2>/dev/null | tr -d ' '); [[ -n $_t && $_t != '??' && -r /dev/$_t ]] && live_cols=$(stty size </dev/$_t 2>/dev/null | awk '{print $2}'); fi
[[ $live_cols =~ ^[0-9]+$ && $live_cols -gt 0 ]] && COLUMNS=$live_cols
# One resize watcher per Claude Code process, locked on its pid.
start_resize_watch() {
  local pid=$claude_pid lock
  [[ -n $pid ]] || return 0
  mkdir -p "$cache_dir" 2>/dev/null || return 0
  lock=$cache_dir/resize-watch.$pid.pid
  [[ -r $lock ]] && kill -0 "$(cat "$lock" 2>/dev/null)" 2>/dev/null && return 0
  # Two overlapping renders must not both spawn: mkdir is the atomic mutex around check-and-spawn.
  # A render killed mid-spawn never removes it; reclaim a mutex older than 60s.
  if ! mkdir "$lock.spawn" 2>/dev/null; then
    local mt; mt=$(stat -c %Y "$lock.spawn" 2>/dev/null || stat -f %m "$lock.spawn" 2>/dev/null || printf '%s' "$(date +%s)")
    (( $(date +%s)-mt>60 )) && rmdir "$lock.spawn" 2>/dev/null && mkdir "$lock.spawn" 2>/dev/null || return 0
  fi
  trap "rmdir '$lock.spawn' 2>/dev/null" EXIT
  if ! { [[ -r $lock ]] && kill -0 "$(cat "$lock" 2>/dev/null)" 2>/dev/null; }; then
    nohup bash "${BASH_SOURCE[0]%/*}/resize-watch.sh" --pid "$pid" --settings "$config_dir/settings.json" --interval 0.1 --settle 0.2 >/dev/null 2>&1 &
    printf '%s' $! >"$lock"
  fi
  rmdir "$lock.spawn" 2>/dev/null
}
# Opt-in: the watcher rewrites settings.json on resize, so it is off unless fit.resize_watch is true.
[[ -n ${BRAISENLY_STATUSLINE_DISABLE_WATCH:-} ]] || [[ $(get_cfg '.fit.resize_watch' 'false') != true ]] || start_resize_watch

input=$(cat)
# Timing trace, enabled by touching $cache_dir/trace: when each render started and what width it saw.
[[ -e $cache_dir/trace ]] && printf '%s render COLUMNS=%s live=%s\n' "$(date +%s.%N)" "${COLUMNS:-}" "${live_cols:-}" >>"$cache_dir/trace"
if [[ -n ${NO_COLOR:-} ]]; then reset= model_color= label_color= sep_color= value_color= empty_color=
else reset=$'\033[0m'; model_color=$'\033[1;38;5;75m'; label_color=$'\033[38;5;240m'; sep_color=$'\033[38;5;237m'; value_color=$'\033[38;5;243m'; empty_color=$'\033[38;5;59m'; fi

# ${#var} must count characters, not bytes: pick a UTF-8 locale if the host left us in a byte locale.
_g='█'; if ((${#_g}!=1)); then for _l in C.UTF-8 en_US.UTF-8; do LC_ALL=$_l; ((${#_g}==1))&&break; done; fi; unset _g _l
sep="$sep_color ● $reset"
# fmt_bytes <bytes> [decimals]
fmt_bytes() { local b=$1 d=${2:-1}; if ((b>=1073741824)); then awk -v b="$b" -v d="$d" 'BEGIN{printf "%.*fG",d,b/1073741824}'; elif ((b>=1048576)); then awk -v b="$b" -v d="$d" 'BEGIN{printf "%.*fM",d,b/1048576}'; elif ((b>=1024)); then awk -v b="$b" -v d="$d" 'BEGIN{printf "%.*fK",d,b/1024}'; else printf '%dB' "$b"; fi; }
# Gradient colour of a bar cell at position pos (0..100): green, through amber, to red. Sets r g b; no subshell.
heat_rgb() { local pos=$1 p2; if ((pos<=50)); then r=$((40+180*pos/50)) g=$((170-10*pos/50)) b=$((60-60*pos/50)); else p2=$((pos-50)); r=$((220-40*p2/50)) g=$((160-160*p2/50)) b=0; fi; }
# The number always carries the heat colour of its bar tip, bar shown or not.
pct_text() { local p=$1 r g b; heat_rgb "$p"; if [[ -n ${NO_COLOR:-} ]]; then PCT="$p%"; else printf -v PCT '\033[38;2;%d;%d;%dm%d%%%s' "$r" "$g" "$b" "$p" "$reset"; fi; }
# Fit state: bars_off=1 drops every bar; scale_num/scale_den shrink configured widths uniformly.
bars_off=0 scale_num=1 scale_den=1
bar() { # sets BAR; empty when bars are off. No subshells: this runs inside the fit loop.
  local pct=$1 width=$2 full i pos r g b cell
  BAR=; ((bars_off))&&return
  width=$((width*scale_num/scale_den)); ((width<1))&&width=1
  ((pct<0))&&pct=0; ((pct>100))&&pct=100
  # Whole cells only: an eighth-block glyph leaves a blank gap before the ░ track.
  full=$(((pct*width+50)/100)); ((pct>0&&full==0))&&full=1
  BAR='['
  for ((i=0;i<full;i++)); do
    pos=$((i*100/width)); heat_rgb "$pos"
    if [[ -n ${NO_COLOR:-} ]]; then BAR+='█'; else printf -v cell '\033[38;2;%d;%d;%dm█' "$r" "$g" "$b"; BAR+=$cell; fi
  done
  ((full<width))&&BAR+=$empty_color; for ((i=full;i<width;i++)); do BAR+='░'; done; BAR+="$reset]"
}
# Display cells of a string: strip SGR, count characters, then add one more cell for each East Asian Wide or emoji
# code point (user labels, model names, and paths may carry them). Pure bash; the wide scan only runs on exotic text.
cells() {
  local s=$1 pre rest x i ch cp
  while [[ $s == *$'\033['* ]]; do pre=${s%%$'\033['*}; rest=${s#*$'\033['}; s=$pre${rest#*m}; done
  N=${#s}
  x=${s//[ -~█░●…⠀]/}; [[ -n $x ]]||return 0
  for ((i=0;i<${#x};i++)); do
    ch=${x:i:1}; printf -v cp '%d' "'$ch"
    if ((cp>=0x1100&&cp<=0x115F)) || ((cp>=0x2E80&&cp<=0xA4CF&&cp!=0x303F)) || ((cp>=0xAC00&&cp<=0xD7A3)) || ((cp>=0xF900&&cp<=0xFAFF)) || ((cp>=0xFE30&&cp<=0xFE4F)) || ((cp>=0xFF00&&cp<=0xFF60)) || ((cp>=0xFFE0&&cp<=0xFFE6)) || ((cp>=0x1F300&&cp<=0x1F64F)) || ((cp>=0x1F900&&cp<=0x1F9FF)) || ((cp>=0x20000&&cp<=0x3FFFD)); then N=$((N+1)); fi
  done
}

model=$(jq -r '.model.display_name//"Claude"' <<<"$input"); used=$(jq -r '.context_window.used_percentage//"null"' <<<"$input"); total_in=$(jq -r '.context_window.total_input_tokens//0' <<<"$input"); ctx=$(jq -r '.context_window.context_window_size//0' <<<"$input"); five=$(jq -r '.rate_limits.five_hour.used_percentage//"null"' <<<"$input"); seven=$(jq -r '.rate_limits.seven_day.used_percentage//"null"' <<<"$input")
fable=null
if [[ -r $cache_file ]]; then at=$(jq -r '.fetched_at//0' "$cache_file" 2>/dev/null||printf 0); [[ $at =~ ^[0-9]+$ ]]&&(( $(date +%s)-at<=max_stale ))&&fable=$(jq -r '.used_percentage//"null"' "$cache_file" 2>/dev/null||printf null); fi

# ---- values and labels, computed once (the fit loop below must not fork) ----
segments=$default_segments; [[ -n $cfg ]]&&segments=$(jq -c '.segments//$d' --argjson d "$default_segments" "$cfg")
seg_list=(); while IFS= read -r s; do seg_list+=("$s"); done < <(jq -r '.[]'<<<"$segments")
L_ctx=$(get_label context ctx) L_disk=$(get_label disk disk) L_tmp=$(get_label tmp /tmp) L_five=$(get_label five_hour 5h) L_seven=$(get_label seven_day 7d) L_fable=$(get_label fable Fable)
W_ctx=$(get_width context 12) W_disk=$(get_width disk 12) W_tmp=$(get_width tmp 15) W_five=$(get_width five_hour 12) W_seven=$(get_width seven_day 12) W_fable=$(get_width fable 12)
profile=${CLAUDE_PROFILE:-}; if [[ -z $profile && -n ${CLAUDE_CONFIG_DIR:-} ]]; then _b=${CLAUDE_CONFIG_DIR##*/}; [[ $_b == .claude-* ]]&&profile=${_b#.claude-}; fi
cwd=${PWD/#$HOME/\~}; ((${#cwd}>30))&&cwd="…/$(basename "$(dirname "$PWD")")/$(basename "$PWD")"
ctx_pct=; ctx_used1= ctx_used0= ctx_total1= ctx_total0=
if [[ $used != null && $ctx -gt 0 ]]; then ctx_pct=$(printf '%.0f' "$used"); ctx_used1=$(fmt_bytes "$total_in" 1); ctx_used0=$(fmt_bytes "$total_in" 0); ctx_total1=$(fmt_bytes "$ctx" 1); ctx_total0=$(fmt_bytes "$ctx" 0); fi
disk_pct= disk_free1= disk_free0=
_x=$(df -k / 2>/dev/null|tail -1); if [[ -n $_x ]]; then _t=$(awk '{print $2}'<<<"$_x"); _a=$(awk '{print $4}'<<<"$_x"); if ((_t>0)); then disk_pct=$(((_t-_a)*100/_t)); disk_free1=$(fmt_bytes $((_a*1024)) 1); disk_free0=$(fmt_bytes $((_a*1024)) 0); fi; fi
tmp_pct= tmp_free1= tmp_free0=
_x=$(df -k /tmp 2>/dev/null|tail -1); if [[ $(awk '{print $1}'<<<"$_x") == tmpfs ]]; then _t=$(awk '{print $2}'<<<"$_x"); _a=$(awk '{print $4}'<<<"$_x"); if ((_t>0)); then tmp_pct=$(((_t-_a)*100/_t)); tmp_free1=$(fmt_bytes $((_a*1024)) 1); tmp_free0=$(fmt_bytes $((_a*1024)) 0); fi; fi
five_pct=; [[ $five != null && -n $five ]]&&five_pct=$(printf '%.0f' "$five")
seven_pct=; [[ $seven != null && -n $seven ]]&&seven_pct=$(printf '%.0f' "$seven")
fable_pct=; [[ $fable != null && -n $fable ]]&&fable_pct=$(printf '%.0f' "$fable")

# ---- exclusion ladder: ordered flags the builders consult; each step buys cells when nothing else fits ----
default_ladder='disk_label ctx_int no_parens disk_int ctx_no_total no_free fable_short disk_value ctx_no_used fable_label fable_segment seven_label five_label ctx_label seven_segment five_segment'
ladder=$default_ladder; [[ -n $cfg ]]&&ladder=$(jq -r --arg d "$default_ladder" '(.fit.ladder // ($d|split(" ")))|join(" ")' "$cfg")
fit_rows=$(get_cfg '.fit.rows' '1')
declare -A F=()
paren() { if [[ -n ${F[no_parens]:-} ]]; then P=$1; else P="($1)"; fi; }
lab() { printf '%s%s%s' "$label_color" "$1" "$reset"; }   # only used outside the fit loop
pct_paren() { pct_text "$1"; paren "$PCT"; }               # sets P

# Builders fill seg_top[] (label + bar) and seg_bot[] (values). A segment with both empty is omitted.
build() {
  local s top bot used total pct free1 free0 L W
  seg_top=() seg_bot=()
  for s in "${seg_list[@]}"; do
    top= bot=
    case $s in
      model) top="$model_color$model$reset" ;;
      profile) [[ -n $profile ]]&&top="${label_color}prof$reset $value_color$profile$reset" ;;
      cwd) top="$value_color$cwd$reset" ;;
      context)
        [[ -n ${F[ctx_label]:-} ]]||top="$label_color$L_ctx$reset"
        if [[ -n $ctx_pct ]]; then
          bar "$ctx_pct" "$W_ctx"; top+=${BAR:+${top:+ }$BAR}
          if [[ -n ${F[ctx_int]:-} ]]; then used=$ctx_used0 total=$ctx_total0; else used=$ctx_used1 total=$ctx_total1; fi
          [[ -n ${F[ctx_no_used]:-} ]]||bot="$value_color$used$reset"
          [[ -n ${F[ctx_no_total]:-} ]]||bot+="$value_color${bot:+/}$total$reset"
          pct_paren "$ctx_pct"; bot+=${bot:+ }$P
        else bar 0 "$W_ctx"; top+=${BAR:+${top:+ }$BAR}; fi ;;
      disk|tmp)
        if [[ $s == disk ]]; then pct=$disk_pct free1=$disk_free1 free0=$disk_free0 L=$L_disk W=$W_disk; else pct=$tmp_pct free1=$tmp_free1 free0=$tmp_free0 L=$L_tmp W=$W_tmp; fi
        [[ -n $pct ]]||continue
        [[ -n ${F[disk_label]:-} ]]||top="$label_color$L$reset"
        bar "$pct" "$W"; top+=${BAR:+${top:+ }$BAR}
        if [[ -z ${F[disk_value]:-} ]]; then if [[ -n ${F[disk_int]:-} ]]; then bot="$value_color$free0$reset"; else bot="$value_color$free1$reset"; fi; [[ -n ${F[no_free]:-} ]]||bot+=" free"; fi ;;
      five_hour)
        [[ -n $five_pct && -z ${F[five_segment]:-} ]]||continue
        [[ -n ${F[five_label]:-} ]]||top="$label_color$L_five$reset"; bar "$five_pct" "$W_five"; top+=${BAR:+${top:+ }$BAR}; pct_paren "$five_pct"; bot=$P ;;
      seven_day)
        [[ -n $seven_pct && -z ${F[seven_segment]:-} ]]||continue
        [[ -n ${F[seven_label]:-} ]]||top="$label_color$L_seven$reset"; bar "$seven_pct" "$W_seven"; top+=${BAR:+${top:+ }$BAR}; pct_paren "$seven_pct"; bot=$P ;;
      fable)
        [[ -z ${F[fable_segment]:-} ]]||continue
        if [[ -n ${F[fable_label]:-} ]]; then :; elif [[ -n ${F[fable_short]:-} ]]; then top="$label_color${L_fable:0:1}$reset"; else top="$label_color$L_fable$reset"; fi
        if [[ -n $fable_pct ]]; then bar "$fable_pct" "$W_fable"; top+=${BAR:+${top:+ }$BAR}; pct_paren "$fable_pct"; bot=$P; else bar 0 "$W_fable"; top+=${BAR:+${top:+ }$BAR}; paren n/a; bot=$P; fi ;;
    esac
    [[ -n $top$bot ]]||continue
    seg_top+=("$top"); seg_bot+=("$bot")
  done
}
# flat: one row, "top bot" per segment. stacked: two rows, each segment padded to max(top,bot) so columns align.
assemble_flat() { local i part out=; for i in "${!seg_top[@]}"; do part=${seg_top[i]}; [[ -n $part && -n ${seg_bot[i]} ]]&&part+=' '; part+=${seg_bot[i]}; out+=${out:+$sep}$part; done; row1=$out row2=; }
assemble_stacked() {
  local i t b wt wb w pad r1= r2=
  for i in "${!seg_top[@]}"; do
    t=${seg_top[i]} b=${seg_bot[i]}; cells "$t"; wt=$N; cells "$b"; wb=$N; w=$((wt>wb?wt:wb))
    printf -v pad '%*s' $((w-wt)) ''; r1+=${r1:+$sep}$t$pad
    printf -v pad '%*s' $((w-wb)) ''; r2+=${r2:+$sep}$b$pad
  done
  # Claude Code trims leading whitespace per row; pad row starts with U+2800 (renders blank, counts one cell).
  local lead; lead=${r1%%[! ]*}; r1=${lead// /⠀}${r1:${#lead}}; lead=${r2%%[! ]*}; r2=${lead// /⠀}${r2:${#lead}}
  row1=$r1 row2=$r2
}

# ---- fit pipeline: try flat then stacked at each stage; stop at the first that fits ----
emit() { printf '%s\n' "$row1"; [[ -n $row2 ]]&&printf '%s\n' "$row2"; exit 0; }
fits() { cells "$row1"; ((N<=budget)); }
try_layouts() { build; assemble_flat; fits&&return 0; if ((fit_rows>=2)); then assemble_stacked; fits&&return 0; fi; return 1; }
pad_rows() { cells "$row1"; ((N<budget))&&printf -v _p '%*s' $((budget-N)) ''&&row1+=$_p; if [[ -n $row2 ]]; then cells "$row2"; ((N<budget))&&printf -v _p '%*s' $((budget-N)) ''&&row2+=$_p; fi; }

if ! [[ ${COLUMNS:-} =~ ^[0-9]+$ ]] || ((COLUMNS<=0)); then build; assemble_flat; emit; fi
budget=$((COLUMNS-3-fit_reserve)); ((budget<1))&&budget=1
# Stage 1: full bars.
try_layouts&&emit
# Stage 2: shrink bars uniformly. Walk the shared ratio down one cell at a time (stacked cells are bounded by their
# value row, so a bar cell does not always buy a column) and stop at the first ratio that fits or breaks the floor.
widths=; for s in "${seg_list[@]}"; do case $s in context)widths+=" $W_ctx";; disk)[[ -n $disk_pct ]]&&widths+=" $W_disk";; tmp)[[ -n $tmp_pct ]]&&widths+=" $W_tmp";; five_hour)[[ -n $five_pct ]]&&widths+=" $W_five";; seven_day)[[ -n $seven_pct ]]&&widths+=" $W_seven";; fable)widths+=" $W_fable";; esac; done
total=0; for w in $widths; do total=$((total+w)); done
# Largest shared ratio in [floor, full] whose layout fits; fits is monotonic in the ratio, so binary search.
shrink_layout() { # $1 = flat|stacked. Sets scale and rows on success.
  local lo=1 hi=$total mid w need best=
  # A bar configured below the floor is exempt from it (it shrinks proportionally, minimum one cell).
  for w in $widths; do ((w>=min_bar_cells))||continue; need=$(((min_bar_cells*total+w-1)/w)); ((need>lo))&&lo=$need; done
  ((lo<=hi))||{ scale_num=1 scale_den=1; return 1; }
  scale_den=$total
  while ((lo<=hi)); do
    mid=$(((lo+hi)/2)); scale_num=$mid; build; "assemble_$1"
    if fits; then best=$mid lo=$((mid+1)); else hi=$((mid-1)); fi
  done
  [[ -n $best ]]||{ scale_num=1 scale_den=1; return 1; }
  scale_num=$best; build; "assemble_$1"; return 0
}
if ((total>0)); then
  shrink_layout flat&&{ pad_rows; emit; }
  ((fit_rows>=2))&&shrink_layout stacked&&{ pad_rows; emit; }
fi
# Stage 3 (two rows only): keep the bars. Walk the ladder with bars at the best size that fits each step.
if ((fit_rows>=2&&total>0)); then
  for step in $ladder; do F[$step]=1; shrink_layout stacked&&{ pad_rows; emit; }; done
  F=()
fi
# Stage 4: bars gone; percentages carry the heat colour instead.
scale_num=1 scale_den=1 bars_off=1
try_layouts&&{ pad_rows; emit; }
# Stage 5: exclusion ladder again without bars, one step at a time, re-measured after each.
for step in $ladder; do F[$step]=1; try_layouts&&{ pad_rows; emit; }; done
# Floor: nothing left to give; Claude Code truncates the overflow.
build; assemble_flat; emit

#!/usr/bin/env bash
# Reset-toggle constants contract; tests/test-constants.ps1 runs the same cases against constants.ps1.
set -uo pipefail

Usage() {
  printf 'Usage: %s [-h|--help]\n' "${0##*/}"
}

case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
  '') ;;
  *) Usage >&2; exit 2 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config/constants.sh
. "$root/config/constants.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Values.
[[ $RESET_TIME_GLYPH_CLOCKWISE_OPEN_CIRCLE_ARROW == '↻' ]] || fail 'reset glyph'
[[ $RESETS_CLICK_GLYPH_SHOWN_SQUARED_MINUS_THEN_LEFT_POINTING_SMALL_TRIANGLE == '⊟◂' ]] || fail 'shown glyph'
[[ $RESETS_CLICK_GLYPH_HIDDEN_SQUARED_PLUS_THEN_LEFT_POINTING_SMALL_TRIANGLE == '⊞◂' ]] || fail 'hidden glyph'
[[ ${#WEEKDAY_CODES_SUNDAY_FIRST_SU_M_T_W_R_F_SA[@]} -eq 7 && ${WEEKDAY_CODES_SUNDAY_FIRST_SU_M_T_W_R_F_SA[*]} == 'SU M T W R F SA' ]] || fail 'day codes'
[[ $RESETS_COUNTDOWN_STATUS_LINE_REFRESH_INTERVAL_SECONDS == 60 ]] || fail 'refresh interval'
[[ $RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R == 'ctrl+x r' ]] || fail 'default chord'

# Toggle URL: full match, slot 5h|7d, optional profile (PASS on the negatives = rejected).
url=$RESETS_TOGGLE_URL_SCHEME_TOGGLE_SLOT_5H_OR_7D_OPTIONAL_PROFILE_FULL_MATCH
for ok in 'claude-statusline://toggle?slot=5h' 'claude-statusline://toggle/?slot=7d' 'claude-statusline://toggle?slot=5h&profile=work-2.a_b'; do
  [[ $ok =~ $url ]] || fail "url rejected: $ok"
done
for bad in 'claude-statusline://toggle?slot=1h' 'claude-statusline://toggle?slot=5h&profile=' 'claude-statusline://toggle?slot=5h&profile=a/b' \
  'claude-statusline://toggle?slot=5h&x=1' 'claude-statusline://toggle?slot=5h;ls' 'xclaude-statusline://toggle?slot=5h' 'claude-statusline://toggle?slot=5h
tail' 'other://toggle?slot=5h' 'claude-statusline://toggle'; do
  if [[ $bad =~ $url ]]; then fail "negative: url accepted: $bad"; fi
done

# OSC 8: the whole sequence matches in both terminators; SGR and unterminated forms do not.
osc=$ANSI_OSC8_HYPERLINK_SEQUENCE_ESC_RIGHT_BRACKET_8_PARAMS_URI_TERMINATED_BY_ST_OR_BEL
esc=$'\033'; bel=$'\007'
for seq in "${esc}]8;id=bsl-5h;claude-statusline://toggle?slot=5h${esc}\\" "${esc}]8;;${esc}\\" "${esc}]8;id=bsl-7d;claude-statusline://toggle?slot=7d&profile=w${bel}" "${esc}]8;;${bel}"; do
  [[ $seq =~ $osc && ${BASH_REMATCH[0]} == "$seq" ]] || fail "osc8 not matched whole: ${seq//$esc/<ESC>}"
done
for bad in "${esc}[31m" "${esc}]8;id=x;uri-unterminated" "plain"; do
  if [[ $bad =~ $osc ]]; then fail "negative: osc8 matched: ${bad//$esc/<ESC>}"; fi
done
# Stripping a whole styled slot leaves only its text.
s="${esc}[2mfive ${esc}]8;id=bsl-5h;claude-statusline://toggle?slot=5h${esc}\\[25%]${esc}]8;;${esc}\\${esc}[0m"
while [[ $s =~ $osc ]]; do s=${s/"${BASH_REMATCH[0]}"/}; done
[[ $s == "${esc}[2mfive [25%]${esc}[0m" ]] || fail "strip: ${s//$esc/<ESC>}"

# Twin parity: the same constant names in both files.
names_sh=$(sed -nE 's/^([A-Z0-9_]+)=.*/\1/p' "$root/config/constants.sh" | sort)
names_ps1=$(sed -nE 's/^\$([A-Z0-9_]+) = .*/\1/p' "$root/config/constants.ps1" | sort)
[[ $names_sh == "$names_ps1" ]] || fail "constants.sh and constants.ps1 differ: $(diff <(printf '%s\n' "$names_sh") <(printf '%s\n' "$names_ps1") | tr '\n' ' ')"

printf 'ok\n'

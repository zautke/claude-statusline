#!/usr/bin/env bash
# Laboratory demo: one row of rings per codepoint block, heat-coloured SGR foreground. bash 3.2-safe.
usage() { echo "usage: demo.sh -b|--bases <hex,hex,...> [-s|--seconds <n>] [-g|--background <r;g;b>]"; }
bases= secs=20 bg=
while (($#)); do case $1 in -b|--bases) bases=$2; shift 2;; -s|--seconds) secs=$2; shift 2;; -g|--background) bg=$2; shift 2;; -h|--help) usage; exit 0;; *) usage; exit 2;; esac; done
[[ -n $bases ]] || { usage; exit 2; }
u8() { # u8 <codepoint> : print a plane-1..16 codepoint as UTF-8 without \U
  local c=$1
  printf "\\x$(printf '%02X' $((0xF0|c>>18)))\\x$(printf '%02X' $((0x80|(c>>12&63))))\\x$(printf '%02X' $((0x80|(c>>6&63))))\\x$(printf '%02X' $((0x80|(c&63))))"
}
[[ -n $bg ]] && printf '\e[48;2;%sm\e[2J' "$bg"
clear
IFS=, read -r -a B <<<"$bases"
for base in "${B[@]}"; do
  printf '%s  ' "$base"
  for p in 0 1 7 25 48 50 77 89 99 100; do
    if ((p<=50)); then r=$((40+180*p/50)) g=$((170-10*p/50)) b=$((60-60*p/50)); else r=$((220-40*(p-50)/50)) g=$((160-160*(p-50)/50)) b=0; fi
    printf '\e[38;2;%d;%d;%dm%s \e[39m %3d%%   ' "$r" "$g" "$b" "$(u8 $((16#$base + p)))" "$p"
  done
  printf '\n\n'
done
sleep "$secs"

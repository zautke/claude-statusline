#!/usr/bin/env bash
# E-002 demo: track glyph in a neutral colour followed by an arc glyph in the heat colour. bash 3.2-safe.
usage() { echo "usage: demo2.sh -n|--neutrals <r;g;b,r;g;b,...> [-t|--track <hex>] [-r|--arcs <hex>] [-s|--seconds <n>] [-g|--background <r;g;b>] [-f|--foreground <r;g;b>] [-T|--tile]"; }
neutrals= track=FFC00 arcs=FFC80 secs=20 bg= fgc= tile=0
while (($#)); do case $1 in -n|--neutrals) neutrals=$2; shift 2;; -t|--track) track=$2; shift 2;; -r|--arcs) arcs=$2; shift 2;; -s|--seconds) secs=$2; shift 2;; -g|--background) bg=$2; shift 2;; -f|--foreground) fgc=$2; shift 2;; -T|--tile) tile=1; shift;; -h|--help) usage; exit 0;; *) usage; exit 2;; esac; done
[[ -n $neutrals ]] || { usage; exit 2; }
u8() { local c=$1; printf "\\x$(printf '%02X' $((0xF0|c>>18)))\\x$(printf '%02X' $((0x80|(c>>12&63))))\\x$(printf '%02X' $((0x80|(c>>6&63))))\\x$(printf '%02X' $((0x80|(c&63))))"; }
base= ; [[ -n $bg ]] && base+=$(printf '\e[48;2;%sm' "$bg"); [[ -n $fgc ]] && base+=$(printf '\e[38;2;%sm' "$fgc")
printf '%s\e[2J\e[H' "$base"
T=$(u8 $((16#$track)))
IFS=, read -r -a N <<<"$neutrals"
for n in "${N[@]}"; do
  printf '%-12s ' "$n"
  for p in 0 1 7 25 48 50 77 89 99 100; do
    if ((p<=50)); then r=$((40+180*p/50)) g=$((170-10*p/50)) b=$((60-60*p/50)); else r=$((220-40*(p-50)/50)) g=$((160-160*(p-50)/50)) b=0; fi
    ((tile)) && T=$(u8 $((16#$track + p)))
    printf '\e[38;2;%sm%s\e[38;2;%d;%d;%dm%s\e[39m%s %3d%%   ' "$n" "$T" "$r" "$g" "$b" "$(u8 $((16#$arcs + p)))" "${fgc:+$(printf '\e[38;2;%sm' "$fgc")}" "$p"
  done
  printf '\n\n'
done
sleep "$secs"

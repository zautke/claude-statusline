#!/usr/bin/env bash
# E-004 status line: tiled two-cell rings inside a real Claude Code status line. bash 3.2-safe.
# Environment: RING_T / RING_R hex bases (defaults FFA00 / FFA80), RING_N neutral "r;g;b".
cat >/dev/null
tb=${RING_T:-FFA00} rb=${RING_R:-FFA80} n=${RING_N:-27;80;101}
u8() { local c=$1; printf "\\x$(printf '%02X' $((0xF0|c>>18)))\\x$(printf '%02X' $((0x80|(c>>12&63))))\\x$(printf '%02X' $((0x80|(c>>6&63))))\\x$(printf '%02X' $((0x80|(c&63))))"; }
ring() { local p=$1 r g b
  if ((p<=50)); then r=$((40+180*p/50)) g=$((170-10*p/50)) b=$((60-60*p/50)); else r=$((220-40*(p-50)/50)) g=$((160-160*(p-50)/50)) b=0; fi
  printf '\e[38;2;%sm%s\e[38;2;%d;%d;%dm%s\e[0m' "$n" "$(u8 $((16#$tb + p)))" "$r" "$g" "$b" "$(u8 $((16#$rb + p)))"; }
row=; for pair in ctx:48 disk:99 5h:7 7d:89 Fable:77; do row+="${pair%%:*} $(ring "${pair##*:}") (${pair##*:}%) | "; done
printf '%s\n' "$row"
printf '%s first-char ring, last-char ring %s\n' "$(ring 25)" "$(ring 63)"

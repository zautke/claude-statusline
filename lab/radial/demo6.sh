#!/usr/bin/env bash
# E-009 demo: reach test row, then four-cell dithered rings. bash 3.2-safe.
usage() { echo "usage: demo6.sh [-n|--neutral <r;g;b>] [-s|--seconds <n>] [-p|--percents \"<list>\"]"; }
n="76;76;76" secs=15 pcts="0 3 7 25 48 50 63 77 82 89 95 100"
while (($#)); do case $1 in -n|--neutral) n=$2; shift 2;; -s|--seconds) secs=$2; shift 2;; -p|--percents) pcts=$2; shift 2;; -h|--help) usage; exit 0;; *) usage; exit 2;; esac; done
u8() { local c=$1; printf "\\x$(printf '%02X' $((0xF0|c>>18)))\\x$(printf '%02X' $((0x80|(c>>12&63))))\\x$(printf '%02X' $((0x80|(c>>6&63))))\\x$(printf '%02X' $((0x80|(c&63))))"; }
printf '\e[2J\e[H'
printf 'reach -3..+3:  '
for k in 0 1 2 3 4 5 6; do printf 'x      \e[38;2;200;200;200m%s\e[39m      x  |  ' "$(u8 $((0xFEE00 + k)))"; done
printf '\n\n\nrings:   '
for p in $pcts; do
  printf '\e[38;2;%sm%s\e[38;2;40;170;60m%s\e[38;2;220;160;0m%s\e[38;2;180;0;0m%s\e[39m%3d%%    ' "$n" "$(u8 $((0xFEC00 + p)))" "$(u8 $((0xFEC80 + p)))" "$(u8 $((0xFED00 + p)))" "$(u8 $((0xFED80 + p)))" "$p"
done
printf '\n\n'
sleep "$secs"

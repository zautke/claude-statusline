#!/usr/bin/env bash
# drift-control.sh contract; tests/test-drift-control.ps1 runs the same cases against the pwsh twin.
set -uo pipefail

Usage() {
  printf 'Usage: %s [-h|--help]\n' "${0##*/}"
}

case "${1:-}" in
  -h|--help) Usage; exit 0 ;;
  '') ;;
  *) Usage >&2; exit 2 ;;
esac

script="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/drift-control.sh"
temp=$(mktemp -d)
trap 'rm -rf "$temp"' EXIT
state=$temp/.claude/state/drift
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# run <args…>: sets out, err, rc for the twin run with HOME=temp.
run() { out=$(HOME=$temp bash "$script" "$@" 2>"$temp/err"); rc=$?; err=$(cat "$temp/err"); }
expect() { [[ $rc -eq $1 ]] || fail "$2: rc=$rc err=$err"; }

run --help; expect 0 help
[[ $out == 'Usage: drift-control.sh'* ]] || fail 'help text'

# Negatives: PASS = exactly the declared failure.
run --get; expect 1 'no session'
[[ $err == "drift-control.sh: no --session-id given and none resolvable in $state" ]] || fail "no-session message: $err"
run -s ../x --get; expect 2 traversal
[[ $err == 'drift-control.sh: invalid session id: ../x' ]] || fail "traversal message: $err"
run -s s1 -p maybe; expect 2 'bad paused'
[[ $err == 'drift-control.sh: --set-paused must be true|false' ]] || fail "paused message: $err"
run -s s1 -r foo; expect 2 'bad provider'
[[ $err == 'drift-control.sh: --set-provider must be groq|gemini|openai|ollama|auto' ]] || fail "provider message: $err"
run --bogus; expect 2 'unknown arg'
[[ $err == 'drift-control.sh: unknown argument: --bogus'* ]] || fail "unknown-arg message: $err"
[[ ! -e $state/s1.control.json ]] || fail 'a rejected write created the control file'

# Defaults, then writes through both short and long flags.
run -s s1 --get; expect 0 defaults
jq -e '.paused==false and .force_provider==null and .updated_at==null' <<<"$out" >/dev/null || fail defaults
run -s s1 --set-paused true -r groq; expect 0 set
run --session-id s1 -g; expect 0 'get after set'
jq -e '.paused==true and .force_provider=="groq" and (.updated_at|test("Z$"))' <<<"$out" >/dev/null || fail "after set: $out"
run -s s1 --set-provider auto -p false; expect 0 reset
run -s s1 --get
jq -e '.paused==false and .force_provider==null' <<<"$out" >/dev/null || fail 'after auto'

# Session resolution (newest *.jsonl) and --recent.
printf '%s\n' '{"ts":"t0","score":1,"tag":"a","provider":"groq","extra":1}' >"$state/old.jsonl"
touch -t 202001010000 "$state/old.jsonl"
printf '%s\n' '{"ts":"t1","score":2,"tag":"b","provider":"gemini"}' '{"ts":"t2","score":3,"tag":"c","provider":"openai"}' 'not json' >"$state/new.jsonl"
run -R; expect 0 resolve
[[ $out == new ]] || fail "resolve picked: $out"
run --recent 3; expect 0 recent
[[ $out == $'{"ts":"t1","score":2,"tag":"b","provider":"gemini"}\n{"ts":"t2","score":3,"tag":"c","provider":"openai"}' ]] || fail "recent: $out"
run -n x; expect 2 'bad recent'
[[ $err == 'drift-control.sh: --recent must be a non-negative integer' ]] || fail "recent message: $err"
printf 'ok\n'

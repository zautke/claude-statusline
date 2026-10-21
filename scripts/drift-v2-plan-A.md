# Drift-Quotient v2 — Approach A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the bug-fix + cheap-wins increment of the drift-quotient (fixes silent data loss, adds tool-call signal, smooths the statusline) as a self-contained, mergeable release.

**Architecture:** Extract three pure, testable helpers into `scripts/drift-lib/` (`tool-digest.jq`, `tripwires.sh`, `ema.sh`), wire them into the existing `drift-assess-worker.sh`; rename the rubric's colliding band label and collapse the tag vocabulary to 9; convert the byte cursor to a line cursor; stamp rows with rubric version/hash; have the worker compute `score_ema` and the statusline merely display it. All changes are additive and backward-compatible (old JSONL rows lack new fields; readers fall back).

**Tech Stack:** bash, jq, awk, shasum; Claude Code hooks; PowerShell mirror for statusline. No new runtime deps.

**Plan-level decisions (refining the spec, flagged for objection):**
- D-A.1: A4 ships the **tool-call loop tripwire only**. The `intention-override` *tripwire* defers to B (false-positive risk on the always-visible statusline); the *tag* still lands in A per Decision 1.
- D-A.2: `score_ema` is computed once by the worker and stored on the row; the statusline reads `.score_ema // .score`. Single source of truth — no EMA math duplicated into the hot-path render.

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `scripts/drift-lib/tool-digest.jq` | create | Pure jq: transcript slice → one-line tool-call digest |
| `scripts/drift-lib/tripwires.sh` | create | `detect_loop()` — deterministic stuck-loop short-circuit |
| `scripts/drift-lib/ema.sh` | create | `drift_ema()` — weighted EMA over recent scores |
| `scripts/test/drift-test.sh` | create | Test runner + assertions (no bats dep) |
| `scripts/test/fixtures/*.jsonl` | create | Fixture transcripts + state files |
| `scripts/drift-rubric.md` | modify | Band rename, 9-tag vocab, 4 axes, examples |
| `scripts/drift-assess-worker.sh` | modify | Line cursor, digest wiring, tripwire Stage-0, EMA, versioning, lock 90s, ERR trap, ollama model |
| `scripts/drift-hook-entry.sh` | modify | Band-label text in report blurb |
| `statusline-command.sh` | modify | Display `.score_ema // .score` |
| `statusline-command.ps1` | modify | Mirror: display `score_ema` fallback |

---

## Task 1: Test harness + fixtures

**Files:**
- Create: `scripts/test/drift-test.sh`
- Create: `scripts/test/fixtures/transcript-loop.jsonl`
- Create: `scripts/test/fixtures/transcript-focused.jsonl`
- Create: `scripts/test/fixtures/state-3scores.jsonl`

- [ ] **Step 1: Create the assertion runner**

Create `scripts/test/drift-test.sh`:

```bash
#!/usr/bin/env bash
# drift-test.sh — unit tests for drift-lib helpers + worker behaviors.
# Run: bash scripts/test/drift-test.sh   (exit 0 = all pass)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../drift-lib"
FIX="$HERE/fixtures"
PASS=0; FAIL=0

assert_eq() { # <name> <expected> <actual>
  if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n      expected: %q\n      actual:   %q\n' "$1" "$2" "$3"; fi
}
assert_contains() { # <name> <needle> <haystack>
  if [[ "$3" == *"$2"* ]]; then PASS=$((PASS+1)); printf 'ok   %s\n' "$1"
  else FAIL=$((FAIL+1)); printf 'FAIL %s\n      missing: %q\n      in:      %q\n' "$1" "$2" "$3"; fi
}

# ---- tests appended by later tasks below this line ----

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
```

- [ ] **Step 2: Create the loop fixture (Read same file 4×, 11 tool calls)**

Create `scripts/test/fixtures/transcript-loop.jsonl`:

```jsonl
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"fix the parser"}]},"timestamp":"2026-05-28T00:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/parser.swift"}}]},"timestamp":"2026-05-28T00:00:01Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"...","is_error":false}]},"timestamp":"2026-05-28T00:00:02Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/a/parser.swift"}}]},"timestamp":"2026-05-28T00:00:03Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"...","is_error":false}]},"timestamp":"2026-05-28T00:00:04Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"/a/parser.swift"}}]},"timestamp":"2026-05-28T00:00:05Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t3","content":"...","is_error":true}]},"timestamp":"2026-05-28T00:00:06Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t4","name":"Read","input":{"file_path":"/a/parser.swift"}}]},"timestamp":"2026-05-28T00:00:07Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t4","content":"...","is_error":false}]},"timestamp":"2026-05-28T00:00:08Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t5","name":"Bash","input":{"command":"rg foo"}}]},"timestamp":"2026-05-28T00:00:09Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t5","content":"...","is_error":false}]},"timestamp":"2026-05-28T00:00:10Z"}
```

- [ ] **Step 3: Create the focused fixture (varied tools, no loop)**

Create `scripts/test/fixtures/transcript-focused.jsonl`:

```jsonl
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"add a flag"}]},"timestamp":"2026-05-28T00:00:00Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/a/main.swift"}}]},"timestamp":"2026-05-28T00:00:01Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"...","is_error":false}]},"timestamp":"2026-05-28T00:00:02Z"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/a/main.swift"}}]},"timestamp":"2026-05-28T00:00:03Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"...","is_error":false}]},"timestamp":"2026-05-28T00:00:04Z"}
```

- [ ] **Step 4: Create the 3-score state fixture (for EMA)**

Create `scripts/test/fixtures/state-3scores.jsonl`:

```jsonl
{"ts":"2026-05-28T00:00:00Z","session_id":"fix","kind":"baseline","goal":"x","ordinal":1}
{"ts":"2026-05-28T00:01:00Z","session_id":"fix","kind":"score","score":40,"tag":"stuck-loop","cursor":4}
{"ts":"2026-05-28T00:02:00Z","session_id":"fix","kind":"score","score":80,"tag":"productive-research","cursor":9}
{"ts":"2026-05-28T00:03:00Z","session_id":"fix","kind":"score","score":90,"tag":"focused-implementation","cursor":14}
```

- [ ] **Step 5: Run the (empty) harness to verify it executes**

Run: `bash scripts/test/drift-test.sh`
Expected: prints `0 passed, 0 failed` and exits 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/test/drift-test.sh scripts/test/fixtures/
git commit -m "test(drift): test harness + transcript/state fixtures for v2 Approach A"
```

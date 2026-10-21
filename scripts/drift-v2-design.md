# Drift-Quotient v2 — Design Spec

**Date:** 2026-05-28
**Status:** APPROVED — 3 forks ruled (§6); ready for implementation plan
**Scope:** Approach A (bug-fix + cheap wins, ~1 day) → merge → Approach B (architectural v2 incl. MCP server, ~1.5–2.5 wk)
**Deferred:** Approach C (local Siamese SLM) — not in this spec; revisit at ≥500 labeled turns
**Author:** pairing session, research synthesized from 4 parallel agents (SOTA / libraries / GitHub / self-introspection)

---

## 1. Context

The drift-quotient is a working Claude Code instrument: a `Stop` hook fires an async worker
(`drift-assess-worker.sh`) that reads the session transcript, sends recent activity to a cloud-LLM
judge chain (Groq → Gemini → OpenAI → Ollama), and persists `{score 1-100, tag, reason}` per turn to
`state/drift/<sid>.jsonl`. A 10-cell inverted statusline bar shows the latest score; a `UserPromptSubmit`
hook injects a drift report into the next turn as a `<system-reminder>`.

Self-introspection over 6 sessions / 20 scored turns surfaced concrete defects (full detail in the
research synthesis). The load-bearing facts driving this design:

- **Cost is a non-constraint** — $0.0021 total across 20 scores (~$0.0001/score). We are free to spend
  more compute on quality; we are *not* free to spend latency or add noise.
- **Volatility ≫ signal** — mean abs consecutive Δ = 15.1, max single-turn swing = 44. A 1-point bar
  change is currently meaningless inside ±15 of noise.
- **The judge's best signal is buried** — when a tool-call loop survives the 600-char truncation the
  judge *does* catch it (reason: "repeatedly encountering Cloudflare WAF blocks"). It just usually
  doesn't survive truncation.
- **No closed loop** — the injected report is decoration; observed score recoveries (38→82) came from
  new user prompts, not agent self-correction.

## 2. Goals / Non-goals

**Goals**
- G1. Eliminate measured silent data loss (cursor truncation, vocabulary leak).
- G2. Raise signal-to-noise: smoothing + deterministic pre-pass + derived tool-call features.
- G3. Close the loop: drift signal should *change agent behavior*, not just paint a bar.
- G4. Make judge output auditable across time (versioned rubric + judge stamp per row).
- G5. Keep the hot path async and the statusline render cheap (<30 ms).

**Non-goals**
- N1. No local model weights on `largo` (hard rule). Any model is cloud-hosted.
- N2. No migration to a SaaS eval platform (LangSmith/Braintrust/etc.) — mine ideas only.
- N3. No synchronous judge in `UserPromptSubmit` (keep it injection-only).
- N4. Approach C (Siamese encoder) is explicitly out of scope here.

## 3. Approach A — Stop the bleeding + cheap wins (~1 day, merges independently)

Each item is decoupled and independently testable. File refs are hints; re-verify line numbers at
implementation time.

### A1. Fix rubric vocabulary leak  *(severity L, effort XS)*
`drift-rubric.md` uses `mild-drift` as the 50–69 **band** label, and the judge has emitted it as a
**tag** (regex `^[a-z][a-z0-9-]{1,30}$` accepted it). Rename the band label → `partial-focus` so the
band name can never collide with the controlled tag vocabulary. Apply the 9-tag vocabulary
(Decision 1, §6) in the same rubric edit, and extend the output schema to emit the 4 axes (Decision 2).

### A2. JSONL line cursor, not raw byte cursor  *(M / S)*
Worker reads `tail -c +$((cursor+1))` — a byte offset that slices the first JSONL record mid-line, and
`fromjson?` silently drops the broken record. Every non-first assessment loses its leading event.
**Fix:** persist the last-seen transcript **line count** (or last `parentUuid`); resume with
`tail -n +$((line+1))`. The state-file `cursor` field is reinterpreted as a line index — no schema change.

### A3. Derived tool-call digest in the prompt  *(L / S)* — highest-impact A item
Before sending `NEW_ACTIVITY`, compute a compact digest with jq and prepend it:
```
TOOL_DIGEST: Read×7 (4× same file: foo.swift), Edit×1, Bash×3 (rg, rg, sed),
             distinct_files=3, errors_in_window=2, read_write_ratio=7:1
```
The judge stops re-deriving loops from 6 KB of JSON envelope and sees the structural signal directly.
RLE-compress the raw event list too (`[Bash×4, Read]` not four `Bash` lines) to reclaim truncation budget.

### A4. Deterministic tripwires (short-circuit the judge)  *(L / S)*
A Stage-0 pre-pass that can emit a verdict **without** a cloud call:
- **Tool-call loop:** SHA-256 of `(tool_name, canonicalized_sorted_args)`; rolling window of 20; any
  hash ≥3× in last 10 → force `stuck-loop`, score 30, skip judge.
- **Intention-override:** user turn contains negation/refusal (`don't|stop|no, instead|undo`) AND next
  assistant turn continues the prior path → force `intention-override` (NEW critical tag), score 20.
These are free, deterministic, and catch the two most damaging classes the LLM currently mis-rates.

### A5. EMA smoothing for the statusline  *(M / S)*
Statusline shows raw `last` score → ±44 swings. Render an exponential moving average
`s' = 0.5·now + 0.3·prev + 0.2·prev2` from the last 3 score rows. **Raw score still written to JSONL**
(traces stay truthful); only the *display* is smoothed. Add `score_ema` to the row for reproducibility.

### A6. Ollama reasoning-model starvation  *(M / XS)*
`gpt-oss:20b-cloud` ignored `think:false`, spent the whole `num_predict:512` on hidden CoT, returned
empty content. Switch the Ollama default to a non-reasoning model (`qwen2.5-coder:32b-cloud` or
equivalent `:cloud` tag) **or** raise `num_predict` to 1024 with a hard `think:false`. Verify against a
live tunnel call before merge.

### A7. Lock + robustness hardening  *(S / XS)*
- `mkdir`-lock stale guard 30 s → 90 s (Gemini legitimately lands at 7 s+; avoid double-scoring).
- Add `set -E` + `ERR trap` → convert silent mid-pipeline `jq` failures into one structured
  `emit_error` row instead of an empty `PRIOR_CURSOR=0` fallback.

### A8. Versioned, auditable rows  *(G4; M / S)*
Stamp every `score` row with `rubric_version`, `rubric_sha256`, and `judge_model` (judge_model already
present). Lets us detect *judge drift* (model bump shifts the mean) separately from *agent drift*.
Bump `rubric_version` whenever `drift-rubric.md` changes.

**A exit criteria:** all gates exercised by a fixture; one live judge call per provider; statusline
renders smoothed value; no raw-byte-cursor path remains; `git diff` scoped to drift files.

## 4. Approach B — Architectural v2 (~1–2 wk, builds on A)

### B1. Two-track scoring (deterministic features → judge)
Formalize A3+A4 into a pipeline: **Stage-0** deterministic detectors always run and (a) may
short-circuit, (b) otherwise pass their features into **Stage-1** (the LLM judge). The judge prompt
gains a `DETERMINISTIC_SIGNALS:` block. This is the field's 2026 consensus (LangSmith `agentevals`
two-track; FutureAGI best-practices): cheap rules first, LLM only for nuance.

### B2. Per-project rolling baselines (deviation, not absolute)
Maintain `state/drift/baselines.json`: a 7-day EMA of score keyed by **project root** (cwd of the
session). Statusline color anchors to **Δ from this project's baseline**, with a `↑/↓` arrow at ±2σ.
Rationale (Stack Pulsar 2026): a 55 in a normally-80 project is the real signal; a 55 in a normally-50
project is noise. Absolute score still shown; baseline reframes it.

### B3. Closed feedback loop (G3) — the highest-value B item
When the latest tag is negative, the `UserPromptSubmit` injection appends a **tag-specific corrective**,
not the current generic blurb. Templates (editable, in a new `drift-correctives.md`):
- `stuck-loop` → "You've run {sig} {n}× with no new result. Stop. State your current hypothesis and
  either change approach or ask the user to disambiguate."
- `scope-creep` → "Current work is drifting from goal #{g}: '{goal}'. Confirm this detour is intended
  or return to the stated task."
- `context-rot` → "You may have lost an earlier decision/constraint. Re-read the original goal before
  proceeding."
- `hallucination` → "Verify {artifact} exists before relying on it — do not assert unverified facts."
- `intention-override` → "The user redirected ('{user_phrase}') but the prior path continued. Stop and
  honor that correction before any further action."
Push-based, free, zero added latency. Pull-based companion is now a first-class deliverable (B6).

### B4. Mid-flight `PostToolUse` sampling (catch runaways before `Stop`)
Today a 200-tool runaway is only scored after it finishes. Add a `PostToolUse` hook firing every
N=8 tool calls that runs **Stage-0 only** (deterministic, zero-LLM) over the sliding window; if a
tripwire fires, inject an immediate corrective. The `Stop`-hook judge remains the ground-truth pass.
Zero added LLM cost; bounded latency (deterministic jq only).

### B5. Richer record schema (Decision 2)
Extend the `score` row with `axes: {efficiency, grounding, robustness, capability}` (each 1–100). The
rubric (A1 edit) emits them; the worker validates and persists them. **Statusline stays single-number**
(smoothed headline only) — the axes are for history/analysis and the future Approach-C training set.
Old readers ignore the new field (backward-compatible).

### B6. MCP self-introspection server (Decision 3 — build now)
A small MCP server exposing read-only tools the *agent* calls mid-turn (hooks can't call MCP, issue
#26112, so this is agent-invoked, not hook-invoked):
- `read_my_drift_history(session_id?, n=10)` → recent `score` rows (score, tag, reason, axes) from
  `state/drift/<sid>.jsonl`.
- `read_my_recent_tool_loops(session_id?, window=20)` → the Stage-0 loop detector's current view
  (repeated tool-call signatures, read/write ratio, error rate) so the agent can self-check on demand.
- `read_my_drift_baseline(project?)` → this project's rolling baseline + current Δ (from B2).

**Implementation constraints:**
- Python server in a **local, machine-specific venv `.venv-drift/`** (already gitignored), bootstrapped
  on first run by `install.sh` — keeps the repo portable, no committed binaries (honors largo disk rule:
  venv is local, never committed, never a model weight).
- Registered via the user's MCP config (`.mcp.json` / settings) referencing
  `~/.claude/.venv-drift/bin/python ~/.claude/scripts/drift-mcp-server.py` (SSoT path).
- Read-only: the server NEVER writes drift state — hooks remain the sole writers (single-writer
  invariant preserved). It only reads the JSONL the worker produces.
- Reuse `anthropic-skills:mcp-builder` skill during implementation for a correct stdio MCP scaffold.

**B exit criteria:** baseline file populated across ≥2 projects; a forced `stuck-loop` produces the
specific corrective in the next injection; PostToolUse sampler fires on a synthetic 8-call loop fixture;
MCP server starts under `.venv-drift/`, all 3 tools return valid JSON against a fixture state file, and
is read-only (no writes to `state/`); no regression in A's gates; statusline still <30 ms.

## 5. Sequencing & decoupling

```
A (bug fixes) ──merge──▶ B1/B2/B4/B5 (pipeline, baselines, sampler, schema) ──▶ B3 correctives ──▶ B6 MCP server
```
A is shippable alone and de-risks B (its tripwires + digest are B's Stage-0). Each B item is independently
mergeable; B6 (MCP) depends only on the JSONL schema (B5) being stable. Nothing here blocks on Approach C.

## 6. Resolved decisions (ruled 2026-05-28)

**Decision 1 — Tag taxonomy → 9 tags.** Keep `hallucination` and `unclear`; drop `useful-tangent`;
merge `redundant-loop`+`debug-spiral` → `stuck-loop`; add `intention-override`. Final vocabulary
(the ONLY strings the validator accepts; band labels live in a separate namespace per A1):

| # | tag | meaning |
|---|---|---|
| 1 | `focused-implementation` | on-spec coding/editing toward the goal |
| 2 | `productive-research` | reading/searching that informs the goal |
| 3 | `context-rot` | lost an earlier decision or constraint |
| 4 | `scope-creep` | expanding beyond the stated goal |
| 5 | `hallucination` | inventing files/APIs/facts (keep — critical even if rare) |
| 6 | `stuck-loop` | non-converging repetition (merged redundant-loop + debug-spiral) |
| 7 | `baseline-recovery` | refocusing after a drift |
| 8 | `unclear` | insufficient signal — explicit abstention (keep — SOTA-endorsed) |
| 9 | `intention-override` | user redirected; prior path continued anyway (forced by A4 tripwire) |

**Decision 2 — One headline score + 4 hidden sub-scores.** The 10-cell statusline bar shows ONE
number (smoothed per A5). The JSONL `score` row additionally carries `axes: {efficiency, grounding,
robustness, capability}` (1–100 each) for history/analysis only. Statusline render is unchanged in
shape. The judge rubric is extended to emit the four axes alongside the headline.

**Decision 3 — Build the MCP self-introspection server now (B6).** Pull-based tools are in scope this
cycle (not deferred). Because hooks cannot call MCP (issue #26112), the *agent* calls these during its
turn; the *hooks* keep writing state as today. See B6.

## 7. Verification (per CLAUDE.md surface table)

- **Scripts:** `bash -n` all; `shellcheck` best-effort; fixture transcript exercising each gate/tripwire;
  one live call per provider; a forced-loop fixture proving short-circuit + corrective injection.
- **Statusline:** pipe sample JSON + matching state file into `statusline-command.sh` and `.ps1`, confirm
  smoothed render + baseline arrow parity.
- **Data:** confirm new schema rows are backward-compatible (old readers ignore new fields); baseline file
  round-trips.
- **MCP (B6):** server boots under `.venv-drift/`; all 3 tools return valid JSON against a fixture state
  file; verified read-only (no writes to `state/`); `install.sh` bootstraps the venv idempotently.
- **No regression:** existing `PreToolUse` rtk hook + `SessionStart` agent-evaluator hook still fire; rest
  of statusline (model/ctx/disk/rate-limits) unchanged.

## 8. Risks

- Statusline does `tail | jq` per render; B2 adds a baseline read. If sluggish, cache to a 1 s-fresh temp
  file (deferred to v2.1).
- Correctives could become nagging if mis-tagged → keep templates terse, gate on tag confidence once
  Decision 2's sub-scores exist.
- B6 MCP server is agent-invoked, so it only helps if the agent actually calls it. Mitigate by mentioning
  the tools in the push-based corrective text (e.g. "call `read_my_recent_tool_loops` to see the loop").
- `settings.json` is live-rewritten by Claude Code (observed this session) → adding the `PostToolUse` hook
  may reorder the file; that's cosmetic churn, not a regression.

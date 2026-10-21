# Drift Control Menu — in-conversation slash command

**Status:** shipped + verified 2026-05-29 · **Owner:** drift-quotient subsystem
**Command:** `/drift-control` (user-fired) · **Backend:** `scripts/drift-control.sh`

## What it is

An interactive, **same-screen** control panel for the drift-quotient assessor. Typing
`/drift-control` renders a native keyboard-selectable menu **inside the Claude Code conversation**
(no external Terminal window, no tmux popup). Menu actions: force assessor provider, pause/resume
assessment, view recent scores, edit the rubric. Choices are written to the per-session
`control.json` consumed by the assessor worker.

## Why this design (research verdict, 6 parallel agents, 2026-05-28)

- **In-band terminal overlay = impossible.** An external process cannot draw into Claude Code's
  render loop (single TTY, CC owns the alt-screen + input). tput/ANSI ruled out.
- **OSC 8 click = external window only**, broken inside tmux (CC #27047). Kept as a *secondary*
  non-tmux trigger; not the primary path.
- **WINNER — native, same-screen, zero new servers:** a custom slash command uses `!` **dynamic
  context injection** to inline live state, then instructs the model to call the native
  **`AskUserQuestion`** tool, which renders the inline selectable menu. Selection runs
  `drift-control.sh` to write `control.json`.

## Mechanism (flow)

1. User types `/drift-control`. The **UserPromptSubmit drift-hook fires first**, writing THIS
   session's `*.jsonl` (making it newest by mtime).
2. The command's two `` !`…` `` blocks run in the preprocessor:
   - `drift-control.sh --get` → injects current `{paused, force_provider}`.
   - `sid=$(drift-control.sh -R); tail -n10 .../$sid.jsonl | jq …` → injects recent scores.
3. The body instructs the model to call `AskUserQuestion` (header `Drift`) with 4 options.
4. On selection the model runs the matching `drift-control.sh` write, then re-runs `--get` to
   confirm. Provider submenu offers groq/gemini/openai/ollama; `auto`/clear via the auto-appended
   "Other".

## Files

| File | Role |
|------|------|
| `~/.claude/commands/drift-control.md` | the slash command (menu definition) — **new** |
| `~/.claude/scripts/drift-control.sh` | read/write backend (atomic control.json) — reused + hardened |
| `~/.claude/scripts/drift-rubric.md` | rubric, edited in-conversation via Read+Edit |
| `~/.claude/state/drift/<sid>.control.json` | per-session control file (gitignored) |

`control.json` schema: `{ paused:bool, force_provider:groq|gemini|openai|ollama|null, updated_at:ISO8601 }`

## Verification (2026-05-29) — 100% of self-testable surface

**Backend battery (5 runs + edge cases), all PASS:**

| Run / case | Result |
|------------|--------|
| R1 force provider — groq/gemini/openai/ollama each set; `auto`→null clears | PASS |
| R2 pause → `paused:true` | PASS |
| R3 resume → `paused:false` | PASS |
| R4 view-history `!`-block — live session (10 lines); missing jsonl → empty, no error | PASS |
| R5 edit-rubric Read target readable (64 lines) | PASS |
| invalid provider / invalid paused / unknown arg → exit 2 | PASS |
| corrupt json / empty json → defaults | PASS |
| combined `--set-paused --set-provider` in one call | PASS |
| `updated_at` ISO8601; atomic temp+mv (no leftover) | PASS |
| `--help` / no-action → Usage, exit 0; `-R` newest jsonl; short flags `-p/-r/-g` | PASS |

> Note: in the first harness run, `--help`, no-action, and history-missing showed FAIL — all three
> were **harness artifacts** (CC shell-snapshot `ZSH_VERSION` unbound under `set -u`; and `pipefail`
> catching `tail`'s exit). Re-tested clean: all three behave correctly.

**Independent audit (2 subagents) → 3 real findings remediated:**

| Finding | Severity | Fix | Verified |
|---------|----------|-----|----------|
| session-id path traversal (`-s ../../x` escapes STATE_DIR) | HIGH | reject ids not matching `^[A-Za-z0-9._-]+$` or containing `/`/`..` → exit 2 | PASS (4 cases, no escape-write) |
| missing `jq` → silent empty write | MED | guard at top: `command -v jq || exit 1` | PASS (faithful no-jq sandbox → exit 1) |
| `allowed-tools` tilde-only match fragile if model emits `$HOME` path | MED | added `Bash($HOME/.claude/scripts/drift-control.sh:*)` clause | PASS (grep confirms) |

**Findings investigated and NOT changed (with evidence):**

- *Session mis-targeting (newest-jsonl)* — downgraded to safe. `CLAUDE_SESSION_ID` is **unset** in
  the command env (verified), so explicit-id passing is unavailable. But the UserPromptSubmit
  drift-hook writes the current session's jsonl **before** the command runs, so `-R` resolves
  correctly at invocation time. Subagent traces live in `state/drift/traces/`, not top-level
  `*.jsonl`, so they don't interfere.
- *LOW items* (empty `-p ''` silent no-op, trailing-flag `shift` stderr, concurrent lost-update,
  tmp leftover on write failure) — left as YAGNI for a single-user local tool.

**Dependency confirmed:** `CLAUDE_CODE_ENABLE_ASK_USER_QUESTION_TOOL=true` — the menu can render.

## Coverage boundary (the one manual step)

Everything the command depends on is verified by script. The **only** piece not self-executable is
the live `AskUserQuestion` *render* (requires the user to type `/drift-control` and pick an option).
Live-test: run `/drift-control` → pick **Pause** → re-run → `--get` shows `paused:true`; pick
**Resume** → back to `false`; **Force provider → groq** → `force_provider:"groq"`; "Other"→`auto`
clears to `null`.

## Secondary (kept, not the focus)

OSC 8 statusline link + `drift-menu-open.command` (1-window) + Textual `drift-menu.py` + tmux
`prefix D` popup remain as non-tmux / external-window fallbacks.

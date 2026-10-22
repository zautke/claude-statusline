# INSTRUCTIONAL INSIGHTS (append-only)

## 2026-10-15

- Stateless re-render makes resize fitting trivial: no snapshot or delta is needed when every render recomputes from live width and live values. Reach for "measure after each step" before designing a delta model.
- Test the real environment, not the shell you happen to have: the statusline runs under whatever `bash` Claude Code finds, and CI runs macOS `/bin/bash` 3.2. Add a `TEST_BASH` knob and run the suite under both.
- A review bot will produce findings forever. Triage, batch, cap rounds. Protocol now in memory and kb.
- Hosted review subagents need a hard deadline enforced by the caller; a prompt-level time box was ignored twice. Stop at the box and fall back to inline review plus a synchronous external model.
- Read the release protocol before the merge, not after the question. The cost of skipping it was two extra PRs, two tags, and a changelog done twice.

## 2026-10-16

- When a protocol collides with an external mandate (marketplace version format), the mandate wins; record the override in the protocol itself so the next agent does not re-derive it.
- Verify "bot says X is unsupported" with the actual binary before fixing (here it was real: `declare -A` on Bash 3.2), and keep the reproduction command in the commit message.

## 2026-10-21

- The two insights above (read the release protocol first; when an external mandate wins) were on file and still went unread at the onset of the next session. Load this file and PLANS "Current facts" before planning, not after a reviewer catches it.
- Twins (`.sh` / `.ps1`) need twin tests. The pwsh renderer silently ignored four config features until a PowerShell test suite existed.
- Turn a named algorithm into a map test: per-step effect plus engagement order at threshold widths. Then mutation-check the suite (swap two steps; the suite must fail).

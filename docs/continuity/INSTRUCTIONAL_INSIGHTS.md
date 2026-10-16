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

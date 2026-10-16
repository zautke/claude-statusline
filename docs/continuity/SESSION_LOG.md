# SESSION LOG (newest first)

## 2026-10-16 — release remediation and protocol addendum

- User asked whether the global release protocol was followed. It was not: no tag, no source-repo bump, direct PR into the publish mirror, hand-written CHANGELOG. Reported honestly.
- User corrected the protocol: `main`/`development` carry no branch suffix; externally mandated version formats (plugins) override the org policy with plain SemVer and no `v` prefix. Addendum written to kb (`protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main`) and memory (`release-protocol-addendum.md`).
- Remediation: braisenly-plugins tagged `braisenly-statusline@1.1.0` at 3e52d52. braisenly-statusline bumped to 1.1.0 with CHANGELOG via PR #6 (release/1.1.0 → development) and PR #7 (development → main), tagged at 871c996. Package test now accepts any SemVer version (it asserted the literal 1.0.0).
- Case study note in kb appended with the deviation.

## 2026-10-16 — Bash 3.2 fix

- Codex finding on braisenly-plugins PR #5: `declare -A` breaks on macOS /bin/bash 3.2. Reproduced. Fixed: flag string for ladder, UTF-8 decoding from bytes under function-local LC_ALL=C, LC_ALL pinned at startup, SGR strip loop guarded. Verified under /bin/bash and bash 5 with UTF-8, no locale, and LC_ALL=C. PR #4 → development → main (PR #5 in the statusline repo). Synced into braisenly-plugins PR #5 (328d7c0), CI green on ubuntu/macOS/Windows, merged 3e52d52.
- Two pairs of Opus review subagents overran their time box without reporting and were stopped; review done inline plus one Gemini pass. Cloud Ollama co-agents unreachable.

## 2026-10-15 — review loop and protocol change

- PR #2 went through 15 Codex passes, 25 findings fixed (P1s: PowerShell `$Pid` collision, settings path, native width fallback; many P2 edge cases). PR #3 promotion had 5 more passes.
- User: "no more infinite circles with the review bot." New protocol saved to memory (`review-protocol.md`) and kb: bot findings triaged by me + two Opus reviewers; my work reviewed by two Opus reviewers; max 3 fix rounds then pause and justify.
- Measurements commented on anthropics/claude-code#76988.

## 2026-10-15 — build

- Research: COLUMNS env is the only reliable width channel inside the statusline script; /dev/tty and tput fail. Resize is not a re-render trigger. kb research note written.
- Built: COLUMNS fit, bar shrink/drop, drift removed, heat-colored percentages, resize watcher (opt-in, hardened), live pty width, 16-step ladder, atom builders, two-row stacked layout (default 1 row), fork-free fit loop (2.9 s → 0.47 s).
- Resize latency measured live by resizing the session pty: 0.42 s to watcher write, 1.65 s Claude Code settings reload.
- Pre-hardening watcher once bumped the live settings.json; restored, verified identical to pre-session backup.

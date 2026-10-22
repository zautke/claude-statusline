# SESSION LOG (newest first)

## 2026-10-21 — release 2.0.0, host switch, install command (session 876dc8f2, adagio)

- Plain SemVer restored before review. The release is 2.0.0 (breaking: plugin id, marketplace, env prefix); the CHANGELOG has a 2.0.0 entry.
- Codex on #10/#11: one critical finding, the drift hook not wired. The user deferred it (kb backlog). Every other finding got a reply.
- A Windows CI flake (free disk moved mid-test) was fixed by masking the disk number in ladder comparisons.
- #10 → `development`, #11 → `main` `482cb3d`, tag `claude-statusline@2.0.0`.
- Both hosts moved from `#feat/coalesce-plugin-copies` to `main`, with `autoUpdate`.
- Stale `~/braisenly-statusline` clones deleted on both hosts. That broke `claude-profile` sessions, whose settings symlink to the dot-agents SSoT, which still ran the clone. Restored with a shim, then fixed in dot-agents #26/#28.
- dot-agents `/install-claude-statusline` added; live `claude -p` 5/5 PASS on both hosts.

## 2026-10-20 — coalesce, rename, adagio verification (session 876dc8f2, adagio)

- RCA: braisenly-plugins had a hand port that bypassed `profile-publish`, and the session ran a stale clone hard-wired in the dot-agents settings SSoT. A plugin cannot set `statusLine`.
- This repo became the only source and its own marketplace. The plugin is renamed `claude-statusline` (repo renamed) and ships for Claude Code only.
- Stable launcher, `/drift-control` import with a `.ps1` twin, `config/` SSoT.
- Live testing on adagio. The first windows were not field-faithful (inherited `NO_COLOR`, stable Windows Terminal) and that evidence was thrown away. A field window opened in the user's Windows Terminal Preview profile found the fit-margin defect: Claude Code's area is `COLUMNS-4`.
- The user asked for a pwsh twin of the renderer test and real coverage of the ladder. Result: `test-statusline.ps1`, a ladder map test (16 per-step effects, plus progressive order) in both twins, mutation-checked, and pwsh renderer parity (segments, labels, widths, `NO_COLOR`, validation).
- Versioning: the session first applied the org 4-part stamp, which the 2026-10-16 addendum forbids for plugins. Reverted to SemVer before review; release is 2.0.0 (breaking), tag `claude-statusline@2.0.0`.
- kb: session summary, run ledger, retrospective and an experiential report under `projects/claude-statusline/` and `reference/agent-insights/`.

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

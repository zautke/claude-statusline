# SESSION LOG (newest first)

## 2026-11-24 — repo triage: resize-wait fix found upstream, PR #15 rebased, PR #17 CI red (largo)

- anthropics/claude-code#76988 (resize re-run request; the `resize-watch` sidecar and `fit.resize_watch` exist because of it) was closed as completed 2026-11-20: **fixed in Claude Code 2.1.326** (2026-11-16 changelog, "Fixed a custom status line keeping its old width … after a terminal resize", anthropics/claude-code#107291). Verified against the live changelog and npm (`@anthropic-ai/claude-code` latest 2.1.332; local CLI is 2.1.326). The ~2 s resize-watch settle is removable; user chose report-only for now.
- `docs/continuity-2026-11-09` rebased onto `development` `e811a8d` (2.3.1); stale release facts refreshed (main still 2.0.0; tags stop at 2.0.0).
- PR #15 (this branch): draft, CI green, 0 reviews. PR #17 (`feat/radial-indicators`): draft, **CI red** since 2026-11-17 (ubuntu/plugin/pwsh fail in ~2 s; macos cancelled at 15 min); logs expired; branch tip `c4cb2cb` duplicates the token-count fix already merged via #20 and will drop out on rebase.
- Open PRs: #15, #17. Recently merged: #16, #18, #19, #20.
- Note: web search returned HTTP 402 this session; research used Context7, the live changelog and GitHub search instead.

## 2026-11-14 evening → 2026-11-15 — live trial, cell-fitted ring, gradient tried and rejected (session a8831aae, largo)

- Remote-session analysis (ssh from iTerm2 into adagio) written to kb; experiments S-001…S-004 proposed.
- L-001: ring wired into the bash renderer (`style: ring`, `ring.grey`) and the user's status line pointed at the worktree; backups `~/.claude/*.bak-pre-ring-2026-11-14`.
- User feedback: blurry, 1 px misfit, 95 % and 82 % alike, want it bigger, exclusion ladder broken. E-008: the misfit was a wrong cell-width assumption (600 vs 545.5 for Victor Mono); font refitted (Lab5), ring enlarged, notches added, ladder walks with rings kept, command path routed through a `claude-statusline` symlink so the resize watcher runs. Commit `e96960b`.
- E-009: continuous hue along the arc by dithered four-cell tiling. Technically confirmed (`8fec0e3`), rejected by the user on sight; renderer reverted to the solid-colour ring (`f6bc23f`), which the user approved.
- A built-in safety check blocked one verification command (suspected hidden removal; none intended); the checks were rerun as separate commands.
- largo disk fell to 0.5–2 GiB free during the session; one test run failed once on live "disk free" text and passed on rerun.

## 2026-11-14 — radial indicators: spike closed, laboratory loop E-001…E-005 (session a8831aae, largo)

- User restarted iTerm2. Rings rendered there and inside a throwaway Claude Code 2.1.325 status line. Design doc updated (`1b46716`), implementation plan written (`756a397`); user was asked to choose an execution method and did not; the plan is now stale.
- New requirement from the user: a full-circle neutral "empty" track behind the coloured arc, 10–15 % lighter or darker than the terminal background. User asked for a kb laboratory ledger with a transcript of the foreground approach and a propose-log-observe-log loop; wider goal is an agentic configuration skill for the public release.
- Ledger created in kb: `projects/claude-statusline/laboratory/claude-statusline-radial-indicators-laboratory-ledger-append-only`.
- E-001 colour font (COLR + CPAL): REFUTED. iTerm2 keeps alpha, discards palette colours; the track became the arc hue at 35 % opacity. Also showed that a new font loads in the running iTerm2.
- E-002 two-cell overprint: PARTIAL. Cross-cell overflow works both ways; draw order between overlapping glyphs is undefined (track covered the arc at 25, 99, 100 %).
- E-003 tiled remainder + arc: CONFIRMED. First run was a procedure fault (codepoints printed < 1 s after install → boxes).
- E-004 the same inside the Claude Code status line: CONFIRMED.
- User asked whether the iTerm2 Python API can drive themes autonomously (yes: `EnableAPIServer = 1`, automation auth disabled) and proposed a plain-grey track from a contrast-ratio formula. User delegated the neutral choice to the agent.
- E-005 grey track by WCAG ratio on six themes through the iTerm2 API: CONFIRMED. Default ratio 1.75 chosen.
- Lab code and evidence pushed: `43ba911`, `e56988c` on `feat/radial-indicators`.
- Cleanup: all test windows closed, throwaway Claude processes stopped (one needed a second `pkill` pattern), Terminal.app quit. Four ring fonts left installed on purpose.
- Later the same day: teaching retrospective written to kb; Windows Terminal desk analysis and experiments W-001…W-004 logged; E-007 (combining-mark overlay, from a user question) logged as a proposal; half-glyph fonts Lab4a/b/c built and committed with Lab3 under `lab/radial/fonts/`; standing handoff order for adagio placed at the top of `CURRENT_TASK_STATE.md`.

## 2026-11-13 — radial indicators: research, design, spike (session a8831aae, largo)

- User asked whether the heat-map bars could be radial rings in 3.6° steps with continuous hue. Research (web, GitHub, Context7 lookup, current to 2026-11-13): no stock glyph set is finer than 8 steps (`○◔◑◕●`, Nerd Font `nf-md-circle_slice_1..8` U+F0A9E–F0AA5, filled pies). Claude Code drops image escapes from status line stdout (anthropics/claude-code#101955, #39024 open).
- User's terminals: iTerm2 and Windows Terminal. Neither draws kitty placeholder images, leaving a custom font as the one route. User approved the short design.
- Repo indexed in codemunch as `zautke/claude-statusline`. Touch points: `bar()` `scripts/statusline-command.sh:152`, `heat_rgb` `:147`, `Get-Bar` / `Get-FitBar` `scripts/statusline-command.ps1:257` / `:285`.
- Worktree `~/claude-statusline-wt/radial`, branch `feat/radial-indicators` off `development` `d78076e`; design doc committed and pushed; draft PR #17.
- Spike: 101-glyph font built with fontTools (29 KB), installed to `~/Library/Fonts`. Terminal.app (fresh process) drew the rings. iTerm2 drew SF Symbols at U+100000, then `[?]` boxes at U+FFF00; a stale font list in the long-running iTerm2 is suspected. Stopped for the user to restart iTerm2. Windows Terminal not tested (no PowerShell tool in the session).
- Cleanup: test iTerm2 windows closed, Terminal.app quit. Spike font left installed on purpose.

## 2026-11-09 — in-flight search, public-release teams (session a5493e17, largo)

- User reported in-flight public-release work lost to a machine crash. Searched: local and remote branches, worktrees and stashes on both hosts (adagio old clone `C:\Users\me\dev\braisenly-statusline`, marketplace clones), all 14 PRs, GitHub events/releases, kb, prompt history on both hosts, every Claude Code transcript (user messages, subagents included), Codex sessions on both hosts. Nothing found. adagio rebooted 2026-11-07 22:12; largo up 4 days; the 11-09 12:05 "machine crash" was sessions dying, not a reboot.
- README at that point: last changed 2026-10-20 (`e39a69a`); install, configure, checks only. Repo PRIVATE, MIT licence, no topics or homepage.
- User asked for an opus/sonnet team to write a professional README for every case and feature, with an animated terminal recording of the width shrinking through the exclusion ladder, installs for PowerShell/macOS/Linux, configuration, demos; and an opus team to simplify the codebase. "README asap and live."
- Spawned readme-writer (opus), demo-builder (sonnet), simplifier (opus) in two worktrees (`~/claude-statusline-wt/readme`, `~/claude-statusline-wt/simplify`). Push monitor armed.
- User asked for continuity for exact pickup after handoff and for plans and session facts to be copied to kb. User stopped the three agents (no output). Continuity moved from a side worktree into the main checkout on `docs/continuity-2026-11-09`; `HANDOFF-public-release.md` holds the verbatim request and briefs.

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

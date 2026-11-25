# TASKS

## Done (2026-10-15 → 2026-10-16)

- [x] Research terminal width detection in bash and PowerShell (kb note written)
- [x] COLUMNS-aware fit, uniform bar shrink with floor, drop, right-pad slack
- [x] Remove drift segment (legacy configs listing `drift` stay valid)
- [x] Percentages always carry bar heat color
- [x] 16-step exclusion ladder, `fit.ladder` override, atoms per segment
- [x] Two-row stacked layout (`fit.rows: 2`), bars kept through the ladder, U+2800 leading pad
- [x] Resize watcher (`fit.resize_watch`), hardened settings write, opt-in; Windows port via AttachConsole (untested on a desktop)
- [x] Live pty width in the renderer; watcher at 100 ms poll / 200 ms settle
- [x] Codex findings triaged and fixed across PR #2, #3, #4 (25+ findings)
- [x] Bash 3.2 compatibility (flag string, UTF-8 byte decoding, LC_ALL pinned)
- [x] Port into zautke/braisenly-plugins (PR #5), CI green on 3 OSes
- [x] Release 1.1.0: versions, CHANGELOGs, tags in both repos
- [x] Comment measurements on anthropics/claude-code#76988
- [x] Memory + kb: review protocol (3-round cap, two Opus reviewers) and release addendum

## Open

- [x] Verify what the next dot-agents → braisenly-plugins publish does to the vendored `braisenly-statusline/` directory. Resolved 2026-10-20: the copy was removed from both repos and `EXTRACTED_PLUGINS` makes `profile-validate` refuse a re-add.
- [x] Windows resize watcher (`resize-watch.ps1`) on a live desktop session. Verified 2026-10-20 in a field window (kb run ledger, E07/E08).
- [ ] Optional: branch name on row 2 under cwd when stacked.
- [ ] Optional: strip `thresholds`/`colors` from existing user configs when the skill next touches them.
- [ ] largo disk: 5.7 GiB free, `~/.cache/uv/archive-v0` 8.2 GiB. Not touched.

## Done (2026-10-20)

- [x] Coalesce: this repo is the only source and marketplace. braisenly-plugins (PR #6) and dot-agents (PR #24) copies removed. The publish guard `EXTRACTED_PLUGINS` stops re-adds, which answers the open "what does the next publish do" item.
- [x] Rename to claude-statusline, Claude Code only. Repo renamed.
- [x] Stable launcher. Updates reach the status line with no settings edit (E11).
- [x] `drift-control.ps1` twin; `/drift-control` paths fixed.
- [x] Windows resize watcher verified live in a field window (closes the open item above).
- [x] Fit margin fix (`COLUMNS-4`).
- [x] pwsh renderer parity; `test-statusline.ps1` twin; ladder map tests; mutation-checked.
- [x] Both hosts migrated off the stale `~/braisenly-statusline` clone.

## Open (2026-10-20)

- [x] Release 2.0.0: #10 → `development`, #11 → `main` `482cb3d`, tag `claude-statusline@2.0.0`; both hosts switched to `main` (2026-10-21)
- [x] Stale `~/braisenly-statusline` clones deleted (user confirmed 2026-10-21). This broke profile status lines; restored with a shim and fixed in dot-agents #26/#28.
- [ ] Live re-run of E10 (`/drift-control`) in a field window; largo user-impersonation cases.

## Open (2026-10-21)

- [ ] Wire the drift assessor hook: `hooks/hooks.json` plus pwsh twins of `drift-hook-entry` and `drift-assess-worker`, with per-host registration. kb `projects/claude-statusline/claude-statusline-backlog-wire-the-drift-assessor-hook-future-implementation`.
- [ ] Deferred Codex findings (same kb note):
  - GNU `stat -c %s` and `date -d` fallbacks in `drift-assess-worker.sh`
  - `--recent` must filter `kind=="score"` before tail, in both twins
  - quote the custom `--config-dir` launcher path in `install.sh`
- [ ] `install.sh` / `install.ps1` replace a symlinked `settings.json` with a plain file (temp-file rename). Write through the link instead. Today `/install-claude-statusline` guards against this.
- [ ] largo: remove the `~/braisenly-statusline` shim once largo's `~/.agents` branch takes dot-agents `main`.

## Open (2026-11-24)

- [x] CI blocked repo-wide (2026-11-16→24): check-run annotation "recent account payments have failed or your spending limit needs to be increased". Root-caused 2026-11-24; repo made **public 2026-11-25** (user decision), Actions restored; #19/#20 had merged with zero-step CI runs. PR #17's CI then ran green (ubuntu/macos/plugin/pwsh all pass).
- [x] Remove `fit.resize_watch` / resize-watch (PR #21, released as 2.4.0). Live-fire proof on 2.1.326: re-render 0.8–2.1 s after resize, no settings writes.
- [x] Tag 2.1.0/2.2.0/2.3.0/2.3.1 (backfilled 2026-11-25), 2.4.0, 3.0.0. Promote development → main as 3.0.0 (PR #23, merge `8d5ba83`). Release records backfilled (kb project + org logs, both memory files).
- [ ] PR #17 (`feat/radial-indicators`): CI now green; still needs rebase onto `development` (drops duplicate token-count commit `c4cb2cb`), removal of committed `lab/radial/__pycache__/*.pyc`, then review and merge decision.
- [ ] User's live `~/.claude/settings.json` still carries a `# bsl-cols=` nonce in `statusLine.command` (inert since 2.4.0; the resets toggle still uses the mechanism). Leave unless the user wants it stripped.
- [ ] Remove `fit.resize_watch` / `scripts/resize-watch.{sh,ps1}` / settings-nonce machinery: Claude Code 2.1.326 re-runs the status line on terminal resize natively (#76988 closed as completed; #107291). User chose report-only on 2026-11-24.
- [ ] Release tags missing for 2.1.0 / 2.2.0 / 2.3.1 (only `claude-statusline@2.0.0` and `braisenly-statusline@1.1.0` exist); check the release protocol before tagging.

## Open (2026-11-09) — public release

- [ ] README rewrite for the public (readme-writer, `docs/public-readme`)
- [ ] Animated SVG + `.cast` demo of the exclusion ladder, regenerable via `scripts/demo/render-demo.sh` (demo-builder)
- [ ] Simplify the codebase without behaviour change; rule on the "proposed, needs ruling" list (simplifier)
- [ ] Two opus reviews per deliverable, max 3 fix rounds
- [ ] Draft PRs into `development`; review bots addressed
- [ ] Version bump + CHANGELOG + tag per kb release protocol; release-record surfaces (kb project log, org log, memories)
- [ ] Promote to `main`
- [ ] User OK, then `gh repo edit --visibility public`; add topics and homepage

## Radial indicators (2026-11-13 →)

- [x] Research stock glyph options and Claude Code's image-escape handling
- [x] First design approved; design doc committed; draft PR #17
- [x] Spike font renders in iTerm2 (after restart) and in a real Claude Code status line
- [x] Implementation plan written (`756a397`) — stale since the track requirement; do not execute as written
- [x] kb laboratory ledger started, foreground approach transcribed
- [x] E-001 colour font (refuted), E-002 overprint (partial), E-003 tiled two-cell ring (confirmed), E-004 in the status line (confirmed)
- [x] E-005 grey track by contrast ratio on six themes via the iTerm2 Python API (confirmed); default ratio 1.75
- [x] L-001 live trial in the user's status line; E-008 cell-fitted ring with notches, rings kept through the ladder (user approved the look 2026-11-15)
- [x] E-009 gradient along the arc: built, rejected by the user, reverted
- [ ] Cell-geometry input: decide between building the font at configuration time, shipping cell-width variants, or a design independent of cell width
- [ ] E-006: background discovery (OSC 11 from a shell, iTerm2 API/profile, Windows Terminal settings, screenshot pixel)
- [ ] Dedicated test of the "codepoint shown before font registration stays a box" inference
- [ ] Windows Terminal on adagio: W-001…W-004 per the standing handoff order in `CURRENT_TASK_STATE.md` (PowerShell tool required; fonts prebuilt in `lab/radial/fonts/`)
- [ ] E-007: combining-mark overlay, one run (proposal in the ledger)
- [ ] `NO_COLOR` form of the ring
- [ ] Revise design doc and implementation plan from the ledger (two codepoints, 202 glyphs, grey rule, no trailing space)
- [ ] User chooses the execution method for the revised plan; build
- [ ] Draft the agentic configuration skill from the ledger once the method holds across terminals
- [ ] Remove spike and lab fonts from `~/Library/Fonts` once the real installer replaces them

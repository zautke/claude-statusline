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
- [ ] E-006: background discovery (OSC 11 from a shell, iTerm2 API/profile, Windows Terminal settings, screenshot pixel)
- [ ] Dedicated test of the "codepoint shown before font registration stays a box" inference
- [ ] Windows Terminal on adagio: font fallback, cross-cell overflow, colours (PowerShell tool required)
- [ ] `NO_COLOR` form of the ring
- [ ] 1 px step where the two halves meet at the cell boundary
- [ ] Revise design doc and implementation plan from the ledger (two codepoints, 202 glyphs, grey rule, no trailing space)
- [ ] User chooses the execution method for the revised plan; build
- [ ] Draft the agentic configuration skill from the ledger once the method holds across terminals
- [ ] Remove spike and lab fonts from `~/Library/Fonts` once the real installer replaces them

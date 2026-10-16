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

- [ ] Verify what the next dot-agents → braisenly-plugins publish does to the vendored `braisenly-statusline/` directory (overwrite, delete, or leave). Owner: user.
- [ ] Windows resize watcher (`resize-watch.ps1`) untested on a live desktop session; AttachConsole needs an interactive session.
- [ ] Optional: branch name on row 2 under cwd when stacked.
- [ ] Optional: strip `thresholds`/`colors` from existing user configs when the skill next touches them.
- [ ] largo disk: 5.7 GiB free, `~/.cache/uv/archive-v0` 8.2 GiB. Not touched.

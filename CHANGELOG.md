# Changelog

All notable changes to claude-statusline (formerly braisenly-statusline) are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are tagged `claude-statusline@X.Y.Z`
(up to 1.1.0: `braisenly-statusline@X.Y.Z`).

## [2.1.0] — 2026-11-11

### Minor changes

- Show when the 5h and 7d limits reset. New settings `resets` (on/off) and `resets_format` (`clock` or `countdown`). Clock shows `↻22:40` today and `↻F14` on another day, with day codes M T W R F SA SU. Countdown shows `↻2h13m` or `↻4d6h`. A state glyph, `⊟◂` (hidden) or `⊞◂` (shown), marks the toggle. `resets` is a new step in the fit ladder, so the times drop before anything else is cut.
- Toggle the reset times three ways: the `/statusline-resets` mod command (Claude Code 2.1.286 or later), the `ctrl+x r` keybinding, or Ctrl/Cmd+click on the 5h/7d slots (OSC 8 link). Each OS gets a URL handler for the click: a Windows registry entry plus the Windows Terminal `safeUriSchemes` setting, a macOS applet, and a Linux `xdg` handler. All three routes share `scripts/resets-toggle.{sh,ps1}`.
- The launcher accepts `-u|--url` and passes it to the installed `resets-toggle`.
- `install.{sh,ps1}` gained `--uninstall` and `-W|--no-wt-scheme` (skip the Windows Terminal scheme edit).
- CI runs `claude plugin test` and `claude plugin validate`.

### Patch changes

- PowerShell 7 turned ISO dates in JSON into `DateTime` values and rewrote them. The Fable cache, `install.ps1` and `resize-watch.ps1` now keep ISO dates verbatim.
- `install.ps1` now honours `--config-dir` and `--force`. It ignored both before.
- The installers write through a symlinked `settings.json` instead of replacing the link.
- The PowerShell renderer's model colour and bar gradient now match the Bash renderer.
- The Bash renderer's width count no longer depends on the locale: `cells()` counts bytes minus UTF-8 continuation bytes, so widths are right even when no UTF-8 locale can be switched on (the fit used to over-shrink there). Its strip loops now stop unless each pass shortens the string, so they always terminate. `LC_ALL` is no longer exported to child processes.

## [2.0.0] — 2026-10-21

### Breaking changes

- Renamed to `claude-statusline`: the plugin, the marketplace, and the repository `zautke/claude-statusline`. The install id is now `claude-statusline@claude-statusline`. Environment variables are now `CLAUDE_STATUSLINE_*` (were `BRAISENLY_STATUSLINE_*`).
- This is a Claude Code plugin only: no Codex, Copilot or Agent Plugins manifests ship.
- This repository is now the plugin's only source and its own marketplace. The copies in `zautke/braisenly-plugins` and dot-agents `profiles/` are retired. Installers and the resize watcher still treat commands under the old name as their own, so old installs migrate.

### Minor changes

- `statusLine.command` now points at a stable launcher in `<config-dir>/claude-statusline/`, which `install.{sh,ps1}` copies there. On every render the launcher runs the installed plugin version, so updates reach the status line without a settings edit. If the plugin is not installed, it prints `claude-statusline: not installed` and exits 0.
- Brought in `/drift-control` (command, scripts, Textual menu, tmux popup) from the marketplace copies. Its scripts find their siblings in their own directory instead of `~/.claude/scripts`. Rubric edits go to `~/.claude/state/drift/rubric.md`, which survives updates.
- Added `drift-control.ps1`, a PowerShell twin of `drift-control.sh` with the same arguments and output, so `/drift-control` runs on Windows without bash. Both twins gained `-n|--recent <N>`. The command runs the PowerShell twin on Windows and the bash twin elsewhere.
- Added `tests/test-statusline.ps1`, a PowerShell twin of `test-statusline.sh`. Both now test the exclusion ladder:
  - Each of the 16 steps must produce exactly its declared change.
  - Narrowing the window one column at a time must engage the steps in order: k steps at `L_k + margin` columns, k+1 one column narrower.
  - Every step must free at least one cell.

  Both twins also reject invalid segments, labels, widths and Fable intervals.
- Identity and regex constants live in `config/` (`identity.env`, `constants.{sh,ps1}`).

### Patch changes

- The fit budget is now `COLUMNS - 4 - fit.reserve` (was `- 3`). Claude Code draws the status line 2 cells in from each edge, so a row padded to `COLUMNS - 3` overflowed by one cell and was cut with an ellipsis. Found live on Claude Code 2.1.306, where a 52-column window shows 48 cells. The margin is the named constant `STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS`.
- The PowerShell renderer now matches the Bash one. It honours `segments` (order and subset, including the `profile` segment), per-segment `labels` and `widths`, and `NO_COLOR`, and it validates the whole schema all-or-nothing. Before this, those settings had no effect on Windows. The Fable label now comes from `labels.fable`; `fable.model` only selects the usage limit.
- `tests/test-statusline.sh` used a fixed Fable `fetched_at` that had gone stale, so every Fable check saw `n/a`. It now writes a fresh timestamp.

## [1.1.0] — 2026-10-16

### Minor changes

- Fit the status line to the terminal on every render: the width comes from the Claude Code pty (falling back to `COLUMNS`), bars shrink by one shared ratio down to `fit.min_bar_cells`, then drop, then a 16-step exclusion ladder (`fit.ladder`) trims text until the line fits. Optional two-row aligned layout (`fit.rows: 2`). Percentages always take the bar's gradient colour; `thresholds` and `colors` are ignored. Optional resize watcher (`fit.resize_watch`) re-renders about two seconds after a pane resize by bumping a nonce on `statusLine.command`. The drift segment is retired; configs that still list it stay valid. Runs on Bash 3.2.

## [1.0.1] — 2026-09-22

### Patch changes

- Fix the Fable usage bar: stop retrying the usage endpoint on every render after a 429 (honor `Retry-After`), reclaim a refresh lock left by a killed refresh (including on Linux), and draw bars in whole cells so the fill is colored and has no gap before the track. The ctx and disk bars now default to 12 cells.

## [1.0.0] — 2026-09-20

- Initial release.

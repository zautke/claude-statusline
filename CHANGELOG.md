# Changelog

All notable changes to claude-statusline (formerly braisenly-statusline) are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases up to 1.1.0 are tagged
`braisenly-statusline@X.Y.Z`. From 1.1.1 the org stamp applies: `version` is
`MAJOR.MINOR.PATCH.BUILD-<branch>` (branch with `/` replaced by `-`), tags are `vMAJOR.MINOR.PATCH.BUILD`,
and each merge into `development` adds an entry to `changeset.md`.

## [Unreleased]

### Changed

- Renamed to `claude-statusline` (plugin, marketplace and repository `zautke/claude-statusline`). It is a Claude Code plugin only: no Codex, Copilot or Agent Plugins manifests ship. Environment variables are now `CLAUDE_STATUSLINE_*` (were `BRAISENLY_STATUSLINE_*`). Installers and the resize watcher still treat commands under the old name as their own, so old installs migrate.
- This repository is now the plugin's only source and its own marketplace (`claude-statusline@claude-statusline`). The copies in `zautke/braisenly-plugins` and dot-agents `profiles/` are retired.
- `statusLine.command` now points at a stable launcher in `<config-dir>/claude-statusline/`, copied there by `install.{sh,ps1}`. On every render it runs the installed plugin version, so updates reach the status line without a settings edit. If the plugin is not installed it prints `claude-statusline: not installed` and exits 0.
- Brought in `/drift-control` (command, scripts, Textual menu, tmux popup) from the marketplace copies. Its scripts resolve their siblings from their own directory instead of `~/.claude/scripts`. Rubric edits go to `~/.claude/state/drift/rubric.md`, which survives updates.
- Added `drift-control.ps1`, a PowerShell twin of `drift-control.sh` with the same arguments and output, so `/drift-control` runs on Windows without bash. Both twins gained `-n|--recent <N>`. The command runs the PowerShell twin on Windows and the bash twin elsewhere.
### Fixed

- The fit budget is now `COLUMNS - 4 - fit.reserve` (was `- 3`). Claude Code draws the status line 2 cells in from each edge, so a row padded to `COLUMNS - 3` overflowed by one cell and was cut with an ellipsis. Found live on Claude Code 2.1.306: a 52-column window shows 48 cells. The margin is the named constant `STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS`.

- The PowerShell renderer now matches the Bash one. It honours `segments` (order and subset, including the `profile` segment), per-segment `labels` and `widths`, and `NO_COLOR`, and it validates the whole schema all-or-nothing. Before this, those settings had no effect on Windows. The Fable label comes from `labels.fable`, and `fable.model` only picks the usage limit.
- `tests/test-statusline.sh` used a fixed Fable `fetched_at` that has since gone stale, so every Fable check saw `n/a`. It now writes a fresh timestamp.

### Changed (continued)

- Added `tests/test-statusline.ps1`, a PowerShell twin of `test-statusline.sh`. Both now check the exclusion ladder. Each of the 16 steps must produce exactly its declared change. Narrowing the line one column at a time must engage the steps in order, k at `L_k + margin` columns and k+1 one column narrower, and every step must free at least one cell. Both twins also reject invalid segments, labels, widths and Fable intervals.

- Identity and regex constants live in `config/` (`identity.env`, `constants.{sh,ps1}`).

## [1.1.0] — 2026-10-16

### Minor changes

- Fit the status line to the terminal on every render: the width comes from the Claude Code pty (falling back to `COLUMNS`), bars shrink by one shared ratio down to `fit.min_bar_cells`, then drop, then a 16-step exclusion ladder (`fit.ladder`) trims text until the line fits. Optional two-row aligned layout (`fit.rows: 2`). Percentages always take the bar's gradient colour; `thresholds` and `colors` are ignored. Optional resize watcher (`fit.resize_watch`) re-renders about two seconds after a pane resize by bumping a nonce on `statusLine.command`. The drift segment is retired; configs that still list it stay valid. Runs on Bash 3.2.

## [1.0.1] — 2026-09-22

### Patch changes

- Fix the Fable usage bar: stop retrying the usage endpoint on every render after a 429 (honor `Retry-After`), reclaim a refresh lock left by a killed refresh (including on Linux), and draw bars in whole cells so the fill is colored and has no gap before the track. The ctx and disk bars now default to 12 cells.

## [1.0.0] — 2026-09-20

- Initial release.

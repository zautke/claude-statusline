# Changelog

All notable changes to braisenly-statusline are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases up to 1.1.0 are tagged
`braisenly-statusline@X.Y.Z`. From 1.1.1 the org stamp applies: `version` is
`MAJOR.MINOR.PATCH.BUILD-<branch>` (branch with `/` replaced by `-`), tags are `vMAJOR.MINOR.PATCH.BUILD`,
and each merge into `development` adds an entry to `changeset.md`.

## [Unreleased]

### Changed

- This repository is now the plugin's only source and its own marketplace (`braisenly-statusline@braisenly-statusline`). The copies in `zautke/braisenly-plugins` and dot-agents `profiles/` are retired.
- `statusLine.command` now points at a stable launcher in `<config-dir>/braisenly-statusline/`, copied there by `install.{sh,ps1}`. On every render it runs the installed plugin version, so updates reach the status line without a settings edit. If the plugin is not installed it prints `braisenly-statusline: not installed` and exits 0.
- Brought in `/drift-control` (command, scripts, Textual menu, tmux popup) from the marketplace copies. Its scripts resolve their siblings from their own directory instead of `~/.claude/scripts`. Rubric edits go to `~/.claude/state/drift/rubric.md`, which survives updates.
- Identity and regex constants live in `config/` (`identity.env`, `constants.{sh,ps1}`).

## [1.1.0] — 2026-10-16

### Minor changes

- Fit the status line to the terminal on every render: the width comes from the Claude Code pty (falling back to `COLUMNS`), bars shrink by one shared ratio down to `fit.min_bar_cells`, then drop, then a 16-step exclusion ladder (`fit.ladder`) trims text until the line fits. Optional two-row aligned layout (`fit.rows: 2`). Percentages always take the bar's gradient colour; `thresholds` and `colors` are ignored. Optional resize watcher (`fit.resize_watch`) re-renders about two seconds after a pane resize by bumping a nonce on `statusLine.command`. The drift segment is retired; configs that still list it stay valid. Runs on Bash 3.2.

## [1.0.1] — 2026-09-22

### Patch changes

- Fix the Fable usage bar: stop retrying the usage endpoint on every render after a 429 (honor `Retry-After`), reclaim a refresh lock left by a killed refresh (including on Linux), and draw bars in whole cells so the fill is colored and has no gap before the track. The ctx and disk bars now default to 12 cells.

## [1.0.0] — 2026-09-20

- Initial release.

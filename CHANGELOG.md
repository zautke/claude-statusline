# Changelog

All notable changes to braisenly-statusline are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are tagged
`braisenly-statusline@X.Y.Z`.

## [1.1.0] — 2026-10-16

### Minor changes

- Fit the status line to the terminal on every render: the width comes from the Claude Code pty (falling back to `COLUMNS`), bars shrink by one shared ratio down to `fit.min_bar_cells`, then drop, then a 16-step exclusion ladder (`fit.ladder`) trims text until the line fits. Optional two-row aligned layout (`fit.rows: 2`). Percentages always take the bar's gradient colour; `thresholds` and `colors` are ignored. Optional resize watcher (`fit.resize_watch`) re-renders about two seconds after a pane resize by bumping a nonce on `statusLine.command`. The drift segment is retired; configs that still list it stay valid. Runs on Bash 3.2.

## [1.0.1] — 2026-09-22

### Patch changes

- Fix the Fable usage bar: stop retrying the usage endpoint on every render after a 429 (honor `Retry-After`), reclaim a refresh lock left by a killed refresh (including on Linux), and draw bars in whole cells so the fill is colored and has no gap before the track. The ctx and disk bars now default to 12 cells.

## [1.0.0] — 2026-09-20

- Initial release.

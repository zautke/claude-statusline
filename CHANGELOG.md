# Changelog

All notable changes to claude-statusline (formerly braisenly-statusline) are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the plugin adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). Releases are tagged `claude-statusline@X.Y.Z`
(up to 1.1.0: `braisenly-statusline@X.Y.Z`).

## [2.4.0] — 2026-11-25

### Removed

- The `fit.resize_watch` setting and the `resize-watch` sidecar (`scripts/resize-watch.sh` / `resize-watch.ps1`), which rewrote `statusLine.command` in `settings.json` with a `# bsl-cols=N` nonce to force a redraw about two seconds after a terminal resize. Claude Code 2.1.326 (2026-11-16) re-runs the status line on terminal resize natively ([anthropics/claude-code#107291](https://github.com/anthropics/claude-code/issues/107291), closing [#76988](https://github.com/anthropics/claude-code/issues/76988)); measured re-render ~0.8–2.1 s after the resize with no watcher and no settings writes. A leftover `resize_watch` key in `statusline.json` is accepted and ignored. The ` # bsl-cols=<n>` nonce remains in use by the resets toggle. Requires Claude Code ≥ 2.1.326 for automatic refit on resize.

## [2.3.1] — 2026-11-17

### Patch changes

- The context segment counts tokens in decimal units, as Claude Code does: 182,832 tokens reads `182.8K` (was `178.5K`) and a 1,000,000-token window reads `1M` (was `953.7K`). The byte formatter, which divides by 1024, was being used for tokens. Disk sizes keep binary units. Both renderers.

## [2.3.0] — 2026-11-16

### Minor changes

- The 7d clock shows the reset's day of month and full time: day code, two-digit day of month, then `|HH:MM`, for example `↻Su22|14:00` (was `↻Su14`, whose hour read like a date). The 5h clock and both countdowns are unchanged.

## [2.2.0] — 2026-11-16

### Minor changes

- The 7d clock writes the weekend day codes in title case: `Sa` (Saturday) and `Su` (Sunday), for example `↻Sa14`. Weekdays stay one capital letter: `M T W R F`.

## [2.1.0] — 2026-11-11

### Minor changes

- Show when the 5h and 7d limits reset. New settings `resets` (on/off) and `resets_format` (`clock` or `countdown`). Clock shows the 5h slot as `↻HH:MM` (for example `↻22:40`) and the 7d slot as day code plus 24h hour (for example `↻F14`), with day codes M T W R F SA SU. Countdown shows `↻2h13m` or `↻4d6h`. A state glyph marks the toggle: `⊟◂` when the times are shown (click hides them), `⊞◂` when they are hidden (click shows them). `resets` is a new step in the fit ladder, so the times drop before anything else is cut.
- Toggle the reset times three ways: the `/statusline-resets` mod command (Claude Code 2.1.286 or later), the `ctrl+x r` keybinding, or Ctrl/Cmd+click on the 5h/7d slots (OSC 8 link). Each OS gets a URL handler for the click: a Windows registry entry plus the Windows Terminal `safeUriSchemes` setting, a macOS applet, and a Linux `xdg` handler. All three routes share `scripts/resets-toggle.{sh,ps1}`.
- The launcher accepts `-u|--url` and passes it to the installed `resets-toggle`.
- `install.{sh,ps1}` gained `--uninstall` and `-W|--no-wt-scheme` (skip the Windows Terminal scheme edit).
- CI runs `claude plugin test` and `claude plugin validate`.
- Upgrading from 2.0.0: `claude plugin update` brings the renderer and the command, but re-run the installer once to get the `ctrl+x r` key binding and the click handler. Use the installed version's installer, looked up in `installed_plugins.json`, not a glob over the plugin cache (which keeps 2.0.0 beside 2.1.0, so a glob runs the old installer):
  - bash: `bash "$(jq -r '.plugins["claude-statusline@claude-statusline"] | (map(select(.scope == "user")) + .)[0].installPath' "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/plugins/installed_plugins.json")/scripts/install.sh"`
  - PowerShell 7 (pwsh; not Windows PowerShell 5.1): `$p = (Get-Content -Raw "$($env:CLAUDE_CONFIG_DIR ?? "$HOME\.claude")\plugins\installed_plugins.json" | ConvertFrom-Json).plugins.'claude-statusline@claude-statusline' | Sort-Object -Stable { $_.scope -ne 'user' } | Select-Object -First 1; pwsh -NoProfile -File (Join-Path $p.installPath 'scripts\install.ps1')`
- A custom `fit.ladder` is used as written and does not gain `resets`, which is first only in the default ladder. If your `statusline.json` sets `fit.ladder`, add `"resets"` at its front, or set `"resets": false`, so a narrow line drops the reset text before your other segments.
- `--uninstall` of the profile that holds the click handler moves the handler to another profile that still has it installed, instead of leaving that profile's links dead.

### Patch changes

- A click link without `&profile=` now always toggles `~/.claude`; it used to follow the `CLAUDE_CONFIG_DIR` of the environment the click handler ran in.
- The installers merge `statusLine` instead of replacing it, so a re-install keeps `refreshInterval` and keys such as `padding`.
- `install.ps1` stops with an error, and leaves no temp file, when it cannot replace a file held open by another program; it used to report success.
- The macOS click applet adds `/opt/homebrew/bin:/usr/local/bin` to its `PATH`, so a Homebrew `jq` is found.
- A Linux `--uninstall` also removes the `x-scheme-handler/claude-statusline` default from `mimeapps.list`.
- `resets-toggle.sh` warns when it cannot write `url-handler.log`, as the PowerShell twin does.

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

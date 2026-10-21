---
name: configure-statusline
description: Configures, previews, resets, installs, or uninstalls the claude-statusline Claude Code status line, including segment order, visibility, labels, indicator lengths, terminal fitting, and the resize watcher. Use for requests such as "make my Claude status bars shorter", "show Fable usage", or "make the status line fit my split pane".
compatibility: Requires bash and jq; Fable refresh additionally requires curl and Claude Code OAuth credentials.
---

# Configure Claude Code Status Line

Operate on the active profile only: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Preserve unrelated settings and refuse to replace a non-claude-statusline `statusLine.command` unless user explicitly requests force.

## Install

1. Resolve this skill's plugin root by walking up from `skills/configure-statusline`.
2. Run the installer from that root: `bash <plugin-root>/scripts/install.sh` on macOS/Linux, `pwsh -NoProfile -File <plugin-root>/scripts/install.ps1` on Windows. Pass `--force` / `-Force` only when the user explicitly asks to replace a non-claude-statusline command.
3. The installer copies the stable launcher to `<config-dir>/claude-statusline/` and points `statusLine` at it. The launcher finds the installed plugin version on every render, so plugin updates need no settings edit. It also enables `claude-statusline@claude-statusline`.
4. Commands pointing at a `claude-statusline` or legacy `braisenly-statusline` clone or plugin cache path, or legacy `bash ~/.claude/statusline-dispatcher.sh` are claude-statusline-owned and safe to migrate.
5. Do not copy renderer scripts outside the plugin; only the launcher lives outside it.

## Configure

Edit `statusline.json` atomically. Start from `statusline.example.json` when absent. Apply only requested fields.

- `segments`: unique ordered subset of `model`, `profile`, `cwd`, `context`, `disk`, `tmp`, `five_hour`, `seven_day`, `fable`. Omission hides a segment.
- `labels`: string labels keyed by segment.
- `widths`: integer indicator lengths from 1 through 128.
- `fit`: `rows` (1 or 2, default 1), `reserve` cells (0 through 200) held back from the `COLUMNS` budget, `min_bar_cells` (1 through 128), `ladder` (ordered subset of the exclusion steps below), and `resize_watch` boolean (default false). Fit order at every render with `rows: 1`: full bars; bars shrink uniformly down to the floor; bars drop and percentages take the bar heat colour; ladder steps apply one at a time until the line fits; then the floor. With `rows: 2` a second aligned row (labels and bars above, values below) is tried before any shrinking, and the ladder first runs with bars kept at the largest size that fits before bars drop. Rows are space-padded to the budget once any fitting engages.
- Ladder steps, default order: `disk_label`, `ctx_int`, `no_parens`, `disk_int`, `ctx_no_total`, `no_free`, `fable_short`, `disk_value`, `ctx_no_used`, `fable_label`, `fable_segment`, `seven_label`, `five_label`, `ctx_label`, `seven_segment`, `five_segment`. Unknown names reject the config.
- Percentages always take the gradient colour of their bar tip. `thresholds` and `colors` from older configs are ignored; remove them when touching the file.
- `fable`: model display name, refresh interval of at least 60 seconds, and maximum stale interval of at least 60 seconds.

Report an exact validation error before changing invalid input. Keep existing values not mentioned by user.

## Resize watch

Opt-in via `fit.resize_watch: true` (default off, because it rewrites `settings.json`). When enabled the renderer starts one `scripts/resize-watch.sh` (or `resize-watch.ps1`) per Claude Code process. It polls the Claude pty width every 250ms and, on change, after the width settles for 400ms appends ` # bsl-cols=<n>` to `statusLine.command` in the active profile's `settings.json`; a command change makes Claude Code re-run the status line at once, since terminal resize is not a native trigger. Writes go through a validated temp file and atomic rename, and are dropped if the file changed since it was read (a microsecond race with a concurrent Claude Code write remains); a one-time `settings.json.bsl-backup` is kept. The zero-write alternative is `statusLine.refreshInterval` in `settings.json`. Set `CLAUDE_STATUSLINE_DISABLE_WATCH=1` to force it off. Treat the nonce suffix as claude-statusline-owned when inspecting or migrating `statusLine.command`.

## Preview and verify

Pipe representative Claude status JSON into `scripts/statusline-dispatcher.sh` with `CLAUDE_STATUSLINE_DISABLE_REFRESH=1`. Show rendered line. Then run `bash tests/test-statusline.sh`.

## Reset or uninstall

- Reset: remove only active profile's `statusline.json`; built-in defaults resume.
- Uninstall: remove `statusLine` only when its command points to this plugin or a legacy braisenly-statusline command, remove active profile's `statusline.json`, and disable plugin entry. Preserve every unrelated setting.

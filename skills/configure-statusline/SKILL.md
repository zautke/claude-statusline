---
name: configure-statusline
description: Configures, previews, resets, installs, or uninstalls the claude-statusline Claude Code status line, including segment order, visibility, labels, indicator lengths, terminal fitting, the resize watcher, and the 5h/7d reset times (on/off, clock or countdown, the /statusline-resets command, the ctrl+x r key, click to toggle). Use for requests such as "make my Claude status bars shorter", "show Fable usage", "make the status line fit my split pane", "show reset times", "hide the reset times", or "show a countdown to when my 5h limit resets".
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
- Ladder steps, default order: `resets`, `disk_label`, `ctx_int`, `no_parens`, `disk_int`, `ctx_no_total`, `no_free`, `fable_short`, `disk_value`, `ctx_no_used`, `fable_label`, `fable_segment`, `seven_label`, `five_label`, `ctx_label`, `seven_segment`, `five_segment`. Unknown names reject the config.
- Percentages always take the gradient colour of their bar tip. `thresholds` and `colors` from older configs are ignored; remove them when touching the file.
- `fable`: model display name, refresh interval of at least 60 seconds, and maximum stale interval of at least 60 seconds.
- `resets`: boolean, default `true`. Shows when the 5h and 7d limits reset, after each slot's `(pct%)`. `false` hides the reset text.
- `resets_format`: `clock` (default) or `countdown`, case-sensitive. Any other value rejects the config.

Report an exact validation error before changing invalid input. Keep existing values not mentioned by user.

## Reset times

Each 5h and 7d slot can show when its limit resets, from the `rate_limits.*.resets_at` the status line receives; a window that is absent shows nothing. The time is rounded up to the next whole minute, in the local time zone.

- `clock` (default): 5h shows `↻22:40` (24h `HH:MM`); 7d shows `↻F14` (day code plus 24h hour). Day codes: `M` Mon, `T` Tue, `W` Wed, `R` Thu, `F` Fri, `SA` Sat, `SU` Sun.
- `countdown`: `↻2h13m`, under an hour `↻42m`, a day or more `↻4d6h`.
- Every rendered 5h/7d slot ends with a 2-cell click hint: `⊟◂` when reset times are shown, `⊞◂` when `resets` is `false`.
- Ladder: `resets` is the first default step, so a narrow line drops the reset text and hint from both slots before anything else.

Three ways to toggle, all rewriting only `resets` / `resets_format` in `statusline.json` (other keys are kept, a missing file is created, an invalid one is refused untouched):

1. `/statusline-resets [toggle|on|off|clock|countdown|status]`: answers instantly, no model turn; no argument toggles. Needs Claude Code 2.1.286 or later.
2. `ctrl+x r`: installed by the installer into `keybindings.json` (`Chat` context). Same requirement. A chord already bound to something else is left alone with a warning.
3. Ctrl/Cmd+click on the 5h or 7d slot: needs a terminal with hyperlink support; no link is drawn under tmux, WSL or `NO_COLOR`, or when the config dir is neither `~/.claude` nor `~/.claude-<name>`, and it works only after the installer registered the `claude-statusline://` handler. On Windows the installer adds `claude-statusline` to Windows Terminal's `safeUriSchemes` (it prints the file it edited); `-W` / `--no-wt-scheme` skips that and prints the line to add by hand.

On older clients, or when none of the three works, edit `statusline.json` directly or run `scripts/resets-toggle.sh` (`pwsh -NoProfile -File scripts/resets-toggle.ps1` on Windows) with `--get`, `--set on|off|toggle`, or `--format clock|countdown`; `--format` also turns reset times on.

Countdown only stays current if the status line refreshes. When the status line is claude-statusline's own, selecting `countdown` sets `statusLine.refreshInterval` to 60 when none is set, and leaving `countdown` removes a `refreshInterval` of exactly 60 (even one the user set); any other value is kept. When the status line is not ours, nothing in `settings.json` is touched, and the user must set `statusLine.refreshInterval` to 60 or less themselves. When a toggle actually changes `statusline.json` and the status line is ours, it also bumps the `# bsl-cols=` nonce so Claude Code redraws at once.

Uninstall: `bash <plugin-root>/scripts/install.sh --uninstall` (`pwsh -NoProfile -File <plugin-root>/scripts/install.ps1 --uninstall` on Windows; short form `-U`). It removes only what the installer added: the `ctrl+x r` entry, the click handler and its marker, the Windows Terminal scheme entry (Windows only; left alone if the install used `-W`), the launcher directory, an owned `statusLine`, and the `enabledPlugins` entry.

## Resize watch

Opt-in via `fit.resize_watch: true` (default off, because it rewrites `settings.json`). When enabled the renderer starts one `scripts/resize-watch.sh` (or `resize-watch.ps1`) per Claude Code process. It polls the Claude pty width every 250ms and, on change, after the width settles for 400ms appends ` # bsl-cols=<n>` to `statusLine.command` in the active profile's `settings.json`; a command change makes Claude Code re-run the status line at once, since terminal resize is not a native trigger. Writes go through a validated temp file and atomic rename, and are dropped if the file changed since it was read (a microsecond race with a concurrent Claude Code write remains); a one-time `settings.json.bsl-backup` is kept. The zero-write alternative is `statusLine.refreshInterval` in `settings.json`. Set `CLAUDE_STATUSLINE_DISABLE_WATCH=1` to force it off. Treat the nonce suffix as claude-statusline-owned when inspecting or migrating `statusLine.command`.

## Preview and verify

Pipe representative Claude status JSON into `scripts/statusline-dispatcher.sh` with `CLAUDE_STATUSLINE_DISABLE_REFRESH=1`. Show rendered line. Then run `bash tests/test-statusline.sh`.

## Reset or uninstall

- Reset: remove only active profile's `statusline.json`; built-in defaults resume.
- Uninstall: run `install --uninstall` (see Reset times) rather than hand-editing; it removes the owned `statusLine`, the keybinding, the click handler, the launcher, and the plugin entry. Then remove active profile's `statusline.json`. Preserve every unrelated setting.

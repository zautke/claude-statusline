---
name: configure-statusline
description: Configures, previews, resets, installs, or uninstalls the Braisenly Claude Code status line, including segment order, visibility, labels, colored percentage thresholds, RGB colors, and indicator lengths. Use for requests such as "make my Claude status bars shorter", "show Fable usage", or "change statusline colors".
compatibility: Requires bash and jq; Fable refresh additionally requires curl and Claude Code OAuth credentials.
---

# Configure Claude Code Status Line

Operate on the active profile only: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Preserve unrelated settings and refuse to replace a non-Braisenly `statusLine.command` unless user explicitly requests force.

## Install

1. Resolve this skill's plugin root by walking up from `skills/configure-statusline`.
2. Confirm `scripts/statusline-dispatcher.sh` exists.
3. Update `settings.json` atomically with `jq`, setting `statusLine` to command `bash <absolute-plugin-root>/scripts/statusline-dispatcher.sh`. Treat legacy `bash ~/.claude/statusline-dispatcher.sh` as Braisenly-owned and safe to migrate.
4. Enable `braisenly-statusline@dot-agents` when the active settings manage plugins.
5. Do not copy renderer scripts outside the plugin.

## Configure

Edit `statusline.json` atomically. Start from `statusline.example.json` when absent. Apply only requested fields.

- `segments`: unique ordered subset of `model`, `profile`, `cwd`, `context`, `disk`, `tmp`, `five_hour`, `seven_day`, `fable`. Omission hides a segment.
- `labels`: string labels keyed by segment.
- `widths`: integer indicator lengths from 1 through 128.
- `thresholds.usage`: `0 <= warn <= critical <= 100`.
- `fit`: `reserve` cells (0 through 200) held back from the `COLUMNS` budget, and `min_bar_cells` (1 through 128); bars shrink uniformly to fit `COLUMNS - 3 - reserve`, drop entirely when any bar would fall below the floor, and the line is space-padded to the budget after shrinking.
- `colors`: `ok`, `warn`, and `critical`, each exactly three integer Red-Green-Blue values from 0 through 255.
- `fable`: model display name, refresh interval of at least 60 seconds, and maximum stale interval of at least 60 seconds.

Report an exact validation error before changing invalid input. Keep existing values not mentioned by user.

## Preview and verify

Pipe representative Claude status JSON into `scripts/statusline-dispatcher.sh` with `BRAISENLY_STATUSLINE_DISABLE_REFRESH=1`. Show rendered line. Then run `bash tests/test-statusline.sh`.

## Reset or uninstall

- Reset: remove only active profile's `statusline.json`; built-in defaults resume.
- Uninstall: remove `statusLine` only when its command points to this plugin or legacy Braisenly dispatcher, remove active profile's `statusline.json`, and disable plugin entry. Preserve every unrelated setting.

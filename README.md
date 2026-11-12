# Claude Status Line

Claude Code plugin with configurable Bash and PowerShell status-line renderers, a configuration skill, and the `/drift-control` menu. This repository is the plugin's only source and its own marketplace.

## Install

```bash
claude plugin marketplace add zautke/claude-statusline
claude plugin install claude-statusline@claude-statusline
```

Then point the status line at the stable launcher. Run the installer from the installed plugin, or ask the `configure-statusline` skill to install it:

```bash
bash ~/.claude/plugins/cache/claude-statusline/claude-statusline/*/scripts/install.sh   # macOS / Linux
```

```powershell
pwsh -NoProfile -File (Resolve-Path "$HOME\.claude\plugins\cache\claude-statusline\claude-statusline\*\scripts\install.ps1")   # Windows
```

The installer copies a small launcher to `~/.claude/claude-statusline/` and sets `statusLine.command` to it. On each render the launcher reads `installed_plugins.json` and runs the installed version's renderer, so `claude plugin update` reaches the status line without another settings edit. If the plugin is not installed, the status line shows `claude-statusline: not installed`.

## Configure

Per-profile configuration lives at `${CLAUDE_CONFIG_DIR:-~/.claude}/statusline.json`. Start from `statusline.example.json`; omitting the file uses defaults. Segment order controls output order and omitted segments are hidden.

Fable usage is read from a machine-global cache. Refresh runs detached and uses `CLAUDE_CODE_OAUTH_TOKEN`, macOS Keychain service `Claude Code-credentials`, then the active profile's `.credentials.json`. Tokens are never cached or logged.

## Reset times

Each 5h and 7d slot shows when its limit resets, then a click hint (clock values below are UTC; you see your local time):

```text
5h [██░░░░░░░░░░] (20%) ↻22:13 ⊟◂ ● 7d [████░░░░░░░░] (30%) ↻M02 ⊟◂      clock (default)
5h [██░░░░░░░░░░] (20%) ↻2h13m ⊟◂ ● 7d [████░░░░░░░░] (30%) ↻4d6h ⊟◂     countdown
```

- `clock`: 5h as 24h local `↻HH:MM`; 7d as day code plus 24h hour, `↻F14`. Day codes: `M T W R F SA SU` (Mon to Sun, `R` is Thursday). Reset times are rounded up to the next minute.
- `countdown`: `↻2h13m`, `↻42m`, `↻4d6h`. When the status line is claude-statusline's own, selecting it sets `statusLine.refreshInterval` to 60 if none is set, and leaving it removes a `refreshInterval` of exactly 60 (any other value is kept). With any other status line, set `refreshInterval` to 60 or less yourself.
- `⊟◂` means reset times are shown, `⊞◂` that they are hidden. The `resets` fit-ladder step drops the reset text first when the line does not fit.
- Config keys in `statusline.json`: `resets` (bool, default `true`) and `resets_format` (`clock` or `countdown`).

Three ways to toggle, all writing only those two keys:

| How | Does | Needs |
| --- | --- | --- |
| `/statusline-resets [toggle\|on\|off\|clock\|countdown\|status]` | Instant, no model turn | Claude Code 2.1.286 or later |
| `ctrl+x r` | Same as `/statusline-resets toggle`; bound by the installer in `keybindings.json` | Claude Code 2.1.286 or later |
| Ctrl/Cmd+click on the 5h or 7d slot | Toggles on/off | A terminal with hyperlink support and a registered handler (below); no link under tmux, WSL or `NO_COLOR`, or when the config dir is neither `~/.claude` nor `~/.claude-<name>` |

On older Claude Code, edit `statusline.json` or run `scripts/resets-toggle.sh` (`resets-toggle.ps1` on Windows) with `--get`, `--set on|off|toggle` or `--format clock|countdown`.

Click handler by OS (registered by the installer; the `claude-statusline://` URL is validated by full match and passed as a quoted argument, never interpolated into a shell command):

- **Windows**: a `HKCU\Software\Classes\claude-statusline` registry entry, and `claude-statusline` added to Windows Terminal `safeUriSchemes` (the installer prints the settings file it edited; `-W` / `--no-wt-scheme` skips it and prints the line to add yourself).
- **macOS**: a small applet, `~/Applications/claude-statusline-toggle.app`.
- **Linux**: `~/.local/share/applications/claude-statusline-toggle.desktop`, set as the `x-scheme-handler/claude-statusline` default through `xdg-mime` (skipped when `xdg-mime` is missing).
- **WSL and tmux**: no click; use the command or the key.

Remove all of it by running `bash scripts/install.sh --uninstall` (`pwsh -NoProfile -File scripts/install.ps1 --uninstall` on Windows) from the plugin directory, or via the plugin cache path shown under Install. It removes only what the installer added: the key binding, the click handler, the Windows Terminal entry (Windows only; left alone if the install used `-W`), the launcher directory, an owned `statusLine`, and the plugin entry.

## Checks

```bash
bash tests/test-package.sh
bash tests/test-launch.sh
bash tests/test-statusline.sh
bash tests/test-drift-control.sh
claude plugin validate . --strict
```

```powershell
pwsh -NoProfile -File tests/test-package.ps1
pwsh -NoProfile -File tests/test-launch.ps1
pwsh -NoProfile -File tests/test-statusline.ps1
pwsh -NoProfile -File tests/test-drift-control.ps1
```

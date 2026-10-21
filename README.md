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

## Checks

```bash
bash tests/test-package.sh
bash tests/test-launch.sh
bash tests/test-statusline.sh
claude plugin validate . --strict
```

```powershell
pwsh -NoProfile -File tests/test-launch.ps1
```

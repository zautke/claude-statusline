# Braisenly Status Line

Claude Code plugin containing configurable Bash and PowerShell status-line renderers plus a configuration skill.

Clone this repository to `~/braisenly-statusline`, enable `braisenly-statusline@dot-agents`, then set Claude Code's command to:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/braisenly-statusline/scripts/statusline-dispatcher.sh"
  }
}
```

Or install into the active profile without copying renderer files:

```bash
bash ~/braisenly-statusline/scripts/install.sh
```

Per-profile configuration lives at `${CLAUDE_CONFIG_DIR:-~/.claude}/statusline.json`. Start from `statusline.example.json`; omitting the file uses defaults. Segment order controls output order and omitted segments are hidden.

Fable usage is read from a machine-global cache. Refresh runs detached and uses `CLAUDE_CODE_OAUTH_TOKEN`, macOS Keychain service `Claude Code-credentials`, then the active profile's `.credentials.json`. Tokens are never cached or logged.

Run checks:

```bash
bash tests/test-statusline.sh
bash scripts/statusline-dispatcher.sh --help
claude plugin validate . --strict
```

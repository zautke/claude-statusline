# REMEMBER (append-only)

## 2026-10-15

- Claude Code pipes statusline stdout; `tput cols`, `stty size`, `/dev/tty` fail inside the script. `COLUMNS`/`LINES` are exported by Claude Code (v2.1.153+). The renderer reads the Claude process's pty with `stty size </dev/ttysN` first (same user, no controlling tty needed), then falls back to `COLUMNS`.
- Claude Code draws the row ~3 cells narrower than `COLUMNS` and truncates overflow with `…`. Budget = `COLUMNS - 3 - fit.reserve`.
- Claude Code trims leading whitespace per statusline row. Leading pad must be U+2800 (braille blank).
- Claude Code re-runs the script on a `statusLine.command` change immediately; `--settings <file>` is read once at launch and not watched; `.claude/settings.local.json` and `~/.claude/settings.json` are hot-reloaded (~1.7 s). Resize (SIGWINCH) is not a trigger (anthropics/claude-code#76988, open).
- `ReadConsoleInput` on Windows consumes the shared input queue; a watcher must poll `GetConsoleScreenBufferInfo` only.
- Render loop must be fork-free in bash: command substitutions in the fit loop cost seconds; return through variables (`BAR`, `PCT`, `N`, `P`).

## 2026-10-16

- Bash 3.2 (macOS /bin/bash): no `declare -A`; `printf '%d' "'$ch"` gives only the first byte of a multibyte char; glob patterns containing multibyte chars mangle strings in a UTF-8 locale; `${#s}` counts bytes with no UTF-8 locale. Use byte-wise decoding under a function-local `LC_ALL=C` and pin `LC_ALL` at startup.
- braisenly-plugins `main` is a publish mirror (`chore(publish): sync from dot-agents`). The statusline directory left dot-agents on 2026-09-20; publish behaviour for the vendored copy is unverified.
- Release rule for plugins: plain SemVer `X.Y.Z`, tag `braisenly-statusline@X.Y.Z`, CHANGELOG entry. Org 4-part stamp and `v` prefix do not apply (kb addendum 2026-10-16).
- `tests/test-package.sh` must never assert a literal version; it is the release gate.

## 2026-10-20

- Plugin versions are plain SemVer with `{name}@{version}` tags (kb org policy, 2026-10-16 addendum). Never apply the org 4-part stamp to `plugin.json`. This was repeated on 2026-10-20 and caught before review.
- Claude Code shows the status line `COLUMNS - 4` cells wide. Budget = `COLUMNS - STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS - fit.reserve`.
- Live tests must run in the user's own terminal (adagio: Windows Terminal Preview `PowerShell` profile, launched via `shell:AppsFolder\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe!App`), never in a window spawned from the agent shell. That shell carries `NO_COLOR=1` and session variables.
- `.sh`/`.ps1` twins need twin tests. The pwsh renderer had silently ignored segments, labels, widths and `NO_COLOR`.
- A user-level `~/.claude/commands/drift-control.md` shadows the plugin command; the plugin's stays reachable as `/claude-statusline:drift-control`.

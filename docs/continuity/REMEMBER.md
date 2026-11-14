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

## 2026-10-21

- The release rule was already in PLANS.md ("plain SemVer … per kb addendum 2026-10-16"), and the 4-part stamp was still applied on 2026-10-20. Read PLANS "Current facts" before any version change.
- `claude-profile` homes symlink `settings.json` to dot-agents `settings/global/claude-settings.json`. Anything `statusLine` points at must stay until that SSoT, and every checked-out dot-agents branch on each host, point elsewhere.
- Tests compare renders taken seconds apart, so the disk free value can change between them: mask the disk segment number (`DISK_SEGMENT_NUMBER_INTEGER_WITH_OPTIONAL_ONE_DECIMAL`).
- bash 5.2 keeps a backslash in the replacement half of `${var//pat/rep}`; escape `/` only in the pattern.

## 2026-11-09

- Before claiming work is lost, check: `git branch -a`, `git worktree list`, `git stash list` on every clone on both hosts (incl. `~/.claude/plugins/marketplaces/claude-statusline`), `gh pr list --state all`, `gh api repos/zautke/claude-statusline/events`, both hosts' `~/.claude/history.jsonl`, user messages inside every transcript (Remote Control prompts can skip history.jsonl), and Codex sessions. On 2026-11-09 all were empty for public-release work.
- No Claude Code session had ever run with cwd `/Users/derp/claude-statusline` on largo before 2026-11-09; earlier largo work ran in `~/braisenly-statusline` (deleted 2026-10-21).
- adagio's `~/.claude/history.jsonl` stopped recording after 2026-11-08 12:49 although sessions ran later; do not treat its absence of prompts as proof.

## 2026-11-13

- Private-use codepoints from U+100000 up are taken by Apple SF Symbols on macOS; a terminal draws Apple's icons there instead of a custom font. Nerd Fonts hold U+E000–F8FF and U+F0001–F1AF0. The ring font uses U+FFF00–U+FFF64 (UTF-8 `F3 BF BC+p/64 80+p%64`).
- A font built with fontTools `FontBuilder` gets a junk PostScript name (`font0000…`) unless `psName` is passed to `setupNameTable`.
- Spike generator parameters: em 1000, ascent 800, descent 200, advance 1200, ring centre (600, 300), outer radius 480, inner 290, arc as line segments every ~3°, TrueType outlines, family `Statusline Rings`.
- A font installed while a terminal is running: a fresh process (Terminal.app, a Swift CoreText check) resolved the fallback at once; the already-running iTerm2 3.7.7 did not. Restart is unverified as the cure.
- iTerm2 "Special Exceptions" (codepoint range → font) is only offered when the profile's non-ASCII font switch is on; the user's profiles have it off (`Normal Font` = `VictorMonoNFM-Regular 13`).
- A window opened by `osascript … create window with default profile command` runs macOS `/bin/bash` 3.2 for `#!/usr/bin/env bash`; `printf '\U…'` prints literally there.
- largo had 2.1 GiB free on 2026-11-13.

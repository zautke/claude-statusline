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

## 2026-11-14

- **Correction to 2026-11-13:** a newly installed font loads in an already-running iTerm2; no restart is needed. The earlier boxes came from the missing PostScript name and, by inference from two incidents, from printing the codepoints before macOS had registered the font: iTerm2 appears to cache a failed glyph lookup per codepoint until it restarts. Install, wait ~5 s, then print. A dedicated test is still owed.
- iTerm2 3.7.7 draws a COLR/CPAL colour-font glyph at a non-emoji codepoint as a coverage mask in the SGR foreground: palette alpha becomes opacity, palette RGB is discarded, and the glyph is scaled into one cell.
- iTerm2 draws glyph overflow into the neighbouring cell on both sides and does not repaint a cell's background over a neighbour's overflow. Draw order between overlapping glyphs is undefined.
- Claude Code 2.1.325 keeps per-character SGR colours for adjacent private-use codepoints, counts each as one cell, and keeps one as the first or last character of a status line row.
- Grey track rule: background luminance `Yb` (WCAG); `Yg = 1.75 (Yb + 0.05) − 0.05` when `Yb < 0.179`, else `(Yb + 0.05)/1.75 − 0.05`; convert back through the sRGB transfer function; grey channel value for the user's background (14, 42, 53) is 76.
- The user's iTerm2 background measures (14, 42, 53) from a screenshot. The same hex set through the iTerm2 Python API measured (21, 41, 52). Read backgrounds from the terminal or a pixel.
- iTerm2 Python API on largo: `EnableAPIServer = 1`, `~/Library/Application Support/iTerm2/disable-automation-auth` present; `uv run --with iterm2` connects with no prompt. `Window.async_create(profile_customizations=LocalWriteOnlyProfile)` themes one window without a saved profile; it cannot be combined with `command`, send the command as text after ~6 s.
- Private-use blocks used by lab fonts: U+FFA00–FFAE4 (Lab3, good), U+FFB00–FFBE4 (boxes in the iTerm2 process of 2026-11-14), U+FFC00–FFCE4 (Lab2), U+FFD00–FFEE4 (Lab1), U+FFF00–FFF64 (spike).
- Terminal.app's login shell on largo takes more than 20 s to reach a command passed by `do script`; unsuitable as a quick control.
- `pkill -f "settings <full path>"` can miss the throwaway Claude process; match on the settings file name and confirm with `pgrep`.

## 2026-11-15

- **Correction to 2026-11-14 (E-003 "1 px step"):** the step was a wrong cell width, not pixel snapping. The remainder glyph's circle centre must equal the terminal font's cell width per 1000 em (Victor Mono Nerd Font Mono: unitsPerEm 1100, advance 600 → 545.5; line height 1409, cell centre 386 above the baseline). The arc glyph, anchored at its own cell's left edge, does not depend on it.
- The user's live status line on largo runs from the `radial` worktree through the symlink `~/claude-statusline-wt/claude-statusline`. Deleting either breaks it. Backups: `~/.claude/settings.json.bak-pre-ring-2026-11-14`, `~/.claude/statusline.json.bak-pre-ring-2026-11-14`.
- The resize watcher only bumps a `statusLine.command` matching `(claude|braisenly)-statusline/scripts/statusline-(dispatcher|command|launch).(sh|ps1)`.
- The renderer reads the invoking Claude session's pty width and ignores `COLUMNS` unless `CLAUDE_STATUSLINE_NO_LIVE_COLS=1` is set; width tests run from inside a Claude session need it.
- iTerm2 draws a fallback glyph wherever its ink lies, at least three cells left or right of its own cell.
- `tests/test-statusline.sh` reads live disk free space; a run can fail one ladder case when free space crosses a unit boundary mid-run.
- At the red end of the heat ramp the arc (181, 4, 0) and a grey-76 track have almost the same luminance; the notch, not the colour, makes the tip readable.

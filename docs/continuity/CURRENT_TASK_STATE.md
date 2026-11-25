# CURRENT TASK STATE

Updated 2026-11-24 (session, largo). Branch `docs/continuity-2026-11-09` rebased onto `development` `e811a8d` (2.3.1); stale release facts refreshed. Two open threads.

> ## ⛔ STANDING HANDOFF ORDER — if this session runs on **adagio** (Windows), do this first
>
> **To the agent reading this on adagio:** you are the continuation of the largo session that built the ring indicators. The user's standing order (2026-11-14) is: **test the ring scheme in Windows Terminal.** Do not wait to be asked twice; when the user's first prompt refers to the handoff, the rings, or Windows Terminal, execute the steps below. If the first prompt is about something else, say in one line that this order is pending and carry on with their request.
>
> **Hard rules on adagio:** every command through the **PowerShell tool** (never Bash, never `pwsh -Command` inside Bash; if the session has no PowerShell tool, stop and tell the user). Scripts are `.ps1` with a `Usage` function, short and long switches, no positional arguments. Drive only windows you open yourself, on the right half of the monitor (`scripts/window-right-half.ps1` pattern from mdeditor), verify the window title before every action, close them when done.
>
> **Read first, in this order:**
> 1. kb ledger `projects/claude-statusline/laboratory/claude-statusline-radial-indicators-laboratory-ledger-append-only` — the method, E-001…E-005, the section **"Desk analysis — Windows Terminal feasibility"** with experiments **W-001…W-004**, and E-007.
> 2. kb `projects/claude-statusline/claude-statusline — Retrospective 2026-11-14 (radial ring indicators, teaching narrative)`.
> 3. The rest of this file (Thread A).
>
> **Get the material:** `git fetch origin`, then a worktree for `feat/radial-indicators` (draft PR #17). Everything is in `lab/radial/`: prebuilt fonts in `lab/radial/fonts/`, generators `mklab2.py` / `mklab4.py` (Python + fontTools; only needed to rebuild), bash demos to port (`demo2.sh`, `sl-ring.sh`), `grey.py`, the pixel scanner `evidence/blobs.py`.
>
> | Font file | Family | Codepoints (p = 0..100) | For |
> |---|---|---|---|
> | `StatuslineRingsLab3.ttf` | Statusline Rings Lab3 | remainder U+FFA00 + p, arc U+FFA80 + p (both overhang into the neighbour cell; built for a 600-unit cell) | W-002, the iTerm2 method as is |
> | `StatuslineRingsLab5.ttf` | Statusline Rings Lab5 | remainder U+FF000 + p, arc U+FF080 + p; cell 545 (Victor Mono), larger ring, notches. The font the bash renderer currently emits | W-002 if the Windows Terminal font has a ~545-unit cell; otherwise rebuild with `mklab2.py -x <cell>` |
> | `StatuslineRingsLab4a.ttf` | Statusline Rings Lab4a | mono halves: left U+FF600 + p, right U+FF680 + p. Colour halves: left U+FF800 + p, right U+FF880 + p. Track grey 128 at alpha 0.35 | W-001 (mono), W-003 (colour, translucent track) |
> | `StatuslineRingsLab4b.ttf` | Statusline Rings Lab4b | mono left U+FF400 + p, right U+FF480 + p; colour left U+FF500 + p, right U+FF580 + p. Track opaque grey 60 | W-003 on a dark background |
> | `StatuslineRingsLab4c.ttf` | Statusline Rings Lab4c | mono left U+FF200 + p, right U+FF280 + p; colour left U+FF300 + p, right U+FF380 + p. Track opaque grey 190 | W-003 on a light background |
>
> Half glyphs: emit left codepoint then right codepoint, **both** with the heat colour as SGR foreground; nothing overhangs. In PowerShell a codepoint is `[char]::ConvertFromUtf32(0xFF600 + $p)`; heat colour is the `heat_rgb` twin already in `scripts/statusline-command.ps1`.
>
> **Run the loop exactly as on largo: append the proposal to the kb ledger before each run, the observation after it, with measured pixel colours.**
>
> - **W-001** Install the fonts per user (`%LOCALAPPDATA%\Microsoft\Windows\Fonts` plus the `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts` value), **wait, then** print. Do the mono halves render with the ring font absent from `font.face`? If not, add `Statusline Rings Lab4a` (and the others) as extra families in the profile's `font.face` in Windows Terminal `settings.json` (back the file up first, restore it at the end unless the user says keep), and note whether a Windows Terminal restart is needed. Record the Windows Terminal version.
> - **W-002** Lab3 two-cell overhang with a neutral grey + heat colour. Observe: drawn across cells, clipped, or recoloured by column (prediction from microsoft/terminal#20890: left half all grey, right half all heat colour).
> - **W-003** Lab4a/4b/4c colour halves. Are palette colour and palette alpha honoured, does the arc layer take the SGR foreground, is there a seam at the cell boundary? Check `font.colorGlyphs`.
> - **W-004** The winner inside a real Claude Code status line on adagio (throwaway `claude --settings <file>` in your own window; stop the process afterwards and verify it is gone).
> - Then, if time: E-007 (combining mark), and the grey rule across two or three Windows Terminal colour schemes.
>
> **Finish:** screenshots into `lab/radial/evidence/` (prefix `w`), commit and push to `feat/radial-indicators`, update the ledger's standing summary with a Windows column, refresh this continuity set (remove this order once W-001…W-004 are logged), tell the user which mechanism the product should use on Windows.

## Thread A (active): radial percentage indicators — laboratory phase, live trial running

**State (2026-11-15):** the solid-colour ring with a neutral grey track is live in the user's own status line on largo and the user approved its look. Experiments E-001…E-009 and live trial L-001 are in the kb ledger. **Next: E-006 (how the configuration step learns the background) and the cell-geometry input; the Windows round is the standing order above.**

- **Ledger (source of truth):** kb `projects/claude-statusline/laboratory/claude-statusline-radial-indicators-laboratory-ledger-append-only`. Append a proposal before every run and an observation after it. Related kb notes: the teaching retrospective of 2026-11-14 and "Remote sessions (ssh from iTerm2 into adagio) - which rules apply and in what order".
- **Current mechanism:** two code points in two cells. Remainder (unfilled part) U+FF000 + p in grey, arc U+FF080 + p in `heat_rgb(p)`; the shapes tile; a 9° background notch at the arc start and tip marks the fill boundary. Font `StatuslineRingsLab5.ttf` (`mklab2.py --tile -x 545 -y 386 -u 615 -i 346 -v -9`).
- **Two per-user inputs the product needs:** (1) terminal background → grey by the WCAG contrast-ratio rule, ratio 1.75 (`lab/radial/grey.py`); (2) **cell geometry of the terminal font**: remainder centre x = advance/unitsPerEm × 1000 (545 for Victor Mono), centre y = ascent − line height/2 (386). A font built for another cell width is off by pixels.
- **Renderer:** `scripts/statusline-command.sh` on `feat/radial-indicators` has `style: "bar" | "ring"` and `ring.grey` (default 76); with `ring` the fit ladder is walked with rings kept and they drop last. Laboratory wiring: lab code points, stored grey. PowerShell renderer untouched. Head `c4cb2cb` (carries a duplicate of the token-count fix already merged as #20 — git will drop it on rebase), draft PR #17. **CI red since 2026-11-17** (ubuntu/plugin/pwsh fail in ~2 s; macos cancelled at 15 min); logs expired, cause not yet diagnosed.
- **Rejected by the user:** gradient along the arc by dithered four-cell tiling (E-009). Do not re-wire a visual variant into the live renderer without showing a mock-up first.
- **Live trial on largo (user's real config, keep unless told otherwise):** `~/.claude/settings.json` `statusLine.command` = `bash /Users/derp/claude-statusline-wt/claude-statusline/scripts/statusline-dispatcher.sh` (symlink `~/claude-statusline-wt/claude-statusline` → `radial`, so the resize watcher recognises the path); `~/.claude/statusline.json` has `"style": "ring", "ring": {"grey": 76}`. Revert: copy `~/.claude/settings.json.bak-pre-ring-2026-11-14` and `~/.claude/statusline.json.bak-pre-ring-2026-11-14` back. **Removing the `radial` worktree or the symlink breaks the user's status line.**
- Installed on largo: `~/Library/Fonts/StatuslineRings.ttf`, `Lab1`…`Lab6`. Only Lab5 is in use.
- **Stale documents:** `docs/superpowers/specs/2026-11-13-radial-indicators-design.md` and `docs/superpowers/plans/2026-11-14-radial-indicators.md` describe a single-glyph ring with no track. Do not execute that plan.
- Not tested: Windows Terminal, ssh sessions (S-001…S-004), `NO_COLOR` form, combining marks (E-007), other terminal fonts and sizes.

**How to run a lab round:** `cd ~/claude-statusline-wt/radial/lab/radial`; build with `uv run -q --with fonttools python mklab2.py …`, copy to `~/Library/Fonts`, **wait 5 s**, use a fresh private-use block; themes `uv run -q --with iterm2 python themes.py -o evidence`; measure with Pillow; renderer tests need `CLAUDE_STATUSLINE_NO_LIVE_COLS=1`.

## Thread B (paused since 2026-11-09): public release

Unchanged. Agents were stopped with no output. Resume exactly from `HANDOFF-public-release.md`. Repo still PRIVATE; the visibility change waits for an explicit user OK.

- `main` = `0e4c3eb` (still 2.0.0 — `development` has not been promoted since); `development` = `e811a8d` (2.3.1, PRs #16/#18/#19/#20 merged). Latest tag remains `claude-statusline@2.0.0`; 2.1.0/2.2.0/2.3.1 were released without tags (release-record gap, unverified).
- Worktrees `readme` (`docs/public-readme`) and `simplify` (`refactor/simplify-codebase`) are at `96805ad`, behind `development`; rebase before re-spawning agents.
- **Claude Code 2.1.326 (2026-11-16) re-renders the status line on terminal resize** (changelog: "Fixed a custom status line keeping its old width … after a terminal resize"; fixes anthropics/claude-code#107291; closes #76988, where the resize-watch measurements were posted). The `fit.resize_watch` sidecar (~2 s settle, rewrites `statusLine.command` nonce in settings.json) is now redundant and can be removed; user chose to report only, not implement yet (2026-11-24).
- Main checkout `/Users/derp/claude-statusline` is on `docs/continuity-2026-11-09`.

**Protocol reminders:** read kb `protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main` before any bump. Merge into `development` = MINOR+1, promotion to `main` = MAJOR+1, exactly three numbers. Review rounds capped at 3.

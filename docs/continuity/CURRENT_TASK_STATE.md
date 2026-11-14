# CURRENT TASK STATE

Updated 2026-11-14 ~12:35 MST (session a8831aae, largo, claude-fable-5-2). Two open threads.

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
> | `StatuslineRingsLab3.ttf` | Statusline Rings Lab3 | remainder U+FFA00 + p, arc U+FFA80 + p (both overhang into the neighbour cell) | W-002, the iTerm2 method as is |
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

## Thread A (active): radial percentage indicators — laboratory phase

**State:** ring with a neutral empty track and a heat-coloured fill works in iTerm2 and inside a real Claude Code status line, on six themes. Work runs as a propose → log → observe → log loop in the kb laboratory ledger. **Next experiment: E-006, how the configuration step learns the terminal background.**

- **Ledger (source of truth for all experiments):** kb `projects/claude-statusline/laboratory/claude-statusline-radial-indicators-laboratory-ledger-append-only`. Holds the foreground transcript (Part A), E-001…E-005 with predictions and measured results, the mechanism table, six procedure rules, and draft v1 of the configuration rule. Append a proposal before every run and an observation after it.
- **Winning mechanism (M7-tiled):** each ring is two codepoints in two neighbouring cells. First: the unfilled remainder of the ring, SGR foreground = neutral grey. Second: the filled arc, SGR foreground = `heat_rgb(p)`. The shapes tile and never overlap. 202 glyphs. Lab font `StatuslineRingsLab3.ttf`: remainders U+FFA00 + p, arcs U+FFA80 + p, advance 600, circle centres x = 600 and x = 0, y = 300, radii 540 / 330.
- **Neutral colour:** pure grey from the WCAG contrast-ratio formula against the background luminance (`lab/radial/grey.py`), lighter when background luminance < 0.179, darker otherwise. Default ratio **1.75** (agent's call, delegated by the user), useful range 1.5–2.5.
- **User's wider goal:** the public release gets an agentic live-configuration skill that adapts the track to the user's terminal theme; the ledger is its source material.
- Worktree `~/claude-statusline-wt/radial`, branch `feat/radial-indicators`, draft PR #17, head `e56988c`. Lab code and evidence in `lab/radial/` (`mklab.py`, `mklab2.py`, `demo.sh`, `demo2.sh`, `sl-ring.sh`, `grey.py`, `themes.py`, `evidence/`). Built `.ttf` files are git-ignored there.
- **Stale documents, not yet revised:** `docs/superpowers/specs/2026-11-13-radial-indicators-design.md` and `docs/superpowers/plans/2026-11-14-radial-indicators.md` describe a single-glyph ring with no track. Do not execute that plan as written. No execution method was chosen for it.
- Installed on largo, kept on purpose: `~/Library/Fonts/StatuslineRings.ttf`, `StatuslineRingsLab1.ttf`, `Lab2`, `Lab3`.
- Not tested: Windows Terminal on adagio (needs a session with the PowerShell tool); `NO_COLOR` form of the ring.

**Next:** log the E-006 proposal in the ledger, then run it: OSC 11 query from an ordinary shell, and the iTerm2 Python API / profile route; compare each with a screenshot pixel. After that: Windows Terminal, the 1 px step at the cell boundary, `NO_COLOR`, then revise the design doc and plan from the ledger.

**How to run a lab round:** `cd ~/claude-statusline-wt/radial/lab/radial`; fonts `uv run -q --with fonttools python mklab2.py -o X.ttf -n LabN -t <hex> -r <hex> --tile`, copy to `~/Library/Fonts`, **wait 5 s**, use a fresh private-use block; themes `uv run -q --with iterm2 python themes.py -o evidence`; measure with Pillow (`evidence/blobs.py`).

## Thread B (paused since 2026-11-09): public release

Unchanged. Agents were stopped with no output. Resume exactly from `HANDOFF-public-release.md`. Repo still PRIVATE; the visibility change waits for an explicit user OK.

- `main` = `0e4c3eb`; `development` = `d78076e`; latest tag was `claude-statusline@2.0.0` on 2026-11-09 (not rechecked).
- Worktrees `readme` (`docs/public-readme`) and `simplify` (`refactor/simplify-codebase`) are at `96805ad`, behind `development`; rebase before re-spawning agents.
- Main checkout `/Users/derp/claude-statusline` is on `docs/continuity-2026-11-09`.

**Protocol reminders:** read kb `protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main` before any bump. Merge into `development` = MINOR+1, promotion to `main` = MAJOR+1, exactly three numbers. Review rounds capped at 3.

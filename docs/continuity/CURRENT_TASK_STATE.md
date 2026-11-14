# CURRENT TASK STATE

Updated 2026-11-14 ~12:15 MST (session a8831aae, largo, claude-fable-5-2). Two open threads.

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

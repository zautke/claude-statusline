# CURRENT TASK STATE

Updated 2026-11-13 ~19:45 MST (session a8831aae, largo, claude-fable-5-2). Two open threads.

## Thread A (active): radial percentage indicators

**State:** design approved by the user; spike half done; **blocked on the user restarting iTerm2** (the restart kills the session that asks for it).

- Worktree `~/claude-statusline-wt/radial`, branch `feat/radial-indicators` off `development` `d78076e`, draft PR #17. Only commit so far: the design doc `docs/superpowers/specs/2026-11-13-radial-indicators-design.md`. **The doc still says U+100000 and has not been updated with the spike findings below.**
- Approach: a custom font with 101 ring glyphs (0–100 %, arc from 12 o'clock clockwise), coloured by the existing `heat_rgb`; config `style: bar | ring`, default `bar`.
- Spike results (largo):
  - Fresh Terminal.app drew the coloured rings through plain system font fallback. Proven.
  - iTerm2 3.7.7 (running since before the font install) shows `[?]` boxes. CoreText in a fresh process resolves U+FFF32 to `StatuslineRings-Regular`, so a stale font list in the running iTerm2 is the leading theory. Unverified.
  - U+100000+ collides with Apple SF Symbols. Range moved to **U+FFF00–U+FFF64**.
  - Rings render one cell wide and small; glyph geometry needs work.
  - The font needs an explicit PostScript name.
- Not tested: Windows Terminal on adagio (the session had no PowerShell tool); Claude Code's cell-width handling of these codepoints inside the real status line.
- Left on largo: spike font at `~/Library/Fonts/StatuslineRings.ttf`. Spike scripts `mkrings.py` and `demo.sh` are in the session scratchpad `/private/tmp/claude-503/-Users-derp-claude-statusline/a8831aae-51e8-44ff-8ce8-7651c9a8b3e5/scratchpad/` and may be gone; the generator is ~60 lines of fontTools (`uv run --with fonttools`), parameters in REMEMBER 2026-11-13.

**Next:** after the iTerm2 restart, print a few ring codepoints with heat colours in a new iTerm2 window and screenshot it. Rings shown → update the design doc with the findings, test Windows Terminal from a session that has the PowerShell tool, test inside the real status line, then write the implementation plan. Boxes persist → iTerm2 needs an explicit font mapping (Special Exceptions requires the non-ASCII font switch) and the design goes back to the user.

## Thread B (paused since 2026-11-09): public release

Unchanged. Agents were stopped with no output. Resume exactly from `HANDOFF-public-release.md`. Repo still PRIVATE; the visibility change waits for an explicit user OK.

- `main` = `0e4c3eb`; `development` is now `d78076e` (PR #16 `feat/statusline-resets` merged since the handoff); latest tag was `claude-statusline@2.0.0` on 2026-11-09 (not rechecked).
- Worktrees `readme` (`docs/public-readme`) and `simplify` (`refactor/simplify-codebase`) are still at `96805ad`, behind `development`; rebase before re-spawning agents.
- Main checkout `/Users/derp/claude-statusline` is on `docs/continuity-2026-11-09`.

**Protocol reminders:** read kb `protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main` before any bump. Merge into `development` = MINOR+1, promotion to `main` = MAJOR+1, exactly three numbers. Review rounds capped at 3.

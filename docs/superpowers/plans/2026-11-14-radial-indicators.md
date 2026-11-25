# Radial Indicators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user switch every percentage indicator in the status line from a heat-map bar to a ring whose arc is the percentage in 1 % steps.

**Architecture:** A committed font holds 101 ring glyphs at private-use codepoints. With `"style": "ring"` the renderers emit one coloured ring codepoint plus a space where they emit a bar today; everything else (labels, percent text, fit ladder) is unchanged. The installers copy the font into the user's font directory.

**Tech Stack:** bash (3.2-compatible), PowerShell, jq, Python with fontTools (build time only, via `uv run --with fonttools`).

**Spec:** `docs/superpowers/specs/2026-11-13-radial-indicators-design.md`

## Global Constraints

- Codepoints: ring for percentage `p` is U+FFF00 + `p`, `p` in 0..100. UTF-8 bytes: `F3 BF (BC + p/64) (80 + p%64)`.
- bash emits those bytes with octal or `\x` escapes, never `\U` (macOS `/bin/bash` 3.2).
- Font family `Statusline Rings`, PostScript name `StatuslineRings-Regular`, file `fonts/StatuslineRings.ttf`.
- A ring is counted as one cell and is always followed by one space: two cells per indicator.
- Default `style` is `bar`. With `style` absent or `bar`, output is byte-identical to today's.
- Ring colour is `heat_rgb(p)` / its PowerShell twin, unchanged. Under `NO_COLOR` the ring carries no colour codes.
- bash and PowerShell produce identical output for identical input.
- The fit loop stays fork-free in bash: no command substitution inside `bar()`.
- Conventional Commits; every commit pushed to draft PR #17.

## Review Focus

1. Percentage that is fractional or out of range (`48.6`, `-3`, `140`): rounds to nearest whole number and clamps to 0..100; never emits a codepoint outside U+FFF00–U+FFF64. Test in Tasks 2 and 3.
2. Narrow terminal with `style: ring`: the fit budget counts each ring as two cells and the row never overflows `COLUMNS - 3`. Test in Tasks 2 and 3.
3. `NO_COLOR` set with `style: ring`: ring present, zero escape sequences. Test in Tasks 2 and 3.
4. Invalid `style` value (`"pie"`, `7`): config is rejected the same way other invalid config values are today. Test in Tasks 2 and 3.
5. Installer run twice, or with the font directory missing: directory created, font replaced, exit 0. Test in Task 4.

---

### Task 1: Ring font generator and committed font

**Files:**
- Create: `scripts/make-ring-font.py`
- Create: `fonts/StatuslineRings.ttf` (generated, committed)
- Test: `tests/test-ring-font.sh`

**Interfaces:**
- Produces: `fonts/StatuslineRings.ttf`; CLI `scripts/make-ring-font.py -o|--output <path>` and `-c|--check <path>` (exit 0 when the font at `<path>` maps exactly U+FFF00..U+FFF64 and has PostScript name `StatuslineRings-Regular`, else exit 1 with one line on stderr).

- [ ] **Step 1: Write the failing test** `tests/test-ring-font.sh`, in the style of `tests/test-package.sh`: asserts `fonts/StatuslineRings.ttf` exists and is larger than 10000 bytes; when `uv` is on PATH, also asserts `uv run -q --with fonttools python scripts/make-ring-font.py --check fonts/StatuslineRings.ttf` exits 0 and that regenerating to a temp path gives a file for which `--check` exits 0.
- [ ] **Step 2: Run** `bash tests/test-ring-font.sh`. Expected: FAIL, font file missing.
- [ ] **Step 3: Write `scripts/make-ring-font.py`.** `#!/usr/bin/env python3`, `argparse` with a usage description, no positional arguments. Geometry, fixed by the spike: units per em 1000, ascent 800, descent 200, advance width 1200, ring centre (520, 300), outer radius 520, inner radius 310, TrueType outlines, arc approximated by a point every 3° or finer. Angle 0 is 12 o'clock, sweep clockwise, sweep = 3.6° × p. Glyph for 0 is empty; glyph for 100 is two closed contours (outer, then inner in the opposite direction). Name table: family `Statusline Rings`, style `Regular`, `psName` `StatuslineRings-Regular`.
- [ ] **Step 4: Generate** `uv run -q --with fonttools python scripts/make-ring-font.py -o fonts/StatuslineRings.ttf`, then run the test. Expected: PASS.
- [ ] **Step 5: Look at it.** Install to `~/Library/Fonts`, print rings for 1, 25, 50, 75, 99, 100 in a freshly started Terminal.app window opened by AppleScript, capture with `screencapture -l <window id>`, read the image. Pass: arcs start at 12 o'clock, run clockwise, 25 is a quarter, 100 is closed, the ring fills most of the line height and does not touch the following character. Adjust radii and regenerate if not. Quit Terminal.app.
- [ ] **Step 6: Commit** `feat(radial): ring font generator and font`.

### Task 2: bash renderer

**Files:**
- Modify: `scripts/statusline-command.sh` (config validation near line 38–42, config reads near line 62, `bar()` near line 179)
- Test: `tests/test-statusline.sh`

**Interfaces:**
- Consumes: codepoint mapping from Global Constraints.
- Produces: config key `style` (`"bar"` | `"ring"`, top level); shell variable `indicator_style`; `bar <pct> <width>` still sets `BAR` and still returns empty when `bars_off` is 1.

- [ ] **Step 1: Write failing tests** in `tests/test-statusline.sh`, using its existing render helper and fixture style:
  - `ring_basic`: config `{"style":"ring"}`, context 48 % → output contains bytes `F3 BF BC B0` followed by a space, and contains no `█` or `░`.
  - `ring_100` / `ring_0`: 100 % → `F3 BF BD A4`; 0 % → `F3 BF BC 80`.
  - `ring_color`: 48 % → the ring is preceded by `\033[38;2;R;G;Bm` with the values `heat_rgb 48` gives.
  - `ring_no_color`: `NO_COLOR=1` → ring bytes present, output contains no `\033`.
  - `ring_clamp`: used percentage `140` → `F3 BF BD A4`; `48.6` → ring for 49 (`F3 BF BC B1`).
  - `ring_fit`: `COLUMNS=60` with all segments → visible width of every row ≤ 57.
  - `ring_bad_style`: config `{"style":"pie"}` → same outcome as the existing invalid-config test.
  - `bar_default_unchanged`: no `style` key → output byte-identical to the existing golden expectation.
- [ ] **Step 2: Run** `bash tests/test-statusline.sh` and `TEST_BASH=/bin/bash bash tests/test-statusline.sh`. Expected: the new tests FAIL, existing tests pass.
- [ ] **Step 3: Implement.** Add `.style` to the jq validation (`null`, `"bar"` or `"ring"`). Read `indicator_style=$(get_cfg '.style' '"bar"')` beside `fit_reserve`. In `bar()`, after the `bars_off` return, branch on `indicator_style == ring`: round and clamp `pct` with shell arithmetic, call `heat_rgb`, build the four bytes with `printf -v` and `\x` escapes computed from the integer (no subshell), set `BAR` to colour + ring + reset + one space. Where the fit loop sums bar widths (the `widths` list near line 347), a ring contributes 2 and is not scaled.
- [ ] **Step 4: Run both test commands.** Expected: all PASS under bash 5 and `/bin/bash` 3.2.
- [ ] **Step 5: Commit** `feat(radial): ring style in the bash renderer`.

### Task 3: PowerShell renderer

**Files:**
- Modify: `scripts/statusline-command.ps1` (`Get-Bar` near line 257, `Get-FitBar` near line 285, `Add-Bar` near line 366, config validation)
- Test: `tests/test-statusline.ps1`

**Interfaces:**
- Consumes: config key `style` and codepoint mapping, exactly as Task 2.
- Produces: `Get-Bar` returns the ring string when style is `ring`.

- [ ] **Step 1: Write failing tests** mirroring every Task 2 test by name, asserting on the codepoint (`[char]::ConvertFromUtf32(0xFFF00 + p)`) rather than bytes.
- [ ] **Step 2: Run** `pwsh -NoProfile -File tests/test-statusline.ps1`. Expected: new tests FAIL.
- [ ] **Step 3: Implement** the same branch in `Get-Bar`; `Get-FitBar` treats a ring as fixed width 2.
- [ ] **Step 4: Run.** Expected: PASS. Then feed one fixture to both renderers with `style: ring` and `NO_COLOR=1` and diff the outputs. Expected: identical.
- [ ] **Step 5: Commit** `feat(radial): ring style in the PowerShell renderer`.

### Task 4: Installers ship the font

**Files:**
- Modify: `scripts/install.sh`, `scripts/install.ps1`
- Modify: `tests/test-install.sh`, `tests/test-install.ps1`, `tests/test-package.sh`, `tests/test-package.ps1`

**Interfaces:**
- Consumes: `fonts/StatuslineRings.ttf`.
- Produces: font at `~/Library/Fonts/StatuslineRings.ttf` (macOS), `${XDG_DATA_HOME:-~/.local/share}/fonts/StatuslineRings.ttf` (Linux, then `fc-cache -f` when present), `%LOCALAPPDATA%\Microsoft\Windows\Fonts\StatuslineRings.ttf` plus the per-user registry value `HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts` → `Statusline Rings (TrueType)` (Windows).

- [ ] **Step 1: Write failing tests** using each install test's existing sandboxed-home pattern: after install the font exists at the platform path and is byte-identical to the repo copy; a second install exits 0; install with the font directory absent creates it. Package tests: `fonts/StatuslineRings.ttf` is in the package file list.
- [ ] **Step 2: Run the four test files.** Expected: new assertions FAIL.
- [ ] **Step 3: Implement** a font-install step in each installer, after the existing file copies. The Windows registry write must be skippable under the test sandbox the same way the installer's other machine-level writes are. The installer prints one line: terminals already running must be restarted before rings appear.
- [ ] **Step 4: Run the four test files.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(radial): install the ring font`.

### Task 5: Docs, live verification, release

**Files:**
- Modify: `statusline.example.json` (add `"style": "bar"`), `README.md` (a "Ring indicators" section: what it looks like, `style: ring`, font install, restart the terminal, Windows Terminal note from Step 2), `CHANGELOG.md`

- [ ] **Step 1: Write the docs.** No screenshot placeholder; capture a real one in Step 3.
- [ ] **Step 2: Windows Terminal on adagio** (PowerShell tool only; stop and report if the session has none). Run `install.ps1`, restart Windows Terminal, render with `style: ring`. If rings show as boxes, add `Statusline Rings` as a second family in the profile's `font.face`, retest, and document the outcome in README. Screenshot before and after.
- [ ] **Step 3: Live verification on largo** per the release protocol: install through `install.sh` on a clean font state (remove the spike font first), restart iTerm2 (hand this to the user if it would end the session), set `style: ring`, exercise the status line in the user's real session, screenshot before and after, resize the window to walk the fit ladder, switch back to `bar`. Record the run in the project's kb run-ledger note.
- [ ] **Step 4: Full suite.** Every `tests/test-*.sh` under bash 5 and `/bin/bash`, every `tests/test-*.ps1`. Expected: all PASS.
- [ ] **Step 5: Mark PR #17 ready**, wait for the review bots, triage each finding against repo rules (max 3 rounds).
- [ ] **Step 6: Release.** Read kb `protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main` first. Merge into `development` = MINOR + 1, three numbers; CHANGELOG entry; write all four release-record surfaces.

# INSTRUCTIONAL INSIGHTS (append-only)

## 2026-10-15

- Stateless re-render makes resize fitting trivial: no snapshot or delta is needed when every render recomputes from live width and live values. Reach for "measure after each step" before designing a delta model.
- Test the real environment, not the shell you happen to have: the statusline runs under whatever `bash` Claude Code finds, and CI runs macOS `/bin/bash` 3.2. Add a `TEST_BASH` knob and run the suite under both.
- A review bot will produce findings forever. Triage, batch, cap rounds. Protocol now in memory and kb.
- Hosted review subagents need a hard deadline enforced by the caller; a prompt-level time box was ignored twice. Stop at the box and fall back to inline review plus a synchronous external model.
- Read the release protocol before the merge, not after the question. The cost of skipping it was two extra PRs, two tags, and a changelog done twice.

## 2026-10-16

- When a protocol collides with an external mandate (marketplace version format), the mandate wins; record the override in the protocol itself so the next agent does not re-derive it.
- Verify "bot says X is unsupported" with the actual binary before fixing (here it was real: `declare -A` on Bash 3.2), and keep the reproduction command in the commit message.

## 2026-10-21

- The two insights above (read the release protocol first; when an external mandate wins) were on file and still went unread at the onset of the next session. Load this file and PLANS "Current facts" before planning, not after a reviewer catches it.
- Twins (`.sh` / `.ps1`) need twin tests. The pwsh renderer silently ignored four config features until a PowerShell test suite existed.
- Turn a named algorithm into a map test: per-step effect plus engagement order at threshold widths. Then mutation-check the suite (swap two steps; the suite must fail).

## 2026-11-09

- "Find the in-flight work" is a search across every store, ending in a clear negative with the evidence list. A thorough negative lets the user decide to restart instead of waiting for work that was never saved.
- Run doc writing and code simplification in separate worktrees, and constrain the simplifier to byte-identical output and an unchanged config schema, so the README written in parallel stays true.

## 2026-11-13

- Spike before planning when the design rests on terminal behaviour: 20 minutes of live screenshots overturned three design assumptions (codepoint range, glyph width, escape syntax).
- Test a font change in a fresh process and in the long-running one; they can disagree, and only the fresh one tells you about the font.
- To screenshot a terminal without disturbing the user: open your own window by AppleScript, capture it by window id with `screencapture -l`, close it by the same id.
- Check a private-use range against the fonts already on the machine before choosing it; "private" ranges are shared by convention only.

## 2026-11-14

- Write the prediction before the run. Three of five experiments contradicted a prediction, and the written prediction is what turned each surprise into a finding instead of a shrug.
- When two glyphs must share a picture, make them tile instead of stack. Removing the overlap removed the dependency on renderer draw order.
- Ask what is a pure function of what. The track colour needed only the background luminance, which collapsed a theme-matching problem into one closed-form number.
- A run that fails for a procedural reason is logged as a fault with its cause, then repeated on clean state (fresh codepoints); it is not counted as a result.
- Put several questions into one laboratory font (control block plus variants) so a single run separates "font not found" from "feature not supported".
- Measure pixels. "Looks grey-green" became "foreground at 35 % opacity, exactly" only after reading the values.
- A plan written before a requirement lands goes stale at once; mark it stale in the state file the same day so nobody executes it.

## 2026-11-15

- Show a mock-up before wiring a visual variant into something the user looks at all day. The gradient met every prediction and was rejected in one glance; a demo screenshot and a question would have cost one message.
- When a small error is "about a pixel", compute it before blaming rounding. 55 font units at 13 pt on a 2× display is 1.4 px: the assumption was wrong, not the rasteriser.
- Do not let a distinction rest on colour alone when luminances are close; add a shape cue (here a gap).
- An indicator's place in a degradation order follows its cost: bars are wide and go first, two-cell rings are cheap and go last.
- Temporary wiring into a user's live config needs a backup, a written revert, and a note in the state file about what must not be deleted.

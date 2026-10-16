# PLANS

## Goal

A Claude Code status line (bash + PowerShell) that fits any terminal width while keeping the most information possible, with a configurable segment set that downstream features can extend.

## Phases

| Phase | Status | Evidence |
|---|---|---|
| 1. Terminal width detection and COLUMNS-aware fit | done 2026-10-15 | PR #2, kb `research/statusline/...` |
| 2. Bars shrink to floor, then drop; heat-colored percentages | done 2026-10-15 | PR #2 |
| 3. 16-step exclusion ladder, atoms per segment, `fit.ladder` | done 2026-10-15 | PR #2 (commit 3fcf63c and after) |
| 4. Two-row stacked layout, opt-in `fit.rows: 2` | done 2026-10-15 | PR #2 (abd71b4, 62fb2aa) |
| 5. Resize watcher, opt-in `fit.resize_watch` | done 2026-10-15 | PR #2 (71fc132, f48fe1e) |
| 6. Bash 3.2 compatibility | done 2026-10-16 | PR #4 |
| 7. Release 1.1.0 in both repos, tags | done 2026-10-16 | PR #6, #7; braisenly-plugins PR #5; tags `braisenly-statusline@1.1.0` |
| 8. Port into braisenly-plugins mirror | done 2026-10-15, mirror risk open | braisenly-plugins PR #5 |

## Current facts

- Claude Code exports `COLUMNS`/`LINES` (v2.1.153+); the renderer reads the pty width directly first. Terminal resize is not a re-render trigger (anthropics/claude-code#76988, open; our measurements commented there).
- Resize-to-refit latency ~2.1 s: 0.4 s watcher, 1.7 s Claude Code settings reload. Floor until upstream ships the trigger.
- Default is one row. `fit.rows: 2` stacks labels+bars over values with aligned separators; leading pad uses U+2800 because Claude Code trims leading whitespace per row.
- Versioning: plugins follow the external mandate (plain SemVer, tag `braisenly-statusline@X.Y.Z`), per kb addendum 2026-10-16.

## Non-goals

- Branch name on row 2 (natural next step, not requested).
- Ambiguous-width symbols (U+2600–27BF), zero-width joiners, emoji modifiers in width counting.
- Removing drift tooling (`/drift-control`, drift scripts) from braisenly-plugins; only the statusline segment was retired.

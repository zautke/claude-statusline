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
| 8. Port into braisenly-plugins mirror | done 2026-10-15, superseded 2026-10-21 | braisenly-plugins PR #5; removed by #6/#7 |
| 9. Coalesce: this repo is the only source and its own marketplace | done 2026-10-20 | PR #10 (`942fc99`) |
| 10. Rename to claude-statusline, Claude Code only | done 2026-10-20 | PR #10 (`1cc440b`); repo renamed |
| 11. Stable launcher; `/drift-control` import plus `.ps1` twin | done 2026-10-20 | PR #10 (`942fc99`, `49d4ea5`) |
| 12. Fit margin `COLUMNS-4`; pwsh parity; twin tests with the ladder map | done 2026-10-20 | PR #10 (`1c1b8b5`, `e39a69a`) |
| 13. Release 2.0.0, hosts on `main` | done 2026-10-21 | #11, tag `claude-statusline@2.0.0` |
| 14. Public release: professional README with animated width-shrink demo, all platforms, full config reference | in progress 2026-11-09 | branch `docs/public-readme` |
| 15. Simplify / de-over-engineer the codebase, behaviour-preserving | in progress 2026-11-09 | branch `refactor/simplify-codebase` |
| 16. Switch repo visibility to public | waiting on user OK | repo is PRIVATE as of 2026-11-09 |

## Current facts

- Claude Code exports `COLUMNS`/`LINES` (v2.1.153+); the renderer reads the pty width directly first. Terminal resize is not a re-render trigger (anthropics/claude-code#76988, open; our measurements commented there).
- Resize-to-refit latency ~2.1 s: 0.4 s watcher, 1.7 s Claude Code settings reload. Floor until upstream ships the trigger.
- Default is one row. `fit.rows: 2` stacks labels+bars over values with aligned separators; leading pad uses U+2800 because Claude Code trims leading whitespace per row.
- Versioning: plugins follow the external mandate, per kb addendum 2026-10-16: plain SemVer, tag `claude-statusline@X.Y.Z` (until 1.1.0, `braisenly-statusline@X.Y.Z`).
- Identity: `claude-statusline@claude-statusline`, marketplace in this repo (`source: "."`), Claude Code only. `config/identity.env` is the SSoT for scripts and tests.
- `statusLine` runs the installer-owned launcher `<config-dir>/claude-statusline/scripts/statusline-launch.{sh,ps1}`, which resolves the installed version from `installed_plugins.json` on every render.
- Claude Code shows the status line `COLUMNS - 4` cells wide (measured on 2.1.306); the budget is `COLUMNS - STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS - fit.reserve`.

- Public-facing README must be generated from source truth; demo frames are real renderer output (`scripts/demo/render-demo.sh`), never hand-drawn.

## Non-goals

- Branch name on row 2 (natural next step, not requested).
- Ambiguous-width symbols (U+2600–27BF), zero-width joiners, emoji modifiers in width counting.
- Removing the drift tooling; only the statusline segment was retired. Drift now lives here.
- Codex, Copilot and Agent Plugins manifests (user decision 2026-10-20: Claude Code only).
- Wiring the drift hook in 2.0.0 (deferred by the user 2026-10-21; open in TASKS).

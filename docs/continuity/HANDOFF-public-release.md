# HANDOFF — claude-statusline public release (from session a5493e17, 2026-11-09)

Read `CURRENT_TASK_STATE.md` first. This file holds what the next session needs to resume exactly: the user's request verbatim, the workspace layout, and the three agent briefs verbatim, ready to re-spawn.

## User request (verbatim, 2026-11-09 ~14:50 MST)

> use a opus/sonnet team and make a profession readme for all cases and features,including ascii video of the terminal width skrinking displaying the progressive exclusion. all installs--powershell, mac, linux- how to configure, everything a user needs instruction and demo wise. then another opus team works on streamlining, simplifying, minimizing and de-over-engineering the code base. iwant the README asap and live

Earlier in the session (context): the user believed public-release work was lost in a machine crash. An exhaustive search found none (see SESSION_LOG 2026-11-09). The user then asked whether README / install notes for a public audience existed: they did not, beyond the 2026-10-20 README.

## Workspace at handoff

| Path | Branch | State |
|---|---|---|
| `/Users/derp/claude-statusline` | `docs/continuity-2026-11-09` | this handoff; pushed |
| `~/claude-statusline-wt/readme` | `docs/public-readme` | created off `development` `96805ad`; clean, no commits, not pushed |
| `~/claude-statusline-wt/simplify` | `refactor/simplify-codebase` | created off `development` `96805ad`; clean, no commits, not pushed |

All three agents (readme-writer, demo-builder, simplifier) were spawned at ~14:52 and stopped by the user at ~15:00 when the session was interrupted for handoff. They produced nothing. Re-spawn them with the briefs below, unchanged unless the user says otherwise.

Tooling checked on largo: `asciinema` at `/opt/homebrew/bin/asciinema`; node 24.13.0; pnpm 11.1.3; no vhs/agg/svg-term; ~11 GiB free.

## Resume sequence

1. `git -C ~/claude-statusline-wt/readme status` and `git -C ~/claude-statusline-wt/simplify status`. Both should be clean on their branches. If a worktree is missing, recreate it: `git worktree add -b <branch> ~/claude-statusline-wt/<name> development`.
2. Spawn in one message, all `run_in_background: true`: readme-writer (opus), demo-builder (sonnet), simplifier (opus), with the briefs below.
3. Arm a push monitor on both branches (`git ls-remote` poll every 60 s) and enforce the deadlines: demo 45 min, README 60 min, simplify 90 min. On timeout, inspect, stop and finish inline.
4. On delivery: two opus reviewers per deliverable (README + demo together; simplify separately), max 3 fix rounds (user review protocol).
5. Open draft PRs into `development`, address review bots (Codex/Copilot) per the "say no to context-free bots" rule.
6. Read kb `protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main` before any version bump; reconcile the global CLAUDE.md table (development MINOR+1, main MAJOR+1, three numbers) with the 2026-10-16 plugin addendum (plain SemVer, tag `claude-statusline@X.Y.Z`). Write all release record surfaces.
7. Promote to `main` so the README is live on the default branch.
8. Ask the user before `gh repo edit zautke/claude-statusline --visibility public --accept-visibility-change-consequences`; then add topics and homepage.
9. Rule on the simplifier's "proposed, needs ruling" list with the user (requirements are fixed: never cut a feature).

## Brief 1 — readme-writer (opus, general-purpose)

```text
Role: lead technical writer. Write a professional, public-facing README for the Claude Code plugin `claude-statusline` (repo zautke/claude-statusline, currently private, about to go public). Users must be able to install, configure, verify, update, uninstall and troubleshoot it from the README alone.

Workspace: git worktree /Users/derp/claude-statusline-wt/readme, branch `docs/public-readme` (based on `development`). Work ONLY there. Do not touch /Users/derp/claude-statusline or /Users/derp/claude-statusline-wt/simplify (another team refactors code there; it preserves behaviour, so document current behaviour).

Ground truth = the source, not the old README. Read: scripts/statusline-command.sh and .ps1 (renderer), config/constants.sh/.ps1, statusline.example.json, scripts/install.sh/.ps1, scripts/statusline-launch.sh/.ps1, scripts/resize-watch.sh/.ps1, skills/configure-statusline/SKILL.md, commands/drift-control.md, docs/drift-control-menu.md, docs/fable-usage-evidence.md, CHANGELOG.md, .claude-plugin/*, .github/workflows/ci.yml, tests/*. Use the codemunch MCP (mcp__codemunch__*) for code navigation where it helps; Read is fine for files you edit.

Research first (state findings briefly in your report, dated 2026-11-09): what well-regarded Claude Code plugins / CLI tools put in READMEs today, and the current Claude Code plugin + marketplace install commands and statusLine settings docs. Use web search, Context7 (Claude Code docs) and GitHub code search. Verify `claude plugin marketplace add` / `claude plugin install` syntax against current docs.

README must cover (adapt order to what research says reads best):
- One-line pitch, badges (CI, license, plugin version) only if they resolve; a hero demo: embed `docs/media/fit-ladder.svg` (an animated terminal recording of the terminal shrinking and segments dropping, being produced right now by a teammate in this same worktree under docs/media/ and scripts/demo/; do not create or edit those paths; just reference the SVG, and also a `.cast` file if present at docs/media/fit-ladder.cast).
- Features: every segment (model, profile, cwd, context, disk, tmp, five_hour, seven_day, fable, and any others in the renderer), bars + heat colours, terminal-width fit, the 16-step exclusion ladder (explain each step in a table, in order, with what it removes), two-row stacked layout, resize watcher, the `/drift-control` command, the `configure-statusline` skill, the stable launcher that survives plugin updates.
- Requirements: Claude Code version, Bash (3.2+ supported, confirm), PowerShell 7 for Windows, OS support, optional tools (e.g. jq/python if used; confirm from source).
- Install per platform: macOS, Linux, Windows (PowerShell), plus WSL notes if relevant; custom `CLAUDE_CONFIG_DIR` / multiple profiles. Show expected result and how to verify it worked.
- Configure: full reference of statusline.json keys with types, defaults and examples (segments, labels, widths, fit.reserve, fit.min_bar_cells, fit.rows, fit.resize_watch, fit.ladder, fable.*), plus env vars. Recipes (minimal, two-row, custom ladder).
- How it works: a Mermaid diagram (Mermaid only; no ASCII box diagrams) of settings.json -> launcher -> installed_plugins.json -> renderer -> caches.
- Usage-limit data: where 5h/7d/Fable numbers come from, how credentials are read, that tokens are never cached or logged, network calls made. Be precise and honest.
- Update, uninstall (exact steps to revert settings.json), troubleshooting (e.g. `claude-statusline: not installed`, blank line, wrong width, Windows quirks), FAQ.
- Contributing + running the tests, license (MIT).
Example rendered output lines in plain code blocks are fine (they are output samples, not diagrams); generate them by actually running the renderer with fixture input (see tests/ for how fixtures feed it), never invent them.

Rules:
- Every command in the README must be one you ran or verified against source/docs. Note anything you could not verify (e.g. Linux, Windows) in your report; do not guess. pwsh may be available on this Mac (`which pwsh`).
- Plain, clear English for a public audience. No org-internal jargon (no "largo", "adagio", "dot-agents", "kb", profile-bucket talk). Do not mention secrets/tokens beyond the factual credential-handling section.
- Add a CHANGELOG.md entry under an `## Unreleased` heading at the top (docs: public README). Do not bump versions anywhere.
- Do not edit any scripts, tests, config, skills or commands. If source and docs disagree, document the source behaviour and list the discrepancy in your report.
- Commit in small steps with Conventional Commits (`docs(readme): ...`), and push to origin `docs/public-readme` after each commit. End commit messages with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
- Do not open or merge PRs, change repo settings, or tag.

Deadline: 60 minutes. Report back: commit SHAs, README outline, research sources (URLs), every unverified claim, and source/doc discrepancies found.
```

## Brief 2 — demo-builder (sonnet, general-purpose)

```text
Role: build the README hero demo for the Claude Code plugin `claude-statusline`: an animated terminal "video" showing the status line as the terminal width shrinks, so viewers see the progressive exclusion ladder drop detail step by step (bars shrink, labels go, then whole segments), and ideally a second short clip of the two-row stacked layout (`fit.rows: 2`).

Workspace: git worktree /Users/derp/claude-statusline-wt/readme, branch `docs/public-readme`. You own ONLY `docs/media/` and `scripts/demo/`. A teammate is writing README.md and CHANGELOG.md in the same worktree right now: never edit them, and only `git add` your own paths. Do not touch any other worktree.

Requirements:
- Authentic: every frame is real output of `scripts/statusline-command.sh` (the renderer) fed fixture JSON on stdin with `COLUMNS` set per frame. Look at tests/test-statusline.sh to see how fixtures, config and caches are made deterministic (fake HOME/CLAUDE_CONFIG_DIR, Fable usage cache, disk numbers). Use fake but plausible numbers; never read the real user's credentials, caches or settings.
- Shrink from wide (~180 columns) down to narrow (~40) in steps that hit each ladder change; show the current width in each frame (e.g. a dim ruler or `COLUMNS=120` caption) so the shrink is obvious. Hold the first and last frame longer. Loop.
- Output must render inside a GitHub README: produce `docs/media/fit-ladder.svg` as an animated SVG (GitHub serves SVGs via <img>, so no JavaScript; CSS keyframe or SMIL animation is fine). Keep ANSI colours. Also save the asciinema v2 recording `docs/media/fit-ladder.cast` (asciinema is installed at /opt/homebrew/bin/asciinema). Optional second pair: `docs/media/two-row.svg/.cast`.
- Research the current best way (as of 2026-11-09) to turn a cast into a GitHub-safe animated SVG (e.g. svg-term-cli, or a small self-written generator). Use web search / GitHub code search briefly. The org package manager is pnpm (`pnpm dlx ...` is fine); do not install anything globally and do not download large files (disk has ~11 GiB free). If a self-written generator is simpler and dependency-free, prefer it.
- Make it reproducible: `scripts/demo/render-demo.sh` regenerates all media. Script rules: `#!/usr/bin/env bash`, a `usage()` function, every option has a short and long form (e.g. `-o/--out-dir`, `-h/--help`), no positional arguments. Bash 3.2 compatible if practical.
- Keep the SVG small (target < 500 KB) and readable at README width; use a monospace font stack and dark terminal background.
- Verify: open the SVG and check frames visually (convert a frame to PNG with any available tool, or use the Read tool on a rendered PNG), confirm the animation loops, and confirm GitHub would accept it (no <script>, no external refs).

Commit with Conventional Commits (`docs(demo): ...`), push to origin `docs/public-readme` (pull --rebase first if the push is rejected because the teammate pushed). End commit messages with:
  Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>
Do not open PRs or change repo settings.

Deadline: 45 minutes. Report: commit SHAs, files produced with sizes, tool chosen and why (with source URLs), the width steps used and what changed at each, and anything that did not work.
```

## Brief 3 — simplifier (opus, general-purpose)

```text
Role: senior engineer. Streamline, simplify, minimise and de-over-engineer the `claude-statusline` Claude Code plugin codebase without changing what users see or configure.

Workspace: git worktree /Users/derp/claude-statusline-wt/simplify, branch `refactor/simplify-codebase` (based on `development`). Work ONLY there. Another team is writing the public README in a different worktree from the current behaviour, so behaviour must stay identical.

Codebase (~4.4k lines): renderers scripts/statusline-command.sh (323) and .ps1 (495) must stay at output parity; launchers statusline-launch.sh/.ps1; installers install.sh/.ps1; resize-watch.sh/.ps1; config/constants.sh/.ps1; drift-control (scripts/drift-control.sh/.ps1, drift-menu.py, drift-menu-launch.sh, commands/drift-control.md); drift assessor (drift-assess-worker.sh 573 lines, drift-hook-entry.sh; not yet wired as a hook, it is a planned backlog item); design notes living in scripts/ (drift-v2-design.md, drift-v2-plan-A.md, drift-rubric.md); scripts/statusline-dispatcher.sh; tmux/; tests/*.sh/*.ps1; .github/workflows/ci.yml; skills/configure-statusline. Use the codemunch MCP (mcp__codemunch__resolve_repo, index_folder, get_file_outline, find_references, check_references, find_dead_code, get_blast_radius) to understand references before changing anything.

Hard constraints:
- No feature removal. Every user-facing feature stays: all segments, bars/colours, fit + 16-step exclusion ladder, two-row layout, resize watcher, `/drift-control` menu (including its OSC 8 link), configure skill, stable launcher, Bash 3.2 support, PowerShell twin parity, and the drift assessor code (planned work; you may simplify it but not delete it).
- Unchanged public surface: statusline.json schema and defaults, env vars, file paths and names that users or docs call (scripts/install.sh, scripts/install.ps1, statusline.example.json, launcher location ~/.claude/claude-statusline/, commands and skill names), rendered output byte-for-byte for the same input.
- Every test must pass before and after: bash tests/test-package.sh, tests/test-launch.sh, tests/test-statusline.sh, tests/test-drift-control.sh, `claude plugin validate . --strict`, and the pwsh tests if pwsh is installed (`which pwsh`). Run the suite first to get a baseline. If you change renderer logic, add a check that compares output before/after across many widths (e.g. COLUMNS 40..200) for both renderers.
- Simplicity means less code and fewer moving parts: remove duplication, dead branches, needless indirection and config for values that never change; prefer stdlib/shell builtins; keep it readable. No new abstractions, no new dependencies.
- Anything that would delete a file, rename a public path, or might be a feature cut: do NOT do it; list it in your report as "proposed, needs ruling" with evidence (references found, why it looks dead). Design markdown files sitting in scripts/ may be proposed for moving to docs/, not deleted.
- Do not edit README.md (the README team owns that) or docs/continuity/*. Add a CHANGELOG.md line under `## Unreleased` (refactor: ...). Do not bump versions.

Commit in small logical steps with Conventional Commits (`refactor(renderer): ...`), push to origin `refactor/simplify-codebase` after each. End commit messages with:
  Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Do not open or merge PRs, tag, or change repo settings. Never run `git push --force`.

Deadline: 90 minutes. Report: baseline and final test results (exact commands and pass counts), line count before/after per file, each change with its rationale and commit SHA, the parity evidence, and the "proposed, needs ruling" list.
```

## Known merge note

Both the README branch and the simplify branch add a CHANGELOG `## Unreleased` section; expect a trivial conflict when the second one merges into `development`.

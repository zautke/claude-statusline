# CURRENT TASK STATE

Updated 2026-10-21.

**State:** 2.0.0 release candidate on `feat/coalesce-plugin-copies` (PR #10). Not merged yet.

- Both hosts run `claude-statusline@claude-statusline` from the marketplace at `#feat/coalesce-plugin-copies`, through the stable launcher in `~/.claude/claude-statusline/`.
- Companion PRs: braisenly-plugins #6 (removes the vendored copy), dot-agents #24 (removes the `profiles/` copy; stacked on `feat/sign-in-base-plugin`).

**Resume point:** review-bot triage on PR #10, then merge to `development`, promote to `main`, tag `claude-statusline@2.0.0`, and repoint both hosts' marketplace to `main`.

**Protocol reminders:** read the kb org release policy and its 2026-10-16 addendum before any bump or tag. Bot findings: triage, report only critical ones to the user, and the user decides.
# CURRENT TASK STATE

Updated 2026-10-21.

**State:** claude-statusline **2.0.0 released**. Nothing in flight.

- `main` = `482cb3d`, tag `claude-statusline@2.0.0`; `development` in sync.
- Both hosts run 2.0.0 from the `claude-statusline` marketplace on `main` (`autoUpdate: true`), with `statusLine` set to the stable launcher in `~/.claude/claude-statusline/`.
- Profiles: dot-agents `settings/global/claude-settings.json` and `profiles/claude/base/settings.json` point at the launcher and enable the plugin (dot-agents `main` `77d955f2`). largo's `~/.agents` is on another branch, so a shim at `~/braisenly-statusline/scripts/statusline-dispatcher.sh` bridges until that branch takes `main`.
- Install or repair from the proper source: dot-agents `/install-claude-statusline`.

**Resume point:** the open items in TASKS.md. The largest is the drift hook wiring (kb backlog note).

**Protocol reminders:** read the kb org release policy and its 2026-10-16 addendum before any bump or tag (plain SemVer, `claude-statusline@X.Y.Z`). Bot findings: triage, report only critical ones to the user, and the user decides. Review rounds are capped at 3.
# CURRENT TASK STATE

Updated 2026-10-16.

**State:** shipped and released. Nothing in flight.

- zautke/braisenly-statusline `main` = 871c996, version 1.1.0, tag `braisenly-statusline@1.1.0` pushed. `development` in sync.
- zautke/braisenly-plugins `main` = 3e52d52, `braisenly-statusline/` at 1.1.0, tag `braisenly-statusline@1.1.0` pushed. User's local checkout is on `feat/agnostic-release` with uncommitted `release.py` changes; untouched.
- Live session: `~/.claude/settings.json` statusLine points at `~/braisenly-statusline/scripts/statusline-dispatcher.sh` (main). `~/.claude/statusline.json` has `fit.resize_watch: true`; a watcher runs per Claude pid.

**Resume point if work continues:** the open items in TASKS.md. First candidate is confirming the publish-mirror behaviour for the vendored plugin directory before anyone runs `profile-publish`.

**Protocol reminders for this repo:** read kb org-wide release policy before any merge/bump/tag; plugins use plain SemVer and `{name}@{version}` tags; bot review findings get triaged by me plus two Opus reviewers, max 3 fix rounds then pause.

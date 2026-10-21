# shellcheck shell=bash
# Regex constants (POSIX ERE / jq Oniguruma compatible). Keep in step with constants.ps1.

# Org version stamp MAJOR.MINOR.PATCH.BUILD-<branch>; the branch part has "/" replaced by "-"
# because the version names Claude Code's cache directory.
ORG_VERSION_STAMP_FOUR_DOTTED_INTEGERS_THEN_HYPHEN_LOWERCASE_BRANCH='^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9._-]+$'

# Resize-watcher nonce appended to statusLine.command, e.g. " # bsl-cols=120".
NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END=' # bsl-cols=[0-9]+$'

# Drift session id: letters, digits, dot, underscore, hyphen only (no separators, no traversal).
SESSION_ID_ONLY_LETTERS_DIGITS_DOT_UNDERSCORE_HYPHEN='^[A-Za-z0-9._-]+$'

# Count argument such as --recent 10.
NON_NEGATIVE_INTEGER_DIGITS_ONLY='^[0-9]+$'

# A statusLine.command this plugin owns: one of its renderer, dispatcher or launcher scripts, under the
# current name or the legacy braisenly-statusline name (so old installs migrate).
OWNED_COMMAND_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE_SCRIPTS_DISPATCHER_COMMAND_OR_LAUNCH='(claude|braisenly)-statusline[\\/]scripts[\\/]statusline-(dispatcher|command|launch)\.(sh|ps1)'

# Installer guard: a statusLine.command mentioning this plugin, current or legacy name, is ours to replace.
OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE='(claude|braisenly)-statusline'

# Claude Code draws the status line 2 cells in from each terminal edge, so it shows COLUMNS - 4 cells
# (measured 2026-10-20 on Claude Code 2.1.306: a 52-column window shows 48 cells; a row padded to
# COLUMNS - 3 was cut with an ellipsis). The fit budget is COLUMNS minus this margin minus fit.reserve.
STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS=4

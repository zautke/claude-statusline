# Regex constants (.NET). Keep in step with constants.sh.

# Org version stamp MAJOR.MINOR.PATCH.BUILD-<branch>; the branch part has "/" replaced by "-"
# because the version names Claude Code's cache directory.
$ORG_VERSION_STAMP_FOUR_DOTTED_INTEGERS_THEN_HYPHEN_LOWERCASE_BRANCH = '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[a-z0-9._-]+$'

# Resize-watcher nonce appended to statusLine.command, e.g. " # bsl-cols=120".
$NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END = ' # bsl-cols=[0-9]+$'

# Drift session id: letters, digits, dot, underscore, hyphen only (no separators, no traversal).
$SESSION_ID_ONLY_LETTERS_DIGITS_DOT_UNDERSCORE_HYPHEN = '^[A-Za-z0-9._-]+$'

# Count argument such as --recent 10.
$NON_NEGATIVE_INTEGER_DIGITS_ONLY = '^[0-9]+$'

# A statusLine.command this plugin owns: one of its renderer, dispatcher or launcher scripts.
$OWNED_COMMAND_BRAISENLY_STATUSLINE_SCRIPTS_DISPATCHER_COMMAND_OR_LAUNCH = 'braisenly-statusline[\\/]scripts[\\/]statusline-(dispatcher|command|launch)\.(sh|ps1)'

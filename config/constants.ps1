# Regex constants (.NET). Keep in step with constants.sh.

# Plugin version: plain SemVer MAJOR.MINOR.PATCH, the format Claude Code marketplaces expect. External mandate overrides
# the org 4-part stamp (kb protocols/release/protocol-org-wide-branch-and-version-policy-development-and-main, addendum 2026-10-16).
$PLAIN_SEMVER_MAJOR_DOT_MINOR_DOT_PATCH_DIGITS_ONLY = '^[0-9]+\.[0-9]+\.[0-9]+$'

# Resize-watcher nonce appended to statusLine.command, e.g. " # bsl-cols=120".
$NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END = ' # bsl-cols=[0-9]+$'

# Drift session id: letters, digits, dot, underscore, hyphen only (no separators, no traversal).
$SESSION_ID_ONLY_LETTERS_DIGITS_DOT_UNDERSCORE_HYPHEN = '^[A-Za-z0-9._-]+$'

# Count argument such as --recent 10.
$NON_NEGATIVE_INTEGER_DIGITS_ONLY = '^[0-9]+$'

# A statusLine.command this plugin owns: one of its renderer, dispatcher or launcher scripts, under the
# current name or the legacy braisenly-statusline name (so old installs migrate).
$OWNED_COMMAND_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE_SCRIPTS_DISPATCHER_COMMAND_OR_LAUNCH = '(claude|braisenly)-statusline[\\/]scripts[\\/]statusline-(dispatcher|command|launch)\.(sh|ps1)'

# Installer guard: a statusLine.command mentioning this plugin, current or legacy name, is ours to replace.
$OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE = '(claude|braisenly)-statusline'

# Claude Code draws the status line 2 cells in from each terminal edge, so it shows COLUMNS - 4 cells
# (measured 2026-10-20 on Claude Code 2.1.306: a 52-column window shows 48 cells; a row padded to
# COLUMNS - 3 was cut with an ellipsis). The fit budget is COLUMNS minus this margin minus fit.reserve.
$STATUS_LINE_AREA_HORIZONTAL_MARGIN_CELLS = 4

# Test parsing of the disk segment: "141.9G free" (one decimal), "142G free" (integer), and either form for masking.
$DISK_FREE_ONE_DECIMAL_THEN_UNIT_THEN_SPACE_FREE = '([0-9]+\.[0-9])([KMG]) free'
$DISK_FREE_INTEGER_THEN_UNIT_THEN_SPACE_FREE = ' ([0-9]+)([KMG]) free'
$DISK_FREE_ANY_NUMBER_THEN_UNIT_THEN_SPACE_FREE = '[0-9.]+[KMG] free'
# Start of an ANSI SGR escape sequence (ESC [).
$ANSI_ESCAPE_SEQUENCE_START = "`e\["

# Test masking: the number in the disk segment (free space moves between renders on a busy machine).
$DISK_SEGMENT_NUMBER_INTEGER_WITH_OPTIONAL_ONE_DECIMAL = '[0-9]+([.][0-9])?'

# Reset times on the 5h/7d slots: the reset glyph, and the 2-cell click hint (U+229F/U+229E then U+25C2) shown
# while reset text is on or off.
$RESET_TIME_GLYPH_CLOCKWISE_OPEN_CIRCLE_ARROW = '↻'
$RESETS_CLICK_GLYPH_SHOWN_SQUARED_MINUS_THEN_LEFT_POINTING_SMALL_TRIANGLE = '⊟◂'
$RESETS_CLICK_GLYPH_HIDDEN_SQUARED_PLUS_THEN_LEFT_POINTING_SMALL_TRIANGLE = '⊞◂'

# Fixed day codes for the 7d clock format, indexed Sunday = 0 through Saturday = 6 (no locale).
$WEEKDAY_CODES_SUNDAY_FIRST_SU_M_T_W_R_F_SA = @('SU', 'M', 'T', 'W', 'R', 'F', 'SA')

# statusLine.refreshInterval (seconds) that keeps the countdown format current.
$RESETS_COUNTDOWN_STATUS_LINE_REFRESH_INTERVAL_SECONDS = 60

# Key chord the installers bind to the statusline-resets command.
$RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R = 'ctrl+x r'
# JSON schema the installers stamp on a keybindings.json they create.
$CLAUDE_CODE_KEYBINDINGS_JSON_SCHEMA_URL = 'https://www.schemastore.org/claude-code-keybindings.json'
# Prepended to the macOS click applet's PATH (do shell script runs with /usr/bin:/bin:/usr/sbin:/sbin) so a Homebrew
# jq is found. Used by install.sh only; kept here for parity.
$MACOS_URL_HANDLER_APPLET_PATH_PREFIX_HOMEBREW_ARM_THEN_USR_LOCAL_BIN = '/opt/homebrew/bin:/usr/local/bin'

# Click URL accepted by the toggle CLI: claude-statusline://toggle?slot=5h|7d[&profile=<name>], whole string.
$RESETS_TOGGLE_URL_SCHEME_TOGGLE_SLOT_5H_OR_7D_OPTIONAL_PROFILE_FULL_MATCH = '^claude-statusline://toggle/?\?slot=(5h|7d)(&profile=[A-Za-z0-9._-]+)?$'

# One OSC 8 hyperlink sequence, for stripping: ESC ] 8 ; params ; uri, ended by ST (ESC \) or BEL. The closing
# link ESC ] 8 ; ; ST matches too.
$ANSI_OSC8_HYPERLINK_SEQUENCE_ESC_RIGHT_BRACKET_8_PARAMS_URI_TERMINATED_BY_ST_OR_BEL = "`e\]8;[^;`e`a]*;[^`e`a]*(`e\\|`a)"

# Latest resets_at the renderers format (9999-12-31T23:59:00Z, the .NET DateTimeOffset ceiling after the round-up to a minute).
# Outside 0..this (e.g. a millisecond epoch) a slot renders no reset text.
$RESETS_AT_LATEST_RENDERABLE_EPOCH_SECONDS_9999_12_31_23_59_00_UTC = 253402300740

# Click-link profile: a config dir whose last component is .claude-<name> (directly under HOME) passes <name> as the
# link's profile parameter. Group 1 is the name.
$CONFIG_DIR_LEAF_DOT_CLAUDE_HYPHEN_PROFILE_NAME_LETTERS_DIGITS_DOT_UNDERSCORE_HYPHEN = '^\.claude-([A-Za-z0-9._-]+)$'

#!/usr/bin/env pwsh
# Installs (or with --uninstall removes) the claude-statusline status line for one Claude profile: the stable
# launcher, statusLine + enabledPlugins in settings.json, the reset-time toggle chord in keybindings.json, the
# click URL handler (HKCU registry) and the click scheme in Windows Terminal's safeUriSchemes.
# Arguments are parsed by hand so the GNU-style -x / --long forms match install.sh (param() ignored them).

function Usage {
    @'
Usage: install.ps1 [-c|--config-dir DIR] [-f|--force] [-U|--uninstall] [-W|--no-wt-scheme] [-h|--help]

  -c, --config-dir DIR  Claude profile directory (default: CLAUDE_CONFIG_DIR or ~/.claude).
  -f, --force           Replace an unrelated statusLine command.
  -U, --uninstall       Remove only what this installer added.
  -W, --no-wt-scheme    Leave Windows Terminal settings alone; print the safeUriSchemes line to add by hand.
  -h, --help            Show help.

Copies the stable launcher to DIR/claude-statusline/ and points statusLine at it, so plugin updates reach
the status line without editing settings again. Also binds the reset-time toggle chord in
DIR/keybindings.json and registers the handler for status-line clicks.
'@
}
function UsageFail { [Console]::Error.WriteLine((Usage)); exit 2 }

$ConfigDir = ''; $Force = $false; $Uninstall = $false; $NoWt = $false
for ($i = 0; $i -lt $args.Count; $i++) {
    $a = [string]$args[$i]
    # -U and -W are capitals; compare case-sensitively. The -Name forms keep old callers working.
    if ($a -cin '-h', '--help', '-Help') { Usage; exit 0 }
    elseif ($a -cin '-c', '--config-dir', '-ConfigDir') { if ($i + 1 -ge $args.Count) { UsageFail }; $ConfigDir = [string]$args[++$i] }
    elseif ($a -cin '-f', '--force', '-Force') { $Force = $true }
    elseif ($a -cin '-U', '--uninstall') { $Uninstall = $true }
    elseif ($a -cin '-W', '--no-wt-scheme') { $NoWt = $true }
    else { UsageFail }
}

$pluginRoot = Split-Path -Parent $PSScriptRoot
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $pluginRoot 'config/identity.env'))
. (Join-Path $pluginRoot 'config/constants.ps1')

$homeDir = if ($IsWindows) { $env:USERPROFILE } else { $env:HOME }
if (-not $ConfigDir) { $ConfigDir = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $homeDir '.claude' } }
$ConfigDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ConfigDir)
$launcherHome = Join-Path $ConfigDir $id.LAUNCHER_HOME
$launcher = Join-Path $launcherHome 'scripts/statusline-launch.ps1'
$marker = Join-Path $launcherHome 'url-handler'
$scheme = $id.URL_SCHEME
$chord = $RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R
$bind = "command:$($id.RESETS_COMMAND_NAME)"

function Warn([string]$m) { [Console]::Error.WriteLine("install.ps1: $m") }
# Follow links so a dotfiles-managed file keeps its link (from resize-watch.ps1).
function Resolve-Target([string]$p) {
    try { $item = Get-Item -LiteralPath $p -Force -ErrorAction Stop; if ($item.LinkType) { $t = $item.ResolveLinkTarget($true); if ($t) { return $t.FullName } } } catch { }
    return $p
}
# Temp file beside the target, original ACL carried over, then rename. Writes $text exactly.
function Write-Atomic([string]$dst, [string]$text, [bool]$bom = $false) {
    $tmp = Join-Path (Split-Path -Parent $dst) ".$(Split-Path -Leaf $dst).$PID.$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    [IO.File]::WriteAllText($tmp, $text, [Text.UTF8Encoding]::new($bom))
    if (Test-Path -LiteralPath $dst) { try { Get-Acl -LiteralPath $dst | Set-Acl -LiteralPath $tmp } catch { } }
    Move-Item -LiteralPath $tmp -Destination $dst -Force
}
function Read-Json([string]$p) { Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop }
function To-Json($o) { ($o | ConvertTo-Json -Depth 100).Replace("`r`n", "`n") + "`n" }
function Is-Owned([string]$c) { -not $c -or $c -match $OWNED_COMMAND_MENTIONS_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE -or $c -eq 'bash ~/.claude/statusline-dispatcher.sh' }

# ---- settings.json (statusLine + enabledPlugins); a symlinked file is written through to its target ----
$settingsPath = Resolve-Target (Join-Path $ConfigDir 'settings.json')
$settings = $null
if (Test-Path -LiteralPath $settingsPath) {
    try { $settings = Read-Json $settingsPath } catch { Warn "$settingsPath is not valid JSON; fix it and run again."; exit 1 }
}
if ($null -eq $settings) { $settings = [ordered]@{} }
# Strip the resize watcher's nonce before the ownership check.
$current = ([string]$settings.statusLine.command) -replace $NONCE_SUFFIX_SPACE_HASH_BSL_COLS_EQUALS_DIGITS_AT_END, ''
if (-not $Uninstall -and -not (Is-Owned $current) -and -not $Force) {
    [Console]::Error.WriteLine("Refusing to replace unrelated statusLine command: $current")
    exit 1
}

# ---- keybindings.json: "<chord>": "command:<name>" in the first Chat block ----
$kbPath = Resolve-Target (Join-Path $ConfigDir 'keybindings.json')
function Norm-Chord([string]$k) { ($k.Trim() -replace '\s+', ' ').ToLowerInvariant() }
function Read-Keybindings {
    try { $doc = Read-Json $kbPath } catch { Warn "keybindings: $kbPath is not valid JSON; left unchanged (bind $chord to $bind yourself)."; return $null }
    if ($doc -isnot [Collections.IDictionary] -or $doc.bindings -isnot [Collections.IList]) { Warn "keybindings: $kbPath has no ""bindings"" array; left unchanged."; return $null }
    return $doc
}
function Install-Keybinding {
    if (-not (Test-Path -LiteralPath $kbPath)) {
        $doc = [ordered]@{ '$schema' = $CLAUDE_CODE_KEYBINDINGS_JSON_SCHEMA_URL; bindings = @([ordered]@{ context = 'Chat'; bindings = [ordered]@{ $chord = $bind } }) }
        Write-Atomic $kbPath (To-Json $doc); "Bound $chord to /$($id.RESETS_COMMAND_NAME) in $kbPath"; return
    }
    $doc = Read-Keybindings
    if ($null -eq $doc) { return }
    foreach ($b in $doc.bindings) {
        if ($b -isnot [Collections.IDictionary] -or $b.bindings -isnot [Collections.IDictionary]) { continue }
        foreach ($k in @($b.bindings.Keys)) {
            if ((Norm-Chord $k) -cne $chord) { continue }
            if ([string]$b.bindings[$k] -ceq $bind) { return }
            Warn "keybindings: $k is already bound to '$($b.bindings[$k])' in $kbPath; left unchanged."; return
        }
    }
    $chat = $doc.bindings | Where-Object { $_ -is [Collections.IDictionary] -and $_.context -ceq 'Chat' } | Select-Object -First 1
    if ($chat) {
        if ($chat.bindings -isnot [Collections.IDictionary]) { $chat.bindings = [ordered]@{} }
        $chat.bindings[$chord] = $bind
    } else {
        $doc.bindings = @($doc.bindings) + @([ordered]@{ context = 'Chat'; bindings = [ordered]@{ $chord = $bind } })
    }
    Write-Atomic $kbPath (To-Json $doc); "Bound $chord to /$($id.RESETS_COMMAND_NAME) in $kbPath"
}
function Uninstall-Keybinding {
    if (-not (Test-Path -LiteralPath $kbPath)) { return }
    $doc = Read-Keybindings
    if ($null -eq $doc) { return }
    $kept = [Collections.Generic.List[object]]::new(); $changed = $false
    foreach ($b in $doc.bindings) {
        if ($b -is [Collections.IDictionary] -and $b.context -ceq 'Chat' -and $b.bindings -is [Collections.IDictionary]) {
            $ours = @($b.bindings.Keys | Where-Object { (Norm-Chord $_) -ceq $chord -and [string]$b.bindings[$_] -ceq $bind })
            foreach ($k in $ours) { $b.bindings.Remove($k); $changed = $true }
            # A Chat block emptied by removing our entry goes too; one that still holds user bindings stays.
            if ($ours.Count -and $b.bindings.Count -eq 0) { continue }
        }
        $kept.Add($b)
    }
    if (-not $changed) { return }
    # A file holding nothing but what Install-Keybinding creates is ours: remove it.
    if ($kept.Count -eq 0 -and $doc.Count -eq 2 -and $doc['$schema'] -ceq $CLAUDE_CODE_KEYBINDINGS_JSON_SCHEMA_URL) { Remove-Item -LiteralPath $kbPath -Force; return }
    $doc.bindings = $kept
    Write-Atomic $kbPath (To-Json $doc)
}

# ---- URL handler: HKCU\Software\Classes\<scheme> (root overridable for tests) ----
$regRoot = if ($env:CLAUDE_STATUSLINE_REGISTRY_ROOT) { $env:CLAUDE_STATUSLINE_REGISTRY_ROOT } else { 'HKCU:\Software\Classes' }
$regKey = "$regRoot\$scheme"
$regCmdKey = "$regKey\shell\open\command"
$handlerCmd = "conhost.exe --headless pwsh -NoProfile -NonInteractive -File `"$([IO.Path]::GetFullPath($launcher))`" --url `"%1`""
$handlerOk = $false
function Get-HandlerCmd {
    if (-not (Test-Path -LiteralPath $regKey)) { return $null }
    if (-not (Test-Path -LiteralPath $regCmdKey)) { return '' }
    return [string](Get-Item -LiteralPath $regCmdKey).GetValue('')
}
function Install-Handler {
    try {
        $existing = Get-HandlerCmd
        # Ownership: only a key whose command runs a claude-statusline launcher (any profile) may be replaced.
        if ($null -ne $existing -and $existing -notmatch $OWNED_COMMAND_CLAUDE_OR_LEGACY_BRAISENLY_STATUSLINE_SCRIPTS_DISPATCHER_COMMAND_OR_LAUNCH) {
            Warn "$scheme URL scheme belongs to another program ($existing); left unchanged, status-line clicks stay off."; return
        }
        if (-not (Test-Path -LiteralPath $regCmdKey)) { New-Item -Path $regCmdKey -Force | Out-Null }
        Set-Item -LiteralPath $regKey -Value "URL:$scheme"
        New-ItemProperty -LiteralPath $regKey -Name 'URL Protocol' -Value '' -PropertyType String -Force | Out-Null
        Set-Item -LiteralPath $regCmdKey -Value $handlerCmd
        Write-Atomic $marker "$scheme`n"
        $script:handlerOk = $true
        "Registered the $scheme click handler."
    } catch { Warn "could not register the $scheme click handler: $($_.Exception.Message)" }
}
function Uninstall-Handler {
    # Only the key that runs THIS profile's launcher; another profile's (or program's) handler stays.
    try { if ((Get-HandlerCmd) -eq $handlerCmd) { Remove-Item -LiteralPath $regKey -Recurse -Force } } catch { Warn "could not remove the $scheme click handler: $($_.Exception.Message)" }
}

# ---- Windows Terminal safeUriSchemes: text edit that keeps comments and formatting ----
# Tokens of a JSONC text (strings, punctuation, bare literals) with their container depth; comments and whitespace
# skipped. Also returns the text with comments blanked, for validation. $null when a string or comment is unterminated.
function Get-JsoncTokens([string]$t) {
    $toks = [Collections.Generic.List[object]]::new(); $plain = [Text.StringBuilder]::new($t); $depth = 0; $i = 0
    while ($i -lt $t.Length) {
        $c = $t[$i]
        if ($c -eq '/' -and $i + 1 -lt $t.Length -and $t[$i + 1] -eq '/') { $e = $t.IndexOf("`n", $i); if ($e -lt 0) { $e = $t.Length }; for ($j = $i; $j -lt $e; $j++) { $plain[$j] = ' ' }; $i = $e; continue }
        if ($c -eq '/' -and $i + 1 -lt $t.Length -and $t[$i + 1] -eq '*') { $e = $t.IndexOf('*/', $i + 2); if ($e -lt 0) { return $null }; for ($j = $i; $j -lt $e + 2; $j++) { if ($t[$j] -ne "`n") { $plain[$j] = ' ' } }; $i = $e + 2; continue }
        if ([char]::IsWhiteSpace($c)) { $i++; continue }
        if ($c -eq '"') {
            $j = $i + 1; while ($j -lt $t.Length -and $t[$j] -ne '"') { if ($t[$j] -eq '\') { $j++ }; $j++ }
            if ($j -ge $t.Length) { return $null }
            $toks.Add([pscustomobject]@{ Kind = 'str'; Start = $i; End = $j + 1; Text = $t.Substring($i, $j + 1 - $i); Depth = $depth }); $i = $j + 1; continue
        }
        if ('{[}]:,'.Contains($c)) {
            if ($c -eq '}' -or $c -eq ']') { $depth-- }
            $toks.Add([pscustomobject]@{ Kind = 'punct'; Start = $i; End = $i + 1; Text = [string]$c; Depth = $depth })
            if ($c -eq '{' -or $c -eq '[') { $depth++ }
            $i++; continue
        }
        $j = $i; while ($j -lt $t.Length -and -not [char]::IsWhiteSpace($t[$j]) -and -not '{[}]:,"/'.Contains($t[$j])) { $j++ }
        if ($j -eq $i) { $j++ }
        $toks.Add([pscustomobject]@{ Kind = 'lit'; Start = $i; End = $j; Text = $t.Substring($i, $j - $i); Depth = $depth }); $i = $j
    }
    return @{ Tokens = $toks; Plain = $plain.ToString() }
}
# The top-level "safeUriSchemes" array as token indexes (Key, Open '[', Close ']'), @{} when absent, or Error.
function Find-SafeSchemes($toks) {
    if ($toks.Count -lt 2 -or $toks[0].Text -ne '{') { return @{ Error = 'top level is not an object' } }
    $nested = $false
    for ($k = 1; $k + 2 -lt $toks.Count; $k++) {
        if ($toks[$k].Kind -ne 'str' -or $toks[$k].Text -cne '"safeUriSchemes"' -or $toks[$k + 1].Text -ne ':') { continue }
        if ($toks[$k].Depth -ne 1) { $nested = $true; continue }
        if ($toks[$k + 2].Text -ne '[') { return @{ Error = 'safeUriSchemes is not an array' } }
        $open = $k + 2; $close = $open + 1
        while ($close -lt $toks.Count -and -not ($toks[$close].Text -eq ']' -and $toks[$close].Depth -eq $toks[$open].Depth)) { $close++ }
        return @{ Key = $k; Open = $open; Close = $close }
    }
    if ($nested) { return @{ Error = 'safeUriSchemes appears only inside a nested object' } }
    return @{}
}
function Test-Jsonc([string]$t, [bool]$want) {
    $p = Get-JsoncTokens $t
    if ($null -eq $p) { return $false }
    try { $j = $p.Plain | ConvertFrom-Json -AsHashtable -DateKind String -ErrorAction Stop } catch { return $false }
    return ([bool](@($j.safeUriSchemes) -ccontains $scheme)) -eq $want
}
function Edit-WtSettings([string]$file, [bool]$add) {
    $file = Resolve-Target $file
    $bytes = [IO.File]::ReadAllBytes($file)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $skip = if ($bom) { 3 } else { 0 }
    $t = [Text.UTF8Encoding]::new($false).GetString($bytes, $skip, $bytes.Length - $skip)
    $p = Get-JsoncTokens $t
    if ($null -eq $p) { Warn "Windows Terminal: $file could not be read safely; left unchanged. Add ""$scheme"" to safeUriSchemes yourself."; return }
    $toks = $p.Tokens; $f = Find-SafeSchemes $toks
    if ($f.Error) { Warn "Windows Terminal: $file left unchanged ($($f.Error)); add ""$scheme"" to the top-level safeUriSchemes yourself."; return }
    $q = "`"$scheme`""
    $ours = if ($f.ContainsKey('Open')) { @(for ($k = $f.Open + 1; $k -lt $f.Close; $k++) { if ($toks[$k].Text -ceq $q -and $toks[$k].Depth -eq $toks[$f.Open].Depth + 1) { $k } }) } else { @() }
    $nl = if ($t.Contains("`r`n")) { "`r`n" } else { "`n" }
    if ($add) {
        if ($ours.Count) { return }
        if (-not $f.ContainsKey('Open')) {
            # Absent: new first property after the opening brace, indented like the next line.
            $indent = [regex]::Match($t.Substring($toks[0].End), '^[^\n]*\n([ \t]*)\S').Groups[1].Value
            if (-not $indent) { $indent = '    ' }
            $comma = if ($toks[1].Text -eq '}') { '' } else { ',' }
            $new = $t.Insert($toks[0].End, "$nl$indent`"safeUriSchemes`": [$q]$comma")
        } elseif ($f.Close -eq $f.Open + 1) {
            $new = $t.Insert($toks[$f.Open].End, $q)
        } else {
            $last = $toks[$f.Close - 1]
            $new = $t.Insert($last.End, $(if ($last.Text -eq ',') { " $q" } else { ", $q" }))
        }
    } else {
        if (-not $ours.Count) { return }
        $s = $toks[$ours[0]]
        $created = [regex]::Match($t.Substring($toks[0].End), "^\r?\n[ \t]*`"safeUriSchemes`": \[$([regex]::Escape($q))\],?")
        if ($created.Success -and $f.Key -eq 1 -and $f.Close -eq $f.Open + 2) { $new = $t.Remove($toks[0].End, $created.Length) }
        elseif ($toks[$ours[0] - 1].Text -eq ',') { $from = $toks[$ours[0] - 1].Start; $new = $t.Remove($from, $s.End - $from) }
        elseif ($toks[$ours[0] + 1].Text -eq ',') { $to = $toks[$ours[0] + 1].End; while ($to -lt $t.Length -and $t[$to] -eq ' ') { $to++ }; $new = $t.Remove($s.Start, $to - $s.Start) }
        else { $new = $t.Remove($s.Start, $s.End - $s.Start) }
    }
    if (-not (Test-Jsonc $new $add)) { Warn "Windows Terminal: editing $file would not leave valid settings; left unchanged."; return }
    Write-Atomic $file $new $bom
    if ($add) { "Added $scheme to Windows Terminal safeUriSchemes in $file" } else { "Removed $scheme from Windows Terminal safeUriSchemes in $file" }
}
function Get-WtSettingsFiles {
    $c = if ($env:CLAUDE_STATUSLINE_WT_SETTINGS) { @($env:CLAUDE_STATUSLINE_WT_SETTINGS) } else {
        @("$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
          "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
          "$env:LOCALAPPDATA\Microsoft\Windows Terminal\settings.json")
    }
    $c | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
}

# ---- uninstall ----
if ($Uninstall) {
    if (Test-Path -LiteralPath $settingsPath) {
        $changed = $false
        if ($settings.enabledPlugins -is [Collections.IDictionary] -and $settings.enabledPlugins.Contains($id.PLUGIN_ID)) {
            $settings.enabledPlugins.Remove($id.PLUGIN_ID); $changed = $true
            if ($settings.enabledPlugins.Count -eq 0) { $settings.Remove('enabledPlugins') }
        }
        if ($current -and (Is-Owned $current)) { $settings.Remove('statusLine'); $changed = $true }
        if ($changed) { Write-Atomic $settingsPath (To-Json $settings) }
    }
    Uninstall-Keybinding
    if ($IsWindows) {
        Uninstall-Handler
        if (-not $NoWt) { foreach ($w in Get-WtSettingsFiles) { Edit-WtSettings $w $false } }
    }
    if ($id.LAUNCHER_HOME -and (Test-Path -LiteralPath $launcherHome)) { Remove-Item -LiteralPath $launcherHome -Recurse -Force }
    "Uninstalled Claude status line from $ConfigDir"
    exit 0
}

# ---- install ----
foreach ($sub in 'scripts', 'config') { New-Item -ItemType Directory -Force -Path (Join-Path $launcherHome $sub) | Out-Null }
Copy-Item -Force -LiteralPath (Join-Path $pluginRoot 'scripts/statusline-launch.ps1'), (Join-Path $pluginRoot 'scripts/statusline-launch.sh') -Destination (Join-Path $launcherHome 'scripts')
Copy-Item -Force -LiteralPath (Join-Path $pluginRoot 'config/identity.env'), (Join-Path $pluginRoot 'config/load-identity.sh') -Destination (Join-Path $launcherHome 'config')

if ($settings.enabledPlugins -isnot [Collections.IDictionary]) { $settings.enabledPlugins = [ordered]@{} }
$settings.enabledPlugins[$id.PLUGIN_ID] = $true
$settings.statusLine = [ordered]@{ type = 'command'; command = "pwsh -NoProfile -NonInteractive -File `"$launcher`"" }
Write-Atomic $settingsPath (To-Json $settings)

Install-Keybinding
if ($IsWindows) {
    Install-Handler
    # The terminal's safe list follows the handler: never mark the scheme safe for someone else's program.
    if ($handlerOk) {
        if ($NoWt) { "Windows Terminal: skipped; to open status-line clicks without a prompt, add `"$scheme`" to the global `"safeUriSchemes`" array in its settings.json." }
        else { foreach ($w in Get-WtSettingsFiles) { Edit-WtSettings $w $true } }
    }
} else {
    "Click handler: run install.sh on this OS to register $scheme links."
}
"Installed Claude status line for $ConfigDir"

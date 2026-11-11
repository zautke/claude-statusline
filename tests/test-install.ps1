#!/usr/bin/env pwsh
# Installer contract (PowerShell side): flag parsing, symlinked settings, keybinding merge, URL handler (registry),
# Windows Terminal safeUriSchemes and --uninstall. Same cases as tests/test-install.sh where the OS allows.
# Every run is isolated: temp USERPROFILE/HOME, a per-PID test registry root and a temp WT settings file.
param(
    [Alias('h')][switch]$Help
)

function Usage { 'Usage: test-install.ps1 [-h|--help]' }
if ($Help) { Usage; exit 0 }
$ErrorActionPreference = 'Stop'

$plugin = Split-Path -Parent $PSScriptRoot
$id = ConvertFrom-StringData (Get-Content -Raw -LiteralPath (Join-Path $plugin 'config/identity.env'))
. (Join-Path $plugin 'config/constants.ps1')
$installer = Join-Path $plugin 'scripts/install.ps1'
function Fail([string]$msg) { [Console]::Error.WriteLine("FAIL: $msg"); exit 1 }

$temp = Join-Path ([IO.Path]::GetTempPath()) ("bsl-install-" + [guid]::NewGuid())
$regTop = "HKCU:\Software\claude-statusline-test-$PID"
$saved = @{}
foreach ($k in 'USERPROFILE', 'HOME', 'CLAUDE_CONFIG_DIR', 'CLAUDE_STATUSLINE_REGISTRY_ROOT', 'CLAUDE_STATUSLINE_WT_SETTINGS') { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
$env:USERPROFILE = Join-Path $temp 'home'; $env:HOME = $env:USERPROFILE
$env:CLAUDE_CONFIG_DIR = $null
$env:CLAUDE_STATUSLINE_REGISTRY_ROOT = "$regTop\Classes"
$env:CLAUDE_STATUSLINE_WT_SETTINGS = Join-Path $temp 'wt/settings.json'
# Guard: never run the installer unless every override points into this test's sandbox.
if (-not $env:CLAUDE_STATUSLINE_REGISTRY_ROOT -or $env:CLAUDE_STATUSLINE_REGISTRY_ROOT -notlike 'HKCU:\Software\claude-statusline-test-*' -or
    -not $env:CLAUDE_STATUSLINE_WT_SETTINGS -or -not $env:CLAUDE_STATUSLINE_WT_SETTINGS.StartsWith($temp) -or
    -not $env:USERPROFILE.StartsWith($temp) -or $env:CLAUDE_CONFIG_DIR) {
    [Console]::Error.WriteLine('ABORT: isolation overrides unset; refusing to run the installer'); exit 3
}

$scheme = $id.URL_SCHEME
$regKey = "$env:CLAUDE_STATUSLINE_REGISTRY_ROOT\$scheme"
$chord = $RESETS_TOGGLE_DEFAULT_KEY_CHORD_CTRL_X_THEN_R
$cmd = "command:$($id.RESETS_COMMAND_NAME)"
$wt = $env:CLAUDE_STATUSLINE_WT_SETTINGS
$utf8 = [Text.UTF8Encoding]::new($false)

function Inst([string[]]$a) {
    $errFile = Join-Path $temp 'stderr.txt'
    $o = & pwsh -NoProfile -NonInteractive -File $installer @a 2>$errFile
    [pscustomobject]@{ Rc = $LASTEXITCODE; Out = ($o -join "`n"); Err = (Get-Content -Raw -LiteralPath $errFile) + '' }
}
function Tree([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) { return '<absent>' }
    (Get-ChildItem -LiteralPath $dir -Recurse -Force | ForEach-Object {
        $rel = $_.FullName.Substring($dir.Length)
        if ($_.PSIsContainer) { $rel } else { "$rel $((Get-FileHash -LiteralPath $_.FullName).Hash)" } } | Sort-Object) -join "`n"
}
function Write-Text([string]$p, [string]$t) { New-Item -ItemType Directory -Force (Split-Path -Parent $p) | Out-Null; [IO.File]::WriteAllText($p, $t, $utf8) }
function Read-Text([string]$p) { [IO.File]::ReadAllText($p) }
function Json([string]$p) { Get-Content -Raw -LiteralPath $p | ConvertFrom-Json -AsHashtable -DateKind String }
function Canon($o) { $o | ConvertTo-Json -Depth 50 -Compress }
function Reg-Cmd { (Get-Item -LiteralPath "$regKey\shell\open\command").GetValue('') }
function Reset-Reg { Remove-Item -LiteralPath $regTop -Recurse -Force -ErrorAction SilentlyContinue }
function Expect-Cmd([string]$cfg) { "conhost.exe --headless pwsh -NoProfile -NonInteractive -File `"$cfg\$($id.LAUNCHER_HOME)\scripts\statusline-launch.ps1`" --url `"%1`"" }

$wtAbsent = "// generated { by Windows Terminal`r`n{`r`n    `"`$help`": `"https://aka.ms/terminal-documentation`",`r`n    // `"safeUriSchemes`": [`"x`"] in a comment`r`n    `"copyOnSelect`": false, /* block } */`r`n    `"profiles`":`r`n    {`r`n        `"defaults`": {},`r`n        `"list`": [ { `"name`": `"pwsh`" } ]`r`n    },`r`n    `"schemes`": []`r`n}`r`n"
$wtList = "{`n  `"safeUriSchemes`": [`"ms-settings`", /* keep */ `"vscode`"],`n  `"theme`": `"dark`" // trailing`n}`n"
$wtEmpty = "{`n    `"safeUriSchemes`": [ ],`n    `"x`": 1`n}`n"
$wtNested = "{`n    `"profiles`": { `"defaults`": { `"safeUriSchemes`": [] } }`n}`n"

try {
    $home0 = Join-Path $env:USERPROFILE '.claude'
    Write-Text (Join-Path $home0 'sentinel.txt') 'do not touch'
    Write-Text $wt $wtAbsent
    $homeTree = Tree $home0

    # ---- 1. Flag parsing (negatives first: PASS = exit 2, Usage on stderr, nothing written) ----
    foreach ($bad in @('--bogus'), @('stray'), @('-c'), @('--config-dir'), @('-u'), @('-F')) {
        $r = Inst $bad
        if ($r.Rc -ne 2 -or $r.Err -notmatch '^Usage: install\.ps1') { Fail "negative flag $($bad -join ' '): rc=$($r.Rc) err=$($r.Err)" }
        if ((Tree $home0) -ne $homeTree) { Fail "negative flag $($bad -join ' ') wrote under HOME" }
        if (Test-Path -LiteralPath $regTop) { Fail "negative flag $($bad -join ' ') wrote the registry" }
        if ((Read-Text $wt) -cne $wtAbsent) { Fail "negative flag $($bad -join ' ') edited WT settings" }
    }
    $r = Inst @('--help')
    if ($r.Rc -ne 0) { Fail "help rc=$($r.Rc)" }
    foreach ($f in '-c, --config-dir', '-f, --force', '-U, --uninstall', '-W, --no-wt-scheme', '-h, --help') {
        if (-not $r.Out.Contains($f)) { Fail "Usage lacks $f" }
    }

    # Positive: --config-dir and -c write only under the given dir; HOME/.claude stays untouched.
    foreach ($form in '--config-dir', '-c') {
        $cfg = Join-Path $temp "cfg$form"
        $r = Inst @($form, $cfg, '-W')
        if ($r.Rc -ne 0) { Fail "$form install rc=$($r.Rc) $($r.Err)" }
        if (-not (Test-Path -LiteralPath (Join-Path $cfg 'settings.json'))) { Fail "$form did not write under $cfg" }
        if ((Tree $home0) -ne $homeTree) { Fail "$form touched HOME/.claude" }
        Reset-Reg
    }

    # --force / -f replace an unrelated statusLine; without it the install refuses (exit 1, file untouched).
    $cfg = Join-Path $temp 'force'
    foreach ($form in '--force', '-f') {
        Write-Text (Join-Path $cfg 'settings.json') '{"statusLine":{"type":"command","command":"echo mine"}}'
        $r = Inst @('-c', $cfg, '-W')
        if ($r.Rc -ne 1 -or (Read-Text (Join-Path $cfg 'settings.json')) -cne '{"statusLine":{"type":"command","command":"echo mine"}}') { Fail "negative unforced: rc=$($r.Rc)" }
        $r = Inst @('-c', $cfg, '-W', $form)
        if ($r.Rc -ne 0 -or (Json (Join-Path $cfg 'settings.json')).statusLine.command -notmatch 'statusline-launch\.ps1') { Fail "$form not honoured: rc=$($r.Rc) $($r.Err)" }
        Reset-Reg
    }

    # ---- 2. Symlinked settings.json: the target is written, the link survives ----
    $cfg = Join-Path $temp 'link'
    $real = Join-Path $temp 'dotfiles/settings.json'
    Write-Text $real '{"model":"opus"}'
    New-Item -ItemType Directory -Force $cfg | Out-Null
    $linked = $true
    try { New-Item -ItemType SymbolicLink -Path (Join-Path $cfg 'settings.json') -Target $real -ErrorAction Stop | Out-Null }
    catch { $linked = $false; "SKIP symlink case: cannot create symlinks on this host ($($_.Exception.Message)); covered by test-install.sh under WSL" }
    if ($linked) {
        $r = Inst @('-c', $cfg, '-W')
        if ($r.Rc -ne 0) { Fail "symlink install rc=$($r.Rc) $($r.Err)" }
        if (-not (Get-Item -LiteralPath (Join-Path $cfg 'settings.json')).LinkType) { Fail 'settings.json symlink replaced by a file' }
        $j = Json $real
        if ($j.model -ne 'opus' -or $j.statusLine.command -notmatch 'statusline-launch\.ps1') { Fail 'symlink target not written' }
        Reset-Reg
    }

    # ---- 3. Keybinding merge ----
    $cfg = Join-Path $temp 'kb'
    $kb = Join-Path $cfg 'keybindings.json'
    $r = Inst @('-c', $cfg, '-W')
    $j = Json $kb
    if (-not $j['$schema'] -or $j.bindings.Count -ne 1 -or $j.bindings[0].context -cne 'Chat' -or $j.bindings[0].bindings[$chord] -cne $cmd) { Fail "absent keybindings: $(Canon $j)" }
    $before = Read-Text $kb
    $null = Inst @('-c', $cfg, '-W')
    if ((Read-Text $kb) -cne $before) { Fail 'keybinding merge not idempotent' }
    Reset-Reg

    # User bindings preserved; ours lands in the first Chat block.
    Write-Text $kb '{"bindings":[{"context":"Global","bindings":{"ctrl+t":"app:toggleTodos"}},{"context":"Chat","bindings":{"shift+enter":"chat:newline"}},{"context":"Chat","bindings":{}}]}'
    $null = Inst @('-c', $cfg, '-W')
    $j = Json $kb
    if ($j.bindings.Count -ne 3 -or $j.bindings[0].bindings['ctrl+t'] -cne 'app:toggleTodos' -or $j.bindings[1].bindings['shift+enter'] -cne 'chat:newline' -or
        $j.bindings[1].bindings[$chord] -cne $cmd -or $j.bindings[2].bindings.Count -ne 0) { Fail "merge: $(Canon $j)" }
    Reset-Reg

    # Negatives: chord bound elsewhere (any spelling) or invalid JSON -> file untouched + stderr warning.
    foreach ($t in '{"bindings":[{"context":"Chat","bindings":{"Ctrl+X  R":"chat:killAgents"}}]}', '{"bindings":[{"context":"Chat",', '{"bindings":{}}') {
        Write-Text $kb $t
        $r = Inst @('-c', $cfg, '-W')
        if ($r.Rc -ne 0 -or (Read-Text $kb) -cne $t -or $r.Err -notmatch 'keybindings') { Fail "negative keybinding '$t': rc=$($r.Rc) err=$($r.Err) now=$(Read-Text $kb)" }
        Reset-Reg
    }

    # Uninstall removes only our entry.
    Write-Text $kb '{"bindings":[{"context":"Chat","bindings":{"shift+enter":"chat:newline"}}]}'
    $null = Inst @('-c', $cfg, '-W')
    $null = Inst @('-c', $cfg, '-W', '--uninstall')
    $j = Json $kb
    if ((Canon $j) -cne '{"bindings":[{"context":"Chat","bindings":{"shift+enter":"chat:newline"}}]}') { Fail "uninstall keybinding: $(Canon $j)" }
    Reset-Reg

    # ---- 4. URL handler (registry) ----
    $cfg = Join-Path $temp 'url'
    $marker = Join-Path $cfg "$($id.LAUNCHER_HOME)/url-handler"
    $r = Inst @('-c', $cfg, '-W')
    if ($r.Rc -ne 0) { Fail "url install rc=$($r.Rc) $($r.Err)" }
    $k = Get-Item -LiteralPath $regKey
    if ($k.GetValue('') -cne "URL:$scheme" -or $k.GetValue('URL Protocol') -cne '' -or $null -eq $k.GetValue('URL Protocol')) { Fail 'registry key values' }
    if ((Reg-Cmd) -cne (Expect-Cmd $cfg)) { Fail "registry command: $(Reg-Cmd)" }
    if (-not (Test-Path -LiteralPath $marker)) { Fail 'marker not written after registration' }

    # Another profile's install takes the scheme; uninstalling this profile then leaves it alone.
    $cfgB = Join-Path $temp 'url-b'
    $null = Inst @('-c', $cfgB, '-W')
    if ((Reg-Cmd) -cne (Expect-Cmd $cfgB)) { Fail 'second profile did not take the handler' }
    $null = Inst @('-c', $cfg, '-W', '-U')
    if (-not (Test-Path -LiteralPath $regKey) -or (Reg-Cmd) -cne (Expect-Cmd $cfgB)) { Fail 'uninstall removed another profile''s handler' }
    if (Test-Path -LiteralPath $marker) { Fail 'uninstall left this profile''s marker' }
    $null = Inst @('-c', $cfgB, '-W', '--uninstall')
    if (Test-Path -LiteralPath $regKey) { Fail 'uninstall left our own handler' }
    Reset-Reg

    # Negative: a foreign handler is kept, warned about, and no marker is written.
    New-Item -Path "$regKey\shell\open\command" -Force | Out-Null
    Set-Item -LiteralPath "$regKey\shell\open\command" -Value 'C:\other\app.exe "%1"'
    Remove-Item -LiteralPath $marker -ErrorAction SilentlyContinue
    Write-Text $wt $wtAbsent
    $r = Inst @('-c', $cfg)
    if ($r.Rc -ne 0 -or (Reg-Cmd) -cne 'C:\other\app.exe "%1"' -or $r.Err -notmatch [regex]::Escape($scheme)) { Fail "negative foreign handler: rc=$($r.Rc) cmd=$(Reg-Cmd) err=$($r.Err)" }
    if (Test-Path -LiteralPath $marker) { Fail 'negative foreign handler: marker written' }
    if ((Read-Text $wt) -cne $wtAbsent) { Fail 'negative foreign handler: WT edited' }
    $null = Inst @('-c', $cfg, '-U')
    if ((Reg-Cmd) -cne 'C:\other\app.exe "%1"') { Fail 'uninstall removed a foreign handler' }
    Reset-Reg

    # ---- 5. Windows Terminal safeUriSchemes ----
    $cfg = Join-Path $temp 'wtcase'
    $q = "`"$scheme`""
    $absIns = $wtAbsent.IndexOf('{', $wtAbsent.IndexOf("`n")) + 1
    $cases = [ordered]@{
        absent = @($wtAbsent, $wtAbsent.Insert($absIns, "`r`n    `"safeUriSchemes`": [$q],"))
        list   = @($wtList, $wtList.Replace('"vscode"]', "`"vscode`", $q]"))
        empty  = @($wtEmpty, $wtEmpty.Replace('[ ]', "[$q ]"))
    }
    foreach ($name in $cases.Keys) {
        $orig, $want = $cases[$name]
        Write-Text $wt $orig
        $r = Inst @('-c', $cfg)
        if ($r.Rc -ne 0 -or (Read-Text $wt) -cne $want) { Fail "WT ${name}: rc=$($r.Rc) err=$($r.Err)`n$(Read-Text $wt)" }
        if (($r.Out -split "`n" | Where-Object { $_.Contains($wt) }).Count -ne 1) { Fail "WT ${name}: edit not announced with the file name: $($r.Out)" }
        $null = Inst @('-c', $cfg)
        if ((Read-Text $wt) -cne $want) { Fail "WT ${name}: not idempotent" }
        $null = Inst @('-c', $cfg, '--uninstall')
        if ((Read-Text $wt) -cne $orig) { Fail "WT ${name}: uninstall did not restore the original bytes`n$(Read-Text $wt)" }
        Reset-Reg
    }
    # -W leaves the file alone and prints the manual setting; nested-only property -> skip + warning.
    Write-Text $wt $wtAbsent
    $r = Inst @('-c', $cfg, '--no-wt-scheme')
    if ((Read-Text $wt) -cne $wtAbsent -or $r.Out -notmatch 'safeUriSchemes') { Fail "-W: out=$($r.Out)" }
    Reset-Reg
    Write-Text $wt $wtNested
    $r = Inst @('-c', $cfg)
    if ($r.Rc -ne 0 -or (Read-Text $wt) -cne $wtNested -or $r.Err -notmatch 'safeUriSchemes') { Fail "negative nested WT: rc=$($r.Rc) err=$($r.Err)" }
    Reset-Reg

    # ---- 6. Round trip: install then uninstall restores the profile, registry and WT file ----
    $cfg = Join-Path $temp 'roundtrip'
    Write-Text (Join-Path $cfg 'settings.json') '{"model":"opus","enabledPlugins":{"x@y":true},"x-date":"2026-11-15T13:59:59Z"}'
    Write-Text (Join-Path $cfg 'keybindings.json') '{"bindings":[{"context":"Chat","bindings":{"shift+enter":"chat:newline"}}]}'
    Write-Text $wt $wtAbsent
    $snapNames = (Get-ChildItem -LiteralPath $cfg -Recurse -Force | ForEach-Object { $_.FullName.Substring($cfg.Length) } | Sort-Object) -join ','
    $snapSettings = Canon (Json (Join-Path $cfg 'settings.json'))
    $snapKb = Canon (Json (Join-Path $cfg 'keybindings.json'))
    $r = Inst @('-c', $cfg)
    if ($r.Rc -ne 0 -or -not (Test-Path -LiteralPath $regKey)) { Fail "round trip install rc=$($r.Rc) $($r.Err)" }
    $r = Inst @('-c', $cfg, '-U')
    if ($r.Rc -ne 0) { Fail "round trip uninstall rc=$($r.Rc) $($r.Err)" }
    $names = (Get-ChildItem -LiteralPath $cfg -Recurse -Force | ForEach-Object { $_.FullName.Substring($cfg.Length) } | Sort-Object) -join ','
    if ($names -cne $snapNames) { Fail "round trip files: $names vs $snapNames" }
    if ((Canon (Json (Join-Path $cfg 'settings.json'))) -cne $snapSettings) { Fail "round trip settings: $(Read-Text (Join-Path $cfg 'settings.json'))" }
    if ((Canon (Json (Join-Path $cfg 'keybindings.json'))) -cne $snapKb) { Fail 'round trip keybindings' }
    if ((Read-Text $wt) -cne $wtAbsent) { Fail 'round trip WT bytes' }
    if (Test-Path -LiteralPath $regKey) { Fail 'round trip registry' }

    if ((Tree $home0) -ne $homeTree) { Fail 'HOME/.claude changed during the run' }
    'ok'
} finally {
    Reset-Reg
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
    Remove-Item -Recurse -Force -LiteralPath $temp -ErrorAction SilentlyContinue
}

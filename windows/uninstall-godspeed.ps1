# =============================================================================
# kit-bootstrap / windows / uninstall-godspeed.ps1
#
# What the uninstaller removes besides its own folder: the program's own files that the setup put
# elsewhere on this PC. Run by the uninstaller after the notebook has stopped (stop-full-alpha.ps1).
#
# Until 18 October 2026 the uninstaller removed only its own folder, and about twenty helper
# programs stayed in ~\.local\bin, with that folder on PATH, beside the daily job, the Startup entry
# and the Hermes program (found on fresh Windows machines on 17 October 2026). This removes them.
#
# WHAT IT NEVER TOUCHES. The mission control folder, the notebook's notes, photos, files, settings
# and backups (the state folder), and what the assistant has learned (its profile) are the
# person's, and stay. So does anything in ~\.local\bin that this setup did not write (Claude Code
# keeps its own program there), and ~\.godspeed, which can hold the key to the folder's locked
# secrets.
#
# THE PREVIOUS EDITION. A PC can still have the first edition's setup beside this one. It shares
# the helpers, the daily job and the GODSPEED_DIR setting, so while it is installed those stay.
#
# Never fails: an uninstall that stops halfway over a leftover is worse than the leftover.
# =============================================================================
param(
    [string]$AppRoot = $PSScriptRoot,
    [string]$State = (Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'),
    [string]$UserHome = [Environment]::GetFolderPath('UserProfile'),
    # Where Windows lists the first edition's setup. A test points this at a key of its own.
    [string]$FirstEditionKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{7B3C1E64-9A55-4E1D-9D6C-2F0B8A4C51D7}_is1',
    [string]$StartupFolder = [Environment]::GetFolderPath('Startup'),
    [string[]]$TaskNames = @('Godspeed prompt archive', 'Godspeed notebook sync'),
    # Write the user's PATH and GODSPEED_DIR, or only say what would change. For the tests.
    [switch]$KeepUserEnvironment
)
$ErrorActionPreference = 'Continue'
$log = Join-Path $env:LOCALAPPDATA 'Godspeed\uninstall-log.txt'
New-Item -ItemType Directory -Force -Path (Split-Path $log) -ErrorAction SilentlyContinue | Out-Null
function Say([string]$Message) {
    Write-Output $Message
    try { Add-Content -LiteralPath $log -Value ((Get-Date -Format 's') + ' ' + $Message) -Encoding UTF8 } catch { }
}
function Same([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    try { return ([IO.Path]::GetFullPath($A).TrimEnd('\')).Equals([IO.Path]::GetFullPath($B).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }
    catch { return $false }
}

$workspace = $null
try { $workspace = (Get-Content -LiteralPath (Join-Path $State 'installation.json') -Raw -ErrorAction Stop | ConvertFrom-Json).workspace } catch { }
$firstEdition = Test-Path -LiteralPath $FirstEditionKey

# 1. The Startup entry, under both of its names (it was "... Full Alpha" until 18 October 2026).
foreach ($name in 'Godspeed Mission Control.lnk', 'Godspeed Mission Control Full Alpha.lnk') {
    $link = Join-Path $StartupFolder $name
    if (Test-Path -LiteralPath $link) { Remove-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue; Say "removed the Startup entry $name" }
}

# 2. The Hermes program that came with the notebook. Its profile (hermes-profile: the
#    conversations and what the assistant learned) and the desktop app's own data stay.
$runtime = Join-Path $State 'hermes-runtime'
if (Test-Path -LiteralPath $runtime) {
    Remove-Item -LiteralPath $runtime -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $runtime) { Say "the Hermes program in $runtime could not all be removed; delete that folder by hand" }
    else { Say "removed the Hermes program that came with the notebook" }
}

if ($firstEdition) {
    Say "the first edition's setup is still on this PC and shares the commands, the daily job and GODSPEED_DIR, so they stay"
    exit 0
}

# 3. The daily job (and the hourly one an older setup scheduled). Only ours: a job of that name
#    that runs in another mission control was made for that one.
if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
    foreach ($taskName in $TaskNames) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) { continue }
        $dir = @($task.Actions | ForEach-Object { $_.WorkingDirectory } | Where-Object { $_ })[0]
        if ($workspace -and $dir -and -not (Same $dir $workspace)) { Say "left the job '$taskName': it runs in $dir"; continue }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        Say "removed the job '$taskName'"
    }
}

# 4. The helpers in ~\.local\bin: the names the setup recorded when it wrote them
#    (installed-commands.txt), and for a setup older than that record the programs the notebook's
#    own copy of the kit ships, with their launchers. Only a file of one of those names goes.
$bin = Join-Path $UserHome '.local\bin'
$names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$record = Join-Path $UserHome '.godspeed\installed-commands.txt'
if (Test-Path -LiteralPath $record) { foreach ($n in (Get-Content -LiteralPath $record)) { if ($n.Trim()) { [void]$names.Add($n.Trim()) } } }
$tools = Join-Path $AppRoot 'payload\kit\tools'
if (Test-Path -LiteralPath $tools) {
    foreach ($f in (Get-ChildItem -LiteralPath $tools -File)) {
        if ($f.Extension -eq '.md' -or $f.Name -like 'test-*' -or $f.Name -like '*-test*' -or $f.Name -like '*_test*') { continue }
        [void]$names.Add($f.Name)
        if ($f.Name -like 'mc-*' -and $f.Extension -eq '') { [void]$names.Add($f.Name + '.cmd') }
    }
    foreach ($cmd in 'mc-prompt-harvest', 'mc-compile-rules', 'mc-check-keys', 'mc-due', 'mc-goals', 'mc-forecast', 'mc-work',
                     'mc-check-written', 'mc-check-moves', 'mc-run', 'mc-decide', 'mc-work-run', 'mc-menerio-connect', 'mc-search') {
        [void]$names.Add($cmd + '.cmd')
    }
}
$removed = 0
if (Test-Path -LiteralPath $bin) {
    # Decided for every file first, removed after: a launcher is known by its twin, which may
    # come first in the folder.
    $ourFiles = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $bin -File -Force -ErrorAction SilentlyContinue)) {
        $ours = $names.Contains($f.Name)
        if (-not $ours -and $f.Name -eq 'run-hidden.vbs') {
            $ours = [bool](Select-String -LiteralPath $f.FullName -SimpleMatch 'written by the kit installer' -Quiet -ErrorAction SilentlyContinue)
        }
        if (-not $ours) {
            # A launcher for one of the mission control's own commands, marked when it was written.
            $ours = [bool](Select-String -LiteralPath $f.FullName -SimpleMatch '# godspeed-cli-shim:' -Quiet -ErrorAction SilentlyContinue)
            if (-not $ours -and $f.Extension -eq '.cmd') {
                $twin = Join-Path $bin $f.BaseName
                $ours = (Test-Path -LiteralPath $twin) -and [bool](Select-String -LiteralPath $twin -SimpleMatch '# godspeed-cli-shim:' -Quiet -ErrorAction SilentlyContinue)
            }
        }
        if ($ours) { $ourFiles += $f.FullName }
    }
    foreach ($file in $ourFiles) {
        Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $file)) { $removed++ }
    }
    if (Test-Path -LiteralPath $record) { Remove-Item -LiteralPath $record -Force -ErrorAction SilentlyContinue }
    Say "removed $removed helper file(s) from $bin"
    # The folder leaves PATH only when nothing else lives in it.
    if (-not (Get-ChildItem -LiteralPath $bin -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
        Remove-Item -LiteralPath $bin -Force -ErrorAction SilentlyContinue
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        $kept = @(($userPath -split ';') | Where-Object { $_ -and -not (Same $_ $bin) })
        if ($userPath -and $kept.Count -ne @(($userPath -split ';') | Where-Object { $_ }).Count) {
            if (-not $KeepUserEnvironment) { [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User') }
            Say "took $bin off your PATH; nothing else was in it"
        }
    } else {
        Say "$bin stays on your PATH: other programs keep files there"
    }
}

# 5. GODSPEED_DIR, which tells other tools where the mission control is, when it names this one.
$dirSetting = [Environment]::GetEnvironmentVariable('GODSPEED_DIR', 'User')
if ($dirSetting -and $workspace -and (Same $dirSetting $workspace)) {
    if (-not $KeepUserEnvironment) { [Environment]::SetEnvironmentVariable('GODSPEED_DIR', $null, 'User') }
    Say "removed the GODSPEED_DIR setting (your mission control folder stays at $workspace)"
}

# 6. The setup's own copies in %LOCALAPPDATA%\Godspeed: the install code it fetched and its last
#    result. Its logs stay, as the record of what happened.
foreach ($name in 'join.ps1', 'setup-result.txt') {
    $f = Join-Path $env:LOCALAPPDATA ('Godspeed\' + $name)
    if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
}
exit 0

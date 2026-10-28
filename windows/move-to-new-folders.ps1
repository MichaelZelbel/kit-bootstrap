# =============================================================================
# kit-bootstrap / windows / move-to-new-folders.ps1
#
# Moves an install made before 2.0.0-beta.11 out of the folders whose names said "Full Alpha" and
# into the names godspeed-folders.ps1 gives (product issue #6), once, with everything that points
# into them, and puts all of it back if any step fails.
#
#   -Action Move     run by the wizard before it copies anything (PrepareToInstall). Stops the
#                    notebook, the assistant and the Godspeed jobs, renames the state folder,
#                    installs the assistant's program again in its new place (the program records
#                    the folder it was installed in, so a renamed copy does not start), and points
#                    the records, the setting files, the shortcuts, the user's environment and the
#                    scheduled tasks at the new names. The program itself is not moved: the wizard
#                    installs it into the new program folder, which is all new, so a cancelled or
#                    failed setup leaves the old one exactly as it was.
#                    Exit 0: moved. 3: nothing to move. 1: it failed and everything was put back.
#   -Action Undo     run by the wizard when the setup ended without installing the program after a
#                    move (cancelled, or a file it could not write): puts everything back.
#   -Action Finish   run by setup-godspeed.ps1 once the new install works: removes the old program
#                    folder and the old copy of the assistant's program, starts the assistant again
#                    if it was open, and leaves an older updater the record it looks for.
#
# What it never does: delete or rewrite the person's data. Notes, photos, files, settings,
# backups and what the assistant learned are moved by renaming the folder that holds them, which
# changes no byte of them; only the setup's own records and setting files have paths rewritten,
# and each one is copied first so it can be put back exactly.
#
# Every step is written down in a record (%LOCALAPPDATA%\Godspeed\folder-move\journal.json) before
# the next one starts. A move that a crash or a closed window left half done is put back by the
# next setup before it tries again.
# =============================================================================
param(
    [ValidateSet('Move', 'Undo', 'Finish')][string]$Action = 'Move',
    # The setup run this belongs to: Undo only puts back a move made by the same run.
    [string]$Run = '',
    [string]$LocalAppData = $env:LOCALAPPDATA,
    [string]$LogDir = (Join-Path $env:LOCALAPPDATA 'Godspeed'),
    # The rest are for the tests: where shortcuts are looked for, the user's environment, the names
    # of the Godspeed jobs, the Apps entry, what installs the assistant's program, and the process
    # of an older updater (found among the processes that started this one when not given).
    [string[]]$ShortcutFolders,
    [string]$EnvironmentKey = 'HKCU:\Environment',
    [string]$TaskNames = 'Godspeed*',
    [string]$AppsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9929B7B4-B588-46D2-AC79-01F7EBD7FA92}_is1',
    [string]$RuntimeBuilder = (Join-Path $PSScriptRoot 'ensure-hermes.ps1'),
    [int]$OldUpdater = 0
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$names = Get-GodspeedFolderNames
$oldState = Join-Path $LocalAppData $names.OldState
$newState = Join-Path $LocalAppData $names.State
$oldProgram = Join-Path $LocalAppData $names.OldProgram
$newProgram = Join-Path $LocalAppData $names.Program
$moveDir = Join-Path $LogDir 'folder-move'
$journalFile = Join-Path $moveDir 'journal.json'
$logFile = Join-Path $LogDir 'setup-log.txt'
$aside = 'hermes-runtime-before-move'
$caches = 'uv-cache', 'npm-cache', 'browser-cache'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not $ShortcutFolders) {
    $ShortcutFolders = @([Environment]::GetFolderPath('Startup'), [Environment]::GetFolderPath('Desktop'),
        (Join-Path ([Environment]::GetFolderPath('Programs')) 'Godspeed Mission Control'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'),
        (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu'))
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

# One line in the update log (setup-log.txt) for each thing that happened. Inside the setup's own
# run the log is its transcript, which takes what is written on the screen.
function Say([string]$Text) {
    Write-Host "  $Text"
    try { Add-Content -LiteralPath $logFile -Value ((Get-Date -Format 's') + ' ' + $Text) -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Save-Journal {
    $tmp = $journalFile + '.tmp'
    $script:journal | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $journalFile -Force
}
function Read-Journal {
    if (-not (Test-Path -LiteralPath $journalFile)) { return $null }
    try { return (Get-Content -LiteralPath $journalFile -Raw | ConvertFrom-Json) } catch { return $null }
}

# Every way a path into the old folders is written: as it is, inside JSON (backslashes doubled),
# with forward slashes (Node, Git Bash), and as %LOCALAPPDATA%\... in the environment. The state
# folder's name starts with the program folder's, so it is replaced first, and a name only counts
# where a separator, a quote or the end follows it.
function Convert-OldPath([string]$Text) {
    if (-not $Text) { return $Text }
    foreach ($pair in @(@($oldState, $newState), @($oldProgram, $newProgram),
                        @("%LOCALAPPDATA%\$($names.OldState)", "%LOCALAPPDATA%\$($names.State)"),
                        @("%LOCALAPPDATA%\$($names.OldProgram)", "%LOCALAPPDATA%\$($names.Program)"))) {
        foreach ($form in @(@($pair[0], $pair[1]), @($pair[0].Replace('\', '\\'), $pair[1].Replace('\', '\\')),
                            @($pair[0].Replace('\', '/'), $pair[1].Replace('\', '/')))) {
            $Text = [regex]::Replace($Text, [regex]::Escape($form[0]) + '(?=[\\/"'';\r\n]|$)', $form[1].Replace('$', '$$'),
                [Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    return $Text
}
function Test-Mentions([string]$Text, [string[]]$Folders) {
    if (-not $Text) { return $false }
    foreach ($f in $Folders) {
        foreach ($end in '\', '"', "'") { if ($Text.IndexOf($f + $end, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true } }
        if ($Text.EndsWith($f, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

# The processes that started this one: an updater from before 2.0.0-beta.11 runs from the old
# program folder and is waiting for this setup, so it is never stopped.
function Get-Ancestors {
    $ids = @(); $id = $PID
    for ($i = 0; $i -lt 12 -and $id -gt 0; $i++) {
        $ids += $id
        $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
        if (-not $p) { break }
        $id = [int]$p.ParentProcessId
    }
    return $ids
}
# Everything else that runs from the folders or names them on its command line: the notebook,
# the assistant's window and the programs it started, a helper. Says whether the assistant's
# window was among them, so it is opened again afterwards.
function Stop-FolderProcesses([string[]]$Folders) {
    $skip = Get-Ancestors
    $found = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessId -notin $skip -and ((Test-Mentions $_.ExecutablePath $Folders) -or (Test-Mentions $_.CommandLine $Folders)) })
    $window = @($found | Where-Object { $_.Name -eq 'Hermes.exe' }).Count -gt 0
    if (-not $found) { return $window }
    # taskkill says on stderr that a process of the tree had ended already; Windows PowerShell 5.1
    # would take that for a failure under Stop.
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { foreach ($p in $found) { & taskkill.exe /PID ([string]$p.ProcessId) /T /F 2>&1 | Out-Null } } finally { $ErrorActionPreference = $previous }
    $until = (Get-Date).AddSeconds(20)
    do {
        $left = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessId -in $found.ProcessId })
        if (-not $left) { return $window }
        Start-Sleep -Milliseconds 300
    } while ((Get-Date) -lt $until)
    throw "$(@($left)[0].Name) did not stop. Restart the computer and run the update again."
}

function Get-FolderBytes([string]$Path, [string[]]$Skip) {
    $total = [long]0; $stack = New-Object System.Collections.Stack; $stack.Push((Get-Item -LiteralPath $Path -Force))
    while ($stack.Count) {
        $dir = $stack.Pop()
        $entries = @(); try { $entries = @($dir.EnumerateFileSystemInfos()) } catch { }
        foreach ($e in $entries) {
            if ($e.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($e -is [IO.DirectoryInfo]) { if ($dir.FullName -ne $Path -or $e.Name -notin $Skip) { $stack.Push($e) } }
            else { $total += $e.Length }
        }
    }
    return $total
}

# A folder renamed, tried for a few seconds: a virus scanner may hold a file for a moment.
function Move-Folder([string]$From, [string]$To) {
    for ($i = 0; ; $i++) {
        try { [IO.Directory]::Move($From, $To); return }
        catch {
            if ($i -ge 10) { throw "$From could not be renamed: something on this PC still uses it (a window or a program opened there). Close it, or restart the computer, and run the update again." }
            Start-Sleep -Milliseconds 500
        }
    }
}
function Remove-Folder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $Path) { Start-Sleep -Seconds 2; Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }
    return -not (Test-Path -LiteralPath $Path)
}

# A file the setup wrote that names the old folders, rewritten in place, its old bytes kept first.
# The byte-order mark is kept as it was: Node reads these files too.
function Update-SettingFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $skip = if ($bom) { 3 } else { 0 }
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes, $skip, $bytes.Length - $skip)
    $new = Convert-OldPath $text
    if ($new -ceq $text) { return }
    $backup = Join-Path $moveDir ('file-' + @($journal.files).Count + '.bak')
    [IO.File]::WriteAllBytes($backup, $bytes)
    $journal.files = @($journal.files) + [pscustomobject]@{ path = $Path; backup = $backup }; Save-Journal
    [IO.File]::WriteAllText($Path, $new, [Text.UTF8Encoding]::new($bom))
}

# A shortcut that runs or opens something in the old folders: the Startup entry, a Start menu or
# taskbar copy. A script that changed its name gets its new name.
function Update-Shortcut([string]$Path, $Shell) {
    $lnk = $Shell.CreateShortcut($Path)
    $fields = 'TargetPath', 'Arguments', 'WorkingDirectory', 'IconLocation'
    $changed = $false
    foreach ($field in $fields) {
        $value = [string]$lnk.$field; $new = $value
        foreach ($old in (Get-GodspeedOldScriptNames).GetEnumerator()) {
            $new = [regex]::Replace($new, [regex]::Escape((Join-Path $oldProgram $old.Key)), (Join-Path $oldProgram $old.Value).Replace('$', '$$'), 'IgnoreCase')
        }
        $new = Convert-OldPath $new
        if ($new -cne $value) { $lnk.$field = $new; $changed = $true }
    }
    if (-not $changed) { return }
    $backup = Join-Path $moveDir ('shortcut-' + @($journal.shortcuts).Count + '.bak')
    Copy-Item -LiteralPath $Path -Destination $backup -Force
    $journal.shortcuts = @($journal.shortcuts) + [pscustomobject]@{ path = $Path; backup = $backup }; Save-Journal
    $lnk.Save()
}

# The user's environment, without expanding %...% (PATH is usually written that way), its kind kept.
function Update-Environment {
    $key = Get-Item -LiteralPath $EnvironmentKey -ErrorAction SilentlyContinue
    if (-not $key) { return }
    $any = $false
    foreach ($name in $key.GetValueNames()) {
        $kind = $key.GetValueKind($name)
        if ([string]$kind -notin 'String', 'ExpandString') { continue }
        $value = [string]$key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
        $new = Convert-OldPath $value
        if ($new -ceq $value) { continue }
        $journal.environment = @($journal.environment) + [pscustomobject]@{ name = $name; value = $value; kind = [string]$kind }; Save-Journal
        Set-ItemProperty -LiteralPath $EnvironmentKey -Name $name -Value $new -Type $kind
        $any = $true
    }
    if ($any) { Send-EnvironmentChanged }
}
# Programs started after this see the new values only once Windows is told; this tells it.
function Send-EnvironmentChanged {
    if ($EnvironmentKey -ne 'HKCU:\Environment') { return }
    try { [Environment]::SetEnvironmentVariable('GODSPEED_FOLDER_MOVE_NOTICE', $null, 'User') } catch { }
}

function Update-Tasks {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return }
    foreach ($task in @(Get-ScheduledTask -TaskName $TaskNames -ErrorAction SilentlyContinue)) {
        $all = @($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments) $($_.WorkingDirectory)" }) -join "`n"
        if (-not (Test-Mentions $all @($oldState, $oldProgram))) { continue }
        $xml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath
        $journal.tasks = @($journal.tasks) + [pscustomobject]@{ name = $task.TaskName; path = $task.TaskPath; xml = $xml }; Save-Journal
        $actions = @($task.Actions | ForEach-Object {
            $a = @{ Execute = (Convert-OldPath $_.Execute) }
            if ($_.Arguments) { $a.Argument = Convert-OldPath $_.Arguments }
            if ($_.WorkingDirectory) { $a.WorkingDirectory = Convert-OldPath $_.WorkingDirectory }
            New-ScheduledTaskAction @a })
        Set-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Action $actions | Out-Null
    }
}

# Puts back everything the record says was changed, last change first. Used when a step fails,
# and when the setup ended without installing the program after the move.
function Undo-Move($j) {
    # Written down first, so a second attempt after a crash knows this one had begun. Every step
    # below can run twice.
    if (Test-Path -LiteralPath $journalFile) { $j.status = 'undoing'; $script:journal = $j; Save-Journal }
    foreach ($t in @($j.tasks)) { if ($t) { Register-ScheduledTask -TaskName $t.name -TaskPath $t.path -Xml $t.xml -Force | Out-Null } }
    $envBack = $false
    foreach ($e in @($j.environment)) { if ($e) { Set-ItemProperty -LiteralPath $EnvironmentKey -Name $e.name -Value $e.value -Type $e.kind; $envBack = $true } }
    if ($envBack) { Send-EnvironmentChanged }
    foreach ($s in @($j.shortcuts)) { if ($s) { Copy-Item -LiteralPath $s.backup -Destination $s.path -Force } }
    # A file whose folder is gone was put back already, before its folder got its old name back.
    foreach ($f in @($j.files)) { if ($f -and (Test-Path -LiteralPath (Split-Path -Parent $f.path))) { [IO.File]::WriteAllBytes($f.path, [IO.File]::ReadAllBytes($f.backup)) } }
    if ($j.stateMoved -and (Test-Path -LiteralPath $newState)) { [void](Stop-FolderProcesses @($newState, $newProgram)) }
    # The assistant's program installed in the new place goes, and the old one comes back with the
    # downloads it lent to it.
    $runtime = Join-Path $newState 'hermes-runtime'
    $kept = Join-Path $newState $aside
    if ($j.runtimeAside -and (Test-Path -LiteralPath $kept)) {
        foreach ($c in @($j.caches)) {
            if ($c -and (Test-Path -LiteralPath (Join-Path $runtime $c)) -and -not (Test-Path -LiteralPath (Join-Path $kept $c))) { Move-Folder (Join-Path $runtime $c) (Join-Path $kept $c) }
        }
        if (Test-Path -LiteralPath $runtime) {
            $failed = Join-Path $newState ('hermes-runtime-failed-' + (Get-Date -Format 'yyyyMMddHHmmss'))
            Move-Folder $runtime $failed
            [void](Remove-Folder $failed)
        }
        Move-Folder $kept $runtime
    }
    if ($j.stateMoved -and (Test-Path -LiteralPath $newState) -and -not (Test-Path -LiteralPath $oldState)) { Move-Folder $newState $oldState }
    # Started again under the old names, as before the update: the notebook, the assistant's
    # window if it was open, and the jobs that were running.
    $start = @('start-notebook.ps1', 'start-full-alpha.ps1' | ForEach-Object { Join-Path $oldProgram $_ } | Where-Object { Test-Path -LiteralPath $_ })[0]
    if ($j.notebookStopped -and $start) {
        Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $start + '"'), '-NoBrowser') -WindowStyle Hidden
    }
    $open = @('open-hermes.ps1', 'open-hermes-full-alpha.ps1' | ForEach-Object { Join-Path $oldProgram $_ } | Where-Object { Test-Path -LiteralPath $_ })[0]
    if ($j.assistantWasOpen -and $open) { Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $open + '"')) -WindowStyle Hidden }
    foreach ($t in @($j.tasksStopped)) { if ($t) { Start-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } }
    Remove-Item -LiteralPath $moveDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Set-Failed([string]$Why) {
    Say "Your Godspeed Mission Control stays in its old folders and works there as before, because the move to the new ones did not finish: $Why The next update tries again."
    try { Set-Content -LiteralPath (Join-Path $LogDir 'setup-result.txt') -Value ('failed: the move to the new folders did not finish; ' + $Why) -Encoding ascii } catch { }
}

# =============================================================================
if ($Action -eq 'Undo') {
    $j = Read-Journal
    if (-not $j -or $j.run -ne $Run -or $j.status -ne 'moved') { exit 0 }
    try { Undo-Move $j; Set-Failed 'the setup ended before it had installed the program.'; exit 0 }
    catch { Say "Putting the old folders back did not finish ($($_.Exception.Message)). The next update finishes it."; exit 1 }
}

if ($Action -eq 'Finish') {
    try {
        # The old copy of the assistant's program, kept until now so a failure could go back to it.
        foreach ($left in @(Get-ChildItem -LiteralPath $newState -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $aside -or $_.Name -like 'hermes-runtime-failed-*' })) {
            if (-not (Remove-Folder $left.FullName)) { Say "The old copy of the assistant's program in $($left.FullName) could not all be removed; the next update removes the rest." }
        }
        $j = Read-Journal
        if ($j -and $j.status -eq 'moved') {
            if ($j.assistantWasOpen -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'open-hermes.ps1'))) {
                Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + (Join-Path $PSScriptRoot 'open-hermes.ps1') + '"')) -WindowStyle Hidden
            }
            foreach ($t in @($j.tasksStopped)) { if ($t) { Start-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } }
            Remove-Item -LiteralPath $moveDir -Recurse -Force -ErrorAction SilentlyContinue
            Say "Godspeed Mission Control now lives in $newProgram and keeps its notebook's data in $newState."
        }
        # The old program folder, once Windows' Apps entry names another one. The program the wizard
        # installed is in the new folder; this holds the version before it.
        $apps = $null; try { $apps = (Get-ItemProperty -LiteralPath $AppsKey -ErrorAction Stop).InstallLocation } catch { }
        if ((Test-Path -LiteralPath $oldProgram) -and -not ($apps -and ([IO.Path]::GetFullPath($apps).TrimEnd('\') -ieq $oldProgram))) {
            try { [void](Stop-FolderProcesses @($oldProgram)) } catch { }
            if (-not (Remove-Folder $oldProgram)) { Say "The old program folder $oldProgram could not all be removed; the next update removes the rest." }
        }
        # The state folder under the old name: empty, or the note an earlier update left for an older updater.
        $kind = Get-GodspeedRecordKind $oldState
        if ((Test-Path -LiteralPath $oldState) -and ($kind -eq 'moved' -or -not (Get-ChildItem -LiteralPath $oldState -Force -ErrorAction SilentlyContinue)) -and
            (Get-GodspeedRecordKind $newState) -eq 'install') {
            [void](Remove-Folder $oldState)
        }
        # AN UPDATER FROM BEFORE 2.0.0-beta.11 ("Update my mission control" of 2.0.0-beta.10) waits for
        # this setup and then reads the notebook's record in the state folder under the OLD name, to
        # see that the new version is in. It would find nothing and say the update failed although it
        # worked. So it gets a record there that names the new version and the folder the install
        # moved to, and a hidden window removes that folder once the updater has ended.
        $updater = $OldUpdater
        if (-not $updater) {
            foreach ($id in (Get-Ancestors)) {
                $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
                if ($p -and $p.CommandLine -match 'update-godspeed\.ps1' -and (Test-Mentions $p.CommandLine @($oldProgram))) { $updater = $id; break }
            }
        }
        if ($updater -and (Get-GodspeedRecordKind $newState) -eq 'install' -and -not (Test-Path -LiteralPath $oldState)) {
            $record = Get-Content -LiteralPath (Join-Path $newState 'installation.json') -Raw | ConvertFrom-Json
            New-Item -ItemType Directory -Force -Path $oldState | Out-Null
            [pscustomobject]@{ movedTo = $newState; kitCommit = $record.kitCommit; kitCommittedAt = $record.kitCommittedAt } | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $oldState 'installation.json') -Encoding UTF8
            $q = $oldState.Replace("'", "''")
            $clean = "Wait-Process -Id $updater -Timeout 86400 -ErrorAction SilentlyContinue; Start-Sleep -Seconds 2; " +
                "`$f = '$q'; `$r = Join-Path `$f 'installation.json'; " +
                "if ((Test-Path -LiteralPath `$r) -and @(Get-ChildItem -LiteralPath `$f -Force).Count -eq 1 -and (Get-Content -LiteralPath `$r -Raw) -match 'movedTo') { Remove-Item -LiteralPath `$f -Recurse -Force }"
            Start-Process -FilePath $ps -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-EncodedCommand', [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($clean))) -WindowStyle Hidden
        }
    } catch { Say "Tidying up after the move did not finish ($($_.Exception.Message)); the next update tries again." }
    exit 0
}

# =============================================================================
# Move
# A move that a crash or a closed window left half done is put back first.
$j = Read-Journal
if ($j -and $j.status -in 'moving', 'undoing') {
    Say 'An earlier move to the new folders did not finish; putting it back first.'
    try { Undo-Move $j } catch { Set-Failed "the earlier, unfinished move could not be put back ($($_.Exception.Message))."; exit 1 }
}

# Only the old program folder left: an earlier update moved the install, and its last step, which
# removes that folder, did not finish. What runs from it is stopped so the wizard can install, and
# that last step (Finish) removes it at the end of this setup.
if ((Get-GodspeedRecordKind $oldState) -ne 'install') {
    if (-not (Test-Path -LiteralPath $oldProgram)) { exit 3 }
    try {
        $stop = Join-Path $PSScriptRoot 'stop-notebook.ps1'
        if (Test-Path -LiteralPath $stop) { & $ps -NoProfile -ExecutionPolicy Bypass -File $stop; if ($LASTEXITCODE -ne 0) { throw 'the notebook could not be stopped.' } }
        [void](Stop-FolderProcesses @($oldProgram))
    } catch { Set-Failed $_.Exception.Message; exit 1 }
    exit 3
}
$script:journal = [pscustomobject]@{
    status = 'moving'; run = $Run; at = (Get-Date -Format 's'); notebookStopped = $false; assistantWasOpen = $false; tasksStopped = @()
    stateMoved = $false; runtimeAside = $false; caches = @(); runtimeBuilt = $false; files = @(); shortcuts = @(); environment = @(); tasks = @()
}
try {
    if (Test-Path -LiteralPath $newState) {
        if ((Get-GodspeedRecordKind $newState) -eq 'install') { throw "there is a notebook in both $oldState and $newState, so neither was moved." }
        if (Get-ChildItem -LiteralPath $newState -Force) { throw "$newState is in the way: it holds files but no notebook. Move it somewhere else and run the update again." }
        Remove-Item -LiteralPath $newState -Force
    }
    $config = Get-Content -LiteralPath (Join-Path $oldState 'installation.json') -Raw | ConvertFrom-Json
    $oldRuntime = Join-Path $oldState 'hermes-runtime'
    # After an uninstall the state folder has no program of the assistant's any more; the setup
    # installs one as on a new PC.
    $rebuild = Test-Path -LiteralPath (Join-Path $oldRuntime 'bin')
    if ($rebuild) {
        # The assistant's program is installed again beside the old one before the old one goes, so
        # a failure can always go back to it. That needs as much free space again, for a while.
        $need = (Get-FolderBytes $oldRuntime $caches) + 512MB
        $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($LocalAppData))).AvailableFreeSpace
        if ($free -lt $need) { throw ("moving the assistant's program needs about {0:N1} GB free on drive {1} for a few minutes, and {2:N1} GB are free." -f ($need / 1GB), [IO.Path]::GetPathRoot($LocalAppData), ($free / 1GB)) }
    }
    New-Item -ItemType Directory -Force -Path $moveDir | Out-Null
    Save-Journal
    Say "Moving Godspeed Mission Control to the folders it has from this version on: $newProgram and $newState."

    # 1. Nothing may run from the old folders while they move.
    $journal.notebookStopped = $true; Save-Journal
    $stop = @((Join-Path $PSScriptRoot 'stop-notebook.ps1'), (Join-Path $oldProgram 'stop-notebook.ps1'), (Join-Path $oldProgram 'stop-full-alpha.ps1') | Where-Object { Test-Path -LiteralPath $_ })[0]
    if ($stop) {
        & $ps -NoProfile -ExecutionPolicy Bypass -File $stop
        if ($LASTEXITCODE -ne 0) { throw 'the notebook could not be stopped. Restart the computer and run the update again.' }
    }
    $journal.assistantWasOpen = [bool](Stop-FolderProcesses @($oldState, $oldProgram)); Save-Journal
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($t in @(Get-ScheduledTask -TaskName $TaskNames -ErrorAction SilentlyContinue | Where-Object { [string]$_.State -eq 'Running' })) {
            Stop-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath
            $journal.tasksStopped = @($journal.tasksStopped) + $t.TaskName; Save-Journal
        }
    }

    # 2. The state folder: the notebook's photos and files, its backups, what the assistant has
    #    learned and its conversations, all in one rename that changes none of them.
    Move-Folder $oldState $newState
    $journal.stateMoved = $true; Save-Journal
    # For the fresh-machine tests of a move that fails, and nothing else: here, halfway, or at its last step.
    if ($env:KB_TEST_MOVE_FAIL -eq 'halfway') { throw 'it was made to fail here, halfway, for a test.' }

    # 3. The assistant's program, installed again where it now lives, with the downloads the old
    #    copy made, so little is fetched again. The old copy stays beside it until the setup has
    #    finished, so a failure can go back to it.
    if ($rebuild) {
        $runtime = Join-Path $newState 'hermes-runtime'
        Move-Folder $runtime (Join-Path $newState $aside)
        $journal.runtimeAside = $true; Save-Journal
        New-Item -ItemType Directory -Force -Path $runtime | Out-Null
        foreach ($c in $caches) {
            if (Test-Path -LiteralPath (Join-Path $newState "$aside\$c")) {
                Move-Folder (Join-Path $newState "$aside\$c") (Join-Path $runtime $c)
                $journal.caches = @($journal.caches) + $c; Save-Journal
            }
        }
        Say "Installing the assistant's program again in its new folder. This takes a few minutes, up to half an hour; your notes, files and conversations are not touched."
        $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
        try { & $ps -NoProfile -ExecutionPolicy Bypass -File $RuntimeBuilder -State $newState -Workspace $config.workspace -Port ([int]$config.port) -Provision -ForceIsolatedInstall -RuntimeOnly | Out-Host; $code = $LASTEXITCODE }
        finally { $ErrorActionPreference = $previous }
        if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $runtime 'bin'))) {
            throw "the assistant's program could not be installed in its new folder (what happened is in $(Join-Path $oldState 'hermes-install.log'))."
        }
        $journal.runtimeBuilt = $true; Save-Journal
    }

    # 4. What points into the old folders: the setup's records and setting files, the shortcuts,
    #    the user's environment (GODSPEED_*, PATH) and the scheduled tasks.
    foreach ($f in 'installation.json', 'assistant.json', 'hermes-profile\config.yaml', 'hermes-profile\.env') { Update-SettingFile (Join-Path $newState $f) }
    if ($config.workspace) { Update-SettingFile (Join-Path $config.workspace '.vscode\settings.json') }
    $shell = New-Object -ComObject WScript.Shell
    foreach ($folder in $ShortcutFolders) {
        foreach ($lnk in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) { Update-Shortcut $lnk.FullName $shell }
    }
    Update-Environment
    Update-Tasks

    if ($env:KB_TEST_MOVE_FAIL -and $env:KB_TEST_MOVE_FAIL -ne 'halfway') { throw 'it was made to fail here, for a test.' }

    $journal.status = 'moved'; Save-Journal
    exit 0
} catch {
    $why = $_.Exception.Message
    try { Undo-Move $journal }
    catch { $why += " Putting it back did not finish either ($($_.Exception.Message)); the next update finishes it." }
    Set-Failed $why
    exit 1
}

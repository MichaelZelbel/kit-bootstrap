# =============================================================================
# kit-bootstrap / windows / move-to-new-folders.ps1
#
# Moves an install made before 2.0.0-beta.11 out of the folders whose names said "Full Alpha" and
# into the names godspeed-folders.ps1 gives (product issue #6), once, and never leaves half of it.
#
#   -Action Move     run by the wizard before it copies anything (PrepareToInstall). Writes down
#                    what it will do and keeps a copy of every file it will change, BEFORE the
#                    first change; points the Startup entry at -Action Resume; stops the notebook,
#                    the assistant and the Godspeed jobs; RENAMES the state folder (one step on the
#                    same drive: nothing is copied, so a full disk cannot break it, and the person's
#                    notes, photos and files change by no byte); then points what inside it names
#                    the old folder at the new one, the assistant's program included (its Python
#                    environment, its launchers and its links), and checks that the program starts
#                    from there. The program itself is not moved: the wizard installs it into the
#                    new program folder, which is new and empty, so a cancelled setup leaves the old
#                    one exactly as it was.
#                    Exit 0: moved, install into the new program folder.
#                         3: nothing to move.
#                         4: put off: nothing is moved (or all of it was put back), the install works
#                            under its old names, and the update goes on there; the next one tries again.
#                         1: put back only in part (a folder still held after minutes of waiting):
#                            the next sign-in or the next setup finishes it, from the record.
#   -Action Resume   finishes or puts back a move that did not end: from the Startup entry at the
#                    next sign-in (-Start then starts the notebook), from start-notebook.ps1, from
#                    the next setup, and from the wizard when it ends (DeinitializeSetup). A move
#                    whose program was installed completely is finished; any other is put back.
#                    A move that belongs to a setup still running is left to that setup.
#   -Action Finish   run by setup-godspeed.ps1 once the new install works: points what lies outside
#                    the two folders at the new names (the user's settings, shortcuts, scheduled
#                    tasks, the mission control's editor settings), removes the old program folder,
#                    starts again what was stopped, and leaves an older updater the record it reads.
#
# What it never does: delete or rewrite the person's data. Notes, photos, files, settings, backups
# and what the assistant learned move with the folder that holds them, by its rename; only the
# setup's own records and the files of the assistant's program that name the folder are changed,
# and each of them is copied first so it can be put back byte for byte.
#
# The record (%LOCALAPPDATA%\Godspeed\folder-move\journal.json) is written before the first change.
# Beside it are the copies, a copy of this script (the Startup entry runs it while a move is under
# way, when neither program folder may be complete), and some reserved disk space that a put-back
# frees first, so even a disk that filled up meanwhile can take the old files back.
# =============================================================================
param(
    [ValidateSet('Move', 'Resume', 'Finish')][string]$Action = 'Move',
    # The setup run this belongs to (the wizard's temporary folder): Resume with the same run is the
    # wizard itself ending, and a move of another run whose setup still runs is left alone.
    [string]$Run = '',
    # Resume: start the notebook afterwards (what the Startup entry does at sign-in), or start
    # nothing (the notebook's own start script, which starts it itself).
    [switch]$Start,
    [switch]$NoStart,
    [string]$LocalAppData = $env:LOCALAPPDATA,
    [string]$LogDir = (Join-Path $env:LOCALAPPDATA 'Godspeed'),
    # How long a folder that something still holds is waited for: before the move is put off, and
    # before a put-back is left to the next start.
    [int]$HoldSeconds = 60,
    [int]$HoldBackSeconds = 300,
    # The rest are for the tests: where shortcuts are looked for, the Startup folder, the user's
    # environment, the names of the Godspeed jobs, the Apps entry, what installs the assistant's
    # program again when it cannot be pointed at its new folder, the process of an older updater
    # (found among the processes that started this one when not given), and the setup this move
    # belongs to (-1: the process that started this one; 0: none).
    [string[]]$ShortcutFolders,
    [string]$StartupFolder = [Environment]::GetFolderPath('Startup'),
    [string]$EnvironmentKey = 'HKCU:\Environment',
    [string]$TaskNames = 'Godspeed*',
    [string]$AppsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9929B7B4-B588-46D2-AC79-01F7EBD7FA92}_is1',
    [string]$RuntimeBuilder = (Join-Path $PSScriptRoot 'ensure-hermes.ps1'),
    [int]$OldUpdater = 0,
    [int]$Owner = -1
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
$copies = Join-Path $moveDir 'copies'
$tools = Join-Path $moveDir 'tools'
$reserve = Join-Path $moveDir 'reserve.bin'
$logFile = Join-Path $LogDir 'setup-log.txt'
$noteFile = Join-Path $LogDir 'folder-move-note.txt'
$aside = 'hermes-runtime-before-move'
$marker = '.godspeed-move'
$caches = 'uv-cache', 'npm-cache', 'browser-cache'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$startupLink = Join-Path $StartupFolder 'Godspeed Mission Control.lnk'
if (-not $ShortcutFolders) {
    $ShortcutFolders = @($StartupFolder, [Environment]::GetFolderPath('Desktop'),
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
# What the wizard shows while the move runs: it reads the lines that start with STEP.
function Step([string]$Text) {
    Write-Host "STEP $Text"
    try { Add-Content -LiteralPath $logFile -Value ((Get-Date -Format 's') + ' ' + $Text) -Encoding UTF8 -ErrorAction Stop } catch { }
}

# For the tests of a move that is cut off (as by a sign-out or a power cut): this process ends here,
# at once, leaving everything as it is at that moment.
function Test-CutOff([string]$Where) { if ($env:KB_TEST_MOVE_STOP -eq $Where) { [Environment]::Exit(9) } }

function Save-Journal {
    $tmp = $journalFile + '.tmp'
    $script:journal | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $journalFile -Force
}
# A put-back must not stop because the record cannot be written (a full disk, a held file).
function Save-JournalQuietly { try { Save-Journal } catch { } }
function Read-Journal {
    if (-not (Test-Path -LiteralPath $journalFile)) { return $null }
    try { return (Get-Content -LiteralPath $journalFile -Raw | ConvertFrom-Json) } catch { return $null }
}
function Set-J([string]$Name, $Value) { $script:journal | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

# Every way a path into the old folders is written: as it is, inside JSON (backslashes doubled),
# with forward slashes (Node, Git Bash), as a file:/// address (Python's install records), and as
# %LOCALAPPDATA%\... in the environment. The state folder's name starts with the program folder's,
# so it is replaced first, and a name only counts where a separator, a quote or the end follows it.
function Convert-OldPath([string]$Text) {
    if (-not $Text) { return $Text }
    foreach ($pair in @(@($oldState, $newState), @($oldProgram, $newProgram),
                        @("%LOCALAPPDATA%\$($names.OldState)", "%LOCALAPPDATA%\$($names.State)"),
                        @("%LOCALAPPDATA%\$($names.OldProgram)", "%LOCALAPPDATA%\$($names.Program)"))) {
        $forms = @(@($pair[0], $pair[1]), @($pair[0].Replace('\', '\\'), $pair[1].Replace('\', '\\')),
                   @($pair[0].Replace('\', '/'), $pair[1].Replace('\', '/')))
        if ($pair[0] -match '^[A-Za-z]:\\') { $forms += , @(([Uri]$pair[0]).AbsoluteUri, ([Uri]$pair[1]).AbsoluteUri) }
        foreach ($form in $forms) {
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
# The setup this move belongs to, so that a Resume from elsewhere (the notebook's start script, run
# by the setup itself) leaves a move alone while its setup still runs.
function Get-OwnerRecord {
    $id = $Owner
    if ($id -lt 0) { $me = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction SilentlyContinue; $id = if ($me) { [int]$me.ParentProcessId } else { 0 } }
    if ($id -le 0) { return $null }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue
    if (-not $p) { return $null }
    return [pscustomobject]@{ pid = $id; started = ([datetime]$p.CreationDate).ToUniversalTime().ToString('o') }
}
function Test-OwnerAlive($o) {
    if (-not $o -or [int]$o.pid -le 0) { return $false }
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$([int]$o.pid)" -ErrorAction SilentlyContinue
    return [bool]($p -and ([datetime]$p.CreationDate).ToUniversalTime().ToString('o') -eq [string]$o.started)
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
function Get-FreeBytes { return (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($LocalAppData))).AvailableFreeSpace }

# A folder renamed: one step on the same drive, nothing copied. Something may hold a file in it for
# a while (a virus scanner checking the files, a window opened there, the search index), so it is
# tried again and again, ever more slowly, for up to $Seconds. Says whether it was renamed.
function Move-Folder([string]$From, [string]$To, [int]$Seconds) {
    $until = (Get-Date).AddSeconds([Math]::Max(1, $Seconds)); $wait = 250; $told = $false
    while ($true) {
        try { [IO.Directory]::Move($From, $To); return $true }
        catch {
            if ((Get-Date) -ge $until) { return $false }
            if (-not $told -and $wait -ge 1000) { Step "Waiting for $From, which something on this PC still uses (often a virus scanner checking it)."; $told = $true }
            Start-Sleep -Milliseconds $wait
            $wait = [Math]::Min(5000, $wait * 2)
        }
    }
}
function Remove-Folder([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $true }
    for ($i = 0; $i -lt 5; $i++) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $Path)) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}
function Test-HasFiles([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool](Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction SilentlyContinue | Select-Object -First 1)
}

# -----------------------------------------------------------------------------
# THE ASSISTANT'S PROGRAM (Hermes, in hermes-runtime) records the folder it was installed in, and a
# renamed copy does not start: its Python environment (pyvenv.cfg) names the Python it was made
# from, the link to that Python (a junction) names it by absolute path, npm's workspace links do
# too, every launcher (hermes.exe and the others, made by uv) carries the path of its Python in a
# resource, and the install records name the source folder. Until 2.0.0-beta.15 the move installed
# the whole program again for that, which took up to half an hour and as much disk space again;
# these are a few dozen small files, pointed at the new folder in a second.
$launcherApi = $true
if (-not ('KbMoveLauncher' -as [type])) { try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class KbMoveLauncher {
    const uint LOAD_LIBRARY_AS_DATAFILE = 0x2, LOAD_LIBRARY_AS_IMAGE_RESOURCE = 0x20;
    static readonly IntPtr RT_RCDATA = (IntPtr)10;
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryExW(string f, IntPtr h, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr FindResourceExW(IntPtr h, IntPtr type, string name, ushort lang);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr LoadResource(IntPtr h, IntPtr r);
    [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr LockResource(IntPtr r);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint SizeofResource(IntPtr h, IntPtr r);
    delegate bool EnumLangProc(IntPtr h, IntPtr type, IntPtr name, ushort lang, IntPtr p);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool EnumResourceLanguagesW(IntPtr h, IntPtr type, string name, EnumLangProc f, IntPtr p);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr BeginUpdateResourceW(string f, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool UpdateResourceW(IntPtr h, IntPtr type, string name, ushort lang, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool EndUpdateResourceW(IntPtr h, bool discard);
    // The bytes of one named data resource and its language; null when the file has none.
    public static byte[] Read(string file, string name, out ushort lang) {
        lang = 0;
        IntPtr h = LoadLibraryExW(file, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE | LOAD_LIBRARY_AS_IMAGE_RESOURCE);
        if (h == IntPtr.Zero) return null;
        try {
            ushort found = 0; bool any = false;
            EnumResourceLanguagesW(h, RT_RCDATA, name, (m, t, n, l, p) => { found = l; any = true; return false; }, IntPtr.Zero);
            if (!any) return null;
            lang = found;
            IntPtr r = FindResourceExW(h, RT_RCDATA, name, found);
            if (r == IntPtr.Zero) return null;
            uint size = SizeofResource(h, r);
            IntPtr at = LockResource(LoadResource(h, r));
            byte[] b = new byte[size];
            Marshal.Copy(at, b, 0, (int)size);
            return b;
        } finally { FreeLibrary(h); }
    }
    // Several named data resources replaced in one write of the file.
    public static void Write(string file, string[] names, ushort[] langs, byte[][] data) {
        IntPtr u = BeginUpdateResourceW(file, false);
        if (u == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        for (int i = 0; i < names.Length; i++) {
            if (!UpdateResourceW(u, RT_RCDATA, names[i], langs[i], data[i], (uint)data[i].Length)) {
                int e = Marshal.GetLastWin32Error(); EndUpdateResourceW(u, true); throw new System.ComponentModel.Win32Exception(e);
            }
        }
        if (!EndUpdateResourceW(u, false)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    }
}
'@
} catch { $launcherApi = $false } }
# A PC that cannot make this small helper (a locked-down Windows) cannot point the launchers at the
# new folder: there the move is put off before it changes anything (below), and a put-back copies
# the launchers' old bytes back, which needs no helper.
Add-Type -AssemblyName System.IO.Compression

# What in the assistant's program names the folder, found by looking, never by a list of Hermes'
# files: links anywhere in it (never followed, and the downloads are skipped), launchers in its
# Scripts and bin folders, and its small setting and install-record files. Paths are relative to
# the state folder, so the same list serves wherever the folder is.
$textExtensions = '.cfg', '.pth', '.json', '.toml', '.yaml', '.yml', '.env', '.ini', '.cmd', '.bat', '.ps1', '.sh', '.csh', '.fish', '.nu', '.xsh', '.npmrc', '.txt', ''
function Find-RuntimePointers([string]$State) {
    $found = New-Object System.Collections.ArrayList
    $rt = Join-Path $State 'hermes-runtime'
    if (-not (Test-Path -LiteralPath $rt)) { return $found.ToArray() }
    $folders = @($oldState, $oldProgram)
    $stack = New-Object System.Collections.Stack; $stack.Push([pscustomobject]@{ Dir = (Get-Item -LiteralPath $rt -Force); Files = $true })
    while ($stack.Count) {
        $item = $stack.Pop(); $dir = $item.Dir
        $subs = @(); try { $subs = @($dir.EnumerateDirectories()) } catch { }
        foreach ($d in $subs) {
            if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $target = @((Get-Item -LiteralPath $d.FullName -Force).Target)[0]
                if (Test-Mentions $target $folders) { [void]$found.Add([pscustomobject]@{ kind = 'link'; rel = $d.FullName.Substring($State.Length + 1); target = $target; backup = $null }) }
                continue
            }
            if ($dir.FullName -eq $rt -and $d.Name -in $caches) { continue }
            if ($d.Name -in '.git', '__pycache__') { continue }
            # node_modules and the Python install: only their links are looked at, not their files.
            $files = $item.Files -and $d.Name -ne 'node_modules' -and $d.Name -notlike 'cpython-*' -and $dir.Name -ne 'site-packages'
            if ($d.Name -like '*.dist-info') { if ($dir.Name -eq 'site-packages') { $direct = Join-Path $d.FullName 'direct_url.json'; if (Test-Path -LiteralPath $direct) { Add-TextPointer $found $direct $State } }; continue }
            $stack.Push([pscustomobject]@{ Dir = $d; Files = $files })
        }
        $isSite = $dir.Name -eq 'site-packages'
        if (-not $item.Files -and -not $isSite) { continue }
        $all = @(); try { $all = @($dir.EnumerateFiles()) } catch { }
        foreach ($f in $all) {
            if ($isSite) {
                if ($f.Extension -in '.pth', '.egg-link' -or ($f.Extension -eq '.py' -and $f.Name -like '__editable__*')) { Add-TextPointer $found $f.FullName $State }
                continue
            }
            if ($f.Extension -eq '.exe') {
                if ($launcherApi -and $f.Length -le 4MB -and $dir.Name -in 'Scripts', 'bin') {
                    $lang = [uint16]0
                    $b = [KbMoveLauncher]::Read($f.FullName, 'UV_PYTHON_PATH', [ref]$lang)
                    if ($b -and (Test-Mentions ([Text.Encoding]::UTF8.GetString($b)) $folders)) { [void]$found.Add([pscustomobject]@{ kind = 'launcher'; rel = $f.FullName.Substring($State.Length + 1); target = $null; backup = $null }) }
                }
                continue
            }
            if ($f.Length -le 512KB -and ($f.Extension -in $textExtensions -or $f.Name -eq 'pyvenv.cfg')) { Add-TextPointer $found $f.FullName $State }
        }
    }
    return $found.ToArray()
}
# A file is rewritten as text only when it is text: one with a zero byte in it is never touched.
function Add-TextPointer($List, [string]$Path, [string]$Root) {
    $bytes = $null; try { $bytes = [IO.File]::ReadAllBytes($Path) } catch { return }
    if ([Array]::IndexOf($bytes, [byte]0) -ge 0) { return }
    $text = [Text.Encoding]::UTF8.GetString($bytes)
    if ((Convert-OldPath $text) -cne $text) { [void]$List.Add([pscustomobject]@{ kind = 'text'; rel = $Path.Substring($Root.Length + 1); target = $null; backup = $null }) }
}
# The setup's own records and setting files in the state folder, the assistant's profile and its
# window's settings: the small files at the top of each.
function Find-RecordPointers([string]$State) {
    $found = New-Object System.Collections.ArrayList
    foreach ($folder in @($State, (Join-Path $State 'hermes-profile'), (Join-Path $State 'hermes-desktop-data'))) {
        foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue)) {
            # process.json describes the notebook that runs now, which the move stops: no setting.
            if ($f.Name -eq 'process.json') { continue }
            if ($f.Length -le 1MB -and $f.Extension -in '.json', '.yaml', '.yml', '.env', '.toml', '.cfg', '.ini') { Add-TextPointer $found $f.FullName $State }
        }
    }
    return $found.ToArray()
}

# A text file rewritten in place, its byte-order mark kept as it was (Node reads these files too).
function Update-TextFile([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $skip = if ($bom) { 3 } else { 0 }
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes, $skip, $bytes.Length - $skip)
    $new = Convert-OldPath $text
    if ($new -cne $text) { [IO.File]::WriteAllText($Path, $new, [Text.UTF8Encoding]::new($bom)) }
}
# A launcher pointed at its Python in the new folder: the path it starts (UV_PYTHON_PATH), and the
# first line of the script it carries (UV_SCRIPT_DATA, a small zip), which names that Python too.
function Update-Launcher([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $resNames = @(); $langs = @(); $data = @()
    $lang = [uint16]0
    $b = [KbMoveLauncher]::Read($Path, 'UV_PYTHON_PATH', [ref]$lang)
    if ($b) {
        $p = [Text.Encoding]::UTF8.GetString($b); $np = Convert-OldPath $p
        if ($np -cne $p) { $resNames += 'UV_PYTHON_PATH'; $langs += $lang; $data += , ([Text.Encoding]::UTF8.GetBytes($np)) }
    }
    $s = [KbMoveLauncher]::Read($Path, 'UV_SCRIPT_DATA', [ref]$lang)
    if ($s) {
        $zipped = Convert-ZipText $s
        if ($zipped) { $resNames += 'UV_SCRIPT_DATA'; $langs += $lang; $data += , $zipped }
    }
    if (-not $resNames) { return }
    for ($i = 0; ; $i++) {
        try { [KbMoveLauncher]::Write($Path, [string[]]$resNames, [uint16[]]$langs, [byte[][]]$data); return }
        catch { if ($i -ge 5) { throw "$Path could not be pointed at the new folder ($($_.Exception.Message))." }; Start-Sleep -Milliseconds 500 }
    }
}
# The zip's entries with the old folder replaced, or $null when none names it.
function Convert-ZipText([byte[]]$Bytes) {
    $in = New-Object IO.MemoryStream(, $Bytes)
    $zip = New-Object IO.Compression.ZipArchive($in, [IO.Compression.ZipArchiveMode]::Read)
    $entries = @(); $changed = $false
    try {
        foreach ($e in @($zip.Entries)) {
            $r = New-Object IO.StreamReader($e.Open(), [Text.UTF8Encoding]::new($false)); $text = $r.ReadToEnd(); $r.Close()
            $new = Convert-OldPath $text
            if ($new -cne $text) { $changed = $true }
            $entries += , @($e.FullName, $new)
        }
    } finally { $zip.Dispose() }
    if (-not $changed) { return $null }
    $out = New-Object IO.MemoryStream
    $zip = New-Object IO.Compression.ZipArchive($out, [IO.Compression.ZipArchiveMode]::Create, $true)
    try {
        foreach ($e in $entries) {
            $w = New-Object IO.StreamWriter($zip.CreateEntry($e[0], [IO.Compression.CompressionLevel]::NoCompression).Open(), [Text.UTF8Encoding]::new($false))
            $w.Write($e[1]); $w.Close()
        }
    } finally { $zip.Dispose() }
    return $out.ToArray()
}
# A link made again with another target. A junction needs no rights and its target need not exist yet.
function Reset-Link([string]$Path, [string]$Target) {
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (@($item.Target)[0] -ieq $Target) { return }
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "$Path is no longer a link, so it was left alone." }
        [IO.Directory]::Delete($Path)
    }
    $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { & cmd.exe /d /c mklink /J "$Path" "$Target" 2>&1 | Out-Null } finally { $ErrorActionPreference = $previous }
    if (-not (Test-Path -LiteralPath $Path)) { throw "the link $Path could not be made again." }
}

# Every pointer of the record made to match where the state folder is now: under the new name they
# are pointed at it (again: each step can run twice), under the old name their copies are put back.
function Set-Pointers([string]$State, [switch]$Back) {
    $errors = @()
    foreach ($p in @($script:journal.pointers)) {
        if (-not $p) { continue }
        $path = Join-Path $State $p.rel
        try {
            if ($p.kind -eq 'link') { Reset-Link $path $(if ($Back) { $p.target } else { Convert-OldPath $p.target }) }
            elseif ($Back) {
                # No copy: the move was cut off before it made one, so before it changed the file.
                if ((Test-Path -LiteralPath $p.backup) -and (Test-Path -LiteralPath (Split-Path -Parent $path))) { [IO.File]::WriteAllBytes($path, [IO.File]::ReadAllBytes($p.backup)) }
            }
            elseif ($p.kind -eq 'launcher') { Update-Launcher $path }
            else { Update-TextFile $path }
        } catch { $errors += "$($p.rel): $($_.Exception.Message)" }
    }
    return $errors
}

# The assistant's program, started from the new folder: its Python with Hermes' own code, and the
# hermes command. A check that cannot be made (no program here, or one made only for the tests) is
# not a failure.
function Test-Runtime([string]$State) {
    if ($env:KB_TEST_RUNTIME_CHECK_FAIL) { return 'it was made to fail here, for a test.' }
    $rt = Join-Path $State 'hermes-runtime'
    $py = Join-Path $rt 'hermes-agent\venv\Scripts\python.exe'
    $cli = @((Join-Path $rt 'bin\hermes.exe'), (Join-Path $rt 'bin\hermes.cmd') | Where-Object { Test-Path -LiteralPath $_ })[0]
    $checks = @(); $lang = [uint16]0
    if ((Test-Path -LiteralPath $py) -and [KbMoveLauncher]::Read($py, 'UV_PYTHON_PATH', [ref]$lang)) {
        $checks += , @($py, @('-c', '"import sys, hermes_cli; print(sys.prefix)"'), (Join-Path $rt 'hermes-agent\venv'))
    }
    if ($cli -and ($cli.EndsWith('.cmd') -or [KbMoveLauncher]::Read($cli, 'UV_PYTHON_PATH', [ref]$lang))) { $checks += , @($cli, @('--version'), $null) }
    # Its own profile, never a default one in the user's home.
    $env:HERMES_HOME = Join-Path $State 'hermes-profile'
    foreach ($c in $checks) {
        $out = Join-Path $moveDir 'check-out.txt'; $err = Join-Path $moveDir 'check-err.txt'
        $p = Start-Process -FilePath $c[0] -ArgumentList $c[1] -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
        # Without its handle taken now, a process waited for with a time limit has no exit code.
        $null = $p.Handle
        if (-not $p.WaitForExit(180000)) { try { $p.Kill() } catch { }; return "$(Split-Path -Leaf $c[0]) did not answer within three minutes." }
        $said = ((Get-Content -LiteralPath $out -Raw -ErrorAction SilentlyContinue) + ' ' + (Get-Content -LiteralPath $err -Raw -ErrorAction SilentlyContinue)).Trim()
        if ($p.ExitCode -ne 0) { return "$(Split-Path -Leaf $c[0]) ended with $($p.ExitCode) ($($said.Substring(0, [Math]::Min(200, $said.Length))))." }
        if ($c[2] -and -not $said.StartsWith($c[2], [StringComparison]::OrdinalIgnoreCase)) { return "its Python still runs from $said." }
    }
    return $null
}

# -----------------------------------------------------------------------------
# The Apps entry, kept as it was, so a put-back after the wizard had rewritten it can restore it.
function Get-AppsValues {
    $key = Get-Item -LiteralPath $AppsKey -ErrorAction SilentlyContinue
    if (-not $key) { return $null }
    return @($key.GetValueNames() | ForEach-Object { [pscustomobject]@{ name = $_; kind = [string]$key.GetValueKind($_); data = $key.GetValue($_, $null, 'DoNotExpandEnvironmentNames') } })
}
function Restore-Apps($Saved) {
    if ($null -eq $Saved) { if (Test-Path -LiteralPath $AppsKey) { Remove-Item -LiteralPath $AppsKey -Recurse -Force }; return }
    if (-not (Test-Path -LiteralPath $AppsKey)) { New-Item -Path $AppsKey -Force | Out-Null }
    $key = Get-Item -LiteralPath $AppsKey
    $keep = @($Saved | ForEach-Object { $_.name })
    foreach ($n in @($key.GetValueNames())) { if ($n -notin $keep) { Remove-ItemProperty -LiteralPath $AppsKey -Name $n -Force } }
    foreach ($v in @($Saved)) { if ($v) { Set-ItemProperty -LiteralPath $AppsKey -Name $v.name -Value $v.data -Type $v.kind } }
}
function Get-AppsLocation {
    try { $l = (Get-ItemProperty -LiteralPath $AppsKey -ErrorAction Stop).InstallLocation; if ($l) { return [IO.Path]::GetFullPath($l).TrimEnd('\') } } catch { }
    return $null
}
# The wizard put the whole program into the new folder: it writes the Apps entry and its uninstall
# record after the last file. From then on a move is finished, never put back: the new version may
# already have changed the notebook's data.
function Test-ProgramComplete {
    return ((Get-AppsLocation) -ieq $newProgram) -and (Test-Path -LiteralPath (Join-Path $newProgram 'unins000.dat')) -and
        (Test-Path -LiteralPath (Join-Path $newProgram 'start-notebook.ps1'))
}

# What the Startup entry runs while a move is under way: this script, from the copy beside the record.
function Set-ResumeEntry {
    $shell = New-Object -ComObject WScript.Shell
    New-Item -ItemType Directory -Force -Path $StartupFolder | Out-Null
    $lnk = $shell.CreateShortcut($startupLink)
    $lnk.TargetPath = $ps
    $lnk.Arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $tools 'move-to-new-folders.ps1') + '" -Action Resume' + $(if ($script:journal.startup.existed) { ' -Start' } else { '' })
    $lnk.Description = 'Finishes moving Godspeed Mission Control to its new folders, then starts your notebook'
    $lnk.WindowStyle = 7
    $lnk.Save()
}
function Test-ResumeEntry {
    if (-not (Test-Path -LiteralPath $startupLink)) { return $false }
    return ((New-Object -ComObject WScript.Shell).CreateShortcut($startupLink).Arguments -match 'move-to-new-folders\.ps1" -Action Resume')
}
function Restore-StartupEntry($j) {
    if ($j.startup.existed) { Copy-Item -LiteralPath $j.startup.backup -Destination $startupLink -Force }
    elseif (Test-ResumeEntry) { Remove-Item -LiteralPath $startupLink -Force }
}

# A shortcut that runs or opens something in the old folders: the Startup entry, a Start menu,
# Desktop or taskbar copy. A script that changed its name gets its new name.
function Update-Shortcut([string]$Path, $Shell) {
    $lnk = $Shell.CreateShortcut($Path)
    $changed = $false
    foreach ($field in 'TargetPath', 'Arguments', 'WorkingDirectory', 'IconLocation') {
        $value = [string]$lnk.$field; $new = $value
        foreach ($old in (Get-GodspeedOldScriptNames).GetEnumerator()) {
            $new = [regex]::Replace($new, [regex]::Escape((Join-Path $oldProgram $old.Key)), (Join-Path $oldProgram $old.Value).Replace('$', '$$'), 'IgnoreCase')
        }
        $new = Convert-OldPath $new
        if ($new -cne $value) { $lnk.$field = $new; $changed = $true }
    }
    if ($changed) { $lnk.Save() }
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
        Set-ItemProperty -LiteralPath $EnvironmentKey -Name $name -Value $new -Type $kind
        $any = $true
    }
    # Programs started after this see the new values only once Windows is told; this tells it.
    if ($any -and $EnvironmentKey -eq 'HKCU:\Environment') { try { [Environment]::SetEnvironmentVariable('GODSPEED_FOLDER_MOVE_NOTICE', $null, 'User') } catch { } }
}
function Update-Tasks {
    if (-not (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)) { return }
    foreach ($task in @(Get-ScheduledTask -TaskName $TaskNames -ErrorAction SilentlyContinue)) {
        $all = @($task.Actions | ForEach-Object { "$($_.Execute) $($_.Arguments) $($_.WorkingDirectory)" }) -join "`n"
        if (-not (Test-Mentions $all @($oldState, $oldProgram))) { continue }
        $actions = @($task.Actions | ForEach-Object {
            $a = @{ Execute = (Convert-OldPath $_.Execute) }
            if ($_.Arguments) { $a.Argument = Convert-OldPath $_.Arguments }
            if ($_.WorkingDirectory) { $a.WorkingDirectory = Convert-OldPath $_.WorkingDirectory }
            New-ScheduledTaskAction @a })
        Set-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -Action $actions | Out-Null
    }
}

function Start-Script([string]$Path, [string[]]$Arguments = @()) {
    Start-Process -FilePath $ps -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', ('"' + $Path + '"')) + $Arguments) -WindowStyle Hidden
}
function Set-Note([string]$Text) { try { Set-Content -LiteralPath $noteFile -Value $Text -Encoding UTF8 } catch { } }

# -----------------------------------------------------------------------------
# PUT BACK. Looks at what is there, not only at the record, because a move can have been cut off
# at any point: each step is done only when it is still needed, and each can run twice. Never stops
# at a step that fails; the next step is tried all the same. Says 'back' when the install is under
# its old names again with every copy put back, 'held' when the state folder could not get its old
# name back within $HoldBackSeconds (the record stays, and the next start tries again).
function Undo-Move($j) {
    $script:journal = $j
    $j.status = 'undoing'; Save-JournalQuietly
    # The reserved space first, so that putting back can always write what it must.
    Remove-Item -LiteralPath $reserve -Force -ErrorAction SilentlyContinue
    $errors = @()
    $at = if ((Get-GodspeedRecordKind $newState) -eq 'install' -and -not (Test-Path -LiteralPath $oldState)) { $newState } else { $oldState }
    try { [void](Stop-FolderProcesses @($oldState, $newState, $newProgram)) } catch { $errors += $_.Exception.Message }
    # The assistant's program, when it had to be installed again: the new copy goes, the old one
    # comes back with the downloads it lent to it.
    $runtime = Join-Path $at 'hermes-runtime'; $kept = Join-Path $at $aside
    if (Test-Path -LiteralPath $kept) {
        try {
            foreach ($c in $caches) {
                if ((Test-Path -LiteralPath (Join-Path $runtime $c)) -and -not (Test-Path -LiteralPath (Join-Path $kept $c))) {
                    if (-not (Move-Folder (Join-Path $runtime $c) (Join-Path $kept $c) 30)) { throw "the downloads in $runtime\$c could not be given back." }
                }
            }
            if (Test-Path -LiteralPath $runtime) {
                $failed = Join-Path $at ('hermes-runtime-failed-' + (Get-Date -Format 'yyyyMMddHHmmss'))
                if (-not (Move-Folder $runtime $failed 30)) { throw "$runtime could not be moved aside." }
                [void](Remove-Folder $failed)
            }
            if (-not (Move-Folder $kept $runtime 30)) { throw "$kept could not get its name back." }
        } catch { $errors += $_.Exception.Message }
    }
    # The state folder under its old name again: one rename, as the move was.
    if ($at -eq $newState) {
        if (Move-Folder $newState $oldState $HoldBackSeconds) { $at = $oldState }
        else { $errors += "$newState could not get its old name back: something on this PC still uses it." }
    }
    # What inside it names a folder matches where it is now.
    $pointerErrors = @(Set-Pointers $at -Back:($at -eq $oldState))
    $errors += $pointerErrors
    if ($at -eq $newState -or $pointerErrors) {
        # The old program cannot run with the new name, nor with a file that still names the new
        # one. The record and its copies stay, the Startup entry keeps running this script, and
        # the next start (or the next setup) tries again.
        $j.status = 'undoing'; Save-JournalQuietly
        Say "Godspeed Mission Control could not be put back into its old folders yet ($($errors -join ' ')). It is finished when you next sign in, or when you run the installer again."
        return 'held'
    }
    try { Restore-Apps $j.apps } catch { $errors += "the Apps entry: $($_.Exception.Message)" }
    if ($j.newProgramMade -and (Test-Path -LiteralPath $newProgram)) {
        try { [void](Stop-FolderProcesses @($newProgram)) } catch { }
        if (-not (Remove-Folder $newProgram)) { $errors += "$newProgram could not all be removed; the next update removes it." }
    } else { Remove-Item -LiteralPath (Join-Path $newProgram $marker) -Force -ErrorAction SilentlyContinue }
    try { Restore-StartupEntry $j } catch { $errors += "the Startup entry: $($_.Exception.Message)" }
    # Started again under the old names, as before the update: the notebook, the assistant's
    # window if it was open, and the jobs that were running.
    $starter = @('start-notebook.ps1', 'start-full-alpha.ps1' | ForEach-Object { Join-Path $oldProgram $_ } | Where-Object { Test-Path -LiteralPath $_ })[0]
    if (($j.stopped.notebook -or $Start) -and $starter -and -not $NoStart) { Start-Script $starter @('-NoBrowser') }
    $opener = @('open-hermes.ps1', 'open-hermes-full-alpha.ps1' | ForEach-Object { Join-Path $oldProgram $_ } | Where-Object { Test-Path -LiteralPath $_ })[0]
    if ($j.stopped.assistant -and $opener) { Start-Script $opener }
    foreach ($t in @($j.stopped.tasks)) { if ($t) { Start-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } }
    if ($errors) { Say "Putting the old folders back left this undone: $($errors -join ' ')" }
    Remove-Item -LiteralPath $moveDir -Recurse -Force -ErrorAction SilentlyContinue
    return 'back'
}

# FINISH: the install works from the new folders. What lies outside them gets the new names, the
# old program folder goes, and what was stopped starts again. Only once the state folder is under
# the new name: after a move that was put off, the install stays under the old names, and so do
# the shortcuts and settings that name them.
function Complete-Move {
    $j = Read-Journal
    $script:journal = $j
    $moved = (Get-GodspeedRecordKind $newState) -eq 'install' -and (Get-GodspeedRecordKind $oldState) -ne 'install'
    if ($moved -and $j) {
        Step 'Pointing the shortcuts, settings and scheduled jobs at the new folders'
        $shell = New-Object -ComObject WScript.Shell
        if (Test-ResumeEntry) {
            # The setup normally writes the Startup entry itself; this is the move finished at a
            # sign-in after a setup that stopped before it got there. The loop below points it at
            # the new program.
            if ($j.startup.existed) {
                Copy-Item -LiteralPath $j.startup.backup -Destination $startupLink -Force
            } else { Remove-Item -LiteralPath $startupLink -Force -ErrorAction SilentlyContinue }
        }
        foreach ($folder in $ShortcutFolders) {
            foreach ($lnk in @(Get-ChildItem -LiteralPath $folder -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
                try { Update-Shortcut $lnk.FullName $shell } catch { Say "The shortcut $($lnk.FullName) could not be pointed at the new folder: $($_.Exception.Message)" }
            }
        }
        try { Update-Environment } catch { Say "The user's settings could not all be pointed at the new folders: $($_.Exception.Message)" }
        try { Update-Tasks } catch { Say "The scheduled jobs could not all be pointed at the new folders: $($_.Exception.Message)" }
        try {
            $config = Get-Content -LiteralPath (Join-Path $newState 'installation.json') -Raw | ConvertFrom-Json
            if ($config.workspace) { Update-TextFile (Join-Path $config.workspace '.vscode\settings.json') }
        } catch { }
        # Python's own note of the interpreters it has seen, which names the old folder: it is made
        # again when needed.
        Get-ChildItem -LiteralPath (Join-Path $newState 'hermes-runtime\uv-cache') -Directory -Filter 'interpreter-v*' -ErrorAction SilentlyContinue |
            ForEach-Object { [void](Remove-Folder $_.FullName) }
    }
    # The old copy of the assistant's program, kept until now so a failure could go back to it.
    foreach ($left in @(Get-ChildItem -LiteralPath $newState -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $aside -or $_.Name -like 'hermes-runtime-failed-*' })) {
        if (-not (Remove-Folder $left.FullName)) { Say "The old copy of the assistant's program in $($left.FullName) could not all be removed; the next update removes the rest." }
    }
    Remove-Item -LiteralPath (Join-Path $newProgram $marker) -Force -ErrorAction SilentlyContinue
    if ($j) {
        if ($j.stopped.assistant -and (Test-Path -LiteralPath (Join-Path $newProgram 'open-hermes.ps1'))) { Start-Script (Join-Path $newProgram 'open-hermes.ps1') }
        foreach ($t in @($j.stopped.tasks)) { if ($t) { Start-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue } }
        Remove-Item -LiteralPath $moveDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($moved) { Say "Godspeed Mission Control now lives in $newProgram and keeps its notebook's data in $newState." }
    }
    # The old program folder, once Windows' Apps entry names another one. The program the wizard
    # installed is in the new folder; this holds the version before it.
    $apps = Get-AppsLocation
    if ((Test-Path -LiteralPath $oldProgram) -and -not ($apps -and $apps -ieq $oldProgram)) {
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
}

# Only one of these runs at a time on this PC: the wizard's move, a Resume at sign-in and one from
# the notebook's start script could otherwise meet.
$lock = New-Object Threading.Mutex($false, 'Local\GodspeedMissionControlFolderMove')
$owned = $false
try { $owned = $lock.WaitOne(300000) } catch [Threading.AbandonedMutexException] { $owned = $true }
if (-not $owned) { Say 'Another move to the new folders is still running, so this one waits for the next start.'; exit 1 }

# =============================================================================
if ($Action -eq 'Finish') {
    try { Complete-Move } catch { Say "Tidying up after the move did not finish ($($_.Exception.Message)); the next update tries again." }
    exit 0
}

# Put off: nothing was moved, or all of it is back; the install works under its old names (and an
# update goes on there). One plain line in the update log, and the same on the wizard's last page.
function Set-Postponed([string]$Why) {
    $line = "Godspeed Mission Control stays in its old folders this time and works there as before, because $Why The next update tries the move again."
    Say $line
    Set-Note $line
}

# A move that did not end: finished when its program was installed completely, put back otherwise.
# Says 'none', 'left' (its setup still runs), 'finished', 'back' or 'held'.
function Resolve-Unfinished([switch]$ThenMove) {
    $j = Read-Journal
    if (-not $j) { return 'none' }
    if ($j.run -ne $Run -and (Test-OwnerAlive $j.owner)) { return 'left' }
    if (Test-ProgramComplete) {
        Say 'The move to the new folders was cut off after the program was installed there; finishing it.'
        Complete-Move
        return 'finished'
    }
    if ($j.run -ne $Run) { Say 'A move to the new folders was cut off before it finished; putting the old folders back first.' }
    $result = Undo-Move $j
    # Before a move of its own the setup says nothing: what it says then is about that move.
    if ($result -eq 'back' -and -not $ThenMove) {
        if ($j.run -eq $Run) { Set-Postponed 'the setup ended before it had installed the program.' }
        else { Set-Postponed 'the update that was moving it was cut off (a sign-out, a restart or a closed window) before it finished.' }
    }
    return $result
}

if ($Action -eq 'Resume') {
    $result = 'none'
    try { $result = Resolve-Unfinished } catch { Say "Finishing the move to the new folders did not work ($($_.Exception.Message)); the next start tries again."; exit 1 }
    if ($Start -and $result -in 'none', 'finished') {
        $starter = @((Join-Path $newProgram 'start-notebook.ps1'), (Join-Path $oldProgram 'start-notebook.ps1'), (Join-Path $oldProgram 'start-full-alpha.ps1') |
            Where-Object { Test-Path -LiteralPath $_ })[0]
        if ($starter) { Start-Script $starter @('-NoBrowser') }
    }
    if ($result -eq 'held') { exit 1 }
    exit 0
}

# =============================================================================
# Move
Remove-Item -LiteralPath $noteFile -Force -ErrorAction SilentlyContinue
Step 'Looking at the folders of Godspeed Mission Control on this PC'
# A move that a sign-out, a restart or a closed window cut off is finished or put back first.
$earlier = Resolve-Unfinished -ThenMove
if ($earlier -eq 'left') { Say 'Another setup is moving Godspeed Mission Control right now, so this one leaves its folders as they are.'; exit 5 }
if ($earlier -eq 'held') { exit 1 }

# Only the old program folder left: an earlier update moved the install, and its last step, which
# removes that folder, did not finish. What runs from it is stopped so the wizard can install, and
# that last step (Finish) removes it at the end of this setup.
if ((Get-GodspeedRecordKind $oldState) -ne 'install') {
    if (-not (Test-Path -LiteralPath $oldProgram)) { exit 3 }
    try {
        $stop = Join-Path $PSScriptRoot 'stop-notebook.ps1'
        if (Test-Path -LiteralPath $stop) { & $ps -NoProfile -ExecutionPolicy Bypass -File $stop; if ($LASTEXITCODE -ne 0) { throw 'the notebook could not be stopped.' } }
        [void](Stop-FolderProcesses @($oldProgram))
    } catch { Say "The notebook could not be stopped before the update: $($_.Exception.Message)"; exit 1 }
    exit 3
}

# 1. LOOKED AT, NOTHING CHANGED. Whatever is in the way puts the move off.
try {
    if (Test-Path -LiteralPath $newState) {
        if ((Get-GodspeedRecordKind $newState) -eq 'install') { throw "there is a notebook in both $oldState and $newState, so neither was moved." }
        if (Test-HasFiles $newState) { throw "$newState is in the way: it holds files but no notebook. Move it somewhere else." }
    }
    # The program may be in the new folder already (an update after an uninstall whose move was put
    # off): then only the state folder moves, and the new program folder is the install's own.
    $programThere = (Get-AppsLocation) -ieq $newProgram
    if ((Test-HasFiles $newProgram) -and -not $programThere) {
        # A program folder an earlier move made and could not take away again carries its mark.
        if (Test-Path -LiteralPath (Join-Path $newProgram $marker)) {
            if (-not (Remove-Folder $newProgram)) { throw "$newProgram, left by an earlier try, could not be removed." }
        } else { throw "$newProgram is in the way: it holds files of another install. Move it somewhere else." }
    }
    $config = Get-Content -LiteralPath (Join-Path $oldState 'installation.json') -Raw | ConvertFrom-Json
    if (-not $launcherApi -and (Test-Path -LiteralPath (Join-Path $oldState 'hermes-runtime\bin'))) {
        throw "this Windows does not let the setup make the small helper that points the assistant's program at its new folder."
    }
    Step 'Finding what in the notebook''s folder and in the assistant''s program names the old folder'
    $pointers = @(Find-RecordPointers $oldState) + @(Find-RuntimePointers $oldState)
    $need = [long]32MB + 16MB
    foreach ($p in $pointers) { if ($p.kind -ne 'link') { $need += (Get-Item -LiteralPath (Join-Path $oldState $p.rel) -Force).Length } }
    if ((Get-FreeBytes) -lt $need) { throw ("drive {0} has {1:N0} MB free, and the move keeps {2:N0} MB of safety copies until it is done." -f [IO.Path]::GetPathRoot($LocalAppData), ((Get-FreeBytes) / 1MB), ($need / 1MB)) }
} catch { Set-Postponed $_.Exception.Message; exit 4 }

# 2. THE RECORD, BEFORE THE FIRST CHANGE: what will be done, a copy of every file that will change,
#    the Apps entry and the Startup entry as they are, and this script beside them.
$script:journal = [pscustomobject]@{
    status = 'moving'; run = $Run; owner = (Get-OwnerRecord); at = (Get-Date -Format 's')
    stopped = [pscustomobject]@{ notebook = $false; assistant = $false; tasks = @() }
    startup = [pscustomobject]@{ existed = (Test-Path -LiteralPath $startupLink); backup = (Join-Path $copies 'startup.lnk') }
    # The new program folder holds nothing of anybody's (looked at above) unless it is the install's
    # own: a put-back removes it only when this move made it.
    apps = (Get-AppsValues); newProgramMade = -not $programThere
    pointers = @(); runtime = 'repointed'; reinstalledBecause = $null
}
try {
    New-Item -ItemType Directory -Force -Path $copies, $tools | Out-Null
    $n = 0
    foreach ($p in $pointers) { if ($p.kind -ne 'link') { $p.backup = Join-Path $copies ("$n.bak"); $n++ } }
    Set-J 'pointers' @($pointers)
    if ($journal.startup.existed) { Copy-Item -LiteralPath $startupLink -Destination $journal.startup.backup -Force }
    foreach ($f in 'move-to-new-folders.ps1', 'godspeed-folders.ps1', 'stop-notebook.ps1') {
        if (Test-Path -LiteralPath (Join-Path $PSScriptRoot $f)) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $f) -Destination (Join-Path $tools $f) -Force }
    }
    # Space a put-back can always use, even on a disk that filled up meanwhile.
    $fs = [IO.File]::Create($reserve); try { $fs.SetLength(32MB) } finally { $fs.Close() }
    Save-Journal
} catch {
    Remove-Item -LiteralPath $moveDir -Recurse -Force -ErrorAction SilentlyContinue
    Set-Postponed "the safety copies could not be made ($($_.Exception.Message))."
    exit 4
}
Test-CutOff 'recorded'

$why = $null
try {
    # 3. Nothing may run from the old folders while they move. From here on, a sign-in finishes or
    #    puts back the move before the notebook starts.
    Step 'Stopping the notebook and the assistant'
    Set-ResumeEntry
    $journal.stopped.notebook = $true; Save-Journal
    $stop = @((Join-Path $PSScriptRoot 'stop-notebook.ps1'), (Join-Path $oldProgram 'stop-notebook.ps1'), (Join-Path $oldProgram 'stop-full-alpha.ps1') | Where-Object { Test-Path -LiteralPath $_ })[0]
    if ($stop) {
        & $ps -NoProfile -ExecutionPolicy Bypass -File $stop
        if ($LASTEXITCODE -ne 0) { throw 'the notebook could not be stopped. Restart the computer and run the update again.' }
    }
    $journal.stopped.assistant = [bool](Stop-FolderProcesses @($oldState, $oldProgram)); Save-Journal
    if (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue) {
        foreach ($t in @(Get-ScheduledTask -TaskName $TaskNames -ErrorAction SilentlyContinue | Where-Object { [string]$_.State -eq 'Running' })) {
            Stop-ScheduledTask -TaskName $t.TaskName -TaskPath $t.TaskPath
            $journal.stopped.tasks = @($journal.stopped.tasks) + $t.TaskName; Save-Journal
        }
    }
    Test-CutOff 'stopped'
    # The copies are made once nothing runs that could still change the files.
    Step 'Making safety copies of the files the move changes'
    foreach ($p in $pointers) { if ($p.kind -ne 'link') { [IO.File]::Copy((Join-Path $oldState $p.rel), $p.backup, $true) } }

    # 4. The state folder: the notebook's photos and files, its backups, what the assistant has
    #    learned and its conversations, all in one rename that changes none of them.
    Step 'Moving the notebook''s folder to its new name (a rename: nothing in it is copied or changed)'
    if (-not (Move-Folder $oldState $newState $HoldSeconds)) {
        throw "$oldState could not be renamed: something on this PC still used it for $HoldSeconds seconds (a window opened there, a program started from it, or a virus scanner checking it)."
    }
    Test-CutOff 'renamed'
    # For the fresh-machine tests of a move that fails, and nothing else: here, halfway, or at its last step.
    if ($env:KB_TEST_MOVE_FAIL -eq 'halfway') { throw 'it was made to fail here, halfway, for a test.' }

    # 5. What inside it names the old folders: the setup's records, the assistant's settings, and
    #    the assistant's program. Then the program is started from the new place once.
    Step 'Pointing the notebook''s records and the assistant''s program at the new folder'
    $errors = @(Set-Pointers $newState)
    if ($errors) { throw "these could not be pointed at the new folder: $($errors -join ' ')" }
    Test-CutOff 'pointed'
    $rt = Join-Path $newState 'hermes-runtime'
    if (Test-Path -LiteralPath (Join-Path $rt 'bin')) {
        Step 'Checking that the assistant''s program starts from its new folder'
        $broken = Test-Runtime $newState
        if ($broken) {
            # 6. ONLY WHEN THAT DOES NOT WORK: the assistant's program installed again in its new
            #    place, beside the old copy, which lends it its downloads and stays until the
            #    setup has finished, so a failure can always go back to it.
            $journal.runtime = 'reinstalled'; $journal.reinstalledBecause = $broken; Save-Journal
            $need = (Get-FolderBytes $rt $caches) + 512MB
            if ((Get-FreeBytes) -lt $need) { throw ("the assistant's program did not start from its new folder ($broken), and installing it again needs about {0:N1} GB free on drive {1}, which has {2:N1} GB." -f ($need / 1GB), [IO.Path]::GetPathRoot($LocalAppData), ((Get-FreeBytes) / 1GB)) }
            Step "Installing the assistant's program again in its new folder, because it did not start there ($broken). This takes up to half an hour; your notes, files and conversations are not touched."
            if (-not (Move-Folder $rt (Join-Path $newState $aside) 30)) { throw "$rt could not be moved aside." }
            New-Item -ItemType Directory -Force -Path $rt | Out-Null
            foreach ($c in $caches) {
                if (Test-Path -LiteralPath (Join-Path $newState "$aside\$c")) {
                    if (-not (Move-Folder (Join-Path $newState "$aside\$c") (Join-Path $rt $c) 30)) { throw "the downloads in $aside\$c could not be lent to the new copy." }
                }
            }
            $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
            try { & $ps -NoProfile -ExecutionPolicy Bypass -File $RuntimeBuilder -State $newState -Workspace $config.workspace -Port ([int]$config.port) -Provision -ForceIsolatedInstall -RuntimeOnly | Out-Host; $code = $LASTEXITCODE }
            finally { $ErrorActionPreference = $previous }
            if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $rt 'bin'))) {
                throw "the assistant's program did not start from its new folder ($broken), and installing it again there did not work either (what happened is in $(Join-Path $newState 'hermes-install.log'))."
            }
        }
    }
    if ($env:KB_TEST_MOVE_FAIL -and $env:KB_TEST_MOVE_FAIL -ne 'halfway') { throw 'it was made to fail here, for a test.' }

    # 7. The new program folder, which the wizard fills next. Its mark says an earlier try made it.
    New-Item -ItemType Directory -Force -Path $newProgram | Out-Null
    Set-Content -LiteralPath (Join-Path $newProgram $marker) -Value 'Made by move-to-new-folders.ps1 for the program the wizard installs here.' -Encoding ascii
    $journal.status = 'moved'; Save-Journal
    $note = "This update also moved Godspeed Mission Control to its new folders, $newProgram and $newState."
    if ($journal.runtime -eq 'reinstalled') { $note += " The assistant's program had to be installed again there, because it did not start from the new folder ($($journal.reinstalledBecause))." }
    else { Say "The assistant's program was pointed at its new folder; nothing had to be installed again." }
    Set-Note $note
    Step 'Moved. Installing the program into its new folder'
    exit 0
} catch {
    $why = $_.Exception.Message
}
Step 'The move did not finish; putting the old folders back'
$result = 'held'
try { $result = Undo-Move $journal } catch { $why += " Putting it back did not finish either ($($_.Exception.Message))." }
if ($result -eq 'back') { Set-Postponed $why; exit 4 }
Say "The move to the new folders did not finish ($why), and the old folders are not all back yet. That is finished when you next sign in, or when you run the installer again."
exit 1

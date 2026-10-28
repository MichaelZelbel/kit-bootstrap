<#
  GodspeedSetup.exe on a fresh GitHub Windows machine, the way a reader runs it silently, and what
  the faults that beta testers met first look like afterwards (18 October 2026):

    fresh      a first installation
    update     the newest published release first (2.0.0-beta.10, under the names that said "Full
               Alpha"), a reader's note, a setting, a photo, what the assistant learned and a user
               setting that names the old folders, then this installer with nothing chosen, which
               must update that mission control and move it to the new names (ticket 05 of 2.0.0-beta.11)
    updater    the same, but updated the way a reader of 2.0.0-beta.10 does it: that release's own
               "Update my mission control", which must end saying the update worked
    reinstall  the same, uninstalled first (which keeps the notebook's data under the old name),
               then this installer, which must move that data to the new names
    fail       the same, with the move made to fail halfway, then with the setup failing after the
               move (a file it cannot write, near the end of its copying): both times the install
               must be back under its old names and working, with one plain line in the update log;
               then the next update must move it

  and on all: the run waits until it is done (the documented command), nothing asks or shows a
  box, Hermes is never called missing, nothing names a person or asks about Menerio, the Startup
  entry starts the notebook without the browser, "Open my notebook" opens it and is in the Start
  menu once (the update removes the old address entry), the Apps list shows Godspeed Mission Control and
  the beta version, an older installer is refused before it touches anything, "Update my mission
  control" looks for a newer release, and the uninstaller removes the program's own files and
  keeps every file of the reader's.

  Only on an ephemeral CI machine: it installs, uninstalls and changes the user's PATH.

    ./windows/test-beta-install.ps1 -Mode fresh -Setup GodspeedSetup.exe -Manifest candidate-manifest.json -Previous prev.exe
#>
param(
  [ValidateSet('fresh', 'update', 'updater', 'reinstall', 'fail')][string]$Mode = 'fresh',
  [Parameter(Mandatory)][string]$Setup,
  [Parameter(Mandatory)][string]$Manifest,
  # The newest published GodspeedSetup.exe: the one the update starts from.
  [Parameter(Mandatory)][string]$Previous,
  # This same installer code built around an older notebook: the older installer that must be
  # refused before it touches anything. (A published one predates the refusal.)
  [Parameter(Mandatory)][string]$Older,
  [string]$Evidence = 'evidence'
)
$ErrorActionPreference = 'Continue'
if ($env:CI -ne 'true') { throw 'This installs and uninstalls for real. It runs only on a throwaway CI machine.' }
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
$Setup = (Resolve-Path $Setup).Path; $Previous = (Resolve-Path $Previous).Path; $Older = (Resolve-Path $Older).Path
$script:fail = 0
function Want($what, [scriptblock]$test) {
  $ok = $false; try { $ok = [bool](& $test) } catch { Write-Host "   $_" }
  if ($ok) { Write-Host "ok    $what" } else { Write-Host "FAIL  $what"; $script:fail++ }
}
# A reader starts the setup from Explorer; from this PowerShell 7 the setup's Windows PowerShell
# 5.1 would inherit PowerShell 7's module path and lose Get-FileHash (as in release-windows.yml).
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')

# The command the guide gives for a silent install: it waits for the setup itself, never for the
# notebook the setup leaves running (Start-Process -Wait would wait for that too, for ever).
function Invoke-Setup([string]$Exe, [string[]]$Arguments, [string]$Name, [int]$Minutes = 60) {
  $log = Join-Path $Evidence "$Name.log"
  $started = Get-Date
  $p = Start-Process $Exe -ArgumentList (@($Arguments) + "/LOG=`"$log`"") -PassThru
  if (-not $p.WaitForExit($Minutes * 60000)) { Write-Host "$Name STILL RUNNING AFTER $Minutes MINUTES"; Stop-Process -Id $p.Id -Force; return 999 }
  Write-Host "$Name ended with $($p.ExitCode) after $([int]((Get-Date) - $started).TotalMinutes) minutes"
  return $p.ExitCode
}
# Every window of the setup's own that a silent run must not show: message boxes and wizards.
$script:seenWindows = @()
$watch = Start-Job -ScriptBlock {
  Add-Type @'
using System; using System.Text; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class W {
  public delegate bool P(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern bool EnumWindows(P f, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  public static List<string> Visible() { var l = new List<string>(); EnumWindows((h, x) => { if (IsWindowVisible(h)) { var c = new StringBuilder(256); GetClassName(h, c, 256); var t = new StringBuilder(512); GetWindowText(h, t, 512); l.Add(c + "|" + t); } return true; }, IntPtr.Zero); return l; }
}
'@
  while ($true) { foreach ($w in [W]::Visible()) { if ($w -match '^(#32770|TWizardForm|TSetupForm)\|') { $w } }; Start-Sleep -Milliseconds 500 }
}

# A new install uses the names of godspeed-folders.ps1, without "Full Alpha" (2.0.0-beta.11), and so
# does every install this setup updates: the newest published release was made under the old names,
# and the update moves it (ticket 05 of 2.0.0-beta.11).
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$names = Get-GodspeedFolderNames
$state = Join-Path $env:LOCALAPPDATA $names.State; $app = Join-Path $env:LOCALAPPDATA $names.Program
$oldState = Join-Path $env:LOCALAPPDATA $names.OldState; $oldApp = Join-Path $env:LOCALAPPDATA $names.OldProgram
$mc = Join-Path $HOME 'godspeed-v2'
$built = Get-Content $Manifest -Raw | ConvertFrom-Json
$setupLog = Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt'
$moved = $Mode -ne 'fresh'
"under test: notebook $($built.kitCommit), installer $($built.bootstrapCommit), version $($built.version)"
$api = 'http://127.0.0.1:47831/api/query'
function Get-Note { @((Invoke-RestMethod $api -Method Post -ContentType 'application/json' -Body '{"table":"notes","operation":"select"}' -TimeoutSec 30).data | Where-Object { $_.id -eq 'written-before-the-update' }).Count -eq 1 }
function Get-Setting { @((Invoke-RestMethod $api -Method Post -ContentType 'application/json' -Body '{"table":"settings","operation":"select"}' -TimeoutSec 30).data | Where-Object { $_.id -eq 'kept-across-the-move' -and $_.value -eq 'yes' }).Count -eq 1 }
function Wait-Notebook([int]$Minutes = 15) {
  $until = (Get-Date).AddMinutes($Minutes)
  while ((Get-Date) -lt $until) { try { if ((Invoke-RestMethod http://127.0.0.1:47831/health -TimeoutSec 5).ok) { return $true } } catch { }; Start-Sleep -Seconds 5 }
  return $false
}
# A program run with a time limit, its output kept as evidence: the assistant's program must not wait for anybody.
function Invoke-Timed([string]$Exe, [string[]]$Arguments, [string]$Name, [int]$Seconds = 120) {
  $out = Join-Path $Evidence "$Name.out.txt"; $err = Join-Path $Evidence "$Name.err.txt"
  $p = Start-Process $Exe -ArgumentList $Arguments -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
  if (-not $p.WaitForExit($Seconds * 1000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; return [pscustomobject]@{ Code = 999; Out = '' } }
  return [pscustomobject]@{ Code = $p.ExitCode; Out = ((Get-Content $out -Raw -ErrorAction SilentlyContinue) + (Get-Content $err -Raw -ErrorAction SilentlyContinue)) }
}
$envKey = 'HKCU:\Environment'

if ($moved) {
  $code = Invoke-Setup $Previous @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'previous'
  $prev = Get-Content (Join-Path $oldState 'installation.json') -Raw | ConvertFrom-Json
  "previous release: $($prev.kitCommit) at $($prev.workspace), program in $((Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9929B7B4-B588-46D2-AC79-01F7EBD7FA92}_is1').InstallLocation) (exit $code)"
  # What a reader has by then, in the mission control and in the folders that move: a note and a
  # setting in the notebook, a photo, what the assistant learned, and a user setting that names
  # the old state folder (PATH in its %LOCALAPPDATA% form, another one written out).
  Set-Content -Path (Join-Path $mc 'my-own-notes.md') -Value 'Written by the reader before the update.' -Encoding utf8
  $body = '{"table":"notes","operation":"insert","values":{"id":"written-before-the-update","title":"Written before the update","content":"This note was written with the previous release."},"selection":"*","single":true}'
  try { (Invoke-RestMethod $api -Method Post -ContentType 'application/json' -Body $body).data.id } catch { "the note could not be written: $_" }
  $body = '{"table":"settings","operation":"insert","values":{"id":"kept-across-the-move","value":"yes"},"selection":"*","single":true}'
  try { (Invoke-RestMethod $api -Method Post -ContentType 'application/json' -Body $body).data.id } catch { "the setting could not be written: $_" }
  New-Item -ItemType Directory -Force (Join-Path $oldState 'media'), (Join-Path $oldState 'hermes-profile\memories') | Out-Null
  Set-Content -Path (Join-Path $oldState 'media\a-photo-of-the-reader.jpg') -Value 'a photo' -Encoding utf8
  Add-Content -Path (Join-Path $oldState 'hermes-profile\memories\MEMORY.md') -Value 'The reader likes short answers.' -Encoding utf8
  [Environment]::SetEnvironmentVariable('GODSPEED_MOVE_CHECK', (Join-Path $oldState 'media'), 'User')
  $k = Get-Item $envKey
  $pathKind = if ($k.GetValueNames() -contains 'Path') { $k.GetValueKind('Path') } else { 'ExpandString' }
  $path0 = [string]$k.GetValue('Path', '', 'DoNotExpandEnvironmentNames')
  Set-ItemProperty $envKey -Name 'Path' -Value ($path0.TrimEnd(';') + ";%LOCALAPPDATA%\$($names.OldState)\hermes-runtime\bin") -Type $pathKind
  Get-Content (Join-Path $oldState 'hermes-runtime\hermes-agent\venv\pyvenv.cfg') -ErrorAction SilentlyContinue | Set-Content (Join-Path $Evidence 'pyvenv-before.cfg')
  Remove-Item $setupLog -ErrorAction SilentlyContinue
}
$appsKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9929B7B4-B588-46D2-AC79-01F7EBD7FA92}_is1'
$startup = [Environment]::GetFolderPath('Startup')
$group = Join-Path ([Environment]::GetFolderPath('Programs')) 'Godspeed Mission Control'
# After a move that did not happen, the install is where it was, works, and the update log says why.
function Test-OldNamesWork([string]$Label, [int]$LinesBefore) {
  Want "${Label}: the install is back under its old names: its Apps entry, its program and its notebook's record there, nothing under the new state name" {
    $apps = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | Get-ItemProperty | Where-Object { $_.DisplayName -like 'Godspeed*' })
    $apps.Count -eq 1 -and $apps[0].InstallLocation.TrimEnd('\') -eq $oldApp -and (Test-Path (Join-Path $oldApp 'unins000.exe')) -and
      (Get-GodspeedRecordKind $oldState) -eq 'install' -and -not (Test-Path $state) -and -not (Test-Path (Join-Path $env:LOCALAPPDATA 'Godspeed\folder-move'))
  }
  Want "${Label}: its records, its Startup entry and the user's settings name the old folders again" {
    $i = Get-Content (Join-Path $oldState 'installation.json') -Raw | ConvertFrom-Json
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'Godspeed Mission Control.lnk'))
    $i.appRoot.TrimEnd('\') -eq $oldApp -and $i.media -eq (Join-Path $oldState 'media') -and $lnk.Arguments.Contains($oldApp + '\') -and
      [Environment]::GetEnvironmentVariable('GODSPEED_MOVE_CHECK', 'User') -eq (Join-Path $oldState 'media')
  }
  Want "${Label}: the assistant's program works where it was" {
    $a = Get-Content (Join-Path $oldState 'assistant.json') -Raw | ConvertFrom-Json
    $r = Invoke-Timed (Join-Path $a.sourceRoot 'venv\Scripts\python.exe') @('-c', '"import sys, hermes_cli; print(sys.prefix)"') "$Label-python-old"
    Write-Host "   $($r.Out.Trim())"
    $r.Code -eq 0 -and $r.Out.Contains($oldState)
  }
  Want "${Label}: its notebook answers again, with the reader's note and setting" { (Wait-Notebook) -and (Get-Note) -and (Get-Setting) }
  Want "${Label}: the update log says why in one plain line, and that the next update tries again" {
    $lines = @(Get-Content $setupLog -ErrorAction SilentlyContinue | Where-Object { $_ -match 'stays in its old folders' })
    if ($lines) { Write-Host "   $($lines[-1])" }
    $lines.Count -eq $LinesBefore + 1 -and $lines[-1].Contains('The next update tries again.')
  }
}

# 1. The installer under test, silent, nothing chosen (in updater mode: started by the old updater).
if ($Mode -eq 'reinstall') {
  $code = Invoke-Setup (Join-Path $oldApp 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'uninstall-previous' 15
  Start-Sleep -Seconds 5
  Want 'the previous release uninstalled: its program and Apps entry gone, its notebook data kept under the old name' {
    -not (Test-Path $oldApp) -and -not (Test-Path $appsKey) -and (Get-GodspeedRecordKind $oldState) -eq 'install' -and
      (Test-Path (Join-Path $oldState 'media\a-photo-of-the-reader.jpg')) -and -not (Test-Path (Join-Path $oldState 'hermes-runtime'))
  }
}
if ($Mode -eq 'fail') {
  # a. The move fails halfway, after the state folder got its new name.
  $env:KB_TEST_MOVE_FAIL = 'halfway'
  $code = Invoke-Setup $Setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'setup-move-fails'
  Remove-Item env:KB_TEST_MOVE_FAIL
  Want 'a move that fails halfway ends the setup with an error code, before it copied anything' { $code -ne 0 -and -not (Test-Path (Join-Path $app 'unins000.exe')) }
  Test-OldNamesWork 'after a move that failed halfway' 0
  # b. The move works, then the setup cannot write a file near the end of its copying (the folder
  #    holding the last files it copies refuses it), so it takes its new files away again. The
  #    move must be put back with them: the old program works only with the old names.
  $deny = Join-Path $app 'vendor'
  New-Item -ItemType Directory -Force $deny | Out-Null
  $rule = New-Object Security.AccessControl.FileSystemAccessRule([Security.Principal.WindowsIdentity]::GetCurrent().Name, 'CreateFiles', 'Deny')
  $acl = Get-Acl $deny; $acl.AddAccessRule($rule); Set-Acl $deny $acl
  $code = Invoke-Setup $Setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'setup-copy-fails'
  $acl = Get-Acl $deny; [void]$acl.RemoveAccessRule($rule); Set-Acl $deny $acl
  Want 'a setup that cannot write its files after the move ends with an error code and took its new files away' {
    $code -ne 0 -and -not (Test-Path (Join-Path $app 'unins000.exe')) -and -not (Test-Path (Join-Path $app 'start-notebook.ps1'))
  }
  Test-OldNamesWork 'after a setup that failed after the move' 1
  Copy-Item $setupLog (Join-Path $Evidence 'setup-log-failures.txt') -ErrorAction SilentlyContinue
}
if ($Mode -eq 'updater') {
  # "Update my mission control" of 2.0.0-beta.10, as its Start menu entry runs it, reading this
  # build as the newest release from a folder (it takes one in place of the web address) and
  # told not to wait for Enter at the end.
  $release = Join-Path $env:RUNNER_TEMP 'release'
  New-Item -ItemType Directory -Force $release | Out-Null
  Copy-Item $Setup (Join-Path $release 'GodspeedSetup.exe'); Copy-Item $Manifest (Join-Path $release 'windows-manifest.json')
  Set-Content (Join-Path $release 'SHA256SUMS') -Encoding ascii -Value @(foreach ($n in 'GodspeedSetup.exe', 'windows-manifest.json') { "$((Get-FileHash (Join-Path $release $n)).Hash.ToLower())  $n" })
  $entry = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $group 'Update my mission control.lnk'))
  "the Start menu entry runs: $($entry.TargetPath) $($entry.Arguments)"
  $updaterOut = Join-Path $Evidence 'old-updater.txt'
  $started = Get-Date
  $p = Start-Process $entry.TargetPath -ArgumentList ($entry.Arguments + " -ReleaseBase `"$release`" -NoPause") -WorkingDirectory $HOME `
    -RedirectStandardOutput $updaterOut -RedirectStandardError (Join-Path $Evidence 'old-updater-errors.txt') -WindowStyle Hidden -PassThru
  if (-not $p.WaitForExit(120 * 60000)) { 'the old updater did not end within two hours'; Stop-Process -Id $p.Id -Force }
  $code = $p.ExitCode
  $said = Get-Content $updaterOut -Raw
  "the old updater ended with $code after $([int]((Get-Date) - $started).TotalMinutes) minutes:"; $said
  Want "the update through 2.0.0-beta.10's own updater ends saying it worked" { $code -eq 0 -and $said.Contains('Your mission control is up to date') -and -not $said.Contains('did not finish') }
  Want 'and the record it read under the old name is gone once it has ended' {
    $until = (Get-Date).AddSeconds(60); while ((Test-Path $oldState) -and (Get-Date) -lt $until) { Start-Sleep -Seconds 2 }
    -not (Test-Path $oldState)
  }
} else {
  $code = Invoke-Setup $Setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'setup'
}
Want 'the setup finished with exit 0 and its result says ok' { $code -eq 0 -and ((Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-result.txt') -Raw).Trim() -eq 'ok') }
$i = Get-Content (Join-Path $state 'installation.json') -Raw | ConvertFrom-Json
$a = Get-Content (Join-Path $state 'assistant.json') -Raw | ConvertFrom-Json
Want "the notebook is this build's ($($built.kitCommit.Substring(0, 7))) and keeps $mc" { $i.kitCommit -eq $built.kitCommit -and ([IO.Path]::GetFullPath($i.workspace).TrimEnd('\') -eq [IO.Path]::GetFullPath($mc).TrimEnd('\')) }
Want 'the notebook answers' { (Invoke-RestMethod http://127.0.0.1:47831/health -TimeoutSec 15).ok -eq $true }
Want 'Hermes came with the setup' { $a.verified -eq $true -and (Test-Path -LiteralPath $a.executable) }
$log = Get-Content $setupLog -Raw
Copy-Item $setupLog (Join-Path $Evidence "setup-log-$Mode.txt") -ErrorAction SilentlyContinue
Want 'the setup never says Hermes is missing' { $log -and -not ($log -match 'Hermes is not on this PC yet') -and -not ($log -match 'some things will not work until they are here:[^\r\n]*Hermes') }
Want 'it asks nothing about Menerio and offers the import instead' { -not $log.Contains('Connect Menerio now?') -and $log.Contains('Import from Menerio') }
Want 'it names no person, and asks nothing about an install count' { -not (($log -replace 'MichaelZelbel', '') -match 'Michael') -and -not $log.Contains('anonymous note') -and -not $log.Contains('install count') }
Want 'the Startup entry starts the notebook without opening the browser, under one plain name' {
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'Godspeed Mission Control.lnk'))
  $lnk.Arguments.Contains('-File "' + (Join-Path $app 'start-notebook.ps1') + '" -NoBrowser') -and -not (Test-Path (Join-Path $startup 'Godspeed Mission Control Full Alpha.lnk'))
}
# "Open my notebook" was the bare address until 26 October 2026, an "Open my notebook.url" that the
# previous release still makes; after the update only the new entry carries that name.
Want 'the Start menu has Open my notebook once, and it runs open-notebook.ps1 hidden' {
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $group 'Open my notebook.lnk'))
  (Test-Path (Join-Path $group 'Open my notebook.lnk')) -and -not (Test-Path (Join-Path $group 'Open my notebook.url')) -and
    $lnk.TargetPath -like '*\WindowsPowerShell\v1.0\powershell.exe' -and
    $lnk.Arguments.Contains('-WindowStyle Hidden -File "' + (Join-Path $app 'open-notebook.ps1') + '"')
}
# Windows' Start search offers a shortcut to a program as an app, and an Internet shortcut (.url)
# not at all: on a PC with the old entry, typing "Open my notebook" found only a web search. Start
# lists the old kind under its address and the new kind as an app of its own, as it lists "Update
# my mission control" (Get-StartApps, Windows PowerShell's own command).
$listApps = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes('$ProgressPreference = "SilentlyContinue"; Get-StartApps | ForEach-Object { $_.Name + "|" + $_.AppID }'))
$startApps = @(& (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -EncodedCommand $listApps)
if (@($startApps | Where-Object { $_ -like 'Uninstall Godspeed Mission Control|*' }).Count) {
  Want 'Start search offers Open my notebook as an app, once, and not as a web address' {
    $mine = @($startApps | Where-Object { $_ -like 'Open my notebook|*' })
    Write-Host "   $($mine -join '; ')"
    $mine.Count -eq 1 -and -not ($mine[0] -match '\|https?:')
  }
} else {
  Write-Host "skip  this machine's Start lists no Godspeed entry at all ($($startApps.Count) apps), so Start search could not be looked at"
}
Want 'Open my notebook opens the running notebook at once and starts nothing' {
  $report = Join-Path $Evidence "open-notebook-$Mode.txt"
  $before = (Get-Content (Join-Path $state 'process.json') -Raw | ConvertFrom-Json).pid
  $p = Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $app 'open-notebook.ps1') + '"'), '-Report', ('"' + $report + '"')) -WindowStyle Hidden -PassThru
  if (-not $p.WaitForExit(120000)) { Stop-Process -Id $p.Id -Force; throw 'open-notebook.ps1 did not return within two minutes' }
  $lines = @(Get-Content $report)
  Write-Host "   $($lines -join ' | ')"
  ($lines -contains 'opened: http://127.0.0.1:47831/') -and -not ($lines -match '^said: ') -and
    (Get-Content (Join-Path $state 'process.json') -Raw | ConvertFrom-Json).pid -eq $before
}
$apps = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | Get-ItemProperty | Where-Object { $_.DisplayName -like 'Godspeed*' })
$apps | Select-Object DisplayName, DisplayVersion, Publisher | Format-Table | Out-String
Want "the Apps list shows one Godspeed Mission Control, version $($built.version), no alpha, in $app" {
  $apps.Count -eq 1 -and $apps[0].DisplayName -eq 'Godspeed Mission Control' -and $apps[0].DisplayVersion -eq $built.version -and
    -not ($built.version -match 'alpha') -and $apps[0].InstallLocation.TrimEnd('\') -eq $app -and
    $apps[0].UninstallString.Contains($app + '\unins000.exe')
}
# The version resource pads its texts with spaces, which the Properties window does not show.
Want "the installer's file properties say Godspeed Mission Control $($built.version)" {
  $v = (Get-Item $Setup).VersionInfo
  $v.ProductVersion.Trim() -eq $built.version -and $v.ProductName.Trim() -eq 'Godspeed Mission Control' -and -not ($v.ProductVersion -match 'alpha')
}
Want 'the commands it put on this PC are recorded for the uninstaller' { @(Get-Content (Join-Path $HOME '.godspeed\installed-commands.txt')).Count -ge 5 }
# What a person sees of the install, named: its folders, every file in the program folder, the
# Start menu and Startup entries with what they run, the daily jobs and the Apps entry.
$shell = New-Object -ComObject WScript.Shell
$seen = @(Get-ChildItem $env:LOCALAPPDATA -Directory -Force | ForEach-Object { $_.FullName }) +
  @(Get-ChildItem $app -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName }) +
  @(Get-ChildItem $group, $startup -Force -ErrorAction SilentlyContinue | ForEach-Object {
      $_.FullName; if ($_.Extension -eq '.lnk') { $l = $shell.CreateShortcut($_.FullName); "$($l.TargetPath) $($l.Arguments) $($l.WorkingDirectory)" } }) +
  @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'Godspeed*' } | ForEach-Object {
      $_.TaskName; foreach ($x in $_.Actions) { "$($x.Execute) $($x.Arguments) $($x.WorkingDirectory)" } }) +
  @($apps | ForEach-Object { $_.DisplayName, $_.InstallLocation, $_.UninstallString, $_.DisplayIcon }) +
  @((Get-Item $envKey).GetValueNames() | ForEach-Object { "$_=" + (Get-Item $envKey).GetValue($_, '', 'DoNotExpandEnvironmentNames') })
Set-Content -Path (Join-Path $Evidence "names-$Mode.txt") -Value $seen -Encoding utf8
$what = if ($moved) { 'the moved install' } else { 'a new install' }
Want "$what names nothing `"Full Alpha`": no folder, program file, Start menu or Startup entry, daily job, Apps entry or user setting" {
    $alpha = @($seen | Where-Object { $_ -match 'full.?alpha' })
    if ($alpha) { Write-Host "   $($alpha -join '; ')" }
    $alpha.Count -eq 0 -and $seen.Count -gt 100 -and (Test-Path (Join-Path $state 'installation.json')) -and (Test-Path (Join-Path $app 'unins000.exe')) -and
      ($apps[0].InstallLocation.TrimEnd('\') -eq $app) -and -not (Test-Path $oldState) -and -not (Test-Path $oldApp)
}
if ($moved) {
  Want "the notebook's records point into the new folders" {
    $a = Get-Content (Join-Path $state 'assistant.json') -Raw | ConvertFrom-Json
    $i.appRoot.TrimEnd('\') -eq $app -and $i.media -eq (Join-Path $state 'media') -and $a.home -eq (Join-Path $state 'hermes-profile') -and
      $a.executable.StartsWith((Join-Path $state 'hermes-runtime') + '\') -and $a.desktop.StartsWith((Join-Path $state 'hermes-runtime') + '\') -and
      -not ((Get-Content (Join-Path $state 'installation.json') -Raw) -match 'full.?alpha') -and -not ((Get-Content (Join-Path $state 'assistant.json') -Raw) -match 'full.?alpha')
  }
  Want "the user's settings that named the old state folder name the new one, PATH in the form it had" {
    $p = [string](Get-Item $envKey).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    [Environment]::GetEnvironmentVariable('GODSPEED_MOVE_CHECK', 'User') -eq (Join-Path $state 'media') -and
      $p.Contains("%LOCALAPPDATA%\$($names.State)\hermes-runtime\bin") -and -not ($p -match 'full.?alpha')
  }
  # The assistant's program records the folder it was installed in; a renamed copy does not start.
  $a = Get-Content (Join-Path $state 'assistant.json') -Raw | ConvertFrom-Json
  $rt = Join-Path $state 'hermes-runtime'
  Want "the assistant's program starts from its new place, and nothing in it points at the old one" {
    $env:HERMES_HOME = $a.home
    $v = Invoke-Timed $a.executable @('--version') 'hermes-version'
    if ($v.Code -ne 0) { $v = Invoke-Timed $a.executable @('--help') 'hermes-help' }
    Remove-Item env:HERMES_HOME
    $py = Invoke-Timed (Join-Path $a.sourceRoot 'venv\Scripts\python.exe') @('-c', '"import sys, hermes_cli; print(sys.prefix); print(hermes_cli.__file__)"') 'hermes-python'
    $cfg = Get-Content (Join-Path $a.sourceRoot 'venv\pyvenv.cfg') -Raw
    $cfg | Set-Content (Join-Path $Evidence 'pyvenv-after.cfg')
    $launcher = [IO.File]::ReadAllBytes($a.executable)
    $inLauncher = [Text.Encoding]::UTF8.GetString($launcher) + [Text.Encoding]::Unicode.GetString($launcher)
    Write-Host "   hermes: exit $($v.Code), $(($v.Out -split "`n")[0].Trim())"
    Write-Host "   python: $(($py.Out -split "`n" | ForEach-Object { $_.Trim() }) -join ' | ')"
    $v.Code -eq 0 -and $py.Code -eq 0 -and @($py.Out -split "`n" | Where-Object { $_.Trim() }).Count -ge 2 -and
      @($py.Out -split "`n" | Where-Object { $_.Trim() } | Where-Object { -not $_.Trim().StartsWith($rt + '\') }).Count -eq 0 -and
      -not ($cfg -match 'full.?alpha') -and -not ($inLauncher -match 'Full Alpha') -and
      -not (Test-Path (Join-Path $state 'hermes-runtime-before-move'))
  }
  Want "Open the Windows assistant starts the assistant's window from its new place" {
    Start-Process (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + (Join-Path $app 'open-hermes.ps1') + '"') -WindowStyle Hidden
    $until = (Get-Date).AddSeconds(90); $window = $null
    while (-not $window -and (Get-Date) -lt $until) { Start-Sleep -Seconds 2; $window = @(Get-CimInstance Win32_Process -Filter "Name='Hermes.exe'" | Where-Object { $_.ExecutablePath -like "$rt\*" })[0] }
    if ($window) { Write-Host "   $($window.ExecutablePath)"; & taskkill.exe /PID $window.ProcessId /T /F | Out-Null }
    [bool]$window
  }
  Want 'its scripts carry the new names, and none is named full alpha' {
    $old = @(Get-ChildItem $app -Filter '*-full-alpha*.ps1' | ForEach-Object { $_.Name })
    if ($old) { Write-Host "   still there: $($old -join ', ')" }
    $old.Count -eq 0 -and (Test-Path (Join-Path $app 'start-notebook.ps1')) -and (Test-Path (Join-Path $app 'godspeed-folders.ps1'))
  }
  Want 'the update went into the mission control that was there, and made no second one' { -not (Test-Path (Join-Path $HOME 'godspeed')) -and @(Get-ChildItem $HOME -Directory -Filter 'godspeed*').Count -eq 1 }
  Want 'it saved a copy of the notebook first' { @(Get-ChildItem (Join-Path $state 'backups') -Directory -ErrorAction SilentlyContinue).Count -ge 1 }
  Want "the reader's own file is untouched" { (Get-Content (Join-Path $mc 'my-own-notes.md') -Raw).Contains('Written by the reader before the update.') }
  Want "the reader's photo and what the assistant learned moved with the notebook, unchanged" {
    (Get-Content (Join-Path $state 'media\a-photo-of-the-reader.jpg') -Raw).Contains('a photo') -and
      (Get-Content (Join-Path $state 'hermes-profile\memories\MEMORY.md') -Raw).Contains('The reader likes short answers.')
  }
  Want 'the note and the setting written with the previous release are still there' { (Get-Note) -and (Get-Setting) }
}

# 2. An older installer is refused before it touches anything.
$programBefore = (Get-FileHash (Join-Path $app 'payload\candidate-manifest.json')).Hash
$code = Invoke-Setup $Older @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'older' 15
$after = Get-Content (Join-Path $state 'installation.json') -Raw | ConvertFrom-Json
Want 'the older installer ends with an error code' { $code -ne 0 }
Want 'and changed nothing: the same program, the same notebook, still running' {
  (Get-FileHash (Join-Path $app 'payload\candidate-manifest.json')).Hash -eq $programBefore -and $after.kitCommit -eq $built.kitCommit -and
    (Invoke-RestMethod http://127.0.0.1:47831/health -TimeoutSec 15).ok -eq $true
}
Want 'and says why in setup-result.txt' { (Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-result.txt') -Raw) -match '^refused: this installer is older' }

# 3. "Update my mission control" reads the newest release and does not take this PC back. This
# build is never older than the newest published release: either it is newer (its notebook commit
# is not released yet) or it is exactly it (the release was cut from that same commit, as on
# 27 October 2026). Both answers are right, and neither downloads anything; test-windows.ps1
# checks each answer on its own against a made-up release.
$check = & (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $app 'update-godspeed.ps1') -CheckOnly -NoPause | Out-String
$check
Want 'Update my mission control reads the newest release and does not take this PC back' {
  ($check.Contains('You have the newest version already.') -or $check.Contains('newer than the newest release')) -and
    $check.Contains('CHECK: would bring this PC up to date') -and -not $check.Contains('would download')
}

# 4. Nothing a silent run shows.
$shown = @(Receive-Job $watch -Keep | Sort-Object -Unique)
Stop-Job $watch -ErrorAction SilentlyContinue
"windows the setup showed: $($shown -join '; ')"
# The setup's own windows only: a message box of the setup is titled "Setup" or names Godspeed, and
# a GitHub machine opens windows of its own now and then (System Properties was seen once).
# The old updater runs the setup with /SILENT, which shows its progress in the wizard's window: that one is meant.
Want 'the silent runs showed no wizard and no message box' { @($shown | Where-Object { ($_ -match '^TWizardForm\|' -and $Mode -ne 'updater') -or $_ -match '^#32770\|.*(Setup|Godspeed|Uninstall)' }).Count -eq 0 }

# 5. The uninstaller: the program's own files go, the reader's stay.
$recorded = @(Get-Content (Join-Path $HOME '.godspeed\installed-commands.txt'))
$code = Invoke-Setup (Join-Path $app 'unins000.exe') @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'uninstall' 15
Start-Sleep -Seconds 5
$bin = Join-Path $HOME '.local\bin'
$left = @($recorded | Where-Object { Test-Path (Join-Path $bin $_) })
Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\uninstall-log.txt') -ErrorAction SilentlyContinue
Want 'uninstall: none of the helpers the setup wrote is left' { $left.Count -eq 0 -and -not (Test-Path (Join-Path $bin 'run-hidden.vbs')) }
Want 'uninstall: no daily job, no Startup entry, no program folder, no Hermes program' {
  -not (Get-ScheduledTask -TaskName 'Godspeed prompt archive' -ErrorAction SilentlyContinue) -and
    -not (Test-Path (Join-Path $startup 'Godspeed Mission Control.lnk')) -and -not (Test-Path $app) -and
    -not (Test-Path (Join-Path $state 'hermes-runtime'))
}
Want 'uninstall: no Start menu entry is left' {
  -not (Test-Path (Join-Path $group 'Open my notebook.lnk')) -and -not (Test-Path (Join-Path $group 'Open my notebook.url')) -and
    -not (Test-Path (Join-Path $group 'Update my mission control.lnk'))
}
Want 'uninstall: the commands folder left PATH if nothing else is in it' {
  (Test-Path $bin) -or -not (([Environment]::GetEnvironmentVariable('Path', 'User') -split ';') -contains $bin)
}
Want 'uninstall: the mission control, the notebook data and the conversations stay' {
  (Test-Path (Join-Path $mc 'AGENTS.md')) -and (Test-Path (Join-Path $state 'installation.json')) -and (Test-Path (Join-Path $state 'hermes-profile'))
}
Want 'uninstall: GODSPEED_DIR no longer points at it' { -not [Environment]::GetEnvironmentVariable('GODSPEED_DIR', 'User') }
if ($moved) { Want 'uninstall: no folder under the old names came back' { -not (Test-Path $oldState) -and -not (Test-Path $oldApp) } }

Copy-Item (Join-Path $env:LOCALAPPDATA 'Godspeed\*.txt') $Evidence -ErrorAction SilentlyContinue
Get-ChildItem $state -Filter *.log -ErrorAction SilentlyContinue | Copy-Item -Destination $Evidence -ErrorAction SilentlyContinue
if ($script:fail) { "$($script:fail) failed"; exit 1 } else { 'ALL PASS' }

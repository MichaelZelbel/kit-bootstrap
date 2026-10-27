<#
  GodspeedSetup.exe on a fresh GitHub Windows machine, the way a reader runs it silently, and what
  the faults that beta testers met first look like afterwards (18 October 2026):

    fresh    a first installation
    update   the newest published release first, a reader's notes in it, then this installer with
             nothing chosen, which must update that mission control in place

  and on both: the run waits until it is done (the documented command), nothing asks or shows a
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
  [ValidateSet('fresh', 'update')][string]$Mode = 'fresh',
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

$state = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$app = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha'
$mc = Join-Path $HOME 'godspeed-v2'
$built = Get-Content $Manifest -Raw | ConvertFrom-Json
$setupLog = Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt'
"under test: notebook $($built.kitCommit), installer $($built.bootstrapCommit), version $($built.version)"

if ($Mode -eq 'update') {
  $code = Invoke-Setup $Previous @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'previous'
  $prev = Get-Content (Join-Path $state 'installation.json') -Raw | ConvertFrom-Json
  "previous release: $($prev.kitCommit) at $($prev.workspace) (exit $code)"
  Set-Content -Path (Join-Path $mc 'my-own-notes.md') -Value 'Written by the reader before the update.' -Encoding utf8
  $body = '{"table":"notes","operation":"insert","values":{"id":"written-before-the-update","title":"Written before the update","content":"This note was written with the previous release."},"selection":"*","single":true}'
  try { (Invoke-RestMethod http://127.0.0.1:47831/api/query -Method Post -ContentType 'application/json' -Body $body).data.id } catch { "the note could not be written: $_" }
  Remove-Item $setupLog -ErrorAction SilentlyContinue
}

# 1. The installer under test, silent, nothing chosen.
$code = Invoke-Setup $Setup @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') 'setup'
Want 'the silent setup finished with exit 0 and its result says ok' { $code -eq 0 -and ((Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-result.txt') -Raw).Trim() -eq 'ok') }
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
$startup = [Environment]::GetFolderPath('Startup')
Want 'the Startup entry starts the notebook without opening the browser, under one plain name' {
  $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $startup 'Godspeed Mission Control.lnk'))
  $lnk.Arguments.Contains('start-full-alpha.ps1" -NoBrowser') -and -not (Test-Path (Join-Path $startup 'Godspeed Mission Control Full Alpha.lnk'))
}
# "Open my notebook" was the bare address until 26 October 2026, an "Open my notebook.url" that the
# previous release still makes; after the update only the new entry carries that name.
$group = Join-Path ([Environment]::GetFolderPath('Programs')) 'Godspeed Mission Control'
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
Want "the Apps list shows one Godspeed Mission Control, version $($built.version), no alpha" {
  $apps.Count -eq 1 -and $apps[0].DisplayName -eq 'Godspeed Mission Control' -and $apps[0].DisplayVersion -eq $built.version -and
    -not ($built.version -match 'alpha')
}
# The version resource pads its texts with spaces, which the Properties window does not show.
Want "the installer's file properties say Godspeed Mission Control $($built.version)" {
  $v = (Get-Item $Setup).VersionInfo
  $v.ProductVersion.Trim() -eq $built.version -and $v.ProductName.Trim() -eq 'Godspeed Mission Control' -and -not ($v.ProductVersion -match 'alpha')
}
Want 'the commands it put on this PC are recorded for the uninstaller' { @(Get-Content (Join-Path $HOME '.godspeed\installed-commands.txt')).Count -ge 5 }
if ($Mode -eq 'update') {
  Want 'the update went into the mission control that was there, and made no second one' { -not (Test-Path (Join-Path $HOME 'godspeed')) -and @(Get-ChildItem $HOME -Directory -Filter 'godspeed*').Count -eq 1 }
  Want 'it saved a copy of the notebook first' { @(Get-ChildItem (Join-Path $state 'backups') -Directory -ErrorAction SilentlyContinue).Count -ge 1 }
  Want "the reader's own file is untouched" { (Get-Content (Join-Path $mc 'my-own-notes.md') -Raw).Contains('Written by the reader before the update.') }
  Want 'the note written with the previous release is still there' {
    $notes = Invoke-RestMethod http://127.0.0.1:47831/api/query -Method Post -ContentType 'application/json' -Body '{"table":"notes","operation":"select"}' -TimeoutSec 30
    @($notes.data | Where-Object { $_.id -eq 'written-before-the-update' }).Count -eq 1
  }
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
Want 'the silent runs showed no wizard and no message box' { @($shown | Where-Object { $_ -match '^TWizardForm\|' -or $_ -match '^#32770\|.*(Setup|Godspeed|Uninstall)' }).Count -eq 0 }

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

Copy-Item (Join-Path $env:LOCALAPPDATA 'Godspeed\*.txt') $Evidence -ErrorAction SilentlyContinue
Get-ChildItem $state -Filter *.log -ErrorAction SilentlyContinue | Copy-Item -Destination $Evidence -ErrorAction SilentlyContinue
if ($script:fail) { "$($script:fail) failed"; exit 1 } else { 'ALL PASS' }

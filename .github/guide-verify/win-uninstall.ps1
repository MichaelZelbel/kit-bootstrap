<#
  The guide's "Uninstall on Windows" and "Remove the rest on Windows" (uninstall.md), with the
  uninstaller run silently, then everything of Godspeed Mission Control and Hermes still on the PC.
  Evidence only; never fails the job by itself.
#>
param([string]$Evidence = 'evidence')
$ErrorActionPreference = 'Continue'
$state = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$app = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha'
$mc = Join-Path $env:USERPROFILE 'godspeed-v2'
function Section($t) { "`n`n########## $t" }
function Have($p) { if (Test-Path -LiteralPath $p) { "present  $p" } else { "gone     $p" } }
function Leftovers {
  foreach ($p in @($app, $state, $mc, (Join-Path $env:LOCALAPPDATA 'Godspeed'), (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt'), (Join-Path $env:USERPROFILE '.godspeed'),
                   (Join-Path $env:USERPROFILE '.local\bin'), (Join-Path ([Environment]::GetFolderPath('Startup')) 'Godspeed Mission Control Full Alpha.lnk'),
                   (Join-Path ([Environment]::GetFolderPath('Programs')) 'Godspeed Mission Control'), (Join-Path $state 'media'), (Join-Path $state 'backups'), (Join-Path $state 'hermes-profile'), (Join-Path $state 'hermes-runtime'))) { Have $p }
  '.local\bin:'; Get-ChildItem (Join-Path $env:USERPROFILE '.local\bin') -Name -ErrorAction SilentlyContinue
  'scheduled tasks:'; Get-ScheduledTask | Where-Object { $_.TaskName -like '*Godspeed*' } | ForEach-Object { "  $($_.TaskName) ($($_.State))" }
  'Apps list:'; Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall' | ForEach-Object { $p = Get-ItemProperty $_.PSPath; if ($p.DisplayName -like '*Godspeed*' -or $p.DisplayName -like '*Hermes*') { "  $($p.DisplayName)" } }
  'Run keys:'; Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | Out-String -Width 300
  'processes:'; Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'Godspeed|godspeed|hermes|Hermes' -and $_.Name -ne 'pwsh.exe' } | ForEach-Object { "  $($_.ProcessId) $($_.Name) $($_.CommandLine)" }
  try { Invoke-RestMethod http://127.0.0.1:47831/health -TimeoutSec 5 | ConvertTo-Json -Compress } catch { 'nothing answers on 127.0.0.1:47831' }
  'anything named godspeed or hermes in the user''s folders:'
  foreach ($root in $env:LOCALAPPDATA, $env:APPDATA, $env:USERPROFILE) { Get-ChildItem $root -Force -Depth 1 -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'godspeed|hermes' } | ForEach-Object { "  $($_.FullName)" } }
  'user PATH:'; [Environment]::GetEnvironmentVariable('Path', 'User')
}

Section 'before'
Leftovers
Section 'the uninstaller, run silently (Start menu: Uninstall Godspeed Mission Control)'
$group = Join-Path ([Environment]::GetFolderPath('Programs')) 'Godspeed Mission Control'
$lnk = Get-ChildItem $group -Filter 'Uninstall*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($lnk) { $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk.FullName); "the Start menu entry runs: $($s.TargetPath)"; $un = $s.TargetPath } else { $un = Join-Path $app 'unins000.exe' }
$started = Get-Date
$p = Start-Process $un -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/LOG=$((Resolve-Path $Evidence).Path)\uninstall.log" -PassThru
$p.WaitForExit(600000) | Out-Null
"uninstaller exit: $($p.ExitCode)"
# The uninstaller copies itself to a temporary folder and finishes from there; wait for that too.
$until = (Get-Date).AddMinutes(5)
while ((Get-Process | Where-Object { $_.Path -match '\\_iu|\\is-|unins' }) -and (Get-Date) -lt $until) { Start-Sleep 2 }
"took $([int]((Get-Date) - $started).TotalSeconds) s"
Start-Sleep 5
Section 'after the uninstaller (the page: it removes the program folder and the Startup entry, stops the notebook, keeps the rest)'
Leftovers

Section 'Remove the rest on Windows, as the page writes it'
# Each step on its own, so an error in one is shown and the next still runs.
function Step($what, [scriptblock]$do) { "$what"; try { & $do; '   done' } catch { "   ERROR: $($_.Exception.Message)" } }
Step '1. delete the state folder' { Remove-Item -LiteralPath "$env:LOCALAPPDATA\Godspeed Mission Control Full Alpha State" -Recurse -Force -ErrorAction Stop }
Step '2a. Unregister-ScheduledTask -TaskName "Godspeed prompt archive" -Confirm:$false' { Unregister-ScheduledTask -TaskName "Godspeed prompt archive" -Confirm:$false -ErrorAction Stop }
Step '2b. Unregister-ScheduledTask -TaskName "Godspeed notebook sync" -Confirm:$false' { Unregister-ScheduledTask -TaskName "Godspeed notebook sync" -Confirm:$false -ErrorAction Stop }
Step '3a. delete %USERPROFILE%\.godspeed' { Remove-Item -LiteralPath "$env:USERPROFILE\.godspeed" -Recurse -Force -ErrorAction Stop }
Step '3b. delete the mc-* files in %USERPROFILE%\.localin' { Get-ChildItem "$env:USERPROFILE\.localin" -Filter 'mc-*' -ErrorAction Stop | Remove-Item -Force -ErrorAction Stop }
Step '4. the setup log folder %LOCALAPPDATA%\Godspeed' { Remove-Item -LiteralPath "$env:LOCALAPPDATA\Godspeed" -Recurse -Force -ErrorAction Stop }
Step '6. the mission control folder' { Remove-Item -LiteralPath $mc -Recurse -Force -ErrorAction Stop }
Section 'after every step: what is still on this PC'
Leftovers

exit 0

<#
  GodspeedSetup.exe with its wizard on screen, driven the way the public guide tells a reader to
  click, every page read (each text the wizard shows, and a picture), every message box read.

    -Plan fresh   install-windows.md: Next on every page. On "Where your mission control goes" it
                  first types a Documents folder to see the refusal the page quotes, then puts the
                  suggested folder back.
    -Plan update  updates-and-versions.md, "Update on Windows": leave the box ticked, Next; on the
                  folder page it first clicks Next to see the "cannot sit beside itself" message,
                  then, as step 4 says for a version 2 folder: Back, untick the box, Next; Install.
    -Plan next    Next on every page and nothing else (a PC with the first edition: the box for a
                  second mission control stays ticked, as install-windows.md step 3 says).
    -Uninstall    afterwards the Start menu's uninstaller with its messages on screen: Yes, then OK.

  KB_UNATTENDED=1 (set by the caller) only keeps the setup's console window from asking its own
  questions; the wizard's pages are unchanged by it. Based on test-finish-page.ps1 (16 October).
#>
param(
  [Parameter(Mandatory)][string]$Setup,
  [ValidateSet('fresh', 'update', 'next')][string]$Plan = 'fresh',
  [string]$Evidence = 'evidence',
  [int]$TimeoutMinutes = 90,
  [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
. (Join-Path $PSScriptRoot 'wiz-lib.ps1')

$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$log = Join-Path $Evidence "wizard-$Plan-setup.log"
$p = Start-Process (Resolve-Path $Setup).Path -ArgumentList "/LOG=`"$log`"" -PassThru
"setup started (process $($p.Id)), wizard on screen, plan: $Plan"
$visits = @{}; $dialogsOn = @{}; $lastSig = ''; $acted = $false; $actedAt = Get-Date; $toggleTries = 0
$suggested = $null; $finishDone = $false; $result = @()
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
try {
  while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 1500
    $w = Wizard
    $heading = if ($w -ne [IntPtr]::Zero) { Heading @(Controls $w) } else { '' }
    foreach ($d in @(Dialogs)) {
      $said = Answer-Dialog $d @('OK', 'Yes')
      $result += "dialog on '$heading': $said"
      $dialogsOn[$heading] = 1 + [int]$dialogsOn[$heading]; $acted = $false
    }
    if ($w -eq [IntPtr]::Zero) { if ($p.HasExited) { "the setup ended (exit $($p.ExitCode))"; break }; continue }
    $c = @(Controls $w)
    $buttons = @($c | Where-Object { $_.Class -eq 'TNewButton' })
    $desc = ($c | Where-Object { $_.Class -eq 'TNewStaticText' -and $_.Text } | Select-Object -First 3 | ForEach-Object Text) -join ' / '
    $sig = "$heading|$desc|" + (($buttons | Where-Object Enabled | ForEach-Object Name) -join ',')
    if ($sig -ne $lastSig) {
      if (-not ($heading -eq $script:lastHeading)) { $visits[$heading] = 1 + [int]$visits[$heading] }
      $script:lastHeading = $heading
      Dump $w "page $heading (visit $($visits[$heading]))"
      $lastSig = $sig; $acted = $false
    }
    $finish = $buttons | Where-Object { $_.Name -eq 'Finish' -and $_.Enabled } | Select-Object -First 1
    if ($finish) { Start-Sleep 2; Dump $w 'finish page'; [Wiz]::Click($finish.H); $finishDone = $true; break }
    if ($acted) { if (((Get-Date) - $actedAt).TotalSeconds -gt 90) { "the page did not move for 90 s after: $lastAction; trying again"; $acted = $false } else { continue } }
    $next = $buttons | Where-Object { ($_.Name -eq 'Next' -or $_.Name -eq 'Install') -and $_.Enabled } | Select-Object -First 1
    $back = $buttons | Where-Object { $_.Name -eq 'Back' -and $_.Enabled } | Select-Object -First 1
    if (-not $next) { continue }
    $lastAction = "Next on $heading"
    [void][Wiz]::SetForegroundWindow($w)
    if ($heading -eq 'Where your mission control goes') {
      $edit = $c | Where-Object { $_.Class -match 'Edit' } | Select-Object -First 1
      if ($null -eq $suggested -and $edit) { $suggested = $edit.Text; "the folder box suggests: $suggested" }
      if ($Plan -eq 'fresh') {
        if (-not $dialogsOn[$heading]) { $lastAction = 'a Documents folder typed, then Next'; [Wiz]::SetText($edit.H, (Join-Path $env:USERPROFILE 'Documents\godspeed-v2')); "typed: $([Wiz]::Text($edit.H))" }
        else { [Wiz]::SetText($edit.H, $suggested); "folder box back to: $([Wiz]::Text($edit.H))" }
      } elseif ($Plan -eq 'update') {
        if (-not $dialogsOn[$heading]) { $lastAction = 'Next on the folder page of a second mission control (expecting the refusal)' }
        else { "updates-and-versions step 4: the folder is the version 2 folder, so Back"; [Wiz]::Click($back.H); $acted = $true; $actedAt = Get-Date; $lastAction = 'Back'; continue }
      }
    }
    if ($heading -eq 'You already have a mission control' -and $Plan -eq 'update' -and $visits[$heading] -ge 2) {
      $list = $c | Where-Object { $_.Class -match 'CheckListBox' } | Select-Object -First 1
      $how = @('posted click', 'real mouse click', 'space bar')[[Math]::Min($toggleTries, 2)]
      "untick the box ($how)"
      switch ($how) { 'posted click' { [Wiz]::PostClick($list.H, 10, 9) } 'real mouse click' { [Wiz]::RealClick($list.H, 12, 11) } 'space bar' { [Wiz]::Space($list.H) } }
      $toggleTries++
      Start-Sleep 2; Dump $w 'the box after unticking' | Out-Host
    }
    "click: $($next.Text) on '$heading'"
    [Wiz]::Click($next.H); $acted = $true; $actedAt = Get-Date
  }
  if (-not $finishDone) { $w = Wizard; if ($w -ne [IntPtr]::Zero) { Picture $w (Join-Path $Evidence 'timeout.png') }; "NO FINISH PAGE within $TimeoutMinutes minutes (or the setup ended)" }
  if (-not $p.WaitForExit(120000)) { 'the setup did not close after Finish' } else { "setup exit: $($p.ExitCode)" }
} finally { Close-Setup $p }
"`nmessage boxes seen:"; $result

if ($Uninstall) {
  "`n==== the uninstaller with its messages on screen (Start menu: Uninstall Godspeed Mission Control)"
  $un = Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha\unins000.exe'
  $u = Start-Process $un -PassThru
  $until = (Get-Date).AddMinutes(15); $seen = 0
  while ((Get-Date) -lt $until) {
    Start-Sleep 2
    foreach ($d in @(Dialogs)) { $said = Answer-Dialog $d @('Yes', 'OK'); "uninstall message: $said"; $seen++ }
    if ($seen -ge 2 -and -not (Get-Process | Where-Object { $_.Path -match '\\_iu|unins' })) { break }
  }
  "uninstall messages answered: $seen"
  Get-Process | Where-Object { $_.Path -match '\\_iu|unins' } | Stop-Process -Force -ErrorAction SilentlyContinue
}

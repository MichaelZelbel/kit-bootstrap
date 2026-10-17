<#
  A silent GodspeedSetup.exe run, watched: any message box it shows anyway (a silent run has
  nobody to answer one) is read, pictured and answered with OK, so the run can end and say what
  it did. For install-windows.md, "Install without the wizard": on a PC that already has a
  mission control, what does `.\GodspeedSetup.exe /VERYSILENT /SUPPRESSMSGBOXES` do?

    ./.github/guide-verify/silent-watch.ps1 -Setup .\GodspeedSetup.exe -Arguments '/VERYSILENT','/SUPPRESSMSGBOXES'
#>
param(
  [Parameter(Mandatory)][string]$Setup,
  [string[]]$Arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES'),
  [string]$Evidence = 'evidence',
  [int]$TimeoutMinutes = 75,
  [int]$AnswerAfterSeconds = 120
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
. (Join-Path $PSScriptRoot 'wiz-lib.ps1')
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$log = Join-Path $Evidence 'silent-setup.log'
$started = Get-Date
$p = Start-Process (Resolve-Path $Setup).Path -ArgumentList ($Arguments + "/LOG=`"$log`"") -PassThru
"started: $Setup $($Arguments -join ' ')  (process $($p.Id))"
$firstSeen = @{}; $answered = 0
try {
  while (-not $p.HasExited -and ((Get-Date) - $started).TotalMinutes -lt $TimeoutMinutes) {
    Start-Sleep 3
    foreach ($d in @(Dialogs)) {
      $key = [string]$d
      if (-not $firstSeen.ContainsKey($key)) {
        $firstSeen[$key] = Get-Date
        "a message box appeared after $([int]((Get-Date) - $started).TotalSeconds) s, with nobody there to answer it:"
        Dump $d 'message box during a silent run'
      }
      # It is left on screen for a while first, to show it really waits; then answered.
      if (((Get-Date) - $firstSeen[$key]).TotalSeconds -ge $AnswerAfterSeconds) {
        "still waiting after $AnswerAfterSeconds s; answering it now"
        [void](Answer-Dialog $d @('OK', 'Yes')); $answered++
      }
    }
    $w = Wizard
    if ($w -ne [IntPtr]::Zero -and -not $script:wizardSeen) { $script:wizardSeen = $true; 'the wizard window became visible during a silent run:'; Dump $w 'wizard during silent run' }
  }
  if ($p.HasExited) { "setup ended after $([int]((Get-Date) - $started).TotalSeconds) s, exit $($p.ExitCode); message boxes answered: $answered" }
  else { "setup still running after $TimeoutMinutes minutes; stopped"; Close-Setup $p }
} finally { Close-Setup $p }
'setup log, its last 40 lines:'; Get-Content $log -Tail 40 -ErrorAction SilentlyContinue

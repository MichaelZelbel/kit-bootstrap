<#
  Download one release's GodspeedSetup.exe from GitHub, check it against that release's
  SHA256SUMS, run it with the given switches and wait for it, then say what it left:
  exit code, setup-result.txt, the end of setup-log.txt and installation.json.

    ./.github/guide-verify/win-install.ps1 -Release godspeed-v2-integrated-2026-10-16-1 -Switches '/VERYSILENT','/SUPPRESSMSGBOXES'
#>
param(
  [Parameter(Mandatory)][string]$Release,
  [string[]]$Switches = @('/VERYSILENT', '/SUPPRESSMSGBOXES'),
  [string]$Evidence = 'evidence',
  [switch]$DownloadOnly
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Evidence | Out-Null
$Evidence = (Resolve-Path $Evidence).Path
$base = "https://github.com/MichaelZelbel/godspeed-mission-control/releases/download/$Release"
$exe = Join-Path $env:RUNNER_TEMP "$Release-GodspeedSetup.exe"
if (-not (Test-Path $exe)) { Invoke-WebRequest "$base/GodspeedSetup.exe" -OutFile $exe -UseBasicParsing }
$sums = (Invoke-WebRequest "$base/SHA256SUMS" -UseBasicParsing).Content
$want = ($sums -split "`n" | Where-Object { $_ -match 'GodspeedSetup\.exe' }) -replace '\s.*$', ''
$have = (Get-FileHash $exe -Algorithm SHA256).Hash.ToLower()
"$Release GodspeedSetup.exe: $have (SHA256SUMS says $want)"
if ($have -ne $want.Trim()) { throw 'not the release file' }
if ($DownloadOnly) { return }
$env:PSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$log = Join-Path $Evidence "$Release-setup.log"
$started = Get-Date
$p = Start-Process $exe -ArgumentList ($Switches + "/LOG=`"$log`"") -PassThru
if (-not $p.WaitForExit(4500000)) { 'STILL RUNNING AFTER 75 MINUTES'; Stop-Process -Id $p.Id -Force }
"$Release with $($Switches -join ' '): exit $($p.ExitCode) after $([int]((Get-Date) - $started).TotalMinutes) min"
"setup-result.txt: " + (Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-result.txt') -Raw -ErrorAction SilentlyContinue)
'setup-log.txt, its last 25 lines:'
Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed\setup-log.txt') -Tail 25 -ErrorAction SilentlyContinue
'installation.json:'
Get-Content (Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State\installation.json') -Raw -ErrorAction SilentlyContinue
try { 'health: ' + (Invoke-WebRequest http://127.0.0.1:47831/health -UseBasicParsing -TimeoutSec 15).Content } catch { "health: $($_.Exception.Message)" }

param([Parameter(Mandatory)][string]$AppRoot)
$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
New-Item -ItemType Directory -Force -Path $state|Out-Null
try{
  & (Join-Path $AppRoot 'setup-full-alpha.ps1') -AppRoot $AppRoot *> (Join-Path $state 'setup.log')
  exit 0
}catch{
  $_|Out-String|Add-Content -LiteralPath (Join-Path $state 'setup.log')
  exit 1
}

param([Parameter(Mandatory)][string]$AppRoot)
$ErrorActionPreference='Stop'
# A launcher started by PowerShell 7 can inherit its module path. Native 5.1
# must resolve Windows modules before the caller's optional modules.
$nativeModules=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\Modules'
$env:PSModulePath=$nativeModules+';'+$env:PSModulePath
Import-Module (Join-Path $nativeModules 'Microsoft.PowerShell.Utility') -Force
Import-Module (Join-Path $nativeModules 'Microsoft.PowerShell.Management') -Force
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
New-Item -ItemType Directory -Force -Path $state|Out-Null
try{
  & (Join-Path $AppRoot 'setup-full-alpha.ps1') -AppRoot $AppRoot *> (Join-Path $state 'setup.log')
  exit 0
}catch{
  $_|Out-String|Add-Content -LiteralPath (Join-Path $state 'setup.log')
  exit 1
}

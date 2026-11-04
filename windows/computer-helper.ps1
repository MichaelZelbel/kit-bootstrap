param([ValidateSet('pair','run','pause','resume','off','status','pages')][string]$Action='status',[string]$Code)
# Started from PowerShell 7, Windows PowerShell 5.1 inherits its module path and cannot find Get-FileHash: use its own.
if($PSVersionTable.PSEdition -eq 'Desktop' -and $env:PSModulePath -match '(?i)[\\/]PowerShell[\\/](7[^\\/;]*|Modules)([\\/;]|$)'){$env:PSModulePath=(@((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),$(if([Environment]::GetEnvironmentVariable('PSModulePath','Machine')){[Environment]::GetEnvironmentVariable('PSModulePath','Machine')}else{(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')+';'+(Join-Path $PSHOME 'Modules')}))|Where-Object{$_}) -join ';'}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$state=Get-GodspeedStateFolder
$config=Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
if($config.channel -ne 'full-alpha'){throw 'The notebook record on this PC is not one this setup made.'}
$env:GODSPEED_COMPUTER_HOME=Join-Path $state 'computer'
$env:GODSPEED_COMPUTER_PROFILE=Join-Path $state 'computer\profile'
$node=Join-Path $config.appRoot 'payload\runtime\node.exe'
$helper=Join-Path $config.appRoot 'payload\kit\computer\helper.js'
$arguments=@($helper,$Action);if($Code){$arguments+=$Code}
& $node @arguments
if($LASTEXITCODE -ne 0){throw 'Lending this computer''s browser to your assistant did not finish.'}

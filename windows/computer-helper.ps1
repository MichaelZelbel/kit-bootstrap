param([ValidateSet('pair','run','pause','resume','off','status','pages')][string]$Action='status',[string]$Code)
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

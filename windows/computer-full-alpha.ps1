param([ValidateSet('pair','run','pause','resume','off','status','pages')][string]$Action='status',[string]$Code)
$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$config=Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
if($config.channel -ne 'full-alpha'){throw 'Choose the isolated full alpha installation.'}
$env:GODSPEED_COMPUTER_HOME=Join-Path $state 'computer'
$env:GODSPEED_COMPUTER_PROFILE=Join-Path $state 'computer\profile'
$node=Join-Path $config.appRoot 'payload\runtime\node.exe'
$helper=Join-Path $config.appRoot 'payload\kit\computer\helper.js'
$arguments=@($helper,$Action);if($Code){$arguments+=$Code}
& $node @arguments
if($LASTEXITCODE -ne 0){throw 'Candidate computer connection did not finish.'}

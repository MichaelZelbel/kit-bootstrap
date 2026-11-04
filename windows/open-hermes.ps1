# Started from PowerShell 7, Windows PowerShell 5.1 inherits its module path and cannot find Get-FileHash: use its own.
if($PSVersionTable.PSEdition -eq 'Desktop' -and $env:PSModulePath -match '(?i)[\\/]PowerShell[\\/](7[^\\/;]*|Modules)([\\/;]|$)'){$env:PSModulePath=(@((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),$(if([Environment]::GetEnvironmentVariable('PSModulePath','Machine')){[Environment]::GetEnvironmentVariable('PSModulePath','Machine')}else{(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')+';'+(Join-Path $PSHOME 'Modules')}))|Where-Object{$_}) -join ';'}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$state=Get-GodspeedStateFolder
$assistant=Get-Content -LiteralPath (Join-Path $state 'assistant.json') -Raw|ConvertFrom-Json
if(-not $assistant.verified){throw 'Hermes is not installed for this notebook yet. Run Update my mission control from the Start menu.'}
$env:HERMES_HOME=$assistant.home
$env:HERMES_DESKTOP_USER_DATA_DIR=Join-Path $state 'hermes-desktop-data'
# The window's name, the same the notebook's Open the Windows assistant gives it.
$env:HERMES_DESKTOP_APP_NAME='Godspeed Mission Control Assistant'
$env:HERMES_DESKTOP_HERMES_ROOT=$assistant.sourceRoot
$env:HERMES_DESKTOP_CWD=$assistant.workspace
$env:GODSPEED_WORKSPACE=$assistant.workspace
$installation=Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
$notebook=Join-Path $installation.appRoot 'payload\kit\notebook'
$env:GODSPEED_ORIGINAL_RUNTIME='on'
$env:GODSPEED_FILE_HERMES='0'
$env:GODSPEED_NODE=Join-Path $installation.appRoot 'payload\runtime\node.exe'
$env:GODSPEED_ASSISTANT_PUBLISHER=Join-Path $notebook 'scripts\save-assistant-state.mjs'
$env:PYTHONPATH=(Join-Path $notebook 'assistant-files')+';'+$env:PYTHONPATH
$env:PLAYWRIGHT_BROWSERS_PATH=Join-Path $state 'hermes-runtime\browser-cache'
Start-Process -FilePath $assistant.desktop -WorkingDirectory $assistant.workspace -WindowStyle Hidden

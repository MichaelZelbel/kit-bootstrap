$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$assistant=Get-Content -LiteralPath (Join-Path $state 'assistant.json') -Raw|ConvertFrom-Json
if(-not $assistant.verified){throw 'Hermes desktop installation must finish before opening the candidate assistant.'}
$env:HERMES_HOME=$assistant.home
$env:HERMES_DESKTOP_USER_DATA_DIR=Join-Path $state 'hermes-desktop-data'
$env:HERMES_DESKTOP_APP_NAME='Godspeed Mission Control Full Alpha Assistant'
$env:HERMES_DESKTOP_HERMES_ROOT=$assistant.sourceRoot
$env:HERMES_DESKTOP_CWD=$assistant.workspace
$env:GODSPEED_WORKSPACE=$assistant.workspace
Start-Process -FilePath $assistant.desktop -WorkingDirectory $assistant.workspace -WindowStyle Hidden

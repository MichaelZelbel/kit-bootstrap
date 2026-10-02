param([switch]$FreshInstaller)
$ErrorActionPreference='Stop'
$testRoot=Join-Path $env:TEMP ('Godspeed-full-alpha-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $testRoot|Out-Null
$evidence=[ordered]@{at=[DateTime]::UtcNow.ToString('o');freshAccount=$env:CI -eq 'true';checks=@();testRoot=$testRoot}
$output=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $output|Out-Null
if($FreshInstaller){
  if($env:CI -ne 'true'){throw 'Fresh executable installation is restricted to an ephemeral CI account.'}
  $app=Join-Path $testRoot 'application'
  $installer=Join-Path $output 'GodspeedSetup-Full-Alpha.exe'
  $p=Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$app+'"'),('/LOG="'+(Join-Path $output 'installer-test.log')+'"')) -WindowStyle Hidden -Wait -PassThru
  if($p.ExitCode -ne 0){throw ('Fresh installer exited '+$p.ExitCode)}
  $evidence.checks+='fresh installer including isolated Hermes desktop'
  $state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
  $settings=Get-Content (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
  $node=Join-Path $app 'payload/runtime/node.exe'
  $cli=Join-Path $app 'payload/kit/notebook/bin/godspeed.mjs'
  $env:GODSPEED_WORKSPACE=$settings.workspace
  $env:GODSPEED_MEDIA_ROOT=$settings.media
  $record=Join-Path $testRoot 'note.json'
  @{id='offline-test';title='Offline candidate test';content='Created without a VPS connection.'}|ConvertTo-Json|Set-Content $record
  & $node $cli record save notes $record|Out-Null
  if($LASTEXITCODE -ne 0){throw 'Offline save failed'}
  & (Join-Path $app 'stop-full-alpha.ps1')
  & (Join-Path $app 'start-full-alpha.ps1') -NoBrowser
  $health=Invoke-RestMethod ('http://127.0.0.1:'+$settings.port+'/health')
  if(-not $health.ok){throw 'Restart health failed'}
  $evidence.checks+='restart and offline file retention'
  $p=Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$app+'"')) -WindowStyle Hidden -Wait -PassThru
  if($p.ExitCode -ne 0){throw 'Upgrade failed'}
  $saved=& $node $cli record get notes offline-test|ConvertFrom-Json
  if($saved.content -ne 'Created without a VPS connection.'){throw 'Upgrade changed user data'}
  if(-not (Get-ChildItem (Join-Path $state 'backups') -Directory)){throw 'Upgrade did not create a backup'}
  $assistant=Get-Content (Join-Path $state 'assistant.json') -Raw|ConvertFrom-Json
  if(-not $assistant.verified -or -not(Test-Path $assistant.desktop)){throw 'Hermes desktop missing'}
  $evidence.checks+='upgrade, integrity backup and Hermes desktop'
  & (Join-Path $app 'stop-full-alpha.ps1')
  $uninstall=Start-Process -FilePath (Join-Path $app 'unins000.exe') -ArgumentList '/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -WindowStyle Hidden -Wait -PassThru
  if($uninstall.ExitCode -ne 0 -or -not(Test-Path (Join-Path $settings.workspace 'records/notes/offline-test.md'))){throw 'Uninstall did not preserve user records'}
  $evidence.checks+='uninstall preserves knowledge'
}
$evidence|ConvertTo-Json -Depth 8|Set-Content (Join-Path $output 'clean-install-evidence.json')
(Get-FileHash (Join-Path $output 'GodspeedSetup-Full-Alpha.exe')).Hash.ToLowerInvariant()+'  GodspeedSetup-Full-Alpha.exe'|Set-Content (Join-Path $output 'SHA256SUMS')

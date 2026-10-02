param([switch]$FreshInstaller,[string]$PreviousInstaller)
$ErrorActionPreference='Stop'
$env:NODE_NO_WARNINGS='1'
$testRoot=Join-Path $env:TEMP ('Godspeed-full-alpha-test-'+[guid]::NewGuid())
New-Item -ItemType Directory -Force -Path $testRoot|Out-Null
$evidence=[ordered]@{at=[DateTime]::UtcNow.ToString('o');freshAccount=$env:CI -eq 'true';checks=@();testRoot=$testRoot}
$output=Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force -Path $output|Out-Null
if($FreshInstaller){
  if($env:CI -ne 'true'){throw 'Fresh executable installation is restricted to an ephemeral CI account.'}
  $app=Join-Path $testRoot 'application'
  $installer=Join-Path $output 'GodspeedSetup-Full-Alpha.exe'
  $state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
  $p=Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$app+'"'),('/LOG="'+(Join-Path $output 'installer-test.log')+'"')) -WindowStyle Hidden -PassThru
  $deadline=[DateTime]::UtcNow.AddMinutes(30)
  while(-not $p.WaitForExit(10000)){
    Get-ChildItem -LiteralPath $state -Filter '*.log' -ErrorAction SilentlyContinue|Copy-Item -Destination $output -ErrorAction SilentlyContinue
    foreach($logName in @('hermes-install.log','hermes-install-error.log')){if(Test-Path -LiteralPath (Join-Path $state $logName)){Get-Content -LiteralPath (Join-Path $state $logName) -Tail 2}}
    if([DateTime]::UtcNow -gt $deadline){Stop-Process -Id $p.Id -Force;throw 'Fresh installer exceeded the diagnostic timeout. Provisioning logs were preserved.'}
  }
  if($p.ExitCode -ne 0){Get-ChildItem $state -Filter '*.log' -ErrorAction SilentlyContinue|Copy-Item -Destination $output;throw ('Fresh installer exited '+$p.ExitCode)}
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
  $assistant=Get-Content (Join-Path $state 'assistant.json') -Raw|ConvertFrom-Json
  & (Join-Path $app 'open-hermes-full-alpha.ps1')
  $desktopDeadline=[DateTime]::UtcNow.AddSeconds(120)
  $nativeFiles=$null
  while([DateTime]::UtcNow -lt $desktopDeadline){
    $nativeFiles=Get-ChildItem (Join-Path $settings.workspace 'assistant-state') -Filter '*.json' -Recurse -ErrorAction SilentlyContinue|Where-Object {$_.FullName -notmatch '[\\/]history[\\/]'}
    if($nativeFiles){break};Start-Sleep -Seconds 2
  }
  $desktop=Get-CimInstance Win32_Process|Where-Object {$_.ExecutablePath -eq $assistant.desktop}
  if(-not $desktop -or -not $nativeFiles){throw 'The actual candidate desktop did not start its file-backed native assistant.'}
  $desktopIds=@($desktop|ForEach-Object {$_.ProcessId})
  foreach($process in ($desktop|Where-Object {$_.ParentProcessId -notin $desktopIds})){& taskkill /T /F /PID $process.ProcessId 2>$null|Out-Null}
  $evidence.checks+='actual Hermes desktop startup with file-backed conversation and work databases'
  $python=Join-Path $assistant.sourceRoot 'venv\Scripts\python.exe'
  $nativeId=& $python -c 'from hermes_state import SessionDB; db=SessionDB(); db.create_session("candidate-upgrade-history","cli"); mid=db.append_message("candidate-upgrade-history","user","Synthetic assistant history retained through version upgrade"); print(mid); db.close()'
  if($LASTEXITCODE -ne 0){throw 'Native assistant upgrade fixture could not be saved'}
  $nativeId=[long]($nativeId|Select-Object -Last 1);if($nativeId -lt 1){throw 'Native message identity was not returned'}
  $evidence.nativeMessageId=$nativeId
  $currentManifest=Get-Content (Join-Path $app 'payload/candidate-manifest.json') -Raw|ConvertFrom-Json
  if($PreviousInstaller){
    $previousManifest=Get-Content (Join-Path (Split-Path $PreviousInstaller -Parent) 'candidate-manifest.json') -Raw|ConvertFrom-Json
    if($previousManifest.kitCommit -eq $currentManifest.kitCommit){throw 'Upgrade verification requires different product versions'}
    $old=Start-Process -FilePath $PreviousInstaller -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$app+'"')) -WindowStyle Hidden -Wait -PassThru
    if($old.ExitCode -ne 0){throw 'Installing the prior candidate failed'}
    $installed=Get-Content (Join-Path $app 'payload/candidate-manifest.json') -Raw|ConvertFrom-Json
    if($installed.kitCommit -ne $previousManifest.kitCommit){throw 'The prior software was not installed'}
    $evidence.previousKitCommit=$previousManifest.kitCommit
  }
  $p=Start-Process -FilePath $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',('/DIR="'+$app+'"')) -WindowStyle Hidden -Wait -PassThru
  if($p.ExitCode -ne 0){throw 'Upgrade failed'}
  $saved=& $node $cli record get notes offline-test|ConvertFrom-Json
  if($saved.content -ne 'Created without a VPS connection.'){throw 'Upgrade changed user data'}
  $installed=Get-Content (Join-Path $app 'payload/candidate-manifest.json') -Raw|ConvertFrom-Json
  if($installed.kitCommit -ne $currentManifest.kitCommit){throw 'Upgrade did not replace the previous software'}
  Remove-Item -LiteralPath (Join-Path $assistant.home 'state.db')
  & $python -c 'import sys; from hermes_state import SessionDB; db=SessionDB(); messages=db.get_messages("candidate-upgrade-history"); assert len(messages)==1 and messages[0]["id"]==int(sys.argv[1]) and messages[0]["content"]=="Synthetic assistant history retained through version upgrade"; db.close()' ([string]$nativeId)
  if($LASTEXITCODE -ne 0){throw 'Native assistant history did not recover from files after version upgrade'}
  $evidence.checks+='different-version software upgrade preserves notebook and native assistant identity, including database deletion'
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

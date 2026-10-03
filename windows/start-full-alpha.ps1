param([switch]$NoBrowser)
$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$config=Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
if($config.channel -ne 'full-alpha'){throw 'Refusing to start a stable workspace.'}
$node=Join-Path $config.appRoot 'payload\runtime\node.exe'
$server=Join-Path $config.appRoot 'payload\kit\notebook\scripts\supervise.mjs'
$expectedInstance=(& $node -e "const c=require('node:crypto'),p=require('node:path');process.stdout.write(c.createHash('sha256').update(p.resolve(process.argv[1])).digest('hex').slice(0,24))" $config.workspace)
try{$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$config.port+'/health') -TimeoutSec 2;if($health.instance -eq $expectedInstance){$running=$true}else{throw 'Another workspace occupies the candidate port.'}}catch{if($_.Exception.Message -eq 'Another workspace occupies the candidate port.'){throw};$running=$false}
if(-not $running){
  $env:GODSPEED_WORKSPACE=$config.workspace;$env:GODSPEED_MEDIA_ROOT=$config.media;$env:GODSPEED_PORT=[string]$config.port;$env:GODSPEED_BIND='127.0.0.1'
  $env:GODSPEED_ASSISTANT_CONFIG=Join-Path $state 'assistant.json'
  if(Test-Path -LiteralPath $env:GODSPEED_ASSISTANT_CONFIG){$assistant=Get-Content -LiteralPath $env:GODSPEED_ASSISTANT_CONFIG -Raw|ConvertFrom-Json;if($assistant.verified){& $node (Join-Path $config.appRoot 'payload\kit\notebook\scripts\wire-assistant.mjs') $assistant.home;if($LASTEXITCODE -ne 0){throw 'Personal assistant workflow setup failed.'}}}
  $managedGit=Join-Path $state 'hermes-runtime\git\cmd';if(Test-Path -LiteralPath (Join-Path $managedGit 'git.exe')){$env:PATH=$managedGit+';'+$env:PATH}
  $providerFile=Join-Path $state 'provider.json'
  if(Test-Path -LiteralPath $providerFile){$provider=Get-Content -LiteralPath $providerFile -Raw|ConvertFrom-Json;$env:GODSPEED_MODEL_URL=$provider.url;$env:GODSPEED_MODEL_KEY=$provider.key;$env:GODSPEED_MODEL=$provider.model}
  $process=Start-Process -FilePath $node -ArgumentList @('"'+$server+'"') -WorkingDirectory (Split-Path -Parent $server) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'service.log') -RedirectStandardError (Join-Path $state 'service-error.log')
  [pscustomobject]@{pid=$process.Id;server=$server;node=$node}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $state 'process.json') -Encoding UTF8
  $healthy=$false
  for($attempt=0;$attempt -lt 30;$attempt++){try{$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$config.port+'/health') -TimeoutSec 2;if($health.instance -eq $expectedInstance){$healthy=$true;break}}catch{};Start-Sleep -Milliseconds 200}
  if(-not $healthy){throw 'The alpha notebook did not start. Its saved records are unchanged.'}
}
if(-not $NoBrowser){Start-Process ('http://127.0.0.1:'+$config.port+'/') -WindowStyle Hidden}

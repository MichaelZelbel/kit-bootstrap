param([switch]$NoBrowser)
$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$config=Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
if($config.channel -ne 'full-alpha'){throw 'Refusing to start a stable workspace.'}
$node=Join-Path $config.appRoot 'payload\runtime\node.exe'
$server=Join-Path $config.appRoot 'payload\kit\notebook\server\main.mjs'
try{$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$config.port+'/health') -TimeoutSec 2;if($health.version -eq '0.1.0-alpha.1'){$running=$true}}catch{$running=$false}
if(-not $running){
  $env:GODSPEED_WORKSPACE=$config.workspace;$env:GODSPEED_MEDIA_ROOT=$config.media;$env:GODSPEED_PORT=[string]$config.port;$env:GODSPEED_BIND='127.0.0.1'
  $providerFile=Join-Path $state 'provider.json'
  if(Test-Path -LiteralPath $providerFile){$provider=Get-Content -LiteralPath $providerFile -Raw|ConvertFrom-Json;$env:GODSPEED_MODEL_URL=$provider.url;$env:GODSPEED_MODEL_KEY=$provider.key;$env:GODSPEED_MODEL=$provider.model}
  $process=Start-Process -FilePath $node -ArgumentList @('"'+$server+'"') -WorkingDirectory (Split-Path -Parent $server) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'service.log') -RedirectStandardError (Join-Path $state 'service-error.log')
  [pscustomobject]@{pid=$process.Id;server=$server;node=$node}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $state 'process.json') -Encoding UTF8
  $healthy=$false
  for($attempt=0;$attempt -lt 30;$attempt++){try{$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$config.port+'/health') -TimeoutSec 2;if($health.version -eq '0.1.0-alpha.1'){$healthy=$true;break}}catch{};Start-Sleep -Milliseconds 200}
  if(-not $healthy){throw 'The alpha notebook did not start. Its saved records are unchanged.'}
}
if(-not $NoBrowser){Start-Process ('http://127.0.0.1:'+$config.port+'/') -WindowStyle Hidden}

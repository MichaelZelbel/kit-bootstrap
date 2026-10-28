param([switch]$NoBrowser,[switch]$Wired,[switch]$PassThru,[int]$WaitSeconds=900)
# -Wired: the setup has just connected the assistant (ensure-hermes.ps1), so it is not done a
#   second time here. Until 21 October 2026 an update did it twice, minutes apart.
# -PassThru: says $true when the notebook answered, $false when it is still starting.
# -WaitSeconds: how long a notebook that is still starting is waited for.
$ErrorActionPreference='Stop'
$env:GODSPEED_ORIGINAL_RUNTIME='on'
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$state=Get-GodspeedStateFolder
$config=Get-Content -LiteralPath (Join-Path $state 'installation.json') -Raw|ConvertFrom-Json
if($config.channel -ne 'full-alpha'){throw 'The notebook record on this PC is not one this setup made, so it was not started.'}
$node=Join-Path $config.appRoot 'payload\runtime\node.exe'
$server=Join-Path $config.appRoot 'payload\kit\notebook\scripts\supervise.mjs'
$busy='Another notebook already uses port '+$config.port+' on this PC, so this one was not started.'
$expectedInstance=(& $node -e "const c=require('node:crypto'),p=require('node:path');process.stdout.write(c.createHash('sha256').update(p.resolve(process.argv[1])).digest('hex').slice(0,24))" $config.workspace)
try{$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$config.port+'/health') -TimeoutSec 2;if($health.instance -eq $expectedInstance){$running=$true}else{throw $busy}}catch{if($_.Exception.Message -eq $busy){throw};$running=$false}
# THE NOTEBOOK THAT IS STARTING ALREADY (26 October 2026). The Startup entry starts it at sign-in,
# and on one laptop it answered only eight minutes later. Until then a second start (the Start
# menu's "Open my notebook", which runs this) launched a second supervisor and a second notebook
# beside the first. The supervisor this script started (process.json) or the one that holds the
# workspace (its supervisor.lock) is waited for instead, when it is still alive. The command line
# names this installation's supervise.mjs, so a process that reused the number is never taken for it.
function Get-RunningSupervisor{
  $ids=@()
  try{$ids+=[int](Get-Content -LiteralPath (Join-Path $state 'process.json') -Raw -ErrorAction Stop|ConvertFrom-Json).pid}catch{}
  try{$ids+=[int](Get-Content -LiteralPath (Join-Path $config.workspace '.godspeed\supervisor.lock') -Raw -ErrorAction Stop|ConvertFrom-Json).pid}catch{}
  foreach($id in @($ids|Where-Object {$_ -gt 0}|Select-Object -Unique)){
    $found=Get-CimInstance Win32_Process -Filter ('ProcessId='+$id) -ErrorAction SilentlyContinue
    if($found -and $found.ExecutablePath -and [IO.Path]::GetFileName($found.ExecutablePath) -eq 'node.exe' -and $found.CommandLine -and $found.CommandLine.Contains($server)){
      try{return Get-Process -Id $id -ErrorAction Stop}catch{}
    }
  }
  return $null
}
$answered=$true
if(-not $running){
  # One start at a time for this workspace: two that begin in the same moment (sign-in and a click)
  # would otherwise both find nothing running and both start one.
  $startLock=New-Object Threading.Mutex($false,('Local\GodspeedMissionControlNotebookStart-'+$expectedInstance))
  $owned=$false
  try{$owned=$startLock.WaitOne([Math]::Max(1,$WaitSeconds)*1000)}catch [Threading.AbandonedMutexException]{$owned=$true}
  try{
  $process=$null
  if($owned){$process=Get-RunningSupervisor}
  if($owned -and -not $process){
  $env:GODSPEED_WORKSPACE=$config.workspace;$env:GODSPEED_MEDIA_ROOT=$config.media;$env:GODSPEED_PORT=[string]$config.port;$env:GODSPEED_BIND='127.0.0.1'
  $env:GODSPEED_ASSISTANT_CONFIG=Join-Path $state 'assistant.json'
  if(-not $Wired -and (Test-Path -LiteralPath $env:GODSPEED_ASSISTANT_CONFIG)){$assistant=Get-Content -LiteralPath $env:GODSPEED_ASSISTANT_CONFIG -Raw|ConvertFrom-Json;if($assistant.verified){& $node (Join-Path $config.appRoot 'payload\kit\notebook\scripts\wire-assistant.mjs') $assistant.home;if($LASTEXITCODE -ne 0){throw 'Personal assistant workflow setup failed.'}}}
  $managedGit=Join-Path $state 'hermes-runtime\git\cmd';if(Test-Path -LiteralPath (Join-Path $managedGit 'git.exe')){$env:PATH=$managedGit+';'+$env:PATH}
  $providerFile=Join-Path $state 'provider.json'
  if(Test-Path -LiteralPath $providerFile){$provider=Get-Content -LiteralPath $providerFile -Raw|ConvertFrom-Json;$env:GODSPEED_MODEL_URL=$provider.url;$env:GODSPEED_MODEL_KEY=$provider.key;$env:GODSPEED_MODEL=$provider.model}
  $process=Start-Process -FilePath $node -ArgumentList @('"'+$server+'"') -WorkingDirectory (Split-Path -Parent $server) -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $state 'service.log') -RedirectStandardError (Join-Path $state 'service-error.log')
  [pscustomobject]@{pid=$process.Id;server=$server;node=$node}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $state 'process.json') -Encoding UTF8
  }
  }finally{if($owned){$startLock.ReleaseMutex()};$startLock.Dispose()}
  # WAITED FOR AS LONG AS IT IS STARTING (21 October 2026). A notebook reads every file of its
  # mission control before it answers: on one PC 2 minutes 15 seconds after an update. Until then
  # this waited about a minute, said "The notebook did not start" and the update counted as failed,
  # while the notebook came up a minute later. Now it waits while the supervisor it started (or
  # found starting) is alive and has not given up (its .godspeed\supervisor.json), for up to
  # WaitSeconds. Only a supervisor that ended or gave up is a notebook that did not start; one
  # still starting when the wait is over is said as such, and it opens by itself.
  $supervisorFile=Join-Path $config.workspace '.godspeed\supervisor.json'
  $started=Get-Date;$said=$started;$healthy=$false;$gaveUp=$null
  while($true){
    try{$health=Invoke-RestMethod -Uri ('http://127.0.0.1:'+$config.port+'/health') -TimeoutSec 5;if($health.instance -eq $expectedInstance){$healthy=$true;break}}catch{}
    if(-not $process -or $process.HasExited){break}
    try{$supervisor=Get-Content -LiteralPath $supervisorFile -Raw -ErrorAction Stop|ConvertFrom-Json;if([int]$supervisor.pid -eq $process.Id -and $supervisor.state -eq 'needs_review'){$gaveUp=[string]$supervisor.reason;break}}catch{}
    if(((Get-Date)-$started).TotalSeconds -ge $WaitSeconds){break}
    if(((Get-Date)-$said).TotalSeconds -ge 60){Write-Host ('  The notebook is still starting ('+[int]((Get-Date)-$started).TotalMinutes+' min so far). The first start after an update can take a few minutes.');$said=Get-Date}
    Start-Sleep -Seconds 1
  }
  if(-not $healthy){
    if($process.HasExited -or $gaveUp){throw 'The notebook did not start. Your notes are unchanged.'}
    Write-Host '  The notebook is still starting. It opens by itself when it is ready, and your notes are unchanged.'
    $answered=$false
  }
}
if($answered -and -not $NoBrowser){Start-Process ('http://127.0.0.1:'+$config.port+'/') -WindowStyle Hidden}
if($PassThru){$answered}

$ErrorActionPreference='Stop'
# How start-full-alpha.ps1 waits for the notebook (21 October 2026). It waited about a minute; a
# notebook that needed 2 minutes 15 seconds after an update was reported as "did not start", the
# update counted as failed, and the notebook came up a minute later. Now it waits while the
# process it started is alive and its supervisor has not given up. Each case runs the real script
# in its own Windows PowerShell with LOCALAPPDATA pointed at a fixture, against a stand-in for
# supervise.mjs, so nothing of this PC's own notebook is read or touched.
$taskNode=(Get-Command node -ErrorAction Stop).Source
$taskFixture=Join-Path $env:TEMP ('Godspeed-start-wait-'+[guid]::NewGuid().ToString('N'))
$taskPs=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
function Get-TaskPort{$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$l.Start();$p=$l.LocalEndpoint.Port;$l.Stop();return $p}
function Invoke-TaskStart([string]$Mode,[string[]]$Arguments){
 $local=Join-Path $taskFixture ('local-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 $state=Join-Path $local 'Godspeed Mission Control Full Alpha State'
 $workspace=Join-Path $local 'mission control'
 New-Item -ItemType Directory -Force -Path $state,(Join-Path $workspace '.godspeed')|Out-Null
 $config=[pscustomobject]@{channel='full-alpha';workspace=$workspace;media=(Join-Path $state 'media');port=(Get-TaskPort);appRoot=$taskApp;dataFormat=1}
 $config|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $state 'installation.json') -Encoding UTF8
 Set-Content -LiteralPath (Join-Path $workspace '.godspeed\stand-in-mode.txt') -Value $Mode -Encoding ASCII
 # The script's words go to a file, not a pipe: the notebook it starts would inherit a pipe and hold
 # it open, and the wait for its end would never end (the setup itself reads no pipe).
 $log=Join-Path $local 'start.log'
 $command="try{& '"+(Join-Path $PSScriptRoot 'start-full-alpha.ps1')+"' "+($Arguments -join ' ')+" *> '"+$log+"'}catch{Add-Content -LiteralPath '"+$log+"' -Value `$_.Exception.Message;exit 1};exit 0"
 $previous=$env:LOCALAPPDATA
 try{
  $env:LOCALAPPDATA=$local
  $at=Get-Date
  $child=Start-Process -FilePath $taskPs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',('"'+$command.Replace('"','\"')+'"')) -WindowStyle Hidden -PassThru
  if(-not $child.WaitForExit(120000)){Stop-Process -Id $child.Id -Force;throw 'start-full-alpha.ps1 did not return within two minutes'}
  $code=$child.ExitCode;$seconds=((Get-Date)-$at).TotalSeconds
 }finally{$env:LOCALAPPDATA=$previous}
 # The stand-in stays running where the script left it; it goes now.
 try{$saved=Get-Content -LiteralPath (Join-Path $state 'process.json') -Raw|ConvertFrom-Json;Stop-Process -Id ([int]$saved.pid) -Force -ErrorAction SilentlyContinue}catch{}
 $out=if(Test-Path -LiteralPath $log){(Get-Content -LiteralPath $log|ForEach-Object {([string]$_).Trim()}) -join "`n"}else{''}
 return [pscustomobject]@{Code=$code;Output=$out;Seconds=$seconds}
}
try{
 # The app folder: this PC's node.exe and a stand-in supervisor, which answers /health as the
 # notebook of its workspace does, after a delay, or ends, or gives up, or never answers.
 $taskApp=Join-Path $taskFixture 'app'
 New-Item -ItemType Directory -Force -Path (Join-Path $taskApp 'payload\runtime'),(Join-Path $taskApp 'payload\kit\notebook\scripts')|Out-Null
 Copy-Item -LiteralPath $taskNode -Destination (Join-Path $taskApp 'payload\runtime\node.exe')
 Set-Content -LiteralPath (Join-Path $taskApp 'payload\kit\notebook\scripts\supervise.mjs') -Encoding ASCII -Value @'
import fs from 'node:fs';import path from 'node:path';import http from 'node:http';import crypto from 'node:crypto';
const root=path.resolve(process.env.GODSPEED_WORKSPACE),state=path.join(root,'.godspeed'),mode=fs.readFileSync(path.join(state,'stand-in-mode.txt'),'utf8').trim();
const instance=crypto.createHash('sha256').update(root).digest('hex').slice(0,24);
const status=value=>fs.writeFileSync(path.join(state,'supervisor.json'),JSON.stringify({pid:process.pid,...value}));
status({state:'starting'});
if(mode==='exit')process.exit(3);
if(mode==='giveup'){setTimeout(()=>status({state:'needs_review',reason:'Five automatic restarts failed'}),1500);setInterval(()=>{},1000);}
else if(mode==='never')setInterval(()=>{},1000);
else setTimeout(()=>{http.createServer((q,r)=>{r.setHeader('content-type','application/json');r.end(JSON.stringify({ok:true,format:1,version:'stand-in',instance}));}).listen(Number(process.env.GODSPEED_PORT),'127.0.0.1');status({state:'healthy'});},Number(mode.split(':')[1]||0));
'@

 # A notebook that needs longer than the old wait (about ten seconds when nothing listens yet).
 $slow=Invoke-TaskStart 'slow:14000' @('-NoBrowser','-PassThru')
 if($slow.Code -ne 0 -or $slow.Output -notmatch '(^|\n)True$'){throw ('A slow start was not waited for: exit '+$slow.Code+': '+$slow.Output)}
 if($slow.Seconds -lt 13){throw ('A slow start answered sooner than it could: '+$slow.Seconds)}
 Write-Output ('A notebook that answers after 14 seconds is waited for ('+[int]$slow.Seconds+' s) and counts as started.')

 # A notebook process that ends is said at once, as before.
 $ended=Invoke-TaskStart 'exit' @('-NoBrowser','-PassThru')
 if($ended.Code -eq 0 -or $ended.Output -notmatch 'The notebook did not start'){throw ('An ended notebook was not reported: '+$ended.Output)}
 if($ended.Seconds -gt 30){throw ('An ended notebook was waited for: '+$ended.Seconds)}
 Write-Output ('A notebook process that ends is reported at once ('+[int]$ended.Seconds+' s).')

 # A supervisor that gave up is a notebook that did not start.
 $gaveUp=Invoke-TaskStart 'giveup' @('-NoBrowser','-PassThru')
 if($gaveUp.Code -eq 0 -or $gaveUp.Output -notmatch 'The notebook did not start'){throw ('A supervisor that gave up was not reported: '+$gaveUp.Output)}
 if($gaveUp.Seconds -gt 30){throw ('A supervisor that gave up was waited for: '+$gaveUp.Seconds)}
 Write-Output ('A supervisor that gives up is reported ('+[int]$gaveUp.Seconds+' s).')

 # Still starting when the wait is over: never "did not start", and it says so.
 $still=Invoke-TaskStart 'never' @('-NoBrowser','-PassThru','-WaitSeconds','6')
 if($still.Code -ne 0 -or $still.Output -match 'did not start' -or $still.Output -notmatch 'still starting' -or $still.Output -notmatch '(^|\n)False$'){throw ('A notebook still starting was reported as: exit '+$still.Code+': '+$still.Output)}
 Write-Output 'A notebook still starting after the wait is said to be starting, not to have failed.'
} finally {
 if([IO.Path]::GetFullPath($taskFixture).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $taskFixture)){
  Start-Sleep -Milliseconds 300
  Remove-Item -LiteralPath $taskFixture -Recurse -Force -ErrorAction SilentlyContinue
 }
}
# The setup connects the assistant once (ensure-hermes-full-alpha.ps1), and removes older copies
# only when the notebook answered.
$taskSetup=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'setup-full-alpha.ps1') -Raw
if(-not $taskSetup.Contains("start-full-alpha.ps1') -NoBrowser -Wired:(-not `$SkipHermes) -PassThru")){throw 'The setup connects the assistant a second time when it starts the notebook'}
Write-Output 'The setup connects the assistant once.'

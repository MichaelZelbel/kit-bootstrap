$ErrorActionPreference='Stop'
# What the Start menu's "Open my notebook" does (26 October 2026). It was the notebook's address
# alone, so it showed "This site can't be reached" while the notebook was not running: on one laptop
# for eight minutes after the computer started. Each case runs the real open-notebook.ps1 (and the
# real start-full-alpha.ps1 beside it) in its own Windows PowerShell with LOCALAPPDATA pointed at a
# fixture, against a stand-in for supervise.mjs, so nothing of this PC's own notebook is read or
# touched. -Report makes the script write what it would show or open, instead of showing it.
$taskNode=(Get-Command node -ErrorAction Stop).Source
$taskFixture=Join-Path $env:TEMP ('Godspeed-open-notebook-'+[guid]::NewGuid().ToString('N'))
$taskPs=Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:failures=0
function Want([string]$What,[bool]$Ok,[string]$Seen){
 if($Ok){Write-Output ('ok    '+$What)}else{Write-Output ('FAIL  '+$What+': '+$Seen);$script:failures++}
}
function Get-TaskPort{$l=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0);$l.Start();$p=$l.LocalEndpoint.Port;$l.Stop();return $p}
# A PC of its own: the notebook's record, its mission control and the stand-in's mode.
function New-TaskPc([string]$Mode,[switch]$NotInstalled){
 $local=Join-Path $taskFixture ('local-'+[guid]::NewGuid().ToString('N').Substring(0,8))
 $state=Join-Path $local 'Godspeed Mission Control Full Alpha State'
 $workspace=Join-Path $local 'mission control'
 New-Item -ItemType Directory -Force -Path $state,(Join-Path $workspace '.godspeed')|Out-Null
 $port=Get-TaskPort
 if(-not $NotInstalled){
  [pscustomobject]@{channel='full-alpha';workspace=$workspace;media=(Join-Path $state 'media');port=$port;appRoot=$taskApp;dataFormat=1}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $state 'installation.json') -Encoding UTF8
 }
 Set-Content -LiteralPath (Join-Path $workspace '.godspeed\stand-in-mode.txt') -Value $Mode -Encoding ASCII
 return [pscustomobject]@{Local=$local;State=$state;Workspace=$workspace;Port=$port;Address=('http://127.0.0.1:'+$port+'/')}
}
# One script of the windows folder, in a hidden Windows PowerShell of its own, as the Start menu
# entry runs it. Its words go to its own hidden console, never to a pipe this test holds.
function Start-Task($Pc,[string]$Script,[string[]]$Arguments){
 $previous=$env:LOCALAPPDATA
 try{
  $env:LOCALAPPDATA=$Pc.Local
  $child=Start-Process -FilePath $taskPs -ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $PSScriptRoot $Script)+'"'))+$Arguments) -WindowStyle Hidden -PassThru
  [void]$child.Handle
  return $child
 }finally{$env:LOCALAPPDATA=$previous}
}
function Wait-Task($Child,[int]$Seconds=120){
 if(-not $Child.WaitForExit($Seconds*1000)){Stop-Process -Id $Child.Id -Force;throw ('A script did not return within '+$Seconds+' seconds')}
 return $Child.ExitCode
}
function Open-Notebook($Pc,[string]$Name,[string[]]$More=@()){
 $report=Join-Path $Pc.Local ($Name+'.txt')
 $at=Get-Date
 $code=Wait-Task (Start-Task $Pc 'open-notebook.ps1' (@('-Report',('"'+$report+'"'))+$More))
 $lines=if(Test-Path -LiteralPath $report){@(Get-Content -LiteralPath $report)}else{@()}
 return [pscustomobject]@{Code=$code;Lines=$lines;Text=($lines -join ' | ');Seconds=((Get-Date)-$at).TotalSeconds}
}
function Get-Starts($Pc){$f=Join-Path $Pc.Workspace '.godspeed\starts.txt';if(Test-Path -LiteralPath $f){@(Get-Content -LiteralPath $f|Where-Object {$_})}else{@()}}
function Wait-Starts($Pc,[int]$Count){$until=(Get-Date).AddSeconds(60);while((Get-Starts $Pc).Count -lt $Count -and (Get-Date) -lt $until){Start-Sleep -Milliseconds 200};if((Get-Starts $Pc).Count -lt $Count){throw 'The stand-in notebook was never started'}}
function Stop-Pc($Pc){foreach($id in (Get-Starts $Pc)){Stop-Process -Id ([int]$id) -Force -ErrorAction SilentlyContinue}}
function Test-Opened($Result,$Pc){return @($Result.Lines|Where-Object {$_ -eq ('opened: '+$Pc.Address)}).Count -eq 1}
function Test-Said($Result,[string]$Words){return [bool]($Result.Lines|Where-Object {$_.StartsWith('said: ') -and $_.Contains($Words)})}

$pcs=@()
try{
 # The app folder: this PC's node.exe and a stand-in supervisor that notes every start, holds the
 # workspace as the real one does (supervisor.lock), and answers /health as the notebook of its
 # workspace does: after a delay, or never, or it ends at once.
 $taskApp=Join-Path $taskFixture 'app'
 New-Item -ItemType Directory -Force -Path (Join-Path $taskApp 'payload\runtime'),(Join-Path $taskApp 'payload\kit\notebook\scripts')|Out-Null
 Copy-Item -LiteralPath $taskNode -Destination (Join-Path $taskApp 'payload\runtime\node.exe')
 Set-Content -LiteralPath (Join-Path $taskApp 'payload\kit\notebook\scripts\supervise.mjs') -Encoding ASCII -Value @'
import fs from 'node:fs';import path from 'node:path';import http from 'node:http';import crypto from 'node:crypto';
const root=path.resolve(process.env.GODSPEED_WORKSPACE),state=path.join(root,'.godspeed'),mode=fs.readFileSync(path.join(state,'stand-in-mode.txt'),'utf8').trim();
const instance=crypto.createHash('sha256').update(root).digest('hex').slice(0,24);
fs.appendFileSync(path.join(state,'starts.txt'),process.pid+'\n');
fs.writeFileSync(path.join(state,'supervisor.lock'),JSON.stringify({pid:process.pid}));
const status=value=>fs.writeFileSync(path.join(state,'supervisor.json'),JSON.stringify({pid:process.pid,...value}));
status({state:'starting'});
if(mode==='exit')process.exit(3);
else if(mode==='never')setInterval(()=>{},1000);
else setTimeout(()=>{http.createServer((q,r)=>{r.setHeader('content-type','application/json');r.end(JSON.stringify({ok:true,format:1,version:'stand-in',instance}));}).listen(Number(process.env.GODSPEED_PORT),'127.0.0.1');status({state:'healthy'});},Number(mode.split(':')[1]||0));
'@

 # 1. Running: it opens at once, and nothing is started.
 $pc=New-TaskPc 'slow:0';$pcs+=$pc
 [void](Wait-Task (Start-Task $pc 'start-full-alpha.ps1' @('-NoBrowser')))
 $r=Open-Notebook $pc 'running'
 Want 'a running notebook opens at once' ((Test-Opened $r $pc) -and $r.Code -eq 0 -and $r.Seconds -lt 20) ($r.Text+' after '+[int]$r.Seconds+' s')
 Want 'a running notebook is not started again, and no note is shown' ((Get-Starts $pc).Count -eq 1 -and -not (Test-Said $r '')) ('starts '+(Get-Starts $pc).Count+': '+$r.Text)
 Stop-Pc $pc

 # 2. Starting: the Startup entry started it at sign-in and it does not answer yet. Waited for,
 #    opened when it answers, and never a second notebook beside it.
 $pc=New-TaskPc 'slow:15000';$pcs+=$pc
 $signIn=Start-Task $pc 'start-full-alpha.ps1' @('-NoBrowser')
 Wait-Starts $pc 1
 $r=Open-Notebook $pc 'starting'
 [void](Wait-Task $signIn)
 Want 'a notebook still starting is waited for, then opened' ((Test-Opened $r $pc) -and $r.Code -eq 0 -and $r.Seconds -ge 8) ($r.Text+' after '+[int]$r.Seconds+' s')
 Want 'it says the notebook is starting while it waits' (Test-Said $r 'Your notebook is starting.') $r.Text
 Want 'a notebook still starting is not started a second time' ((Get-Starts $pc).Count -eq 1) ('started '+(Get-Starts $pc).Count+' times')
 Stop-Pc $pc

 # 3. Stopped: started, then opened. A second click while the first waits opens no second tab and
 #    starts nothing.
 $pc=New-TaskPc 'slow:12000';$pcs+=$pc
 $firstReport=Join-Path $pc.Local 'first.txt'
 $first=Start-Task $pc 'open-notebook.ps1' @('-Report',('"'+$firstReport+'"'))
 Wait-Starts $pc 1
 $second=Open-Notebook $pc 'second'
 $code=Wait-Task $first
 $r=[pscustomobject]@{Code=$code;Lines=@(Get-Content -LiteralPath $firstReport);Text=(@(Get-Content -LiteralPath $firstReport) -join ' | ')}
 Want 'a stopped notebook is started, then opened' ((Test-Opened $r $pc) -and $r.Code -eq 0 -and (Test-Said $r 'Your notebook is starting.')) $r.Text
 Want 'a second click meanwhile says it is starting and opens nothing' ((Test-Said $second 'Your notebook is starting.') -and -not ($second.Text.Contains('opened:')) -and $second.Code -eq 0) $second.Text
 Want 'the two clicks started one notebook' ((Get-Starts $pc).Count -eq 1) ('started '+(Get-Starts $pc).Count+' times')
 Stop-Pc $pc

 # 4. Cannot start: a plain message that says so and what to do, and nothing opened.
 $pc=New-TaskPc 'exit';$pcs+=$pc
 $r=Open-Notebook $pc 'cannot'
 Want 'a notebook that cannot start is said in plain words, with what to do' ((Test-Said $r 'The notebook did not start. Your notes are unchanged.') -and (Test-Said $r 'Restart the computer, then choose Open my notebook again.') -and $r.Code -ne 0) $r.Text
 Want 'and nothing is opened' (-not $r.Text.Contains('opened:')) $r.Text

 # 5. Still starting when the wait is over: said as such, never "did not start", nothing opened.
 $pc=New-TaskPc 'never';$pcs+=$pc
 $r=Open-Notebook $pc 'still' @('-WaitSeconds','5')
 Want 'a notebook still starting after the wait is said to be starting, not failed' ((Test-Said $r 'Your notebook is still starting and does not answer yet.') -and -not $r.Text.Contains('did not start') -and -not $r.Text.Contains('opened:')) $r.Text
 Stop-Pc $pc

 # 6. Another notebook holds the address: said, and this one is not started.
 $pc=New-TaskPc 'slow:0';$pcs+=$pc
 $other=Start-Process -FilePath $taskNode -ArgumentList @('-e',('"require(''http'').createServer((q,r)=>r.end(JSON.stringify({ok:true,instance:''someone-else''}))).listen('+$pc.Port+',''127.0.0.1'')"')) -WindowStyle Hidden -PassThru
 try{
  $until=(Get-Date).AddSeconds(20);while((Get-Date) -lt $until){try{[void](Invoke-RestMethod -Uri ($pc.Address+'health') -TimeoutSec 2);break}catch{Start-Sleep -Milliseconds 200}}
  $r=Open-Notebook $pc 'busy'
  Want 'another notebook on its address is said, and this one is not started' ((Test-Said $r ('Another notebook already uses port '+$pc.Port)) -and (Get-Starts $pc).Count -eq 0 -and -not $r.Text.Contains('opened:')) ($r.Text+'; starts '+(Get-Starts $pc).Count)
 }finally{Stop-Process -Id $other.Id -Force -ErrorAction SilentlyContinue}

 # 7. No notebook set up on this PC (the record is gone): said, nothing else.
 $pc=New-TaskPc 'slow:0' -NotInstalled;$pcs+=$pc
 $r=Open-Notebook $pc 'none'
 Want 'a PC without the notebook is told to run the setup again' ((Test-Said $r 'Your notebook is not set up on this PC. Run GodspeedSetup.exe again.') -and $r.Code -ne 0 -and (Get-Starts $pc).Count -eq 0) $r.Text
} finally {
 foreach($pc in $pcs){Stop-Pc $pc}
 if([IO.Path]::GetFullPath($taskFixture).StartsWith([IO.Path]::GetFullPath($env:TEMP)+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $taskFixture)){
  Start-Sleep -Milliseconds 500
  Remove-Item -LiteralPath $taskFixture -Recurse -Force -ErrorAction SilentlyContinue
 }
}
if($script:failures){Write-Output ([string]$script:failures+' failed');exit 1}
Write-Output 'ALL PASS'

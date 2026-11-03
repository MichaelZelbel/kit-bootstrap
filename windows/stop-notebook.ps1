param([switch]$Uninstall)
# Started from PowerShell 7, Windows PowerShell 5.1 inherits its module path and cannot find Get-FileHash: use its own.
if($PSVersionTable.PSEdition -eq 'Desktop' -and $env:PSModulePath -match '(?i)[\\/]PowerShell[\\/](7[^\\/;]*|Modules)([\\/;]|$)'){$env:PSModulePath=(@((Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'),$(if([Environment]::GetEnvironmentVariable('PSModulePath','Machine')){[Environment]::GetEnvironmentVariable('PSModulePath','Machine')}else{(Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules')+';'+(Join-Path $PSHOME 'Modules')}))|Where-Object{$_}) -join ';'}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'godspeed-folders.ps1')
$state=Get-GodspeedStateFolder
$pidFile=Join-Path $state 'process.json'
if(Test-Path -LiteralPath $pidFile){
  # A damaged record names no process; the installer must not be refused over it.
  try{$saved=Get-Content -LiteralPath $pidFile -Raw|ConvertFrom-Json;$savedPid=[int]$saved.pid}catch{$saved=$null}
  if(-not $saved -or $savedPid -le 0){Remove-Item -LiteralPath $pidFile;$saved=$null}
}
if($saved){
  $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$saved.pid) -ErrorAction SilentlyContinue
  # A notebook started with administrator rights hides its path and command line from this
  # window. Until 6 October 2026 that read as "not ours": nothing was stopped, the record was
  # deleted and the script reported success, so an update then failed on locked files.
  if($process -and -not $process.ExecutablePath -and (Get-Process -Id ([int]$saved.pid) -ErrorAction SilentlyContinue)){
    throw 'The notebook is running with administrator rights, so it can only be stopped from an administrator window or by restarting the computer.'
  }
  if($process -and $process.ExecutablePath -eq $saved.node -and $process.CommandLine.Contains($saved.server)){
    # Whether anything still runs decides, not taskkill's exit code. taskkill /T reports an error
    # when a process of the tree ends while it works through it, and until 7 October 2026 that
    # read as "did not stop" with every process already gone: an update on the maintainer's laptop was
    # cancelled that way, with the notebook stopped and nothing installed. A process of this
    # notebook's own Node that the tree missed would keep files locked, so it goes too.
    $ours={@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue|Where-Object {$_.ExecutablePath -eq $saved.node})}
    & taskkill.exe /PID ([string]$saved.pid) /T /F|Out-Null
    foreach($left in (& $ours)){& taskkill.exe /PID ([string]$left.ProcessId) /T /F|Out-Null}
    $until=(Get-Date).AddSeconds(15)
    while((& $ours).Count -and (Get-Date) -lt $until){Start-Sleep -Milliseconds 250}
    if((& $ours).Count){throw 'The notebook did not stop. Restart the computer and try again.'}
  }
  Remove-Item -LiteralPath $pidFile
}
if($Uninstall){
  foreach($name in 'Godspeed Mission Control.lnk','Godspeed Mission Control Full Alpha.lnk'){
    $shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) $name
    if(Test-Path -LiteralPath $shortcut){Remove-Item -LiteralPath $shortcut}
  }
}
# Knowledge, media, settings and backups are deliberately retained for recovery.
# A taskkill above that answered with an error must not become this script's exit code.
exit 0

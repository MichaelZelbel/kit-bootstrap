param([switch]$Uninstall)
$ErrorActionPreference='Stop'
$state=Join-Path $env:LOCALAPPDATA 'Godspeed Mission Control Full Alpha State'
$pidFile=Join-Path $state 'process.json'
if(Test-Path -LiteralPath $pidFile){
  $saved=Get-Content -LiteralPath $pidFile -Raw|ConvertFrom-Json
  $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+[int]$saved.pid) -ErrorAction SilentlyContinue
  if($process -and $process.ExecutablePath -eq $saved.node -and $process.CommandLine.Contains($saved.server)){& taskkill.exe /PID ([string]$saved.pid) /T /F|Out-Null;if($LASTEXITCODE -ne 0){throw 'The isolated notebook process tree did not stop.'}}
  Remove-Item -LiteralPath $pidFile
}
if($Uninstall){
  $shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'Godspeed Mission Control Full Alpha.lnk'
  if(Test-Path -LiteralPath $shortcut){Remove-Item -LiteralPath $shortcut}
}
# Knowledge, media, settings and backups are deliberately retained for recovery.
